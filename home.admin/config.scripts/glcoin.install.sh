#!/bin/bash

# Glcoin Core - build & install from source tarball
# Source lookup order:
#   1. Explicit path passed as 2nd argument
#   2. Tarball at /tmp/glcoin-0.1.10-src.tar.gz  (copy here before running)
#   3. Already-extracted dir at /tmp/glcoin-src or /home/admin/glcoin-src
#   4. GitHub (once the repo is public)
GLCOIN_TARBALL_URL="https://github.com/glcoin/glcoin/releases/download/v0.1.10/glcoin-0.1.10-src.tar.gz"
GLCOIN_VERSION="0.1.10"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "glcoin.install.sh install [source_path_or_tarball]"
  echo "Install or remove parallel chains for Glcoin Core:"
  echo "glcoin.install.sh install"
  echo "glcoin.install.sh install /path/to/glcoin-0.1.10-src.tar.gz"
  echo "glcoin.install.sh install /path/to/extracted/glcoin-src"
  echo "glcoin.install.sh [on|off] [signet|testnet|mainnet]"
  echo
  exit 1
fi

echo "# Running: glcoin.install.sh $*"

# mainnet | testnet | signet
# When 'install' is used, $2 may be a source path rather than a chain name
if [ "$1" = "install" ] && ([ -f "${2}" ] || [ -d "${2}" ]); then
  CHAIN=${3:-mainnet}
else
  CHAIN=${2:-mainnet}
fi
if [ "${CHAIN}" != signet ] && [ "${CHAIN}" != testnet ] && [ "${CHAIN}" != mainnet ]; then
  echo "# ${CHAIN} is not supported"
  exit 1
fi
# prefixes for parallel services
if [ "${CHAIN}" = testnet ]; then
  prefix="t"
  glcoinprefix="test"
  rpcprefix=1
  glcoinZmqBlock=31617
  glcoinZmqTx=31618
elif [ ${CHAIN} = signet ]; then
  prefix="s"
  glcoinprefix="signet"
  rpcprefix=3
  glcoinZmqBlock=41617
  glcoinZmqTx=41618
elif [ ${CHAIN} = mainnet ]; then
  prefix=""
  glcoinprefix="main"
  rpcprefix=""
  glcoinZmqBlock=21617
  glcoinZmqTx=21618
fi

# glcoinlogpath
if [ ${CHAIN} = signet ]; then
  glcoinlogpath="/mnt/hdd/app-data/glcoin/signet/debug.log"
elif [ ${CHAIN} = testnet ]; then
  glcoinlogpath="/mnt/hdd/app-data/glcoin/testnet3/debug.log"
elif [ ${CHAIN} = mainnet ]; then
  glcoinlogpath="/mnt/hdd/app-data/glcoin/debug.log"
fi

function addGlcoinAliases {
  echo "# Add aliases ${prefix}glcoin-cli, ${prefix}glcoinlog"
  sudo -u admin touch /home/admin/_aliases
  if ! grep "alias ${prefix}glcoin-cli" /home/admin/_aliases; then
    echo "alias ${prefix}glcoin-cli=\"sudo -u glcoin /usr/local/bin/glcoin-cli -rpcport=${rpcprefix}1617\"" |
      sudo tee -a /home/admin/_aliases
  fi
  if ! grep "alias ${prefix}glcoinlog" /home/admin/_aliases; then
    echo "alias ${prefix}glcoinlog=\"sudo -u glcoin tail -n 30 -f ${glcoinlogpath}\"" |
      sudo tee -a /home/admin/_aliases
  fi
  if ! grep "alias glcoinconf" /home/admin/_aliases; then
    echo "alias glcoinconf=\"sudo nano /mnt/hdd/app-data/glcoin/glcoin.conf\"" |
      sudo tee -a /home/admin/_aliases
  fi
  sudo chown admin:admin /home/admin/_aliases
}

if [ "$1" = "install" ]; then
  echo "*** PREPARING GLCOIN ***"

  # resolve source: explicit arg > local tarball > extracted dir > download tarball
  LOCAL_SOURCE=""
  TARBALL_PATH=""

  if [ -n "${2}" ] && [ -f "${2}" ] && [[ "${2}" == *.tar.gz ]]; then
    TARBALL_PATH="${2}"
  elif [ -n "${2}" ] && [ -d "${2}" ]; then
    LOCAL_SOURCE="${2}"
  elif [ -f "/home/admin/assets/glcoin-0.1.10-src.tar.gz" ]; then
    TARBALL_PATH="/home/admin/assets/glcoin-0.1.10-src.tar.gz"
  elif [ -f "/tmp/glcoin-0.1.10-src.tar.gz" ]; then
    TARBALL_PATH="/tmp/glcoin-0.1.10-src.tar.gz"
  elif [ -d "/tmp/glcoin-src" ]; then
    LOCAL_SOURCE="/tmp/glcoin-src"
  elif [ -d "/home/admin/glcoin-src" ]; then
    LOCAL_SOURCE="/home/admin/glcoin-src"
  fi

  # install build dependencies
  echo "# Installing build dependencies ..."
  apt-get install -y -q \
    build-essential cmake pkg-config git \
    libboost-system-dev libboost-filesystem-dev libboost-thread-dev \
    libboost-test-dev libboost-chrono-dev \
    libevent-dev libssl-dev libzmq3-dev \
    libsqlite3-dev libdb-dev libdb++-dev \
    python3 python3-pip || exit 1

  BUILD_DIR="/home/admin/glcoin-build"
  SRC_DIR="/home/admin/glcoin-src"

  # extract tarball if provided
  if [ -n "${TARBALL_PATH}" ]; then
    echo "# Extracting source tarball: ${TARBALL_PATH}"
    rm -rf "${SRC_DIR}"
    mkdir -p "${SRC_DIR}"
    tar -xzf "${TARBALL_PATH}" -C "${SRC_DIR}" --strip-components=2 || exit 1
    LOCAL_SOURCE="${SRC_DIR}"
  fi

  # use local source if available
  if [ -n "${LOCAL_SOURCE}" ] && [ -d "${LOCAL_SOURCE}" ]; then
    echo "# Using local source: ${LOCAL_SOURCE}"
    SRC_DIR="${LOCAL_SOURCE}"
  elif [ -d "${SRC_DIR}" ]; then
    echo "# Using existing source in ${SRC_DIR}"
  else
    echo "# No local source found — downloading tarball from ${GLCOIN_TARBALL_URL} ..."
    wget -O /tmp/glcoin-src.tar.gz "${GLCOIN_TARBALL_URL}" || exit 1
    mkdir -p "${SRC_DIR}"
    tar -xzf /tmp/glcoin-src.tar.gz -C "${SRC_DIR}" --strip-components=2 || exit 1
  fi

  # build
  echo "# Building Glcoin Core ..."
  rm -rf "${BUILD_DIR}"
  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}" || exit 1

  cmake "${SRC_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_DAEMON=ON \
    -DBUILD_CLI=ON \
    -DBUILD_BITCOIN_BIN=OFF \
    -DBUILD_GUI=OFF \
    -DBUILD_TESTS=OFF \
    -DBUILD_TX=OFF \
    -DBUILD_UTIL=OFF \
    -DBUILD_BENCH=OFF \
    -DENABLE_IPC=OFF \
    -DBUILD_WALLET_TOOL=OFF \
    -DWITH_ZMQ=ON \
    -DENABLE_WALLET=ON \
    || exit 1

  cmake --build . --parallel "$(nproc)" || exit 1

  # install binaries
  echo "# Installing Glcoin binaries ..."
  sudo install -m 0755 -o root -g root -t /usr/local/bin/ "${BUILD_DIR}/bin/glcoind" || exit 1
  sudo install -m 0755 -o root -g root -t /usr/local/bin/ "${BUILD_DIR}/bin/glcoin-cli" || exit 1
  if [ -f "${BUILD_DIR}/bin/glcoin-tx" ]; then
    sudo install -m 0755 -o root -g root -t /usr/local/bin/ "${BUILD_DIR}/bin/glcoin-tx"
  fi
  if [ -f "${BUILD_DIR}/bin/glcoin-wallet" ]; then
    sudo install -m 0755 -o root -g root -t /usr/local/bin/ "${BUILD_DIR}/bin/glcoin-wallet"
  fi

  # install man pages if available
  if [ -d "${BUILD_DIR}/share/man/man1" ]; then
    sudo install -m 0644 -o root -g root -D -t /usr/local/share/man/man1 "${BUILD_DIR}/share/man/man1/"*.1
  fi

  # verify installation
  INSTALLED_VERSION=$(sudo /usr/local/bin/glcoind --version 2>/dev/null | head -1)
  if [ -z "${INSTALLED_VERSION}" ]; then
    echo
    echo "# BUILD FAILED --> glcoind could not be executed after install"
    exit 1
  fi
  echo
  echo "# Installed: ${INSTALLED_VERSION}"
  echo "**********************************"
  echo "OK --> GLCOIN CORE INSTALLED"
  echo "**********************************"
  echo

  addGlcoinAliases

  echo "- Glcoin install OK"
  exit 0
fi

function removeParallelService() {
  if [ -f "/etc/systemd/system/${prefix}glcoind.service" ]; then
    if [ ${CHAIN} != mainnet ]; then
      /usr/local/bin/glcoin-cli -${CHAIN} stop
    else
      /usr/local/bin/glcoin-cli stop
    fi
    sudo systemctl stop ${prefix}glcoind
    sudo systemctl disable ${prefix}glcoind
    sudo rm /etc/systemd/system/${prefix}glcoind.service 2>/dev/null
    if [ ${glcoinprefix} = signet ]; then
      if [ -f "/etc/systemd/system/signetd.service" ]; then
        sudo systemctl stop signetd
        sudo systemctl disable signetd
        echo "# The signetd.service is stopped and disabled"
      fi
    fi
    echo "# Glcoin Core on ${CHAIN} service is stopped and disabled"
  fi
}

function installParallelService() {
  echo "# Installing Glcoin Core instance on ${CHAIN}"

  sudo sed -i s/^rpcbind=/main.rpcbind=/g /mnt/hdd/app-data/glcoin/glcoin.conf
  if grep "rpcallowip" /mnt/hdd/app-data/glcoin/glcoin.conf; then
    if ! grep "${glcoinprefix}.rpcbind=" /mnt/hdd/app-data/glcoin/glcoin.conf; then
      echo "${glcoinprefix}.rpcbind=127.0.0.1" |
        sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
    fi
  fi

  sudo sed -i s/^rpcport=/main.rpcport=/g /mnt/hdd/app-data/glcoin/glcoin.conf
  if ! grep "${glcoinprefix}.rpcport" /mnt/hdd/app-data/glcoin/glcoin.conf; then
    echo "${glcoinprefix}.rpcport=${rpcprefix}1617" |
      sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
  fi

  sudo sed -i s/^zmqpubraw/main.zmqpubraw/g /mnt/hdd/app-data/glcoin/glcoin.conf
  if ! grep "${glcoinprefix}.zmqpubrawblock" /mnt/hdd/app-data/glcoin/glcoin.conf; then
    echo "\
${glcoinprefix}.zmqpubrawblock=tcp://127.0.0.1:${glcoinZmqBlock}
${glcoinprefix}.zmqpubrawtx=tcp://127.0.0.1:${glcoinZmqTx}" |
      sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
  fi

  if [ ${glcoinprefix} = signet ]; then
    if [ $(grep -c "signet.addnode" /mnt/hdd/app-data/glcoin/glcoin.conf) -eq 0 ]; then
      echo "signet.addnode=seed.glcoin.org:31618" |
        sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
    fi
  fi
  if [ ${glcoinprefix} = main ] || [ -z "${glcoinprefix}" ]; then
    if [ $(grep -c "main.addnode" /mnt/hdd/app-data/glcoin/glcoin.conf) -eq 0 ]; then
      echo "main.addnode=glcoin.org:1618" |
        sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
    fi
  fi

  removeParallelService

  chainparameter=""
  if [ "${CHAIN}" != "mainnet" ]; then
    chainparameter="-${CHAIN}"
  fi
  echo "
[Unit]
Description=Glcoin daemon on ${CHAIN}

Wants=redis.service
After=redis.service

[Service]
Environment='MALLOC_ARENA_MAX=1'
ExecStartPre=-/home/admin/config.scripts/glcoin.check.sh prestart ${CHAIN}
ExecStart=/usr/local/bin/glcoind ${chainparameter} \\
                                  -daemonwait \\
                                  -conf=/mnt/hdd/app-data/glcoin/glcoin.conf \\
                                  -datadir=/mnt/hdd/app-storage/glcoin
PermissionsStartOnly=true

# Process management
####################
Type=forking
Restart=on-failure
TimeoutStartSec=infinity
TimeoutStopSec=600

# Directory creation and permissions
####################################
# Run as glcoin:glcoin
User=glcoin
Group=glcoin

StandardOutput=null
StandardError=journal

# Hardening measures
####################
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true
PrivateDevices=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${prefix}glcoind.service
  sudo systemctl daemon-reload
  sudo systemctl enable ${prefix}glcoind
  echo "# OK - the glcoin daemon on ${CHAIN} service is now enabled"

  addGlcoinAliases

  source <(/home/admin/_cache.sh get state)

  if [ "${state}" == "ready" ]; then
    echo "# OK - the ${prefix}glcoind.service is enabled, system is ready so starting service"
    sudo systemctl start ${prefix}glcoind
  else
    echo "# OK - the ${prefix}glcoind service is enabled, to start manually use:"
    echo "sudo systemctl start ${prefix}glcoind"
  fi

  isInstalled=$(systemctl status ${prefix}glcoind | grep -c active)
  if [ $isInstalled -gt 0 ]; then
    echo "# Installed $(sudo -u glcoin glcoind --version | head -1)"
    echo
    echo "# Monitor the ${prefix}glcoind with:"
    echo "# sudo tail -f /mnt/hdd/app-storage/glcoin/${prefix}debug.log"
    echo
  else
    echo "# Installation failed"
    echo "# See:"
    echo "# sudo journalctl -fu ${prefix}glcoind"
    exit 1
  fi
}

source /mnt/hdd/app-data/raspiblesk.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # Create glcoin system user if it doesn't exist yet
  if ! id -u glcoin >/dev/null 2>&1; then
    echo "# Creating glcoin system user ..."
    sudo adduser --system --group --home /home/glcoin glcoin || exit 1
    echo "# glcoin user created"
  fi

  echo "# Glcoin datadir"
  source <(sudo /home/admin/config.scripts/blesk.data.sh status)
  mkdir -p ${storageMountedPath}/app-storage/glcoin
  echo "# Linking /glcoin"
  unlink /mnt/hdd/glcoin 2>/dev/null
  ln -s ${storageMountedPath}/app-storage/glcoin /mnt/hdd/glcoin
  chown -R glcoin:glcoin /mnt/hdd/glcoin
  chmod -R 777 /mnt/hdd/glcoin

  installParallelService
  /home/admin/config.scripts/blesk.conf.sh set ${CHAIN} "on"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# Uninstall Glcoin Core instance on ${CHAIN}"
  removeParallelService
  /home/admin/config.scripts/blesk.conf.sh set ${CHAIN} "off"
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1
