#!/usr/bin/env bash

set -e

export PATH=$PATH:/opt/benchmark/bin

. /opt/benchmark/suites/utils.sh

sudo rm -rf footprint.tar.bz2
sudo rm -rf *.json

for i in $(seq 4); do
    retry-on-error base sudo $OMB/bin/benchmark -o base-$1-$i -t swarm -d $OMB/driver-redpanda/redpanda-ack-all-linger-1ms-eod-false.yaml $OMB/workloads/release/full/load.625k.yaml
    fetch-logs base-$1-$i

    retry-on-error autobalance sudo $OMB/bin/benchmark -o autobalance-$1-$i -t swarm -d $OMB/driver-redpanda/redpanda-ack-all-linger-1ms-eod-false.yaml $OMB/workloads/release/full/load.625k.yaml
    fetch-logs autobalance-$1-$i
done

sudo tar cjf footprint.tar.bz2 $(ls *json) base-* autobalance-*