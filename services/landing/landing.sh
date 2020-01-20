#!/usr/bin/env bash

source ./services/deploytools
REPO="https://github.com/SciCatProject/LandingPageServer.git"
envarray=($KUBE_NAMESPACE) # selects angular configuration in subrepo component
cd ./services/landing/

INGRESS_NAME=" "
DOCKERNAME="-f ./Dockerfile"
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
    envarray=(dmsc)
    INGRESS_NAME="-f ./landingserver/dmsc.yaml"
    DOCKERNAME="-f ./CI/ESS/Dockerfile.dmsc"
elif    [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
    envarray=(ess)
    INGRESS_NAME="-f ./landingserver/lund.yaml"
    DOCKERNAME="-f ./CI/ESS/Dockerfile.ess"
elif    [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
    envarray=(dmscprod)
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

read -r -d '' angEnv <<EOF
export const environment = {
    production: true,
    lbBaseURL: "http://$(hostname --fqdn):3000",
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

read -r -d '' angCfg2 <<EOF
{
    "fileReplacements": [ {
        "replace": "src/environments/environment.ts",
        "with": \$envfn } ]
}
EOF

export LOCAL_ENV="${envarray[i]}"
echo $LOCAL_ENV

helm del --purge landingserver
if [ ! -d "./component/" ]; then
    git clone $REPO component
fi
cd component
git checkout . # revert any changes so that pull succeeds
git pull
git checkout -f develop
git clean -f
# update angular config
injectEnvConfig LandingPageServer "$LOCAL_ENV" "$angEnv" "$angCfg" "$angCfg2"

# using ESS Dockerfile and modify it to our needs
# using Alpine v12 due to this error: https://stackoverflow.com/q/52196518
grep -v '^$' CI/ESS/Dockerfile.dmscprod \
    | grep -v proxy \
    | grep -v 'npm config set' \
    | grep -v 'COPY CI/ESS/' \
    | sed -e '/LB_BASE_URL=/ s#\(http://\)[^\]\+\(/.*\)#\1'$hostaddr:3000'\2#' \
          -e "/RUN ng build/ s/dmscprod/$LOCAL_ENV/g" \
          -e '/mhart\/alpine/ s#\(alpine-node:\)[0-9]\+#\112#' \
    > Dockerfile

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
    local bannersrc; bannersrc="$(find $mediaPath -maxdepth 1 -iname '*banner*.png' | head -n1)"
    local favicon="$mediaPath/favicon.ico"
    [ -f "$bannersrc" ] && cp "$bannersrc" src/assets/site_banner.png
    [ -f "$favicon" ] && cp "$favicon" src/favicon.ico
}

export LANDING_IMAGE_VERSION=$(git rev-parse HEAD)
echo $DOCKERNAME
copyimages
if [ "$(hostname)" != "k8-lrg-serv-prod.esss.dk" ]; then
    cmd="docker build $DOCKERNAME . -t $5:$LANDING_IMAGE_VERSION$LOCAL_ENV"
    echo "$cmd"; eval $cmd
    cmd="docker push $5:$LANDING_IMAGE_VERSION$LOCAL_ENV"
    echo "$cmd"; eval $cmd
fi
echo "Deploying to Kubernetes"
cd ..
pwd
cmd="helm install landingserver --name landingserver --namespace $LOCAL_ENV \
    --set image.tag=$LANDING_IMAGE_VERSION$LOCAL_ENV --set image.repository=$5 ${INGRESS_NAME}"
echo "$cmd"; eval $cmd
# envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false

# vim: set ts=4 sw=4 sts=4 tw=0 et:
