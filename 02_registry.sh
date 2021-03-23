#!/bin/sh
# setting up a private registry on the cluster, using
# https://github.com/twuni/docker-registry.helm
# arguments:
# - passing 'nopwd' disables http basic auth for registry access

# learn about some utility functions before heading on ...
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
. "$scriptdir/services/deploytools"

nopwd=
(echo "$@" | grep -qi nopwd) && nopwd=true

# CERT_PATH_PUB should be the path to the full chain public cert
checkVars SC_SITECONFIG REGISTRY_PORT CERT_PATH_PUB CERT_PATH_PRIV || exit 1
REGISTRY_NAME=myregistry
pvcfg="$scriptdir/definitions/registry_pv_nfs.yaml"

if [ "$1" != "clean" ];
then
    helm repo add twuni https://helm.twun.io

    if [ -z "$nopwd" ]; then
        # set password for public accessible registry
        sudo apt install -y apache2-utils apg
        htusr="foo"
        htpwd="$(apg -m 17 -n1)"
        echo "$REGISTRY_NAME credentials are: $htusr - $htpwd"
        pwdargs="$(echo "$htpwd" | htpasswd -Bbn -i $htusr)"
    fi

    # add registry name to known hosts -> on all nodes which access the registry
#    grep -q $REGISTRY_NAME /etc/hosts || sudo sed -i -e '/10.0.9.1/s/$/ '$REGISTRY_NAME'/' /etc/hosts
    kubectl create secret -ndev tls "${REGISTRY_NAME}.secret" --key "$CERT_PATH_PRIV" --cert "$CERT_PATH_PUB"

    echo " -> Using NFS for persistent volumes."
    echo "    Please make sure the configured NFS shares can be mounted: '$pvcfg'"
    kubectl apply -f "$pvcfg"
    helm install $REGISTRY_NAME twuni/docker-registry --namespace dev \
        --set service.type=NodePort,service.nodePort=$REGISTRY_PORT \
        --set tlsSecretName="${REGISTRY_NAME}.secret" \
        --set persistence.enabled=true,persistence.size=5Gi \
        --set secrets.htpasswd="$pwdargs"
else # clean up
    helm del $REGISTRY_NAME -ndev
    kubectl delete secret -n dev "${REGISTRY_NAME}.secret"
    kubectl delete -f "$pvcfg"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
