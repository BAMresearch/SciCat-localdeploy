#!/bin/bash

DNAME=docker.local

registerDockerIP()
{
    local hostsfn="/etc/hosts"
    local ipaddr; ipaddr="$(minikube ip)"
    sudo sed -i "/$DNAME/d" "$hostsfn"
    sudo sh -c "echo '$ipaddr\t$DNAME' >> '$hostsfn'"
#    sudo sh -c "echo '{ \"insecure-registries\": [\"$DNAME:5000\"] }' > /etc/docker/daemon.json"
    sudo service docker restart
}

start_minikube()
{
    #minikube start -v7    --insecure-registry localhost:5000 --extra-config=apiserver.GenericServerRunOptions.AuthorizationMode=RBAC
    echo "Cleaning some KVM ressources first:"
    #virsh undefine minikube
    #virsh net-undefine minikube-net
    virsh net-list --name | grep -q minikube \
        && virsh net-destroy minikube-net
    virsh net-destroy default # stop dnsmasq and old DNS values for 'docker.local'
    sudo sed -i "/$DNAME/d" /etc/hosts # remove docker.local
    echo "Starting minikube now:"
    minikube start --vm-driver kvm2 --insecure-registry=$DNAME:5000 $@
}

# configure the minikube VM before it is started
cpucount="$(grep -c '^processor' /proc/cpuinfo)"
cpucount="$(python -c "print(int($cpucount * 0.8))")"
memratio=0.8 # how much phys. memory to use for minikube (the k8s cluster)
mem="$(awk "/MemTotal/{print int(\$2*$memratio/1024)}" /proc/meminfo)"
start_minikube --cpus="$cpucount" --memory="$mem"
#kubectl config use-context minikube #should auto set, but added in case
registerDockerIP # docker.local points always to the same local registry

#kubectl -n kube-system create sa tiller # handled by rbac-config.yaml
kubectl create -f rbac-config.yaml
helm init --service-account tiller
helm repo update

# get nginx-ingress-controller with hostNetwork=true
tmpyaml=$(mktemp -p .) # yq does not like files in /tmp/ for unknown reasons
curl -o "$tmpyaml" https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/mandatory.yaml
# https://skryvets.com/blog/2019/04/09/exposing-tcp-and-udp-services-via-ingress-on-minikube/
# add 'spec.template.spec.hostNetwork = true' to Deployment of this controller config
yq w -i -d 9 "$tmpyaml" spec.template.spec.hostNetwork true
echo "Applying ingress config from "$tmpyaml"!"
kubectl apply -f "$tmpyaml"
sleep 5

kubectl apply -f service-nodeport.yaml
kubectl apply -f configmap.yaml

# do not delete the dev namespace
if false; then
    NS_DIR=./namespaces/*.yaml
    for file in $NS_DIR; do
        f="$(basename $file)"
        ns="${f%.*}"
        kubectl delete namespace $ns 2> /dev/null
    done
fi

# let docker context point to minikube
eval $(minikube docker-env)
# set up a local registry if not running
if ! curl -s -X GET http://docker.local:5000/v2/_catalog | grep -q repositories; then
    # https://hackernoon.com/local-kubernetes-setup-with-minikube-on-mac-os-x-eeeb1cbdc0b
    # start local docker registry
    docker run -d -p 5000:5000 --restart=always --name registry registry:2
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
