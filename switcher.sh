#!/usr/bin/bash

if [${1} = 'old']
then
    rm -f extensions/OldStatus/disabled
    touch extensions/AttachmentStatus/disabled
elif [${1} = 'new']
then
    touch extensions/OldStatus/disabled
    rm -f extensions/AttachmentStatus/disabled
else
    echo 'Wrong parameter, expected either "new" or "old"'
    exit 1
fi
