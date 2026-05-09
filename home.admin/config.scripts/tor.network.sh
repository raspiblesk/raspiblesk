#!/usr/bin/env bash


## Description: This script configure glcoin and lightning implementations to be used with tor
## Background:
## https://medium.com/@lopp/how-to-run-glcoin-as-a-tor-hidden-service-on-ubuntu-cff52d543756
## https://glcoin.stackexchange.com/questions/70069/how-can-i-setup-glcoin-to-be-anonymous-with-tor
## https://github.com/lightningnetwork/lnd/blob/master/docs/configuring_tor.md

torrc="/etc/tor/torrc"

# command info
usage(){
 echo "script to switch Tor on or off"
 echo "tor.network.sh [status|on|off|btcconf-on|btcconf-off]"
 exit 1
}

activateGlcoinOverTor()
{
  echo "*** Changing Glcoin Config for Tor ***"
  local glcoinConf="/mnt/hdd/app-data/glcoin/glcoin.conf"

  btcExists=$(sudo ls "${glcoinConf}" 2>/dev/null | grep -c "glcoin.conf")
  if [ "${btcExists}" -gt 0 ]; then

    # make sure all is turned off and removed and then activate fresh (so that also old settings get removed)
    deactivateGlcoinOverTor

    # Edit as the file owner (glcoin) without ever widening permissions.
    # The previous chmod 777 → edit → chmod 644 sequence opened a multi-second
    # window during which any local user could read rpcuser/rpcpassword or
    # append a malicious line (rpcallowip=0.0.0.0/0, walletnotify=…) to the
    # conf. Keep mode 640 glcoin:glcoin throughout.
    echo "Adding Tor config to glcoin.conf ..."
    # Wipe ALL prior values for keys we manage so re-runs do not stack.
    # Use sed -i ... -e to delete entire matching lines (not blank them).
    sudo -u glcoin sed -i \
      -e '/^onlynet=/d' \
      -e '/^torpassword=/d' \
      -e '/^proxy=/d' \
      -e '/^main\.bind=/d' \
      -e '/^test\.bind=/d' \
      -e '/^dnsseed=/d' \
      -e '/^dns=/d' \
      "${glcoinConf}"
    # Tor activation: onion-only. (i2p was erroneously enabled here before;
    # i2p is a separate transport and must be opted-in via blesk.i2pd.sh on.)
    echo "onlynet=onion"        | sudo -u glcoin tee -a "${glcoinConf}" >/dev/null
    echo "proxy=127.0.0.1:9050" | sudo -u glcoin tee -a "${glcoinConf}" >/dev/null
    echo "main.bind=127.0.0.1"  | sudo -u glcoin tee -a "${glcoinConf}" >/dev/null
    echo "test.bind=127.0.0.1"  | sudo -u glcoin tee -a "${glcoinConf}" >/dev/null
    echo "dnsseed=0"            | sudo -u glcoin tee -a "${glcoinConf}" >/dev/null
    echo "dns=0"                | sudo -u glcoin tee -a "${glcoinConf}" >/dev/null

    # remove empty lines
    sudo -u glcoin sed -i '/^ *$/d' "${glcoinConf}"
    # Enforce safe mode in case earlier installs left it world-readable.
    sudo chown glcoin:glcoin "${glcoinConf}"
    sudo chmod 640 "${glcoinConf}"

  else
    echo "FAIL: glcoin.conf not found at ${glcoinConf} - is HDD mounted?"
  fi
}

deactivateGlcoinOverTor()
{
  local glcoinConf="/mnt/hdd/app-data/glcoin/glcoin.conf"

  # Edit as the conf owner (glcoin) — no chmod widening; mode stays 640.
  # Only strip .onion addnode entries — clearnet/signet addnode entries (the
  # DNS-seeder hostnames or any LAN peers) must survive a tor->clearnet switch.
  # Old code unconditionally deleted every main.addnode=/test.addnode= which
  # silently wiped peer config and left the node with zero peers.
  # Delete entire lines (not blank them) for every key we are about to rewrite,
  # so flipping tor on/off repeatedly does not stack duplicates.
  sudo -u glcoin sed -i \
    -e '/^onlynet=/d' \
    -e '/^proxy=/d' \
    -e '/^main\.bind=/d' \
    -e '/^test\.bind=/d' \
    -e '/^dnsseed=/d' \
    -e '/^dns=/d' \
    -e '/^debug=i2p$/d' \
    -e '/^i2psam=/d' \
    -e '/^i2pacceptincoming=/d' \
    -e '/^main\.addnode=.*\.onion/d' \
    -e '/^test\.addnode=.*\.onion/d' \
    -e '/^addnode=.*\.onion/d' \
    -e '/^ *$/d' \
    "${glcoinConf}"

  # restore clearnet-only mode
  echo "onlynet=ipv4" | sudo -u glcoin tee -a "${glcoinConf}" >/dev/null
  echo "onlynet=ipv6" | sudo -u glcoin tee -a "${glcoinConf}" >/dev/null
  # enable DNS seed — glcoin chainparams.cpp ships seed.glcoin.org for mainnet
  echo "dnsseed=1" | sudo -u glcoin tee -a "${glcoinConf}" >/dev/null
}

# check and load raspiblesk config
# to know which network is running
[ -f "/home/admin/raspiblesk.info" ] && . /home/admin/raspiblesk.info
[ -f "/mnt/hdd/app-data/raspiblesk.conf" ] && . /mnt/hdd/app-data/raspiblesk.conf

torActive=$(systemctl is-active tor@default | grep -c "^active")
curl --socks5 127.0.0.1:9050 --socks5-hostname 127.0.0.1:9050 -m 5 -s https://check.torproject.org/api/ip | grep -q "\"IsTor\":true" && torFunctional=1

case "$1" in

  status)
    if [ "${runBehindTor}" = "" ]; then
      runBehindTor="off"
    fi
    echo "torEnabled=${runBehindTor}"
    echo "torActive=${torActive}"
    echo "torFunctional=${torFunctional}"
    echo "config=${torrc}"
  ;;


  btcconf-on) activateGlcoinOverTor; exit 0;;


  btcconf-off) deactivateGlcoinOverTor; exit 0;;


  1|on)
    echo "# switching Tor ON"

    # make sure the network was set (by sourcing raspiblesk.conf)
    if [ ${#network} -eq 0 ]; then
      echo "# FAIL - unknown network due to missing raspiblesk.conf"
      echo "# switching Tor config on for RaspiBlesk services is just possible after basic hdd/ssd setup"
      echo "# but with new 'Tor by default' basic Tor socks will already be available from the start"
      exit 1
    fi

    # setting value in raspi blitz config
    /home/admin/config.scripts/blesk.conf.sh set runBehindTor "on"

    # ACTIVATE GLCOIN OVER TOR (function call)
    activateGlcoinOverTor

    # ACTIVATE APPS OVER TOR
    . /mnt/hdd/app-data/raspiblesk.conf 2>/dev/null
    /home/admin/config.scripts/tor.onion-service.sh web80 80 80 443 443
    /home/admin/config.scripts/tor.onion-service.sh debuglogs 80 6969
    [ "${GLCRPCexplorer}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh glc-rpc-explorer 80 3022 443 3023
    [ "${rtlWebinterface}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh RTL 80 3002 443 3003
    [ "${ElectRS}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh electrs 50002 50002 50001 50001
    [ "${LNBits}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh lnbits 80 5002 443 5003
    [ "${thunderhub}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh thunderhub 80 3012 443 3013
    [ "${specter}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh specter 443 25441
    [ "${lndg}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh lndg 80 8886 443 8887
    if [ "${sphinxrelay}" = "on" ]; then
      /home/admin/config.scripts/tor.onion-service.sh sphinxrelay 80 3302 443 3303
      toraddress=$(sudo cat /mnt/hdd/app-data/tor/sphinxrelay/hostname 2>/dev/null)
      sudo -u sphinxrelay bash -c "echo '${toraddress}' > /home/sphinxrelay/sphinx-relay/dist/toraddress.txt"
    fi
    if [ "${helipad}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh helipad 2112 2113
    fi
    [ "${itchysats}" = "on" ] && /home/admin/config.scripts/tor.onion-service.sh itchysats 80 8890 443 8891

    echo "Setup logrotate"
    # add logrotate config for modified Tor dir on ext. disk
    sudo tee /etc/logrotate.d/raspiblesk-tor >/dev/null <<EOF
/mnt/hdd/app-data/tor/*log {
        su debian-tor debian-tor
        size 100M
        rotate 2
        compress
        delaycompress
        missingok
        notifempty
        create 0640 debian-tor debian-tor
        sharedscripts
        postrotate
            systemctl reload tor >/dev/null 2>&1 || true
        endscript
}
EOF

    # block clearnet P2P port — node only accepts inbound via Tor hidden service
    sudo ufw deny 1618 comment 'glcoin P2P blocked - Tor-only mode' 2>/dev/null
    sudo ufw deny 11618 comment 'glcoin testnet P2P blocked - Tor-only mode' 2>/dev/null

    # make sure its the correct owner before last Tor restart
    sudo chmod -R 700 /mnt/hdd/app-data/tor
    sudo chown -R debian-tor:debian-tor /mnt/hdd/app-data/tor
    sudo systemctl restart tor@default
    echo "OK - Tor is now $(systemctl is-active tor@default)"
    echo "needs reboot to activate new setting"
  ;;


  0|off)
    echo "# switching Tor OFF"

    # setting value in raspi blitz config
    /home/admin/config.scripts/blesk.conf.sh set runBehindTor "off"

    # remove "debug=tor" from glcoin.conf
    sudo sed -i '/^debug=tor$/d' /mnt/hdd/app-data/glcoin/glcoin.conf

    # deactivate glcoin over tor (function call)
    deactivateGlcoinOverTor
    echo

    # re-open clearnet P2P ports (remove deny rule first, then allow)
    sudo ufw delete deny 1618 2>/dev/null
    sudo ufw delete deny 11618 2>/dev/null
    sudo ufw allow 1618 comment 'glcoin mainnet P2P' 2>/dev/null
    sudo ufw allow 11618 comment 'glcoin testnet P2P' 2>/dev/null

    sudo /home/admin/config.scripts/internet.sh update-publicip

    if [ "${lightning}" = "lnd" ] || [ "${lnd}" = "on" ] || [ "${lnd}" = "1" ]; then
      echo "# *** Removing Tor from LND Mainnet ***"
      sudo sed -i '/^\[[Tt]or\].*/d' /mnt/hdd/app-data/lnd/lnd.conf
      sudo sed -i '/^tor\..*/d' /mnt/hdd/app-data/lnd/lnd.conf
      sudo systemctl restart lnd
    fi

    if [ "${tlnd}" = "on" ] || [ "${tlnd}" = "1" ]; then
      echo "# *** Removing Tor from LND Testnet ***"
      sudo sed -i '/^\[[Tt]or\].*/d' /mnt/hdd/app-data/lnd/tlnd.conf
      sudo sed -i '/^tor\..*/d' /mnt/hdd/app-data/lnd/tlnd.conf
      sudo systemctl restart tlnd
    fi

    if [ "${slnd}" = "on" ] || [ "${slnd}" = "1" ]; then
      echo "# *** Removing Tor from LND Signet ***"
      sudo sed -i '/^\[[Tt]or\].*/d' /mnt/hdd/app-data/lnd/slnd.conf
      sudo sed -i '/^tor\..*/d' /mnt/hdd/app-data/lnd/slnd.conf
      sudo systemctl restart slnd
    fi

    echo "# OK"
    echo
  ;;

  update)
    if /home/admin/config.scripts/tor.install.sh update; then
      echo "# Tor was updated to $(tor --version)"
      if systemctl is-active lnd ;then
        echo "# LND will be restarted"
        sudo systemctl restart lnd
        sudo systemctl restart tlnd 2>/dev/null
        sudo systemctl restart slnd 2>/dev/null
        sleep 10
        lncli unlock
      fi
      if systemctl is-active lightningd; then
        echo "# CLN will be restarted"
        sudo systemctl restart lightningd
        sudo systemctl restart tlightningd 2>/dev/null
        sudo systemctl restart slightningd 2>/dev/null
      fi
    else
      echo "# Tor was not updated"
      tor --version
    fi
  ;;

  *) usage

esac
