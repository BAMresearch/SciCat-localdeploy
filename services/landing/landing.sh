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
git pull
git checkout -f develop
git clean -f
# update angular config
injectEnvConfig LandingPageServer "$LOCAL_ENV" "$angEnv" "$angCfg" "$angCfg2"

# use own Dockerfile
cat <<EOF > Dockerfile
    FROM mhart/alpine-node:8
    RUN mkdir /usr/html
    RUN mkdir /landing
    WORKDIR /landing
    COPY package.json .
    RUN npm install http-server -g
    RUN npm install -g @angular/cli
    RUN npm install
    COPY src src
    COPY angular.json .
    COPY tsconfig.json .
    COPY ngsw-config.json .
    COPY webpack.server.config.js .
    COPY server.ts .
    COPY karma.conf.js .
    ARG APP_PROD='true'
    ARG LB_BASE_URL='http://$hostaddr:3000/api'
    ARG LB_API_VERSION=''
    RUN ng build --configuration=$LOCAL_ENV && ng run LandingPageServer:server:$LOCAL_ENV && npm run webpack:server
    WORKDIR /landing/
    EXPOSE 4000
    CMD ["node", "dist/server.js"]
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

if true; then # forward service ports to the outside
    echo "Mapping service ports directly!"
    oldrule="$(vboxmanage showvminfo minikube | grep 'NIC\s[0-9]\sRule' \
        | awk '{print $6}' |tr -d ',' |grep landing)"
    vboxmanage controlvm "minikube" natpf1 delete "$oldrule" 2> /dev/null
    nodeport="$(kubectl get service landingserver-landingserver -n$LOCAL_ENV -o yaml \
        | awk '/nodePort/ {print $NF}')"
    rule="landing-$LOCAL_ENV"
    vboxmanage controlvm "minikube" natpf1 "$rule,tcp,,4000,,$nodeport"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
