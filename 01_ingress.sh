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
    # find public ip address of this node
    IPADDRESS=$(curl -s http://checkip.dyndns.org | python3 -c 'import sys; data=sys.stdin.readline(); import xml.etree.ElementTree as ET; print(ET.fromstring(data).find("body").text.split(":")[-1].strip())')
    # port forwarding 80 -> 30080 (behind oracle cloud firewall)
    # inspired by https://www.karlrupp.net/en/computer/nat_tutorial
    # TODO: put this into rc.local:
    sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $IPADDRESS:30080
    sudo iptables -t nat -A POSTROUTING -p tcp --dport 30080 -j MASQUERADE
    sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination $IPADDRESS:30443
    sudo iptables -t nat -A POSTROUTING -p tcp --dport 30443 -j MASQUERADE
else # clean up
    timeout 5 kubectl delete -f "$url"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
