#!/bin/sh

sleep 10
SCRIPTPATH=/home/ingo/code/localdeploy
export HOME=/root/
cd $SCRIPTPATH
echo "USER: $(whoami), HOME: '$HOME'"
export KUBE_NAMESPACE=yourns
$SCRIPTPATH/start.sh
sleep 5
$SCRIPTPATH/forwardPorts.sh

