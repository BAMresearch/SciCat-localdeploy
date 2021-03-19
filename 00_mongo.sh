#!/bin/sh
# Set up and start a mongodb instance in a kubernetes cluster
# USAGE: $0 [bare] [clean]
# 1st arg: 'bare' sets up services in a 'pure' k8s scenario
#          while using minikube is the default
# 2nd arg: 'clean' runs cleanup procedures only, skips starting services again

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/services/deploytools"

NS_FILE="$(find "$scriptdir/namespaces" -iname '*.yaml')"
kubectl create -f $NS_FILE
NS="$(sed -n -e '/^metadata/{:a;n;s/^\s\+name:\s*\(\w\+\)/\1/;p;Ta' -e'}' "$NS_FILE")"
[ -z "$NS" ] && (echo "Could not determine namespace!"; exit 1)

pvcfg="$scriptdir/definitions/mongo_pv_hostpath.yaml"
if [ "$2" = "bare" ]; then
    pvcfg="$scriptdir/definitions/mongo_pv_nfs.yaml"
    echo " -> Using NFS for persistent volumes in 'bare' mode."
    echo "    Please make sure the configured NFS shares can be mounted: '$pvcfg'"
fi

# remove the pod
helm del local-mongodb --namespace "$NS"
# reclaim PV
pvname="$(kubectl -n $NS get pv | grep mongo | awk '{print $1}')"
[ -z "$pvname" ] || \
    kubectl patch pv "$pvname" -p '{"spec":{"claimRef":null}}'

if [ "$2" = "clean" ]; then
    # delete old volume first
    echo -n "Waiting for mongodb persistentvolume being removed ... "
    while kubectl -n "$NS" get pv | grep -q mongo; do
        # https://github.com/kubernetes/kubernetes/issues/77258#issuecomment-502209800
        kubectl patch pv $pvname -p '{"metadata":{"finalizers":null}}'
        timeout 6 kubectl delete pv $pvname
    done
    kubectl delete -f "$pvcfg"
    echo "done."
fi

if [ "$1" = "bare" ] && [ "$2" = "clean" ]; then
    # delete the underlying data
    datapath="$(awk -F: '/path/ {sub("^\\s*","",$2); print $2}' "$pvcfg")"
    [ -d "$datapath" ] && rm -R "$datapath/data"
fi

[ -z "$SITECONFIG" ] && SITECONFIG="$scriptdir/siteconfig"
export SITECONFIG
if [ ! -d "$SITECONFIG" ]; then
    # generate some passwords before starting any services
    mkdir -p "$SITECONFIG"
    gen_catamel_credentials "$SITECONFIG"
fi

kubectl apply -f "$pvcfg"
cmd="helm install local-mongodb bitnami/mongodb --namespace $NS"
echo "$cmd"; eval $cmd

# vim: set ts=4 sw=4 sts=4 tw=0 et:
