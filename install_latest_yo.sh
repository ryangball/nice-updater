#!/bin/bash

# Contributed by Kurt Roberts https://github.com/kurtroberts
# Obtained from https://github.com/ryangball/nice-updater

# Use this script to avoid having to package Yo in your Jamf Pro
# To configure, create a policy available on an ongoing basis,
# triggered by a custom event called "yo" that runs this script as a payload.

# Get the url of the latest Yo release
latestYoReleaseURL=$(curl -s https://api.github.com/repos/sheagcraig/yo/releases/latest | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["assets"][0]["browser_download_url"];');

# Copy that release to /tmp/yo.pkg
curl -L "$latestYoReleaseURL" > /tmp/yo.pkg

# Install 'Yo' in /Applications/Utilities (default location)
installer -pkg /tmp/yo.pkg -target /

# Clean up
rm -f /tmp/yo.pkg

# Verify installation
if [[ -e /Applications/Utilities/yo.app ]]; then
    echo "Yo installation succeeded; exiting."
    exit 0
else
    echo "Yo installation failed; exiting."
    exit 1
fi
