#!/usr/bin/env bash

set -e

function worker_stop() {
    ssh -i ~/.ssh/redpanda_aws $1 sudo systemctl stop benchmark-worker
}

function worker_start() {
    ssh -i ~/.ssh/redpanda_aws $1 sudo systemctl start benchmark-worker
}

function redpanda_stop () {
    ssh -i ~/.ssh/redpanda_aws $1 sudo systemctl stop redpanda
}
function redpanda_wipe () {
    ssh -i ~/.ssh/redpanda_aws $1 sudo rm -rf /mnt/vectorized/redpanda/data
    ssh -i ~/.ssh/redpanda_aws $1 sudo rm -rf /mnt/vectorized/redpanda/coredump
}
function redpanda_start () {
    ssh -i ~/.ssh/redpanda_aws $1 sudo systemctl start redpanda
}

export -f worker_stop
export -f worker_start
export -f redpanda_stop
export -f redpanda_wipe
export -f redpanda_start

function reset_all () {
    sudo echo "Restarting workload" >> log
    cat /opt/benchmark/client | xargs -L 1 bash -c 'worker_stop "$@"' _
    sudo echo "Restarting redpanda" >> log
    cat /opt/benchmark/redpanda | xargs -L 1 bash -c 'redpanda_stop "$@"' _
    cat /opt/benchmark/redpanda | xargs -L 1 bash -c 'redpanda_wipe "$@"' _
    cat /opt/benchmark/redpanda | xargs -L 1 bash -c 'redpanda_start "$@"' _
    sleep 10s
    sudo echo "Redpanda is restarted" >> log
    cat /opt/benchmark/client | xargs -L 1 bash -c 'worker_start "$@"' _
    sudo echo "Workload is restarted" >> log
}

function retry-on-error () {
    sudo echo "retry-on-error $@" >> log
    reset_all

    attempt=0
    while (( attempt < 5)); do
        stated_s=$(date +%s)
        eval $@
        duration_s=$(( $(date +%s) - stated_s ))
        if (( duration_s > 60 )); then
            return 0
        fi
        sleep 1s
        attempt=$(( $attempt + 1))
    done
    exit 1
}