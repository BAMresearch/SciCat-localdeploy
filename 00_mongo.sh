#!/bin/sh
# Set up and start a mongodb instance in a kubernetes cluster
# USAGE: $0 [cleanonly] [deletedata]
# *cleanonly* runs cleanup procedures only, skips starting services again
# *deletedata* removes persistent storage data entirely

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/services/deploytools"

# get given command line flags
cleanonly="$(getScriptFlags cleanonly "$@")"
deletedata="$(getScriptFlags deletedata "$@")"

# ensure infrastucture namespace exists
NS_FILE="$(find "$scriptdir/namespaces" -iname '*.yaml')"
NS="$(sed -n -e '/^metadata/{:a;n;s/^\s\+name:\s*\(\w\+\)/\1/;p;Ta' -e'}' "$NS_FILE")"
if [ -z "$NS" ]; then
    echo "Could not determine desired namespace!"
    exit 1
fi
if ! (kubectl get ns -o jsonpath='{.items[*].metadata.name}' | grep -qi "\\<$NS\\>"); then
    echo "Could not find namespace, creating '$NS'."
    kubectl create -f "$NS_FILE"
fi
kubectl get ns -o jsonpath='{.items[*].metadata.name}'; echo

pvcfg="$scriptdir/definitions/mongo_pv_nfs.yaml"
echo "-> Using NFS for persistent volumes."
echo "   Please make sure the configured NFS shares can be mounted:"
echo "   '$pvcfg'"
mpath="$(awk -F':' '/path:/{sub(/^ */,"",$2);print $2}' "$pvcfg")"
if ! [ -d "$mpath" ]; then
    mkdir -p "$mpath"
    chmod a+w "$mpath"
fi

# remove the pod
helm del local-mongodb --namespace "$NS"
# reclaim PV
pvname="$(kubectl -n $NS get pv | grep mongo | awk '{print $1}')"
[ -z "$pvname" ] || \
    kubectl patch pv "$pvname" -p '{"spec":{"claimRef":null}}'

# delete old volume first
echo "Waiting for mongodb persistentvolume being removed ... "
while kubectl -n "$NS" get pv | grep -q mongo; do
    # https://github.com/kubernetes/kubernetes/issues/77258#issuecomment-502209800
    kubectl patch pv $pvname -p '{"metadata":{"finalizers":null}}'
    timeout 6 kubectl delete pv $pvname
done
echo "done."

if [ ! -z "$deletedata" ]; then
    echo "Delete the underlying data!"
    datapath="$(awk -F: '/path/ {sub("^\\s*","",$2); print $2}' "$pvcfg")"
    [ -d "$datapath" ] && rm -R "$datapath/data"
fi

[ -z "$cleanonly" ] || exit # done here in 'clean only' mode

kubectl apply -f "$pvcfg"
# reset root password in existing db:
# - create pod with auth disabled, helm arg '--set auth.enabled=false'
# - change pwd of user root in db
# - recreate pod with auth enabled
# - update k8s secret (example pwd 'test'):
#   kubectl -ndev get secret local-mongodb -o json | jq ".data[\"mongodb-root-password\"]=\"$(echo test | base64)\"" | kubectl apply -f -
cmd="helm install local-mongodb bitnami/mongodb --namespace $NS"
echo "$cmd"; eval $cmd

# vim: set ts=4 sw=4 sts=4 tw=0 et:
