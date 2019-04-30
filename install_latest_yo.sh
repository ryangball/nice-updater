#!/bin/bash

latestYoReleaseURL=$(curl -s https://api.github.com/repos/sheagcraig/yo/releases/latest |  python -c 'import json,sys;obj=json.load(sys.stdin);print obj["assets"][0]["browser_download_url"];');

curl -L $latestYoReleaseURL > /tmp/yo.pkg

installer -pkg /tmp/yo.pkg -target /
