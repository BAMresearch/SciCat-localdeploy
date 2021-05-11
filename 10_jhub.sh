#!/bin/sh
# Installing JupyterHub in kubernetes
# https://zero-to-jupyterhub.readthedocs.io/en/stable/jupyterhub/installation.html

# learn about some utility functions before heading on ...
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
. "$scriptdir/services/deploytools"

# get provided command line flags
clean="$(getScriptFlags clean "$@")"

SVC_NAME=jhub
NS_NAME=jhub
SECRET="${SVC_NAME}.tls"

loadSiteConfig
checkVars SC_JHUB_FQDN SC_JHUB_PUB SC_JHUB_KEY || exit 1

pvcfg="$scriptdir/definitions/jhub-db_pv_nfs.yaml"
mpath="$(awk -F':' '/path:/{sub(/^ */,"",$2);print $2}' "$pvcfg")"

kubectl delete secret -n "$NS_NAME" "$SECRET"
if [ -z "$clean" ];
then
    # ensure chart repo is available
    (helm repo list | grep -q '^jupyterhub') \
        || helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
    # set up storage volumes (pv)
    if ! [ -d "$mpath" ]; then
        mkdir -p "$mpath"
        #chmod a+w "$mpath"
    fi
    kubectl apply -f "$pvcfg"
    # set up TLS config for https through ingress
    args="--set ingress.enabled=true,ingress.hosts[0]=$SC_JHUB_FQDN"
    args="$args --set ingress.tls[0].hosts[0]=$SC_JHUB_FQDN"
    args="$args --set ingress.tls[0].secretName=$SECRET"
    createTLSsecret $NS_NAME "$SECRET" "$SC_JHUB_PUB" "$SC_JHUB_KEY"
    helm upgrade --cleanup-on-fail --install $SVC_NAME jupyterhub/jupyterhub \
            --namespace $NS_NAME --create-namespace \
            --set singleuser.storage.capacity=2Gi \
            --set proxy.secretToken=$(openssl rand -hex 32) \
            --set proxy.service.type=ClusterIP $args

else # clean up
    pvname="$(kubectl get pvc -n $NS_NAME hub-db-dir -o jsonpath='{.spec.volumeName}')"
    helm del $SVC_NAME -n$NS_NAME
    # reclaim PV
    [ -z "$pvname" ] || \
        kubectl patch pv "$pvname" -p '{"spec":{"claimRef":null}}'
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
