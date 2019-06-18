#!/bin/bash

# Written by Ryan Ball
# Obtained from https://github.com/ryangball/nice-updater

# These variables will be automagically updated if you run build.sh, no need to modify them
mainDaemonPlist="/Library/LaunchDaemons/com.github.ryangball.nice_updater.plist"
mainOnDemandDaemonPlist="/Library/LaunchDaemons/com.github.ryangball.nice_updater_on_demand.plist"
watchPathsPlist="/Library/Preferences/com.github.ryangball.nice_updater.trigger.plist"
yoPath="/Applications/Utilities/yo.app/Contents/MacOS/yo"

if [[ ! -e "$yoPath" ]]; then
    echo "yo.app is not installed; installing..."
    /usr/local/bin/jamf policy -event yo
    if [[ ! -e "$yoPath" ]]; then
        echo "The installation failed; exiting."
        exit 1
    fi
fi

# Stop our LaunchDaemons
/bin/launchctl unload -w "$mainOnDemandDaemonPlist"
/bin/launchctl unload -w "$mainDaemonPlist"

# Create the WatchPaths file that triggers the On-Demand LaunchDaemon
/usr/bin/defaults write "$watchPathsPlist" update_key -string none
/usr/bin/plutil -convert xml1 "$watchPathsPlist"
/bin/chmod 666 "$watchPathsPlist"

exit 0
