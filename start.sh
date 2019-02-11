#!/bin/bash

if [ "$(uname)" == "Darwin" ]; then
        LOCAL_IP=`ipconfig getifaddr en0`
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
        LOCAL_IP=`hostname --ip-address`
fi
echo $LOCAL_IP
#minikube start -v7  --insecure-registry localhost:5000 --extra-config=apiserver.GenericServerRunOptions.AuthorizationMode=RBAC

minikube start --kubernetes-version=v1.11.0 --insecure-registry docker.local:5000
#kubectl config use-context minikube #should auto set, but added in case

#kubectl -n kube-system create sa tiller # handled by rbac-config.yaml
kubectl create -f rbac-config.yaml
helm init --service-account tiller
helm repo update
#kubectl apply -f ./deployments/registry.yaml
#kubectl apply -f ./deployments/ingress/nginx-controller.yaml
#curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/namespace.yaml | kubectl apply --validate=false -f -
#curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/default-backend.yaml | kubectl apply --validate=false -f -
#curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/configmap.yaml | kubectl apply --validate=false -f -
#curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/tcp-services-configmap.yaml | kubectl apply --validate=false -f -
#curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/udp-services-configmap.yaml | kubectl apply --validate=false -f -
#curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/rbac.yaml | kubectl apply --validate=false -f -
#curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/with-rbac.yaml | kubectl apply --validate=false -f -
for fn in ingress-nginx/*.yaml; do kubectl apply -f $fn; done

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
IPADDR="$(minikube ip)"
DNAME="docker.local"
sudo sed -i "/$DNAME/d" /etc/hosts
sudo sh -c "echo '$IPADDR\t$DNAME' >> /etc/hosts"
sudo sh -c "echo '{ \"insecure-registries\":[\"$DNAME:5000\"] }' > /etc/docker/daemon.json"
sudo service docker restart

