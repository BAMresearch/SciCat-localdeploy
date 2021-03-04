#!/bin/sh

latest="$(curl -s https://api.github.com/repos/kubernetes/ingress-nginx/releases | jq '[.[] | select(.prerelease == false and .tag_name[:4] == "cont" )] | .[0].tag_name' | tr -d '"')"
url="https://raw.githubusercontent.com/kubernetes/ingress-nginx/$latest/deploy/static/provider/baremetal/deploy.yaml"
echo "$0 using '$url'"

if [ "$1" != "clean" ];
then
    kubectl apply -f "$url"
    # change ingress-nginx service to known port numbers
    kubectl patch svc -n ingress-nginx ingress-nginx-controller --type=json --patch \
        '[{"op": "replace", "path": "/spec/ports/0/nodePort", "value":30080},
          {"op": "replace", "path": "/spec/ports/1/nodePort", "value":30443}]'
    sleep 2
    # remove completed one-shot pods
    kubectl delete pod -n ingress-nginx --field-selector=status.phase==Succeeded
else # clean up
    timeout 5 kubectl delete -f "$url"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
