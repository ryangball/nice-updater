#!/bin/bash

# The main identifier which everything hinges on
identifier="com.github.grahampugh.nice_updater"

# The location of your log, keep in mind that if you nest the log into a folder that does not exist you'll need to mkdir -p the directory as well
log="/Library/Logs/Nice_Updater.log"

###### Variables below this point are not intended to be modified #####
mainDaemonPlist="/Library/LaunchDaemons/${identifier}.plist"
mainOnDemandDaemonPlist="/Library/LaunchDaemons/${identifier}_on_demand.plist"
watchPathsPlist="/Library/Preferences/${identifier}.trigger.plist"
preferenceFileFullPath="/Library/Preferences/${identifier}.prefs.plist"
iconPath="/Library/Scripts/nice_updater_custom_icon.png"
scriptPath="/Library/Scripts/nice_updater.sh"
uninstallScriptPath="/Library/Scripts/nice_updater_uninstall.sh"
uninstallScriptName=$(basename "$uninstallScriptPath")

writelog() {
    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    /bin/echo "${1}"
    /bin/echo "$DATE" " $1" >> "$log"
}

finish() {
    writelog "======== Finished $uninstallScriptName ========"
    exit "$1"
}

writelog " "
writelog "======== Starting $uninstallScriptName ========"

writelog "Stopping NiceUpdater On-Demand LaunchDaemon..."
launchctl unload -w "$mainOnDemandDaemonPlist"

writelog "Stopping NiceUpdater LaunchDaemon..."
launchctl unload -w "$mainDaemonPlist"

writelog "Deleting NiceUpdater LaunchDaemons..."

# Delete the main Daemon plist
[[ -e "$mainOnDemandDaemonPlist" ]] && rm -f "$mainOnDemandDaemonPlist"
# Delete the on_demand Daemon plist
[[ -e "$mainDaemonPlist" ]] && rm -f "$mainDaemonPlist"

writelog "Deleting NiceUpdater Preferences..."

# Delete the main preferences file
[[ -e "$preferenceFileFullPath" ]] && rm -f "$preferenceFileName"
# Delete the watch path preferences file
[[ -e "$watchPathsPlist" ]] && rm -f "$watchPathsPlist"

writelog "Deleting NiceUpdater files..."

# Delete the main preferences file
[[ -e "$iconPath" ]] && rm -f "$iconPath"
# Delete the main preferences file
[[ -e "$scriptPath" ]] && rm -f "$scriptPath"
[[ -e "$uninstallScriptPath" ]] && rm -f "$uninstallScriptPath"

finish 0
