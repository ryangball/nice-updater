#!/bin/bash

identifier="com.ryangball.nice_updater"
version="1.0"

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

# The start interval of the main plist, essentially the time in seconds between alerts, 7200 is two hours
startInterval="7200"

# The full path of the yo.app binary
yoPath="/Applications/Utilities/yo.app/Contents/MacOS/yo"

###### Variables below this point are not intended to be modified #####
mainDaemonPlist="/Library/LaunchDaemons/${identifier}.plist"
mainDaemonFileName="${mainDaemonPlist##*/}"
mainOnDemandDaemonPlist="/Library/LaunchDaemons/${identifier}_on_demand.plist"
onDemainDaemonFileName="${mainOnDemandDaemonPlist##*/}"
onDemandDaemonIdentifier="${identifier}_on_demand"
watchPathsPlist="/Library/Preferences/${identifier}.trigger.plist"
preferenceFileFullPath="/Library/Preferences/${identifier}.prefs.plist"
preferenceFileName="${preferenceFileFullPath##*/}"
# watchPathsPlistFileName="${watchPathsPlist##*/}"

if [[ -n "$1" ]]; then
    version="$1"
    echo "Version set to $version"
else
    echo "No version passed, using version $version"
fi

# Update the variables in the various files of the project
# If you know of a more elegant/efficient way to do this please create a PR
sed -i .bak "s#mainDaemonPlist=.*#mainDaemonPlist=\"$mainDaemonPlist\"#" "$PWD/postinstall.sh"
sed -i .bak "s#mainDaemonPlist=.*#mainDaemonPlist=\"$mainDaemonPlist\"#" "$PWD/preinstall.sh"
sed -i .bak "s#mainOnDemandDaemonPlist=.*#mainOnDemandDaemonPlist=\"$mainOnDemandDaemonPlist\"#" "$PWD/postinstall.sh"
sed -i .bak "s#mainOnDemandDaemonPlist=.*#mainOnDemandDaemonPlist=\"$mainOnDemandDaemonPlist\"#" "$PWD/preinstall.sh"
sed -i .bak "s#mainOnDemandDaemonPlist=.*#mainOnDemandDaemonPlist=\"$mainOnDemandDaemonPlist\"#" "$PWD/nice_updater.sh"
sed -i .bak "s#watchPathsPlist=.*#watchPathsPlist=\"$watchPathsPlist\"#" "$PWD/preinstall.sh"
sed -i .bak "s#watchPathsPlist=.*#watchPathsPlist=\"$watchPathsPlist\"#" "$PWD/nice_updater.sh"
sed -i .bak "s#preferenceFileFullPath=.*#preferenceFileFullPath=\"$preferenceFileFullPath\"#" "$PWD/postinstall.sh"
sed -i .bak "s#preferenceFileFullPath=.*#preferenceFileFullPath=\"$preferenceFileFullPath\"#" "$PWD/nice_updater.sh"
sed -i .bak "s#yoPath=.*#yoPath=\"$yoPath\"#" "$PWD/preinstall.sh"

# Create clean temp build directories
find /private/tmp/nice_updater -mindepth 1 -delete
mkdir -p /private/tmp/nice_updater/files/Library/LaunchDaemons
mkdir -p /private/tmp/nice_updater/files/Library/Preferences
mkdir -p /private/tmp/nice_updater/files/Library/Scripts/
mkdir -p /private/tmp/nice_updater/scripts
mkdir -p "$PWD/build"

# Create/modify the main Daemon plist
[[ -e "$PWD/$mainDaemonFileName" ]] && /usr/libexec/PlistBuddy -c Clear "$PWD/$mainDaemonFileName" &> /dev/null
defaults write "$PWD/$mainDaemonFileName" Label -string "$identifier"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$PWD/$mainDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.0 -string "/bin/bash" "$PWD/$mainDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.1 -string "/Library/Scripts/nice_updater.sh" "$PWD/$mainDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.2 -string "main" "$PWD/$mainDaemonFileName"
defaults write "$PWD/$mainDaemonFileName" StartInterval -int "$startInterval"

# Create/modify the on_demand Daemon plist
[[ -e "$PWD/$onDemainDaemonFileName" ]] && /usr/libexec/PlistBuddy -c Clear "$PWD/$onDemainDaemonFileName" &> /dev/null
defaults write "$PWD/$onDemainDaemonFileName" Label -string "$onDemandDaemonIdentifier"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$PWD/$onDemainDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.0 -string "/bin/bash" "$PWD/$onDemainDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.1 -string "/Library/Scripts/nice_updater.sh" "$PWD/$onDemainDaemonFileName"
/usr/bin/plutil -insert ProgramArguments.2 -string "on_demand" "$PWD/$onDemainDaemonFileName"
/usr/libexec/PlistBuddy -c "Add :WatchPaths array" "$PWD/$onDemainDaemonFileName"
/usr/bin/plutil -insert WatchPaths.0 -string "/Library/Preferences/${identifier}_trigger.plist" "$PWD/$onDemainDaemonFileName"

# Create/modify the main preference file
[[ -e "$PWD/$preferenceFileName" ]] && /usr/libexec/PlistBuddy -c Clear "$PWD/$preferenceFileName" &> /dev/null
defaults write "$PWD/$preferenceFileName" UpdateInProgressTitle -string "$updateInProgressTitle"
defaults write "$PWD/$preferenceFileName" UpdateInProgressMessage -string "$updateInProgressMessage"
defaults write "$PWD/$preferenceFileName" LoginAfterUpdatesInProgressMessage -string "$loginAfterUpdatesInProgressMessage"
defaults write "$PWD/$preferenceFileName" Log -string "$log"
defaults write "$PWD/$preferenceFileName" AfterFullUpdateDelayDayCount -int "$afterFullUpdateDelayDayCount"
defaults write "$PWD/$preferenceFileName" AfterEmptyUpdateDelayDayCount -int "$afterEmptyUpdateDelayDayCount"
defaults write "$PWD/$preferenceFileName" MaxNotificationCount -int "$maxNotificationCount"
defaults write "$PWD/$preferenceFileName" YoPath -string "$yoPath"

# Migrate preinstall and postinstall scripts to temp build directory
cp "$PWD/preinstall.sh" /private/tmp/nice_updater/scripts/preinstall
chmod +x /private/tmp/nice_updater/scripts/preinstall
cp "$PWD/postinstall.sh" /private/tmp/nice_updater/scripts/postinstall
chmod +x /private/tmp/nice_updater/scripts/postinstall

# Put the main script in place
cp "$PWD/nice_updater.sh" /private/tmp/nice_updater/files/Library/Scripts/nice_updater.sh

# Copy the LaunchDaemon plists to the temp build directory
cp "$PWD/$mainDaemonFileName" "/private/tmp/nice_updater/files/Library/LaunchDaemons/"
cp "$PWD/$onDemainDaemonFileName" "/private/tmp/nice_updater/files/Library/LaunchDaemons/"
cp "$PWD/$preferenceFileName" "/private/tmp/nice_updater/files/Library/Preferences/"

# Remove any unwanted .DS_Store files from the temp build directory
find "/private/tmp/nice_updater/" -name '*.DS_Store' -type f -delete

# Remove the default plists if the identifier has changed
if [[ ! "$identifier" = "com.github.ryangball.nice_updater" ]]; then
    rm "$PWD/com.github.ryangball.nice_updater.plist" &> /dev/null
    rm "$PWD/com.github.ryangball.nice_updater_on_demand.plist" &> /dev/null
    rm "$PWD/com.github.ryangball.nice_updater.prefs.plist" &> /dev/null
fi

# Remove any extended attributes (ACEs) from the temp build directory
/usr/bin/xattr -rc "/private/tmp/nice_updater"

echo "Building the .pkg in $PWD/build/"
/usr/bin/pkgbuild --quiet --root "/private/tmp/nice_updater/files/" \
    --install-location "/" \
    --scripts "/private/tmp/nice_updater/scripts/" \
    --identifier "$identifier" \
    --version "$version" \
    --ownership recommended \
    "$PWD/build/Nice_Updater_${version}.pkg"

# shellcheck disable=SC2181
if [[ "$?" == "0" ]]; then
    echo "Revealing Nice_Updater_${version}.pkg in Finder"
    open -R "$PWD/build/Nice_Updater_${version}.pkg"
else
    echo "Build failed."
fi
exit 0