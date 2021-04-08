#!/bin/sh
# Builds all SciCat services and pushes the images to the registry
# as defined by $SC_SITECONFIG/general.rc
#
# Add this script to a crontab like this:
# ./daily_build.sh > $HOME/scicat/buildlog/log.md 2>&1; (cd $HOME/scicat/buildlog; git ci -m "latest build" log.md && git push)

# get the script directory before creating any files
scriptdir="$(dirname "$(readlink -f "$0")")"

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

timeSum=0
echo "# Updating the deploy script"
echo '```'
cd "$scriptdir"
git stash save && git pull --rebase && git stash pop
echo '```'

for svc in catamel catanie landing scichat-loopback;
do
    echo "# $svc"
    start=$(ts)
    echo "Attempting build at $(date)"
    echo '```'
    sh "$scriptdir/services/$svc"/*.sh buildonly
    echo '```'
    timeDelta=$(($(ts)-start))
    timeSum=$((timeSum+timeDelta))
    echo "Building $svc took $(timeFmt $timeDelta)."
    echo
done
echo "Overall time: $(timeFmt $timeSum)."


# vim: set ts=4 sw=4 sts=4 tw=0 et:
