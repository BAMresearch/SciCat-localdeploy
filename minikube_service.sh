#!/bin/sh

SCRIPTPATH=/home/ingo/code/localdeploy
username="$(whoami)"
export HOME="$(eval echo "~$username")"
cd $SCRIPTPATH
echo "USER: $username, HOME: '$HOME'"
export KUBE_NAMESPACE=yourns
$SCRIPTPATH/start.sh
#sleep 5
#$SCRIPTPATH/forwardPorts.sh

