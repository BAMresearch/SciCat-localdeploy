#!/bin/bash

export REPO=https://github.com/SciCatBAM/catanie.git
envarray=(bam2) # selects angular configuration in subrepo component
cd ./services/catanie/

INGRESS_NAME=" "
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
  envarray=(dmsc)
  INGRESS_NAME="-f ./dacat-gui/dmsc.yaml"
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
  envarray=(ess)
  INGRESS_NAME="-f ./dacat-gui/lund.yaml"
elif  [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
  envarray=(dmscprod)
  INGRESS_NAME="-f ./dacat-gui/dmscprod.yaml"
else
  YAMLFN="./dacat-gui/$(hostname).yaml"
  INGRESS_NAME="-f $YAMLFN"
  # generate yaml file with appropriate hostname here
  cat > "$YAMLFN" << EOF
ingress:
  enabled: true
  host:  catanie.$(hostname).local
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
  helm del --purge catanie
  if [ -d "./component/" ]; then
    cd component/
    git checkout develop
    git pull
    ./CI/ESS/copyimages.sh
    if  [ "$(hostname)" != "k8-lrg-serv-prod.esss.dk" ]; then
      npm install
      ./node_modules/@angular/cli/bin/ng build --configuration $LOCAL_ENV --output-path dist/$LOCAL_ENV
    fi
  else
    git clone $REPO component
    cd component/
    git checkout develop
    git pull
    npm install
    ./CI/ESS/copyimages.sh
    echo "Building release"
    if  [ "$(hostname)" != "k8-lrg-serv-prod.esss.dk" ]; then
      npm install
      ./node_modules/@angular/cli/bin/ng build --configuration $LOCAL_ENV --output-path dist/$LOCAL_ENV
    fi
  fi
  echo STATUS:
  kubectl cluster-info
  export CATANIE_IMAGE_VERSION=$(git rev-parse HEAD)
  if  [ "$(hostname)" != "k8-lrg-serv-prod.esss.dk" ]; then
    cmd="docker build -t $2:$CATANIE_IMAGE_VERSION$LOCAL_ENV -t $2:latest --build-arg env=$LOCAL_ENV ."
    echo "$cmd"; eval $cmd
    cmd="docker push $2:$CATANIE_IMAGE_VERSION$LOCAL_ENV"
    echo "$cmd"; eval $cmd
  fi
  echo "Deploying to Kubernetes"
  cd ..
  helm install dacat-gui --name catanie --namespace $LOCAL_ENV --set image.tag=$CATANIE_IMAGE_VERSION$LOCAL_ENV --set image.repository=$2 ${INGRESS_NAME}
  echo helm install dacat-gui --name catanie --namespace $LOCAL_ENV --set image.tag=$CATANIE_IMAGE_VERSION$LOCAL_ENV --set image.repository=$2
done
