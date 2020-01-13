#!/usr/bin/env bash

source ./services/deploytools
if [ -z "$KUBE_NAMESPACE" ]; then
  echo "KUBE_NAMESPACE not defined!" >&2
  exit 1
fi
export env=$KUBE_NAMESPACE

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
  host:  catanie.$(hostname --fqdn)
EOF
fi

hostaddr="$(getHostAddr)"

read -r -d '' angEnv <<EOF
export const environment = {
  production: true,
  lbBaseURL: "http://$(hostname --fqdn):3000",
  fileserverBaseURL: "http://$(hostname --fqdn):8888",
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
      "with": \$envfn } ],
    "serviceWorker": true
  }
EOF

copyimages()
{
    if [ "$(basename $(pwd))" != component ]; then
        echo "$0 not in directory 'component', aborting!"
        return
    fi
    local mediaPath="$HOME/media/"
    if [ ! -d "$mediaPath" ]; then
        echo "No media/images found, not copying site specific media."
        return
    fi
    local logosrc; logosrc="$(find $mediaPath -maxdepth 1 -iname '*logo*.png' | head -n1)"
    local sitesrc; sitesrc="$(find $mediaPath -maxdepth 1 -iname '*site*.png' | grep -v banner | head -n1)"
    local favicon="$mediaPath/favicon.ico"
    [ -f "$logosrc" ] && cp "$logosrc" src/assets/images/esslogo.png
    [ -f "$sitesrc" ] && cp "$sitesrc" src/assets/images/ess-site.png
    [ -f "$favicon" ] && cp "$favicon" src/favicon.ico
}

#echo $1

#for ((i=0;i<${#envarray[@]};i++)); do
#export LOCAL_ENV="${envarray[i]}"
#export LOCAL_IP="$1"
#echo $LOCAL_ENV
helm del --purge catanie
if [ ! -d "./component" ]; then
    git clone $REPO component
fi
cd component
git checkout develop
git checkout .
git clean -f
git pull
injectEnvConfig catanie $env "$angEnv" "$angCfg"
./CI/ESS/copyimages.sh
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
    cmd="docker build -t $2:$CATANIE_IMAGE_VERSION$env -t $2:latest --build-arg env=$env ."
    echo "$cmd"; eval $cmd
    cmd="docker push $2:$CATANIE_IMAGE_VERSION$env"
    echo "$cmd"; eval $cmd
fi
export tag=$(git rev-parse HEAD)
echo "Deploying to Kubernetes"
cd ..
helm install dacat-gui --name catanie --namespace $env \
    --set image.tag=$CATANIE_IMAGE_VERSION$env --set image.repository=$2 ${INGRESS_NAME}
exit 0

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
