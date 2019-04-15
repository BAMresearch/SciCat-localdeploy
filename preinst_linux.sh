#!/bin/sh

distrib="$(grep ^ID= /etc/os-release | awk -F= '{print $2}')"
[ -z "$distrib" ] && distrib="$(grep ^ID_LIKE= /etc/os-release | awk -F= '{print $2}')"
if [ "$distrib" != ubuntu ] && [ "$distrib" != debian ]; then
    echo "This script is made for Debian/Ubuntu only, sorry!"
    exit 1
fi
codename="$(grep ^UBUNTU_CODENAME= /etc/os-release | awk -F= '{print $2}')"
[ -z "$codename" ] && codename="$(grep ^VERSION= /etc/os-release | grep -oE '\w+' | tail -n1)"
# prepare for docker
sudo apt update
sudo apt install -y git curl jq vim apt-transport-https ca-certificates curl software-properties-common

# install docker
curl -fsSL "https://download.docker.com/linux/${distrib}/gpg" | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/${distrib} ${codename} stable"
sudo apt update
sudo apt install -y docker-ce

# fix 'invoke-rc.d: policy-rc.d denied execution of start.'
if [ -f '/usr/sbin/policy-rc.d' ]; then
    sudo sh -c 'echo "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d'
fi

# allow the user to call the docker cmd
USER=$(whoami)
sudo usermod -aG docker ${USER}

# install docker-compose
dcompose=/usr/local/bin/docker-compose
if [ ! -f "$dcompose" ]; then
    tmpfn="$(mktemp)"
    latest="$(curl -s https://api.github.com/repos/docker/compose/releases | jq '[.[] | select(.prerelease == false)] | .[0].name'  | tr -d '"')"
    curl -L https://github.com/docker/compose/releases/download/${latest}/docker-compose-`uname -s`-`uname -m` -o "$tmpfn"
    chmod +x "$tmpfn"
    sudo mv "$tmpfn" "$dcompose"
fi

sudo add-apt-repository "deb [arch=amd64] https://download.virtualbox.org/virtualbox/debian ${codename} contrib"
wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
wget -q https://www.virtualbox.org/download/oracle_vbox.asc -O- | sudo apt-key add -
sudo apt update
sudo apt install -y virtualbox-6.0

# install nodejs/npm (some scripts need this)
curl -sL https://deb.nodesource.com/setup_10.x | sudo bash -
sudo apt install -y nodejs

## install docker-machine
#dmachine=/usr/local/bin/docker-machine
#if [ ! -f "$dmachine" ]; then
#    tmpfn=$(mktemp)
#    latest="$(curl -s https://api.github.com/repos/docker/machine/releases | jq '[.[] | select(.prerelease == false)] | .[0].name'  | tr -d '"')"
#    curl -L https://github.com/docker/machine/releases/download/${latest}/docker-machine-`uname -s`-`uname -m` -o "$tmpfn"
#    chmod 755 "$tmpfn"
#    sudo mv "$tmpfn" "$dmachine"
#    sudo chown root.staff "$dmachine"
#fi
## install docker-machine kvm driver
#dmachdrv=/usr/local/bin/docker-machine-driver-kvm2
#if [ ! -f "$dmachdrv" ]; then
#    tmpfn=$(mktemp)
#    latest="$(curl -s https://api.github.com/repos/kubernetes/minikube/releases | jq '[.[] | select(.prerelease == false)] | .[0].name'  | tr -d '"')"
#    curl -L https://github.com/kubernetes/minikube/releases/download/${latest}/docker-machine-driver-kvm2 -o "$tmpfn"
#    chmod 755 "$tmpfn"
#    sudo mv "$tmpfn" "$dmachdrv"
#    sudo chown root.staff "$dmachdrv"
#fi
#
## install kvm
## https://www.cyberciti.biz/faq/install-kvm-server-debian-linux-9-headless-server/
#sudo apt install qemu-kvm libvirt-clients libvirt-daemon-system bridge-utils libguestfs-tools genisoimage virtinst libosinfo-bin
#sudo adduser $(whoami) libvirt
#sudo adduser $(whoami) libvirt-qemu
## minikube config set vm-driver xhyve #?
## https://kubernetes.io/docs/setup/minikube/#quickstart

# get scicat
cd; mkdir -p code; cd code
if [ ! -d localdeploy ]; then
	git clone https://github.com/SciCatBAM/localdeploy.git
fi
if cd localdeploy; then
	git pull
	bash ./install.sh # installs helm
	helm init
	echo "Rebooting in 30 secs ... press Ctrl-C to abort."
	sleep 30
	sudo reboot
fi

# vim: set ts=4 sts=4 sw=4 tw=0:
