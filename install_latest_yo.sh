#!/bin/bash

# Use this script to avoid having to package yo in your Jamf Pro
# To configure, create a policy available on an ongoing basis,
# triggered by a custom event called "yo" that runs this script as a payload.

# Get the url of the latest yo release
latestYoReleaseURL=$(curl -s https://api.github.com/repos/sheagcraig/yo/releases/latest | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["assets"][0]["browser_download_url"];');

# Copy that release to /tmp/yo.pkg
curl -L "$latestYoReleaseURL" > /tmp/yo.pkg

# Install yo in /Applications/Utilities (default location)
installer -pkg /tmp/yo.pkg -target /

# Clean up
rm -f /tmp/yo.pkg

# Verify installation
if [[ -e /Applications/Utilities/yo.app ]]; then
    echo "yo.app installation succedded; exiting."
    exit 0
else
    echo "yo.app installation failed; exiting."
    exit 1
fi