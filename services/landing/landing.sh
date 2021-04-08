#!/bin/sh

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/../deploytools"

# get given command line flags
noBuild="$(getScriptFlags nobuild "$@")"
buildOnly="$(getScriptFlags buildonly "$@")"
clean="$(getScriptFlags clean "$@")"

loadSiteConfig
checkVars SC_LANDING_FQDN SC_LANDING_FQDN SC_LANDING_PUB SC_LANDING_KEY SC_REGISTRY_ADDR || exit 1

REPO="https://github.com/SciCatProject/LandingPageServer.git"

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
    if [ -f "$SC_MEDIA_PATH/src/icon.svg" ]; then
        convert "$SC_MEDIA_PATH/src/icon.svg" -resize 16 src/favicon-16x16.png
        convert "$SC_MEDIA_PATH/src/icon.svg" -resize 32 src/favicon-32x32.png
    fi
    if [ -f "$SC_MEDIA_PATH/src/logo.svg" ]; then
        convert "$SC_MEDIA_PATH/src/logo.svg" -resize 192 src/android-chrome-192x192.png
        convert "$SC_MEDIA_PATH/src/logo.svg" -resize 384 src/android-chrome-384x384.png
        convert "$SC_MEDIA_PATH/src/logo.svg" -resize 180 src/apple-touch-icon.png
        convert "$SC_MEDIA_PATH/src/logo.svg" -resize 150 src/mstile-150x150.png
        cp "$SC_MEDIA_PATH/src/logo.svg" src/safari-pinned-tab.svg
    fi
    mediaPath="$SC_MEDIA_PATH/landing"
    local bannersrc; bannersrc="$(find $mediaPath -maxdepth 1 -iname '*banner*.png' | head -n1)"
    [ -f "$bannersrc" ] && cp "$bannersrc" src/assets/site_banner.png
}

cd "$scriptdir"

if [ -z "$buildOnly" ]; then
    namespaceExists "$NS" || kubectl create ns "$NS"
    # remove the existing service
    helm del landingserver -n "$NS"
    kubectl -n $NS delete secret certs-landing
    [ -z "$clean" ] || exit 0 # stop here when cleaning up

    IARGS="--set ingress.enabled=true,ingress.host=$SC_LANDING_FQDN,ingress.tlsSecretName=certs-landing"
    createTLSsecret "$NS" certs-landing "$SC_LANDING_PUB" "$SC_LANDING_KEY"
fi

baseurl="$SC_REGISTRY_ADDR"
IMG_NAME="landing-$NS"
IMG_REPO="$baseurl/$IMG_NAME"
# extra arguments if the registry need authentication as indicated by a set password
[ -z "$SC_REGISTRY_PASS" ] || baseurl="$SC_REGISTRY_USER:$SC_REGISTRY_PASS@$baseurl"
# get the latest image tag: sort by timestamp, pick the largest
IMAGE_TAG="$(curl -s "https://$baseurl/v2/$IMG_NAME/tags/list" | jq -r '(.tags|sort[-1])?')"
if [ -z "$noBuild" ] || [ -z "$IMAGE_TAG" ]; then
    if [ ! -d "./component/" ]; then
        git clone $REPO component
    fi
    cd component
    git checkout develop
    git checkout .
    git clean -f
    git pull
    # update angular config
    angEnv=$(sed -e "/facility:/s/[[:alnum:]\"]\+,$/\"$SC_SITE_NAME\",/g" \
                 -e '/lbBaseURL:/s#[[:alnum:]"\:\./]\+,$#"https://'$SC_CATAMEL_FQDN'",#g' \
                 -e '/scicatBaseUrl:/s#[[:alnum:]"\:\./]\+,$#"https://'$SC_CATANIE_FQDN'",#g' \
                 src/environments/environment.essprod.ts)
    angBuildCfg="$(jq '.projects.LandingPageServer.architect.build.configurations.essprod' angular.json)"
    injectEnvConfig LandingPageServer "$NS" "$angEnv" "$angBuildCfg"
    copyimages
    sed -i -e "s#\\(<title>\\)\\w\\+\\(</title>\\)#\\1$SC_SITE_NAME\\2#" src/index.html
    echo "Building release"
    sed '/_proxy/d;/maintainer/d;/site.png/d;/google/d;s/^\(ARG\s\+env=\).*$/\1'$NS'/' \
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
    cmd="helm install landingserver landingserver --namespace $NS --set image.tag=$IMAGE_TAG \\
             --set image.repository=$IMG_REPO --set service.type=ClusterIP \\
             ${IARGS}"
    (echo "$cmd" && eval "$cmd")
fi
registryLogout

# vim: set ts=4 sw=4 sts=4 tw=0 et:
