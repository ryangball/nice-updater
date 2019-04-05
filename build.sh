#!/bin/bash

identifier="com.github.ryangball.nice_updater"
version="1.0"

if [[ -n "$1" ]]; then
    version="$1"
    echo "Version set to $version"
else
    echo "No version passed, using version $version"
fi

# Create clean temp build directories
find /private/tmp/nice_updater -mindepth 1 -delete
mkdir -p /private/tmp/nice_updater/files/Library/LaunchDaemons
mkdir -p /private/tmp/nice_updater/files/Library/Scripts/
mkdir -p /private/tmp/nice_updater/scripts
mkdir -p "$PWD/build"

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