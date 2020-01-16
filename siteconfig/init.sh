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
    mkdir -p catamel/envfiles/
    cp ../services/catamel/dacat-api-server/envfiles/datasources.json \
        catamel/envfiles/
    sed -i -e '/"user":/ s/"[^"]*"\(,\?\)\s*$/"'$mongousr'"\1/' \
        -e '/"password":/ s/"[^"]*"\(,\?\)\s*$/"'$mongopwd'"\1/' \
        catamel/envfiles/datasources.json
}

mongodb
catamel

# vim: set ts=4 sw=4 sts=4 tw=0 et:
