# parallel-leader-participation-test
Test effects of Postgres parallel_leader_participation settings

# Prerequisites

* AWS CLI installed / configured
* [pg-spot-operator](https://github.com/pg-spot-ops/pg-spot-operator) Python CLI installed
* Ansible installed

# Running the test

```
./launch_vms_and_run_test.sh run1-local eu-south-2 local 100
```

# Analyzing the results

Load the pg_stat_statements dump files from `results` folder into a local Postgres instance:

```
for x in `ls -1 results/*.dump` ; do psql -f $x ; done
```

A `pgss_results` table will be created. See the queries from `analyze_results.sql` as a base line.
