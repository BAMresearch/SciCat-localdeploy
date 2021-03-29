#!/bin/sh

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/../deploytools"

# get given command line flags
noBuild="$(getScriptFlags nobuild "$@")"
buildOnly="$(getScriptFlags buildonly "$@")"
clean="$(getScriptFlags clean "$@")"

loadSiteConfig
checkVars SC_CATAMEL_FQDN SC_CATAMEL_PUB SC_CATAMEL_KEY SC_REGISTRY_ADDR SC_NAMESPACE || exit 1

REPO=https://github.com/SciCatProject/catamel.git

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

cd "$scriptdir"

if [ -z "$buildOnly" ]; then
    # remove the existing service
    helm del catamel -n "$NS"
    kubectl -n $NS delete secret certs-catamel
    [ -z "$clean" ] || exit 0 # stop here when cleaning up

    IARGS="--set ingress.enabled=true,ingress.host=$SC_CATAMEL_FQDN,ingress.tlsSecretName=certs-catamel"
    createTLSsecret "$NS" certs-catamel "$SC_CATAMEL_PUB" "$SC_CATAMEL_KEY"
    # make sure DB credentials exist before starting any services
    gen_catamel_credentials "$SC_SITECONFIG"
    [ -d "$SC_SITECONFIG/catamel" ] && cp "$SC_SITECONFIG/catamel"/* "$scriptdir/dacat-api-server/config/"
fi

IMG_REPO="$SC_REGISTRY_ADDR/catamel"
baseurl="$SC_REGISTRY_ADDR"
# extra arguments if the registry need authentication as indicated by a set password
[ -z "$SC_REGISTRY_PASS" ] || baseurl="$SC_REGISTRY_USER:$SC_REGISTRY_PASS@$baseurl"
IMAGE_TAG="$(curl -s "https://$baseurl/v2/catamel/tags/list" | jq -r .tags[0])"
if [ -z "$noBuild" ] || [ -z "$IMAGE_TAG" ]; then
    if [ ! -d "./component/" ]; then
        git clone $REPO component
    fi
    cd component/
    git checkout develop
    git checkout .
    git pull
    # adjustments for older versions of nodejs build env
    # (such as 10.19 + node-gyp 5.1, not needed for node 10.24 with node-gyp 6.1)
    fix_nan_package_version
    # using the ESS Dockerfile without ESS specific stuff
    cp CI/ESS/Dockerfile .
    # https://stackoverflow.com/questions/54428608/docker-node-alpine-image-build-fails-on-node-gyp#59538284
    sed -i -e '/COPY .*CI\/ESS/d' \
        -e '/FROM/s/^.*$/FROM node:15.1-alpine/' \
        -e '/RUN apk/a\    apk add --no-cache python make g++ && \\' \
        Dockerfile
    echo '*.json-sample' >> .dockerignore

    npm install
    echo "Building release"
    IMAGE_TAG="$(git rev-parse HEAD)$NS"
    cmd="$DOCKER_BUILD -t $IMG_REPO:$IMAGE_TAG -t $IMG_REPO:latest ."
    echo "$cmd"; eval $cmd
    # extra arguments if the registry need authentication as indicated by a set password
    [ -z "$SC_REGISTRY_PASS" ] || pushargs="--creds \$SC_REGISTRY_USER:\$SC_REGISTRY_PASS"
    cmd="$DOCKER_PUSH $pushargs $IMG_REPO:$IMAGE_TAG"
    echo "$cmd"; eval "$cmd"
    [ -z "$buildOnly" ] || exit 0
    cd ..
fi
create_dbuser catamel
echo "Deploying to Kubernetes"
cmd="helm install catamel dacat-api-server --namespace $NS --set image.tag=$IMAGE_TAG --set image.repository=$IMG_REPO ${IARGS}"
(echo "$cmd" && eval "$cmd")
[ -d component ] && reset_envfiles component/server
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
