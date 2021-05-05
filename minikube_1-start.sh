#!/bin/bash

DNAME=docker.local

getScriptFlags()
{
    local key="$1"
    shift
    (echo "$@" | grep -qi "\\<$key\\>") && echo true
}

# get given command line flags
withNvidia="$(getScriptFlags withNvidia "$@")"

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
    echo "Cleaning some KVM ressources first:"
    #virsh undefine minikube
    #virsh net-undefine minikube-net
    virsh net-list --name | grep -q minikube \
        && virsh net-destroy minikube-net
    virsh net-destroy default # stop dnsmasq and old DNS values for 'docker.local'
    sudo sed -i "/$DNAME/d" /etc/hosts # remove docker.local
    echo "Starting minikube now:"
    minikubeArgs="--delete-on-failure=false --insecure-registry=$DNAME:5000"
    if [ -z "$withNvidia" ]; then
        minikube start $minikubeArgs --vm-driver kvm2 $@
    else
        sudo apt-get install nvidia-docker2
        sudo sysctl fs.protected_regular=0
        minikube start $minikubeArgs --driver=none --docker-opt default-runtime=nvidia \
            --apiserver-ips 127.0.0.1 --apiserver-name localhost $@
#        kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/master/nvidia-device-plugin.yml
        kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/1.0.0-beta6/nvidia-device-plugin.yml
#        helm repo add nvdp https://nvidia.github.io/k8s-device-plugin \
#            && helm repo update
#        helm install --generate-name nvdp/nvidia-device-plugin
         # try this? https://nvidia.github.io/gpu-operator/#quickstart
#        helm repo add nvidia https://nvidia.github.io/gpu-operator \
#            && helm repo update
#        helm install --wait --generate-name nvidia/gpu-operator
#        helm install gpu-operator deployments/gpu-operator --set operator.registry=registry.gitlab.com/nvidia/kubernetes --set operator.version=1.6.2-31-g2345a5c --set toolkit.registry=registry.gitlab.com/nvidia/container-toolkit/container-config/staging --toolkit.version=22225e5d-ubuntu18.04 --set driver.enabled=false
    fi
}

# configure the minikube VM before it is started
cpucount="$(grep -c '^processor' /proc/cpuinfo)"
cpucount="$(python3 -c "print(int($cpucount * 0.8))")"
memratio=0.8 # how much phys. memory to use for minikube (the k8s cluster)
mem="$(awk "/MemTotal/{print int(\$2*$memratio/1024)}" /proc/meminfo)"
start_minikube --cpus="$cpucount" --memory="$mem" --disk-size=100g
#exit # for debugging

#kubectl config use-context minikube #should auto set, but added in case
registerDockerIP # docker.local points always to the same local registry

#kubectl -n kube-system create sa tiller # handled by rbac-config.yaml
#kubectl create -f rbac-config.yaml
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# get nginx-ingress-controller with hostNetwork=true
tmpyaml=$(mktemp -p .) # yq does not like files in /tmp/ for unknown reasons
curl -o "$tmpyaml" https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/mandatory.yaml
# https://skryvets.com/blog/2019/04/09/exposing-tcp-and-udp-services-via-ingress-on-minikube/
# add 'spec.template.spec.hostNetwork = true' to Deployment of this controller config
sed -i -E 's/((\s+)spec:)/\1\n\2  hostNetwork: true/' "$tmpyaml"
echo "Applying ingress config from "$tmpyaml"!"
kubectl apply -f "$tmpyaml"
rm "$tmpyaml"
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
[ -z "$withNvidia" ] && eval $(minikube docker-env)
# set up a local registry if not running
if ! curl -s -X GET http://docker.local:5000/v2/_catalog | grep -q repositories; then
    # https://hackernoon.com/local-kubernetes-setup-with-minikube-on-mac-os-x-eeeb1cbdc0b
    # start local docker registry
    docker run -d -p 5000:5000 --restart=always --name registry registry:2
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
