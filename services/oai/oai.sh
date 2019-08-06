#!/bin/bash

source ./services/deploytools
export REPO=https://github.com/SciCatProject/oai-provider-service.git
envarray=($KUBE_NAMESPACE) # selects angular configuration in subrepo component
cd ./services/oai

INGRESS_NAME=" "
BUILD="true"
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
    envarray=(dmsc)
    INGRESS_NAME="-f ./oai/dmsc.yaml"
    BUILD="false"
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
    envarray=(ess)
    INGRESS_NAME="-f ./oai/lund.yaml"
    BUILD="false"
elif  [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
    envarray=(dmscprod)
    INGRESS_NAME="-f ./oai/dmscprod.yaml"
    BUILD="false"
else
    YAMLFN="./oai/$(hostname).yaml"
    INGRESS_NAME="-f $YAMLFN"
    # generate yaml file with appropriate hostname here
    cat > "$YAMLFN" << EOF
ingress:
  enabled: true
  host:  oai.$(hostname --fqdn)
EOF
fi

echo $1

for ((i=0;i<${#envarray[@]};i++)); do
    export LOCAL_ENV="${envarray[i]}"
    export LOCAL_IP="$1"
    echo $LOCAL_ENV $PORTOFFSET $HOST_EXT
    echo $LOCAL_ENV
    helm del --purge oai
    if [ ! -d "./component" ]; then
        git clone $REPO component
    fi
    cd component
    git checkout develop
    git clean -f
    git pull
    export OAI_IMAGE_VERSION=$(git rev-parse HEAD)
    echo "Deploying to Kubernetes"
    cd ..
    helm install oai --name oai --namespace $LOCAL_ENV \
	--set image.tag=$OAI_IMAGE_VERSION$LOCAL_ENV --set image.repository=$2 ${INGRESS_NAME}
done
