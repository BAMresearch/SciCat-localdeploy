#!/bin/sh

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/services/deploytools"

checkVars REGISTRY_ADDR KUBE_NAMESPACE || exit 1

IMG_REPO="$REGISTRY_ADDR/catamel"
export REPO=https://github.com/SciCatProject/catamel.git
export NS=$KUBE_NAMESPACE

cd "$scriptdir/services/catamel"
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
  host:  api.$DOMAINBASE
EOF
fi

# Updating TLS certificates, assuming letsencrypt provided by acme.sh client
if [ ! -d "$LE_WORKING_DIR/$DOMAINBASE" ]; then
    echo "WARNING! Location for TLS certificates not found ('$LE_WORKING_DIR/$DOMAINBASE')."
else
    certpath="$LE_WORKING_DIR/$DOMAINBASE"
    kubectl -n $NS create secret tls certs-catamel \
        --cert="$certpath/fullchain.cer" --key="$certpath/$DOMAINBASE.key" \
        --dry-run=client -o yaml | kubectl apply -f -
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

if  [ "$BUILD" == "true" ]; then
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
        -e '/RUN apk/a\    apk add --no-cache python make g++ curl && \\' \
        -e '/USER/a\USER node' \
        Dockerfile
    echo '*.json-sample' >> .dockerignore
    (cd ../.. && update_envfiles catamel component/server)

    npm install
    echo "Building release"
    IMAGE_TAG="$(git rev-parse HEAD)$NS"
    cmd="$DOCKER_BUILD ${DOCKERNAME} -t $IMG_REPO:$IMAGE_TAG -t $IMG_REPO:latest ."
    echo "$cmd"; eval $cmd
    cmd="$DOCKER_PUSH $IMG_REPO:$IMAGE_TAG"
    echo "$cmd"; eval "$cmd"
    cd .. && create_dbuser catamel
else # BUILD == false
    IMAGE_TAG="$(curl -s https://$REGISTRY_ADDR/v2/catamel/tags/list | jq -r .tags[0])"
fi
echo "Deploying to Kubernetes"
cmd="helm install catamel dacat-api-server --namespace $NS --set image.tag=$IMAGE_TAG --set image.repository=$IMG_REPO ${INGRESS_NAME}"
(echo "$cmd" && eval "$cmd")
reset_envfiles component/server
exit 0
# this part is disabled as we do not have a build server yet and don't use public repos

function docker_tag_exists() {
    curl --silent -f -lSL https://index.docker.io/v1/repositories/$1/tags/$2 > /dev/null
}

tag=$(git rev-parse HEAD)
if docker_tag_exists dacat/catamel $IMAGE_TAG; then
    echo exists
    helm upgrade dacat-api-server-${NS} dacat-api-server --namespace=${NS} --set image.tag=$tag
    helm history catamel-${NS}
    echo "To roll back do: helm rollback --wait --recreate-pods dacat-api-server-${NS} revision-number"
else
    echo not exists
fi
# envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false

# vim: set ts=4 sw=4 sts=4 tw=0 et:
