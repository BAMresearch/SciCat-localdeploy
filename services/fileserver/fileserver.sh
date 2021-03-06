#!/bin/bash

[ -z "$DOCKER_REG" ] && \
    echo "WARNING: Docker registry not defined, using default (docker.io?)!"
docker_repo="$DOCKER_REG/fs"

REPO="https://github.com/garethcmurphy/minitornado.git"
envarray=(dev)
cd services/fileserver/

INGRESS_NAME=" "
if true; then
    mkdir -p fileserver
    YAMLFN="./fileserver/$(hostname).yaml"
    INGRESS_NAME="-f $YAMLFN"
    # generate yaml file with appropriate hostname here
    cat > "$YAMLFN" << EOF
ingress:
    enabled: true
    host: files.$(hostname --fqdn)
EOF
fi

echo $1

export LOCAL_ENV="${envarray[i]}"
echo $LOCAL_ENV
helm del fileserver -n$LOCAL_ENV
if [ ! -d "./component/" ]; then
  git clone $REPO component
fi
cd component
git checkout .
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
docker build . -t $docker_repo:$FILESERVER_IMAGE_VERSION$LOCAL_ENV
docker push $docker_repo:$FILESERVER_IMAGE_VERSION$LOCAL_ENV
echo "Deploying to Kubernetes"
cd ..
pwd
cmd="helm install fileserver fileserver --namespace $LOCAL_ENV \
    --set image.tag=$FILESERVER_IMAGE_VERSION$LOCAL_ENV --set image.repository=$docker_repo ${INGRESS_NAME}"
echo "$cmd"; eval $cmd
# envsubst < ../catanie-deployment.yaml | kubectl apply -f - --validate=false

# vim: set ts=4 sw=4 sts=4 tw=0 et:
