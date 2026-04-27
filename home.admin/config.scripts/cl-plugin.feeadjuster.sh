#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install the feeadjuster plugin for Core Lightning"
  echo "Usage:"
  echo "cl-plugin.feeadjuster.sh [on|off] <testnet|mainnet|signet>"
  echo
  exit 1
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)
plugin="feeadjuster"

if [ "$1" = "on" ];then

  if [ ! -f "/home/glcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py" ]; then
    cd /home/glcoin/cl-plugins-available || exit 1
    sudo -u glcoin git clone https://github.com/lightningd/plugins.git
    sudo -u glcoin pip config set global.break-system-packages true
    sudo -u glcoin pip install -r /home/glcoin/cl-plugins-available/plugins/${plugin}/requirements.txt
  fi
  if [ ! -L /home/glcoin/${netprefix}cl-plugins-enabled/${plugin}.py ];then
    sudo ln -s /home/glcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py \
               /home/glcoin/${netprefix}cl-plugins-enabled
    sudo chmod +x /home/glcoin/cl-plugins-available/plugins/${plugin}/${plugin}.py
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blesk.conf.sh set ${netprefix}feeadjuster "on"

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ] && [ "$3" != "norestart" ]; then
    echo "# Start ${netprefix}${plugin}"
    $lightningcli_alias plugin start /home/glcoin/cl-plugins-enabled/${plugin}.py
  fi

fi

if [ "$1" = "off" ];then

  echo "Stop the ${plugin}"
  $lightningcli_alias plugin stop home/glcoin/${netprefix}cl-plugins-enabled/${plugin}.py

  echo "# delete symlink"
  sudo rm -rf /home/glcoin/${netprefix}cl-plugins-enabled/${plugin}.py
  
  echo "# Edit ${CLCONF}"
  sudo sed -i "/^feeadjuster/d" ${CLCONF}

  # setting value in raspi blitz config
  /home/admin/config.scripts/blesk.conf.sh set ${netprefix}feeadjuster "off"

  echo "# The ${plugin} was uninstalled"
fi