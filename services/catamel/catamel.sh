#!/bin/bash

export REPO=https://github.com/SciCatProject/catamel.git
envarray=(dev)
cd ./services/catamel/

INGRESS_NAME=" "
BUILD="true"
DOCKERNAME="-f ./Dockerfile"
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
    INGRESS_NAME="-f ./dacat-api-server/dmsc.yaml"
    DOCKERNAME="-f ./CI/ESS/Dockerfile.proxy"
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
    INGRESS_NAME="-f ./dacat-api-server/lund.yaml"
    DOCKERNAME="-f ./Dockerfile"
elif  [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
    INGRESS_NAME="-f ./dacat-api-server/dmscprod.yaml"
    DOCKERNAME="-f ./CI/ESS/Dockerfile.proxy"
else
    YAMLFN="./dacat-api-server/$(hostname).yaml"
    INGRESS_NAME="-f $YAMLFN"
    # generate yaml file with appropriate hostname here
    cat > "$YAMLFN" << EOF
ingress:
  enabled: true
  host:  catamel.$(hostname --fqdn)
EOF
fi

echo $1

fix_nan_package_version()
{
  nan_json="$(mktemp)"
  curl -s https://registry.npmjs.org/nan/ > "$nan_json"
  nan_ver="$(jq '."dist-tags".latest' "$nan_json")"
  nan_url="$(jq ".versions.$nan_ver.dist.tarball" "$nan_json")"
  nan_sha="$(jq ".versions.$nan_ver.dist.integrity" "$nan_json")"
  nan_path='.dependencies."loopback-connector-kafka".dependencies.nan'
  jq --indent 4 \
     "$nan_path.version = $nan_ver \
    | $nan_path.resolved = $nan_url \
    | $nan_path.integrity = $nan_sha" package-lock.json > "$nan_json"
  mv "$nan_json" package-lock.json
}

for ((i=0;i<${#envarray[@]};i++)); do
    export LOCAL_ENV="${envarray[i]}"
    export LOCAL_IP="$1"
    echo $LOCAL_ENV
    helm del --purge catamel
    if [ ! -d "./component/" ]; then
        git clone $REPO component
    fi
    cd component/
    git checkout develop
    git checkout .
    git pull
    fix_nan_package_version
    if  [ "$BUILD" == "true" ]; then
        npm install
    fi
    echo "Building release"
    export CATAMEL_IMAGE_VERSION=$(git rev-parse HEAD)
    if  [ "$BUILD" == "true" ]; then
        cmd="docker build ${DOCKERNAME} -t $3:$CATAMEL_IMAGE_VERSION$LOCAL_ENV -t $3:latest ."
        echo "$cmd"; eval $cmd
        cmd="docker push $3:$CATAMEL_IMAGE_VERSION$LOCAL_ENV"
        echo "$cmd"; eval "$cmd"
      fi
  echo "Deploying to Kubernetes"
  cd ..
  helm install dacat-api-server --name catamel --namespace $LOCAL_ENV \
      --set image.tag=$CATAMEL_IMAGE_VERSION$LOCAL_ENV --set image.repository=$3 ${INGRESS_NAME}
  # envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false
done

# vim: set ts=4 sw=4 sts=4 tw=0 et:
