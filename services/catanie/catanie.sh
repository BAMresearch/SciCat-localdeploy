#!/bin/sh

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/../deploytools"

# get given command line flags
noBuild="$(getScriptFlags nobuild "$@")"
buildOnly="$(getScriptFlags buildonly "$@")"
clean="$(getScriptFlags clean "$@")"

loadSiteConfig
checkVars SC_CATAMEL_FQDN SC_CATANIE_FQDN SC_CATANIE_PUB SC_CATANIE_KEY SC_REGISTRY_ADDR || exit 1

REPO=https://github.com/SciCatProject/catanie.git

copyimages()
{
    if [ "$(basename $(pwd))" != component ]; then
        echo "$0 not in directory 'component', aborting!"
        return
    fi
    if [ ! -d "$SC_MEDIA_PATH" ]; then
        echo "No media/images found, not copying site specific media."
        return
    fi
    # get favicon
    local favicon="$SC_MEDIA_PATH/favicon.ico"
    if [ ! -f "$favicon" ]; then
        (cd "$SC_MEDIA_PATH" && convert src/icon.svg -define icon:auto-resize="64,48,32,16" favicon.ico)
    fi
    [ -f "$favicon" ] && cp "$favicon" src/favicon.ico
    local mediaPath="$SC_MEDIA_PATH/catanie"
    local logosrc; logosrc="$(find $mediaPath -maxdepth 1 -iname '*logo*.png' | head -n1)"
    [ -f "$logosrc" ] && cp "$logosrc" src/assets/images/esslogo.png
    local sitesrc; sitesrc="$(find $mediaPath -maxdepth 1 -iname '*site*.png' | grep -v banner | head -n1)"
    [ -f "$sitesrc" ] && cp "$sitesrc" src/assets/images/ess-site.png
}

cd "$scriptdir"

if [ -z "$buildOnly" ]; then
    namespaceExists "$NS" || kubectl create ns "$NS"
    # remove the existing service
    helm del catanie -n "$NS"
    kubectl -n $NS delete secret certs-catanie
    [ -z "$clean" ] || exit 0 # stop here when cleaning up

    IARGS="--set ingress.enabled=true,ingress.host=$SC_CATANIE_FQDN,ingress.tlsSecretName=certs-catanie"
    createTLSsecret "$NS" certs-catanie "$SC_CATANIE_PUB" "$SC_CATANIE_KEY"
fi

baseurl="$SC_REGISTRY_ADDR"
IMG_NAME="catanie-$NS"
IMG_REPO="$baseurl/$IMG_NAME"
# extra arguments if the registry need authentication as indicated by a set password
[ -z "$SC_REGISTRY_PASS" ] || baseurl="$SC_REGISTRY_USER:$SC_REGISTRY_PASS@$baseurl"
# get the latest image tag: sort by timestamp, pick the largest
IMAGE_TAG="$(curl -s "https://$baseurl/v2/$IMG_NAME/tags/list" | jq -r '(.tags|sort[-1])?')"
if [ -z "$noBuild" ] || [ -z "$IMAGE_TAG" ]; then
    if [ ! -d "./component" ]; then
        git clone $REPO component
    fi
    cd component
    git checkout develop
    git checkout .
    git clean -f
    git pull
    angEnv="$(sed \
        -e "/facility:/s/[[:alnum:]\"]\+,$/\"$SC_SITE_NAME\",/g" \
        -e '/lbBaseURL:/s#[[:alnum:]"\:\./]\+,$#"http://'$SC_CATAMEL_FQDN'",#g' \
        -e '/fileserverBaseURL:/s#[[:alnum:]"\:\./]\+,$#"http://files.'$DOMAINBASE'",#g' \
        -e '/landingPage:/s#[[:alnum:]"\:\./]\+,$#"http://landing.'$DOMAINBASE'",#g' \
        -e '/production:/s/\w\+,$/true,/g' \
        -e '/archiveWorkflowEnabled:/s/\w\+,$/false,/g' \
        -e '/synapseBaseUrl/d' \
        -e '/riotBaseUrl/d' \
        -e '/jupyterHubUrl/d' \
        -e '/sftpHost/d' \
        -e '/multipleDownloadAction/d' \
        -e '/externalAuthEndpoint/d' \
        src/environments/environment.ts)"
    angBuildCfg="$(jq '.projects.catanie.architect.build.configurations.dmscdev' angular.json \
        | jq 'del(.assets[-3:])|del(.stylePreprocessorOptions)|del(.styles[-1])')"
    injectEnvConfig catanie "$NS" "$angEnv" "$angBuildCfg"
    copyimages
    echo "Building release"
    sed '/_proxy/d;/maintainer/d;/site.png/d;/google/d;s/^\(ARG\s\+env=\).*$/\1bla/' \
        CI/ESS/Dockerfile.dmscprod > Dockerfile
    IMAGE_TAG="$(git show --format='%at_%h' HEAD)" # <timestamp>_<git commit>
    cmd="$DOCKER_BUILD -t $IMG_REPO:$IMAGE_TAG -t $IMG_REPO:latest --build-arg env=$NS ."
    echo "$cmd"; eval $cmd
    authargs="$(registryLogin)"
    cmd="$DOCKER_PUSH $authargs $IMG_REPO:$IMAGE_TAG"
    echo "$cmd"; eval $cmd
    cd ..
fi
if [ -z "$buildOnly" ]; then
    setRegistryAccessForPulling
    echo "Deploying to Kubernetes"
    cmd="helm install catanie dacat-gui --namespace $NS --set image.tag=$IMAGE_TAG \\
             --set image.repository=$IMG_REPO --set service.type=ClusterIP \\
             ${IARGS}"
    (echo "$cmd" && eval "$cmd")
fi
registryLogout

exit 0
# disabled the lower part as we do not have a build server yet and don't use public repos

function docker_tag_exists() {
    curl --silent -f -lSL https://index.docker.io/v1/repositories/$1/tags/$2 > /dev/null
}

if docker_tag_exists dacat/catanie latest; then
    echo exists
    helm upgrade catanie-${NS} dacat-gui --wait --recreate-pods --namespace=${NS} --set image.tag=$tag$NS ${INGRESS_NAME}
    helm history catanie-${NS}
else
    echo not exists
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
