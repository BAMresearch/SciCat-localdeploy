#!/usr/bin/env bash

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/../deploytools"

loadSiteConfig
checkVars REGISTRY_ADDR KUBE_NAMESPACE LE_WORKING_DIR || exit 1

IMG_REPO="$REGISTRY_ADDR/catanie"
export REPO=https://github.com/SciCatProject/catanie.git
export NS=$KUBE_NAMESPACE

cd "$scriptdir"

INGRESS_NAME=" "
BUILD="true"
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
    INGRESS_NAME="-f ./dacat-gui/dmsc.yaml"
    BUILD="false"
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
    INGRESS_NAME="-f ./dacat-gui/lund.yaml"
    BUILD="false"
elif  [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
    INGRESS_NAME="-f ./dacat-gui/dmscprod.yaml"
    BUILD="false"
else
    YAMLFN="./dacat-gui/$(hostname).yaml"
    INGRESS_NAME="-f $YAMLFN"
    # generate yaml file with appropriate hostname here
    cat > "$YAMLFN" << EOF
ingress:
  enabled: true
  host: $DOMAINBASE
EOF
fi

read -r -d '' angCfg <<EOF
  {
    "optimization": true,
    "outputHashing": "all",
    "sourceMap": false,
    "extractCss": true,
    "namedChunks": false,
    "aot": true,
    "extractLicenses": true,
    "vendorChunk": false,
    "buildOptimizer": true,
    "fileReplacements": [ {
      "replace": "src/environments/environment.ts",
      "with": \$envfn } ]
  }
EOF

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

# Updating TLS certificates, assuming letsencrypt provided by acme.sh client
if [ ! -d "$LE_WORKING_DIR/$DOMAINBASE" ]; then
    echo "WARNING! Location for TLS certificates not found ('$LE_WORKING_DIR/$DOMAINBASE')."
else
    certpath="$LE_WORKING_DIR/$DOMAINBASE"
    kubectl -n $NS create secret tls certs-catanie \
        --cert="$certpath/fullchain.cer" --key="$certpath/$DOMAINBASE.key" \
        --dry-run=client -o yaml | kubectl apply -f -
fi

helm del catanie -n$NS

IMAGE_TAG="$(curl -s https://$REGISTRY_ADDR/v2/catamel/tags/list | jq -r .tags[0])"
if [ "$BUILD" = "true" ] || [ -z "$IMAGE_TAG" ]; then
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
        -e '/lbBaseURL:/s#[[:alnum:]"\:\./]\+,$#"http://api.'$DOMAINBASE'",#g' \
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

    injectEnvConfig catanie $NS "$angEnv" "$angCfg"
    copyimages

    npm install
    echo "Building release"
    ./node_modules/@angular/cli/bin/ng build --configuration $NS --output-path dist/$NS
    IMAGE_TAG="$(git rev-parse HEAD)$NS"
    cmd="$DOCKER_BUILD -t $IMG_REPO:$IMAGE_TAG -t $IMG_REPO:latest --build-arg NS=$NS ."
    echo "$cmd"; eval $cmd
    cmd="$DOCKER_PUSH $IMG_REPO:$IMAGE_TAG"
    echo "$cmd"; eval $cmd
    cd ..
fi
echo "Deploying to Kubernetes"
cmd="helm install catanie dacat-gui --namespace $NS --set image.tag=$IMAGE_TAG --set image.repository=$IMG_REPO ${INGRESS_NAME}"
(echo "$cmd" && eval "$cmd")

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
