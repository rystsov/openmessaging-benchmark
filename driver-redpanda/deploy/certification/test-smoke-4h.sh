#!/usr/bin/env bash

set -e

if [ "$1" = "" ]; then
    echo "Must provide owner ./test-load user-name"
    exit 1
fi

for i in 1; do
    echo "$(date) terraforming" >> log
    terraform apply -auto-approve -var="username=$1"
    sleep 1m
    
    echo "$(date) deploying" >> log
    ansible-playbook deploy.yaml
    
    echo "$(date) installing 21.11.18" >> log
    ansible-playbook redpanda.install.yaml --extra-vars "redpanda_version=21.11.18-1-601d05da"
    ansible-playbook redpanda.configure.yaml
    ansible-playbook redpanda.start.yaml
    echo "$(date) testing perf-footprint-smoke" >> log
    ansible-playbook test.yaml --extra-vars "test=perf-footprint-smoke"
    echo "$(date) tested perf-footprint-smoke" >> log
    ./fetch-n-report.sh "21.11.18-smoke-$i"
    if [ ! -d results ]; then
        echo "$(date) fetch-n-report.sh failed to build results" >> log
        exit 1
    fi
    echo "$(date) stopping redpanda" >> log
    ansible-playbook redpanda.stop.yaml
    echo "$(date) uninstalling redpanda" >> log
    ansible-playbook redpanda.uninstall.yaml
    
    for v in "22.1.5" "22.2.1"; do
        echo "$(date) installing $v" >> log
        ansible-playbook redpanda.install.yaml --extra-vars "redpanda_version=$v~rc1-1"
        ansible-playbook redpanda.configure.yaml
        ansible-playbook redpanda.start.yaml
        echo "$(date) testing perf-footprint-smoke" >> log
        ansible-playbook test.yaml --extra-vars "test=perf-footprint-smoke"
        echo "$(date) tested perf-footprint-smoke" >> log
        ./fetch-n-report.sh "$v-smoke-$i"
        if [ ! -d results ]; then
            echo "$(date) fetch-n-report.sh failed to build results" >> log
            exit 1
        fi
        echo "$(date) stopping redpanda" >> log
        ansible-playbook redpanda.stop.yaml
        echo "$(date) uninstalling redpanda" >> log
        ansible-playbook redpanda.uninstall.yaml
    done
    echo "$(date) destroying" >> log
    terraform destroy -auto-approve -var="username=$1"
done