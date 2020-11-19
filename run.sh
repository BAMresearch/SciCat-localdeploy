#!/usr/bin/env bash

# get the script directory before creating any files
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
cd "$scriptdir"
. ./services/deploytools

export KUBE_NAMESPACE=yourns
NS_DIR=./namespaces/*.yaml

# using minikube
eval $(minikube docker-env)

LOCAL_IP=docker.local
DOCKER_REG="$LOCAL_IP:5000"
KAFKA=0 

while getopts 'fhkd:' flag; do
    case "${flag}" in
        d) DOCKER_REG=${OPTARG} ;;
        h) echo "-d for Docker Repo prefix"; exit 1 ;;
        k) KAFKA=1 ;;
        f) FILESERVER=1 ;;
    esac
done
# make sure following scripts know about our registry
export DOCKER_REG

answer=
[ "$1" = "nopause" ] || \
  read -p "Skip restarting base services (mongodb, rabbit, node)? [yN] " answer
if [ "$answer" != "y" ]; then
  kubectl delete -f mongo.yaml
  kubectl delete -f rabbit.yaml

  helm del --purge local-mongodb 2> /dev/null
  helm del --purge local-postgresql 2> /dev/null
  helm del --purge local-rabbit 2> /dev/null
  helm del --purge local-node 2> /dev/null
  if [[ "$KAFKA" -eq "1" ]]; then
    helm del --purge local-kafka 2> /dev/null
  fi
  # generate some passwords before starting any services
  mkdir -p siteconfig
  gen_catamel_credentials siteconfig
  gen_scichat_credentials siteconfig

  echo -n "Waiting for mongodb persistentvolume being removed ... "
  while kubectl -n dev get pv | grep -q mongo; do sleep 1; done
  echo "done."

  for file in $NS_DIR; do
    f="$(basename $file)"
    ns="${f%.*}"
    kubectl create -f $file
    export LOCAL_ENV="$ns"
    kubectl apply -f mongo.yaml
    mongocmd="helm install bitnami/mongodb --namespace $LOCAL_ENV --name local-mongodb"
    echo "$mongocmd"; eval $mongocmd
    kubectl apply -f postgres.yaml
    helm install bitnami/postgresql --namespace $LOCAL_ENV --name local-postgresql
    if [ "$KAFKA" == "1" ]; then
      helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
      helm install --name local-kafka incubator/kafka --namespace $LOCAL_ENV
    fi
    kubectl apply -f rabbit.yaml
    helm install bitnami/rabbitmq --namespace $LOCAL_ENV \
        --name local-rabbit --set rabbitmq.username=admin,rabbitmq.password=admin
    helm install stable/node-red --namespace $LOCAL_ENV --name local-node
  done
fi

[ "$1" = "nopause" ] || \
  read -p "Skip generating certificates? [yN] " answer
if [ "$answer" != "y" ]; then
    ./secret.sh "$KUBE_NAMESPACE"
fi

# Deploy services

SERVICES_DIR=./services/*/*.sh

for file in $SERVICES_DIR; do
    answer=
    [ "$1" = "nopause" ] || \
        read -p "Skip restarting $file? [yN] " answer
    [ "$answer" = "y" ] && continue
    echo "# Running now '$file' ..."
    bash "$file"
done

# vim: set ts=4 sw=4 sts=4 tw=0 et:
