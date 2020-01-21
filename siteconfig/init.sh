#!/bin/sh
# A script for init/generate site config credentials.
# Run it first, before any calls of 'run.sh'
# It creates a directory structure with files included in the helm charts of the services.

newpwd()
{
    openssl rand -base64 16
}

mongousr=dacatuser
mongopwd=$(newpwd | tr -d '+=/')

mongodb()
{
    mkdir -p mongodb
    cat > mongodb/credentials.yaml <<EOF
mongodbRootPassword: $(newpwd)
# MongoDB custom user and database
# ref: https://github.com/bitnami/bitnami-docker-mongodb/blob/master/README.md#creating-a-user-and-database-on-first-run
mongodbUsername: $mongousr
mongodbPassword: $mongopwd
mongodbDatabase: dacat
EOF
}

catamel()
{
    local path; path="dacat-api-server/envfiles"
    mkdir -p "$path"
    cp ../services/catamel/dacat-api-server/envfiles/datasources.json "$path"/
    sed -i -e '/"user":/ s/"[^"]*"\(,\?\)\s*$/"'$mongousr'"\1/' \
        -e '/"password":/ s/"[^"]*"\(,\?\)\s*$/"'$mongopwd'"\1/' \
        "$path"/datasources.json
}

scichat()
{
    local path; path="scichat/envfiles"
    mkdir -p "$path"
    cp ../services/scichat-loopback/scichat/envfiles/datasources.json "$path"/
    sed -i -e '/"user":/ s/"[^"]*"\(,\?\)\s*$/"'$mongousr'"\1/' \
        -e '/"password":/ s/"[^"]*"\(,\?\)\s*$/"'$mongopwd'"\1/' \
        "$path"/datasources.json
}

# go to the script directory before creating any files
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
cd "$scriptdir"

mongodb
catamel
scichat

# vim: set ts=4 sw=4 sts=4 tw=0 et:
