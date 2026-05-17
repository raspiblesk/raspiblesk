#!/bin/bash

# https://github.com/romanz/electrs/releases
ELECTRSVERSION="v0.10.10"
GLCOIN_RELEASE="v0.1.12"
GITHUB_RELEASE_BASE="https://github.com/raspiblesk/raspiblesk/releases/download/${GLCOIN_RELEASE}"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the Electrum Rust Server on or off"
  echo "bonus.electrs.sh status -> dont call in loops"
  echo "bonus.electrs.sh status-sync"
  echo "bonus.electrs.sh [on|off|menu|update]"
  echo "bonus.electrs.sh [install|uninstall]"
  echo "installs the version $ELECTRSVERSION"
  exit 1
fi

PGPsigner="romanz"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="87CAE5FA46917CBB"

# Pinned SHA-256 of bundled prebuilt electrs tarballs (Glcoin-patched).
# Recomputed at v0149 release; bump on rebuild.
SHA256_ELECTRS_PREBUILT_arm64="ae84c3fd66a39b93a805a0f0af0369537d22087d79ca84910b95dfe534a77540"
SHA256_ELECTRS_PREBUILT_amd64="874b7e587b5b8892c33868b48556853aa163424f107743e840365cb0fc55aa8d"

# Reject any prebuilt tarball whose hash does not match. Prevents a poisoned
# GitHub release / MITM'd asset from delivering a backdoored electrs that
# sits between LND and the chain.
verify_sha256_electrs() {
  local _file="$1"; local _arch="$2"
  local _expected=""
  case "${_arch}" in
    arm64) _expected="${SHA256_ELECTRS_PREBUILT_arm64}" ;;
    amd64) _expected="${SHA256_ELECTRS_PREBUILT_amd64}" ;;
  esac
  if [ -z "${_expected}" ]; then
    echo "# WARN - no SHA-256 pinned for electrs ${_arch}; rejecting prebuilt."
    rm -f "${_file}"
    return 1
  fi
  if [ ! -f "${_file}" ]; then return 1; fi
  local _actual
  _actual="$(sha256sum "${_file}" 2>/dev/null | awk '{print $1}')"
  if [ "${_actual}" != "${_expected}" ]; then
    echo "# FAIL - SHA-256 mismatch for electrs prebuilt (${_arch})"
    echo "#   expected: ${_expected}"
    echo "#   got:      ${_actual}"
    rm -f "${_file}"
    return 1
  fi
  echo "# OK - electrs prebuilt sha256 verified (${_expected:0:16}…)"
  return 0
}

source /mnt/hdd/app-data/raspiblesk.conf 2>/dev/null

# give status (dont call regularly - just on occasions)
if [ "$1" = "status" ]; then

  # get local and global internet info
  source <(/home/admin/config.scripts/internet.sh status global)

  echo "##### STATUS ELECTRS SERVICE"

  echo "version='${ELECTRSVERSION}'"

  fatpack=$(compgen -u | grep -c electrs)
  echo "fatpack=${fatpack}"

  if [ "${ElectRS}" = "on" ]; then
    echo "configured=1"
    echo "installed=1"
  else
    echo "configured=0"
    echo "installed=0"
    echo "infoSync='Service not installed'"
  fi

  #if id "electrs" &>/dev/null; then
  #  echo "installed=1"
  #else
  #  echo "installed=0"
  #fi

  serviceInstalled=$(sudo systemctl status electrs --no-page 2>/dev/null | grep -c "electrs.service - Electrs")
  serviceRunning=$(sudo systemctl status electrs --no-page 2>/dev/null | grep -c "active (running)")
  echo "serviceRunning=${serviceRunning}"
  if [ ${serviceRunning} -eq 1 ]; then

    # check local IPv4 port
    echo "localIP='${localip}'"
    echo "publicIP='${cleanip}'"
    echo "portTCP='50001'"
    localPortRunning=$(sudo netstat -an | grep -c '0.0.0.0:50001')
    echo "localTCPPortActive=${localPortRunning}"

    publicPortRunning=$(
      nc -z -w6 ${publicip} 50001 2>/dev/null
      echo $?
    )
    if [ "${publicPortRunning}" == "0" ]; then
      # OK looks good - but just means that something is answering on that port
      echo "publicTCPPortAnswering=1"
    else
      # no answer on that port
      echo "publicTCPPortAnswering=0"
    fi
    echo "portSSL='50002'"
    localPortRunning=$(sudo netstat -an | grep -c '0.0.0.0:50002')
    echo "localHTTPPortActive=${localPortRunning}"
    publicPortRunning=$(
      nc -z -w6 ${publicip} 50002 2>/dev/null
      echo $?
    )
    if [ "${publicPortRunning}" == "0" ]; then
      # OK looks good - but just means that something is answering on that port
      echo "publicHTTPPortAnswering=1"
    else
      # no answer on that port
      echo "publicHTTPPortAnswering=0"
    fi
    # add Tor info
    if [ "${runBehindTor}" == "on" ]; then
      echo "TorRunning=1"
      if [ "$2" = "showAddress" ]; then
        TORaddress=$(sudo cat /mnt/hdd/app-data/tor/electrs/hostname)
        echo "TORaddress='${TORaddress}'"
      fi
    else
      echo "TorRunning=0"
    fi
    # check Nginx
    nginxTest=$(sudo nginx -t 2>&1 | grep -c "test is successful")
    echo "nginxTest=$nginxTest"
  fi

  exit 0
fi

# give sync-status (can be called regularly)
if [ "$1" = "status-sync" ]; then

  serviceRunning=$(sudo systemctl status electrs --no-page 2>/dev/null | grep -c "active (running)")
  echo "serviceRunning=${serviceRunning}"
  if [ ${serviceRunning} -eq 1 ]; then

    # check if initial sync was done, by setting a file as once electrs is the first time responding on port 50001
    electrumResponding=$(echo '{"jsonrpc":"2.0","method":"server.ping","params":[],"id":"electrs-check"}' | netcat -w 2 127.0.0.1 50001 | grep -c "result")
    if [ ${electrumResponding} -gt 1 ]; then
      electrumResponding=1
    fi
    echo "electrumResponding=${electrumResponding}"

    blockheight=0
    blockheightPercent=0
    if [ ${electrumResponding} -eq 0 ]; then

      # get the synced blockheight
      syncedBlock=$(echo '{"id": 1, "method": "blockchain.headers.subscribe", "params": []}' | nc -w 20 -q 1 localhost 50001 | jq '.result.height')
      if [ "$syncedBlock" -eq "$syncedBlock" ] 2>/dev/null; then
        blockheight=${syncedBlock}

        # calculate the progress
        source <(/home/admin/_cache.sh get glc_mainnet_blocks_verified)
        if [ "$glc_mainnet_blocks_verified" -eq "$glc_mainnet_blocks_verified" ] 2>/dev/null; then
          blockheightPercent=$(echo "scale=2; $syncedBlock / $glc_mainnet_blocks_verified * 100" | bc)
          blockheightPercent=$(printf "%.0f\n" $blockheightPercent)
        fi

      fi
    fi
    echo "blockheight='${blockheight}'"
    echo "blockheightPercent='${blockheightPercent}'"

    fileFlagExists=$(sudo ls /mnt/hdd/app-storage/electrs/initial-sync.done 2>/dev/null | grep -c 'initial-sync.done')
    if [ ${fileFlagExists} -eq 0 ] && [ ${electrumResponding} -gt 0 ]; then
      # set file flag for the future
      sudo touch /mnt/hdd/app-storage/electrs/initial-sync.done
      sudo chmod 544 /mnt/hdd/app-storage/electrs/initial-sync.done
      fileFlagExists=1
    fi
    if [ ${fileFlagExists} -eq 0 ]; then
      echo "initialSynced=0"
      if [ "${blockheightPercent}" != "0" ]; then
        echo "infoSync='Building Index ${blockheightPercent}% (please wait)'"
      else
        echo "infoSync='Building Index (please wait)'"
      fi
    else
      echo "initialSynced=1"
    fi

  else
    # echo "tipSynced=0"
    echo "initialSynced=0"
    echo "electrumResponding=0"
    echo "infoSync='Not running - check: sudo journalctl -u electrs'"
  fi
  exit 0
fi

if [ "$1" = "menu" ]; then

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.electrs.sh status showAddress)

  if [ ${configured} -eq 0 ]; then
    echo "# FAIL not installed"
    exit 0
  fi

  if [ ${serviceRunning} -eq 0 ]; then
    dialog --title "Electrum Service Not Running" --msgbox "
The electrum system service is not running.
Please check the following debug info.
      " 8 48
    /home/admin/config.scripts/blesk.debug.sh
    echo "Press ENTER to get back to main menu."
    read key
    exit 0
  fi

  if [ ${initialSynced} -eq 0 ]; then
    dialog --title "Electrum Index Not Ready" --msgbox "
Electrum server is still building its index.
Please wait and try again later.
This can take multiple hours.
      " 9 48
    exit 0
  fi

  if [ ${nginxTest} -eq 0 ]; then
    dialog --title "Testing nginx.conf has failed" --msgbox "
Nginx is in a failed state. Will attempt to fix.
Try connecting via port 50002 or Tor again once finished.
Check 'sudo nginx -t' for a detailed error message.
      " 9 61
    logFileMissing=$(sudo nginx -t 2>&1 | grep -c "/var/log/nginx/access.log")
    if [ ${logFileMissing} -eq 1 ]; then
      sudo mkdir /var/log/nginx
      sudo systemctl restart nginx
    fi
    /home/admin/config.scripts/blesk.web.sh
    echo "Press ENTER to get back to main menu."
    read key
    exit 0
  fi

  # Options (available without TOR)
  OPTIONS=(
    CONNECT "How to Connect"
    REINDEX "Delete&Rebuild Index"
    STATUS "ElectRS Status Info"
  )

  CHOICE=$(whiptail --clear --title "Electrum Rust Server" --menu "menu" 10 50 4 "${OPTIONS[@]}" 2>&1 >/dev/tty)
  clear

  case $CHOICE in
  CONNECT)
    echo "######## How to Connect to Electrum Rust Server #######"
    echo
    echo "Install the Electrum Wallet App on your laptop from:"
    echo "https://electrum.org"
    echo
    echo "On Network Settings > Server menu:"
    echo "- deactivate automatic server selection"
    echo "- as manual server set '${localIP}':'${portTCP}':t"
    echo "- laptop and RaspiBlesk need to be within same local network"
    echo
    echo "To start directly from laptop terminal use"
    echo "PC: electrum --oneserver --server ${localIP}:${portTCP}:t"
    echo "MAC: open -a /Applications/Electrum.app --args --oneserver --server ${localIP}:${portTCP}:t"
    if [ ${TorRunning} -eq 1 ]; then
      echo
      echo "The Tor Hidden Service address for electrs is (see LCD for QR code):"
      echo "${TORaddress}"
      echo
      echo "To connect through TOR open the Tor Browser and start with the options:"
      echo "electrum --oneserver --server ${TORaddress}:50001:t --proxy socks5:127.0.0.1:9150"
      sudo /home/admin/config.scripts/blesk.display.sh qr "${TORaddress}"
    fi
    echo
    echo "If you want to use SSL encrypted connections use in examples above"
    echo "'${localIP}':'${portSSL}':s' instead of '${localIP}':'${portTCP}':t"
    echo
    echo "For more details check the RaspiBlesk README on ElectRS:"
    echo "https://github.com/rootzoll/raspiblesk"
    echo
    echo "Press ENTER to get back to main menu."
    read key
    sudo /home/admin/config.scripts/blesk.display.sh hide
    ;;
  STATUS)
    sudo /home/admin/config.scripts/bonus.electrs.sh status
    echo
    echo "Press ENTER to get back to main menu."
    read key
    ;;
  REINDEX)
    echo "######## Delete/Rebuild Index ########"
    echo "# stopping service"
    sudo systemctl stop electrs
    echo "# deleting index"
    sudo rm -r /mnt/hdd/app-storage/electrs/db
    sudo rm /mnt/hdd/app-storage/electrs/initial-sync.done 2>/dev/null
    echo "# starting service"
    sudo systemctl start electrs
    echo "# ok"
    echo
    echo "Press ENTER to get back to main menu."
    read key
    ;;
  esac

  exit 0
fi

# stop service
echo "# Making sure services are not running"
sudo systemctl stop electrs 2>/dev/null

# install
if [ "$1" = "install" ]; then
  echo "# INSTALL ELECTRS"

  if id "electrs" &>/dev/null; then
    echo "# user electrs exists already (codebase is installed)"
  else
    echo "# Installing codebase"

    echo
    echo "# Creating the electrs user"
    echo
    sudo adduser --system --group --home /home/electrs electrs
    cd /home/electrs

    # Detect arch for pre-built tarball lookup
    if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
      electrsArch="armv7"
    elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
      electrsArch="arm64"
    else
      electrsArch="amd64"
    fi

    # OPTION 1: pre-built Glcoin-patched electrs binary tarball
    # Place electrs-glcoin-${ELECTRSVERSION}-linux-${arch}.tar.gz in /tmp before running.
    # Format: contains a single 'electrs' binary at the top level.
    PREBUILT_TARBALL="/tmp/electrs-glcoin-${ELECTRSVERSION}-linux-${electrsArch}.tar.gz"
    if [ ! -f "${PREBUILT_TARBALL}" ]; then
      echo "# Attempting GitHub Release download: ${GITHUB_RELEASE_BASE}/$(basename "${PREBUILT_TARBALL}")"
      wget -q --show-progress --timeout=120 \
        -O "${PREBUILT_TARBALL}" \
        "${GITHUB_RELEASE_BASE}/$(basename "${PREBUILT_TARBALL}")" || rm -f "${PREBUILT_TARBALL}"
    fi
    # Refuse the prebuilt unless its SHA-256 matches a pinned value for our
    # arch; otherwise fall through to a verified source build (PGP-checked
    # via blesk.git-verify.sh below).
    _prebuilt_ok=0
    if [ -f "${PREBUILT_TARBALL}" ]; then
      if verify_sha256_electrs "${PREBUILT_TARBALL}" "${electrsArch}"; then
        _prebuilt_ok=1
      fi
    fi
    if [ "${_prebuilt_ok}" -eq 1 ]; then
      echo "# Installing pre-built Glcoin electrs tarball: ${PREBUILT_TARBALL}"
      mkdir -p /home/electrs/electrs/target/release
      tar -xzf "${PREBUILT_TARBALL}" -C /home/electrs/electrs/target/release || { echo "# FAIL - could not extract tarball"; exit 1; }
      sudo chown -R electrs:electrs /home/electrs/electrs
      chmod +x /home/electrs/electrs/target/release/electrs
      echo "# Installed from pre-built tarball"
    else
      # OPTION 2: build from source (romanz/electrs fork with network_glcoin.patch applied)
      # This takes ~30-40 minutes and requires Rust + clang.
      echo "# No pre-built tarball found at ${PREBUILT_TARBALL}"
      echo "# Building patched electrs from source (this will take ~40 minutes)"

      sudo -u electrs curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u electrs sh -s -- --default-toolchain stable -y
      sudo apt-get install -y clang cmake build-essential

      sudo -u electrs git clone https://github.com/romanz/electrs
      cd /home/electrs/electrs || exit 1
      sudo -u electrs git reset --hard $ELECTRSVERSION

      # verify
      sudo -u electrs /home/admin/config.scripts/blesk.git-verify.sh \
        "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "${ELECTRSVERSION}" || exit 1

      # apply Glcoin network name patch (mandatory — vanilla electrs rejects
      # --network=glcoin and the systemd unit passes that flag at startup).
      GLCOIN_PATCH="/home/admin/patches/electrs/network_glcoin.patch"
      if [ ! -f "${GLCOIN_PATCH}" ]; then
        echo "# FAIL - Glcoin electrs patch not found at ${GLCOIN_PATCH}"
        echo "# Build aborted: a vanilla electrs would crash-loop at startup."
        exit 1
      fi
      sudo -u electrs patch -p1 < "${GLCOIN_PATCH}" || { echo "# FAIL - could not apply Glcoin patch"; exit 1; }
      # Verify the patch took effect (defensive: a corrupted .patch could
      # silently no-op leaving config.rs vanilla).
      if ! grep -q '"glcoin" => Ok(BitcoinNetwork' /home/electrs/electrs/src/config.rs; then
        echo "# FAIL - patch applied but glcoin literal missing in src/config.rs"
        exit 1
      fi

      sudo -u electrs /home/electrs/.cargo/bin/cargo build --locked --release || exit 1
    fi
  fi
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# ACTIVATING ELECTRS"

  isInstalled=$(sudo ls /etc/systemd/system/electrs.service 2>/dev/null | grep -c 'electrs.service')
  if [ ${isInstalled} -eq 0 ]; then

    # cleanup
    sudo rm -f /home/electrs/.electrs/config.toml

    if id "electrs" &>/dev/null; then
      echo "# user electrs exists already (codebase is installed)"
    else
      echo "# Installing codebase"
      /home/admin/config.scripts/bonus.electrs.sh install
      if [ $? -ne 0 ]; then
        echo "Install failed .. removing again."
        /home/admin/config.scripts/bonus.electrs.sh uninstall
        exit 1
      fi
    fi

    # check and create storage dir
    if ! sudo ls /mnt/hdd/app-storage/electrs 2>/dev/null; then
      sudo mkdir /mnt/hdd/app-storage/electrs
      echo
      echo "# The electrs database will be built in /mnt/hdd/app-storage/electrs/db. Glcoin chain is young — initial sync takes seconds and the index grows ~80 MB/year at the current 5-min block target."
      echo
    fi

    # Reset stale DB on reinstall: when re-flashing across versions where
    # electrs ABI changed (e.g. magic-byte handling in v0164's
    # network_glcoin.patch hunk #3), the previous DB at .../db/bitcoin/ may
    # contain headers with the wrong magic and cause "receiving on empty and
    # disconnected channel" on first start. /mnt/hdd/app-storage/ is
    # persistent across re-flashes (see project_raspiblesk_v0159), so the
    # install script must do this cleanup itself; we cannot rely on a fresh
    # SD card alone. Cheap: a few-MB delete on a re-install, seconds to re-sync.
    # Guarded by a marker so we only wipe ONCE per install run, not on every
    # "switch on" toggle.
    if [ ! -f /mnt/hdd/app-storage/electrs/.v0164-reset.done ]; then
      echo "# v0164 first-install: wiping any stale electrs index (magic-byte format change)"
      sudo rm -rf /mnt/hdd/app-storage/electrs/db
      sudo rm -f /mnt/hdd/app-storage/electrs/initial-sync.done
      sudo touch /mnt/hdd/app-storage/electrs/.v0164-reset.done
    fi
    # Bug H2 (v0.15.16): v0164/v0165 seeded the chain with Bitcoin's hardcoded
    # genesis (bitcoin::constants::genesis_block(Network::Bitcoin) =
    # 000...ce26f). Glcoin's mainnet genesis is 6e605c9c...e9ed, so electrs
    # rejected block 1 with "missing prev_blockhash: 6e605c9c..." in a
    # restart loop. Fixed by --genesis-header-hex on the ExecStart line
    # (see network_glcoin.patch + bonus.electrs.sh ExecStart). The old DB
    # was built against the wrong seed and must be wiped exactly once.
    if [ ! -f /mnt/hdd/app-storage/electrs/.v0166-genesis-reset.done ]; then
      echo "# v0166 install: wiping electrs index built with wrong (Bitcoin) genesis seed"
      sudo rm -rf /mnt/hdd/app-storage/electrs/db
      sudo rm -f /mnt/hdd/app-storage/electrs/initial-sync.done
      sudo touch /mnt/hdd/app-storage/electrs/.v0166-genesis-reset.done
    fi

    # always fix user id
    sudo chown -R electrs:electrs /mnt/hdd/app-storage/electrs

    echo
    echo "# Getting RPC credentials from the glcoin.conf"
    # read PASSWORD_B
    RPC_USER=$(sudo cat /mnt/hdd/app-data/glcoin/glcoin.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/app-data/glcoin/glcoin.conf | grep rpcpassword | cut -c 13-)
    echo "# Done"

    echo
    echo "# Generating electrs.toml setting file with the RPC passwords"
    echo
    # generate setting file: https://github.com/romanz/electrs/issues/170#issuecomment-530080134
    # https://github.com/romanz/electrs/blob/master/doc/usage.md#configuration-files-and-environment-variables
    sudo -u electrs mkdir /home/electrs/.electrs 2>/dev/null
    echo "\
log_filters = \"WARN\"
jsonrpc_import = true
index-batch-size = 10
wait_duration_secs = 10
jsonrpc_timeout_secs = 15
db_dir = \"/mnt/hdd/app-storage/electrs/db\"
daemon_p2p_addr = \"127.0.0.1:1618\"
daemon_rpc_addr = \"127.0.0.1:1617\"
auth = \"${RPC_USER}:${PASSWORD_B}\"
# network is passed via --network=glcoin in the systemd ExecStart, NOT here.
# configure_me reads CLI args through FromStr (our network_glcoin.patch covers
# that path) but reads TOML values through serde::Deserialize (which derives
# directly on bitcoin::Network and rejects \"glcoin\" as unknown variant).
# Moving it to CLI keeps the Glcoin masquerade working without a much
# more invasive serde-deserializer patch.
# allow GLC-RPC-explorer show tx-s for addresses with a history of more than 100
txid_limit = 1000
server_banner = \"Welcome to electrs $ELECTRSVERSION - the Electrum Rust Server on your RaspiBlesk\"
" | sudo tee /home/electrs/.electrs/config.toml
    sudo chmod 600 /home/electrs/.electrs/config.toml
    sudo chown electrs:electrs /home/electrs/.electrs/config.toml

    echo
    echo "# Checking for config.toml"
    echo
    if [ ! -f "/home/electrs/.electrs/config.toml" ]; then
      echo "Failed to create config.toml"
      exit 1
    else
      echo "OK"
    fi

    echo
    echo "# Setting up the nginx.conf"
    echo
    isElectrs=$(sudo cat /etc/nginx/nginx.conf 2>/dev/null | grep -c 'upstream electrs')
    if [ ${isElectrs} -gt 0 ]; then
      echo "electrs is already configured with Nginx. To edit manually run \`sudo nano /etc/nginx/nginx.conf\`"

    elif [ ${isElectrs} -eq 0 ]; then

      isStream=$(sudo cat /etc/nginx/nginx.conf 2>/dev/null | grep -c 'stream {')
      if [ ${isStream} -eq 0 ]; then

        echo "
stream {
        upstream electrs {
                server 127.0.0.1:50001;
        }
        server {
                listen 50002 ssl;
                proxy_pass electrs;
                ssl_certificate /mnt/hdd/app-data/nginx/tls.cert;
                ssl_certificate_key /mnt/hdd/app-data/nginx/tls.key;
                ssl_session_cache shared:SSL-electrs:1m;
                ssl_session_timeout 4h;
                ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
                ssl_prefer_server_ciphers on;
        }
}" | sudo tee -a /etc/nginx/nginx.conf

      elif [ ${isStream} -eq 1 ]; then
        sudo truncate -s-2 /etc/nginx/nginx.conf
        echo "
        upstream electrs {
                server 127.0.0.1:50001;
        }
        server {
                listen 50002 ssl;
                proxy_pass electrs;
                ssl_certificate /mnt/hdd/app-data/nginx/tls.cert;
                ssl_certificate_key /mnt/hdd/app-data/nginx/tls.key;
                ssl_session_cache shared:SSL-electrs:1m;
                ssl_session_timeout 4h;
                ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
                ssl_prefer_server_ciphers on;
        }
}" | sudo tee -a /etc/nginx/nginx.conf

      elif [ ${isStream} -gt 1 ]; then
        echo " Too many \`stream\` commands in nginx.conf. Please edit manually: \`sudo nano /etc/nginx/nginx.conf\` and retry"
        exit 1
      fi
    fi

    echo
    echo "# Open ports 50001 and 5002 on UFW "
    echo
    sudo ufw allow 50001 comment 'electrs TCP'
    sudo ufw allow 50002 comment 'electrs SSL'

    echo
    echo "# Installing the systemd service"
    echo
    # sudo nano /etc/systemd/system/electrs.service
    echo "
[Unit]
Description=Electrs
After=glcoind.service

[Service]
WorkingDirectory=/home/electrs/electrs
# --network=glcoin uses the FromStr code path (patched in network_glcoin.patch
# to map glcoin -> Network::Bitcoin internally). TOML's serde path is not
# patched, so passing this here instead of in config.toml is mandatory.
# --signet-magic=f9b4b4d9 is the Glcoin mainnet pchMessageStart (chainparams.cpp
# CMainParams). The network_glcoin.patch extends config.rs to accept this
# override on Network::Bitcoin (not just Signet), since the bitcoin crate
# hardcodes Network::Bitcoin::magic() to Bitcoin's 0xf9beb4d9. Without this
# the P2P handshake to glcoind fails and the block-fetcher channel dies
# with \"receiving on empty and disconnected channel\".
ExecStart=/home/electrs/electrs/target/release/electrs --network=glcoin --signet-magic=f9b4b4d9 --genesis-header-hex=010000000000000000000000000000000000000000000000000000000000000000000000820ebef339d91314b3a647b544ad77209dcca4aaf093333b6b970506e6d14d7f00f3fe67ffff7f2003000000 --electrum-rpc-addr=\"0.0.0.0:50001\"
User=electrs
Group=electrs
Type=simple
TimeoutSec=60
Restart=always
RestartSec=60
# Stop after 10 failures in 10 min so a broken config can't crash-loop forever
# and flood the journal (v0.15.11: 82 restarts in 82 min before this guard).
StartLimitInterval=600
StartLimitBurst=10

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
    " | sudo tee -a /etc/systemd/system/electrs.service
    sudo systemctl enable electrs
    # manual start:
    # sudo -u electrs /home/electrs/.cargo/bin/cargo run --release -- --index-batch-size=10 --electrum-rpc-addr="0.0.0.0:50001"
  else
    echo "# ElectRS is already installed."
  fi

  # setting value in raspiblesk config
  /home/admin/config.scripts/blesk.conf.sh set ElectRS "on"

  # Hidden Service for electrs if Tor active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    /home/admin/config.scripts/tor.onion-service.sh electrs 50002 50002 50001 50001
  fi

  # determine glcoin.conf network prefix based on chain
  if [ "${chain}" = "main" ]; then
    btcprefix="main"
  elif [ "${chain}" = "test" ]; then
    btcprefix="test"
  elif [ "${chain}" = "sig" ]; then
    btcprefix="signet"
  else
    btcprefix="main"
  fi

 # whitelist electrs's local connection in glcoind
  # IMPORTANT: do NOT use whitebind=...:1619 — Bitcoin Core auto-binds an onion
  # service target on nDefaultPort+1 (= 1619 for glcoin mainnet, since
  # nDefaultPort=1618), which produces:
  #   [error] Duplicate binding configuration for address 127.0.0.1:1619
  # whether or not Tor is on. Use whitelist= instead — that grants the
  # download permission to any peer connecting from 127.0.0.1 over the regular
  # p2p port (1618) without requiring a separate bind port.
  # Clean up any stale whitebind entries from older installs (any prefix, any port)
  sudo sed -i '/^\(main\.\|test\.\|signet\.\|\)whitebind=.*download@127\.0\.0\.1:/d' /mnt/hdd/app-data/glcoin/glcoin.conf
  # add whitelist (network-prefixed for the current chain)
  if ! sudo grep -Eq "^${btcprefix}\.whitelist=download@127\.0\.0\.1\$" /mnt/hdd/app-data/glcoin/glcoin.conf; then
    echo "${btcprefix}.whitelist=download@127.0.0.1" | sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
    glcoindRestart=yes
  fi

  # clean up
  sudo rm -R /home/electrs/.cargo
  sudo rm -R /home/electrs/.rustup

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    if [ "${glcoindRestart}" == "yes" ]; then
      sudo systemctl restart glcoind
    fi
    sudo systemctl restart nginx
    sudo systemctl start electrs
    # restart GLC-RPC-Explorer to reconfigure itself to use electrs for address API
    if [ "${GLCRPCexplorer}" == "on" ]; then
      sudo systemctl restart glc-rpc-explorer
      echo "# GLC-RPC-Explorer restarted"
    fi
  fi

  echo
  echo "# To connect through SSL from outside of the local network make sure the port 50002 is forwarded on the router"
  echo

  exit 0
fi

# uninstall
if [ "$1" = "uninstall" ]; then
  echo "# UNINSTALL ELECTRS"

  if [ "${ElectRS}" = "on" ]; then
    echo "# FAIL: First switch ElectRS off before uninstalling."
    exit 1
  fi

  echo "# remove user and home directory"
  sudo userdel -rf electrs
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# DEACTIVATING ELECTRS"

  # if second parameter is "deleteindex"
  if [ "$2" == "deleteindex" ]; then
    echo "# deleting electrum index"
    sudo rm -rf /mnt/hdd/app-storage/electrs/
  fi

  isInstalled=$(sudo ls /etc/systemd/system/electrs.service 2>/dev/null | grep -c 'electrs.service')
  if [ ${isInstalled} -eq 1 ]; then
    sudo systemctl disable electrs
    sudo rm /etc/systemd/system/electrs.service

    # restart GLC-RPC-Explorer to reconfigure itself to use electrs for address API
    if [ "${GLCRPCexplorer}" == "on" ]; then
      sudo systemctl restart glc-rpc-explorer
      echo "# GLC-RPC-Explorer restarted"
    fi

  else
    echo "# electrs.service is not installed."
  fi

  # remove whitelist + any legacy whitebind entries from glcoin.conf so glcoind
  # restarts cleanly after the next config change
  if [ -f /mnt/hdd/app-data/glcoin/glcoin.conf ]; then
    sudo sed -i '/^\(main\.\|test\.\|signet\.\|\)whitelist=download@127\.0\.0\.1/d' /mnt/hdd/app-data/glcoin/glcoin.conf
    sudo sed -i '/^\(main\.\|test\.\|signet\.\|\)whitebind=.*download@127\.0\.0\.1:/d' /mnt/hdd/app-data/glcoin/glcoin.conf
    sudo systemctl restart glcoind 2>/dev/null
  fi

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off electrs
  fi

  # close ports on firewall
  sudo ufw delete allow 50001
  sudo ufw delete allow 50002

  # setting value in raspiblesk config
  /home/admin/config.scripts/blesk.conf.sh set ElectRS "off"

  echo "# OK ElectRS off."
  exit 0
fi

if [ "$1" = "update" ]; then
  echo "# Update Electrs"
  cd /home/electrs/electrs || exit 1
  sudo -u electrs git fetch

  localVersion=$(/home/electrs/electrs/target/release/electrs --version)
  updateVersion=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s https://api.github.com/repos/romanz/electrs/releases/latest | grep tag_name | head -1 | cut -d '"' -f4)

  if [ $localVersion = $updateVersion ]; then
    echo "# Up-to-date on version $localVersion"
  else
    echo "# Pulling latest changes..."
    sudo -u electrs git pull -p
    echo "# Reset to the latest release tag: $updateVersion"
    sudo -u electrs git reset --hard $updateVersion

    sudo -u electrs /home/admin/config.scripts/blesk.git-verify.sh \
      "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "${updateVersion}" || exit 1

    # re-apply Glcoin network name patch after git reset
    GLCOIN_PATCH="/home/admin/patches/electrs/network_glcoin.patch"
    if [ -f "${GLCOIN_PATCH}" ]; then
      sudo -u electrs patch -p1 < "${GLCOIN_PATCH}" || { echo "# FAIL - could not apply Glcoin patch"; exit 1; }
    fi

    echo "# Installing build dependencies"
    sudo -u electrs curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u electrs sh -s -- --default-toolchain stable -y
    sudo apt-get install -y clang cmake build-essential # for building 'rust-rocksdb'
    echo

    echo "# Build Electrs ..."
    sudo -u electrs /home/electrs/.cargo/bin/cargo build --locked --release || exit 1

    # update config
    sudo -u electrs sed -i "/^server_banner = /d" /home/electrs/.electrs/config.toml
    sudo -u electrs bash -c "echo 'server_banner = \"Welcome to electrs $updateVersion - the Electrum Rust Server on your RaspiBlesk\"' >> /home/electrs/.electrs/config.toml"
    # remove the deprecated timestamp entry
    sudo -u electrs sed -i '/^timestamp = true/d' /home/electrs/.electrs/config.toml

    echo "# Updated Electrs to $updateVersion"
  fi
  sudo systemctl start electrs
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
