#!/bin/bash

# Glcoin CPU Miner — glcoin_miner.py wrapper
# Installs and manages the Glcoin mining worker as a systemd service.
# Supports plain mining (mine-plain) and IPFS-anchored mining (mine-ipfs).

MINER_DIR="/opt/glcoin-miner"
SERVICE_FILE="/etc/systemd/system/glcoin-miner.service"
<<<<<<< HEAD
MINER_SCRIPT="/home/admin/config.scripts/glcoin_miner.py"
MINER_CONF="${MINER_DIR}/miner.conf"
=======
MINER_SCRIPT="${MINER_DIR}/glcoin_miner.py"
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Glcoin CPU Miner install script"
  echo "bonus.glcoin-miner.sh [on|off|status|menu]"
  echo "bonus.glcoin-miner.sh set-address <glcoin-address>"
  echo "bonus.glcoin-miner.sh set-mode [plain|ipfs]"
<<<<<<< HEAD
  echo "bonus.glcoin-miner.sh set-txid <anchor-txid>   (mine-ipfs mode)"
=======
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
  echo
  exit 1
fi

source /mnt/hdd/app-data/raspiblesk.conf 2>/dev/null

# STATUS
if [ "$1" = "status" ]; then
  echo "# Glcoin Miner Status"
  installed=0
  active=0
  address=""
  mode="plain"
<<<<<<< HEAD
  txid=""
=======
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)

  [ -f "${MINER_SCRIPT}" ] && installed=1
  if [ -f "${SERVICE_FILE}" ]; then
    active=$(systemctl is-active glcoin-miner 2>/dev/null | grep -c "^active")
  fi
<<<<<<< HEAD
  [ -f "${MINER_CONF}" ] && source "${MINER_CONF}" 2>/dev/null
=======
  [ -f "${MINER_DIR}/miner.conf" ] && source "${MINER_DIR}/miner.conf" 2>/dev/null
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)

  echo "installed=${installed}"
  echo "active=${active}"
  echo "address='${address}'"
  echo "mode='${mode}'"
<<<<<<< HEAD
  echo "txid='${txid}'"
=======
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
  exit 0
fi

# MENU
if [ "$1" = "menu" ]; then
  source <(sudo /home/admin/config.scripts/bonus.glcoin-miner.sh status)
  if [ "${installed}" = "0" ]; then
    whiptail --title " Glcoin Miner " --yesno "
Install the Glcoin CPU miner?

Mines blocks and sends rewards to your Glcoin address.
Requires glcoind to be running and synced.
" 12 52
    [ $? -eq 0 ] || exit 0
    sudo /home/admin/config.scripts/bonus.glcoin-miner.sh on
  else
    OPTIONS=()
    if [ "${active}" = "1" ]; then
      OPTIONS+=(STOP "Stop miner")
    else
      OPTIONS+=(START "Start miner")
    fi
    OPTIONS+=(ADDRESS "Set payout address (current: ${address})")
<<<<<<< HEAD
    OPTIONS+=(MODE "Set mining mode (current: ${mode})")
    if [ "${mode}" = "ipfs" ]; then
      OPTIONS+=(TXID "Set anchor txid (current: ${txid:0:16}...)")
    fi
    OPTIONS+=(UNINSTALL "Uninstall miner")
    CHOICE=$(whiptail --title " Glcoin Miner " --menu "" 14 62 6 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
=======
    OPTIONS+=(UNINSTALL "Uninstall miner")
    CHOICE=$(whiptail --title " Glcoin Miner " --menu "" 12 52 4 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
    case "${CHOICE}" in
      START)   sudo systemctl start glcoin-miner ;;
      STOP)    sudo systemctl stop glcoin-miner ;;
      ADDRESS)
<<<<<<< HEAD
        NEW_ADDR=$(whiptail --title " Payout Address " --inputbox \
          "Enter your Glcoin mining address (bech32 gc1...)" 8 60 "${address}" 3>&1 1>&2 2>&3)
        [ -n "${NEW_ADDR}" ] && sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-address "${NEW_ADDR}"
        ;;
      MODE)
        NEW_MODE=$(whiptail --title " Mining Mode " --menu "" 10 52 2 \
          plain "Standard block mining" \
          ipfs  "IPFS-anchored block mining" 3>&1 1>&2 2>&3)
        [ -n "${NEW_MODE}" ] && sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-mode "${NEW_MODE}"
        ;;
      TXID)
        NEW_TXID=$(whiptail --title " IPFS Anchor txid " --inputbox \
          "Enter the anchor transaction txid to commit in the coinbase." 8 72 "${txid}" 3>&1 1>&2 2>&3)
        [ -n "${NEW_TXID}" ] && sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-txid "${NEW_TXID}"
        ;;
=======
        NEW_ADDR=$(whiptail --title " Payout Address " --inputbox "Enter your Glcoin mining address (bech32 gc1...)" 8 60 "${address}" 3>&1 1>&2 2>&3)
        [ -n "${NEW_ADDR}" ] && sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-address "${NEW_ADDR}"
        ;;
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
      UNINSTALL) sudo /home/admin/config.scripts/bonus.glcoin-miner.sh off ;;
    esac
  fi
  exit 0
fi

# SET ADDRESS
if [ "$1" = "set-address" ]; then
  ADDR="${2}"
  if [ -z "${ADDR}" ]; then
    echo "error='missing address'"
    exit 1
  fi
<<<<<<< HEAD
  sudo mkdir -p "${MINER_DIR}"
  # preserve existing keys, update only address
  sudo sed -i '/^address=/d' "${MINER_CONF}" 2>/dev/null || true
  echo "address='${ADDR}'" | sudo tee -a "${MINER_CONF}" > /dev/null
=======
  mkdir -p "${MINER_DIR}"
  echo "address='${ADDR}'" | sudo tee "${MINER_DIR}/miner.conf" > /dev/null
  # update service if installed
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
  if [ -f "${SERVICE_FILE}" ]; then
    sudo /home/admin/config.scripts/bonus.glcoin-miner.sh on
  fi
  echo "# Payout address set to: ${ADDR}"
  exit 0
fi

# SET MODE
if [ "$1" = "set-mode" ]; then
  MODE="${2:-plain}"
  if [ "${MODE}" != "plain" ] && [ "${MODE}" != "ipfs" ]; then
    echo "error='mode must be plain or ipfs'"
    exit 1
  fi
<<<<<<< HEAD
  sudo mkdir -p "${MINER_DIR}"
  sudo sed -i '/^mode=/d' "${MINER_CONF}" 2>/dev/null || true
  echo "mode='${MODE}'" | sudo tee -a "${MINER_CONF}" > /dev/null
  if [ -f "${SERVICE_FILE}" ]; then
    sudo /home/admin/config.scripts/bonus.glcoin-miner.sh on
  fi
=======
  mkdir -p "${MINER_DIR}"
  sed -i '/^mode=/d' "${MINER_DIR}/miner.conf" 2>/dev/null
  echo "mode='${MODE}'" | sudo tee -a "${MINER_DIR}/miner.conf" > /dev/null
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
  echo "# Mining mode set to: ${MODE}"
  exit 0
fi

<<<<<<< HEAD
# SET TXID (mine-ipfs anchor transaction)
if [ "$1" = "set-txid" ]; then
  TXID="${2}"
  if [ -z "${TXID}" ]; then
    echo "error='missing txid'"
    exit 1
  fi
  sudo mkdir -p "${MINER_DIR}"
  sudo sed -i '/^txid=/d' "${MINER_CONF}" 2>/dev/null || true
  echo "txid='${TXID}'" | sudo tee -a "${MINER_CONF}" > /dev/null
  if [ -f "${SERVICE_FILE}" ]; then
    sudo /home/admin/config.scripts/bonus.glcoin-miner.sh on
  fi
  echo "# Anchor txid set to: ${TXID}"
  exit 0
fi

=======
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
# INSTALL / ON
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# Installing Glcoin Miner ..."

<<<<<<< HEAD
  apt-get install -y -q python3 2>/dev/null || true

  if [ ! -f "${MINER_SCRIPT}" ]; then
    echo "error='${MINER_SCRIPT} not found — ensure RaspiBlesk is fully installed'"
=======
  # install python3 if not present
  apt-get install -y -q python3 2>/dev/null || true

  # install miner script from raspiblesk source
  mkdir -p "${MINER_DIR}"
  if [ -f "/home/admin/raspiblesk/home.admin/config.scripts/glcoin_miner.py" ]; then
    cp /home/admin/raspiblesk/home.admin/config.scripts/glcoin_miner.py "${MINER_SCRIPT}"
  elif [ -f "/home/admin/glcoin-miner/glcoin_miner.py" ]; then
    cp /home/admin/glcoin-miner/glcoin_miner.py "${MINER_SCRIPT}"
  else
    echo "error='glcoin_miner.py not found — copy it to /opt/glcoin-miner/glcoin_miner.py'"
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
    exit 1
  fi
  chmod +x "${MINER_SCRIPT}"

<<<<<<< HEAD
  sudo mkdir -p "${MINER_DIR}"

  # load config
  address=""
  mode="plain"
  txid=""
  [ -f "${MINER_CONF}" ] && source "${MINER_CONF}" 2>/dev/null

  if [ -z "${address}" ]; then
    echo "# WARNING: no payout address configured."
    echo "# Run: sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-address <gc1...>"
    echo "# Then restart: sudo systemctl restart glcoin-miner"
  fi

  # Build ExecStart depending on mode
  if [ "${mode}" = "ipfs" ] && [ -n "${txid}" ]; then
    EXEC_START="/usr/bin/python3 ${MINER_SCRIPT} \
    --datadir=/mnt/hdd/app-data/glcoin \
    mine-ipfs \
    --address ${address:-PAYOUT_ADDRESS_NOT_SET} \
    --txid ${txid} \
    --from-store"
  else
    EXEC_START="/usr/bin/python3 ${MINER_SCRIPT} \
    --datadir=/mnt/hdd/app-data/glcoin \
    mine-plain \
    --address ${address:-PAYOUT_ADDRESS_NOT_SET}"
  fi

  echo "
[Unit]
Description=Glcoin CPU Miner (${mode})
=======
  # load config
  address=""
  mode="plain"
  [ -f "${MINER_DIR}/miner.conf" ] && source "${MINER_DIR}/miner.conf" 2>/dev/null

  if [ -z "${address}" ]; then
    echo "# WARNING: no payout address configured."
    echo "# Run: sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-address <gc1...address>"
    echo "# Then restart: sudo systemctl restart glcoin-miner"
  fi

  # write systemd service
  echo "
[Unit]
Description=Glcoin CPU Miner (mine-${mode})
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
After=glcoind.service
Requires=glcoind.service

[Service]
User=glcoin
Group=glcoin
WorkingDirectory=${MINER_DIR}
<<<<<<< HEAD
ExecStart=${EXEC_START}
=======
EnvironmentFile=-/etc/glcoin/glcoin.conf
ExecStart=/usr/bin/python3 ${MINER_SCRIPT} \\
    --datadir=/mnt/hdd/app-data/glcoin \\
    mine-${mode} \\
    --address ${address:-PAYOUT_ADDRESS_NOT_SET}
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
Restart=on-failure
RestartSec=30s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
" | sudo tee "${SERVICE_FILE}"

  sudo systemctl daemon-reload
  sudo systemctl enable glcoin-miner

<<<<<<< HEAD
  if [ -n "${address}" ]; then
    sudo systemctl restart glcoin-miner
    echo "# Glcoin Miner started — mining to ${address} (mode: ${mode})"
  else
    echo "# Glcoin Miner installed but NOT started (no address set)"
    echo "# sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-address <gc1...>"
=======
  if [ -n "${address}" ] && [ "${address}" != "PAYOUT_ADDRESS_NOT_SET" ]; then
    sudo systemctl start glcoin-miner
    echo "# Glcoin Miner started — mining to ${address}"
  else
    echo "# Glcoin Miner installed but NOT started (no address set)"
    echo "# Set address then start:"
    echo "# sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-address <address>"
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
    echo "# sudo systemctl start glcoin-miner"
  fi

  /home/admin/config.scripts/blesk.conf.sh set glcoinMiner "on"
  echo "OK glcoin-miner installed"
  exit 0
fi

# UNINSTALL / OFF
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# Uninstalling Glcoin Miner ..."
  sudo systemctl stop glcoin-miner 2>/dev/null
  sudo systemctl disable glcoin-miner 2>/dev/null
  sudo rm -f "${SERVICE_FILE}"
  sudo systemctl daemon-reload
  /home/admin/config.scripts/blesk.conf.sh set glcoinMiner "off"
<<<<<<< HEAD
  echo "# Glcoin Miner uninstalled (config preserved at ${MINER_CONF})"
=======
  echo "# Glcoin Miner uninstalled (miner config kept at ${MINER_DIR}/miner.conf)"
>>>>>>> 27c1a3bb2 (feat: integrate Glcoin CPU miner, remove public-pool server)
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
