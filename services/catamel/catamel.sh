#!/usr/bin/env bash

if [ -z "$KUBE_NAMESPACE" ]; then
  echo "KUBE_NAMESPACE not defined!" >&2
  exit 1
fi
export env=$KUBE_NAMESPACE

export REPO=https://github.com/SciCatProject/catamel.git
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

fix_nan_package_version()
{
    nan_json="$(mktemp)"
    curl -s https://registry.npmjs.org/nan/ > "$nan_json"
    nan_ver="$(jq '."dist-tags".latest' "$nan_json")"
    nan_url="$(jq ".versions.$nan_ver.dist.tarball" "$nan_json")"
    nan_sha="$(jq ".versions.$nan_ver.dist.integrity" "$nan_json")"
    dep_path='.dependencies."loopback-connector-kafka".dependencies'
    jq --indent 4 \
       "$dep_path.nan.version = $nan_ver \
      | $dep_path.nan.resolved = $nan_url \
      | $dep_path.nan.integrity = $nan_sha \
      | $dep_path.snappy.requires.nan = $nan_ver" package-lock.json > "$nan_json"
    mv "$nan_json" package-lock.json
    chmod 644 package-lock.json
}

helm del --purge catamel
if [ ! -d "./component/" ]; then
    git clone $REPO component
fi
cd component/
git checkout develop
git checkout .
git pull
fix_nan_package_version
# using the ESS Dockerfile without ESS specific stuff
cp CI/ESS/Dockerfile .
sed -i -e '/COPY CI\/ESS/d' Dockerfile
if  [ "$BUILD" == "true" ]; then
    npm install
fi
echo "Building release"
export CATAMEL_IMAGE_VERSION=$(git rev-parse HEAD)
if  [ "$BUILD" == "true" ]; then
    cmd="docker build ${DOCKERNAME} -t $3:$CATAMEL_IMAGE_VERSION$env -t $3:latest ."
    echo "$cmd"; eval $cmd
    cmd="docker push $3:$CATAMEL_IMAGE_VERSION$env"
    echo "$cmd"; eval "$cmd"
fi
tag=$(git rev-parse HEAD)
echo "Deploying to Kubernetes"
cd ..
helm install dacat-api-server --name catamel --namespace $env \
    --set image.tag=$CATAMEL_IMAGE_VERSION$env --set image.repository=$3 ${INGRESS_NAME}
exit 0

function docker_tag_exists() {
    curl --silent -f -lSL https://index.docker.io/v1/repositories/$1/tags/$2 > /dev/null
}

if docker_tag_exists dacat/catamel $CATAMEL_IMAGE_VERSION$env; then
    echo exists
    #helm install dacat-api-server --name catamel --namespace $env --set image.tag=$CATAMEL_IMAGE_VERSION$env --set image.repository=$3 ${INGRESS_NAME}
    helm upgrade dacat-api-server-${env} dacat-api-server --namespace=${env} --set image.tag=$tag
    helm history catamel-${env}
    echo "To roll back do: helm rollback --wait --recreate-pods dacat-api-server-${env} revision-number"
else
    echo not exists
fi
# envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false

# vim: set ts=4 sw=4 sts=4 tw=0 et:
