#!/bin/bash

export REPO=https://github.com/SciCatProject/catamel.git
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

  kubectl -ndev delete svc catamel-out
  kubectl -ndev expose deployment catamel-dacat-api-server-dev --name=catamel-out --type=NodePort
  oldrule="$(vboxmanage showvminfo minikube | grep 'NIC\s[0-9]\sRule' | awk '{print $6}' |tr -d ',' |grep catamel)"
  vboxmanage controlvm "minikube" natpf1 delete "$oldrule" 2> /dev/null
  rule="catamel-$LOCAL_ENV"
  nodeport="$(kubectl get service catamel-out -n$LOCAL_ENV -o yaml | awk '/nodePort/ {print $NF}')"
  vboxmanage controlvm "minikube" natpf1 "$rule,tcp,,3000,,$nodeport"
done

# vim: set ts=4 sw=4 sts=4 tw=0 et:
