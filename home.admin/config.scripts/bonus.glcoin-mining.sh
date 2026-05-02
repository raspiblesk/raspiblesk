#!/bin/bash

# Glcoin CPU miner using cpuminer-multi
# Integrates with the Glcoin KYC miner registry (enforced from block 1000).
# https://github.com/tpruvot/cpuminer-multi

MINER_BINARY="/usr/local/bin/minerd"
MINER_SERVICE="/etc/systemd/system/glcoin-mining.service"
MINER_CONFIG="/mnt/hdd/app-data/glcoin/mining.conf"
GLCOIN_CONF="/mnt/hdd/app-data/glcoin/glcoin.conf"
GLCOIN_CLI="sudo -u glcoin /usr/local/bin/glcoin-cli -rpcport=1617"
REGISTRY_HEIGHT=1111

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "# Glcoin CPU miner — KYC registry integrated"
  echo "# bonus.glcoin-mining.sh [install|uninstall]"
  echo "# bonus.glcoin-mining.sh [on|off|status]"
  echo "# bonus.glcoin-mining.sh threads <n>"
  echo "# bonus.glcoin-mining.sh register <kyc_id> <display_name>"
  echo "# bonus.glcoin-mining.sh approve [address]   # admin: approve via on-chain GLCM tx"
  exit 1
fi

source /mnt/hdd/app-data/raspiblesk.conf 2>/dev/null
source /mnt/disk_storage/app-data/raspiblesk.conf 2>/dev/null

# helper: get mining address from config
getMiningAddress() {
  grep "^miningAddress=" "${MINER_CONFIG}" 2>/dev/null | cut -d= -f2
}

# helper: query registry status for the mining address
getRegistryStatus() {
  local addr="$1"
  ${GLCOIN_CLI} listminers 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data:
    if m.get('address') == '${addr}':
        print(m.get('status','unknown'))
        sys.exit(0)
print('unregistered')
" 2>/dev/null || echo "unknown"
}

##############
# STATUS
##############
if [ "$1" = "status" ]; then

  isInstalled=0
  [ -f "${MINER_BINARY}" ] && isInstalled=1
  echo "isInstalled=${isInstalled}"

  isRunning=0
  systemctl is-active --quiet glcoin-mining.service && isRunning=1
  echo "isRunning=${isRunning}"

  miningAddress=$(getMiningAddress)
  echo "miningAddress=${miningAddress}"

  threads=$(grep -oP '(?<=--threads=)\d+' "${MINER_SERVICE}" 2>/dev/null || echo "not set")
  echo "threads=${threads}"

  if [ -n "${miningAddress}" ]; then
    registryStatus=$(getRegistryStatus "${miningAddress}")
    echo "registryStatus=${registryStatus}"
  fi

  currentHeight=$(${GLCOIN_CLI} getblockcount 2>/dev/null || echo "0")
  echo "currentHeight=${currentHeight}"

  if [ "${currentHeight}" -ge "${REGISTRY_HEIGHT}" ] 2>/dev/null; then
    echo "enforcementActive=1"
  else
    blocksUntilEnforcement=$(( REGISTRY_HEIGHT - currentHeight ))
    echo "enforcementActive=0"
    echo "blocksUntilEnforcement=${blocksUntilEnforcement}"
  fi

  if [ "${isRunning}" = "1" ]; then
    hashrate=$(journalctl -u glcoin-mining.service --no-pager -n 100 2>/dev/null | \
      grep -oP '\d+\.\d+ [kMG]?H/s' | tail -1)
    echo "hashrate=${hashrate}"
  fi

  exit 0
fi

##############
# INSTALL
##############
if [ "$1" = "install" ]; then

  if [ -f "${MINER_BINARY}" ]; then
    echo "result='already installed'"
    exit 0
  fi

  echo "# *** INSTALL cpuminer-multi ***"

  # Try bundled pre-built binary first (avoids internet + build deps at runtime)
  ARCH=$(uname -m)
  BUNDLED_BINARY="/home/admin/assets/minerd-${ARCH}"
  if [ -f "${BUNDLED_BINARY}" ]; then
    echo "# Using bundled minerd for ${ARCH}"
    install -m 0755 "${BUNDLED_BINARY}" "${MINER_BINARY}"
    echo "# OK - cpuminer-multi installed from bundle"
    echo "result='installed'"
    exit 0
  fi

  # Fall back: build from source (requires internet + build deps)
  echo "# No bundled binary for ${ARCH} — building from source"
  apt-get install -y build-essential libcurl4-openssl-dev libssl-dev \
    libjansson-dev automake git 2>/dev/null

  BUILD_DIR=$(mktemp -d)
  git clone --depth=1 https://github.com/tpruvot/cpuminer-multi.git "${BUILD_DIR}" || {
    echo "error='failed to clone cpuminer-multi'"
    rm -rf "${BUILD_DIR}"
    exit 1
  }
  cd "${BUILD_DIR}" || exit 1
  ./autogen.sh
  ./configure --disable-assembly \
    CFLAGS="-O2 -march=native" \
    --with-crypto --with-curl || {
    echo "error='configure failed'"
    rm -rf "${BUILD_DIR}"
    exit 1
  }
  make -j$(nproc) || {
    echo "error='build failed'"
    rm -rf "${BUILD_DIR}"
    exit 1
  }
  install -m 0755 minerd "${MINER_BINARY}"
  rm -rf "${BUILD_DIR}"

  echo "# OK - cpuminer-multi installed"
  echo "result='installed'"
  exit 0
fi

##############
# UNINSTALL
##############
if [ "$1" = "uninstall" ]; then

  systemctl stop glcoin-mining.service 2>/dev/null
  systemctl disable glcoin-mining.service 2>/dev/null
  rm -f "${MINER_SERVICE}"
  systemctl daemon-reload
  rm -f "${MINER_BINARY}"
  rm -f "${MINER_CONFIG}"
  /home/admin/config.scripts/blesk.conf.sh delete glcoinMiner 2>/dev/null

  echo "# OK - Glcoin miner uninstalled"
  exit 0
fi

##############
# SET THREADS
##############
if [ "$1" = "threads" ]; then

  threadCount=$2
  if [ -z "${threadCount}" ] || ! [[ "${threadCount}" =~ ^[0-9]+$ ]]; then
    echo "error='usage: bonus.glcoin-mining.sh threads <n>'"
    exit 1
  fi
  mkdir -p "$(dirname ${MINER_CONFIG})"
  if grep -q "^threads=" "${MINER_CONFIG}" 2>/dev/null; then
    sed -i "s/^threads=.*/threads=${threadCount}/" "${MINER_CONFIG}"
  else
    echo "threads=${threadCount}" >> "${MINER_CONFIG}"
  fi
  if [ -f "${MINER_SERVICE}" ]; then
    /home/admin/config.scripts/bonus.glcoin-mining.sh on
    echo "# Threads updated and miner restarted with ${threadCount} thread(s)"
  else
    echo "# Thread count saved — will apply when mining is switched on"
  fi
  exit 0
fi

##############
# REGISTER
# Submits a pending application to the miner registry.
# The coinbase address must be approved by the Glcoin admin
# before block 1000 for the miner to produce valid blocks.
##############
if [ "$1" = "register" ]; then

  kycId="$2"
  displayName="$3"

  if [ -z "${kycId}" ] || [ -z "${displayName}" ]; then
    echo "error='usage: bonus.glcoin-mining.sh register <kyc_id> <display_name>'"
    exit 1
  fi

  miningAddress=$(getMiningAddress)
  if [ -z "${miningAddress}" ]; then
    echo "error='no mining address set yet — run: bonus.glcoin-mining.sh on first'"
    exit 1
  fi

  echo "# Registering mining address ${miningAddress} with the Glcoin miner registry ..."
  result=$(${GLCOIN_CLI} registerminer "${miningAddress}" "${kycId}" "${displayName}" 2>&1)
  if echo "${result}" | grep -q "error\|Error"; then
    echo "# Registry response: ${result}"
    echo "error='registration failed'"
    exit 1
  fi

  echo "# OK - Registration submitted (status: pending)"
  echo "# Your mining address: ${miningAddress}"
  echo "# KYC ID: ${kycId}"
  echo "#"
  echo "# Next step: send your address and KYC ID to the Glcoin admin"
  echo "# for approval before block ${REGISTRY_HEIGHT}."
  echo "# The admin approves on-chain from the authority wallet:"
  echo "#   glcoin-cli approveminer ${miningAddress}"
  echo "# The approval is final once that transaction is mined."

  # save kyc info to mining config for reference
  sed -i '/^kycId=/d' "${MINER_CONFIG}" 2>/dev/null
  sed -i '/^displayName=/d' "${MINER_CONFIG}" 2>/dev/null
  echo "kycId=${kycId}" >> "${MINER_CONFIG}"
  echo "displayName=${displayName}" >> "${MINER_CONFIG}"

  exit 0
fi

##############
# APPROVE
# Admin-side: approve a miner via on-chain GLCM transaction.
# Authority wallet must be loaded and unlocked on this node.
##############
if [ "$1" = "approve" ]; then

  miningAddress="$2"

  # if no explicit address, use local mining address
  if [ -z "${miningAddress}" ]; then
    miningAddress=$(getMiningAddress)
  fi

  if [ -z "${miningAddress}" ]; then
    echo "error='usage: bonus.glcoin-mining.sh approve [address]'"
    exit 1
  fi

  result=$(${GLCOIN_CLI} approveminer "${miningAddress}" 2>&1)
  txid=$(echo "${result}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('txid',''))" 2>/dev/null)
  if [ -n "${txid}" ]; then
    echo "# OK - GLCM approval tx broadcast. Registry updates when mined."
    echo "# Miner:  ${miningAddress}"
    echo "# Txid:   ${txid}"
  else
    echo "# Registry response: ${result}"
    echo "error='approval failed — is the authority wallet loaded and unlocked?'"
    exit 1
  fi
  exit 0
fi

##############
# ON
##############
if [ "$1" = "on" ] || [ "$1" = "1" ]; then

  echo "# *** Switching ON Glcoin CPU Mining ***"

  # install miner binary if missing
  if [ ! -f "${MINER_BINARY}" ]; then
    /home/admin/config.scripts/bonus.glcoin-mining.sh install || exit 1
  fi

  # get RPC credentials from glcoin.conf
  RPCUSER=$(grep "^rpcuser=" "${GLCOIN_CONF}" 2>/dev/null | cut -d= -f2 | tail -1)
  RPCPASS=$(grep "^rpcpassword=" "${GLCOIN_CONF}" 2>/dev/null | cut -d= -f2 | tail -1)
  if [ -z "${RPCUSER}" ] || [ -z "${RPCPASS}" ]; then
    echo "error='could not read RPC credentials from ${GLCOIN_CONF}'"
    exit 1
  fi

  # get mining address — must be pre-configured (wallet is disabled on this node)
  mkdir -p "$(dirname ${MINER_CONFIG})"
  miningAddress=$(getMiningAddress)
  if [ -z "${miningAddress}" ]; then
    echo "error='no mining address configured'"
    echo "# Set your payout address (gc1...) first:"
    echo "#   sudo bash -c \"echo miningAddress=gc1... >> ${MINER_CONFIG}\""
    exit 1
  fi

  # check registry status and warn if needed
  currentHeight=$(${GLCOIN_CLI} getblockcount 2>/dev/null || echo "0")
  registryStatus=$(getRegistryStatus "${miningAddress}")

  if [ "${registryStatus}" = "unregistered" ]; then
    echo "#"
    echo "# WARNING: Mining address is not registered in the Glcoin miner registry."
    echo "# Mining will work until block ${REGISTRY_HEIGHT}."
    echo "# After block ${REGISTRY_HEIGHT} only KYC-approved addresses can produce blocks."
    echo "# Register with:"
    echo "#   bonus.glcoin-mining.sh register <kyc_id> \"<display_name>\""
    echo "#"
  elif [ "${registryStatus}" = "pending" ]; then
    echo "#"
    echo "# WARNING: Mining address is registered but pending admin approval."
    echo "# Mining will work until block ${REGISTRY_HEIGHT}."
    echo "# Contact the Glcoin admin to get your address approved."
    echo "#"
  elif [ "${registryStatus}" = "approved" ]; then
    echo "# OK - Mining address is approved in the registry."
  elif [ "${registryStatus}" = "revoked" ] || [ "${registryStatus}" = "suspended" ]; then
    if [ "${currentHeight}" -ge "${REGISTRY_HEIGHT}" ] 2>/dev/null; then
      echo "error='Mining address is ${registryStatus} — blocks will be rejected by the network'"
      exit 1
    else
      echo "# WARNING: Mining address is ${registryStatus} in the registry."
      echo "# Blocks will be rejected after block ${REGISTRY_HEIGHT}."
    fi
  fi

  # read thread count (default: all cores minus 1, minimum 1)
  threadCount=$(grep "^threads=" "${MINER_CONFIG}" 2>/dev/null | cut -d= -f2)
  if [ -z "${threadCount}" ]; then
    totalCores=$(nproc)
    threadCount=$(( totalCores > 1 ? totalCores - 1 : 1 ))
  fi
  echo "# Using ${threadCount} thread(s)"

  # write systemd service
  cat > "${MINER_SERVICE}" << EOF
[Unit]
Description=Glcoin CPU Miner
After=glcoind.service
Requires=glcoind.service

[Service]
User=glcoin
Group=glcoin
ExecStart=${MINER_BINARY} \\
  --algo=sha256d \\
  --url=http://127.0.0.1:1617/ \\
  --user=${RPCUSER} \\
  --pass=${RPCPASS} \\
  --coinbase-addr=${miningAddress} \\
  --threads=${threadCount} \\
  --retry-pause=10
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable glcoin-mining.service
  systemctl restart glcoin-mining.service
  sleep 3

  if systemctl is-active --quiet glcoin-mining.service; then
    /home/admin/config.scripts/blesk.conf.sh set glcoinMiner "on"
    echo "# OK - Glcoin CPU mining started"
    echo "# Address: ${miningAddress}  (registry: ${registryStatus})"
    echo "# Threads: ${threadCount}"
    echo "# Monitor: journalctl -fu glcoin-mining.service"
  else
    echo "error='glcoin-mining.service failed to start'"
    journalctl -u glcoin-mining.service --no-pager -n 20
    exit 1
  fi

  exit 0
fi

##############
# OFF
##############
if [ "$1" = "off" ] || [ "$1" = "0" ]; then

  systemctl stop glcoin-mining.service 2>/dev/null
  systemctl disable glcoin-mining.service 2>/dev/null
  /home/admin/config.scripts/blesk.conf.sh set glcoinMiner "off"

  echo "# OK - Glcoin CPU mining stopped"
  exit 0
fi

##############
# MENU
##############
if [ "$1" = "menu" ]; then

  # collect status
  isInstalled=0
  [ -f "${MINER_BINARY}" ] && isInstalled=1

  isRunning=0
  systemctl is-active --quiet glcoin-mining.service 2>/dev/null && isRunning=1

  miningAddress=$(getMiningAddress)
  threadCount=$(grep "^threads=" "${MINER_CONFIG}" 2>/dev/null | cut -d= -f2)
  [ -z "${threadCount}" ] && threadCount="auto ($(( $(nproc) > 1 ? $(nproc) - 1 : 1 )))"

  registryStatus="n/a"
  if [ -n "${miningAddress}" ]; then
    registryStatus=$(getRegistryStatus "${miningAddress}")
  fi

  currentHeight=$(${GLCOIN_CLI} getblockcount 2>/dev/null || echo "0")
  hashrate=""
  if [ "${isRunning}" = "1" ]; then
    hashrate=$(journalctl -u glcoin-mining.service --no-pager -n 100 2>/dev/null | \
      grep -oP '\d+\.\d+ [kMG]?H/s' | tail -1)
  fi

  # build status lines
  statusLine="Status:  $([ "${isRunning}" = "1" ] && echo "RUNNING" || echo "stopped")"
  [ -n "${hashrate}" ] && statusLine="${statusLine}  (${hashrate})"
  addrLine="Address: ${miningAddress:-not set}"
  regLine="Registry: ${registryStatus}  |  Block: ${currentHeight}"
  threadLine="Threads: ${threadCount}"

  OPTIONS=()
  if [ "${isRunning}" = "1" ]; then
    OPTIONS+=(OFF "Stop Mining")
  else
    OPTIONS+=(ON "Start Mining")
  fi
  OPTIONS+=(THREADS "Set Thread Count")
  OPTIONS+=(REGISTER "Register KYC Identity")
  OPTIONS+=(STATUS "Show Full Status")

  CHOICE=$(dialog --clear \
    --backtitle "RaspiBlesk" \
    --title " Glcoin CPU Miner " \
    --menu "\n${statusLine}\n${addrLine}\n${regLine}\n${threadLine}\n\nOptions:" \
    18 60 5 \
    "${OPTIONS[@]}" \
    2>&1 >/dev/tty)

  case $CHOICE in
    ON)
      clear
      /home/admin/config.scripts/bonus.glcoin-mining.sh on
      echo ""
      echo "Press ENTER to return to menu."
      read -r key
      ;;
    OFF)
      clear
      /home/admin/config.scripts/bonus.glcoin-mining.sh off
      echo ""
      echo "Press ENTER to return to menu."
      read -r key
      ;;
    THREADS)
      n=$(dialog --clear --title " Set Thread Count " \
        --inputbox "Enter number of CPU threads (1-$(nproc)):" 8 40 \
        2>&1 >/dev/tty)
      if [[ "${n}" =~ ^[0-9]+$ ]] && [ "${n}" -ge 1 ]; then
        /home/admin/config.scripts/bonus.glcoin-mining.sh threads "${n}"
        dialog --msgbox "Thread count set to ${n}." 6 40
      fi
      ;;
    REGISTER)
      kycId=$(dialog --clear --title " KYC Registration " \
        --inputbox "Enter your KYC ID:" 8 50 \
        2>&1 >/dev/tty)
      if [ -n "${kycId}" ]; then
        dispName=$(dialog --clear --title " KYC Registration " \
          --inputbox "Enter display name:" 8 50 \
          2>&1 >/dev/tty)
        if [ -n "${dispName}" ]; then
          clear
          /home/admin/config.scripts/bonus.glcoin-mining.sh register "${kycId}" "${dispName}"
          echo ""
          echo "Press ENTER to return to menu."
          read -r key
        fi
      fi
      ;;
    STATUS)
      clear
      /home/admin/config.scripts/bonus.glcoin-mining.sh status
      echo ""
      echo "Press ENTER to return to menu."
      read -r key
      ;;
  esac

  exit 0
fi
