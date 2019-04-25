#!/bin/bash

REPO="https://github.com/garethcmurphy/minitornado.git"
envarray=(dev)

echo $1

export LOCAL_ENV="${envarray[i]}"
echo $LOCAL_ENV
helm del --purge fileserver
cd services/fileserver/
if [ ! -d "./component/" ]; then
  git clone $REPO component
fi
cd component
git pull

# create own site-specific Dockerfile (no proxy needed, as in $REPO)
cat <<EOF > Dockerfile
FROM ubuntu:bionic
RUN apt-get update && apt-get install -y python3-tornado 
COPY . /usr/src/app/
WORKDIR /usr/src/app/
EXPOSE 8888
CMD ["python3","app2.py"]
EOF

export FILESERVER_IMAGE_VERSION=$(git rev-parse HEAD)
docker build . -t $4:$FILESERVER_IMAGE_VERSION$LOCAL_ENV
docker push $4:$FILESERVER_IMAGE_VERSION$LOCAL_ENV
echo "Deploying to Kubernetes"
cd ..
cd ..
pwd
cmd="helm install fileserver --name fileserver --namespace $LOCAL_ENV --set image.tag=$FILESERVER_IMAGE_VERSION$LOCAL_ENV --set image.repository=$4"
echo "$cmd"; eval $cmd
# envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false

rule="fileserver-$LOCAL_ENV"
vboxmanage controlvm "minikube" natpf1 delete "$rule" 2> /dev/null
nodeport="$(kubectl get service fileserver-fileserver -ndev -o yaml | awk '/nodePort/ {print $NF}')"
vboxmanage controlvm "minikube" natpf1 "$rule,tcp,,8888,,$nodeport"
