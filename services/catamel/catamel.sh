#!/bin/sh

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/../deploytools"

# get given command line flags
noBuild="$(getScriptFlags nobuild "$@")"
buildOnly="$(getScriptFlags buildonly "$@")"
clean="$(getScriptFlags clean "$@")"

loadSiteConfig
checkVars REGISTRY_ADDR SC_NAMESPACE LE_WORKING_DIR || exit 1

REPO=https://github.com/SciCatProject/catamel.git

cd "$scriptdir"

if [ -z "$buildOnly" ]; then
    # remove the existing service
    helm del catamel -n "$NS"
    kubectl -n $NS delete secret certs-catamel
    [ -z "$clean" ] || exit 0 # stop here when cleaning up

    DOCKERNAME="-f ./Dockerfile"
    YAMLFN="./dacat-api-server/$NS.yaml"
    IARGS="-f $YAMLFN"
    # generate yaml file with appropriate hostname here
    cat > "$YAMLFN" << EOF
ingress:
  enabled: true
  host: $SC_CATAMEL_FQDN
EOF

    # Updating TLS certificates, assuming letsencrypt provided by acme.sh client
    if [ ! -d "$LE_WORKING_DIR/$DOMAINBASE" ]; then
        echo "WARNING! Location for TLS certificates not found ('$LE_WORKING_DIR/$DOMAINBASE')."
    else
        certpath="$LE_WORKING_DIR/$DOMAINBASE"
        kubectl -n $NS create secret tls certs-catamel \
            --cert="$certpath/fullchain.cer" --key="$certpath/$DOMAINBASE.key" \
            --dry-run=client -o yaml | kubectl apply -f -
    fi

    # make sure DB credentials exist before starting any services
    gen_catamel_credentials "$SC_SITECONFIG"
fi

IMG_REPO="$REGISTRY_ADDR/catamel"
baseurl="$REGISTRY_ADDR"
# extra arguments if the registry need authentication as indicated by a set password
[ -z "$REGISTRY_PASS" ] || baseurl="$REGISTRY_USER:$REGISTRY_PASS@$baseurl"
IMAGE_TAG="$(curl -s "https://$baseurl/v2/catamel/tags/list" | jq -r .tags[0])"
if [ -z "$noBuild" ] || [ -z "$IMAGE_TAG" ]; then
    if [ ! -d "./component/" ]; then
        git clone $REPO component
    fi
    cd component/
    git checkout develop
    git checkout .
    git pull
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
    # extra arguments if the registry need authentication as indicated by a set password
    [ -z "$REGISTRY_PASS" ] || pushargs="--creds \$REGISTRY_USER:\$REGISTRY_PASS"
    cmd="$DOCKER_PUSH $pushargs $IMG_REPO:$IMAGE_TAG"
    echo "$cmd"; eval "$cmd"
    [ -z "$buildOnly" ] || exit 0
    cd .. && create_dbuser catamel
fi
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
