#!/bin/sh

source ./services/deploytools
if [ -z "$KUBE_NAMESPACE" ]; then
  echo "KUBE_NAMESPACE not defined!" >&2
  exit 1
fi
export NS=$KUBE_NAMESPACE

[ -z "$DOCKER_REG" ] && \
    echo "WARNING: Docker registry not defined, using default (docker.io?)!"
docker_repo="$DOCKER_REG/catamel"

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

# remove the existing service
helm del catamel -n$NS

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
# https://stackoverflow.com/questions/54428608/docker-node-alpine-image-build-fails-on-node-gyp#59538284
sed -i -e '/COPY .*CI\/ESS/d' \
    -e '/FROM/s/^.*$/FROM node:15.1-alpine/' \
    -e '/RUN apk/a\    apk add --no-cache python make g++ && \\' \
    -e '/USER/a\USER node' \
    Dockerfile
echo '*.json-sample' >> .dockerignore
(cd ../.. && update_envfiles catamel component/server)
if  [ "$BUILD" == "true" ]; then
    npm install
fi
echo "Building release"
export CATAMEL_IMAGE_VERSION=$(git rev-parse HEAD)
if  [ "$BUILD" == "true" ]; then
    cmd="$DOCKER_BUILD ${DOCKERNAME} -t $docker_repo:$CATAMEL_IMAGE_VERSION$NS -t $docker_repo:latest ."
    echo "$cmd"; eval $cmd
    cmd="$DOCKER_PUSH $docker_repo:$CATAMEL_IMAGE_VERSION$NS"
    echo "$cmd"; eval "$cmd"
fi
create_dbuser catamel
echo "Deploying to Kubernetes"
cmd="helm install catamel dacat-api-server --namespace $NS --set image.tag=$CATAMEL_IMAGE_VERSION$NS --set image.repository=$docker_repo ${INGRESS_NAME}"
(cd .. && echo "$cmd" && eval "$cmd")
reset_envfiles server
exit 0
# disabled the lower part as we do not have a build server yet and don't use public repos

function docker_tag_exists() {
    curl --silent -f -lSL https://index.docker.io/v1/repositories/$1/tags/$2 > /dev/null
}

tag=$(git rev-parse HEAD)
if docker_tag_exists dacat/catamel $CATAMEL_IMAGE_VERSION$NS; then
    echo exists
    helm upgrade dacat-api-server-${NS} dacat-api-server --namespace=${NS} --set image.tag=$tag
    helm history catamel-${NS}
    echo "To roll back do: helm rollback --wait --recreate-pods dacat-api-server-${NS} revision-number"
else
    echo not exists
fi
# envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false

# vim: set ts=4 sw=4 sts=4 tw=0 et:
