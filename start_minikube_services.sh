#!/bin/sh

sleep 10
export HOME=/root/
cd /home/ingo/code/localdeploy/
echo "USER: $(whoami), HOME: '$HOME'"
export KUBE_NAMESPACE=yourns
SCRIPTPATH=/home/ingo/code/localdeploy
$SCRIPTPATH/start.sh
sleep 5
$SCRIPTPATH/forwardPorts.sh

