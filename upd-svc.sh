#!/bin/sh
# upd-svc.sh
# Build script for running regularily in a crontab for example.
# This script rebuilds all SciCat services from source and pushes the resulting
# images to the registry as defined in $SC_SITECONFIG/general.rc
#
# Add this script to a crontab like this for building images repeatedly:
# cd $HOME/scicat; export SC_SITECONFIG=$(pwd)/<sitecfg>; ./deploy/upd-svc.sh update buildlog/readme.md; ./deploy/upd-svc.sh build buildlog/readme.md
# Add this script to a crontab like this for restarting regularly:
# cd $HOME/scicat; export SC_SITECONFIG=$(pwd)/<sitecfg>; ./deploy/upd-svc.sh update buildlog/readme.md; ./deploy/upd-svc.sh restart buildlog/readme.md
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
restart="$(getScriptFlags restart "$@")"
[ -z "$update" ] || action=update
[ -z "$build" ] || action=build
[ -z "$restart" ] || action=restart

# log file can be provided as 1st or 2nd arg
logfn="$(readlink -f "$1")"
[ -f "$logfn" ] || logfn="$(readlink -f "$2")"

loadSiteConfig
checkVars SC_NAMESPACE || exit 1

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

datestr () { TZ='Europe/Berlin' date; }

foreachsvc()
{
    local start
    local tocfn="$1"
    (echo "# $(datestr)"; echo) > "$tocfn"
    echo "   * [Updating the deploy script](#updating-the-deploy-script)" >> "$tocfn"
    local descr; local cmd
    if [ "$action" = "build" ]; then
        cmd="buildonly"; descr="Building"
    elif [ "$action" = "restart" ]; then
        cmd="nobuild"; descr="Restarting"
    fi
    local descr_low; descr_low="$(echo $descr | tr '[:upper:]' '[:lower:]')"
    for svc in catamel catanie landing scichat-loopback;
    do
        start=$(ts)
        echo "# $descr $svc"
        datestr
        echo '```'
        if "$scriptdir/services/$svc"/*.sh $cmd;
        then
            echo "   * [{+ $svc +}](#$descr_low-$svc)" >> "$tocfn"
        else
            echo "   * [{- $svc -}](#$descr_low-$svc)" >> "$tocfn"
        fi
        echo '```'
        timeDelta=$(($(ts)-start))
        SC_TIMESUM=$((SC_TIMESUM+timeDelta))
        echo "Completed in $(timeFmt $timeDelta)."
        echo
    done
    if [ "$action" = "build" ]; then
        # remove all containers built
        $DOCKER_CMD rmi -f $($DOCKER_CMD images -a -q)
    fi
    echo >> "$tocfn"
    echo "Overall time for $descr_low: $(timeFmt $SC_TIMESUM)."
}

if [ ! -f "$logfn" ]; then
    echo "No log file provided, giving up!"
elif [ ! -z "$update" ]; then
    #rm -f "$logfn"
    update > "$logfn" 2>&1
elif [ ! -z "$build" ] || [ ! -z "$restart" ]; then
    # assumes *update* ran before
    tocfn="$(mktemp)"
    foreachsvc "$tocfn" >> "$logfn" 2>&1
    cat "$logfn" >> "$tocfn"
    cat "$tocfn" > "$logfn"
    #chmod g+rw "$logfn"
    branch="${SC_NAMESPACE}-$action"
    cd "$(dirname "$logfn")" \
        && git checkout -B "$branch" \
        && git commit -m "latest $action" "$(basename "$logfn")" \
        && git push -u origin "$branch"
else
    echo "Usage: $0 (update|build|restart) <log file>"
fi

# vim: set ts=4 sw=4 sts=4 tw=0 et:
