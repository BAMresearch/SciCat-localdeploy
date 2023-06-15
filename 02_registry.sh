#!/bin/sh
# setting up a private registry on the cluster, using
# https://github.com/twuni/docker-registry.helm
# argument flags:
# - 'nopwd' disables http basic auth for registry access
# - 'noingress' sets up NodePort without ingress
# - 'clean' removes the services and removes used resources (e.g. secrets)
# - 'checkCert' Returns true if the installed certificates (in kubernetes)
#   are older than the files on disk and an restart using this script is recommended
# example crontab:
# (check once a week if there is a more recent cert and restart the registry if positive)
# 23 2 * * 0 (cd /home/buildbot/scicat; export SC_SITECONFIG=$(pwd)/fb65; if ./deploy/02_registry.sh checkCert; then ./deploy/02_registry.sh clean; sleep 5; ./deploy/02_registry.sh; fi)

# learn about some utility functions before heading on ...
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
. "$scriptdir/services/deploytools"

# get provided command line flags
nopwd="$(getScriptFlags nopwd "$@")"
noingress="$(getScriptFlags noingress "$@")"
checkCert="$(getScriptFlags checkCert "$@")"

loadSiteConfig

checkVars SC_REGISTRY_NAME SC_REGISTRY_PUB SC_REGISTRY_KEY || exit 1
SVC_NAME=myregistry
pvcfg="$scriptdir/definitions/registry_pv_nfs.yaml"

if [ ! -z "$checkCert" ]; then
    [ "$( ( (kubectl get secret -n dev ${SVC_NAME}.tls -o json | jq .data | sed 's/tls.//g' | jq -r .crt | base64 -d | openssl x509 -noout -dates); openssl x509 -in "$SC_REGISTRY_PUB" -noout -dates) | grep notBefore | python3 -c "import sys, datetime; fmt='%b %d %H:%M:%S %Y %Z'; starts=[datetime.datetime.strptime(dat.split('=')[-1].strip(), fmt).timestamp() for dat in sys.stdin.readlines()]; print(starts[0] < starts[1])")" = "True" ]
    exit $?
fi

if [ "$1" != "clean" ];
then
    helm repo add twuni https://helm.twun.io
    helm repo update

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
    adjustServerAddr "$NFS_SERVER" "$pvcfg" | kubectl apply -f -
    cmd="helm install $SVC_NAME twuni/docker-registry --namespace dev \
        --set persistence.enabled=true,persistence.size=5Gi \
        $pwdargs $args"
    (echo "$cmd" && eval "$cmd")
else # clean up
    helm del $SVC_NAME -ndev
    kubectl delete secret -n dev "${SVC_NAME}.tls"
    kubectl delete secret -n dev "${SVC_NAME}.ht"
    kubectl delete secret -n "$SC_NAMESPACE" reg-cred #"${SVC_NAME}-cred"
    kubectl patch serviceaccount -n "$SC_NAMESPACE" default -p '{"imagePullSecrets":[]}'
    pvname="$(yq .metadata.name "$pvcfg")"
    if [ -n "$pvname" ]; then
        kubectl patch pv $pvname -p '{"spec":{"claimRef":null}}'
        echo "Waiting for persistentvolume being removed ... "
        while kubectl -n dev get pv | grep -q "$pvname"; do
            # https://github.com/kubernetes/kubernetes/issues/77258#issuecomment-502209800
            kubectl patch pv "$pvname" -p '{"metadata":{"finalizers":null}}'
            timeout 6 kubectl delete pv "$pvname"
        done
    fi
    pvcname="$(kubectl get pvc -n dev -o yaml | yq '.items[].metadata.name' | grep registry)"
    if [ -n "$pvcname" ]; then
        kubectl patch pvc -n dev "$pvcname" -p '{"metadata":{"finalizers":null}}'
        kubectl delete pvc -n dev "$pvcname"
    fi
    echo "done."
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
