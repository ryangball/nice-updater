#!/bin/bash

identifier="com.github.ryangball.nice_updater"
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

if [[ $identifier -ne "com.github.ryangball.nice_updater" ]]; then
    echo "Renaming files due to changed identifier..."
    $(find $PWD -name *nice_updater.plist)
    mv $(find $PWD -name *nice_updater.plist) "$PWD/${identifier}.plist"
    mv "$PWD/com.github.ryangball.nice_updater_on_demand.plist" "$PWD/${identifier}_on_demand.plist"
    mv "$PWD/com.github.ryangball.nice_updater.prefs.plist" "$PWD/${identifier}.prefs.plist"

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
/usr/bin/plutil -replace WatchPaths -json "[ \"$watchPathsPlist\" ]" "$PWD/$onDemainDaemonFileName"
/usr/bin/plutil -replace Label -string $onDemandDaemonIdentifier "$PWD/$onDemainDaemonFileName"
/usr/bin/plutil -replace Label -string $identifier "$PWD/$mainDaemonFileName"

# Create clean temp build directories
find /private/tmp/nice_updater -mindepth 1 -delete
mkdir -p /private/tmp/nice_updater/files/Library/LaunchDaemons
mkdir -p /private/tmp/nice_updater/files/Library/Preferences
mkdir -p /private/tmp/nice_updater/files/Library/Scripts/
mkdir -p /private/tmp/nice_updater/scripts
mkdir -p "$PWD/build"

# Create/modify the main preference file
if [[ -e "$PWD/$preferenceFileName" ]]; then
    /usr/libexec/PlistBuddy -c Clear "$PWD/$preferenceFileName"
fi

# Populate our variables into the plist
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

# Create the binary
# /usr/local/bin/shc -r -f "$PWD/nice_updater.sh" -o "$PWD/build/nice_updater"
cp "$PWD/nice_updater.sh" /private/tmp/nice_updater/files/Library/Scripts/nice_updater.sh

# Copy the LaunchDaemon plists to the temp build directory
cp "$PWD/com.github.ryangball.nice_updater.plist" "/private/tmp/nice_updater/files/Library/LaunchDaemons/"
cp "$PWD/com.github.ryangball.nice_updater_on_demand.plist" "/private/tmp/nice_updater/files/Library/LaunchDaemons/"
cp "$PWD/$preferenceFileName" "/private/tmp/nice_updater/files/Library/Preferences/"

# Remove any unwanted .DS_Store files from the temp build directory
find "/private/tmp/nice_updater/" -name '*.DS_Store' -type f -delete

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