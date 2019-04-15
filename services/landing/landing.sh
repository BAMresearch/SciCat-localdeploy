#!/usr/bin/env bash
envarray=(dev)

REPO="https://github.com/SciCatProject/LandingPageServer.git"
cd ./services/landing/

INGRESS_NAME=" "
DOCKERNAME="-f ./Dockerfile"
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
  envarray=(dmsc)
  INGRESS_NAME="-f ./landingserver/dmsc.yaml"
  DOCKERNAME="-f ./CI/ESS/Dockerfile.dmsc"
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
  envarray=(ess)
  INGRESS_NAME="-f ./landingserver/lund.yaml"
  DOCKERNAME="-f ./CI/ESS/Dockerfile.ess"
elif  [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
  envarray=(dmscprod)
  INGRESS_NAME="-f ./landingserver/dmscprod.yaml"
  DOCKERNAME="-f ./CI/ESS/Dockerfile.dmscprod"
else
  envarray=(dev)
  YAMLFN="./landingserver/$(hostname).yaml"
  INGRESS_NAME="-f $YAMLFN"
  # generate yaml file with appropriate hostname here
  cat > "$YAMLFN" << EOF
ingress:
  enabled: true
  host: landing.$(hostname).local
EOF
fi

echo $1

export LOCAL_ENV="${envarray[i]}"
echo $LOCAL_ENV
helm del --purge landingserver
if [ -d "./component/" ]; then
  cd component
  git pull
else
  git clone $REPO component
  cd component
fi
export LANDING_IMAGE_VERSION=$(git rev-parse HEAD)
echo $DOCKERNAME
if  [ "$(hostname)" != "k8-lrg-serv-prod.esss.dk" ]; then
  docker build $DOCKERNAME . -t $5:$LANDING_IMAGE_VERSION$LOCAL_ENV
  docker push $5:$LANDING_IMAGE_VERSION$LOCAL_ENV
echo "Deploying to Kubernetes"
cd ..
pwd
echo helm install landingserver --name landingserver --namespace $LOCAL_ENV --set image.tag=$LANDING_IMAGE_VERSION$LOCAL_ENV --set image.repository=$5 ${INGRESS_NAME}
helm install landingserver --name landingserver --namespace $LOCAL_ENV --set image.tag=$LANDING_IMAGE_VERSION$LOCAL_ENV --set image.repository=$5 ${INGRESS_NAME}
# envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false

