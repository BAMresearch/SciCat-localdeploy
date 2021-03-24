#!/bin/sh
# setting up a private registry on the cluster, using
# https://github.com/twuni/docker-registry.helm
# argument flags:
# - passing 'nopwd' disables http basic auth for registry access

# learn about some utility functions before heading on ...
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
. "$scriptdir/services/deploytools"

# find which script flags were provided
nopwd=
(echo "$@" | grep -qi nopwd) && nopwd=true
noingress=
(echo "$@" | grep -qi noingress) && noingress=true

# CERT_PATH_PUB should be the path to the full chain public cert
checkVars SC_SITECONFIG REGISTRY_PORT CERT_PATH_PUB CERT_PATH_PRIV || exit 1
SVC_NAME=myregistry
pvcfg="$scriptdir/definitions/registry_pv_nfs.yaml"

if [ "$1" != "clean" ];
then
    helm repo add twuni https://helm.twun.io

    if [ -z "$nopwd" ]; then
        # check for credentials for protected public accessible registry
        checkVars REGISTRY_USER REGISTRY_PASS || exit 1
        echo "$REGISTRY_NAME credentials are: $REGISTRY_USER - $REGISTRY_PASS"
        pwdargs="--set secrets.htpasswd=$(echo "$REGISTRY_PASS" | htpasswd -Bbn -i "$REGISTRY_USER")"
    fi
    if [ -z "$noingress" ]; then
        args="--set ingress.enabled=true,ingress.hosts[0]=$REGISTRY_NAME"
        args="$args --set ingress.tls[0].hosts[0]=$REGISTRY_NAME"
        args="$args --set ingress.tls[0].secretName=${SVC_NAME}.tls"
        if [ -z "$nopwd" ]; then
            echo "$REGISTRY_PASS" | htpasswd -Bbn -i $REGISTRY_USER | \
                kubectl -n dev create secret generic ${SVC_NAME}.ht --from-file=auth=/dev/stdin
            akey="\"nginx\\.ingress\\.kubernetes\\.io"
            pwdargs="         --set ingress.annotations.$akey/auth-type\"=basic"
            pwdargs="$pwdargs --set ingress.annotations.$akey/auth-secret\"=${SVC_NAME}.ht"
        fi
    else
        echo "Using NodePort without ingress: Make sure that $REGISTRY_NAME points to this host!"
        echo "  e.g. via /etc/hosts"
        args="--set service.type=NodePort,service.nodePort=$REGISTRY_PORT"
        args="$args --set tlsSecretName=${SVC_NAME}.tls"
    fi

    # add registry name to known hosts -> on all nodes which access the registry
#    grep -q $REGISTRY_NAME /etc/hosts || sudo sed -i -e '/10.0.9.1/s/$/ '$REGISTRY_NAME'/' /etc/hosts
    kubectl create secret -ndev tls "${SVC_NAME}.tls" --key "$CERT_PATH_PRIV" --cert "$CERT_PATH_PUB"

    echo " -> Using NFS for persistent volumes."
    echo "    Please make sure the configured NFS shares can be mounted: '$pvcfg'"
    kubectl apply -f "$pvcfg"
    helm install $SVC_NAME twuni/docker-registry --namespace dev \
        --set persistence.enabled=true,persistence.size=5Gi \
        $pwdargs $args
else # clean up
    helm del $SVC_NAME -ndev
    kubectl delete secret -n dev "${SVC_NAME}.tls"
    kubectl delete secret -n dev "${SVC_NAME}.ht"
    kubectl delete -f "$pvcfg"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
