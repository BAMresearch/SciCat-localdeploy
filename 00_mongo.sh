#!/bin/sh
# Set up and start a mongodb instance in a kubernetes cluster
# USAGE: $0 [cleanonly] [deletedata]
# *cleanonly* runs cleanup procedures only, skips starting services again
# *deletedata* removes persistent storage data entirely
#
# todo: indefinitely growing journal on VM hosts
#  - perhaps: https://docs.mongodb.com/manual/reference/command/compact/

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/services/deploytools"

# get given command line flags
cleanonly="$(getScriptFlags cleanonly "$@")"
deletedata="$(getScriptFlags deletedata "$@")"
noauth="$(getScriptFlags noauth "$@")"

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
# list all namespaces for debugging
# kubectl get ns -o jsonpath='{.items[*].metadata.name}'; echo

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
pvname="$(kubectl get pvc -n $NS local-mongodb -o jsonpath='{.spec.volumeName}')"
helm del local-mongodb --namespace "$NS"
# reclaim PV
if [ ! -z "$pvname" ]; then
    kubectl patch pv "$pvname" -p '{"spec":{"claimRef":null}}'
    # delete old volume first
    echo "Waiting for mongodb persistentvolume being removed ... "
    while kubectl -n "$NS" get pv | grep -q mongo; do
        # https://github.com/kubernetes/kubernetes/issues/77258#issuecomment-502209800
        kubectl patch pv "$pvname" -p '{"metadata":{"finalizers":null}}'
        timeout 6 kubectl delete pv "$pvname"
    done
    echo "done."
fi

if [ ! -z "$deletedata" ]; then
    echo "Delete the underlying data!"
    datapath="$(awk -F: '/path/ {sub("^\\s*","",$2); print $2}' "$pvcfg")"
    [ -d "$datapath" ] && rm -R "$datapath/data"
fi

[ -z "$cleanonly" ] || exit # done here in 'clean only' mode

kubectl apply -f "$pvcfg"
# reset root password in existing db:
# - restart service with auth disabled
#   ./00_mongo.sh noauth
# - change pwd of user root in db: db.changeUserPassword('root', <password>)
#   - log in by following shown notes after mongodb setup
# - recreate pod with auth enabled
#   ./00_mongo.sh
# - update k8s secret, set MONGODB_ROOT_PASSWORD env var before:
#   kubectl -ndev get secret local-mongodb -o json | jq ".data[\"mongodb-root-password\"]=\"$(echo "$MONGODB_ROOT_PASSWORD" | base64)\"" | kubectl apply -f -

autharg=""
[ -z "$noauth" ] || autharg="--set auth.enabled=false"
cmd="helm install local-mongodb bitnami/mongodb --namespace $NS $autharg"
echo "$cmd"; eval $cmd

# vim: set ts=4 sw=4 sts=4 tw=0 et:
