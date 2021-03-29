#!/bin/sh
# setting up a private registry on the cluster, using
# https://github.com/twuni/docker-registry.helm
# argument flags:
# - passing 'nopwd' disables http basic auth for registry access

# learn about some utility functions before heading on ...
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
. "$scriptdir/services/deploytools"

# get provided command line flags
nopwd="$(getScriptFlags nopwd "$@")"
noingress="$(getScriptFlags noingress "$@")"

loadSiteConfig

checkVars SC_REGISTRY_NAME SC_REGISTRY_PUB SC_REGISTRY_KEY || exit 1
SVC_NAME=myregistry
pvcfg="$scriptdir/definitions/registry_pv_nfs.yaml"

if [ "$1" != "clean" ];
then
    helm repo add twuni https://helm.twun.io

    if [ -z "$nopwd" ]; then
        # check for credentials for protected public accessible registry
        checkVars SC_REGISTRY_USER SC_REGISTRY_PASS SC_NAMESPACE || exit 1
        cmdExists htpasswd || sudo apt-get install -y apache2-utils
        pwdargs="--set secrets.htpasswd=$(echo "$SC_REGISTRY_PASS" | htpasswd -Bbn -i "$SC_REGISTRY_USER")"
        setRegistryAccessForPulling
    fi
    if [ -z "$noingress" ]; then
        args="--set ingress.enabled=true,ingress.hosts[0]=$SC_REGISTRY_NAME"
        args="$args --set ingress.tls[0].hosts[0]=$SC_REGISTRY_NAME"
        args="$args --set ingress.tls[0].secretName=${SVC_NAME}.tls"
        if [ -z "$nopwd" ]; then
            echo "$SC_REGISTRY_PASS" | htpasswd -Bbn -i $SC_REGISTRY_USER | \
                kubectl -n dev create secret generic ${SVC_NAME}.ht --from-file=auth=/dev/stdin
            akey="\"nginx\\.ingress\\.kubernetes\\.io"
            pwdargs="         --set ingress.annotations.$akey/auth-type\"=basic"
            pwdargs="$pwdargs --set ingress.annotations.$akey/auth-secret\"=${SVC_NAME}.ht"
            # fix this https://imti.co/413-request-entity-too-large/
            pwdargs="$pwdargs --set ingress.annotations.$akey/proxy-body-size\"=0"
        fi
    else
        echo "Using NodePort without ingress: Make sure that $SC_REGISTRY_NAME points to this host!"
        echo "  e.g. via /etc/hosts"
        args="--set service.type=NodePort,service.nodePort=$SC_REGISTRY_PORT"
        args="$args --set tlsSecretName=${SVC_NAME}.tls"
    fi

    # add registry name to known hosts -> on all nodes which access the registry
#    grep -q $SC_REGISTRY_NAME /etc/hosts || sudo sed -i -e '/10.0.9.1/s/$/ '$SC_REGISTRY_NAME'/' /etc/hosts
    createTLSsecret dev "${SVC_NAME}.tls" "$SC_REGISTRY_PUB" "$SC_REGISTRY_KEY"

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
    kubectl delete secret -n "$SC_NAMESPACE" "${SVC_NAME}-cred"
    kubectl patch serviceaccount -n "$SC_NAMESPACE" default -p '{"imagePullSecrets":[]}'
    kubectl delete -f "$pvcfg"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
