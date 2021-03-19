#!/usr/bin/env bash
# run.sh - set up and start SciCat services and their dependencies
# USAGE: run.sh [pause|nopause] [bare] [clean]
# 1st arg: 'nopause' does not ask user to confirm or skip single steps
#          runs everything in one go
# 2nd arg: 'bare' sets up services in a 'pure' k8s scenario
#          while using minikube is the default
# 3rd arg: 'clean' runs cleanup procedures only, skips starting services again

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/services/deploytools"
loadSiteConfig
checkVars REGISTRY_NAME REGISTRY_PORT || exit 1
export REGISTRY_ADDR=$REGISTRY_NAME:$REGISTRY_PORT
export KUBE_NAMESPACE=yourns

cd "$scriptdir"
NS_FILE=./namespaces/*.yaml
fn="$(basename $NS_FILE)"
ns="${fn%.*}"
kubectl create -f $NS_FILE
export LOCAL_ENV="$ns"

# Deploy services

SERVICES_DIR=./services/*/*.sh
for file in $SERVICES_DIR; do
    answer=
    [ "$1" = "nopause" ] || \
        read -p "Skip restarting $file? [yN] " answer
    [ "$answer" = "y" ] && continue
    echo "# Running now '$file' ..."
    bash "$file"
done

# vim: set ts=4 sw=4 sts=4 tw=0 et:
