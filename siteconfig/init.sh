#!/bin/sh
# A script for init/generate site config credentials.
# Run it first, before any calls of 'run.sh'
# It creates a directory structure with files included in the helm charts of the services.

newpwd()
{
    openssl rand -base64 16 | tr -d '+=/'
}

mongodb()
{
    mkdir -p mongodb
    cat > mongodb/credentials.yaml <<EOF
mongodbRootPassword: $(newpwd)
# MongoDB custom user and database
# ref: https://github.com/bitnami/bitnami-docker-mongodb/blob/master/README.md#creating-a-user-and-database-on-first-run
# and here: https://github.com/helm/charts/blob/master/stable/mongodb/README.md
#mongodbUsername: <disabled>
#mongodbPassword: <disabled>
#mongodbDatabase: <disabled>
EOF
}

createUserCmd()
{
    cat > "$1" <<EOF
use $4
db.createUser({
    user: "$2",
    pwd: "$3",
    roles: [{
        role: "readWrite",
        db: "$4"
    }]
});
EOF
}

catamel()
{
    local dbusr=dacat
    local dbpwd=$(newpwd)
    local dbname=dacatdb
    local path; path="dacat-api-server/envfiles"
    mkdir -p "$path"
    cp ../services/catamel/dacat-api-server/envfiles/datasources.json "$path"/
    sed -i -e '/"user":/ s/"[^"]*"\(,\?\)\s*$/"'$dbusr'"\1/' \
        -e '/"password":/ s/"[^"]*"\(,\?\)\s*$/"'$dbpwd'"\1/' \
        -e '/"database":/ s/"[^"]*"\(,\?\)\s*$/"'$dbname'"\1/' \
        "$path"/datasources.json
    createUserCmd mongodb/catamel.js "$dbusr" "$dbpwd" "$dbname"
}

scichat()
{
    local dbusr=scichat
    local dbpwd=$(newpwd)
    local dbname=scichatdb
    local path; path="scichat/envfiles"
    mkdir -p "$path"
    cp ../services/scichat-loopback/scichat/envfiles/datasources.json "$path"/
    sed -i -e '/"user":/ s/"[^"]*"\(,\?\)\s*$/"'$dbusr'"\1/' \
        -e '/"password":/ s/"[^"]*"\(,\?\)\s*$/"'$dbpwd'"\1/' \
        -e '/"database":/ s/"[^"]*"\(,\?\)\s*$/"'$dbname'"\1/' \
        "$path"/datasources.json
    createUserCmd mongodb/scichat.js "$dbusr" "$dbpwd" "$dbname"
}

# go to the script directory before creating any files
scriptpath="$(readlink -f "$0")"
scriptdir="$(dirname "$scriptpath")"
cd "$scriptdir"

mongodb
catamel
scichat

# vim: set ts=4 sw=4 sts=4 tw=0 et:
