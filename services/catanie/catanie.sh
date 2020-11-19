#!/usr/bin/env bash

source ./services/deploytools
if [ -z "$KUBE_NAMESPACE" ]; then
  echo "KUBE_NAMESPACE not defined!" >&2
  exit 1
fi
export env=$KUBE_NAMESPACE

[ -z "$DOCKER_REG" ] && \
    echo "WARNING: Docker registry not defined, using default (docker.io?)!"
docker_repo="$DOCKER_REG/catanie"

export REPO=https://github.com/SciCatProject/catanie.git
cd ./services/catanie/

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
  host:  $(hostname --fqdn)
EOF
fi

read -r -d '' angEnv <<EOF
export const environment = {
  production: true,
  lbBaseURL: "http://catamel.$(hostname --fqdn)",
  fileserverBaseURL: "http://files.$(hostname --fqdn)",
  externalAuthEndpoint: "/auth/msad",
  archiveWorkflowEnabled: true,
  editMetadataEnabled: true,
  columnSelectEnabled: true,
  editSampleEnabled: true,
  shoppingCartEnabled: true,
  facility: "BAM"
};
EOF

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
    local mediaPath="../../../media"
    if [ ! -d "$mediaPath" ]; then
        echo "No media/images found, not copying site specific media."
        return
    fi
    # get favicon
    local favicon="$mediaPath/favicon.ico"
    if [ ! -f "$favicon" ]; then
        (cd "$mediaPath" && convert src/icon.svg -define icon:auto-resize="64,48,32,16" favicon.ico)
    fi
    [ -f "$favicon" ] && cp "$favicon" src/favicon.ico
    mediaPath="$mediaPath/catanie"
    local logosrc; logosrc="$(find $mediaPath -maxdepth 1 -iname '*logo*.png' | head -n1)"
    [ -f "$logosrc" ] && cp "$logosrc" src/assets/images/esslogo.png
    local sitesrc; sitesrc="$(find $mediaPath -maxdepth 1 -iname '*site*.png' | grep -v banner | head -n1)"
    [ -f "$sitesrc" ] && cp "$sitesrc" src/assets/images/ess-site.png
}

#echo $1

#for ((i=0;i<${#envarray[@]};i++)); do
#export LOCAL_ENV="${envarray[i]}"
#export LOCAL_IP="$1"
#echo $LOCAL_ENV
helm del -n$env catanie
if [ ! -d "./component" ]; then
    git clone $REPO component
fi
cd component
git checkout develop
git checkout .
git clean -f
git pull
injectEnvConfig catanie $env "$angEnv" "$angCfg"
copyimages
if  [ "$BUILD" == "true" ]; then
    echo "Building release"
    npm install
    ./node_modules/@angular/cli/bin/ng build --configuration $env --output-path dist/$env
fi
echo STATUS:
kubectl cluster-info
export CATANIE_IMAGE_VERSION=$(git rev-parse HEAD)
if  [ "$BUILD" == "true" ]; then
    cmd="docker build -t $docker_repo:$CATANIE_IMAGE_VERSION$env -t $docker_repo:latest --build-arg env=$env ."
    echo "$cmd"; eval $cmd
    cmd="docker push $docker_repo:$CATANIE_IMAGE_VERSION$env"
    echo "$cmd"; eval $cmd
fi
export tag=$(git rev-parse HEAD)
echo "Deploying to Kubernetes"
cd ..
helm install catanie dacat-gui --namespace $env \
    --set image.tag=$CATANIE_IMAGE_VERSION$env --set image.repository=$docker_repo ${INGRESS_NAME}
exit 0
# disabled the lower part as we do not have a build server yet and don't use public repos

function docker_tag_exists() {
    curl --silent -f -lSL https://index.docker.io/v1/repositories/$1/tags/$2 > /dev/null
}

if docker_tag_exists dacat/catanie latest; then
    echo exists
    helm upgrade catanie-${env} dacat-gui --wait --recreate-pods --namespace=${env} --set image.tag=$tag$env ${INGRESS_NAME}
    helm history catanie-${env}
else
    echo not exists
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
