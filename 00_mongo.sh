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

loadSiteConfig
checkVars NFS_SERVER || exit 1

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

get_podid() {
    kubectl get po -n dev | grep -o '[a-zA-Z0-9-]*mongo[a-zA-Z0-9-]*'
}
# remove the pod
svc=local-mongodb
remove_pod() {
    local svc="$1"
    podid="$(get_podid)"
    pvname="$(kubectl get pv -n $NS -o json | \
        jq -r "(.items[] | select(.spec.claimRef.name==\"$svc\")).metadata.name")"
    helm del $svc --namespace "$NS"
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
        kubectl -n dev wait --for=delete "pvc/$svc"
        echo "done."
    fi
    kubectl -n dev wait --for=delete "pod/$podid"
}
remove_pod $svc

if [ ! -z "$deletedata" ]; then
    echo "Delete the underlying data!"
    datapath="$(awk -F: '/path/ {sub("^\\s*","",$2); print $2}' "$pvcfg")"
    [ -d "$datapath" ] && rm -R "$datapath/data"
fi

[ -z "$cleanonly" ] || exit # done here in 'clean only' mode

# create the persistent volume first
adjustServerAddr "$NFS_SERVER" "$pvcfg" | kubectl apply -f -
# reset root password in existing db:
# - restart service with auth disabled
#   ./00_mongo.sh noauth
# - change pwd of user root in db: db.changeUserPassword('root', <password>)
#   - log in by following shown notes after mongodb setup
# - recreate pod with auth enabled
#   ./00_mongo.sh
# - update k8s secret, set MONGODB_ROOT_PASSWORD env var before:
#   kubectl -ndev get secret local-mongodb -o json | jq ".data[\"mongodb-root-password\"]=\"$(echo "$MONGODB_ROOT_PASSWORD" | base64)\"" | kubectl apply -f -

# start mongodb in no-auth mode first
cmd="helm install $svc bitnami/mongodb --namespace $NS"
tmpcmd="$cmd --set auth.enabled=false"
echo "$tmpcmd"; eval $tmpcmd
podid="$(get_podid)"
kubectl -n dev wait --for=condition=ready "pod/$podid"
# set root password in no-auth mode
(echo "use admin"; echo "db.changeUserPassword(\"root\", \"$SC_MONGO_ROOTPWD\")") | \
    kubectl -n dev exec -i "$podid"  -- mongosh
remove_pod $svc
kubectl get po -n dev
kubectl get pv -n dev
kubectl get pvc -n dev

# create a new persistent volume first
adjustServerAddr "$NFS_SERVER" "$pvcfg" | kubectl apply -f -
# restart mongodb with auth again
echo "$cmd"; eval $cmd
kubectl -n dev wait --for=condition=ready "pod/$(get_podid)"

# update k8s secret, set MONGODB_ROOT_PASSWORD env var before:
kubectl -n $NS get secret $svc -o json | jq ".data[\"mongodb-root-password\"]=\"$(echo "$SC_MONGO_ROOTPWD" | base64)\"" | kubectl apply -f -

# vim: set ts=4 sw=4 sts=4 tw=0 et:
