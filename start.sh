#!/bin/bash

if [ "$(uname)" == "Darwin" ]; then
        LOCAL_IP=`ipconfig getifaddr en0`
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
        LOCAL_IP=`hostname --ip-address`
fi
echo $LOCAL_IP
#minikube start -v7  --insecure-registry localhost:5000 --extra-config=apiserver.GenericServerRunOptions.AuthorizationMode=RBAC

minikube start --insecure-registry docker.local:5000
#kubectl config use-context minikube #should auto set, but added in case

#kubectl -n kube-system create sa tiller # handled by rbac-config.yaml
kubectl create -f rbac-config.yaml
helm init --service-account tiller
helm repo update
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
sleep 5

kubectl apply -f service-nodeport.yaml
kubectl apply -f configmap.yaml


NS_DIR=./namespaces/*.yaml

for file in $NS_DIR; do
  f="$(basename $file)"
  ns="${f%.*}"
  kubectl delete namespace $ns 2> /dev/null
done

# set up a local registry
# https://hackernoon.com/local-kubernetes-setup-with-minikube-on-mac-os-x-eeeb1cbdc0b
# let docker context point to minikube
eval $(minikube docker-env)
# start local docker registry
docker run -d -p 5000:5000 --restart=always --name registry registry:2
# https://stackoverflow.com/a/54190375
DNAME="docker.local"
IPADDR="$(minikube ip)"
sudo sed -i "/$DNAME/d" /etc/hosts
sudo sh -c "echo '$IPADDR\t$DNAME' >> /etc/hosts"
sudo service docker restart
