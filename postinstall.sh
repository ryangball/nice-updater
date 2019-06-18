#!/bin/bash

# Written by Ryan Ball
# https://github.com/ryangball/nice-updater

# These variables will be automagically updated if you run build.sh, no need to modify them
mainDaemonPlist="/Library/LaunchDaemons/com.github.ryangball.nice_updater.plist"
mainOnDemandDaemonPlist="/Library/LaunchDaemons/com.github.ryangball.nice_updater_on_demand.plist"
preferenceFileFullPath="/Library/Preferences/com.github.ryangball.nice_updater.prefs.plist"
identifier="com.github.ryangball.nice_updater"

# Set permissions on LaunchDaemon and Script
chown root:wheel "$mainDaemonPlist"
chmod 644 "$mainDaemonPlist"
chown root:wheel "$mainOnDemandDaemonPlist"
chmod 644 "$mainOnDemandDaemonPlist"
chown root:wheel "$preferenceFileFullPath"
chmod 644 "$preferenceFileFullPath"
chown root:wheel /Library/Scripts/nice_updater.sh
chmod 755 /Library/Scripts/nice_updater.sh

# Load our LaunchDaemons
/bin/launchctl load -w "$mainDaemonPlist"
/bin/launchctl load -w "$mainOnDemandDaemonPlist"

# Start the main LaunchDaemon
/bin/launchctl start "$identifier"

exit 0
