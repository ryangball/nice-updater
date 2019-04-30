#!/bin/bash

# Use this script to avoid having to package yo in your Jamf Pro
# To configure, create a policy available on an ongoing basis,
# triggered by a custom event called "yo" that runs this script as a payload.

#get the url of the latest yo release
latestYoReleaseURL=$(curl -s https://api.github.com/repos/sheagcraig/yo/releases/latest |  python -c 'import json,sys;obj=json.load(sys.stdin);print obj["assets"][0]["browser_download_url"];');

#copy that release to /tmp/yo.pkg
curl -L $latestYoReleaseURL > /tmp/yo.pkg

#install yo in /Applications/Utilities (default location)
installer -pkg /tmp/yo.pkg -target /

#clean up
rm -f /tmp/yo.pkg
