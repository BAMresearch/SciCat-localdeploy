#!/bin/bash

source ./services/deploytools

[ -z "$DOCKER_REG" ] && \
    echo "WARNING: Docker registry not defined, using default (docker.io?)!"
docker_repo="$DOCKER_REG/scichat"

export REPO=https://github.com/SciCatProject/scichat-loopback.git
LOCAL_ENV=$KUBE_NAMESPACE # selects angular configuration in subrepo component
cd ./services/scichat-loopback/

INGRESS_NAME=" "
BUILD="true"
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
    INGRESS_NAME="-f ./scichat/dmsc.yaml"
    BUILD="false"
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
    INGRESS_NAME="-f ./scichat/lund.yaml"
    BUILD="false"
elif  [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
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

helm del scichat-loopback -n$env
if [ ! -d "./component" ]; then
    git clone $REPO component
fi
cd component
git checkout master
git checkout . # revert any changes so that pull succeeds
git clean -f
git pull
if  [ $BUILD = "true" ]; then
    echo "Building release"
    npm install
fi
sed -i -e "/npm config set/d" Dockerfile

export SCICHAT_IMAGE_VERSION=$(git rev-parse HEAD)
if  [ $BUILD = "true" ]; then
    cmd="docker build -t $docker_repo:$SCICHAT_IMAGE_VERSION$LOCAL_ENV -t $docker_repo:latest --build-arg env=$LOCAL_ENV ."
    echo "$cmd"; eval $cmd
    cmd="docker push $docker_repo:$SCICHAT_IMAGE_VERSION$LOCAL_ENV"
    echo "$cmd"; eval $cmd
fi
echo "Deploying to Kubernetes"
cd ..
update_envfiles scichat
create_dbuser scichat
helm install scichat-loopback scichat --namespace $LOCAL_ENV \
    --set image.tag=$SCICHAT_IMAGE_VERSION$LOCAL_ENV --set image.repository=$docker_repo ${INGRESS_NAME}
reset_envfiles scichat

# vim: set ts=4 sw=4 sts=4 tw=0 et:
