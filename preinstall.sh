#!/bin/bash

# These variables will be automagically updated if you run build.sh, no need to modify them
mainDaemonPlist="/Library/LaunchDaemons/com.github.grahampugh.nice_updater.plist"
mainOnDemandDaemonPlist="/Library/LaunchDaemons/com.github.grahampugh.nice_updater_on_demand.plist"
watchPathsPlist="/Library/Preferences/com.github.grahampugh.nice_updater.trigger.plist"

# Stop our LaunchDaemons
/bin/launchctl unload -w "$mainOnDemandDaemonPlist"
/bin/launchctl unload -w "$mainDaemonPlist"

# Create the WatchPaths file that triggers the On-Demand LaunchDaemon
/usr/bin/defaults write "$watchPathsPlist" update_key -string none
/usr/bin/plutil -convert xml1 "$watchPathsPlist"
/bin/chmod 666 "$watchPathsPlist"

exit 0
