#!/bin/bash

# These variables will be automagically updated if you run build.sh, no need to modify them
mainOnDemandDaemonPlist="/Library/LaunchDaemons/com.github.grahampugh.nice_updater_on_demand.plist"
watchPathsPlist="/Library/Preferences/com.github.grahampugh.nice_updater.trigger.plist"
preferenceFileFullPath="/Library/Preferences/com.github.grahampugh.nice_updater.prefs.plist"

###### Variables below this point are not intended to be modified #####
helperTitle=$(defaults read "$preferenceFileFullPath" UpdateRequiredTitle)
helperDesc=$(defaults read "$preferenceFileFullPath" UpdateRequiredMessage)
alertTimeout=$(defaults read "$preferenceFileFullPath" AlertTimeout)
updateInProgressTitle=$(defaults read "$preferenceFileFullPath" UpdateInProgressTitle)
updateInProgressMessage=$(defaults read "$preferenceFileFullPath" UpdateInProgressMessage)
loginAfterUpdatesInProgressMessage=$(defaults read "$preferenceFileFullPath" LoginAfterUpdatesInProgressMessage)
log=$(defaults read "$preferenceFileFullPath" Log)
afterFullUpdateDelayDayCount=$(defaults read "$preferenceFileFullPath" AfterFullUpdateDelayDayCount)
afterEmptyUpdateDelayDayCount=$(defaults read "$preferenceFileFullPath" AfterEmptyUpdateDelayDayCount)
maxNotificationCount=$(defaults read "$preferenceFileFullPath" MaxNotificationCount)
iconCustomPath=$(defaults read "$preferenceFileFullPath" IconCustomPath)

scriptName=$(basename "$0")
osVersion=$(sw_vers -productVersion)
osMinorVersion=$(echo "$osVersion" | awk -F. '{print $2}')
osReleaseVersion=$(echo "$osVersion" | awk -F. '{print $3}')
JAMFHELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# set default icon if not included in build
if [[ -f "$iconCustomPath" ]]; then
    icon="$iconCustomPath"
elif [[ "$osMinorVersion" -le 12 ]]; then
    icon="/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"
elif [[ "$osMinorVersion" -ge 13 ]]; then
    icon="/System/Library/CoreServices/Install Command Line Developer Tools.app/Contents/Resources/SoftwareUpdate.icns"
fi

writelog() {
    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    /bin/echo "${1}"
    /bin/echo "$DATE" " $1" >> "$log"
}

finish() {
    writelog "======== Finished $scriptName ========"
    exit "$1"
}

random_delay() {
    delay_time=$(( ($RANDOM % 300)+1 ))
    writelog "Delaying software update check by ${delay_time}s."
    sleep ${delay_time}s
}

record_last_full_update() {
    writelog "Done with update process; recording last full update time."
    /usr/libexec/PlistBuddy -c "Delete :last_full_update_time" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :last_full_update_time string $(date +%Y-%m-%d\ %H:%M:%S)" $preferenceFileFullPath

    writelog "Clearing user alert data."
    /usr/libexec/PlistBuddy -c "Delete :users" $preferenceFileFullPath

    writelog "Clearing On-Demand Update Key."
    /usr/libexec/PlistBuddy -c "Delete :update_key" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :update_key array" $preferenceFileFullPath 2> /dev/null
}

initiate_restart() {
    writelog "Initiating $restartType now..."
    kill "$jamfHelperPID" > /dev/null 2>&1 && wait $! > /dev/null
    if [[ "$restartType" = "restart" ]]; then
        /usr/local/bin/jamf reboot -background -immediately | while read -r LINE; do writelog "$LINE"; done
        finish 0
    elif [[ "$restartType" = "shutdown" ]]; then
        /sbin/halt | while read -r LINE; do writelog "$LINE"; done
        finish 0
    fi
}

trigger_updates() {
    # Run softwareupdate and clean up the output so we only see what is necessary.
    # 10.11 and above allows you to skip the update scan, so we can do that since we already scanned for updates initially
    [[ "$osMinorVersion" -ge 11 ]] && noScan='--no-scan'
    # shellcheck disable=SC2086
    updateOutput=$(/usr/sbin/softwareupdate --install $1 "$noScan" | \
        grep --line-buffered -v -E 'Software Update Tool|Copyright|Finding|Downloaded|Done\.|You have installed one|Please restart immediately\.|select Shut Down from the Apple menu|^$' | \
        while read -r LINE; do writelog "$LINE"; done)
    if [[ "$updateOutput" =~ "select Shut Down from the Apple menu" ]]; then
        restartType="shutdown"
    else
        restartType="restart"
    fi
    sleep 5
}

compare_date() {
    then_unix="$(date -j -f "%Y-%m-%d %H:%M:%S" "$1" +%s)"  # convert date to unix timestamp
    now_unix="$(date +'%s')"    # Get timestamp from right now
    delta=$(( now_unix - then_unix ))   # Will get the amount of time in seconds between then and now
    daysAgo="$((delta / (60*60*24)))"   # Converts the seconds to days
    echo $daysAgo
    return
}

alert_user() {
    local subtitle="$1"
    [[ "$notificationsLeft" == "1" ]] && local subtitle="1 remaining alert before auto-install."
    [[ "$notificationsLeft" == "0" ]] && local subtitle="No deferrals remaining! Click on \"Install Now\" to proceed"

    writelog "Stopping NiceUpdater On-Demand LaunchDaemon..."
    launchctl unload -w "$mainOnDemandDaemonPlist"

    writelog "Generating NiceUpdater Update Key..."
    updateKey=$(cat /dev/urandom | env LC_CTYPE=C tr -dc a-zA-Z0-9 | head -c 16; echo)
    /usr/libexec/PlistBuddy -c "Add :update_key array" $preferenceFileFullPath 2> /dev/null
    /usr/bin/plutil -insert update_key.0 -string "$updateKey" $preferenceFileFullPath

    writelog "Clearing NiceUpdater On-Demand Trigger file..."
    /usr/libexec/PlistBuddy -c "Delete :update_key" $watchPathsPlist 2> /dev/null

    writelog "Restarting NiceUpdater On-Demand LaunchDaemon..."
    launchctl load -w "$mainOnDemandDaemonPlist"

    if /usr/bin/pgrep jamfHelper ; then
    writelog "Existing JamfHelper window running... killing"
        /usr/bin/pkill jamfHelper
        sleep 3
    fi

    writelog "Notifying $loggedInUser of available updates..."
    if [[ "$notificationsLeft" == "0" ]]; then
        helperExitCode=$( "$JAMFHELPER" -windowType utility -lockHUD -title "$helperTitle" -heading "$subtitle" -description "$helperDesc" -button1 "Install Now" -defaultButton 1 -timeout 300 -icon "$icon" -iconSize 100 )
    else
        "$JAMFHELPER" -windowType utility -title "$helperTitle" -heading "$subtitle" -description "$helperDesc" -button1 "Install Now" -button2 "Cancel" -defaultButton 2 -cancelButton 2 -icon "$icon" -iconSize 100 &
        jamfHelperPID=$!
        # since the "cancel" exit code is the same as the timeout exit code, we
        # need to distinguish between the two. We use a while loop that checks
        # that the process exists every second. If so, count down 1 and check
        # again. If the process is gone, use `wait` to grab the exit code.
        timeLeft=$alertTimeout
        while [[ $timeLeft > 0 ]]; do
            if pgrep jamfHelper ; then
                # writelog "Waiting for timeout: $timeLeft remaining"
                sleep 1
                ((timeLeft--))
            else
                wait $jamfHelperPID
                helperExitCode=$?
                break
            fi
        done
        # if the process is still running, we need to kill it and give a fake
        # exit code
        if pgrep jamfHelper; then
            pkill jamfHelper
            helperExitCode=1
        else
            writelog "A button was pressed."
        fi
    fi
    # writelog "Response: $helperExitCode"
    if [[ $helperExitCode == 0 ]]; then
        writelog "User initiated installation."
        defaults write $watchPathsPlist update_key $updateKey
    elif [[ $helperExitCode == 2 ]]; then
        writelog "User cancelled installation."
    else
        writelog "Alert timed out without response."
        ((notificationCount--))
    fi

    /usr/libexec/PlistBuddy -c "Add :users dict" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Delete :users:$loggedInUser" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :users:$loggedInUser dict" $preferenceFileFullPath
    /usr/libexec/PlistBuddy -c "Add :users:$loggedInUser:alert_count integer $notificationCount" $preferenceFileFullPath
}

alert_logic() {
    notificationCount=$(/usr/libexec/PlistBuddy -c "Print :users:$loggedInUser:alert_count" $preferenceFileFullPath 2> /dev/null | xargs)
    if [[ "$notificationCount" -ge "$maxNotificationCount" ]]; then
        writelog "$loggedInUser has been notified $notificationCount times; not waiting any longer."
        "$JAMFHELPER" -windowType utility -lockHUD -title "$updateInProgressTitle" -alignHeading center -alignDescription natural -description "$updateInProgressMessage" -icon "$icon" -iconSize 100 &
        jamfHelperPID=$(echo $!)
        writelog "Installing updates that DO require a restart..."
        triggerOptions="--recommended"
        [[ "$osMinorVersion" -ge 14 || ("$osMinorVersion" -eq 13 && "$osReleaseVersion" -ge 4) ]] && triggerOptions+=" --restart"
        trigger_updates "$triggerOptions"

        record_last_full_update
        initiate_restart
    else
        ((notificationCount++))
        notificationsLeft="$((maxNotificationCount - notificationCount))"
        writelog "$notificationsLeft remaining alerts before auto-install."
        alert_user "$notificationsLeft remaining alerts before auto-install." "$notificationCount"
    fi
}

update_check() {
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
            loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
            loggedInUID=$(id -u "$loggedInUser")
            if [[ "$loggedInUser" == "root" ]] || [[ -z "$loggedInUser" ]]; then
                writelog "No user logged in."
                writelog "Installing updates that DO require a restart..."
                trigger_updates "--recommended --restart"
                record_last_full_update
                # Some time has passed since we started to install the updates, check for a logged in user once more
                loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
                if [[ ! "$loggedInUser" == "root" ]] && [[ -n "$loggedInUser" ]]; then
                    writelog "$loggedInUser has logged in since we started to install updates, alerting them of pending restart."
                    "$JAMFHELPER" -windowType utility -lockHUD -title "$updateInProgressTitle" -alignHeading center -alignDescription natural -description "$loginAfterUpdatesInProgressMessage" -icon "$icon" -iconSize 100 -timeout "60"
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
        /usr/libexec/PlistBuddy -c "Delete :last_empty_update_time" $preferenceFileFullPath 2> /dev/null
        /usr/libexec/PlistBuddy -c "Add :last_empty_update_time string $(date +%Y-%m-%d\ %H:%M:%S)" $preferenceFileFullPath
        /usr/libexec/PlistBuddy -c "Delete :users" $preferenceFileFullPath 2> /dev/null
        finish 0
    fi
}

on_demand() {
    # This function is intended to be run from a LaunchDaemon using WatchPaths that is triggered when the user
    # clicks the "Install now" at a generated prompt. A randomized key is inserted simultaneously in both the
    # WatchPaths file and a seperate preference file, and when confirmed for a match here, it is allowed to run.
    # This elimantes any accidental runs if the WatchPaths file gets modified for any reason.

    writelog " "
    writelog "======== Starting $scriptName ========"
    writelog "Verifying On-Demand Update Key..."
    storedUpdateKeys=$(/usr/libexec/PlistBuddy -c "Print update_key" $preferenceFileFullPath | sed -e 1d -e '$d' | sed 's/^ *//')
    testUpdateKey=$(defaults read $watchPathsPlist update_key)
if [[ -n "$testUpdateKey" ]] && [[ "$storedUpdateKeys" == *"$testUpdateKey"* ]]; then
    writelog "On-Demand Update Key confirmed; continuing."
        "$JAMFHELPER" -windowType utility -lockHUD -title "$updateInProgressTitle" -alignHeading center -alignDescription natural -description "$updateInProgressMessage" -icon "$icon" -iconSize 100 &
        jamfHelperPID=$(echo $!)
        writelog "Installing updates that DO require a restart..."
        trigger_updates "--recommended --restart"
        record_last_full_update
        initiate_restart
    else
        writelog "On-Demand Update Key not confirmed; exiting."
        finish 0
    fi
}

main() {
    # This function is intended to be run from a LaunchDaemon at intervals

    writelog " "
    writelog "======== Starting $scriptName ========"

    # See if we are blocking updates, if so exit
    updatesBlocked=$(/usr/libexec/PlistBuddy -c "Print :updates_blocked" $preferenceFileFullPath 2> /dev/null | xargs 2> /dev/null)
    if [[ "$updatesBlocked" == "true" ]]; then
        writelog "Updates are blocked for this client at this time; exiting."
        finish 0
    fi

    # Check the last time we had a full successful update
    updatesAvailable=$(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist LastRecommendedUpdatesAvailable | /usr/bin/awk '{ if  (NF > 2) {print $1 " "  $2} else { print $0 }}')
    if [[ "$updatesAvailable" -gt "0" ]]; then
        writelog "At least one recommended update was marked available from a previous check."
        random_delay
        update_check
    else
        lastFullUpdateTime=$(/usr/libexec/PlistBuddy -c "Print :last_full_update_time" $preferenceFileFullPath 2> /dev/null | xargs 2> /dev/null)
        lastEmptyUpdateTime=$(/usr/libexec/PlistBuddy -c "Print :last_empty_update_time" $preferenceFileFullPath 2> /dev/null | xargs 2> /dev/null)
        if [[ -n "$lastFullUpdateTime" ]]; then
            daysSinceLastFullUpdate="$(compare_date "$lastFullUpdateTime")"
            if [[ "$daysSinceLastFullUpdate" -ge "$afterFullUpdateDelayDayCount" ]]; then
                writelog "$afterFullUpdateDelayDayCount or more days have passed since last full update."
                # delay script's actions by up to 5 mins to prevent all computers running software update at the same time
                random_delay
                update_check
            else
                writelog "Less than $afterFullUpdateDelayDayCount days since last full update; exiting."
                finish 0
            fi
        elif [[ -n "$lastEmptyUpdateTime" ]]; then
            daysSinceLastEmptyUpdate="$(compare_date "$lastEmptyUpdateTime")"
            if [[ "$daysSinceLastEmptyUpdate" -ge "$afterEmptyUpdateDelayDayCount" ]]; then
                writelog "$afterEmptyUpdateDelayDayCount or more days have passed since last empty update check."
                # delay script's actions by up to 5 mins to prevent all computers running software update at the same time
                random_delay
                update_check
            else
                writelog "Less than $afterEmptyUpdateDelayDayCount days since last empty update check; exiting."
                finish 0
            fi
        else
            writelog "This device might not have performed a full update yet."
            # delay script's actions by up to 5 mins to prevent all computers running software update at the same time
            random_delay
            update_check
        fi
    fi

    finish 0
}

"$@"
