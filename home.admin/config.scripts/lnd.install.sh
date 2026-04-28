#!/bin/bash

# "*** LND ***"
## based on https://raspibolt.github.io/raspibolt/raspibolt_40_lnd.html#lightning-lnd
## see LND releases: https://github.com/lightningnetwork/lnd/releases
### If you change here - make sure to also change interims version in lnd.update.sh #!
lndVersion="0.20.99-beta"
GLCOIN_RELEASE="v0.1.12"
GITHUB_RELEASE_BASE="https://github.com/raspiblesk/raspiblesk/releases/download/${GLCOIN_RELEASE}"

# olaoluwa
PGPauthor="roasbeef"
PGPpkeys="https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/roasbeef.asc"
PGPcheck="A5B61896952D9FDA83BC054CDC42612E89237182"

# guggero
# PGPauthor="guggero"
# PGPpkeys="https://keybase.io/guggero/pgp_keys.asc"
# PGPcheck="F4FC70F07310028424EFC20A8E4256593F177720"

# bitconner
#PGPauthor="bitconner"
#PGPpkeys="https://keybase.io/bitconner/pgp_keys.asc"
#PGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install or remove LND services on parallel chains"
  echo "lnd.install.sh install - called by the build_sdcard.sh"
  echo "lnd.install.sh info [?compareVersion]"
  echo "lnd.install.sh on [mainnet|testnet|signet] [?initwallet]"
  echo "lnd.install.sh off [mainnet|testnet|signet] <purge>"
  echo "lnd.install.sh display-seed [mainnet|testnet|signet] [?delete]"
  echo
  exit 1
fi

source <(/home/admin/_cache.sh get network)
if [ "${network}" == "" ]; then
  network="glcoin"
fi

if [ "$1" = "info" ] ; then

  # the version that this script installs by default
  echo "lndDefaultInstallVersion='${lndVersion}'"

  # the version that is installed
  lndInstalledVersion=$(sudo -u admin lnd --version 2>/dev/null | cut -d " " -f3)
  echo "lndInstalledVersion='${lndInstalledVersion}'"

  # if a version string is given as second optional parameter - check update compatibility
  # assumption: if the available version is one miner version lower then asked data is not compatible
  compareVersion=$2
  if [ "${compareVersion}" != "" ]; then
    # use version thats either installed or can be installed
    availableVersion="${lndInstalledVersion}"
    if [ "${availableVersion}" == "" ]; then
      availableVersion="${lndVersion}"
    fi
    # check major & miner version value
    availableMajor=$(echo ${availableVersion} | cut -d "." -f1 | grep -o '[[:digit:]]*' | tail -n 1)
    compareMajor=$(echo ${compareVersion} | cut -d "." -f1 | grep -o '[[:digit:]]*' | tail -n 1)
    availableMiner=$(echo ${availableVersion} | cut -d "." -f2 | grep -o '[[:digit:]]*' | tail -n 1)
    compareMiner=$(echo ${compareVersion} | cut -d "." -f2 | grep -o '[[:digit:]]*' | tail -n 1)
    #echo "# ${availableMajor} ${compareMajor} ${availableMiner} ${compareMiner}"
    if [ "${compareMajor}" != "" ] && [ "${compareMiner}" != "" ]; then
      # check major
      if [ ${availableMajor} -lt ${compareMajor} ]; then
       echo "compatible=0"
      else
        if [ ${availableMiner} -lt ${compareMiner} ]; then
          echo "compatible=0"
        else
          echo "compatible=1"
        fi
      fi
    fi
  fi

  exit 0
fi

if [ "$1" = "install" ] ; then

  echo "# *** INSTALL LND ${lndVersion} (Glcoin-patched) ***"
  echo "# Installs LND built from source with Glcoin chain params."
  echo "# Official LND binaries do NOT know about Glcoin's genesis block"
  echo "# and will refuse to connect to glcoind. A patched build is required."

  # check if lnd binary is already installed
  if [ $(sudo -u admin lnd --version 2>/dev/null | grep -c 'lnd') -gt 0 ]; then
    echo "lnd binary already installed - done"
    exit 0
  fi

  # detect architecture
  if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
    lndArch="armv7"
  elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
    lndArch="arm64"
  elif [ "$(uname -m | grep -c 'x86_64')" -gt 0 ]; then
    lndArch="amd64"
  else
    echo "# FAIL - unsupported architecture: $(uname -m)"
    exit 1
  fi

  # -----------------------------------------------------------------------
  # OPTION 1: pre-built Glcoin-patched LND binary tarball
  # Place lnd-glcoin-${lndVersion}-linux-${arch}.tar.gz in /tmp before running.
  # Format: contains lnd and lncli binaries at the top level.
  # -----------------------------------------------------------------------
  PREBUILT_TARBALL="/tmp/lnd-glcoin-${lndVersion}-linux-${lndArch}.tar.gz"
  if [ ! -f "${PREBUILT_TARBALL}" ]; then
    echo "# Attempting GitHub Release download: ${GITHUB_RELEASE_BASE}/$(basename "${PREBUILT_TARBALL}")"
    wget -q --show-progress --timeout=120 \
      -O "${PREBUILT_TARBALL}" \
      "${GITHUB_RELEASE_BASE}/$(basename "${PREBUILT_TARBALL}")" || rm -f "${PREBUILT_TARBALL}"
  fi
  if [ -f "${PREBUILT_TARBALL}" ]; then
    echo "# Found pre-built Glcoin LND tarball: ${PREBUILT_TARBALL}"
    cd /home/admin/download || exit 1
    tar -xzf "${PREBUILT_TARBALL}" || { echo "# FAIL - could not extract tarball"; exit 1; }
    sudo install -m 0755 -o root -g root lnd lncli /usr/local/bin/
    echo "# Installed from pre-built tarball"
  else
    # -----------------------------------------------------------------------
    # OPTION 2: build from source
    # Requires Go. Downloads btcd + lnd, applies Glcoin patch, builds.
    # On a Raspberry Pi 4 this takes ~30-60 minutes.
    # -----------------------------------------------------------------------
    echo "# No pre-built tarball found at ${PREBUILT_TARBALL}"
    echo "# Building LND from source with Glcoin chain params patch..."
    echo "# (This will take 30-60 minutes on a Raspberry Pi)"

    # install Go if missing
    if ! command -v go &>/dev/null; then
      echo "# Installing Go..."
      apt-get install -y golang-go || {
        # fallback: install upstream Go binary
        GO_VERSION="1.22.3"
        GO_ARCH="${lndArch}"
        [ "${lndArch}" = "armv7" ] && GO_ARCH="armv6l"
        wget -O /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
        tar -C /usr/local -xzf /tmp/go.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/admin/.bashrc
      }
    fi
    export GOPATH=/home/admin/go
    export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin

    BUILD_BASE="/home/admin/lnd-glcoin-build"
    mkdir -p "${BUILD_BASE}"
    cd "${BUILD_BASE}" || exit 1

    # --- patch btcd --------------------------------------------------------
    echo "# Cloning btcd..."
    rm -rf "${BUILD_BASE}/btcd"
    git clone --depth=1 --branch master https://github.com/btcsuite/btcd.git btcd || {
      echo "# FAIL - could not clone btcd"; exit 1
    }
    # copy the Glcoin chain params file
    cp /home/admin/patches/lnd/btcd_glcoin_params.go \
       "${BUILD_BASE}/btcd/chaincfg/glcoin_params.go" || {
      # fallback: look for it relative to this script (one level up = /home/admin)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      cp "${SCRIPT_DIR}/../patches/lnd/btcd_glcoin_params.go" \
         "${BUILD_BASE}/btcd/chaincfg/glcoin_params.go" || {
        echo "# FAIL - could not find btcd_glcoin_params.go patch file"; exit 1
      }
    }

    # --- build LND with patched btcd ---------------------------------------
    echo "# Cloning LND v${lndVersion}..."
    git clone --depth=1 --branch "v${lndVersion}" \
      https://github.com/lightningnetwork/lnd.git lnd || {
      echo "# FAIL - could not clone LND v${lndVersion}"; exit 1
    }
    cd "${BUILD_BASE}/lnd" || exit 1

    # replace btcd dependency with our patched local copy
    go mod edit -replace github.com/btcsuite/btcd="${BUILD_BASE}/btcd"
    go mod tidy

    echo "# Building LND (this is slow on ARM)..."
    make install tags="autopilotrpc chainrpc invoicesrpc routerrpc signrpc walletrpc watchtowerrpc wtclientrpc" || {
      echo "# FAIL - LND build failed"; exit 1
    }

    sudo install -m 0755 -o root -g root "${GOPATH}/bin/lnd" /usr/local/bin/lnd
    sudo install -m 0755 -o root -g root "${GOPATH}/bin/lncli" /usr/local/bin/lncli

    # package for future use (saves 30-60 min on reinstall)
    echo "# Packaging built binaries to ${PREBUILT_TARBALL} for reuse..."
    tar -czf "${PREBUILT_TARBALL}" -C "${GOPATH}/bin" lnd lncli && \
      echo "# Saved to ${PREBUILT_TARBALL} — copy to /tmp on future installs to skip rebuild"
  fi

  # verify installation
  sleep 2
  installed=$(sudo -u admin lnd --version 2>/dev/null)
  if [ ${#installed} -eq 0 ]; then
    echo
    echo "# BUILD FAILED --> lnd binary not found after install"
    exit 1
  fi
  echo "# Installed: ${installed}"
  sudo chown -R admin /home/admin
  echo "# OK - LND (Glcoin-patched) install done"
  exit 0
fi

# CHAIN is signet | testnet | mainnet
CHAIN=$2
if [ -z "${CHAIN}" ] || [ "$2" = purge ]; then
  source /mnt/hdd/app-data/raspiblesk.conf
  CHAIN=${chain}net
fi
if [ "${CHAIN}" = testnet ]||[ "${CHAIN}" = mainnet ]||[ "${CHAIN}" = signet ];then
  echo "# Configuring the LND instance on ${CHAIN}"
else
  echo "# ${CHAIN} is not supported"
  exit 1
fi

# prefix for parallel services
if [ ${CHAIN} = testnet ];then
  netprefix="t"
  portprefix=1
  rpcportmod=1
  zmqprefix=21
  glcoinRpcPort=11617
elif [ ${CHAIN} = signet ];then
  netprefix="s"
  portprefix=3
  rpcportmod=3
  zmqprefix=23
  glcoinRpcPort=31617
elif [ ${CHAIN} = mainnet ];then
  netprefix=""
  portprefix=""
  rpcportmod=0
  zmqprefix=28
  glcoinRpcPort=1617
fi

source /home/admin/raspiblesk.info
source <(/home/admin/_cache.sh get state)
source /mnt/hdd/app-data/raspiblesk.conf

function removeParallelService() {
  if [ -f "/etc/systemd/system/${netprefix}lnd.service" ];then
    echo "# Stopping ${netprefix}lnd ..."
    #sudo -u glcoin /usr/local/bin/lncli --rpcserver localhost:1${rpcportmod}009 stop
    sudo systemctl stop ${netprefix}lnd
    sudo systemctl disable ${netprefix}lnd
    sudo rm /etc/systemd/system/${netprefix}lnd.service 2>/dev/null
    echo "# ${netprefix}lnd.service on ${CHAIN} is stopped and disabled"
    echo
  fi
}

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "${CHAIN}" == "testnet" ] && [ "${testnet}" != "on" ]; then
    echo "# before activating testnet on lnd, first activate testnet on glcoind"
    echo "err='missing glcoin testnet'"
    exit 1
  fi

  if [ "${CHAIN}" == "signet" ] && [ "${signet}" != "on" ]; then
    echo "# before activating signet on lnd, first activate signet on glcoind"
    echo "err='missing glcoin signet'"
    exit 1
  fi

  initwallet=0
  if [ "$3" == "initwallet" ]; then
    initwallet=1
    echo "# OK will init wallet if not exists (may ask for passwordc)"
  fi

  # make sure binary is installed (will skip if already done)
  /home/admin/config.scripts/lnd.install.sh install

  echo "# Make sure the user glcoin is in the debian-tor group"
  sudo usermod -a -G debian-tor glcoin

  sudo ufw allow ${portprefix}9735 comment "${netprefix}lnd"
  sudo ufw allow ${portprefix}8080 comment "${netprefix}lnd REST"
  sudo ufw allow 1${rpcportmod}009 comment "${netprefix}lnd RPC"

  sudo chown -R glcoin:glcoin /mnt/hdd/app-data/lnd
  sudo chmod -R 750 /mnt/hdd/app-data/lnd

  echo "# Create /mnt/hdd/app-data/lnd/${netprefix}lnd.conf"
  if [ ! -f /mnt/hdd/app-data/lnd/${netprefix}lnd.conf ];then
    echo "# LND configuration

[Application Options]
# alias=ALIAS # up to 32 UTF-8 characters
# color=COLOR # choose from: https://www.color-hex.com/
listen=0.0.0.0:${portprefix}9735
rpclisten=0.0.0.0:1${rpcportmod}009
restlisten=0.0.0.0:${portprefix}8080
nat=false
debuglevel=info
gc-canceled-invoices-on-startup=true
gc-canceled-invoices-on-the-fly=true
ignore-historical-gossip-filters=1
stagger-initial-reconnect=true
tlsautorefresh=1
tlsdisableautofill=1
tlscertpath=/mnt/hdd/app-data/lnd/tls.cert
tlskeypath=/mnt/hdd/app-data/lnd/tls.key

# Set to false for nodes with larger amount of channels. This modification leads to increased 
# latency during initialization, yet significantly boosts runtime performance of the daemon.
sync-freelist=true

# Specify the maximum number of logfiles retained in rotation and the threshold size for rotation initiation.
maxlogfiles=2
maxlogfilesize=400

[Bitcoin]
bitcoin.active=1
bitcoin.${CHAIN}=1
bitcoin.node=bitcoind

[Bitcoind]
bitcoind.rpchost=127.0.0.1:${glcoinRpcPort}
bitcoind.rpccookiefile=/mnt/hdd/app-data/glcoin/.cookie
bitcoind.zmqpubrawblock=tcp://127.0.0.1:${zmqprefix}332
bitcoind.zmqpubrawtx=tcp://127.0.0.1:${zmqprefix}333

[bolt]
db.bolt.auto-compact=true
db.bolt.auto-compact-min-age=672h

# Allow for longer latency, especially useful for <8GB RAM Pi and congested mempool
[healthcheck] 
healthcheck.chainbackend.attempts=3
healthcheck.chainbackend.timeout=2m0s 
healthcheck.chainbackend.interval=1m30s
" | sudo -u glcoin tee /mnt/hdd/app-data/lnd/${netprefix}lnd.conf
  else
    echo "# The file /mnt/hdd/app-data/lnd/${netprefix}lnd.conf is already present"
  fi

  # systemd service
  removeParallelService
  echo "# Create /etc/systemd/system/.lnd.service"
  # based on https://github.com/lightningnetwork/lnd/blob/master/contrib/init/lnd.service
  echo "
[Unit]
Description=Lightning Network Daemon on $CHAIN

# Make sure lnd starts after glcoind is ready
Requires=${netprefix}glcoind.service
After=${netprefix}glcoind.service
PartOf=${netprefix}glcoind.service

[Service]
EnvironmentFile=/mnt/hdd/app-data/raspiblesk.conf

ExecStartPre=-/home/admin/config.scripts/lnd.check.sh prestart ${CHAIN}
ExecStart=/usr/local/bin/lnd --configfile=/mnt/hdd/app-data/lnd/${netprefix}lnd.conf
# avoid hanging on stop
# ExecStop=/usr/local/bin/lncli -n=${CHAIN} --rpcserver localhost:1${rpcportmod}009 stop
PIDFile=/mnt/hdd/app-data/lnd/${netprefix}lnd.pid

User=glcoin
Group=glcoin

# Try to restart lnd always
Restart=always
RestartSec=60

# Type=notify is required for lnd to notify systemd when it is ready
Type=notify

# An extended timeout period is needed to allow for database compaction
# and other time intensive operations during startup. We also extend the
# stop timeout to ensure graceful shutdowns of lnd.
TimeoutStartSec=1200
TimeoutStopSec=3600

StandardOutput=null
StandardError=journal

# Hardening Measures
####################
# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full
# Disallow the process and all of its children to gain
# new privileges through execve().
NoNewPrivileges=true
# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true
# Deny the creation of writable and executable memory mappings.
MemoryDenyWriteExecute=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${netprefix}lnd.service
  sudo systemctl enable ${netprefix}lnd
  echo "# Enabled the ${netprefix}lnd.service"
  if [ "${state}" == "ready" ]; then
    sudo systemctl start ${netprefix}lnd
    echo "# Started the ${netprefix}lnd.service"
  fi

  echo
  echo "# Add aliases ${netprefix}lncli, ${netprefix}lndlog, ${netprefix}lndconf"
  sudo -u admin touch /home/admin/_aliases
  if [ $(grep -c "alias ${netprefix}lncli" < /home/admin/_aliases) -eq 0 ];then
    echo "\
alias ${netprefix}lncli=\"sudo -u glcoin /usr/local/bin/lncli\
 -n=${CHAIN} --rpcserver localhost:1${rpcportmod}009\"\
" | sudo tee -a /home/admin/_aliases
  fi
  if [ $(grep -c "alias ${netprefix}lndlog" < /home/admin/_aliases) -eq 0 ];then
    echo "\
alias ${netprefix}lndlog=\"sudo tail -n 30 -f /mnt/hdd/app-data/lnd/logs/${network}/${CHAIN}/lnd.log\"\
" | sudo tee -a /home/admin/_aliases
  fi
  if [ $(grep -c "alias ${netprefix}lndconf" < /home/admin/_aliases) -eq 0 ];then
    echo "\
alias ${netprefix}lndconf=\"sudo nano /mnt/hdd/app-data/lnd/${netprefix}lnd.conf\"\
" | sudo tee -a /home/admin/_aliases
  fi

  # if parameter "initwallet" was set and wallet does not exist yet
  walletExists=$(sudo ls /mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/wallet.db 2>/dev/null | grep -c "wallet.db")
  echo "# initwallet(${initwallet}) walletExists(${walletExists})"
  if [ "${initwallet}" == "1" ] && [ "${walletExists}" == "0" ]; then
      # only ask on mainnet for passwordC - for the testnet/signet its default 'raspiblesk'
      if [ "${CHAIN}" == "mainnet" ]; then
        tempFile="/var/cache/raspiblesk/passwordc.tmp"
        sudo /home/admin/config.scripts/blesk.passwords.sh set x "PASSWORD C - LND Wallet Password" ${tempFile}
        passwordC=$(sudo cat ${tempFile})
        sudo rm ${tempFile}
      else
        passwordC="raspiblesk"
      fi
      source <(sudo /home/admin/config.scripts/lnd.initwallet.py new ${CHAIN} ${passwordC})
      if [ "${err}" != "" ]; then
        clear
        echo "# LND ${CHAIN} wallet creation failed"
        echo "# ${err}"
        echo "# press ENTER to continue"
        read key
      else
        sudo mkdir -p /mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}
        seedFile="/mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/seedwords.info"
        echo "seedwords='${seedwords}'" | sudo tee ${seedFile}
        echo "seedwords6x4='${seedwords6x4}'" | sudo tee -a ${seedFile}
      fi
  fi

  if [ "${CHAIN}" != "mainnet" ]; then
    echo "# Setting autounlock for ${CHAIN}"
    source <(/home/admin/config.scripts/network.aliases.sh getvars lnd ${CHAIN})
    passwordFile="/mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/password.info"
    # create passwordfile
    if ! sudo ls ${passwordFile} &>/dev/null; then
      echo "raspiblesk" | sudo -u glcoin tee ${passwordFile} 1>/dev/null
    fi
    # add autounlock to lnd.conf
    if ! grep "^wallet-unlock-password-file=${passwordFile}" < ${lndConfFile}; then
      if grep "^\[Application Options\]" < ${lndConfFile} &>/dev/null; then
        # add under header
        sudo sed -i "/^\[Application Options\]$/awallet-unlock-password-file=${passwordFile}" ${lndConfFile}
      else
        # just append if no headers used
        echo "wallet-unlock-password-file=${passwordFile}" | sudo -u glcoin tee ${lndConfFile}
      fi
    fi
  fi

  echo
  echo "# The installed LND version is: $(sudo -u glcoin /usr/local/bin/lnd --version)"
  echo
  echo "# To activate the aliases reopen the terminal or use:"
  echo "source ~/_aliases"
  echo "# Monitor the ${netprefix}lnd with:"
  echo "sudo journalctl -fu ${netprefix}lnd"
  echo "sudo systemctl status ${netprefix}lnd"
  echo "# logs:"
  echo "sudo tail -f /mnt/hdd/app-data/lnd/logs/glcoin/${CHAIN}/lnd.log"
  echo "# for the command line options use"
  echo "${netprefix}lncli help"
  echo

  # setting value in raspi blitz config
  /home/admin/config.scripts/blesk.conf.sh set ${netprefix}lnd "on"

  # if this is the first lightning mainnet turned on - make default
  if [ "${CHAIN}" == "mainnet" ]; then
    if [ "${lightning}" == "" ] || [ "${lightning}" == "none" ]; then
      echo "# LND is now default lighthning implementation"
      /home/admin/config.scripts/blesk.conf.sh set lightning "lnd"
    fi
  fi

  # needed to make lnd.newwallet.py work
  pip config set global.break-system-packages true
  pip install --upgrade google-api-python-client

  exit 0
fi

if [ "$1" = "display-seed" ]; then

  # check if sudo
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (with sudo)"
    exit 1
  fi

  # get network and aliasses from second parameter (default mainnet)
  displayNetwork=$2
  if [ "${displayNetwork}" == "" ]; then
    displayNetwork="mainnet"
  fi

  deleteSeedInfoAfterDisplay=0
  if [ "$3" == "delete" ]; then
    echo "# deleting seedinfo after display"
    deleteSeedInfoAfterDisplay=1
  fi

  # check if seedword file exists
  seedwordFile="/mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/seedwords.info"
  echo "# seedwordFile(${seedwordFile})"
  seedwordFileExists=$(ls ${seedwordFile} 2>/dev/null | grep -c "seedwords.info")
  echo "# seedwordFileExists(${seedwordFileExists})"
  if [ "${seedwordFileExists}" == "1" ]; then
    source ${seedwordFile}
  fi
  if [ "${seedwords}" != "" ]; then
    #echo "# seedwords(${seedwords})"
    #echo "# seedwords6x4(${seedwords6x4})"
    ack=0
    while [ ${ack} -eq 0 ]
    do
      whiptail --title "LND ${displayNetwork} Wallet" \
        --msgbox "This is your LND ${displayNetwork} wallet seed. Store these numbered words in a safe location:\n\n${seedwords6x4}" 13 76
      whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
      if [ $? -eq 1 ]; then
        ack=1
      fi
    done
    if [ "${deleteSeedInfoAfterDisplay}" == "1" ]; then
      echo "# deleting seed info"
      sudo shred ${seedwordFile}
      sudo rm ${seedwordFile} 2>/dev/null
    fi
  else
    walletFile="/mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/wallet.db"
    whiptail --title "LND ${displayNetwork} Wallet Info" --msgbox "Your LND ${displayNetwork} wallet was already created before - there are no seed words available.\n\nTo secure your wallet secret you can manually backup the file: ${walletFile}" 11 76
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# removing ${CHAIN} lnd service (if active)"

  removeParallelService

  # setting value in raspiblesk config
  /home/admin/config.scripts/blesk.conf.sh set ${netprefix}lnd "off"
  echo "# ${netprefix}lnd --> off"

  # if lnd mainnet was default - remove
  if [ "${CHAIN}" == "mainnet" ] && [ "${lightning}" == "lnd" ]; then
    echo "# LND is REMOVED as default lightning implementation"
    /home/admin/config.scripts/blesk.conf.sh set lightning "none"
    if [ "${cl}" == "on" ]; then
      echo "# CL is now the new default lightning implementation"
      /home/admin/config.scripts/blesk.conf.sh set lightning "cl"
    fi
  fi

  # purge
  if echo "$@" | grep purge; then
    echo "# Stop on LND all networks and delete lnd binaries"
    /home/admin/config.scripts/lnd.install.sh off mainnet
    /home/admin/config.scripts/lnd.install.sh off testnet
    /home/admin/config.scripts/lnd.install.sh off signet
    sudo rm /usr/local/bin/lncli
    sudo rm /usr/local/bin/lnd
    echo "# Deleted the binaries"
  fi

  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1
