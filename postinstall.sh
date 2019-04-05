#!/bin/bash

# Set permissions on LaunchDaemon and Script
chown root:wheel /Library/LaunchDaemons/com.github.ryangball.nice_updater.plist
chmod 644 /Library/LaunchDaemons/com.github.ryangball.nice_updater.plist
chown root:wheel /Library/LaunchDaemons/com.github.ryangball.nice_updater_on_demand.plist
chmod 644 /Library/LaunchDaemons/com.github.ryangball.nice_updater_on_demand.plist
chown root:wheel /Library/Scripts/nice_updater.sh
chmod 755 Library/Scripts/nice_updater.sh

# Start our LaunchDaemons
/bin/launchctl load -w /Library/LaunchDaemons/com.github.ryangball.nice_updater.plist
/bin/launchctl load -w /Library/LaunchDaemons/com.github.ryangball.nice_updater_on_demand.plist

exit 0