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
    # get the systems outward facing (physical) ip address
    ipaddr="$(ip addr show | awk '/\<inet\>\s[0-9\.]+\/24/ { split($2,a,"/"); print a[1] }' | head -n1)"
    helm install ingress-nginx ingress-nginx/ingress-nginx --namespace kube-system \
        --set controller.kind=DaemonSet --set "controller.service.externalIPs[0]=$ipaddr"
else # clean up
    helm del --namespace kube-system ingress-nginx
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
