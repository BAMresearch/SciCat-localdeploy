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
    virsh net-destroy minikube-net \
        && virsh net-destroy default # stop dnsmasq and old DNS values for 'docker.local'
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
# https://skryvets.com/blog/2019/04/09/exposing-tcp-and-udp-services-via-ingress-on-minikube/
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/mandatory.yaml
# add 'spec.template.spec.hostNetwork = true' to this controller
kubectl get deploy nginx-ingress-controller -n ingress-nginx -o yaml > temp.yaml
[ -f "temp.yaml" ] \
	&& yq w -i temp.yaml spec.template.spec.hostNetwork true \
	&& kubectl apply -f temp.yaml \
	&& rm temp.yaml
sleep 5

kubectl apply -f service-nodeport.yaml
kubectl apply -f configmap.yaml

if false; then # forward ingress ports to the outside
    ns=ingress-nginx
    ipaddr="$(minikube ip)"
    portmapping="$(kubectl get svc --no-headers=true -ningress-nginx -o yaml | \
                    awk '/nodePort:/ {ORS=":"; print $NF} /targetPort:/ {ORS=" "; print $NF}')"
    echo "port mapping found: '$portmapping'"
    sudo killall ssh > /dev/null 2>&1
    sudo sh -x -c "
        fn=\$(eval echo ~\$(whoami)/.ssh/known_hosts)
        ssh-keygen -f \$fn -R '$ipaddr'
        ssh-keyscan -H '$ipaddr' >> \$fn
        for mapping in $portmapping; do
            inp=\${mapping%:*}; outp=\${mapping#*:}
            echo \"mapping \$mapping: \$inp -> \$outp\"
	    if [ -z \"\$inp\" ] || [ -z \"\$outp\" ]; then
                echo \"Input or output port could not be determined! Skipping.\"
		continue
            fi
            ssh -N -i ~/.minikube/machines/minikube/id_rsa \
                -L 0.0.0.0:\$outp:$ipaddr:\$inp docker@$ipaddr &
        done"
fi

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
