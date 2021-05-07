#!/bin/sh
# setting up the ingress controller with port forwarding to the node ports
# argument 'forwardonly' does not install the ingress controller, assumes it exists already

# learn about some utility functions before heading on ...
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
. "$scriptdir/services/deploytools"

# get provided command line flags
clean="$(getScriptFlags clean "$@")"

if [ -z "$clean" ]; then
    # make sure the necessary repo is available
    (helm repo list | grep -q '^ingress-nginx') || helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    #helm repo update

    ipaddr=$(curl -s http://checkip.dyndns.org | python3 -c 'import sys; data=sys.stdin.readline(); import xml.etree.ElementTree as ET; print(ET.fromstring(data).find("body").text.split(":")[-1].strip())')
    helm install ingress-nginx ingress-nginx/ingress-nginx --namespace kube-system \
        --set controller.kind=DaemonSet --set "controller.service.externalIPs[0]=$ipaddr"
else # clean up
    helm del --namespace kube-system ingress-nginx
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
