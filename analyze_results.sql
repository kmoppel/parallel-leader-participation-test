-- some rough numbers to assure myself that i'm not on some wild goose chase
with q as (
	select
	  (select avg(mean_exec_time)::numeric(9, 2) from pgss_results where parallel_leader_participation = 'on') as plp_on,
	  (select avg(mean_exec_time)::numeric(9, 2) from pgss_results where parallel_leader_participation = 'off') as plp_off
)
select 100.0 * ((q.plp_off - q.plp_on) / q.plp_on) as diff from q;


-- summary per scale / partitions
SELECT
    scale,
    partitions,
    avg(mean_exec_time / 1000.0)::int mean_exec_time_s,
    avg(pct)::numeric(7, 1) AS no_leader_participation_speedup_pct
FROM (
    SELECT
        *,
        lag AS mean_exec_time_lag,
        (100.0 * ((mean_exec_time - lag) / lag))::numeric(7, 1) pct
    FROM (
        SELECT
            *,
            lag(mean_exec_time) OVER (PARTITION BY hostname, scale, duration, clients, partitions, max_parallel_workers_per_gather ORDER BY parallel_leader_participation DESC)
        FROM pgss_results) ORDER BY hostname,
    scale,
    clients,
    partitions,
    max_parallel_workers_per_gather::int,
    parallel_leader_participation DESC) x
GROUP BY
    ROLLUP (scale, partitions)
ORDER BY
    scale,
    partitions;


-- a more detailed summary
SELECT
    *
FROM (
    SELECT
        scale,
        partitions,
        CASE WHEN random_page_cost::float < 2 THEN
            'fast'
        ELSE
            'slow'
        END AS storage_latency, -- random_page_cost set by pg-spot-operator automatically according to disk type
        avg(mean_exec_time / 1000.0)::int mean_exec_time_s,
        avg(pct)::numeric(7, 1) AS no_participation_speedup_pct
    FROM (
        SELECT
            *,
            lag AS mean_exec_time_lag,
            (100.0 * ((mean_exec_time - lag) / lag))::numeric(7, 1) pct
        FROM (
            SELECT
                *,
                lag(mean_exec_time) OVER (PARTITION BY hostname, scale, duration, random_page_cost, clients, partitions, max_parallel_workers_per_gather ORDER BY parallel_leader_participation DESC)
            FROM pgss_results
            -- where scale = 5000
            -- and partitions > 0
) ORDER BY hostname,
        scale,
        clients,
        partitions,
        max_parallel_workers_per_gather::int,
        parallel_leader_participation DESC) x
GROUP BY ROLLUP (scale, partitions, random_page_cost) ORDER BY scale, partitions, random_page_cost) y;


-- target use case: partitions + more data
with q as (
	select
	  (select avg(mean_exec_time)::numeric(9, 2) from pgss_results where parallel_leader_participation = 'on' and partitions > 0 and scale = 5000) as plp_on,
	  (select avg(mean_exec_time)::numeric(9, 2) from pgss_results where parallel_leader_participation = 'off' and partitions > 0 and scale = 5000) as plp_off
)
select 100.0 * ((q.plp_off - q.plp_on) / q.plp_on) as diff from q;


-- max win conditions
SELECT
    *
FROM (
    SELECT
        hostname,
        scale,
        partitions,
        CASE WHEN random_page_cost::float < 2 THEN
            'fast'
        ELSE
            'slow'
        END AS storage_latency, -- random_page_cost set by pg-spot-operator automatically according to disk type
        avg(mean_exec_time / 1000.0)::int mean_exec_time_s,
        avg(pct)::numeric(7, 1) AS no_leader_participation_speedup_pct
    FROM (
        SELECT
            *,
            lag AS mean_exec_time_lag,
            (100.0 * ((mean_exec_time - lag) / lag))::numeric(7, 1) pct
        FROM (
            SELECT
                *,
                lag(mean_exec_time) OVER (PARTITION BY hostname, scale, duration, random_page_cost, clients, partitions, max_parallel_workers_per_gather ORDER BY parallel_leader_participation DESC)
            FROM pgss_results) x ORDER BY hostname,
        scale,
        clients,
        partitions,
        max_parallel_workers_per_gather::int,
        parallel_leader_participation DESC) y
GROUP BY 1,
2,
3,
4) z
WHERE
    no_leader_participation_speedup_pct < 0
ORDER BY
    no_leader_participation_speedup_pct nulls LAST
LIMIT 5;
