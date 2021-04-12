#!/bin/sh

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/../deploytools"

# get given command line flags
noBuild="$(getScriptFlags nobuild "$@")"
buildOnly="$(getScriptFlags buildonly "$@")"
clean="$(getScriptFlags clean "$@")"

loadSiteConfig
checkVars SC_SCICHAT_FQDN SC_SCICHAT_PUB SC_SCICHAT_KEY SC_REGISTRY_ADDR SC_NAMESPACE || exit 1

REPO="https://github.com/SciCatProject/scichat-loopback.git"

cd "$scriptdir"

if [ -z "$buildOnly" ]; then
    namespaceExists "$NS" || kubectl create ns "$NS"
    # remove the existing service
    helm del scichat-loopback -n "$NS"
    kubectl -n $NS delete secret certs-scichat
    [ -z "$clean" ] || exit 0 # stop here when cleaning up

    IARGS="--set ingress.enabled=true,ingress.host=$SC_SCICHAT_FQDN,ingress.tlsSecretName=certs-scichat"
    createTLSsecret "$NS" certs-scichat "$SC_SCICHAT_PUB" "$SC_SCICHAT_KEY"
    # make sure DB credentials exist before starting any services
    gen_scichat_credentials "component/CI/ESS"
    [ -d "$SC_SITECONFIG/scichat" ] && mkdir -p "$scriptdir/scichat/config/" \
        && cp "$SC_SITECONFIG/scichat"/* "$scriptdir/scichat/config/"
fi

baseurl="$SC_REGISTRY_ADDR"
IMG_REPO="$baseurl/scichat"
# extra arguments if the registry need authentication as indicated by a set password
[ -z "$SC_REGISTRY_PASS" ] || baseurl="$SC_REGISTRY_USER:$SC_REGISTRY_PASS@$baseurl"
# get the latest image tag: sort by timestamp, pick the largest
IMAGE_TAG="$(curl -s "https://$baseurl/v2/scichat/tags/list" | jq -r '(.tags|sort[-1])?')"
if [ -z "$noBuild" ] || [ -z "$IMAGE_TAG" ]; then
    echo "img tag before: $IMAGE_TAG"
    updateSrcRepo "$REPO" develop "$IMAGE_TAG" || exit 1
    echo "img tag after:  $IMAGE_TAG"
    echo "Building release with tag $IMAGE_TAG"
    npm install
	sed -i -e "/npm config set/d" Dockerfile

    IMAGE_TAG="$(git show --format='%at_%h' HEAD)" # <timestamp>_<git commit>
    cmd="$DOCKER_BUILD -t $IMG_REPO:$IMAGE_TAG -t $IMG_REPO:latest ."
    echo "$cmd"; eval $cmd || exit 1
    authargs="$(registryLogin)"
    cmd="$DOCKER_PUSH $authargs $IMG_REPO:$IMAGE_TAG"
    echo "$cmd"; eval "$cmd"
    cd ..
fi
if [ -z "$buildOnly" ]; then
    setRegistryAccessForPulling
    create_dbuser scichat
    echo "Deploying to Kubernetes"
    cmd="helm install scichat-loopback scichat --namespace $NS --set image.tag=$IMAGE_TAG \\
            --set image.repository=$IMG_REPO  --set service.type=ClusterIP \\
            ${IARGS}"
    (echo "$cmd" && eval "$cmd")
fi
registryLogout

# vim: set ts=4 sw=4 sts=4 tw=0 et:
