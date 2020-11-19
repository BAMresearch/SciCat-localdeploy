#!/usr/bin/env bash

source ./services/deploytools

[ -z "$DOCKER_REG" ] && \
    echo "WARNING: Docker registry not defined, using default (docker.io?)!"
docker_repo="$DOCKER_REG/ls"

REPO="https://github.com/SciCatProject/LandingPageServer.git"
export LOCAL_ENV=$KUBE_NAMESPACE # selects angular configuration in subrepo component
cd ./services/landing/

INGRESS_NAME=" "
DOCKERNAME="-f ./Dockerfile"
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
    LOCAL_ENV=dmsc
    INGRESS_NAME="-f ./landingserver/dmsc.yaml"
    DOCKERNAME="-f ./CI/ESS/Dockerfile.dmsc"
elif    [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
    LOCAL_ENV=ess
    INGRESS_NAME="-f ./landingserver/lund.yaml"
    DOCKERNAME="-f ./CI/ESS/Dockerfile.ess"
elif    [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
    LOCAL_ENV=dmscprod
    INGRESS_NAME="-f ./landingserver/dmscprod.yaml"
    DOCKERNAME="-f ./CI/ESS/Dockerfile.dmscprod"
else
    YAMLFN="./landingserver/$(hostname).yaml"
    INGRESS_NAME="-f $YAMLFN"
    # generate yaml file with appropriate hostname here
    cat > "$YAMLFN" << EOF
ingress:
    enabled: true
    host: landing.$(hostname --fqdn)
EOF
fi

hostaddr="$(getHostAddr)"

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

helm del landingserver -n$env
if [ ! -d "./component/" ]; then
    git clone $REPO component
fi
cd component
git checkout . # revert any changes so that pull succeeds
git pull
git checkout -f develop
git clean -f
# update angular config
lbBaseURL="http://catamel.$(hostname --fqdn)"
angEnv=$(sed -e "/facility/ s/'[^']\+',/'BAM',/" \
             -e "/lbBaseURL/ s#'[^']\+',#'$lbBaseURL',#" \
             src/environments/environment.dmscprod.ts)
injectEnvConfig LandingPageServer "$LOCAL_ENV" "$angEnv" "$angCfg"

# using ESS Dockerfile and modify it to our needs
grep -v '^$' CI/ESS/Dockerfile.dmscprod \
    | grep -v proxy \
    | grep -v 'npm config set' \
    | grep -v 'COPY CI/ESS/' \
    | sed -e '/LB_BASE_URL=/ s#\(http://\)[^\]\+\(/.*\)#\1'$hostaddr:3000'\2#' \
          -e "/RUN ng build/ s/dmscprod/$LOCAL_ENV/" \
          -e "/ARG env/ s/env=\\s*[a-zA-Z0-9]\+/env=$LOCAL_ENV/" \
    > Dockerfile

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
    if [ -f "$mediaPath/src/icon.svg" ]; then
        convert "$mediaPath/src/icon.svg" -resize 16 src/favicon-16x16.png
        convert "$mediaPath/src/icon.svg" -resize 32 src/favicon-32x32.png
    fi
    if [ -f "$mediaPath/src/logo.svg" ]; then
        convert "$mediaPath/src/logo.svg" -resize 192 src/android-chrome-192x192.png
        convert "$mediaPath/src/logo.svg" -resize 384 src/android-chrome-384x384.png
        convert "$mediaPath/src/logo.svg" -resize 180 src/apple-touch-icon.png
        convert "$mediaPath/src/logo.svg" -resize 150 src/mstile-150x150.png
        cp "$mediaPath/src/logo.svg" src/safari-pinned-tab.svg
    fi
    mediaPath="$mediaPath/landing"
    local bannersrc; bannersrc="$(find $mediaPath -maxdepth 1 -iname '*banner*.png' | head -n1)"
    [ -f "$bannersrc" ] && cp "$bannersrc" src/assets/site_banner.png
}

export LANDING_IMAGE_VERSION=$(git rev-parse HEAD)
echo $DOCKERNAME
copyimages
if [ "$(hostname)" != "k8-lrg-serv-prod.esss.dk" ]; then
    cmd="docker build $DOCKERNAME . -t $docker_repo:$LANDING_IMAGE_VERSION$LOCAL_ENV"
    echo "$cmd"; eval $cmd
    cmd="docker push $docker_repo:$LANDING_IMAGE_VERSION$LOCAL_ENV"
    echo "$cmd"; eval $cmd
fi
echo "Deploying to Kubernetes"
cd ..
pwd
cmd="helm install landingserver landingserver --namespace $LOCAL_ENV \
    --set image.tag=$LANDING_IMAGE_VERSION$LOCAL_ENV --set image.repository=$docker_repo ${INGRESS_NAME}"
echo "$cmd"; eval $cmd
# envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false

# vim: set ts=4 sw=4 sts=4 tw=0 et:
