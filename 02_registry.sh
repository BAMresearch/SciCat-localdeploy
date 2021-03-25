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

checkVars REGISTRY_NAME SC_REGISTRY_PUB SC_REGISTRY_KEY || exit 1
SVC_NAME=myregistry
pvcfg="$scriptdir/definitions/registry_pv_nfs.yaml"

if [ "$1" != "clean" ];
then
    helm repo add twuni https://helm.twun.io

    if [ -z "$nopwd" ]; then
        # check for credentials for protected public accessible registry
        checkVars REGISTRY_USER REGISTRY_PASS SC_NAMESPACE || exit 1
        command -v htpasswd || sudo apt-get install -y apache2-utils
        pwdargs="--set secrets.htpasswd=$(echo "$REGISTRY_PASS" | htpasswd -Bbn -i "$REGISTRY_USER")"
        # set the private registry credentials to the service account pulling scicat builds later
        # see https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/
        # and https://www.digitalocean.com/community/questions/using-do-k8s-container-registry-authentication-required
        # alternatively https://stackoverflow.com/a/63643081
        kubectl -n "$SC_NAMESPACE" patch serviceaccount default \
            -p "{\"imagePullSecrets\": [{\"name\": \"${SVC_NAME}-cred\"}]}"
        kubectl -n "$SC_NAMESPACE" create secret docker-registry "${SVC_NAME}-cred" \
            --docker-server="$REGISTRY_NAME" --docker-username="$REGISTRY_USER" --docker-password="$REGISTRY_PASS"
        # check details with:
        # kubectl -n "$SC_NAMESPACE" get secret "${SVC_NAME}-cred" -o="jsonpath={.data.\.dockerconfigjson}" | base64 --decode
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
            # fix this https://imti.co/413-request-entity-too-large/
            pwdargs="$pwdargs --set ingress.annotations.$akey/proxy-body-size\"=0"
        fi
    else
        echo "Using NodePort without ingress: Make sure that $REGISTRY_NAME points to this host!"
        echo "  e.g. via /etc/hosts"
        args="--set service.type=NodePort,service.nodePort=$REGISTRY_PORT"
        args="$args --set tlsSecretName=${SVC_NAME}.tls"
    fi

    # add registry name to known hosts -> on all nodes which access the registry
#    grep -q $REGISTRY_NAME /etc/hosts || sudo sed -i -e '/10.0.9.1/s/$/ '$REGISTRY_NAME'/' /etc/hosts
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
