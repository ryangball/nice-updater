#!/bin/bash

# Stop our LaunchDaemons
/bin/launchctl unload -w /Library/LaunchDaemons/com.github.ryangball.nice_updater_on_demand.plist
/bin/launchctl unload -w /Library/LaunchDaemons/com.github.ryangball.nice_updater.plist

# Create the WatchPaths file that triggers the On-Demand LaunchDaemon
/usr/bin/defaults write /Library/Preferences/com.github.ryangball.nice_updater_trigger.plist update_key none
/bin/chmod 666 /Library/Preferences/com.github.ryangball.nice_updater_trigger.plist

exit 0
