#!/bin/sh

# learn about some utility functions before heading on ...
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
. "$scriptdir/services/deploytools"

# CERT_PATH_PUB should be the path to the full chain public cert
checkVars REGISTRY_PORT CERT_PATH_PUB CERT_PATH_PRIV || exit 1
REGISTRY_NAME=myregistry
pvcfg="$scriptdir/definitions/registry_pv_nfs.yaml"
echo " -> Using NFS for persistent volumes."
echo "    Please make sure the configured NFS shares can be mounted: '$pvcfg'"

if [ "$1" != "clean" ];
then
    helm repo add twuni https://helm.twun.io

    # add registry name to known hosts -> on all nodes which access the registry
#    grep -q $REGISTRY_NAME /etc/hosts || sudo sed -i -e '/10.0.9.1/s/$/ '$REGISTRY_NAME'/' /etc/hosts
    sudo -E kubectl create secret -ndev tls "${REGISTRY_NAME}.secret" --key "$CERT_PATH_PRIV" --cert "$CERT_PATH_PUB"
    kubectl apply -f "$pvcfg"
    helm install $REGISTRY_NAME twuni/docker-registry --namespace dev \
        --set service.type=NodePort,service.nodePort=$REGISTRY_PORT \
        --set tlsSecretName="${REGISTRY_NAME}.secret" \
        --set persistence.enabled=true,persistence.size=5Gi
else # clean up
    helm del $REGISTRY_NAME -ndev
    kubectl delete secret -ndev "${REGISTRY_NAME}.secret"
    kubectl delete -f "$pvcfg"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
