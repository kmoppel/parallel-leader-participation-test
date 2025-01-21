#!/bin/bash

if [ -z "$4" ]; then
  echo "Usage: ./launch_vms_and_run_test.sh INSTANCE_ID REGION STORAGE_TYPE STORAGE_MIN"
  echo "Example:"
  echo "   ./launch_vms_and_run_test.sh run1-ebs eu-south-2 network 100"
  exit 1
fi

mkdir logs results

set -eu

INSTANCE_ID="$1"  # lowercase + dashes only
REGION="$2"  # eu-south-2 (Spain) best in EU currently according to: pg_spot_operator --list-avg-spot-savings --region ^eu
STORAGE_TYPE="$3"  # local | network
STORAGE_MIN="$4"  # in GB

CPU_MIN=16
CPU_MIN=2
RAM_MIN=32
RAM_MIN=4
PROVISIONED_VOLUME_THROUGHPUT=500  # Default 125 MBs is very limiting

T1=$(date +%s)

# Launch a Spot VM with Postgres, place Ansible connstr in $INSTANCE_ID.ini
echo "Starting the test VM $INSTANCE_ID in region $REGION ..."
# Prerequisite: pipx install --include-deps ansible pg_spot_operator
# Details: https://github.com/pg-spot-ops/pg-spot-operator
pg_spot_operator --instance-name $INSTANCE_ID --region $REGION \
  --cpu-min $CPU_MIN --ram-min $RAM_MIN \
  --storage-type $STORAGE_TYPE --storage-min $STORAGE_MIN \
  --volume-throughput $PROVISIONED_VOLUME_THROUGHPUT \
  --connstr-only --connstr-format ansible \
  --os-extra-packages rsync > $INSTANCE_ID.ini

echo "VM OK - running Ansible ..."
ANSIBLE_LOG_PATH=logs/ansible_${INSTANCE_ID}.log ansible-playbook -i $INSTANCE_ID.ini playbook.yml

if [ "$?" -eq 0 ]; then
  echo "Tests OK, shutting down the instance ..."
  pg_spot_operator --region $REGION --instance-name $INSTANCE_ID --teardown
else
  echo "ERROR: Ansible failed - check the log at $ANSIBLE_LOG_PATH"
  exit 1
fi

T2=$(date +%s)
DUR=$((T2-T1))

echo "Done in $DUR seconds"
