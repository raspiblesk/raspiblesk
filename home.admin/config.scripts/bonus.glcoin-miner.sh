#!/bin/bash

# Glcoin CPU Miner — glcoin_miner.py wrapper
# Installs and manages the Glcoin mining worker as a systemd service.
# Supports plain mining (mine-plain) and IPFS-anchored mining (mine-ipfs).

MINER_DIR="/opt/glcoin-miner"
SERVICE_FILE="/etc/systemd/system/glcoin-miner.service"
MINER_SCRIPT="/home/admin/config.scripts/glcoin_miner.py"
MINER_CONF="${MINER_DIR}/miner.conf"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Glcoin CPU Miner install script"
  echo "bonus.glcoin-miner.sh [on|off|status|menu]"
  echo "bonus.glcoin-miner.sh set-address <glcoin-address>"
  echo "bonus.glcoin-miner.sh set-mode [plain|ipfs]"
  echo "bonus.glcoin-miner.sh set-txid <anchor-txid>   (mine-ipfs mode)"
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
  txid=""

  # installed = service file exists (MINER_SCRIPT always exists in a full install)
  [ -f "${SERVICE_FILE}" ] && installed=1
  if [ -f "${SERVICE_FILE}" ]; then
    active=$(systemctl is-active glcoin-miner 2>/dev/null | grep -c "^active")
  fi
  [ -f "${MINER_CONF}" ] && source "${MINER_CONF}" 2>/dev/null

  echo "installed=${installed}"
  echo "active=${active}"
  echo "address='${address}'"
  echo "mode='${mode}'"
  echo "txid='${txid}'"
  exit 0
fi

# MENU
if [ "$1" = "menu" ]; then
  source <(sudo /home/admin/config.scripts/bonus.glcoin-miner.sh status)
  if [ "${installed}" = "0" ]; then
    # Pre-flight: glcoind must be running
    if ! systemctl is-active glcoind >/dev/null 2>&1; then
      whiptail --title " Glcoind nicht aktiv " --msgbox \
"glcoind muss laufen und synchronisiert sein, bevor der Miner gestartet werden kann.

Starte zuerst glcoind über das Glcoin-Menü." 10 64
      exit 0
    fi
    # Pre-flight: glcoin.conf mit RPC-Credentials muss vorhanden sein
    _CONF_CHECK="/mnt/hdd/app-data/glcoin/glcoin.conf"
    if [ ! -f "${_CONF_CHECK}" ]; then
      whiptail --title " Konfiguration fehlt " --msgbox \
"Glcoin-Konfiguration nicht gefunden:
${_CONF_CHECK}

Stelle sicher dass glcoind vollständig eingerichtet ist." 10 70
      exit 0
    fi
    _RPC_USER_CHECK=$(grep "^rpcuser=" "${_CONF_CHECK}" 2>/dev/null | cut -d= -f2 | tail -1)
    _RPC_PASS_CHECK=$(grep "^rpcpassword=" "${_CONF_CHECK}" 2>/dev/null | cut -d= -f2 | tail -1)
    if [ -z "${_RPC_USER_CHECK}" ] || [ -z "${_RPC_PASS_CHECK}" ]; then
      whiptail --title " RPC-Credentials fehlen " --msgbox \
"In ${_CONF_CHECK} fehlen rpcuser oder rpcpassword.

Ergänze die RPC-Zugangsdaten und versuche es erneut." 10 70
      exit 0
    fi

    whiptail --title " Glcoin Miner " --yesno "
Install the Glcoin CPU miner?

Mines blocks and sends rewards to your Glcoin address.
Requires glcoind to be running and synced.
" 12 52
    [ $? -eq 0 ] || exit 0
    # Ask for payout address before installing
    NEW_ADDR=$(whiptail --title " Payout Address " --inputbox \
"Enter your Glcoin mining address (bech32 gc1...)

This address receives all block rewards.
Example: gc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh" \
      12 66 "" 3>&1 1>&2 2>&3)
    if [ -z "${NEW_ADDR}" ]; then
      whiptail --title " Cancelled " --msgbox "No address entered. Installation cancelled." 7 50
      exit 0
    fi
    if ! echo "${NEW_ADDR}" | grep -qE '^gc1[a-z0-9]{10,}$'; then
      whiptail --title " Invalid Address " --msgbox \
        "Address must be a valid Glcoin bech32 address starting with gc1." 7 58
      exit 0
    fi
    sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-address "${NEW_ADDR}"
    INSTALL_OUT=$(sudo /home/admin/config.scripts/bonus.glcoin-miner.sh on 2>&1)
    INSTALL_RC=$?
    if [ ${INSTALL_RC} -ne 0 ]; then
      whiptail --title " Installation fehlgeschlagen " --msgbox \
"Der Glcoin Miner konnte nicht installiert werden.

Fehler:
${INSTALL_OUT}" 16 72
      exit 1
    fi
    whiptail --title " Miner gestartet " --msgbox \
"Glcoin Miner wurde installiert und gestartet!

Mining-Adresse:
${NEW_ADDR}

Öffne das Miner-Menü erneut um Status und Einstellungen zu verwalten." 13 64
  else
    GLC_CLI="sudo -u glcoin /usr/local/bin/glcoin-cli -rpcport=1617"

    # Block height
    BLOCKCOUNT=$(${GLC_CLI} getblockcount 2>/dev/null || echo "?")

    # Miner permit status from registry
    PERMIT_STATUS="?"
    if [ -n "${address}" ]; then
      MINER_JSON=$(${GLC_CLI} getminerinfo "${address}" 2>/dev/null)
      if echo "${MINER_JSON}" | grep -q '"status"'; then
        PERMIT_STATUS=$(echo "${MINER_JSON}" | grep -oP '"status"\s*:\s*"\K[^"]+' 2>/dev/null \
          || echo "${MINER_JSON}" | sed 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
      else
        PERMIT_STATUS="not registered"
      fi
    fi

    # Service state label
    SVC_STATE="stopped"
    [ "${active}" = "1" ] && SVC_STATE="MINING"

    # Truncated address for display
    ADDR_SHORT="${address:-(not set)}"
    [ "${#address}" -gt 32 ] && ADDR_SHORT="${address:0:20}...${address: -8}"

    MENU_TEXT="\n Status: ${SVC_STATE}  |  Block height: ${BLOCKCOUNT}\n Permit: ${PERMIT_STATUS}  |  Mode: ${mode}\n Address: ${ADDR_SHORT}\n"

    OPTIONS=()
    if [ "${active}" = "1" ]; then
      OPTIONS+=(STOP "Stop miner")
    else
      OPTIONS+=(START "Start miner")
    fi
    OPTIONS+=(ADDRESS "Set payout address")
    OPTIONS+=(MODE "Mining mode: ${mode}")
    if [ "${mode}" = "ipfs" ]; then
      OPTIONS+=(TXID "Anchor txid: ${txid:0:20}...")
    fi
    if [ "${PERMIT_STATUS}" = "not registered" ] && [ -n "${address}" ]; then
      OPTIONS+=(REGISTER "Apply for mining permit")
    fi
    OPTIONS+=(VIEWLOG "View recent mining log")
    OPTIONS+=(UNINSTALL "Uninstall miner")

    CHOICE=$(whiptail --title " Glcoin Miner " --menu "${MENU_TEXT}" 18 68 8 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
    case "${CHOICE}" in
      START)   sudo systemctl start glcoin-miner ;;
      STOP)    sudo systemctl stop glcoin-miner ;;
      ADDRESS)
        NEW_ADDR=$(whiptail --title " Payout Address " --inputbox \
          "Enter your Glcoin mining address (bech32 gc1...)

This address must match your approved miner permit.
Example: gc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh" \
          12 66 "${address}" 3>&1 1>&2 2>&3)
        if [ -n "${NEW_ADDR}" ]; then
          if ! echo "${NEW_ADDR}" | grep -qE '^gc1[a-z0-9]{10,}$'; then
            whiptail --title " Invalid Address " --msgbox \
              "Address must be a valid Glcoin bech32 address starting with gc1." 7 58
          else
            sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-address "${NEW_ADDR}"
          fi
        fi
        ;;
      MODE)
        NEW_MODE=$(whiptail --title " Mining Mode " --menu "" 10 62 2 \
          plain "Block mining — Tier 1 permit required" \
          ipfs  "IPFS-anchored mining — Tier 2 permit required" 3>&1 1>&2 2>&3)
        [ -n "${NEW_MODE}" ] && sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-mode "${NEW_MODE}"
        ;;
      TXID)
        NEW_TXID=$(whiptail --title " IPFS Anchor txid " --inputbox \
          "Enter the anchor transaction txid to commit in the coinbase." 8 72 "${txid}" 3>&1 1>&2 2>&3)
        [ -n "${NEW_TXID}" ] && sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-txid "${NEW_TXID}"
        ;;
      REGISTER)
        whiptail --title " Mining Permit Application " --yesno \
"Apply for a Glcoin mining permit for address:

${address}

This submits a registration request to the local node.
Contact the Glcoin admin to complete KYC approval
and have your permit approved." 14 66
        if [ $? -eq 0 ]; then
          DISP_NAME=$(whiptail --title " Display Name " --inputbox \
            "Enter your miner display name (e.g. 'Alice - Germany'):" 8 60 "" 3>&1 1>&2 2>&3)
          [ -z "${DISP_NAME}" ] && DISP_NAME="RaspiBlesk Miner"
          KYC_ID="PENDING-$(date +%Y%m%d)"
          RESULT=$(${GLC_CLI} registerminer "${address}" "${KYC_ID}" "${DISP_NAME}" 2>&1)
          whiptail --title " Registration Submitted " --msgbox \
"Application submitted to the local registry.

Your KYC reference: ${KYC_ID}
Contact admin at admin@glcoin.org to complete approval.

Node response:
${RESULT}" 14 68
        fi
        ;;
      VIEWLOG)
        LOG=$(journalctl -u glcoin-miner -n 40 --no-pager 2>/dev/null || echo "(no log entries found)")
        whiptail --title " Glcoin Miner — Recent Log " --scrolltext --msgbox "${LOG}" 24 90
        ;;
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
  sudo mkdir -p "${MINER_DIR}"
  # preserve existing keys, update only address
  sudo sed -i '/^address=/d' "${MINER_CONF}" 2>/dev/null || true
  echo "address='${ADDR}'" | sudo tee -a "${MINER_CONF}" > /dev/null
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
  sudo mkdir -p "${MINER_DIR}"
  sudo sed -i '/^mode=/d' "${MINER_CONF}" 2>/dev/null || true
  echo "mode='${MODE}'" | sudo tee -a "${MINER_CONF}" > /dev/null
  if [ -f "${SERVICE_FILE}" ]; then
    sudo /home/admin/config.scripts/bonus.glcoin-miner.sh on
  fi
  echo "# Mining mode set to: ${MODE}"
  exit 0
fi

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

# INSTALL / ON
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# Installing Glcoin Miner ..."

  apt-get install -y -q python3 2>/dev/null || true

  if [ ! -f "${MINER_SCRIPT}" ]; then
    echo "error='${MINER_SCRIPT} not found — ensure RaspiBlesk is fully installed'"
    exit 1
  fi
  chmod +x "${MINER_SCRIPT}"

  sudo mkdir -p "${MINER_DIR}"

  # load config
  address=""
  mode="plain"
  txid=""
  [ -f "${MINER_CONF}" ] && source "${MINER_CONF}" 2>/dev/null

  if [ -z "${address}" ]; then
    # No address yet — mark as enabled in config so the menu can configure it,
    # but don't create a broken service. The user sets the address via the menu.
    /home/admin/config.scripts/blesk.conf.sh set glcoinMiner "on"
    echo "# Glcoin Miner enabled — set payout address to start mining:"
    echo "# sudo /home/admin/config.scripts/bonus.glcoin-miner.sh set-address <gc1...>"
    exit 0
  fi

  # read RPC credentials from glcoin.conf (wallet is disabled — no cookie fallback)
  GLCOIN_CONF_FILE="/mnt/hdd/app-data/glcoin/glcoin.conf"
  RPC_USER=$(grep "^rpcuser=" "${GLCOIN_CONF_FILE}" 2>/dev/null | cut -d= -f2 | tail -1)
  RPC_PASS=$(grep "^rpcpassword=" "${GLCOIN_CONF_FILE}" 2>/dev/null | cut -d= -f2 | tail -1)
  if [ -z "${RPC_USER}" ] || [ -z "${RPC_PASS}" ]; then
    echo "error='could not read RPC credentials from ${GLCOIN_CONF_FILE}'"
    exit 1
  fi

  # Build ExecStart as a single line — no backslash continuations (safer for systemd)
  if [ "${mode}" = "ipfs" ] && [ -n "${txid}" ]; then
    EXEC_START="/usr/bin/python3 ${MINER_SCRIPT} --rpc-url http://127.0.0.1:1617/ --rpc-user ${RPC_USER} --rpc-password ${RPC_PASS} mine-ipfs --address ${address} --txid ${txid} --from-store"
  else
    EXEC_START="/usr/bin/python3 ${MINER_SCRIPT} --rpc-url http://127.0.0.1:1617/ --rpc-user ${RPC_USER} --rpc-password ${RPC_PASS} mine-plain --address ${address}"
  fi

  echo "
[Unit]
Description=Glcoin CPU Miner (${mode})
After=glcoind.service
Requires=glcoind.service

[Service]
User=glcoin
Group=glcoin
WorkingDirectory=${MINER_DIR}
ExecStart=${EXEC_START}
Restart=always
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
" | sudo tee "${SERVICE_FILE}"

  sudo systemctl daemon-reload
  sudo systemctl enable glcoin-miner
  sudo systemctl restart glcoin-miner
  echo "# Glcoin Miner started — mining to ${address} (mode: ${mode})"

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
  echo "# Glcoin Miner uninstalled (config preserved at ${MINER_CONF})"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
