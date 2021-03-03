#!/bin/sh

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

kubectl create ns ingress-nginx # make sure the namespace exists
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx

# wait for the controller to get ready
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

kubectl apply -f service-nodeport.yaml
# kubectl delete svc ingress-nginx-controller -n ingress-nginx
kubectl apply -f configmap.yaml

# vim: set ts=4 sw=4 sts=4 tw=0 et:
