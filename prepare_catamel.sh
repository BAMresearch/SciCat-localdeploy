#!/usr/bin/env bash
# run.sh - set up and start SciCat services and their dependencies
# USAGE: run.sh [pause|nopause] [bare] [clean]
# 1st arg: 'nopause' does not ask user to confirm or skip single steps
#          runs everything in one go
# 2nd arg: 'bare' sets up services in a 'pure' k8s scenario
#          while using minikube is the default
# 3rd arg: 'clean' runs cleanup procedures only, skips starting services again

# get the script directory before creating any files
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
cd "$scriptdir"
. ./services/deploytools

export KUBE_NAMESPACE=yourns
NS_FILE=./namespaces/*.yaml
fn="$(basename $NS_FILE)"
ns="${fn%.*}"
kubectl create -f $NS_FILE
export LOCAL_ENV="$ns"

#mongopvcfg="mongopv_hostpath.yaml"
mongopvcfg="mongopv.yaml"
[ "$2" = "bare" ] && mongopvcfg="mongo_pv_nfs.yaml"

answer=
[ "$1" = "nopause" ] || \
  read -p "Skip restarting base services (mongodb, rabbit, node)? [yN] " answer
if [ "$answer" != "y" ]; then

  # delete old volume first
  echo -n "Waiting for mongodb persistentvolume being removed ... "
  while kubectl -n $LOCAL_ENV get pv | grep -q mongo; do
      sleep 1;
      pvname="$(kubectl -n $LOCAL_ENV get pv | grep mongo | awk '{print $1}')"
      # https://github.com/kubernetes/kubernetes/issues/77258#issuecomment-502209800
      kubectl patch pv $pvname -p '{"metadata":{"finalizers":null}}'
      timeout 6 kubectl delete pv $pvname
  done
  echo "done."
  kubectl delete -f "$mongopvcfg"
  helm del local-mongodb --namespace $LOCAL_ENV

  if [ "$3" != "clean" ]; then
    # generate some passwords before starting any services
    mkdir -p siteconfig
    gen_catamel_credentials siteconfig

    kubectl apply -f "$mongopvcfg"
    # using mongodb 4.2.x with chart v8, v4.4 causes fallocate errors with WiredTiger in logs, doesnt start
    mongocmd="helm install local-mongodb bitnami/mongodb --namespace $LOCAL_ENV --version '8'"
    echo "$mongocmd"; eval $mongocmd
  fi
fi

[ "$1" = "nopause" ] || \
  read -p "Skip generating certificates? [yN] " answer
if [ "$answer" != "y" ]; then
    NS="$KUBE_NAMESPACE" # provide namespace as command line argument
    FQDN="$(hostname --fqdn)"
    if [ -z "$FQDN" ]; then
        echo "Fully qualified domain name could not be found, aborting!"
        exit 1
    fi
    openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout catamel.key -out catamel.crt -subj "/CN=catamel.$FQDN" -days 3650
    kubectl delete secret -n$NS catamelservice 2>/dev/null
    kubectl create ns $NS
    kubectl create secret -n$NS tls catamelservice --key catamel.key --cert catamel.crt
fi

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
