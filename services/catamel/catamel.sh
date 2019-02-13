#!/bin/bash

export REPO=https://github.com/SciCatBAM/catamel.git
envarray=(dev)
cd ./services/catamel/

INGRESS_NAME=" "
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
  INGRESS_NAME="-f ./dacat-api-server/dmsc.yaml"
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
  INGRESS_NAME="-f ./dacat-api-server/lund.yaml"
elif  [ "$(hostname)" == "k8-lrg-prod.esss.dk" ]; then
  INGRESS_NAME="-f ./dacat-api-server/dmscprod.yaml"
else
  YAMLFN="./dacat-api-server/$(hostname).yaml"
  INGRESS_NAME="-f $YAMLFN"
  # generate yaml file with appropriate hostname here
  cat > "$YAMLFN" << EOF
ingress:
  enabled: true
  host:  catamel.debianvm.local
EOF
fi

echo $1

for ((i=0;i<${#envarray[@]};i++)); do
  export LOCAL_ENV="${envarray[i]}"
  export LOCAL_IP="$1"
  echo $LOCAL_ENV
  helm del --purge catamel
  if [ -d "./component/" ]; then
    cd component/
    git checkout develop
    git pull 
  else
    git clone $REPO component
    cd component/
    git checkout develop
    npm install
    echo "Building release"
  fi
  export CATAMEL_IMAGE_VERSION=$(git rev-parse HEAD)
  docker build -t $3:$CATAMEL_IMAGE_VERSION$LOCAL_ENV -t $3:latest .
  echo docker build -t $3:$CATAMEL_IMAGE_VERSION$LOCAL_ENV -t $3:latest .
  docker push $3:$CATAMEL_IMAGE_VERSION$LOCAL_ENV
  echo docker push $3:$CATAMEL_IMAGE_VERSION$LOCAL_ENV
  echo "Deploying to Kubernetes"
  cd ..
  helm install dacat-api-server --name catamel --namespace $LOCAL_ENV --set image.tag=$CATAMEL_IMAGE_VERSION$LOCAL_ENV --set image.repository=$3 ${INGRESS_NAME}
  # envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false
done
