#!/bin/bash

source ./services/deploytools
export REPO=https://github.com/SciCatProject/scichat-loopback.git
envarray=($KUBE_NAMESPACE) # selects angular configuration in subrepo component
cd ./services/scichat-loopback/

INGRESS_NAME=" "
BUILD="true"
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
    envarray=(dev)
    INGRESS_NAME="-f ./scichat/dmsc.yaml"
    BUILD="false"
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
    envarray=(dev)
    INGRESS_NAME="-f ./scichat/lund.yaml"
    BUILD="false"
elif  [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
    envarray=(dev)
    INGRESS_NAME="-f ./scichat/dmscprod.yaml"
    BUILD="false"
else
    YAMLFN="./scichat/$(hostname).yaml"
    INGRESS_NAME="-f $YAMLFN"
    # generate yaml file with appropriate hostname here
    cat > "$YAMLFN" << EOF
ingress:
  enabled: true
  host: scichat.$(hostname --fqdn)
EOF
fi

portarray=(30021 30023)
hostextarray=('-qa' '')
certarray=('discovery' 'discovery')
echo $1

for ((i=0;i<${#envarray[@]};i++)); do
    export LOCAL_ENV="${envarray[i]}"
    export PORTOFFSET="${portarray[i]}"
    export HOST_EXT="${hostextarray[i]}"
    export CERTNAME="${certarray[i]}"
    export LOCAL_IP="$1"
    echo $LOCAL_ENV $PORTOFFSET $HOST_EXT
    echo $LOCAL_ENV
    helm del --purge scichat-loopback
    if [ ! -d "./component" ]; then
        git clone $REPO component
    fi
    cd component
    git checkout develop
    git clean -f
    git pull
    if  [[ $BUILD == "true" ]]; then
        echo "Building release"
        npm install
    fi
    export SCICHAT_IMAGE_VERSION=$(git rev-parse HEAD)
    repo="dacat/scichat-loopback"
    if  [[ $BUILD == "true" ]]; then
        cmd="docker build -t ${repo}:$SCICHAT_IMAGE_VERSION$LOCAL_ENV -t ${repo}:latest --build-arg env=$LOCAL_ENV ."
	echo "$cmd"; eval $cmd
        cmd="docker push ${repo}:$SCICHAT_IMAGE_VERSION$LOCAL_ENV"
	echo "$cmd"; eval $cmd
    fi
    echo "Deploying to Kubernetes"
    cd ..
    helm install scichat --name scichat-loopback --namespace $LOCAL_ENV \
	--set image.tag=$SCICHAT_IMAGE_VERSION$LOCAL_ENV --set image.repository=${repo} ${INGRESS_NAME}
done

# vim: set ts=4 sw=4 sts=4 tw=0 et:
