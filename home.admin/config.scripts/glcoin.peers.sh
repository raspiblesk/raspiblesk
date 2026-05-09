#!/bin/bash

# glcoin.peers.sh — manage addnode peers in glcoin.conf
# glcoin.peers.sh status
# glcoin.peers.sh set-authority <ip>
# glcoin.peers.sh menu

GLCOIN_CONF="/mnt/hdd/app-data/glcoin/glcoin.conf"
GLCOIN_PORT=1618

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "glcoin.peers.sh [status|set-authority <ip>|menu]"
  echo
  exit 1
fi

if [ "$1" = "status" ]; then
  echo "# Glcoin Peer Status"
  current=$(grep "^main.addnode=" "${GLCOIN_CONF}" 2>/dev/null | cut -d= -f2 | head -1)
  echo "authorityNode='${current}'"
  echo "dnsseed=$(grep -c '^dnsseed=0' "${GLCOIN_CONF}" 2>/dev/null)"
  exit 0
fi

if [ "$1" = "set-authority" ]; then
  newIP="$2"
  if [ -z "${newIP}" ]; then
    echo "error='missing ip'"
    exit 1
  fi
  # validate: must look like an IP or hostname
  if ! echo "${newIP}" | grep -qE '^[0-9a-zA-Z._-]+$'; then
    echo "error='invalid ip or hostname'"
    exit 1
  fi
  if [ ! -f "${GLCOIN_CONF}" ]; then
    echo "error='glcoin.conf not found'"
    exit 1
  fi
  # remove old main.addnode entries
  sudo sed -i '/^main\.addnode=/d' "${GLCOIN_CONF}"
  # ensure dnsseed=0 is present
  if ! grep -q '^dnsseed=0' "${GLCOIN_CONF}"; then
    echo "dnsseed=0" | sudo tee -a "${GLCOIN_CONF}" > /dev/null
  fi
  # add new authority addnode
  echo "main.addnode=${newIP}:${GLCOIN_PORT}" | sudo tee -a "${GLCOIN_CONF}" > /dev/null
  echo "# Authority node set to ${newIP}:${GLCOIN_PORT}"
  # restart glcoind
  echo "# Restarting glcoind ..."
  sudo systemctl restart glcoind
  echo "# Done"
  exit 0
fi

if [ "$1" = "menu" ]; then
  source /home/admin/raspiblesk.info
  source /mnt/hdd/app-data/raspiblesk.conf

  current=$(grep "^main.addnode=" "${GLCOIN_CONF}" 2>/dev/null | cut -d= -f2 | head -1)
  currentDisplay="${current:-not set}"

  newIP=$(whiptail --title " Glcoin Authority Node " --inputbox \
"Enter the IP address of the authority node (the machine running glcoind with mining rights).

Current peer: ${currentDisplay}

Example: 192.168.1.100
Leave empty to cancel." \
12 60 "${current%%:*}" 2>&1 >/dev/tty)

  if [ $? -ne 0 ] || [ -z "${newIP}" ]; then
    exit 0
  fi

  /home/admin/config.scripts/glcoin.peers.sh set-authority "${newIP}"
  whiptail --title " Done " --msgbox \
"Authority node set to ${newIP}:${GLCOIN_PORT}.
glcoind is restarting — blocks should sync within a few minutes." \
8 60
  exit 0
fi

echo "# FAIL - Unknown parameter: $1"
exit 1
