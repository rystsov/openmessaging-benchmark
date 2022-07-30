#!/usr/bin/env bash

set -e

if [ "$1" = "" ]; then
    echo "Must provide owner ./test-load user-name"
    exit 1
fi

echo "terraforming" >> log
terraform apply -auto-approve -var="username=$1"
sleep 1m

echo "deploying" >> log
ansible-playbook deploy.yaml
for v in "22.1.5" "22.2.1"; do
    echo "installing $v" >> log
    ansible-playbook redpanda.install.yaml --extra-vars "redpanda_version=$v~rc1-1"
    ansible-playbook redpanda.configure.yaml
    ansible-playbook redpanda.start.yaml
    echo "testing perf-footprint-full-load-simple" >> log
    ansible-playbook test.yaml --extra-vars "test=perf-footprint-full-simple"
    ./fetch-n-report.sh "$v-simple"
    ansible-playbook redpanda.stop.yaml
    ansible-playbook redpanda.uninstall.yaml
done
echo "destroying" >> log
terraform destroy -auto-approve -var="username=$1"
