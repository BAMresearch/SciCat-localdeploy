#!/bin/sh
# setting up the ingress controller with port forwarding to the node ports
# argument 'forwardonly' does not install the ingress controller, assumes it exists already

# learn about some utility functions before heading on ...
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
. "$scriptdir/services/deploytools"

# get provided command line flags
clean="$(getScriptFlags clean "$@")"
forwardonly="$(getScriptFlags forwardonly "$@")"

# detect if is ingress already running, forward only in that case
kubectl get po -n ingress-nginx --no-headers | grep -q 'ingress-nginx-controller.*Running' && forwardonly=true

latest="$(curl -s https://api.github.com/repos/kubernetes/ingress-nginx/releases | jq '[.[] | select(.prerelease == false and .tag_name[:4] == "cont" )] | .[0].tag_name' | tr -d '"')"
url="https://raw.githubusercontent.com/kubernetes/ingress-nginx/$latest/deploy/static/provider/baremetal/deploy.yaml"
echo "$0 using '$url'"

iptabCmd()
{
    local port="$1"
    local op="$2"
    local baseport=30000
    # find public ip address of this node and its device name
    local ipaddr=$(curl -s http://checkip.dyndns.org | python3 -c 'import sys; data=sys.stdin.readline(); import xml.etree.ElementTree as ET; print(ET.fromstring(data).find("body").text.split(":")[-1].strip())')
    devname="$(ip addr show | awk -F': ' '/^[0-9]+:\s*ens/{print $2}')"
    echo "sudo iptables -t nat $op PREROUTING -i $devname -p tcp --dport $port -j DNAT --to-destination $ipaddr:$((baseport+port))"
    echo "sudo iptables -t nat $op POSTROUTING -o $devname -p tcp --dport $((baseport+port)) -j MASQUERADE"
}

if [ -z "$clean" ]; then
    if [ -z "$forwardonly" ]; then
        kubectl apply -f "$url"
        # change ingress-nginx service to known port numbers
        kubectl patch svc -n ingress-nginx ingress-nginx-controller --type=json --patch \
            '[{"op": "replace", "path": "/spec/ports/0/nodePort", "value":30080},
              {"op": "replace", "path": "/spec/ports/1/nodePort", "value":30443}]'
        sleep 2
        # remove completed one-shot pods
        kubectl delete pod -n ingress-nginx --field-selector=status.phase==Succeeded
    fi
    # port forwarding 80 -> 30080 (behind oracle cloud firewall)
    # inspired by https://www.karlrupp.net/en/computer/nat_tutorial
    # TODO: put this into rc.local:
    tmpfn="$(mktemp)"
    cat << EOF > "$tmpfn"
#!/bin/sh
$(iptabCmd 80 -A)
$(iptabCmd 443 -A)
EOF
    sudo mv "$tmpfn" /etc/rc.local
    sudo sh -x /etc/rc.local
    # enable rc.local service
    if [ "$(sudo systemctl is-active rc-local)" != "active" ]; then
        if [ "$(sudo systemctl is-enabled rc-local)" != "enabled" ]; then
            svcfn="/usr/lib/systemd/system/rc-local.service"
            grep -qiF '[Install]' "$svcfn" \
                || (sudo sh -c "(echo '[Install]'; echo 'WantedBy=multi-user.target') >> $svcfn" \
                    && sudo systemctl enable rc-local)
        fi
        sudo systemctl start rc-local
    fi
else # clean up
    timeout 5 kubectl delete -f "$url"
    sudo sh -c "echo '#!/bin/sh' > /etc/rc.local"
    sudo sh -c "$(iptabCmd 80 -D; iptabCmd 443 -D)"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
