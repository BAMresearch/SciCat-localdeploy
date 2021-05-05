# [Walk-through for installing kubernetes dockerless](#walk-through-for-installing-kubernetes-dockerless)

  1. [Cleaning up the initial system](#cleaning-up-the-initial-system)
    - [Ubuntu minimal](#ubuntu-minimal)
  1. [Install utility packages](#install-utility-packages)
  1. [Update installed packages](#update-installed-packages)
  1. [Configure *unattended-upgrades*](#configure-unattended-upgrades)
  1. [Install & configure fail2ban](#install--configure-fail2ban)
  1. [Configure networking and packet forwarding](#configure-networking-and-packet-forwarding)
  1. [Wireguard VPN for encrypted networking between nodes](#wireguard-vpn-for-encrypted-networking-between-nodes)
    - [Server Config (`wg0.conf`) on Node 1](#server-config-wg0conf-on-node-1)
    - [Client Config (`wg0.conf`) example on Node 2](#client-config-wg0conf-example-on-node-2)
    - [Update Wireguard config](#update-wireguard-config)
    - [Bring up the WireGuard interface at boot time](#bring-up-the-wireguard-interface-at-boot-time)
  1. [Install kubernetes tools](#install-kubernetes-tools)
  1. [Install *CRI-O*](#install-cri-o)
    - [Configuring CRI-O](#configuring-cri-o)
    - [Add existing private registry name to /etc/hosts \[optional\]](#add-existing-private-registry-name-to-etchosts-optional)
    - [Use docker.io public registry only, avoid questions for unqualified image names](#use-dockerio-public-registry-only-avoid-questions-for-unqualified-image-names)
    - [Start CRI-O](#start-cri-o)
  1. [Init kubernetes](#init-kubernetes)
    - [Some preparations](#some-preparations)
    - [Init the master node](#init-the-master-node)
    - [Setup the kubernetes config on a client](#setup-the-kubernetes-config-on-a-client)
    - [To let the master node run pods as well](#to-let-the-master-node-run-pods-as-well)
  1. [Setup cluster networking with *flannel* CNI](#setup-cluster-networking-with-flannel-cni)
    - [Check network settings (FYI)](#check-network-settings-fyi)
    - [Literature on network config ports needed (FYI)](#literature-on-network-config-ports-needed-fyi)
    - [Troubleshooting](#troubleshooting)
  1. [Get helm](#get-helm)
  1. [NVIDIA GPU support](#nvidia-gpu-support)
    - [Install the package `nvidia-container-runtime`](#install-the-package-nvidia-container-runtime)
    - [Set cri-o hooks appropriately](#set-cri-o-hooks-appropriately)
    - [Install the device plugin](#install-the-device-plugin)
    - [Test GPU support with an example pod](#test-gpu-support-with-an-example-pod)
  1. [A public name with certificates](#a-public-name-with-certificates)
    - [Using https://www.ddnss.de](#using-httpswwwddnssde)
    - [Get certificates from Let's Encrypt](#get-certificates-from-lets-encrypt)
    - [Create a kubernets secret with the provided certificates (FYI)](#create-a-kubernets-secret-with-the-provided-certificates-fyi)
  1. [Ingress](#ingress)
    - [For **SciCat** there is \[a script\](01_ingress.sh)](#for-scicat-there-is-a-script01_ingresssh)
  1. [NFS server (for persistent storage)](#nfs-server-for-persistent-storage)
    - [Mounting NFS shares on nodes](#mounting-nfs-shares-on-nodes)
  1. [MongoDB with persistent storage](#mongodb-with-persistent-storage)
  1. [A secured private local registry](#a-secured-private-local-registry)
  1. [That's it - have fun!](#thats-it---have-fun)
  1. [Misc. Snippets](#misc-snippets)
    - [ConfigMaps](#configmaps)


This works for the Ubuntu Server LTS edition 20.04
and was tested on free-tier Orcale Cloud VMs,
inspired by https://matrix.org/docs/guides/free-small-matrix-server

#### See also:

- https://kubernetes.io/docs/reference/kubectl/cheatsheet/
- https://github.com/kelseyhightower/kubernetes-the-hard-way
- https://blog.quickbird.uk/domesticating-kubernetes-d49c178ebc41

## Cleaning up the initial system

Remove some unwanted, unused packages.
Possibly, some packages might not be installed, just in case.
```
sudo apt-get -y purge netfilter-persistent iptables-persistent
sudo snap remove oracle-cloud-agent
sudo apt-get -y purge snap snapd open-iscsi lxd
```

### Ubuntu minimal

If the Ubuntu minimal image was used, run `unminimize` to get manpages back.

## Install utility packages

```
sudo apt-get update
sudo apt-get install -y vim less screen git bridge-utils net-tools inetutils-ping psmisc software-properties-common jq
```

## Update installed packages

```
sudo apt-get dist-upgrade -y
sudo apt-get --purge autoremove -y
sudo apt-get clean
```

## Configure *unattended-upgrades*

To get system package updates automatically/unattended.
```
sudo sh -c "echo 'Unattended-Upgrade::Origins-Pattern { \"origin=*\"; };' >> /etc/apt/apt.conf.d/50unattended-upgrades"
```

## Install & configure fail2ban

For protecting your SSH server from brute forcing system passwords.
See also: https://linuxize.com/post/install-configure-fail2ban-on-ubuntu-20-04/
```
sudo apt-get install fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
```
Adjust `jail.local` your needs, especially the `[sshd]` section.

## Configure networking and packet forwarding

```
SYSCTLCFG=/etc/sysctl.conf
sudo sh -c "grep -v bridge-nf-call-iptables $SYSCTLCFG | echo 'net.bridge.bridge-nf-call-iptables = 1' >> $SYSCTLCFG"
sudo sh -c "echo net.ipv4.ip_forward=1 >> $SYSCTLCFG"
sudo sysctl --system
sudo modprobe overlay
sudo modprobe br_netfilter
sudo sh -c 'echo overlay >> /etc/modules'
sudo sh -c 'echo br_netfilter >> /etc/modules'
```

## Wireguard VPN for encrypted networking between nodes

See also: https://linuxize.com/post/how-to-set-up-wireguard-vpn-on-ubuntu-20-04/
```
sudo apt install -y wireguard
wg genkey | sudo tee /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
sudo chmod 600 /etc/wireguard/privatekey
```

#### TODO: A script for adding new client in server cfg and generate client cfg.

### Server Config (`wg0.conf`) on Node 1

```
[Interface]
Address = 10.0.9.1/24
ListenPort = 51820
PrivateKey = ***

# Node 2
[Peer]
PublicKey = ***
AllowedIPs = 10.0.9.2/32, <local node2 IP>/32

# Node 3
[Peer]
PublicKey = ***
AllowedIPs = 10.0.9.3/32, <local node3 IP>/32
```

### Client Config (`wg0.conf`) example on Node 2

```
[Interface]
PrivateKey = ***
Address = 10.0.9.2/24

[Peer]
PublicKey = ***
Endpoint = <public IP of node1>:51820
AllowedIPs = 10.0.9.0/24, <local node2 IP>/32, <local node3 IP>/32
```

#### How to find your public ip address oneliner
```
IPADDRESS=$(curl -s http://checkip.dyndns.org | python3 -c 'import sys; data=sys.stdin.readline(); import xml.etree.ElementTree as ET; print(ET.fromstring(data).find("body").text.split(":")[-1].strip())')
```
### Update Wireguard config

```
sudo chmod 600 /etc/wireguard/wg0.conf
sudo sh -c 'wg-quick down wg0; wg-quick up wg0'
```

### Bring up the WireGuard interface at boot time
```
sudo systemctl enable wg-quick@wg0
```

#### Attention:
Make sure the wireguard port used here (51820) is accessible from the outside on each node,
check firewall settings if any cloud provider is used.

For wireguard debugging, see https://serverfault.com/a/1020299

## Install kubernetes tools

See also: https://linoxide.com/containers/install-kubernetes-on-ubuntu/
```
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
sudo apt-get install -y kubectl kubeadm kubelet kubernetes-cni
```

See also: https://gist.github.com/ruanbekker/38a38aea5f325f7fa4a19e795ef4f0d0

## Install *CRI-O*

Add software sources for *CRI-O* and *buildah* first:

See also:
- https://computingforgeeks.com/install-cri-o-container-runtime-on-ubuntu-linux/
- https://linoxide.com/containers/install-kubernetes-on-ubuntu/
- https://github.com/cri-o/cri-o/blob/master/tutorials/kubeadm.md

```
source /etc/os-release
URL="http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable"
KUBEVER="$(kubeadm version -o short | grep -o '[0-9]\.[0-9]\+')"
sudo sh -c "(echo 'deb $URL/x${NAME}_${VERSION_ID}/ /'; echo 'deb $URL:/cri-o:/$KUBEVER/x${NAME}_${VERSION_ID}/ /') > /etc/apt/sources.list.d/cri-o_stable.list"
curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/x${NAME}_${VERSION_ID}/Release.key | sudo apt-key add -
sudo apt update
```

Install CRI-O:
```
sudo apt install cri-o cri-o-runc buildah
```

### Configuring CRI-O
```
TMPFN=$(mktemp)
cat << EOF > $TMPFN
[crio.runtime]
conmon = "$(which conmon)"
EOF
sudo mv $TMPFN /etc/crio/crio.conf.d/99-custom.conf
```
### Add existing private registry name to /etc/hosts [optional]
```
grep -q registry /etc/hosts || sudo sh -c "echo '10.0.9.1 registry' >> /etc/hosts"
```
### Use docker.io public registry only, avoid questions for unqualified image names
```
sudo sed -i -e '/unqualified-search-registries/cunqualified-search-registries = ["docker.io",]' /etc/containers/registries.conf
```
### Start CRI-O
```
sudo systemctl daemon-reload && sudo systemctl enable crio && sudo systemctl start crio && sudo systemctl status crio
```
## Init kubernetes

### Some preparations
```
sudo kubeadm config images pull
swapoff /swap # if any, just in case
```

**Literature** for k8s networking, see: https://kubernetes.io/docs/concepts/cluster-administration/networking/

### Init the master node

Set up k8s init config:
- let it use the cri-o socket
- different IP (that of the VPN) for the API server
- set the pod network range (pod-network-cidr, the network of the pods which must not overlap with any host networks/devices), has to be given for the CNI plugin to pick it up (here: flannel)
- generate a new token, which is not done automatically once a cfg file is provided

```
KUBELET_CFG=/etc/kubernetes/custom_kubelet.conf
(kubeadm config print init-defaults --component-configs=KubeletConfiguration | sed -e '/ClusterConfiguration/{:a;n;/networking:/{a\  podSubnet: 10.244.0.0/16' -e'};ba' -e '}' | sed -e '/bootstrapTokens/{:a;n;/\(token:\s*\)/d;ba' -e '}' | sed -e 's#\(criSocket:\s*\).*$#\1unix:///var/run/crio/crio.sock#' -e 's#\(advertiseAddress:\s*\).*$#\110.0.9.1#' && echo 'cgroupDriver: systemd') > "$KUBELET_CFG"
sudo kubeadm init --ignore-preflight-errors=Mem,Swap --config="$KUBELET_CFG"
```

For problems with missing pod network, see: https://github.com/coreos/flannel/issues/728#issuecomment-425701657

### Setup the kubernetes config on a client
```
To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.0.9.1:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

### To let the master node run pods as well

And to let the coredns deployment start on the master node.
```
kubectl taint nodes --all node-role.kubernetes.io/master-
```

## Setup cluster networking with *flannel* CNI

See https://github.com/coreos/flannel

```
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

### Check network settings (FYI)

Get service-cluster-cidr:  
(https://stackoverflow.com/a/61685899)
```
echo '{"apiVersion":"v1","kind":"Service","metadata":{"name":"tst"},"spec":{"clusterIP":"1.1.1.1","ports":[{"port":443}]}}' | kubectl apply -f - 2>&1 | sed 's/.*valid IPs is //'
```
Get Services IPs range:
```
kubectl cluster-info dump | grep -m 1 service-cluster-ip-range
```
Get Pods IPs range:
```
kubectl cluster-info dump | grep -m 1 cluster-cidr
```
 
### Literature on network config ports needed (FYI)

- https://stackoverflow.com/questions/39293441/needed-ports-for-kubernetes-cluster
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#check-required-ports
- https://coreos.com/flannel/docs/latest/flannel-config.html#firewall
- https://serverfault.com/questions/1040893/vpn-network-and-kubernetes-clusters

### Troubleshooting

[NetworkPlugin cni failed to set up pod “xxxxx” network: failed to set bridge addr: “cni0” already has an IP address different from 10.x.x.x - Error
](https://stackoverflow.com/questions/61373366/networkplugin-cni-failed-to-set-up-pod-xxxxx-network-failed-to-set-bridge-add)

## Get helm
```
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get-helm-3 | bash
helm repo add k8s-at-home https://k8s-at-home.com/charts/
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

## NVIDIA GPU support

### Install the package `nvidia-container-runtime`

As described here: https://github.com/NVIDIA/nvidia-docker/issues/1427#issuecomment-737892353
NVIDIAs container runtime needs to be installed but without using docker, CRI-O will be configured accordingly below:
https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html#installing-on-ubuntu-and-debian
```
# sources for NVIDIA container toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
   && curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add - \
   && curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update
sudo apt-get install nvidia-container-runtime
```
### Set cri-o hooks appropriately

```
sudo mkdir -p /usr/share/containers/oci/hooks.d
sudo bash -c '
cat > /usr/share/containers/oci/hooks.d/oci-nvidia-hook.json << EOF
{
    "version": "1.0.0",
    "hook": {
        "path": "/usr/bin/nvidia-container-toolkit",
        "args": ["nvidia-container-toolkit", "prestart"]
    },
    "when": {
        "always": true,
        "commands": [".*"]
    },
    "stages": ["prestart"]
}
EOF
'
```

### Install the device plugin
```
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/master/nvidia-device-plugin.yml
```

### Test GPU support with an example pod

Create a new file `pod1.yaml` with the following contents:
```
apiVersion: v1
kind: Pod
metadata:
  name: pod1
spec:
  restartPolicy: OnFailure
  containers:
  - image: nvcr.io/nvidia/cuda:11.0-base
    name: pod1-ctr
    command: ["sleep"]
    args: ["100000"]

    resources:
      limits:
        nvidia.com/gpu: 1
```
Create the pod by calling:
```
kubectl create -f test.yaml
```
Check GPU support by running `nvidia-smi` in the pod:
```
kubectl exec -it pod1 -- nvidia-smi
```

## A public name with certificates

### Using https://www.ddnss.de

1. Create an account
2. Create a new domain, wildcard capable
3. Put the update script into /etc/dhcp/dhclient-exit-hooks.d/99_ddnss_update
   (from https://www.ddnss.de/info.php -> 'CRON & Bash Script')  
   https://gist.github.com/ibressler/53ea52c88392831b615d65091281dc38
4. Fill in the update key and the host name and run it manually for the first time to check if it works

### Get certificates from Let's Encrypt

The [acme.sh command line client](https://github.com/acmesh-official/acme.sh) supports the ddnss API out of the box (and many others).

1. Following the install guide https://github.com/acmesh-official/acme.sh#2-or-install-from-git
2. [Use DDNSS.de API](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#74-use-ddnssde-api)
```
   $ export DDNSS_Token="<update token>"
   $ acme.sh --issue --dns dns_ddnss -d <full ddnss domain> -d <ddnss subdomain>
```

### Create a kubernets secret with the provided certificates (FYI)

The environment variable *LE_WORKING_DIR* is set by `acme.sh` somewhere
```
DOMAINBASE=<your domain>
kubectl -n yourns create secret tls certs-catamel --cert="$LE_WORKING_DIR/$DOMAINBASE/$DOMAINBASE.cer" --key="$LE_WORKING_DIR/$DOMAINBASE/$DOMAINBASE.key" --dry-run=client -o yaml | kubectl apply -f -
```

## Ingress

See https://github.com/kubernetes/ingress-nginx/blob/master/docs/deploy/index.md

### For **SciCat** there is [a script](01_ingress.sh)

It forwards node ports to the outward facing network device
and makes it persistent across reboots (assuming there is no load balancer available)
as shown below:


```
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
else # clean up
    timeout 5 kubectl delete -f "$url"
fi
```

#### Port forwarding 80 to 30080 (the ingress node port)
Inspired by https://www.karlrupp.net/en/computer/nat_tutorial  
Add this to rc.local:
```
#!/bin/sh
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination 158.101.164.220:30080
sudo iptables -t nat -A POSTROUTING -o eth0 -p tcp --dport 30080 -j MASQUERADE
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT --to-destination 158.101.164.220:30443
sudo iptables -t nat -A POSTROUTING -o eth0 -p tcp --dport 30443 -j MASQUERADE
```

Then enable rc.local service:
```
grep -qiF '[Install]' /usr/lib/systemd/system/rc-local.service || sudo sh -c "(echo '[Install]'; echo 'WantedBy=multi-user.target') >> /usr/lib/systemd/system/rc-local.service"
sudo systemctl enable rc-local
```

For ingress options see: https://kubernetes.github.io/ingress-nginx/deploy/baremetal/

## NFS server (for persistent storage)
```
sudo apt install nfs-kernel-server
mkdir -p /nfs && chmod a+rwx /nfs
sudo su -c "echo '/nfs	10.0.9.0/24(rw,sync,no_subtree_check) 10.0.0.0/24(rw,sync,no_subtree_check)' >> /etc/exports"
sudo exportfs -a
sudo service nfs-kernel-server restart
```

### Mounting NFS shares on nodes
```
sudo mkdir -p /nfs
sudo sh -c "echo '10.0.9.1:/nfs/  /nfs    nfs     vers=4,rw       0 0' >> /etc/fstab"
```

## MongoDB with persistent storage

See also: https://vocon-it.com/2018/12/10/kubernetes-4-persistent-volumes-hello-world/

Basically it is:
```
kubectl apply -f definitions/mongo_pv_nfs.yaml
helm install local-mongodb bitnami/mongodb --namespace dev
```

#### For **SciCat**, there is [a script](00_mongo.sh)
It does a bit more to make sure persistent storage works and it provides a cleanup routine.

#### The following output should be produced:
```
MongoDB(R) can be accessed on the following DNS name(s) and ports from within your cluster:

    local-mongodb.dev.svc.cluster.local

To get the root password run:

    export MONGODB_ROOT_PASSWORD=$(kubectl get secret --namespace dev local-mongodb -o jsonpath="{.data.mongodb-root-password}" | base64 --decode)

To connect to your database, create a MongoDB(R) client container:

    kubectl run --namespace dev local-mongodb-client --rm --tty -i --restart='Never' --env="MONGODB_ROOT_PASSWORD=$MONGODB_ROOT_PASSWORD" --image docker.io/bitnami/mongodb:4.4.4-debian-10-r0 --command -- bash

Then, run the following command:
    mongo admin --host "local-mongodb" --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD

To connect to your database from outside the cluster execute the following commands:

    kubectl port-forward --namespace dev svc/local-mongodb 27017:27017 &
    mongo --host 127.0.0.1 --authenticationDatabase admin -p $MONGODB_ROOT_PASSWORD
```

## A secured private local registry

Needed for building custom images of SciCat services from source.
It is deployed in the k8s cluster using a helm chart *twuni*: https://github.com/twuni/docker-registry.helm

Using the registry over TLS with generally trusted certificates, e.g. by Let's Encrypt via the [acme.sh client](https://github.com/acmesh-official/acme.sh) is strongly recommended.
Otherwise, it might break in multiple places when clients refuse to access untrusted/insecure registry (helm, cri-o, …).

#### For **SciCat** there is [a script](02_registry.sh)
It configures
- TLS
- ingress
- htpasswd for username&password access and
- persistent storage settings accordingly.

It provides a cleanup routine for rollback too.

## That's it - have fun!

## Misc. Snippets

#### Get shell access in a pod (if a shell is available)
```
kubectl -nyourns exec -it $(kubectl get po --all-namespaces | awk '/catamel/{print $2}') -- ash
```
#### Install NodeJs via NPM
```
sudo apt install npm
```
#### Distributed storage

- https://www.gluster.org/linux-scale-out-nfsv4-using-nfs-ganesha-and-glusterfs-one-step-at-a-time/
- https://docs.gluster.org/en/latest/Quick-Start-Guide/Architecture/
- https://www.taste-of-it.de/glusterfs-mount-mittels-nfs/

### ConfigMaps

- https://stackoverflow.com/questions/54571185/how-to-patch-a-configmap-in-kubernetes
- https://pabraham-devops.medium.com/mapping-kubernetes-configmap-to-read-write-folders-and-files-8a548c855817

From directory, https://phoenixnap.com/kb/kubernetes-configmap-create-and-use
```
kubectl create configmap test --from-file=/nfs/siteconfig/catamel/ --dry-run=client -o yaml | kubectl apply -f -

kubectl -nyourns patch cm catamel-dacat-api-server-dev -p "$(printf 'data:\n  datasources.json: |-\n%s' "$(jq '.' /nfs/siteconfig/catamel/datasources.json | sed 's/^/    /g')")" 
```
#### On changes, the deployment needs to be updated:
- https://blog.questionable.services/article/kubernetes-deployments-configmap-change/
- https://helm.sh/docs/chart_template_guide/accessing_files/
- https://github.com/helm/helm/issues/3403#issuecomment-590882954

