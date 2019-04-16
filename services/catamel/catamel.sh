#!/bin/bash

export REPO=https://github.com/SciCatBAM/catamel.git
envarray=(dev)
cd ./services/catamel/

INGRESS_NAME=" "
DOCKERNAME="-f ./Dockerfile"
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
  INGRESS_NAME="-f ./dacat-api-server/dmsc.yaml"
  DOCKERNAME="-f ./CI/ESS/Dockerfile.proxy"
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
  INGRESS_NAME="-f ./dacat-api-server/lund.yaml"
  DOCKERNAME="-f ./Dockerfile"
elif  [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
  INGRESS_NAME="-f ./dacat-api-server/dmscprod.yaml"
  DOCKERNAME="-f ./CI/ESS/Dockerfile.proxy"
else
  YAMLFN="./dacat-api-server/$(hostname).yaml"
  INGRESS_NAME="-f $YAMLFN"
  # generate yaml file with appropriate hostname here
  cat > "$YAMLFN" << EOF
ingress:
  enabled: true
  host:  catamel.$(hostname).local
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
    if cd server; then # activate default config files
	cp -n config.local.js-sample config.local.js
	cp -n datasources.json-sample datasources.json
	cp -n providers.json-sample providers.json
	cp -n functionalAccounts_example.json functionalAccounts.json
    fi
    if  [ "$(hostname)" != "k8-lrg-serv-prod.esss.dk" ]; then
      npm install
    fi
    echo "Building release"
  fi
  export CATAMEL_IMAGE_VERSION=$(git rev-parse HEAD)
  if  [ "$(hostname)" != "k8-lrg-serv-prod.esss.dk" ]; then
    cmd="docker build ${DOCKERNAME} -t $3:$CATAMEL_IMAGE_VERSION$LOCAL_ENV -t $3:latest ."
    echo "$cmd"; eval $cmd
    cmd="docker push $3:$CATAMEL_IMAGE_VERSION$LOCAL_ENV"
    echo "$cmd"; eval "$cmd"
  fi
  echo "Deploying to Kubernetes"
  cd ..
  helm install dacat-api-server --name catamel --namespace $LOCAL_ENV --set image.tag=$CATAMEL_IMAGE_VERSION$LOCAL_ENV --set image.repository=$3 ${INGRESS_NAME}
  # envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false

  kubectl expose deployment catamel-dacat-api-server-dev -ndev --name=catamel-out --type=NodePort
  rule="catamel-$LOCAL_ENV"
  vboxmanage controlvm "minikube" natpf1 delete "$rule" 2> /dev/null
  nodeport="$(kubectl get service catamel-out -ndev -o yaml | awk '/nodePort/ {print $NF}')"
  vboxmanage controlvm "minikube" natpf1 "$rule,tcp,,3000,,$nodeport"
done
