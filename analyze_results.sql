-- some rough numbers to assure myself that i'm not on some wild goose chase
with q as (
	select
	  (select avg(mean_exec_time)::numeric(9, 2) from pgss_results where parallel_leader_participation = 'on') as plp_on,
	  (select avg(mean_exec_time)::numeric(9, 2) from pgss_results where parallel_leader_participation = 'off') as plp_off
)
select 100.0 * ((q.plp_off - q.plp_on) / q.plp_on) as diff from q;
-- -3.538868875728028982000



-- summary
select *, (avg(no_participation_speedup_pct) over())::numeric(7,1) as avg_no_participation_speedup_pct from (
select
  scale,
  partitions,
  case when random_page_cost::float < 2 then 'fast' else 'slow' end as storage_latency, -- random_page_cost set by pg-spot-operator automatically according to disk type
  avg(mean_exec_time / 1000.0)::int mean_exec_time_ms, avg(pct)::numeric(7,1) as no_participation_speedup_pct
from (
select
  *,
  lag as mean_exec_time_lag,
  (100.0 * ((mean_exec_time - lag) / lag))::numeric(7,1) pct
from (
select
  *,
  lag(mean_exec_time) over(partition by hostname, scale, duration, random_page_cost, clients, partitions, max_parallel_workers_per_gather order by parallel_leader_participation desc)
from
  pgss_results
-- where scale = 5000
-- and partitions > 0
)
order by
  hostname, scale, clients, partitions, max_parallel_workers_per_gather::int, parallel_leader_participation desc
) x
group by (scale, partitions, random_page_cost)
order by scale, partitions, random_page_cost
) y
;
/*
scale|partitions|storage_latency|mean_exec_time_ms|no_participation_speedup_pct|avg_no_participation_speedup_pct|
-----+----------+---------------+-----------------+----------------------------+--------------------------------+
 5000|         0|fast           |               60|                        -0.3|                            -2.7|
 5000|         0|slow           |              394|                        -1.1|                            -2.7|
 5000|         8|fast           |               55|                        -2.6|                            -2.7|
 5000|         8|slow           |              336|                        -6.9|                            -2.7|
*/


-- target use case: partitions + more data
with q as (
	select
	  (select avg(mean_exec_time)::numeric(9, 2) from pgss_results where parallel_leader_participation = 'on' and partitions > 0 and scale = 5000) as plp_on,
	  (select avg(mean_exec_time)::numeric(9, 2) from pgss_results where parallel_leader_participation = 'off' and partitions > 0 and scale = 5000) as plp_off
)
select 100.0 * ((q.plp_off - q.plp_on) / q.plp_on) as diff from q;

-- -7.214798181364803285000