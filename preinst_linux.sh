#!/bin/sh

distrib="$(grep ^ID= /etc/os-release | awk -F= '{print $2}')"
[ -z "$distrib" ] && distrib="$(grep ^ID_LIKE= /etc/os-release | awk -F= '{print $2}')"
if [ "$distrib" != ubuntu ] && [ "$distrib" != debian ]; then
    echo "This script is made for Debian/Ubuntu only, sorry!"
    exit 1
fi
codename="$(grep ^UBUNTU_CODENAME= /etc/os-release | awk -F= '{print $2}')"
[ -z "$codename" ] && codename="$(grep ^VERSION= /etc/os-release | grep -oE '\w+' | tail -n1)"
# prepare for docker and other required packages
sudo apt-get update
sudo apt-get install -y git curl jq vim apt-transport-https ca-certificates curl software-properties-common g++

# install docker
curl -fsSL "https://download.docker.com/linux/${distrib}/gpg" | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/${distrib} ${codename} stable"
sudo apt-get update
sudo apt-get install -y docker-ce

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
sudo apt-get update
sudo apt-get install -y virtualbox-6.0

# install nodejs/npm (some scripts need this)
curl -sL https://deb.nodesource.com/setup_10.x | sudo bash -
sudo apt-get install -y nodejs

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

# vim: set ts=4 sw=4 sts=4 tw=0 et:
