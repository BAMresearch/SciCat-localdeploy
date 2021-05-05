# SciCat deploy scripts

This repo provides scripts for setting up the [SciCat data catalog project](https://scicatproject.github.io/)
on a single machine by setting up a [minikube cluster](https://minikube.sigs.k8s.io)
or a [kubernetes cluster](https://kubernetes.io)
running on multiple machines (which may be physical or virtual).

The scripts provided here can be used for the operational deployment
of the SciCat microservices (catanie/front-end, catamel/api, etc.).
The initial setup scripts download and install the required software
and create a basic configuration accordingly.
This was tested and developed with a minimal installation of [Ubuntu Server](https://ubuntu.com/server) Linux.
Most likely it will work on similar distributions with slight modifications.

## Installing on a single machine with *minikube*

### Required software being installed automatically

- Docker
- Minikube
- Kubectl
- Helm
- MongoDB - running locally is easiest, but this will be installed by Helm

### Install minikube

    curl -L https://github.com/scicatbam/localdeploy/raw/baremetal/minikube_0-install.sh | sh

Running this will install the above mentioned software packages.

### Start minikube

    ./minikube_1-start.sh

Running this script will start minikube and set up helm access.
It will also deploy a registry for docker images and an nginx ingress controller.

### Start the SciCat services

    ./minikube_2-run.sh [nopause]

This starts the SciCat services one after another and waits for user confirmation before starting the next one.
This gives a chance to spot any error messages and it can be disabled by providing the argument `nopause` to the script.

The `services` directory contains charts and custom code SciCat consists of and is deployed through helm:

1. The image is built using the script
2. The image is then pushed to your docker regsitry and tagged
3. Once pushed, the helm script starts and pulls down the image and deploys it

### Publish services

    ./minikube_3-forwardPorts.sh

Running the above command will connect the appropriate ports of the network device to the minikube service set up previously.
With minikube they are accessible at the (internal) address given by the `minikube ip` command only be default.
The above mentioned script uses *ssh* to forward the service ports to the outward facing network device.

## [Install a kubernetes cluster dockerless](InstallingKubernetes.md)

For installing SciCat on a bunch of virtual machines running Ubuntu Server
there is [a guide on bootstrapping the kubernetes cluster without using docker](InstallingKubernetes.md)
for a smaller memory footprint - works on VMs limited to 1G RAM for master and worker nodes.

### SciCat services

Once the cluster is setup, to current machine needs access with `kubectl`.
A particular service can be started (and build on the fly) by running (in this case the catamel API server):
```
./services/catamel/catamel.sh
```

There are command line arguments for each service to run only a part of the procedure:
- `./services/catamel/catamel.sh nobuild` does not build the image but pull the latest one from the registry
- `./services/catamel/catamel.sh buildonly` builds an image from source and does not interact with the cluster, it can be run on any machine, it uploads the image to the configured registry finally
- `./services/catamel/catamel.sh clean` just removes the service and all accociated resources from the cluster

## Site config

All services and infrastucture refer to a *siteconfig* directory which must exist,
contains your local settings, host names, certificate locations and credentials.
It will be created on the first try accessing it and will be populated with sane defaults.
Additionally, it has to be made accessible in a secure way to any machine/node installing cluster services.
Here, a NFS server (which can be used as persistent storage backend) over VPN is used.
There may be better options depending on your requirements.

