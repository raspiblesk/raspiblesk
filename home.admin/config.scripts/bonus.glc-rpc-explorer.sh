#!/bin/bash

# https://github.com/janoside/glc-rpc-explorer
# ~/.config/glc-rpc-explorer.env
# https://github.com/janoside/glc-rpc-explorer/blob/master/.env-sample

# use commit hash, so that also in between updates can be used if needed
GITHUBCOMMIT="8ed77ab225f5507c521b570d5240624de597ad44" #3.5.1

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# small config script to switch GLC-RPC-explorer on or off"
 echo "# bonus.glc-rpc-explorer.sh [install|uninstall]"
 echo "# bonus.glc-rpc-explorer.sh [status|on|off]"
 echo "# bonus.glc-rpc-explorer.sh prestart"
 exit 1
fi

PGPsigner="janoside"
PGPpubkeyLink="https://github.com/janoside.gpg"
PGPpubkeyFingerprint="F579929B39B119CC7B0BB71FB326ACF51F317B69"

source /mnt/hdd/app-data/raspiblesk.conf 2>/dev/null

##########################
# MENU
#########################

# show info menu
if [ "$1" = "menu" ]; then

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.glc-rpc-explorer.sh status)

  # check if index is ready
  if [ "${isIndexed}" == "0" ]; then
    dialog --title " Blockchain Index Not Ready " --msgbox "
The Blockchain Index is still getting built.
${indexInfo}
This can take multiple hours.
      " 9 48
    exit 0
  fi

  # check if password protected
  isGlcoinWalletOff=$(sudo cat /mnt/hdd/app-data/${network}/${network}.conf | grep -c "^disablewallet=1")
  passwordInfo=""
  if [ "${isGlcoinWalletOff}" != "1" ]; then
    passwordInfo="Login is 'admin' with your Password B"
  fi

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # TOR
    sudo /home/admin/config.scripts/blesk.display.sh qr "${toraddress}"
    whiptail --title " GLC-RPC-Explorer " --msgbox "Open in your local web browser:
http://${localIP}:3020\n
https://${localIP}:3021 with Fingerprint:
${fingerprint}\n
${passwordInfo}\n
Hidden Service address for TOR Browser (QR see LCD):
${toraddress}
" 16 67
    sudo /home/admin/config.scripts/blesk.display.sh hide
  else

    # IP + Domain
    whiptail --title " GLC-RPC-Explorer " --msgbox "Open in your local web browser:
http://${localIP}:3020\n
https://${localIP}:3021 with Fingerprint:
${fingerprint}\n
${passwordInfo}\n
Activate TOR to access the web block explorer from outside your local network.
" 16 54
  fi

  echo "please wait ..."
  exit 0
fi

# status
if [ "$1" = "status" ]; then

  echo "version='${VERSION}'"

    fatpack=$(compgen -u | grep -c glcrpcexplorer)
    echo "fatpack=${fatpack}"

  if [ "${GLCRPCexplorer}" = "on" ]; then
    echo "configured=1"

    installed=$(sudo ls /etc/systemd/system/glc-rpc-explorer.service 2>/dev/null | grep -c 'glc-rpc-explorer.service')
    echo "installed=${installed}"

    # get network info
    localIP=$(hostname -I | awk '{print $1}')
    toraddress=$(sudo cat /mnt/hdd/app-data/tor/glc-rpc-explorer/hostname 2>/dev/null)
    fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

    authMethod="user_admin_password_b"
    isGlcoinWalletOff=$(cat /mnt/hdd/app-data/glcoin/glcoin.conf | grep -c "^disablewallet=1")
    if [ "${isGlcoinWalletOff}" == "1" ]; then
      authMethod="none"
    fi

    echo "localIP='${localIP}'"
    echo "httpPort='3020'"
    echo "httpsPort='3021'"
    echo "httpsForced='0'"
    echo "httpsSelfsigned='1'"
    echo "authMethod='${authMethod}'"
    echo "toraddress='${toraddress}'"
    echo "fingerprint='${fingerprint}'"

    # check indexing
    source <(sudo /home/admin/config.scripts/network.txindex.sh status)
    echo "isIndexed=${isIndexed}"
    echo "indexInfo='${indexInfo}'"

    # check for error
    isDead=$(sudo systemctl status glc-rpc-explorer | grep -c 'inactive (dead)')
    if [ ${isDead} -eq 1 ]; then
      echo "error='Service Failed'"
      exit 1
    fi

  else
    echo "configured=0"
    echo "installed=0"
  fi
  exit 0
fi

##########################
# PRESTART
# - will be called as prestart by systemd service (as user glcrpcexplorer)
#########################

if [ "$1" = "prestart" ]; then

  # users need to be `glcrpcexplorer` so that it can be run by systemd as prestart (no SUDO available)
  if [ "$USER" != "glcrpcexplorer" ]; then
    echo "# FAIL: run as user glcrpcexplorer"
    exit 1
  fi

  echo "## glc-rpc-explorer.service PRESTART CONFIG"
  echo "# --> /home/glcrpcexplorer/.config/glc-rpc-explorer.env"

  # Robust initial values to avoid unset-variable issues
  isElectrsReady=0
  isFulcrumReady=0
  electrumTCPport=""

  # check if electrs is installed & running
  if [ "${ElectRS}" == "on" ]; then

    # CHECK THAT ELECTRS INDEX IS BUILT (WAITLOOP)
    # electrs listening in port 50001 means index is built
    # Use flags: t = tcp protocol only  /  a = list all connection states (includes LISTEN)  /  n = don't resolve names => no dns spam
    isElectrsReady=$(netstat -tan | grep -c "50001")
    echo "# electrs is ON .. and ready (${isElectrsReady})"
    electrumTCPport=50001
  fi

  # check if fulcrum is installed & running
  if [ "${fulcrum}" == "on" ]; then
    isFulcrumReady=$(netstat -tan | grep -c "50021")
    echo "# fulcrum is ON .. and ready (${isFulcrumReady})"
    electrumTCPport=50021
  fi

  # If an electrum server is ON but not ready, fall back to RPC-only mode
  # rather than blocking the service from starting.
  if { [ "${ElectRS}" == "on" ] && [ "${isElectrsReady}" == "0" ]; } || { [ "${fulcrum}" == "on" ] && [ "${isFulcrumReady}" == "0" ]; }; then
    echo "# An Electrum Server is ON but not ready (index still building) -- falling back to RPC-only mode"
    isElectrsReady=0
    isFulcrumReady=0
  fi

  if [ "${isElectrsReady}" -gt 0 ] || [ "${isFulcrumReady}" -gt 0 ]; then
    # CHECK THAT ELECTRUM SERVER IS PART OF CONFIG
    echo "# updating BTCEXP_ADDRESS_API=electrumx"
    sed -i 's/^BTCEXP_ADDRESS_API=.*/BTCEXP_ADDRESS_API=electrumx/g' /home/glcrpcexplorer/.config/glc-rpc-explorer.env
    # Use different delimiter to avoid collision with "tcp://"
    sed -i "s|^BTCEXP_ELECTRUMX_SERVERS=.*|BTCEXP_ELECTRUMX_SERVERS=tcp://127.0.0.1:${electrumTCPport}|g" /home/glcrpcexplorer/.config/glc-rpc-explorer.env
  else
    # v0.15.20 (Bug B1): btc-rpc-explorer's address-API enum rejects 'none'
    # (`Error 32907ghsd0ge: Unrecognized value for BTCEXP_ADDRESS_API: 'none'.
    # Valid options are: blockchain.com,blockchair.com,blockcypher.com,electrum,
    # electrumx`) which surfaces at startup before RPC verification. The
    # previous setter wrote 'none' as a kill-switch to disable the API
    # connection when no local Electrum server was ready, but the upstream
    # parser only honours an absent variable as "address-API disabled".
    # Delete the line entirely so the default (no address-API) applies cleanly.
    echo "# unsetting BTCEXP_ADDRESS_API (no Electrum server ready)"
    sed -i '/^BTCEXP_ADDRESS_API=/d' /home/glcrpcexplorer/.config/glc-rpc-explorer.env
  fi

  #  UPDATE RPC PASSWORD
  # Defensive read: if glcoin.conf is not readable (e.g. glcrpcexplorer not
  # in group 'glcoin' on an old install) we MUST NOT blank the existing
  # password in .env — that would corrupt a working configuration on every
  # service start. Log a warning instead and keep what's already there.
  RPCPASSWORD=$(cat /mnt/hdd/app-data/${network}/${network}.conf 2>/dev/null | grep "^rpcpassword=" | cut -d "=" -f2)
  if [ -z "${RPCPASSWORD}" ]; then
    echo "# WARN: could not read rpcpassword from /mnt/hdd/app-data/${network}/${network}.conf"
    echo "# Check: 'id glcrpcexplorer' must include group '${network}'"
    echo "# Fix:   sudo usermod -a -G ${network} glcrpcexplorer && sudo systemctl restart glc-rpc-explorer"
    echo "# Leaving existing BTCEXP_BITCOIND_PASS in .env untouched"
  else
    echo "# updating BTCEXP_BITCOIND_PASS (length=${#RPCPASSWORD})"
    sed -i "s/^BTCEXP_BITCOIND_PASS=.*/BTCEXP_BITCOIND_PASS=${RPCPASSWORD}/g" /home/glcrpcexplorer/.config/glc-rpc-explorer.env
  fi

  # WALLET PROTECTION (only if Glcoin has wallet active protect GLC-RPC-Explorer with additional passwordB)
  isGlcoinWalletOff=$(cat /mnt/hdd/app-data/${network}/${network}.conf | grep -c "^disablewallet=1")
  if [ "${isGlcoinWalletOff}" == "1" ]; then
    echo "# updating BTCEXP_BASIC_AUTH_PASSWORD= --> no password needed because wallet is disabled"
    sed -i "s/^BTCEXP_BASIC_AUTH_PASSWORD=.*/BTCEXP_BASIC_AUTH_PASSWORD=/g" /home/glcrpcexplorer/.config/glc-rpc-explorer.env
  else
    echo "# updating BTCEXP_BASIC_AUTH_PASSWORD=${RPCPASSWORD} --> enable password to protect wallet"
    sed -i "s/^BTCEXP_BASIC_AUTH_PASSWORD=.*/BTCEXP_BASIC_AUTH_PASSWORD=${RPCPASSWORD}/g" /home/glcrpcexplorer/.config/glc-rpc-explorer.env
  fi

  exit 0 # exit with clean code
fi

# stop service (for all calls below)
echo "# making sure services are not running"
sudo systemctl stop glc-rpc-explorer 2>/dev/null

# install (code & compile)
if [ "$1" = "install" ]; then

  # check if already installed
  isInstalled=$(compgen -u | grep -c glcrpcexplorer)
  if [ "${isInstalled}" != "0" ]; then
    echo "result='already installed'"
    exit 0
  fi

  echo "# *** INSTALL GLC-RPC-EXPLORER ***"

  # install nodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on

  # add glcrpcexplorer user
  sudo adduser --system --group --home /home/glcrpcexplorer glcrpcexplorer

  # Membership in group 'glcoin' is required so the prestart script can read
  # /mnt/hdd/app-data/glcoin/glcoin.conf (mode 0640, group glcoin per v0149
  # audit). Without this, prestart's RPCPASSWORD lookup silently returns
  # empty and BTCEXP_BITCOIND_PASS gets blanked on every service start —
  # the explorer process runs but every RPC call to glcoind fails auth.
  sudo usermod -a -G glcoin glcrpcexplorer

  # install glc-rpc-explorer (using btc-rpc-explorer codebase, cloned as glc-rpc-explorer)
  cd /home/glcrpcexplorer
  sudo -u glcrpcexplorer git clone https://github.com/janoside/btc-rpc-explorer.git glc-rpc-explorer
  cd glc-rpc-explorer
  sudo -u glcrpcexplorer git reset --hard ${GITHUBCOMMIT}
  sudo -u glcrpcexplorer /home/admin/config.scripts/blesk.git-verify.sh "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || echo "# WARN: PGP verify skipped for pinned commit ${GITHUBCOMMIT}"
  sudo -u glcrpcexplorer NO_UPDATE_NOTIFIER=1 npm ci --no-audit --no-fund 2>&1 | grep -Ev "^npm (warn deprecated|warn old lockfile|notice)"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      echo "FAIL - npm ci did not run correctly, aborting"
      echo "result='fail npm ci'"
      exit 1
  fi

  # apply Glcoin patches on top of the btc-rpc-explorer codebase:
  # injects app/coins/glc.js, registers GLC in app/coins.js so
  # BTCEXP_COIN=GLC actually resolves to a coin module
  if [ -d /home/admin/assets/glc-rpc-explorer ]; then
    echo "# applying Glcoin patches to explorer tree ..."
    sudo cp -r /home/admin/assets/glc-rpc-explorer /home/glcrpcexplorer/.glcoin-patches
    sudo chown -R glcrpcexplorer:glcrpcexplorer /home/glcrpcexplorer/.glcoin-patches
    sudo -u glcrpcexplorer bash /home/glcrpcexplorer/.glcoin-patches/apply-glcoin-patches.sh \
      /home/glcrpcexplorer/glc-rpc-explorer || {
        echo "FAIL - Glcoin patch step failed"
        echo "result='fail glcoin-patch'"
        exit 1
    }
  else
    echo "# WARN: /home/admin/assets/glc-rpc-explorer not found — explorer will run with BTC branding"
  fi

  exit 0
fi

# remove from system
if [ "$1" = "uninstall" ]; then

  # check if still active
  isActive=$(sudo ls /etc/systemd/system/glc-rpc-explorer.service 2>/dev/null | grep -c 'glc-rpc-explorer.service')
  if [ "${isActive}" != "0" ]; then
    echo "result='still in use'"
    exit 1
  fi

  echo "# *** UNINSTALL GLC-RPC-EXPLORER ***"

  # always delete user and home directory
  sudo userdel -rf glcrpcexplorer

  exit 0
fi

##########################
# ON
#########################

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if code is already installed
  isInstalled=$(compgen -u | grep -c glcrpcexplorer)
  if [ "${isInstalled}" == "0" ]; then
    echo "# Installing code base & dependencies first .."
    /home/admin/config.scripts/bonus.glc-rpc-explorer.sh install || exit 1
  fi

  echo "# *** ACTIVATE GLC-RPC-EXPLORER ***"

  isInstalled=$(sudo ls /etc/systemd/system/glc-rpc-explorer.service 2>/dev/null | grep -c 'glc-rpc-explorer.service')
  if [ ${isInstalled} -eq 0 ]; then

    # make sure that txindex of blockchain is switched on
    /home/admin/config.scripts/network.txindex.sh on

    # prepare .env file
    echo "# getting RPC credentials from the ${network}.conf"

    RPC_USER=$(sudo cat /mnt/hdd/app-data/${network}/${network}.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/app-data/${network}/${network}.conf | grep rpcpassword | cut -c 13-)

    touch /var/cache/raspiblesk/glc-rpc-explorer.env
    chmod 600 /var/cache/raspiblesk/glc-rpc-explorer.env || exit 1
    cat > /var/cache/raspiblesk/glc-rpc-explorer.env <<EOF
# Coin selection — must match the GLC module we inject post-clone
# (apply-glcoin-patches.sh registers 'glc' in app/coins.js).
BTCEXP_COIN=GLC
# Host/Port to bind to
# Defaults: shown
BTCEXP_HOST=0.0.0.0
BTCEXP_PORT=3020
# Glcoin RPC Credentials (URI -OR- HOST/PORT/USER/PASS)
# Defaults:
#   - [host/port]: 127.0.0.1:1617
#   - [username/password]: none
#   - cookie: '~/.glcoin/.cookie'
#   - timeout: 5000 (ms)
BTCEXP_BITCOIND_HOST=127.0.0.1
BTCEXP_BITCOIND_PORT=1617
BTCEXP_BITCOIND_USER=$RPC_USER
BTCEXP_BITCOIND_PASS=$PASSWORD_B
#BTCEXP_BITCOIND_COOKIE=/path/to/glcoind/.cookie
BTCEXP_BITCOIND_RPC_TIMEOUT=10000
# Privacy mode disables:
# Exchange-rate queries, IP-geolocation queries
# Default: false
BTCEXP_PRIVACY_MODE=true
# Password protection for site via basic auth (enter any username, only the password is checked)
# Default: none
#BTCEXP_BASIC_AUTH_PASSWORD=$PASSWORD_B
# Select optional "address API" to display address tx lists and balances
# Options: electrumx, blockchain.com, blockchair.com, blockcypher.com
# If electrumx set, the BTCEXP_ELECTRUMX_SERVERS variable must also be
# set.
# v0.15.20 (Bug B1): empty value (not 'none') at init.
# The prestart hook substitutes this with `electrumx` once a local electrs/
# fulcrum becomes ready (sed -i 's/^BTCEXP_ADDRESS_API=.*/...=electrumx/'),
# or deletes the line entirely if no Electrum server is up (sed -i '/^BTC.../d').
# An empty value is silently accepted by btc-rpc-explorer's enum parser as
# "no address-API" — unlike 'none' which is rejected as Unrecognized.
BTCEXP_ADDRESS_API=
BTCEXP_ELECTRUMX_SERVERS=tcp://127.0.0.1:50001
# Expose every RPC method through /rpc-browser. Glcoin 0.2.x adds custom RPCs
# (listminers, getminerinfo, getminerregistrystats, getipfslink, listipfslinks,
# pinipfslink, …) that the default whitelist doesn't cover.
BTCEXP_RPC_ALLOWALL=true
EOF
    sudo -u glcrpcexplorer mkdir /home/glcrpcexplorer/.config
    sudo mv /var/cache/raspiblesk/glc-rpc-explorer.env /home/glcrpcexplorer/.config/glc-rpc-explorer.env
    sudo chown glcrpcexplorer:glcrpcexplorer /home/glcrpcexplorer/.config/glc-rpc-explorer.env

    # open firewall
    echo "# *** Updating Firewall ***"
    sudo ufw allow 3020 comment 'glc-rpc-explorer HTTP'
    sudo ufw allow 3021 comment 'glc-rpc-explorer HTTPS'
    echo ""

    ##################
    # NGINX
    ##################
    # setup nginx symlinks
    if ! [ -f /etc/nginx/sites-available/glcrpcexplorer_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/glcrpcexplorer_ssl.conf /etc/nginx/sites-available/glcrpcexplorer_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/glcrpcexplorer_tor.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/glcrpcexplorer_tor.conf /etc/nginx/sites-available/glcrpcexplorer_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/glcrpcexplorer_tor_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/glcrpcexplorer_tor_ssl.conf /etc/nginx/sites-available/glcrpcexplorer_tor_ssl.conf
    fi
    sudo ln -sf /etc/nginx/sites-available/glcrpcexplorer_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/glcrpcexplorer_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/glcrpcexplorer_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx

    # install service
    echo "*** Install glc-rpc-explorer systemd ***"
    cat > /var/cache/raspiblesk/glc-rpc-explorer.service <<EOF
# systemd unit for GLC RPC Explorer

[Unit]
Description=glc-rpc-explorer
Wants=${network}d.service
After=${network}d.service
StartLimitIntervalSec=0

[Service]
User=glcrpcexplorer
ExecStartPre=/home/admin/config.scripts/bonus.glc-rpc-explorer.sh prestart
WorkingDirectory=/home/glcrpcexplorer/glc-rpc-explorer
# btc-rpc-explorer's dotenv loader looks at ~/.config/btc-rpc-explorer/.env, not
# our renamed glc-rpc-explorer.env — so without an explicit EnvironmentFile
# every BTCEXP_* var falls back to the upstream BTC defaults (RPC port 8332,
# coin BTC, etc.) and the Glcoin overrides written by the prestart are ignored.
EnvironmentFile=/home/glcrpcexplorer/.config/glc-rpc-explorer.env
ExecStart=/usr/bin/node ./bin/www
Restart=on-failure
RestartSec=20
# LogLevelMax intentionally not set — Node logs at INFO (level 6) and the
# previous LogLevelMax=4 dropped every line from the journal, masking
# RPC-auth failures, prestart warnings, and "Listening on port 3020"
# banners. Without journal output we cannot diagnose anything.
Environment=NODE_ENV=production
Environment=DEBUG=*

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /var/cache/raspiblesk/glc-rpc-explorer.service /etc/systemd/system/glc-rpc-explorer.service
    sudo systemctl enable glc-rpc-explorer
    echo "# OK - the GLC-RPC-explorer service is now enabled"

  else
    echo "# GLC-RPC-explorer already installed."
  fi

  # setting value in raspi blitz config
  sudo /home/admin/config.scripts/blesk.conf.sh set GLCRPCexplorer "on"

  echo "# needs to finish creating txindex to be functional"
  echo "# monitor with: sudo tail -n 20 -f /mnt/hdd/app-data/glcoin/debug.log"
  echo "# npm audit fix"
  cd /home/glcrpcexplorer/glc-rpc-explorer/
  sudo npm audit fix

  # Hidden Service for GLC-RPC-explorer if Tor is active
  source /mnt/hdd/app-data/raspiblesk.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    sudo /home/admin/config.scripts/tor.onion-service.sh glc-rpc-explorer 80 3022 443 3023
  fi

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    # start service
    echo "# starting service ..."
    sudo systemctl start glc-rpc-explorer 2>/dev/null
    sleep 10
  fi

  # needed for API/WebUI to signal successfull install
  echo "result='OK'"
  exit 0
fi

##########################
# OFF
#########################

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo /home/admin/config.scripts/blesk.conf.sh set GLCRPCexplorer "off"

  isInstalled=$(sudo ls /etc/systemd/system/glc-rpc-explorer.service 2>/dev/null | grep -c 'glc-rpc-explorer.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING GLC-RPC-explorer ***"
    sudo systemctl disable glc-rpc-explorer
    sudo rm /etc/systemd/system/glc-rpc-explorer.service

    # remove nginx symlinks
    sudo rm -f /etc/nginx/sites-enabled/glcrpcexplorer_ssl.conf
    sudo rm -f /etc/nginx/sites-enabled/glcrpcexplorer_tor.conf
    sudo rm -f /etc/nginx/sites-enabled/glcrpcexplorer_tor_ssl.conf
    sudo rm -f /etc/nginx/sites-available/glcrpcexplorer_ssl.conf
    sudo rm -f /etc/nginx/sites-available/glcrpcexplorer_tor.conf
    sudo rm -f /etc/nginx/sites-available/glcrpcexplorer_tor_ssl.conf
    sudo nginx -t
    sudo systemctl reload nginx

    # Hidden Service if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with tor.network.sh script
      sudo /home/admin/config.scripts/tor.onion-service.sh off glc-rpc-explorer
    fi

    echo "# OK GLC-RPC-explorer removed."

  else
    echo "# GLC-RPC-explorer is not installed."
  fi

  # close ports on firewall
  sudo ufw delete allow 3020
  sudo ufw delete allow 3021

  # needed for API/WebUI to signal successfull install
  echo "result='OK'"
  exit 0
fi

echo "error='unknown parameter'"
exit 1