#!/bin/bash

# postinstall script for use in a Jamf policy
# allows defaults to be tweaked from within a Jamf Pro policy
#
# parameters as follows:
#
# 4  - Start interval (hour of the day), e.g. 13 = 1pm
# 5  - Start interval (minute of the hour), e.g. 45 = 45 mins past the hour, e.g. 13:45
# 6  - Alert timeout in seconds. The time that the alert should stay on the screen
#          (should be less than the start interval)
# 7  - Max number of deferrals (default is 11 so first message says "10 remaining alerts")
# 8  - Number of days to wait after an empty software update run (default is 3)
# 9  - Number of days to wait after a full software update is carried out (default is 14)
# 10 - Custom icon path - must exist on the device before the policy is run

[[ $4 ]] && startIntervalHour=$4
[[ $5 ]] && startIntervalMinute=$5
[[ $6 ]] && alertTimeoutSeconds=$6
[[ $7 ]] && maxNotificationCount=$7
[[ $8 ]] && afterEmptyUpdateDelayDayCount=$8
[[ $9 ]] && afterFullUpdateDelayDayCount=$9
[[ $10 ]] && customIconPath="$10"

# These variables will be automagically updated if you run build.sh, no need to modify them
mainDaemonPlist="/Library/LaunchDaemons/com.github.grahampugh.nice_updater.plist"
mainOnDemandDaemonPlist="/Library/LaunchDaemons/com.github.grahampugh.nice_updater_on_demand.plist"
preferenceFileFullPath="/Library/Preferences/com.github.grahampugh.nice_updater.prefs.plist"

# safety net
[[ $maxNotificationCount < 3 ]] && maxNotificationCount=''

# Stop our LaunchDaemon
echo "Stopping daemon..."
/bin/launchctl stop com.github.grahampugh.nice_updater
/bin/launchctl unload -w "$mainDaemonPlist"
/bin/launchctl unload -w "$mainOnDemandDaemonPlist"

# update the icon path
if [[ -f "$customIconPath" ]]; then
    echo "Custom icon specified. Copying to /Library/Scripts/nice_updater_custom_icon.png..."
    cp "$customIconPath" /Library/Scripts/nice_updater_custom_icon.png
    chown root:wheel /Library/Scripts/nice_updater_custom_icon.png
    chmod 644 /Library/Scripts/nice_updater_custom_icon.png
fi

# update the start time intervals
if [[ $startIntervalHour || $startIntervalMinute ]]; then
    echo "Reconfiguring StartCalendarInterval..."
    /usr/libexec/PlistBuddy -c "Delete :StartCalendarInterval" "$mainDaemonPlist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval dict" "$mainDaemonPlist"
    [[ $startIntervalHour ]] && /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:Hour integer '$startIntervalHour'" "$mainDaemonPlist"
    [[ $startIntervalMinute ]] && /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:Minute integer '$startIntervalMinute'" "$mainDaemonPlist"
fi

# update the preferences
if [[ $alertTimeoutSeconds ]]; then
    echo "Reconfiguring Nice Updater preferences..."
    # safety net
    [[ $maxNotificationCount < 3 ]] && maxNotificationCount=''

    [[ $alertTimeoutSeconds ]] && defaults write "$preferenceFileFullPath" AlertTimeout -int "$alertTimeoutSeconds"
    [[ $maxNotificationCount ]] && defaults write "$preferenceFileFullPath" MaxNotificationCount -int "$maxNotificationCount"
    [[ $afterEmptyUpdateDelayDayCount ]] && defaults write "$preferenceFileFullPath" AfterEmptyUpdateDelayDayCount -int "$afterEmptyUpdateDelayDayCount"
    [[ $afterFullUpdateDelayDayCount ]] && defaults write "$preferenceFileFullPath" AfterFullUpdateDelayDayCount -int "$afterFullUpdateDelayDayCount"
fi

# Start our LaunchDaemon
echo "Restarting daemon..."
/bin/launchctl load -w "$mainDaemonPlist"
/bin/launchctl load -w "$mainOnDemandDaemonPlist"
/bin/launchctl start com.github.grahampugh.nice_updater
