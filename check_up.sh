#!/bin/sh

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/services/deploytools"

loadSiteConfig
checkVars SC_CATAMEL_FQDN SC_CATAMEL_PUB SC_CATAMEL_KEY SC_REGISTRY_ADDR SC_NAMESPACE || exit 1

result=0
test_result() {
    width=$((30-${#1}))
    echo -n "$1: "
    shift
    if [ "$1" -eq 0 ]; then
        printf "%${width}s\n" "OK."
    else
        printf "%${width}s\n" "FAIL!"
        result=1
    fi
}
baseurl="$SC_REGISTRY_ADDR"
# extra arguments if the registry need authentication as indicated by a set password
[ -z "$SC_REGISTRY_PASS" ] || baseurl="$SC_REGISTRY_USER:$SC_REGISTRY_PASS@$baseurl"
curl -s "https://$baseurl/v2/_catalog" | grep -q repositories
test_result "$SC_REGISTRY_ADDR" "$?"

curl -s "https://$SC_CATAMEL_FQDN" | grep -q started
test_result "$SC_CATAMEL_FQDN" "$?"

curl -s "https://$SC_CATANIE_FQDN" | grep -q '<title>SciCat'
test_result "$SC_CATANIE_FQDN" "$?"

exit $result
