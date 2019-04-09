#!/bin/bash
# shellcheck disable=SC2116,SC2002

# The title of the message that is displayed when software updates are in progress and a user is logged in
updateInProgressTitle="Software Update In Progress"

# The message that is displayed when software updates are in progress and a user is logged in
updateInProgressMessage="Apple Software Updates are being installed now. Please do not turn off this Mac, it will automatically reboot once the installation is complete.

If you see this message for more than 30 minutes please call the Help Desk."

# The message that a user will receive if they login to the Mac WHILE updates are being performed
loginAfterUpdatesInProgressMessage="Unfortunately you logged in while Apple Software Updates were being installed. This Mac will restart in 60 seconds.

If you have any questions please call the Help Desk."

# The location of your log, keep in mind that if you nest the log into a folder that does not exist you'll need to mkdir -p the directory as well
log="/Library/Logs/Nice_Updater.log"

# The number of days to check for updates after a full update has been performed
afterFullUpdateDelayDayCount="14"

# The number of days to check for updates after a updates were checked, but no updates were available
afterEmptyUpdateDelayDayCount="3"

# The number of times to alert a single user prior to forcibly installing updates
maxNotificationCount="3"

# The full path of the yo.app binary
yo="/Applications/Utilities/yo.app/Contents/MacOS/yo"

# The full path of the preference file which will store update information
# If you modify this you need to modify the LaunchDaemon plists as well
mainPreferencePlist="/Library/Preferences/com.github.ryangball.nice_updater.plist"

# The name of the main LaunchDaemon plist
# If you modify this you need to modify the LaunchDaemon plists as well
mainLDPlist="com.github.ryangball.nice_updater_on_demand.plist"

# Full path of the plist file which will be used as the watchpaths file
# If you change this you need to modify the preinstall/postinstall scripts
# and the com.github.ryangball.nice_updater_on_demand.plist contents
watchPathsPlist="/Library/Preferences/com.github.ryangball.nice_updater_trigger.plist"

###### Variables below this point are not intended to be modified #####
scriptName=$(basename "$0")
osVersion=$(sw_vers -productVersion)
osMinorVersion=$(echo "$osVersion" | awk -F. '{print $2}')
[[ "$osMinorVersion" -le 12 ]] && icon="/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"
[[ "$osMinorVersion" -ge 13 ]] && icon="/System/Library/CoreServices/Install Command Line Developer Tools.app/Contents/Resources/SoftwareUpdate.icns"

function writelog () {
    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    /bin/echo "${1}"
    /bin/echo "$DATE" " $1" >> "$log"
}

function finish () {
    writelog "======== Finished $scriptName ========"
    exit "$1"
}

function record_last_full_update () {
    writelog "Done with update process; recording last full update time."
    /usr/libexec/PlistBuddy -c "Delete :last_full_update_time" $mainPreferencePlist 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :last_full_update_time string $(date +%Y-%m-%d\ %H:%M:%S)" $mainPreferencePlist

    writelog "Clearing user alert data."
    /usr/libexec/PlistBuddy -c "Delete :users" $mainPreferencePlist

    writelog "Clearing On-Demand Update Key."
    /usr/libexec/PlistBuddy -c "Delete :update_key" $mainPreferencePlist 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :update_key string $updateKey" $mainPreferencePlist 2> /dev/null
}

function initiate_restart () {
    writelog "Initiating restart now..."
    kill "$jamfHelperPID" > /dev/null 2>&1 && wait $! > /dev/null
    /usr/local/bin/jamf reboot -background -immediately | while read -r LINE; do writelog "$LINE"; done
    finish 0
}

function trigger_updates () {
    # Run softwareupdate and clean up the output so we only see what is necessary.
    # 10.11 and above allows you to skip the update scan, so we can do that since we already scanned for updates initially
    [[ "$osMinorVersion" -ge 11 ]] && noScan='--no-scan'
    # shellcheck disable=SC2086
    /usr/sbin/softwareupdate --install $1 "$noScan" | \
        grep --line-buffered -v -E 'Software Update Tool|Copyright|Finding|Downloaded|Done\.|You have installed one|Please restart immediately\.|^$' | \
        while read -r LINE; do writelog "$LINE"; done
    sleep 5
}

function compare_date () {
    then_unix="$(date -j -f "%Y-%m-%d %H:%M:%S" "$1" +%s)"  # convert date to unix timestamp
    now_unix="$(date +'%s')"    # Get timestamp from right now
    delta=$(( now_unix - then_unix ))   # Will get the amount of time in seconds between then and now
    daysAgo="$((delta / (60*60*24)))"   # Converts the seconds to days
    echo $daysAgo
    return
}

function alert_user () {
    local subtitle="$1"
    [[ "$notificationsLeft" == "1" ]] && local subtitle="1 remaining alert before auto-install."
    [[ "$notificationsLeft" == "0" ]] && local subtitle="Install now to avoid interruptions."

    writelog "Stopping NiceUpdater On-Demand LaunchDaemon..."
    launchctl unload -w "/Library/LaunchDaemons/$mainLDPlist"

    writelog "Generating NiceUpdater Update Key..."
    updateKey=$(cat /dev/urandom | env LC_CTYPE=C tr -dc a-zA-Z0-9 | head -c 16; echo)
    /usr/libexec/PlistBuddy -c "Delete :update_key" $mainPreferencePlist 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :update_key string $updateKey" $mainPreferencePlist 2> /dev/null

    writelog "Clearing NiceUpdater On-Demand Trigger file..."
    /usr/libexec/PlistBuddy -c "Clear string" $watchPathsPlist

    writelog "Restarting NiceUpdater On-Demand LaunchDaemon..."
    launchctl load -w "/Library/LaunchDaemons/$mainLDPlist"

    writelog "Notifying $loggedInUser of available updates..."
    /bin/launchctl asuser "$loggedInUID" "$yo" -t "Software Updates Required" -s "$subtitle" -n "Mac will restart after installation." \
        -o "Cancel" -b "Install Now" -B "defaults write $watchPathsPlist update_key $updateKey"
    /usr/libexec/PlistBuddy -c "Add :users dict" $mainPreferencePlist 2> /dev/null
    /usr/libexec/PlistBuddy -c "Delete :users:$loggedInUser" $mainPreferencePlist 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :users:$loggedInUser dict" $mainPreferencePlist
    /usr/libexec/PlistBuddy -c "Add :users:$loggedInUser:alert_count integer $2" $mainPreferencePlist
}

function alert_logic () {
    notificationCount=$(/usr/libexec/PlistBuddy -c "Print :users:$loggedInUser:alert_count" $mainPreferencePlist 2> /dev/null | xargs)
    if [[ "$notificationCount" -ge "$maxNotificationCount" ]]; then
        writelog "$loggedInUser has been notified $notificationCount times; not waiting any longer."
        /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -lockHUD -title "$updateInProgressTitle" -alignHeading center -alignDescription natural -description "$updateInProgressMessage" -icon "$icon" -iconSize 100 &
        jamfHelperPID=$(echo $!)
        writelog "Installing updates that DO require a restart..."
        trigger_updates "--recommended"
        record_last_full_update
        initiate_restart
    else
        ((notificationCount++))
        notificationsLeft="$((maxNotificationCount - notificationCount))"
        alert_user "$notificationsLeft remaining alerts before auto-install." "$notificationCount"
    fi
}

function update_check () {
    writelog "Determining available Software Updates for macOS $osVersion..."
    updates=$(/usr/sbin/softwareupdate -l)
    updatesNoRestart=$(echo "$updates" | /usr/bin/grep -v restart | /usr/bin/grep -B1 recommended | /usr/bin/grep -v recommended | /usr/bin/awk '{print $2}' | /usr/bin/awk '{printf "%s ", $0}')
    updatesRestart=$(echo "$updates" | grep -i restart | grep -v '\*' | cut -d , -f 1)
    updateCount=$(echo "$updates" | grep -i -c recommended)

    if [[ "$updateCount" -gt "0" ]]; then
        # Download the updates
        writelog "Downloading $updateCount update(s)..."
        [[ "$osMinorVersion" -ge 11 ]] && noScan='--no-scan'
        /usr/sbin/softwareupdate --download --recommended "$noScan" | grep --line-buffered Downloaded | while read -r LINE; do writelog "$LINE"; done

        # Don't waste the user's time - install any updates that do not require a restart first.
        if [[ -n "$updatesNoRestart" ]]; then
            writelog "Installing updates that DO NOT require a restart in the background..."
            trigger_updates "$updatesNoRestart"
        fi

        # If the script moves past this point, a restart is required.
        if [[ -n "$updatesRestart" ]]; then
            writelog "A restart is required for remaining updates."

            # If no user is logged in, just update and restart. Check the user now as some time has past since the script began.
            loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
            loggedInUID=$(id -u "$loggedInUser")
            if [[ "$loggedInUser" == "root" ]] || [[ -z "$loggedInUser" ]]; then
                writelog "No user logged in."
                writelog "Installing updates that DO require a restart..."
                trigger_updates "--recommended"
                record_last_full_update
                # Some time has passed since we started to install the updates, check for a logged in user once more
                loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
                if [[ ! "$loggedInUser" == "root" ]] && [[ -n "$loggedInUser" ]]; then
                    writelog "$loggedInUser has logged in since we started to install updates, alerting them of pending restart."
                    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -lockHUD -title "$updateInProgressTitle" -alignHeading center -alignDescription natural -description "$loginAfterUpdatesInProgressMessage" -icon "$icon" -iconSize 100 -timeout "60"
                    initiate_restart
                else
                    # Still nobody is logged in, restart
                    initiate_restart
                fi
            fi
            # Getting here means a user is logged in, alert them that they will need to install and restart
            alert_logic
        else
            record_last_full_update
            writelog "No updates that require a restart available; exiting."
            finish 0
        fi
    else
        writelog "No updates at this time; exiting."
        /usr/libexec/PlistBuddy -c "Delete :last_empty_update_time" $mainPreferencePlist 2> /dev/null
        /usr/libexec/PlistBuddy -c "Add :last_empty_update_time string $(date +%Y-%m-%d\ %H:%M:%S)" $mainPreferencePlist
        finish 0
    fi
}

on_demand () {
    # This function is intended to be run from a LaunchDaemon using WatchPaths that is triggered when the user
    # clicks the "Install now" at a generated prompt. A randomized key is inserted simultaneously in both the
    # WatchPaths file and a seperate preference file, and when confirmed for a match here, it is allowed to run.
    # This elimantes any accidental runs if the WatchPaths file gets modified for any reason.

    writelog " "
    writelog "======== Starting $scriptName ========"
    writelog "Verifying On-Demand Update Key..."
    updateKey=$(defaults read $mainPreferencePlist update_key)
    testUpdateKey=$(defaults read $watchPathsPlist update_key)
    if [[ ! "$updateKey" == "$testUpdateKey" ]]; then
        writelog "On-Demand Update Keys don't match; exiting."
        finish 0
    else
        writelog "On-Demand Update Keys match; continuing."
        /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -lockHUD -title "$updateInProgressTitle" -alignHeading center -alignDescription natural -description "$updateInProgressMessage" -icon "$icon" -iconSize 100 &
        jamfHelperPID=$(echo $!)
        writelog "Installing updates that DO require a restart..."
        trigger_updates "--recommended"
        record_last_full_update
        initiate_restart
    fi
}

function main () {
    # This function is intended to be run from a LaunchDaemon at intervals

    writelog " "
    writelog "======== Starting $scriptName ========"

    # See if we are blocking updates, if so exit
    updatesBlocked=$(/usr/libexec/PlistBuddy -c "Print :updates_blocked" $mainPreferencePlist 2> /dev/null | xargs 2> /dev/null)
    if [[ "$updatesBlocked" == "true" ]]; then
        writelog "Updates are blocked for this client at this time; exiting."
        finish 0
    fi

    # Check the last time we had a full successful update
    updatesAvailable=$(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist LastRecommendedUpdatesAvailable | /usr/bin/awk '{ if  (NF > 2) {print $1 " "  $2} else { print $0 }}')
    if [[ "$updatesAvailable" -gt "0" ]]; then
        writelog "At least one recommended update was marked available from a previous check."
        update_check
    else
        lastFullUpdateTime=$(/usr/libexec/PlistBuddy -c "Print :last_full_update_time" $mainPreferencePlist 2> /dev/null | xargs 2> /dev/null)
        lastEmptyUpdateTime=$(/usr/libexec/PlistBuddy -c "Print :last_empty_update_time" $mainPreferencePlist 2> /dev/null | xargs 2> /dev/null)
        if [[ -n "$lastFullUpdateTime" ]]; then
            daysSinceLastFullUpdate="$(compare_date "$lastFullUpdateTime")"
            if [[ "$daysSinceLastFullUpdate" -ge "$afterFullUpdateDelayDayCount" ]]; then
                writelog "$afterFullUpdateDelayDayCount or more days have passed since last full update."
                update_check
            else
                writelog "Less than $afterFullUpdateDelayDayCount days since last full update; exiting."
                finish 0
            fi
        elif [[ -n "$lastEmptyUpdateTime" ]]; then
            daysSinceLastEmptyUpdate="$(compare_date "$lastEmptyUpdateTime")"
            if [[ "$daysSinceLastEmptyUpdate" -ge "$afterEmptyUpdateDelayDayCount" ]]; then
                writelog "$afterEmptyUpdateDelayDayCount or more days have passed since last empty update check."
                update_check
            else
                writelog "Less than $afterEmptyUpdateDelayDayCount days since last empty update check; exiting."
                finish 0
            fi
        else
            writelog "This device might not have performed a full update yet."
            update_check
        fi
    fi

    finish 0
}

"$@"