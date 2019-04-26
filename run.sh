#!/bin/bash

kubectl delete -f mongo.yaml
kubectl delete -f rabbit.yaml

NS_DIR=./namespaces/*.yaml

if [ "$(uname)" == "Darwin" ]; then
        LOCAL_IP=`ipconfig getifaddr en0`
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
        LOCAL_IP=`hostname --ip-address`
fi
# using minikube
eval $(minikube docker-env)

LOCAL_IP=docker.local
DOCKER_REPO="$LOCAL_IP:5000"
KAFKA=0 

while getopts 'fhkd:' flag; do
  case "${flag}" in
    d) DOCKER_REPO=${OPTARG} ;;
    h) echo "-d for Docker Repo prefix"; exit 1 ;;
    k) KAFKA=1 ;;
    f) FILESERVER=1 ;;
  esac
done

CATANIE_REPO=$DOCKER_REPO/catanie
CATAMEL_REPO=$DOCKER_REPO/catamel

echo $CATANIE_REPO

helm del --purge local-mongodb 2> /dev/null
helm del --purge local-rabbit 2> /dev/null
helm del --purge local-node 2> /dev/null
if [[ "KAFKA" -eq "1" ]]; then
  helm del --purge local-kafka 2> /dev/null
fi

for file in $NS_DIR; do
  f="$(basename $file)"
  ns="${f%.*}"
  kubectl create -f $file
  export LOCAL_ENV="$ns"
  kubectl apply -f mongo.yaml
  helm install stable/mongodb --version 0.4.15 --namespace $LOCAL_ENV --name local-mongodb
  if [[ "KAFKA" -eq "1" ]]; then
    helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
    helm install --name local-kafka incubator/kafka --namespace $LOCAL_ENV
  fi
  kubectl apply -f rabbit.yaml
  helm install stable/rabbitmq --version 0.6.3 --namespace $LOCAL_ENV --name local-rabbit --set rabbitmqUsername=admin,rabbitmqPassword=admin
  helm install services/node-red --namespace $LOCAL_ENV --name local-node
done
./secret.sh

# Deploy services

SERVICES_DIR=./services/*/*.sh

for file in $SERVICES_DIR; do
  read -p "Press <enter> to deploy the next service: $file (any input skips)" answer
  [ -z "$answer" ] || continue
  bash $file $LOCAL_IP $CATANIE_REPO $CATAMEL_REPO $DOCKER_REPO/fs $DOCKER_REPO/ls
done

# vim: set ts=4 sw=4 sts=4 tw=0 et:
