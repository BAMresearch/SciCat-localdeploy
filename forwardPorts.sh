#!/bin/bash

ipaddr="$(minikube ip)"
sudo killall ssh 2>/dev/null
sudo sh -xc "
    mkdir -p ~/.ssh;
    fn=\$(eval echo ~/.ssh/known_hosts);
    ssh-keygen -f \$fn -R '$ipaddr';
    ssh-keyscan -H '$ipaddr' >> \$fn;
    ssh -N -i $HOME/.minikube/machines/minikube/id_rsa -L 0.0.0.0:80:$ipaddr:80 docker@$ipaddr & \
    ssh -N -i $HOME/.minikube/machines/minikube/id_rsa -L 0.0.0.0:443:$ipaddr:443 docker@$ipaddr &"

# vim: set ts=4 sw=4 sts=4 tw=0 et:
