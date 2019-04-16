#!/bin/bash

REPO="https://github.com/garethcmurphy/minitornado.git"
envarray=(dev)

echo $1

export LOCAL_ENV="${envarray[i]}"
echo $LOCAL_ENV
helm del --purge fileserver
cd services/fileserver/
if [ -d "./component/" ]; then
  cd component
  git pull
else
  git clone $REPO component
  cd component
fi
export FILESERVER_IMAGE_VERSION=$(git rev-parse HEAD)
eval $(minikube docker-env)
docker build . -t $4:$FILESERVER_IMAGE_VERSION$LOCAL_ENV
docker push $4:$FILESERVER_IMAGE_VERSION$LOCAL_ENV
echo "Deploying to Kubernetes"
cd ..
cd ..
pwd
echo helm install fileserver --name fileserver --namespace $LOCAL_ENV --set image.tag=$FILESERVER_IMAGE_VERSION$LOCAL_ENV --set image.repository=$4
helm install fileserver --name fileserver --namespace $LOCAL_ENV --set image.tag=$FILESERVER_IMAGE_VERSION$LOCAL_ENV --set image.repository=$4
# envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false



