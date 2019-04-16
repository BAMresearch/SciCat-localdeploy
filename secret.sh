#!/usr/bin/env bash

NS=dev
if [ "$(hostname)" == "kubetest01.dm.esss.dk" ]; then
  NS=dmsc
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout catanie.key -out catanie.crt -subj "/CN=kubetest01.dm.esss.dk" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout catamel.key -out catamel.crt -subj "/CN=kubetest02.dm.esss.dk" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout landingserver.key -out landingserver.crt -subj "/CN=kubetest03.dm.esss.dk" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout fileserver.key -out fileserver.crt -subj "/CN=kubetest04.dm.esss.dk" -days 3650
elif  [ "$(hostname)" == "scicat01.esss.lu.se" ]; then
  NS=ess
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout catanie.key -out catanie.crt -subj "/CN=scicat01.esss.lu.se" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout catamel.key -out catamel.crt -subj "/CN=scicat05.esss.lu.se" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout landingserver.key -out landingserver.crt -subj "/CN=scicat06.esss.lu.se" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout fileserver.key -out fileserver.crt -subj "/CN=scicat07.esss.lu.se" -days 3650
elif  [ "$(hostname)" == "k8-lrg-serv-prod.esss.dk" ]; then
  NS=dmscprod
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout catanie.key -out catanie.crt -subj "/CN=catanieservice.esss.dk" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout catamel.key -out catamel.crt -subj "/CN=catamelservice.esss.dk" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout landingserver.key -out landingserver.crt -subj "/CN=scicatlandingpageserver.esss.dk" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout fileserver.key -out fileserver.crt  -subj "/CN=scicatfileserver.esss.dk" -days 3650
else
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout catanie.key -out catanie.crt -subj "/CN=catanie.$(hostname).local" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout catamel.key -out catamel.crt -subj "/CN=catamel.$(hostname).local" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout landingserver.key -out landingserver.crt -subj "/CN=landing.$(hostname).local" -days 3650
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout fileserver.key -out fileserver.crt -subj "/CN=files.$(hostname).local" -days 3650
fi

for tmpns in dev $NS; do
  kubectl delete secret -n$tmpns catanieservice 2>/dev/null
  kubectl delete secret -n$tmpns catamelservice 2>/dev/null
  kubectl delete secret -n$tmpns landingserverservice 2>/dev/null
  kubectl delete secret -n$tmpns fileserverservice 2>/dev/null
done

kubectl create ns $NS
kubectl create secret -n$NS tls catanieservice --key catanie.key --cert catanie.crt
kubectl create secret -n$NS tls landingserverservice --key landingserver.key --cert landingserver.crt
kubectl create secret -ndev tls catamelservice --key catamel.key --cert catamel.crt
kubectl create secret -ndev tls fileserverservice --key fileserver.key --cert fileserver.crt

