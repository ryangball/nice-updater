#!/bin/bash
# shellcheck disable=SC2116,SC2002

# Written by Ryan Ball
# Obtained from https://github.com/ryangball/nice-updater

# These variables will be automagically updated if you run build.sh, no need to modify them
mainOnDemandDaemonPlist="/Library/LaunchDaemons/com.github.ryangball.nice_updater_on_demand.plist"
watchPathsPlist="/Library/Preferences/com.github.ryangball.nice_updater.trigger.plist"
preferenceFileFullPath="/Library/Preferences/com.github.ryangball.nice_updater.prefs.plist"

###### Variables below this point are not intended to be modified #####
updateInProgressTitle=$(/usr/bin/defaults read "$preferenceFileFullPath" UpdateInProgressTitle)
updateInProgressMessage=$(/usr/bin/defaults read "$preferenceFileFullPath" UpdateInProgressMessage)
# loginAfterUpdatesInProgressMessage=$(/usr/bin/defaults read "$preferenceFileFullPath" LoginAfterUpdatesInProgressMessage)
log=$(/usr/bin/defaults read "$preferenceFileFullPath" Log)
afterFullUpdateDelayDayCount=$(/usr/bin/defaults read "$preferenceFileFullPath" AfterFullUpdateDelayDayCount)
afterEmptyUpdateDelayDayCount=$(/usr/bin/defaults read "$preferenceFileFullPath" AfterEmptyUpdateDelayDayCount)
maxNotificationCount=$(/usr/bin/defaults read "$preferenceFileFullPath" MaxNotificationCount)
yoPath=$(/usr/bin/defaults read "$preferenceFileFullPath" YoPath)

###### Variables below this point are not intended to be modified #####
scriptName=$(/usr/bin/basename "$0")
osVersion=$(/usr/bin/sw_vers -productVersion)
osMinorVersion=$(/usr/bin/awk -F. '{print $2}' <<< "$osVersion")
osPatchVersion=$(/usr/bin/awk -F. '{print $3}' <<< "$osVersion")
restartEnabled="false"
automatedRestartEnabled="false"

# Determine icns path for softwareupdate
[[ "$osMinorVersion" -le 12 ]] && icon="/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"
[[ "$osMinorVersion" -ge 13 ]] && icon="/System/Library/CoreServices/Install Command Line Developer Tools.app/Contents/Resources/SoftwareUpdate.icns"

# Determine if this version of macOS is compatable with the --restart argument for softwareupdate
[[ "$osMinorVersion" -eq 13 ]] && [[ "$osPatchVersion" -ge 4 ]] && automatedRestartEnabled="true"
[[ "$osMinorVersion" -ge 14 ]] && automatedRestartEnabled="true"

function writelog () {
    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    /bin/echo "${1}"
    /bin/echo "$DATE" " $1" >> "$log"
}

function finish () {
    # Record our last full update if we installed all updates
    if [[ "$recordFullUpdate" == "true" ]]; then
        writelog "Done with update process; recording last full update time."
        # /usr/libexec/PlistBuddy -c "Delete :last_full_update_time" $preferenceFileFullPath 2> /dev/null
        # /usr/libexec/PlistBuddy -c "Add :last_full_update_time string $(date +%Y-%m-%d\ %H:%M:%S)" $preferenceFileFullPath
        /usr/bin/defaults delete "$preferenceFileFullPath" last_full_update_time
        /usr/bin/defaults write "$preferenceFileFullPath" last_full_update_time -string "$(date +%Y-%m-%d\ %H:%M:%S)"

        writelog "Clearing user alert data."
        # /usr/libexec/PlistBuddy -c "Delete :users" $preferenceFileFullPath
        /usr/bin/defaults delete "$preferenceFileFullPath" users

        writelog "Clearing On-Demand Update Key."
        # /usr/libexec/PlistBuddy -c "Delete :update_key" $preferenceFileFullPath 2> /dev/null
        # /usr/libexec/PlistBuddy -c "Add :update_key array" $preferenceFileFullPath 2> /dev/null
        /usr/bin/defaults delete "$preferenceFileFullPath" update_key
        /usr/bin/defaults write "$preferenceFileFullPath" update_key -array
    fi

    kill "$jamfHelperPID" > /dev/null 2>&1 && wait $! > /dev/null
    writelog "======== Finished $scriptName ========"

    # If the updates installed require a restart, but the OS is 10.13.3 or lower, we need to manually restart the Mac
    if [[ "$restartEnabled" == "true" ]] && [[ "$automatedRestartEnabled" == "false" ]]; then
        writelog "Automated restart through softwareupdate only available in macOS 10.13.4 and above."
        writelog "Initiating manual restart."
        if [[ -f /usr/local/bin/jamf ]]; then
            /usr/local/bin/jamf reboot -background -immediately | while read -r LINE; do writelog "$LINE"; done;
        else
            /sbin/shutdown -r now | while read -r LINE; do writelog "$LINE"; done;
        fi
    fi
}

# Make sure we run the finish function at the exit signal
trap 'finish' EXIT

function install_restart_updates () {
    local restartArgument
    writelog "Installing $updatesRestartCount update(s) that WILL REQUIRE a restart or shut down..."
    recordFullUpdate="true"
    restartEnabled="true"

    # If the OS is 10.13.4 or higher, configure softwareupdate with the --restart argument to automate the restart or shut down of the Mac
    [[ "$automatedRestartEnabled" == "true" ]] && restartArgument='--restart'

    /usr/sbin/softwareupdate --install --all --no-scan "$restartArgument" | /usr/bin/awk '!/Software Update Tool|Copyright|Finding|Done\.|^$/' | while read -r LINE; do writelog "$LINE"; done;
    exit 0
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
    [[ "$notificationsLeft" == "1" ]] && subtitle="1 remaining alert before auto-install."
    [[ "$notificationsLeft" == "0" ]] && subtitle="Install now to avoid interruptions."

    writelog "Stopping NiceUpdater On-Demand LaunchDaemon..."
    /bin/launchctl unload -w "$mainOnDemandDaemonPlist"

    writelog "Generating NiceUpdater Update Key..."
    updateKey=$(cat /dev/urandom | env LC_CTYPE=C tr -dc a-zA-Z0-9 | head -c 16; echo)
    # /usr/libexec/PlistBuddy -c "Add :update_key array" $preferenceFileFullPath 2> /dev/null
    /usr/bin/defaults write "$preferenceFileFullPath" update_key -array 2> /dev/null
    /usr/bin/plutil -insert update_key.0 -string "$updateKey" "$preferenceFileFullPath"

    # /usr/libexec/PlistBuddy -c "Delete :update_key" $watchPathsPlist 2> /dev/null
    /usr/bin/defaults delete "$watchPathsPlist" update_key 2> /dev/null

    writelog "Restarting NiceUpdater On-Demand LaunchDaemon..."
    /bin/launchctl load -w "$mainOnDemandDaemonPlist"

    writelog "Notifying $loggedInUser of available updates..."
    /bin/launchctl asuser "$loggedInUID" "$yoPath" -t "Software Updates Required" -s "$subtitle" -n "Mac will restart after installation." \
        -o "Cancel" -b "Install Now" -B "/usr/bin/defaults write $watchPathsPlist update_key -string $updateKey" --ignores-do-not-disturb
    /usr/libexec/PlistBuddy -c "Add :users dict" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Delete :users:$loggedInUser" $preferenceFileFullPath 2> /dev/null
    /usr/libexec/PlistBuddy -c "Add :users:$loggedInUser dict" $preferenceFileFullPath
    /usr/libexec/PlistBuddy -c "Add :users:$loggedInUser:alert_count integer $2" $preferenceFileFullPath
}

function alert_logic () {
    notificationCount=$(/usr/libexec/PlistBuddy -c "Print :users:$loggedInUser:alert_count" $preferenceFileFullPath 2> /dev/null | /usr/bin/xargs)
    if [[ "$notificationCount" -ge "$maxNotificationCount" ]]; then
        writelog "$loggedInUser has been notified $notificationCount times; not waiting any longer."
        /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -lockHUD -title "$updateInProgressTitle" -alignHeading center -alignDescription natural -description "$updateInProgressMessage" -icon "$icon" -iconSize 100 &
        jamfHelperPID=$(echo $!)
        install_restart_updates
    else
        ((notificationCount++))
        notificationsLeft="$((maxNotificationCount - notificationCount))"
        alert_user "$notificationsLeft remaining alerts before auto-install." "$notificationCount"
    fi
}

function update_check () {
    writelog "Determining available Software Updates for macOS $osVersion..."
    updates=$(/usr/sbin/softwareupdate -l)

    if [[ "$osMinorVersion" -le 14 ]]; then
        updatesNoRestart=$(echo "$updates" | /usr/bin/grep -Ei "restart|shut down" -B1 | /usr/bin/diff --normal - <(echo "$updates") | /usr/bin/sed -n -e 's/^.*[\*|-] //p')
        updatesRestart=$(echo "$updates" | /usr/bin/grep -Ei "restart|shut down" -B1 | /usr/bin/grep -vEi 'restart|shut down' | /usr/bin/sed -n -e 's/^.*\* //p')
    elif [[ "$osMinorVersion" -ge 15 ]]; then
        updatesNoRestart=$(echo "$updates" | /usr/bin/grep -Ei -B1 "restart|shut down" | /usr/bin/diff - <(echo "$updates") | /usr/bin/sed -n 's/.*Label://p')
        updatesRestart=$(echo "$updates" | /usr/bin/grep -Ei "restart|shut down" | /usr/bin/sed -e 's/.*Title: \(.*\), Ver.*/\1/')
    fi

    updatesNoRestartCount=$(echo -n "$updatesNoRestart" | /usr/bin/grep -c '^')
    updatesRestartCount=$(echo -n "$updatesRestart" | /usr/bin/grep -c '^')
    totalUpdateCount=$((updatesNoRestartCount + updatesRestartCount))

    if [[ "$totalUpdateCount" -gt "0" ]]; then
        # Download the updates
        writelog "Downloading $totalUpdateCount update(s)..."
        /usr/sbin/softwareupdate --download --all --no-scan | /usr/bin/awk '/Downloaded/{ print $0 }' | while read -r LINE; do writelog "$LINE"; done;

        # Don't waste the user's time - install any updates that do not require a restart first.
        if [[ -n "$updatesNoRestart" ]]; then
            writelog "Installing $updatesNoRestartCount update(s) that WILL NOT require a restart in the background..."

            # Loop through and install all of the updates that do not require a restart
            while read -r LINE ; do
                /usr/sbin/softwareupdate --install "$LINE" --no-scan | /usr/bin/awk '/Installing|Installed/{ print $0 }' | while read -r LINE; do writelog "$LINE"; done;
            done < <(echo "$updatesNoRestart")
        fi

        # If the script moves past this point, a restart is required.
        if [[ -n "$updatesRestart" ]]; then
            writelog "A restart is required for remaining updates."

            # If no user is logged in, just update and restart. Check the user now as some time has past since the script began.
            loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }')
            loggedInUID=$(id -u "$loggedInUser")
            if [[ "$loggedInUser" == "root" ]] || [[ -z "$loggedInUser" ]]; then
                writelog "No user logged in."
                install_restart_updates
            fi
            # Getting here means a user is logged in, alert them that they will need to install and restart
            alert_logic
        else
            recordFullUpdate="true"
            writelog "No updates that require a restart available; exiting."
            exit 0
        fi
    else
        writelog "No updates at this time; exiting."
        # /usr/libexec/PlistBuddy -c "Delete :last_empty_update_time" $preferenceFileFullPath 2> /dev/null
        # /usr/libexec/PlistBuddy -c "Add :last_empty_update_time string $(date +%Y-%m-%d\ %H:%M:%S)" $preferenceFileFullPath
        /usr/bin/defaults delete "$preferenceFileFullPath" last_empty_update_time 2> /dev/null
        /usr/bin/defaults write "$preferenceFileFullPath" last_empty_update_time -string "$(date +%Y-%m-%d\ %H:%M:%S)"
        exit 0
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
    storedUpdateKeys=$(/usr/libexec/PlistBuddy -c "Print update_key" $preferenceFileFullPath | /usr/bin/sed -e 1d -e '$d' | /usr/bin/sed 's/^ *//')
    testUpdateKey=$(/usr/bin/defaults read $watchPathsPlist update_key)
    if [[ -n "$testUpdateKey" ]] && [[ "$storedUpdateKeys" == *"$testUpdateKey"* ]]; then
        writelog "On-Demand Update Key confirmed; continuing."
        /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -lockHUD -title "$updateInProgressTitle" -alignHeading center -alignDescription natural -description "$updateInProgressMessage" -icon "$icon" -iconSize 100 &
        jamfHelperPID=$(echo $!)
        install_restart_updates
    else
        writelog "On-Demand Update Key not confirmed; exiting."
        exit 0
    fi
}

function main () {
    # This function is intended to be run from a LaunchDaemon at intervals

    writelog " "
    writelog "======== Starting $scriptName ========"

    # See if we are blocking updates, if so exit
    updatesBlocked=$(/usr/libexec/PlistBuddy -c "Print :UpdatesBlocked" $preferenceFileFullPath 2> /dev/null | /usr/bin/xargs 2> /dev/null)
    if [[ "$updatesBlocked" == "true" ]]; then
        writelog "Updates are blocked for this client at this time; exiting."
        exit 0
    fi

    # Check the last time we had a full successful update
    updatesAvailable=$(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist LastRecommendedUpdatesAvailable | /usr/bin/awk '{ if  (NF > 2) {print $1 " "  $2} else { print $0 }}')
    if [[ "$updatesAvailable" -gt "0" ]]; then
        writelog "At least one recommended update was marked available from a previous check."
        update_check
    else
        # lastFullUpdateTime=$(/usr/libexec/PlistBuddy -c "Print :last_full_update_time" $preferenceFileFullPath 2> /dev/null | /usr/bin/xargs 2> /dev/null)
        # lastEmptyUpdateTime=$(/usr/libexec/PlistBuddy -c "Print :last_empty_update_time" $preferenceFileFullPath 2> /dev/null | /usr/bin/xargs 2> /dev/null)
        lastFullUpdateTime=$(/usr/bin/defaults read "$preferenceFileFullPath" "last_full_update_time" 2> /dev/null | /usr/bin/xargs)
        lastEmptyUpdateTime=$(/usr/bin/defaults read "$preferenceFileFullPath" "last_empty_update_time" 2> /dev/null | /usr/bin/xargs)
        if [[ -n "$lastFullUpdateTime" ]]; then
            daysSinceLastFullUpdate="$(compare_date "$lastFullUpdateTime")"
            if [[ "$daysSinceLastFullUpdate" -ge "$afterFullUpdateDelayDayCount" ]]; then
                writelog "$afterFullUpdateDelayDayCount or more days have passed since last full update."
                update_check
            else
                writelog "Less than $afterFullUpdateDelayDayCount days since last full update; exiting."
                exit 0
            fi
        elif [[ -n "$lastEmptyUpdateTime" ]]; then
            daysSinceLastEmptyUpdate="$(compare_date "$lastEmptyUpdateTime")"
            if [[ "$daysSinceLastEmptyUpdate" -ge "$afterEmptyUpdateDelayDayCount" ]]; then
                writelog "$afterEmptyUpdateDelayDayCount or more days have passed since last empty update check."
                update_check
            else
                writelog "Less than $afterEmptyUpdateDelayDayCount days since last empty update check; exiting."
                exit 0
            fi
        else
            writelog "This device might not have performed a full update yet."
            update_check
        fi
    fi

    exit 0
}

"$@"
