#!/usr/bin/env bash

# get the script directory before creating any files
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
cd "$scriptdir"
. ./services/deploytools

export KUBE_NAMESPACE=yourns
# make sure this namespace exists
kubectl create namespace $KUBE_NAMESPACE
NS_FILE=./namespaces/*.yaml
fn="$(basename $NS_FILE)"
ns="${fn%.*}"
kubectl create -f $NS_FILE
export LOCAL_ENV="$ns"

# using minikube
eval $(minikube docker-env)

LOCAL_IP=docker.local
DOCKER_REG="$LOCAL_IP:31000"
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

  helm del local-mongodb --namespace $LOCAL_ENV
  helm del local-postgresql --namespace $LOCAL_ENV
  helm del local-rabbit --namespace $LOCAL_ENV
  helm del local-node --namespace $LOCAL_ENV
  if [ "$KAFKA" == "1" ]; then
    helm del local-kafka
  fi
  # generate some passwords before starting any services
  mkdir -p siteconfig
  gen_catamel_credentials siteconfig
  gen_scichat_credentials siteconfig

  echo -n "Waiting for mongodb persistentvolume being removed ... "
  while kubectl -n $LOCAL_ENV get pv | grep -q mongo; do
      sleep 1;
      pvname="$(kubectl -n $LOCAL_ENV get pv | grep mongo | awk '{print $1}')"
      # https://github.com/kubernetes/kubernetes/issues/77258#issuecomment-502209800
      kubectl patch pv $pvname -p '{"metadata":{"finalizers":null}}'
      kubectl delete pv $pvname
  done
  echo "done."

  kubectl apply -f mongo.yaml
  mongocmd="helm install local-mongodb bitnami/mongodb --namespace $LOCAL_ENV"
  echo "$mongocmd"; eval $mongocmd
  kubectl apply -f postgres.yaml
  helm install local-postgresql bitnami/postgresql --namespace $LOCAL_ENV
  if [ "$KAFKA" == "1" ]; then
    helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
    helm install local-kafka incubator/kafka --namespace $LOCAL_ENV
  fi
  kubectl apply -f rabbit.yaml
  helm install local-rabbit bitnami/rabbitmq --namespace $LOCAL_ENV \
             --set rabbitmq.username=admin,rabbitmq.password=admin
  helm install local-node k8s-at-home/node-red --namespace $LOCAL_ENV
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
