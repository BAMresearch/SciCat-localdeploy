#!/bin/sh

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/services/deploytools"

loadSiteConfig
le_wd="${LE_WORKING_DIR%/*}"
if [ ! -d "$le_wd" ]; then
  echo "Let's encrypt working dir not found!"
  exit 1
fi
domains="$(echo $DOMAINBASE; env | awk -F'=' "/\\.$DOMAINBASE/{print \$2}" | sort | uniq)"
#echo "$domains"
domargs=""
waitdelay=5
maxtries=5 # before failing hard
for dom in $domains; do
  domargs="$domargs -d $dom"
  #echo "$domargs"
  cmd="$le_wd/acme.sh --home $le_wd --issue --dns dns_ddnss $domargs"
  while ! (echo "$cmd"; eval "$cmd"); do
    echo "Waiting $waitdelay secs ..."; sleep $waitdelay
    [ "$maxtries" -eq 0 ] && exit 1
    maxtries=$((maxtries-1))
  done
  # Waiting anyway here to avoid being blocked for too many requests
  echo "Waiting $waitdelay secs ..."; sleep $waitdelay;
done

