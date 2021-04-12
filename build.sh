#!/bin/sh
# Build script for running regularily in a crontab for example.
# This script rebuilds all SciCat services from source and pushes the resulting
# images to the registry as defined in $SC_SITECONFIG/general.rc
#
# Add this script to a crontab like this:
# cd $HOME/scicat; export SC_SITECONFIG=$(pwd)/<sitecfg>; ./deploy/build.sh update buildlog/log.md; ./deploy/build.sh build buildlog/log.md
# - Assuming the following directory structure:
#   - `$HOME/scicat`
#     - `<sitecfg>` ($SC_SITECONFIG directory, file 'general.rc' is needed only)
#     - `deploy` (git repo containing this script and SciCat deploy scripts)
#     - `buildlog` (gitlab snippet or gist repo to share the build log file)
# - do not forget to
#   - clone the deploy script repo
#   - clone the buildlog repo, set user&pwd, upload ssh keys
#   - add the building user to the docker group
#   - copy the $SC_SITECONFIG/general.rc from elsewhere

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"
. "$scriptdir/services/deploytools"

# get given command line flags
update="$(getScriptFlags update "$@")"
build="$(getScriptFlags build "$@")"
# log file can be provided as 1st or 2nd arg
logfn="$(readlink -f "$1")"
[ -f "$logfn" ] || logfn="$(readlink -f "$2")"

ts() {
    date +%s
}
timeFmt() {
    local secs="$1"
    if [ "$secs" -lt 60 ]; then
        echo "$secs s"
    else
        echo "$((secs/60)) m, $((secs-60*(secs/60))) s"
    fi
}

update() {
    export SC_TIMESUM=0
    echo "# Updating the deploy script"
    echo '```'
    cd "$scriptdir"
    git stash save && git pull --rebase && git stash pop
    echo '```'
}

build() {
    local start
    local tocfn="$1"
    (echo "# $(date)"; echo) > "$tocfn"
    echo "   * [Updating the deploy script](#updating-the-deploy-script)" >> "$tocfn"
    for svc in catamel catanie landing scichat-loopback;
    do
        start=$(ts)
        echo "# $svc"
        echo "Attempting build at $(date)"
        echo '```'
        if "$scriptdir/services/$svc"/*.sh buildonly;
        then
            echo "   * [{+ $svc +}](#$svc)" >> "$tocfn"
        else
            echo "   * [{- $svc -}](#$svc)" >> "$tocfn"
        fi
        echo '```'
        timeDelta=$(($(ts)-start))
        SC_TIMESUM=$((SC_TIMESUM+timeDelta))
        echo "Building $svc took $(timeFmt $timeDelta)."
        echo
    done
    echo >> "$tocfn"
    echo "Overall time: $(timeFmt $SC_TIMESUM)."
}

if [ ! -f "$logfn" ]; then
    echo "No log file provided, giving up!"
elif [ ! -z "$update" ]; then
    update > "$logfn" 2>&1
elif [ ! -z "$build" ]; then
    tocfn="$(mktemp)"
    build "$tocfn" >> "$logfn" 2>&1
    cat "$logfn" >> "$tocfn"
    mv "$tocfn" "$logfn"
    cd "$(dirname "$logfn")" && \
        git commit -m "latest build" "$(basename "$logfn")" && git push
else
    echo "Usage: $0 (update|build') <log file>"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
