#!/bin/bash

set -e

# Assumes runs "postgres" user + pg_stat_statements installed
CONNSTR_TESTDB="host=/var/run/postgresql dbname=postgres"

PGBENCH_SCALES="2000 5000" # RAM vs 2x RAM, assuming 32GB RAM
PGBENCH_INIT_FLAGS="-I dtgv --unlogged"  # Don't need the PK
PGBENCH_PARTITIONS="0 8"
PGBENCH_DURATION=1800
PROTOCOL=prepared
PGBENCH_CLIENTS=1

TEST_QUERY="select bid, avg(abalance) from pgbench_accounts group by bid"

SQL_PGSS_SETUP="CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
SQL_PGSS_RESULTS_SETUP="CREATE TABLE IF NOT EXISTS public.pgss_results AS SELECT ''::text AS hostname, now() AS created_on, 0::numeric AS server_version_num, ''::text as random_page_cost, 0 AS scale, 0 AS duration, 0 AS clients, 0 AS partitions, ''::text AS parallel_leader_participation, 0::int max_parallel_workers_per_gather, mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query FROM public.pg_stat_statements WHERE false;"
SQL_PGSS_RESET="SELECT public.pg_stat_statements_reset();"

HOSTNAME=`hostname`
DUMP_FILE="pgss.dump"

function exec_sql() {
    psql "$CONNSTR_TESTDB" -Xqc "$1"
}

START_TIME=`date +%s`
START_TIME_PG=`psql "$CONNSTR_RESULTSDB" -qAXtc "select now();"`

echo "Ensuring pg_stat_statements extension on result server and public.pgss_results table ..."

echo "Ensuring pg_stat_statements extension on test instance ..."
exec_sql "$SQL_PGSS_SETUP"
exec_sql "$SQL_PGSS_RESULTS_SETUP"


for SCALE in $PGBENCH_SCALES ; do

for PARTS in $PGBENCH_PARTITIONS ; do

echo -e "\n*** SCALE $SCALE ***\n"

echo "Creating test data using pgbench ..."
exec_sql "drop table if exists pgbench_accounts cascade"
echo "pgbench -i -q $PGBENCH_INIT_FLAGS -s $SCALE --partitions $PARTS  \"$CONNSTR_TESTDB\" &>/dev/null"
pgbench -i -q $PGBENCH_INIT_FLAGS -s $SCALE --partitions $PARTS "$CONNSTR_TESTDB" &>/dev/null

DBSIZE=`psql "$CONNSTR_TESTDB" -XAtqc "select pg_size_pretty(pg_database_size(current_database()))"`
echo "DB size = $DBSIZE"

for parallel_leader_participation in on off ; do

for max_parallel_workers_per_gather in 2 4 8 16 ; do

exec_sql "alter system set parallel_leader_participation = $parallel_leader_participation;"
exec_sql "alter system set max_parallel_workers_per_gather = $max_parallel_workers_per_gather;"
exec_sql "select pg_reload_conf();"

echo "Starting the test loop ..."

echo "Reseting pg_stat_statements..."
exec_sql "$SQL_PGSS_RESET" >/dev/null

echo "Running the timed query test"
echo "echo '$TEST_QUERY' | pgbench --random-seed 666 -M $PROTOCOL -c $PGBENCH_CLIENTS -T $PGBENCH_DURATION -f- \"$CONNSTR_TESTDB\""
echo "$TEST_QUERY" | pgbench --random-seed 666 -M $PROTOCOL -c $PGBENCH_CLIENTS -T $PGBENCH_DURATION -f- "$CONNSTR_TESTDB"

exec_sql "insert into pgss_results select '${HOSTNAME}', now(), current_setting('server_version_num')::int, current_setting('random_page_cost'), ${SCALE}, ${PGBENCH_DURATION}, ${PGBENCH_CLIENTS}, $PARTS, '${parallel_leader_participation}', '${max_parallel_workers_per_gather}', mean_exec_time, stddev_exec_time, calls, rows, shared_blks_hit, shared_blks_read, blk_read_time, blk_write_time, query from public.pg_stat_statements where calls > 1 and query ~* '(INSERT|UPDATE|SELECT).*pgbench_accounts'"

echo "Done with max_parallel_workers_per_gather=$max_parallel_workers_per_gather"
done # max_parallel_workers_per_gather

echo "Done with parallel_leader_participation=$parallel_leader_participation"
done # parallel_leader_participation

echo "Done with SCALE $SCALE"
done # SCALE

echo "Done with PARTS $PARTS"
done # PARTS

echo "Dumping pgss_results to $DUMP_FILE ..."
pg_dump -t pgss_results > $DUMP_FILE

END_TIME=`date +%s`
echo -e "\nDONE in $((END_TIME-START_TIME)) s"
