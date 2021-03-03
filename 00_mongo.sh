#!bin/sh
# Set up and start a mongodb instance in a kubernetes cluster
# USAGE: $0 [bare] [clean]
# 1st arg: 'bare' sets up services in a 'pure' k8s scenario
#          while using minikube is the default
# 2nd arg: 'clean' runs cleanup procedures only, skips starting services again

# get the script directory before creating any files
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
cd "$scriptdir"
. "$scriptdir/services/deploytools"

NS_FILE="$(find "$scriptdir/namespaces" -iname '*.yaml')"
kubectl create -f $NS_FILE
NS="$(sed -n -e '/^metadata/{:a;n;s/^\s\+name:\s*\(\w\+\)/\1/;p;Ta' -e'}' "$NS_FILE")"
[ -z "$NS" ] && (echo "Could not determine namespace!"; exit 1)

#mongopvcfg="mongopv_hostpath.yaml"
mongopvcfg="mongopv.yaml"
[ "$1" = "bare" ] && mongopvcfg="mongo_pv_nfs.yaml"

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
    echo "done."
fi
#kubectl delete -f "$mongopvcfg"

if [ "$1" = "bare" ] && [ "$2" = "clean" ]; then # delete the underlying data
    mongodatapath="$(awk -F: '/path/ {sub("^\\s*","",$2); print $2}' "$mongopvcfg")"
    [ -d "$mongodatapath" ] && rm -R "$mongodatapath/data"
fi
SITECFG="$scriptdir/siteconfig"
if [ ! -d "$SITECFG" ]; then
    # generate some passwords before starting any services
    mkdir -p "$SITECFG"
    (cd "$(dirname "$SITECFG")" && gen_catamel_credentials "$(basename "$SITECFG")")
fi

kubectl apply -f "$mongopvcfg"
mongocmd="helm install local-mongodb bitnami/mongodb --namespace $NS"
echo "$mongocmd"; eval $mongocmd

# vim: set ts=4 sw=4 sts=4 tw=0 et:
