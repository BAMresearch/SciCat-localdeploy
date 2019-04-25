#!/bin/bash

source ./services/deploytools
export REPO=https://github.com/SciCatProject/catanie.git
envarray=(bam2) # selects angular configuration in subrepo component
cd ./services/catanie/

INGRESS_NAME=" "
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
  envarray=(dmsc)
  INGRESS_NAME="-f ./dacat-gui/dmsc.yaml"
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
  envarray=(ess)
  INGRESS_NAME="-f ./dacat-gui/lund.yaml"
elif  [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
  envarray=(dmscprod)
  INGRESS_NAME="-f ./dacat-gui/dmscprod.yaml"
else
  YAMLFN="./dacat-gui/$(hostname).yaml"
  INGRESS_NAME="-f $YAMLFN"
  # generate yaml file with appropriate hostname here
  cat > "$YAMLFN" << EOF
ingress:
  enabled: true
  host:  catanie.$(hostname).local
EOF
fi

portarray=(30021 30023)
hostextarray=('-qa' '')
certarray=('discovery' 'discovery')
echo $1

hostaddr="$(getHostAddr)"

read -r -d '' angEnv <<EOF
export const environment = {
  production: true,
  lbBaseURL: "http://${hostaddr}:3000",
  fileserverBaseURL: "http://${hostaddr}:8888",
  externalAuthEndpoint: "/auth/msad",
  archiveWorkflowEnabled: true,
  editMetadataEnabled: true,
  columnSelectEnabled: true,
  editSampleEnabled: true,
  shoppingCartEnabled: true,
  facility: "BAM"
};
EOF

read -r -d '' angCfg <<EOF
  {
    "optimization": true,
    "outputHashing": "all",
    "sourceMap": false,
    "extractCss": true,
    "namedChunks": false,
    "aot": true,
    "extractLicenses": true,
    "vendorChunk": false,
    "buildOptimizer": true,
    "fileReplacements": [ {
      "replace": "src/environments/environment.ts",
      "with": \$envfn } ],
    "serviceWorker": true
  }
EOF

for ((i=0;i<${#envarray[@]};i++)); do
  export LOCAL_ENV="${envarray[i]}"
  export PORTOFFSET="${portarray[i]}"
  export HOST_EXT="${hostextarray[i]}"
  export CERTNAME="${certarray[i]}"
  export LOCAL_IP="$1"
  echo $LOCAL_ENV $PORTOFFSET $HOST_EXT
  echo $LOCAL_ENV
  helm del --purge catanie
  if [ ! -d "./component" ]; then
    git clone $REPO component
  fi
  cd component
  git checkout develop
  git clean -f
  git pull
  injectEnvConfig catanie $LOCAL_ENV "$angEnv" "$angCfg"
  ./CI/ESS/copyimages.sh
  if  [ "$(hostname)" != "k8-lrg-serv-prod.esss.dk" ]; then
    npm install
    ./node_modules/@angular/cli/bin/ng build --configuration $LOCAL_ENV --output-path dist/$LOCAL_ENV
  fi
  echo STATUS:
  kubectl cluster-info
  export CATANIE_IMAGE_VERSION=$(git rev-parse HEAD)
  if  [ "$(hostname)" != "k8-lrg-serv-prod.esss.dk" ]; then
    cmd="docker build -t $2:$CATANIE_IMAGE_VERSION$LOCAL_ENV -t $2:latest --build-arg env=$LOCAL_ENV ."
    echo "$cmd"; eval $cmd
    cmd="docker push $2:$CATANIE_IMAGE_VERSION$LOCAL_ENV"
    echo "$cmd"; eval $cmd
  fi
  echo "Deploying to Kubernetes"
  cd ..
  helm install dacat-gui --name catanie --namespace $LOCAL_ENV --set image.tag=$CATANIE_IMAGE_VERSION$LOCAL_ENV --set image.repository=$2 ${INGRESS_NAME}

  svcname="$(kubectl get svc --no-headers=true -n$LOCAL_ENV | awk '{print $1}')"
  guestport="$(kubectl get service $svcname -n$LOCAL_ENV -o yaml | awk '/nodePort:/ {print $NF}')"
  ipaddr="$(minikube ip)"
  sudo killall ssh 2>/dev/null
  sudo sh -c "\
    fn=\$(eval echo ~\$(whoami)/.ssh/known_hosts);
    ssh-keygen -f \$fn -R '$ipaddr'; \
    ssh-keyscan -H '$ipaddr' >> \$fn; \
    ssh -N -i ~/.minikube/machines/minikube/id_rsa -L 0.0.0.0:80:$ipaddr:$guestport docker@$ipaddr &"
done
