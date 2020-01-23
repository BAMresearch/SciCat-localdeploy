#!/bin/bash

#if [ -z "$KUBE_NAMESPACE" ]; then
#    echo "\$KUBE_NAMESPACE not defined! giving up."
#    exit 1
#fi

ipaddr="$(minikube ip)"
sudo killall ssh 2>/dev/null
sudo sh -c "
    mkdir -p ~\$(whoami)/.ssh;
    fn=\$(eval echo ~\$(whoami)/.ssh/known_hosts);
    ssh-keygen -f \$fn -R '$ipaddr';
    ssh-keyscan -H '$ipaddr' >> \$fn;
    ssh -N -i ~/.minikube/machines/minikube/id_rsa -L 0.0.0.0:80:$ipaddr:80 docker@$ipaddr & \
    ssh -N -i ~/.minikube/machines/minikube/id_rsa -L 0.0.0.0:443:$ipaddr:443 docker@$ipaddr &"

exit 0

# remove all port forwardings first
pids=$(ps ax | grep port-forward | grep kubectl | awk '{print $1}')
[ -z "$pids" ] || sudo kill $pids
# catamel
NS=$KUBE_NAMESPACE
kubectl port-forward --address 0.0.0.0 --namespace $NS $(kubectl get po -n $NS | grep catamel | awk '{print $1;}') 3000:3000 >/dev/null 2>&1 &
sudo kubectl port-forward --address 0.0.0.0 --namespace $NS $(kubectl get po -n $NS | grep catanie | awk '{print $1;}') 80:80 >/dev/null 2>&1 &
exit

# namespaces
NS_CATAMEL=dev
NS_CATANIE=$KUBE_NAMESPACE

# configure virtualbox NAT rules
for svcname in catamel fileserver landingserver;
do
    NS=$NS_CATAMEL
    case $svcname in
        catamel)        outport=3000;;
        fileserver)     outport=8888;;
        landingserver)  outport=4000; NS=$NS_CATANIE;;
    esac
    # remove the catamel service only and expose it again
    [ "$svcname" = catamel ] && \
        kubectl -n$NS delete svc ${svcname}-${svcname}
    # remove the labeled NAT rules from virtualbox first
    oldrule="$(vboxmanage showvminfo minikube | grep 'NIC\s[0-9]\sRule' \
                | awk '{print $6}' |tr -d ',' | grep $svcname)"
    [ -z "$oldrule" ] || \
        vboxmanage controlvm "minikube" natpf1 delete "$oldrule" 2> /dev/null
    # setup a new NAT rule with the current node ports
    if true; then # switch allows disabling forwarding for debugging
        # forward service ports to the outside
        echo "Mapping service ports directly!"
        [ "$svcname" = catamel ] && \
            kubectl -n$NS expose deployment catamel-dacat-api-server-dev \
                --name=${svcname}-${svcname} --type=NodePort
        rule="$svcname-$NS"
        nodeport="$(kubectl get service ${svcname}-${svcname} -n$NS -o yaml \
                    | awk '/nodePort/ {print $NF}')"
        [ -z "$nodeport" ] || \
            vboxmanage controlvm "minikube" natpf1 "$rule,tcp,,$outport,,$nodeport"
    fi
done

## catanie
# setup SSH based port forwarding of port 80 (which needs root because its <1024)
if true; then # forward service ports to the outside
    echo "Mapping service ports directly!"
    svcname="$(kubectl get svc --no-headers=true -n$NS_CATANIE | awk '{print $1}' | grep catanie)"
    guestport="$(kubectl get service $svcname -n$NS_CATANIE -o yaml | awk '/nodePort:/ {print $NF}')"
    ipaddr="$(minikube ip)"
    sudo killall ssh 2>/dev/null
    sudo sh -c "\
        fn=\$(eval echo ~\$(whoami)/.ssh/known_hosts);
        ssh-keygen -f \$fn -R '$ipaddr'; \
        ssh-keyscan -H '$ipaddr' >> \$fn; \
        ssh -N -i ~/.minikube/machines/minikube/id_rsa -L 0.0.0.0:80:$ipaddr:$guestport docker@$ipaddr &"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
