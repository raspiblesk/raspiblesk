#!/bin/bash
# script for custom tmux status bar

if [ -f "/mnt/hdd/app-data/raspiblesk.conf" ]; then
    source /mnt/hdd/app-data/raspiblesk.conf 2>/dev/null
    echo " ${chain}net "
else
    #echo "$configFile does not exist"
    echo " unknown "
fi
