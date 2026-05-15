#!/bin/bash

# check if run by root user
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root'"
  exit 1
fi

# This script gets called from a fresh SD card
# starting up that has a config file on HDD
# from old RaspiBlesk or manufacturer
# to install and config services

# LOGFILE - store debug logs of bootstrap
logFile="/home/admin/raspiblesk.log"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblesk.info"

# CONFIGFILE - configuration of RaspiBlesk
configFile="/mnt/hdd/app-data/raspiblesk.conf"

# SETUPFILE
# this key/value file contains the state during the setup process
setupFile="/var/cache/raspiblesk/temp/raspiblesk.setup"
source ${setupFile}

# log header
echo "" >> ${logFile}
echo "###################################" >> ${logFile}
echo "# _provision_.sh" >> ${logFile}
echo "###################################" >> ${logFile}
/home/admin/_cache.sh set message "Provisioning from Config"

# check if there is a config file
configExists=$(ls ${configFile} 2>/dev/null | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
  /home/admin/config.scripts/blesk.error.sh _provision_.sh "missing-config" "no config file (${configFile}) found to run provision" "" ${logFile}
  exit 1
fi

# import config values
source ${infoFile}
source ${configFile}

##########################
# BASIC SYSTEM SETTINGS
##########################

echo "### BASIC SYSTEM SETTINGS ###" >> ${logFile}
/home/admin/_cache.sh set message "Setup System ."

echo "# Make sure the user glcoin is in the debian-tor group"
usermod -a -G debian-tor glcoin

# make sure to have glcoin core >=22 is backwards comp
# see https://github.com/rootzoll/raspiblesk/issues/2546
sed -i '/^deprecatedrpc=.*/d' /mnt/hdd/app-data/glcoin/glcoin.conf 2>/dev/null
echo "deprecatedrpc=addresses" >> /mnt/hdd/app-data/glcoin/glcoin.conf 2>/dev/null

# backup SSH PubKeys
/home/admin/config.scripts/blesk.ssh.sh backup

# set timezone
/home/admin/config.scripts/blesk.time.sh set-by-config >> ${logFile}

# optimize mempool if RAM >1GB
kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
if [ ${kbSizeRAM} -gt 1500000 ]; then
  echo "Detected RAM >1GB --> optimizing ${network}.conf"
  sed -i "s/^maxmempool=.*/maxmempool=300/g" /mnt/hdd/app-data/${network}/${network}.conf
fi
if [ ${kbSizeRAM} -gt 3500000 ]; then
  echo "Detected RAM >3GB --> optimizing ${network}.conf"
  sed -i "s/^maxmempool=.*/maxmempool=300/g" /mnt/hdd/app-data/${network}/${network}.conf
fi

# zram on for all devices
/home/admin/config.scripts/blesk.zram.sh on >> ${logFile}

# PREPARE LND (if activated)
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  # backup LND TLS certs
  # https://github.com/rootzoll/raspiblesk/issues/324
  echo "*** Make backup of LND TLS files" >> ${logFile}
  rm -r  /var/cache/raspiblesk/tls_backup 2>/dev/null
  mkdir /var/cache/raspiblesk/tls_backup 2>/dev/null
  cp /mnt/hdd/app-data/lnd/tls.cert /var/cache/raspiblesk/tls_backup/tls.cert >> ${logFile} 2>&1
  cp /mnt/hdd/app-data/lnd/tls.key /var/cache/raspiblesk/tls_backup/tls.key >> ${logFile} 2>&1
fi
echo "" >> ${logFile}

##########################
# FINISH SETUP
##########################

# finish setup (SWAP, Benus, Firewall, Update, ..)
/home/admin/_cache.sh set message "Setup System .."

# bash completion for glcoin-cli and lncli is shipped with the source tarballs
# installed during build_sdcard.sh phase — skip external downloads

###### SWAP File
source <(/home/admin/config.scripts/blesk.data.sh status)
if [ ${bootFromSD} -eq 0 ] && [ ${swapActive} -eq 0 ]; then
  echo "No SWAP found - creating ... "
  /home/admin/config.scripts/blesk.data.sh swap on
else
  echo "SWAP already OK - dont add swap when running from SD card or already active"
fi

####### FIREWALL - just install (not configure)
echo ""
echo "*** Setting and Activating Firewall ***"
echo "deny incoming connection on other ports"
ufw default deny incoming
echo "allow outgoing connections"
ufw default allow outgoing
echo "allow: ssh"
ufw allow ssh
echo "allow: glcoin testnet P2P"
ufw allow 11618 comment 'glcoin testnet P2P'
echo "allow: glcoin mainnet P2P"
ufw allow 1618 comment 'glcoin mainnet P2P'
echo 'allow: glcoin mainnet RPC (localhost + LAN only)'
ufw allow from 127.0.0.1 to any port 1617 comment 'glcoin mainnet RPC localhost'
ufw allow from 10.0.0.0/8 to any port 1617 comment 'glcoin mainnet RPC LAN'
ufw allow from 172.16.0.0/12 to any port 1617 comment 'glcoin mainnet RPC LAN'
ufw allow from 192.168.0.0/16 to any port 1617 comment 'glcoin mainnet RPC LAN'
echo "allow: lightning mainnet"
ufw allow 9735 comment 'lightning mainnet'
# (lightning testnet 19735 used to be allowed Anywhere unconditionally —
# removed in v0.15.12. Re-add scoped to LAN if testnet is ever enabled.)
echo "allow: lightning gRPC (localhost + LAN only)"
ufw allow from 127.0.0.1 to any port 10009 comment 'lightning gRPC localhost'
ufw allow from 10.0.0.0/8 to any port 10009 comment 'lightning gRPC LAN'
ufw allow from 172.16.0.0/12 to any port 10009 comment 'lightning gRPC LAN'
ufw allow from 192.168.0.0/16 to any port 10009 comment 'lightning gRPC LAN'
echo "allow: lightning REST API (localhost + LAN only)"
ufw allow from 127.0.0.1 to any port 8080 comment 'lightning REST localhost'
ufw allow from 10.0.0.0/8 to any port 8080 comment 'lightning REST LAN'
ufw allow from 172.16.0.0/12 to any port 8080 comment 'lightning REST LAN'
ufw allow from 192.168.0.0/16 to any port 8080 comment 'lightning REST LAN'
echo "allow: public web HTTP"
ufw allow from any to any port 80 comment 'allow public web HTTP'
echo "allow: local web admin HTTPS"
ufw allow from 10.0.0.0/8 to any port 443 comment 'allow local LAN HTTPS'
ufw allow from 172.16.0.0/12 to any port 443 comment 'allow local LAN HTTPS'
ufw allow from 192.168.0.0/16 to any port 443 comment 'allow local LAN HTTPS'
echo "open firewall for auto nat discover (see issue #129 & #3144)"
ufw allow proto udp from 10.0.0.0/8 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
ufw allow proto udp from 172.16.0.0/12 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
ufw allow proto udp from 192.168.0.0/16 port 1900 to any comment 'allow local LAN SSDP for UPnP discovery'
ufw allow proto udp from 192.168.0.0/16 port 5350 to any comment 'Bonjour NAT'
ufw allow proto udp from 172.16.0.0/12 port 5350 to any comment 'Bonjour NAT'
ufw allow proto udp from 192.168.0.0/16 port 5351 to any comment 'Bonjour NAT'
ufw allow proto udp from 172.16.0.0/12 port 5351 to any comment 'Bonjour NAT'

echo "enable lazy firewall"
ufw --force enable
echo ""

# update system
echo ""
echo "*** Update System ***"
apt-mark hold raspberrypi-bootloader
apt-get update -y -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::ftp::Timeout=30
echo "OK - System is now up to date"

# mark setup is done
sed -i "s/^setupStep=.*/setupStep=100/g" /home/admin/raspiblesk.info

##########################
# PROVISIONING SERVICES
##########################

echo "### CHECKING BLESK-API/FRONT STATUS ###" >> ${logFile}
blitzApiInstalled=$(systemctl status bleskapi | grep -c "loaded")
echo "# bleskapi(${bleskapi}) blitzApiInstalled(${blitzApiInstalled})"
if [ "${bleskapi}" != "on" ] && [ ${blitzApiInstalled} -gt 0 ]; then
  /home/admin/_cache.sh set message "Deactivated API/WebUI (as in your config) - please use SSH for further setup"
  sleep 10
else
  /home/admin/_cache.sh set message "Installing Services"
fi

# BLESK WEB SERVICE
echo "Provisioning BLESK WEB SERVICE - run config script" >> ${logFile}
/home/admin/config.scripts/blesk.web.sh https-on >> ${logFile} 2>&1

# deinstall when not explizit 'on' when bleskapi is installed by fatpack
# https://github.com/raspiblesk/raspiblesk/issues/4171#issuecomment-1728302628
if [ "${bleskapi}" != "on" ] && [ ${blitzApiInstalled} -gt 0 ]; then
  echo "blesk_api directory exists & bleskapi is not 'on' - deactivating blesk-api" >> ${logFile}
  /home/admin/config.scripts/blesk.web.api.sh off >> ${logFile} 2>&1
  /home/admin/config.scripts/blesk.web.ui.sh off >> ${logFile} 2>&1
fi
# WebAPI & UI (in case image was not fatpack - but webapi was switched on)
if [ "${bleskapi}" == "on" ] && [ $blitzApiInstalled -eq 0 ]; then
    echo "Provisioning BleskAPI - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup BleskAPI (takes time)"
    /home/admin/config.scripts/blesk.web.api.sh on DEFAULT >> ${logFile} 2>&1
    /home/admin/config.scripts/blesk.web.ui.sh on DEFAULT >> ${logFile} 2>&1
else
    echo "Provisioning BleskAPI - keep default" >> ${logFile}
fi

echo "### RUNNING PROVISIONING SERVICES ###" >> ${logFile}

# Reset Glcoin conf to a clean known-good state BEFORE any module that
# may add entries (tor.network.sh, bonus.electrs.sh, bonus.fulcrum.sh,
# blesk.i2pd.sh). Reinstalls on top of an existing HDD inherit junk left
# in the live conf (duplicate dnsseed, stale onlynet=onion / onlynet=i2p
# / proxy from prior runs). We rewrite from the template and only carry
# over the secret + RAM tuning that downstream provisioning depends on,
# so the daemon reaches a runnable baseline every install.
echo "*** Reset Glcoin Conf from template" >> ${logFile}
glcoinConf="/mnt/hdd/app-data/glcoin/glcoin.conf"
preservedRpcPw=""
preservedDbcache=""
if [ -f "${glcoinConf}" ]; then
  preservedRpcPw=$(grep -m1 '^rpcpassword=' "${glcoinConf}" | cut -d= -f2-)
  preservedDbcache=$(grep -m1 '^dbcache=' "${glcoinConf}" | cut -d= -f2-)
  cp "${glcoinConf}" "${glcoinConf}.bak.$(date +%s)"
fi
install -o glcoin -g glcoin -m 0640 /home/admin/assets/glcoin.conf "${glcoinConf}"
if [ -n "${preservedRpcPw}" ]; then
  sudo -u glcoin sed -i "s|^rpcpassword=.*|rpcpassword=${preservedRpcPw}|" "${glcoinConf}"
fi
if [ -n "${preservedDbcache}" ]; then
  sudo -u glcoin sed -i "s|^dbcache=.*|dbcache=${preservedDbcache}|" "${glcoinConf}"
fi
/home/admin/config.scripts/blesk.data.sh link

# GLCOIN INTERIMS UPDATE
if [ ${#glcoinInterimsUpdate} -gt 0 ]; then
  /home/admin/_cache.sh set message "Glcoin Core update"
  if [ "${glcoinInterimsUpdate}" == "reckless" ]; then
    # recklessly update Glcoin Core to latest release on GitHub
    echo "Provisioning Glcoin Core reckless interims update" >> ${logFile}
    /home/admin/config.scripts/glcoin.update.sh reckless >> ${logFile}
  else
    # when installing the same sd image - this will re-trigger the secure interims update
    # if this a update with a newer RaspiBlesk version .. interims update will be ignored
    # because standard Glcoin Core version is most more up to date
    echo "Provisioning Glcoin Core tested interims update" >> ${logFile}
    /home/admin/config.scripts/glcoin.update.sh tested ${glcoinInterimsUpdate} >> ${logFile}
  fi
else
  echo "Provisioning Glcoin Core interims update - keep default" >> ${logFile}
fi

# LND INTERIMS UPDATE
if [ ${#lndInterimsUpdate} -gt 0 ]; then
  /home/admin/_cache.sh set message "Provisioning LND update"
  if [ "${lndInterimsUpdate}" == "reckless" ]; then
    # recklessly update LND to latest release on GitHub (just for test & dev nodes)
    echo "Provisioning LND reckless interims update" >> ${logFile}
    /home/admin/config.scripts/lnd.update.sh reckless >> ${logFile}
  else
    # when installing the same sd image - this will re-trigger the secure interims update
    # if this a update with a newer RaspiBlesk version .. interims update will be ignored
    # because standard LND version is most more up to date
    echo "Provisioning LND verified interims update" >> ${logFile}
    /home/admin/config.scripts/lnd.update.sh verified ${lndInterimsUpdate} >> ${logFile}
  fi
else
  echo "Provisioning LND interims update - keep default" >> ${logFile}
fi

# CL INTERIMS UPDATE
if [ ${#clInterimsUpdate} -gt 0 ]; then
  /home/admin/_cache.sh set message "Provisioning CL update"
  if [ "${clInterimsUpdate}" == "reckless" ]; then
    # determine the database version # Examples: 216 is CLN v23.02.2 # 219 is CLN v23.05
    clDbVersion=$(sqlite3 /mnt/hdd/app-data/.lightning/glcoin/lightningd.sqlite3 "SELECT version FROM version;")
    if [ ${#clDbVersion} -eq 0 ]; then
      echo "Could not determine the CLN database version - using 0" >> ${logFile}
      clDbVersion=0
    else
      echo "The CLN database version is ${clDbVersion}" >> ${logFile}
    fi
    if [ ${clDbVersion} -lt 217 ]; then
      # even if reckless is set - update to the recommended release
      echo "Provisioning CL verified interims update" >> ${logFile}
      /home/admin/config.scripts/cl.update.sh verified >> ${logFile}
    else # 217 or higher
      # recklessly update CL to latest release on GitHub (just for test & dev nodes)
      echo "Provisioning CL reckless interims update" >> ${logFile}
      /home/admin/config.scripts/cl.update.sh reckless >> ${logFile}
    fi
  else
    # when installing the same sd image - this will re-trigger the secure interims update
    # if this is an update with a newer RaspiBlesk version .. interims update will be ignored
    # because the standard CL version is up to date
    echo "Provisioning CL verified interims update" >> ${logFile}
    /home/admin/config.scripts/cl.update.sh verified ${clInterimsUpdate} >> ${logFile}
  fi
else
  echo "Provisioning CL interims update - keep default" >> ${logFile}
fi

# LND binary install
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ] || [ "${tlnd}" == "on" ] || [ "${slnd}" == "on" ]; then
  # if already installed by fatpack will skip
  echo "Provisioning LND Binary - run config script" >> ${logFile}
  /home/admin/config.scripts/lnd.install.sh install >> ${logFile} 2>&1
else
    echo "Provisioning LND Binary - not active" >> ${logFile}
fi

# LND Mainnet — covers both: lightning=lnd (primary) and lnd=on (secondary)
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
    echo "Provisioning LND Mainnet - run config script" >> ${logFile}
    /home/admin/config.scripts/lnd.install.sh on mainnet >> ${logFile} 2>&1
    /home/admin/config.scripts/lnd.credentials.sh sync mainnet >> $logFile
else
    echo "Provisioning LND Mainnet - not active" >> ${logFile}
fi

# LND Testnet
if [ "${tlnd}" == "on" ]; then
    echo "Provisioning LND Testnet - run config script" >> ${logFile}
    /home/admin/config.scripts/lnd.install.sh on testnet >> ${logFile} 2>&1
    /home/admin/config.scripts/lnd.credentials.sh sync testnet >> $logFile
    systemctl start tlnd >> ${logFile} 2>&1
else
    echo "Provisioning LND Testnet - not active" >> ${logFile}
fi

# LND Signet
if [ "${slnd}" == "on" ]; then
    echo "Provisioning LND Signet - run config script" >> ${logFile}
    /home/admin/config.scripts/lnd.install.sh on signet >> ${logFile} 2>&1
    /home/admin/config.scripts/lnd.credentials.sh sync signet >> $logFile
    systemctl start slnd >> ${logFile} 2>&1
else
  echo "Provisioning LND Signet - not active" >> ${logFile}
fi

# CORE LIGHTNING binary install
if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ] || [ "${tcl}" == "on" ] || [ "${scl}" == "on" ]; then
  # if already installed by fatpack will skip
  echo "Provisioning Core Lightning Binary - run config script" >> ${logFile}
  /home/admin/config.scripts/cl.install.sh install >> ${logFile} 2>&1
else
    echo "Provisioning Core Lightning Binary - not active" >> ${logFile}
fi

# CL Mainnet
if [ "${cl}" == "on" ]; then
    echo "Provisioning CL Mainnet - run config script" >> ${logFile}
    /home/admin/config.scripts/cl.install.sh on mainnet >> ${logFile} 2>&1
else
  echo "Provisioning CL Mainnet - not active" >> ${logFile}
fi

# CL Testnet
if [ "${tcl}" == "on" ]; then
    echo "Provisioning CL Testnet - run config script" >> ${logFile}
    /home/admin/config.scripts/cl.install.sh on testnet >> ${logFile} 2>&1
else
    echo "Provisioning CL Testnet - not active" >> ${logFile}
fi

# CL Signet
if [ "${scl}" == "on" ]; then
    echo "Provisioning CL Signet - run config script" >> ${logFile}
    /home/admin/config.scripts/cl.install.sh on signet >> ${logFile} 2>&1
else
    echo "Provisioning CL Signet - not active" >> ${logFile}
fi


# TOR
if [ "${runBehindTor}" == "on" ]; then
    echo "Provisioning TOR - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup Tor (takes time)"
    /home/admin/config.scripts/tor.network.sh on >> ${logFile} 2>&1
else
    echo "Provisioning Tor - keep default" >> ${logFile}
fi

# DYNAMIC DOMAIN
if [ "${#dynDomain}" -gt 0 ]; then
    echo "Provisioning DYNAMIC DOMAIN - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup DynamicDomain"
    /home/admin/config.scripts/internet.dyndomain.sh on ${dynDomain} ${dynUpdateUrl} >> ${logFile} 2>&1
else
    echo "Provisioning DYNAMIC DOMAIN - keep default" >> ${logFile}
fi

# RTL (LND)
if [ "${rtlWebinterface}" = "on" ]; then
    echo "Provisioning RTL LND - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup RTL LND (takes time)"
    sudo -u admin /home/admin/config.scripts/bonus.rtl.sh on lnd mainnet >> ${logFile} 2>&1
else
    echo "Provisioning RTL LND - keep default" >> ${logFile}
fi

# RTL (CL)
if [ "${crtlWebinterface}" = "on" ]; then
    echo "Provisioning RTL CL - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup RTL CL (takes time)"
    sudo -u admin /home/admin/config.scripts/bonus.rtl.sh on cl mainnet >> ${logFile} 2>&1
else
    echo "Provisioning RTL CL - keep default" >> ${logFile}
fi

# clHTTPplugin
if [ "${clHTTPplugin}" = "on" ]; then
    echo "Provisioning clHTTPplugin - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup clHTTPplugin"
    sudo -u admin /home/admin/config.scripts/cl-plugin.http.sh on >> ${logFile} 2>&1
else
    echo "Provisioning clHTTPplugin - keep default" >> ${logFile}
fi

# clboss
if [ "${clboss}" = "on" ]; then
    echo "Provisioning clboss - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup clboss"
    sudo -u admin /home/admin/config.scripts/cl-plugin.clboss.sh on >> ${logFile} 2>&1
else
    echo "Provisioning clboss - keep default" >> ${logFile}
fi

# clWatchtowerClient
if [ "${clWatchtowerClient}" = "on" ]; then
    echo "Provisioning clWatchtowerClient - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup clWatchtowerClient"
    sudo -u admin /home/admin/config.scripts/cl-plugin.watchtower-client.sh on >> ${logFile} 2>&1
else
    echo "Provisioning clWatchtowerClient - keep default" >> ${logFile}
fi

#GLC RPC EXPLORER
if [ "${GLCRPCexplorer}" = "on" ]; then
  echo "Provisioning GLCRPCexplorer - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup GLCRPCexplorer (takes time)"
  sudo -u admin /home/admin/config.scripts/bonus.glc-rpc-explorer.sh on >> ${logFile} 2>&1
else
  echo "Provisioning GLCRPCexplorer - keep default" >> ${logFile}
fi

#ELECTRS
if [ "${ElectRS}" = "on" ]; then
  echo "Provisioning ElectRS - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup ElectRS (takes time)"
  sudo -u admin /home/admin/config.scripts/bonus.electrs.sh on >> ${logFile} 2>&1
else
  echo "Provisioning ElectRS - keep default" >> ${logFile}
fi

#FULCRUM
if [ "${fulcrum}" = "on" ]; then
  echo "Provisioning Fulcrum - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Fulcrum"
  sudo -u admin /home/admin/config.scripts/bonus.fulcrum.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Fulcrum - keep default" >> ${logFile}
fi

# CUSTOM PORT
echo "Provisioning LND Port" >> ${logFile}
if [ ${#lndPort} -eq 0 ]; then
  lndPort=$(cat /mnt/hdd/app-data/lnd/lnd.conf | grep "^listen=*" | cut -f2 -d':')
fi
if [ ${#lndPort} -gt 0 ]; then
  if [ "${lndPort}" != "9735" ]; then
    echo "User is running custom LND port: ${lndPort}" >> ${logFile}
    /home/admin/config.scripts/lnd.setport.sh ${lndPort} >> ${logFile} 2>&1
  else
    echo "User is running standard LND port: ${lndPort}" >> ${logFile}
  fi
else
  echo "Was not able to get LND port from config." >> ${logFile}
fi

# DNS Server
if [ ${#dnsServer} -gt 0 ]; then
    echo "Provisioning DNS Server - Setting DNS Server" >> ${logFile}
    /home/admin/config.scripts/internet.dns.sh ${dnsServer} >> ${logFile} 2>&1
else
    echo "Provisioning DNS Server - keep default" >> ${logFile}
fi

# CHANTOOLS
if [ "${chantools}" == "on" ]; then
    echo "Provisioning chantools - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup Chantools"
    /home/admin/config.scripts/bonus.chantools.sh on >> ${logFile} 2>&1
else
    echo "Provisioning chantools - keep default" >> ${logFile}
fi

# SSH TUNNEL
if [ "${#sshtunnel}" -gt 0 ]; then
    echo "Provisioning SSH Tunnel - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup SSH Tunnel"
    /home/admin/config.scripts/internet.sshtunnel.py restore ${sshtunnel} >> ${logFile} 2>&1
else
    echo "Provisioning SSH Tunnel - not active" >> ${logFile}
fi

# ZEROTIER
if [ "${#zerotier}" -gt 0 ] && [ "${zerotier}" != "off" ]; then
    echo "Provisioning ZeroTier - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup ZeroTier"
    /home/admin/config.scripts/internet.zerotier.sh on ${zerotier} >> ${logFile} 2>&1
else
    echo "Provisioning ZeroTier - not active" >> ${logFile}
fi

# LCD ROTATE
if [ ${#lcdrotate} -eq 0 ]; then
  # when upgrading from an old raspiblesk - enforce lcdrotate = 0
  lcdrotate=0
fi
if [ "${lcdrotate}" == "0" ]; then
  echo "Provisioning LCD rotate - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "LCD Rotate"
  /home/admin/config.scripts/blesk.display.sh rotate ${lcdrotate} >> ${logFile} 2>&1
else
  echo "Provisioning LCD rotate - not needed, keep default rotate on" >> ${logFile}
fi

# TOUCHSCREEN - deactivated see https://github.com/raspiblesk/raspiblesk/pull/4609#issuecomment-2144406124
# if [ "${#touchscreen}" -gt 0 ]; then
#     echo "Provisioning Touchscreen - run config script" >> ${logFile}
#     /home/admin/_cache.sh set message "Setup Touchscreen"
#     /home/admin/config.scripts/blesk.touchscreen.sh ${touchscreen} >> ${logFile} 2>&1
# else
#     echo "Provisioning Touchscreen - not active" >> ${logFile}
# fi

# UPS
if [ "${#ups}" -gt 0 ]; then
    echo "Provisioning UPS - run config script" >> ${logFile}
    /home/admin/_cache.sh set message "Setup UPS"
    /home/admin/config.scripts/blesk.ups.sh on ${ups} >> ${logFile} 2>&1
else
    echo "Provisioning UPS - not active" >> ${logFile}
fi

# LNbits
if [ "${LNBits}" = "on" ]; then
  if [ "${LNBitsFunding}" == "" ]; then
    LNBitsFunding="lnd"
  fi
  echo "Provisioning LNbits (${LNBitsFunding}) - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup LNbits (${LNBitsFunding})"
  sudo -u admin /home/admin/config.scripts/bonus.lnbits.sh on ${LNBitsFunding} >> ${logFile} 2>&1
else
  echo "Provisioning LNbits - keep default" >> ${logFile}
fi

# JoinMarket
if [ "${joinmarket}" = "on" ]; then
  echo "Provisioning JoinMarket - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup JoinMarket"
  /home/admin/config.scripts/bonus.joinmarket.sh on >> ${logFile} 2>&1
else
  echo "Provisioning JoinMarket - keep default" >> ${logFile}
fi

# Jam
if [ "${jam}" = "on" ]; then
  echo "Provisioning Jam - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Jam"
  sudo /home/admin/config.scripts/bonus.jam.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Jam - keep default" >> ${logFile}
fi

# Specter
if [ "${specter}" = "on" ]; then
  echo "Provisioning Specter - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Specter"
  sudo -u admin /home/admin/config.scripts/bonus.specter.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Specter - keep default" >> ${logFile}
fi

# BOS
if [ "${bos}" = "on" ]; then
  echo "Provisioning Balance of Satoshis - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Balance of Satoshis"
  sudo -u admin /home/admin/config.scripts/bonus.bos.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Balance of Satoshis - keep default" >> ${logFile}
fi

# thunderhub
if [ "${thunderhub}" = "on" ]; then
  echo "Provisioning ThunderHub - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup ThunderHub"
  sudo -u admin /home/admin/config.scripts/bonus.thunderhub.sh on >> ${logFile} 2>&1
else
  echo "Provisioning ThunderHub - keep default" >> ${logFile}
fi

# mempool space
if [ "${mempoolExplorer}" = "on" ]; then
  echo "Provisioning MempoolSpace - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Mempool Space (can take 30–90 min)"
  if sudo -u admin /home/admin/config.scripts/bonus.mempool.sh on >> ${logFile} 2>&1; then
    echo "OK MEMPOOL" >> ${logFile}
  else
    echo "# WARNING: Mempool install failed (exit $?) — continuing without it" >> ${logFile}
    echo "# Node core functionality is unaffected." >> ${logFile}
    echo "# Re-run later: sudo /home/admin/config.scripts/bonus.mempool.sh on" >> ${logFile}
    /home/admin/_cache.sh set message "Mempool failed — core node OK, continuing"
  fi
else
  echo "Provisioning Mempool Explorer - keep default" >> ${logFile}
fi

# Glcoin Knots
if [ "${knots}" = "on" ]; then
  echo "Provisioning Glcoin Knots - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Glcoin Knots"
  sudo -u admin /home/admin/config.scripts/bonus.knots.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Glcoin Knots - keep default" >> ${logFile}
fi

# letsencrypt
if [ "${letsencrypt}" = "on" ]; then
  echo "Provisioning letsencrypt - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup letsencrypt"
  sudo -u admin /home/admin/config.scripts/internet.letsencrypt.sh on >> ${logFile} 2>&1
else
  echo "Provisioning letsencrypt - keep default" >> ${logFile}
fi

# kindle-display
if [ "${kindleDisplay}" = "on" ]; then
  echo "Provisioning kindle-display - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup kindle-display"
  sudo -u admin /home/admin/config.scripts/bonus.kindle-display.sh on >> ${logFile} 2>&1
else
  echo "Provisioning kindle-display - keep default" >> ${logFile}
fi

# pyblock
if [ "${pyblock}" = "on" ]; then
  echo "Provisioning pyblock - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup pyblock"
  sudo -u admin /home/admin/config.scripts/bonus.pyblock.sh on >> ${logFile} 2>&1
else
  echo "Provisioning pyblock - keep default" >> ${logFile}
fi

# stacking-sats-kraken
if [ "${stackingSatsKraken}" = "on" ]; then
  echo "Provisioning Stacking Sats Kraken - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Stacking Sats Kraken"
  sudo -u admin /home/admin/config.scripts/bonus.stacking-sats-kraken.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Stacking Sats Kraken - keep default" >> ${logFile}
fi

# lit (make sure to be installed after RTL)
if [ "${lit}" = "on" ]; then
  echo "Provisioning LIT - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup LIT"
  sudo -u admin /home/admin/config.scripts/bonus.lit.sh on >> ${logFile} 2>&1
else
  echo "Provisioning LIT - keep default" >> ${logFile}
fi

# labelbase
if [ "${labelbase}" = "on" ]; then
  echo "Provisioning Labelbase - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Labelbase"
  sudo -u admin /home/admin/config.scripts/bonus.labelbase.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Labelbase - keep default" >> ${logFile}
fi

# lndg
if [ "${lndg}" = "on" ]; then
  echo "Provisioning LNDg - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup LNDg"
  sudo -u admin /home/admin/config.scripts/bonus.lndg.sh on >> ${logFile} 2>&1
else
  echo "Provisioning LNDg - keep default" >> ${logFile}
fi

# helipad
if [ "${helipad}" = "on" ]; then
  echo "Helipad - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Helipad"
  sudo -u admin /home/admin/config.scripts/bonus.helipad.sh on >> ${logFile} 2>&1
else
  echo "Helipad - keep default" >> ${logFile}
fi

# circuitbreaker
if [ "${circuitbreaker}" = "on" ]; then
  echo "Provisioning CircuitBreaker - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup CircuitBreaker"
  sudo -u admin /home/admin/config.scripts/bonus.circuitbreaker.sh on >> ${logFile} 2>&1
else
  echo "Provisioning CircuitBreaker - keep default" >> ${logFile}
fi

# squeaknode
if [ "${squeaknode}" = "on" ]; then
  echo "Provisioning Squeaknode - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Squeaknode"
  sudo -u admin /home/admin/config.scripts/bonus.squeaknode.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Squeaknode - keep default" >> ${logFile}
fi

# LightningTipBot
if [ "${lightningtipbot}" = "on" ]; then
  echo "Provisioning LightningTipBot - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup LightningTipBot"
  sudo -u admin /home/admin/config.scripts/bonus.lightningtipbot.sh on >> ${logFile} 2>&1
else
  echo "Provisioning LightningTipBot - keep default" >> ${logFile}
fi

# FinTS
if [ "${fints}" = "on" ]; then
  echo "Provisioning FinTS - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup FinTS"
  sudo -u admin /home/admin/config.scripts/bonus.fints.sh on >> ${logFile} 2>&1
else
  echo "Provisioning FinTS - keep default" >> ${logFile}
fi

# Tailscale
if [ "${tailscale}" = "on" ]; then
  echo "Provisioning Tailscale - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Tailscale"
  sudo -u admin /home/admin/config.scripts/internet.tailscale.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Tailscale - keep default" >> ${logFile}
fi

# Telegraf
if [ "${telegraf}" = "on" ]; then
  echo "Provisioning Telegraf - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Telegraf"
  sudo -u admin /home/admin/config.scripts/bonus.telegraf.sh on >> ${logFile} 2>&1
else
  echo "Provisioning Telegraf - keep default" >> ${logFile}
fi

# GlcoinMiner
if [ "${glcoinMiner}" = "on" ]; then
  echo "Provisioning GlcoinMiner - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup Glcoin Miner"
  sudo -u admin /home/admin/config.scripts/bonus.glcoin-miner.sh on >> ${logFile} 2>&1
else
  echo "Provisioning GlcoinMiner - keep default" >> ${logFile}
fi

# AlbyHub
if [ "${albyhub}" = "on" ]; then
  echo "Provisioning AlbyHub - run config script" >> ${logFile}
  /home/admin/_cache.sh set message "Setup AlbyHub"
  sudo -u admin /home/admin/config.scripts/bonus.albyhub.sh on >> ${logFile} 2>&1
else
  echo "Provisioning AlbyHub - keep default" >> ${logFile}
fi

# custom install script from user
customInstallAvailable=$(ls /mnt/hdd/app-data/custom-installs.sh 2>/dev/null | grep -c "custom-installs.sh")
if [ ${customInstallAvailable} -gt 0 ]; then
  echo "Running the custom install script .." >> ${logFile}
  /home/admin/_cache.sh set message "Running Custom Install Script"
  # copy script over to admin (in case HDD is not allowing exec)
  cp -av /mnt/hdd/app-data/custom-installs.sh /home/admin/custom-installs.sh >> ${logFile}
  # make sure script is executable
  chmod +x /home/admin/custom-installs.sh >> ${logFile}
  # run it & delete it again
  /home/admin/custom-installs.sh >> ${logFile}
  rm /home/admin/custom-installs.sh >> ${logFile}
  echo "Done" >> ${logFile}
else
  echo "No custom install script ... adding the placeholder." >> ${logFile}
  cp /home/admin/assets/custom-installs.sh /mnt/hdd/app-data/custom-installs.sh
fi

# replay backup LND conf & tlscerts
# https://github.com/rootzoll/raspiblesk/issues/324
echo "" >> ${logFile}
echo "*** Replay backup of LND conf/tls" >> ${logFile}
if [ -d "/var/cache/raspiblesk/tls_backup" ]; then

  echo "Copying TLS ..." >> ${logFile}
  cp /var/cache/raspiblesk/tls_backup/tls.cert /mnt/hdd/app-data/lnd/tls.cert >> ${logFile} 2>&1
  cp /var/cache/raspiblesk/tls_backup/tls.key /mnt/hdd/app-data/lnd/tls.key >> ${logFile} 2>&1
  chown -R glcoin:glcoin /mnt/hdd/app-data/lnd >> ${logFile} 2>&1
  echo "On next final restart admin creds will be updated by _bootstrap.sh" >> ${logFile}

  echo "DONE" >> ${logFile}
else
  echo "No BackupDir so skipping that step." >> ${logFile}
fi
echo "" >> ${logFile}

# I2P daemon: install apt package only — activation is opt-in via
# `blesk.i2pd.sh on`. Forcing it during provision used to drop
# `onlynet=i2p` into glcoin.conf, which made the node unreachable on
# a clearnet box.
echo "Install i2pd (not activating)" >> ${logFile}
/home/admin/_cache.sh set message "i2pd setup"
/home/admin/config.scripts/blesk.i2pd.sh install >> ${logFile}

# clean up raspiblesk config from old settings
sed -i '/^autoPilot=/d' /mnt/hdd/app-data/raspiblesk.conf
sed -i '/^lndKeysend=/d' /mnt/hdd/app-data/raspiblesk.conf

# signal setup done
/home/admin/_cache.sh set message "Setup Done"

# set the local network hostname (just if set in config - will not be set anymore by default in newer version)
# have at the end - see https://github.com/rootzoll/raspiblesk/issues/462
# see also https://github.com/rootzoll/raspiblesk/issues/819
if [ ${#hostname} -gt 0 ]; then
  hostnameSanatized=$(echo "${hostname}"| tr -dc '[:alnum:]\n\r')
  if [ ${#hostnameSanatized} -gt 0 ]; then
    if [ "${setnetworkname}" == "1" ]; then
      echo "Setting new network hostname '$hostnameSanatized'" >> ${logFile}
      if [ "${baseimage}" == "raspios_arm64" ]; then
         raspi-config nonint do_hostname ${hostnameSanatized} >> ${logFile} 2>&1
      else
         hostnameCurrent=$(hostname)
         sed -i "s/${hostnameCurrent}/${hostnameSanatized}/g" /etc/hostname 2>&1
         sed -i "s/${hostnameCurrent}/${hostnameSanatized}/g" /etc/hosts 2>&1
      fi
    else
      echo "Not setting local network hostname" >> ${logFile}
    fi
  else
    echo "WARNING: hostname in raspiblesk.conf contains just special chars" >> ${logFile}
  fi
else
  echo "No hostname set." >> ${logFile}
fi

# PERMANENT MOUNT OF HDD/SSD
# always at the end, because data drives will be just available again after a reboot
echo "Prepare fstab for permanent data drive mounting .." >> ${logFile}
# get info on data drive
/home/admin/config.scripts/blesk.data.sh mount >> ${logFile}

# MAKE SURE SERVICES ARE RUNNING
echo "Make sure main services are running .." >> ${logFile}
systemctl start ${network}d
if [ "${lightning}" == "lnd" ];then
  systemctl start lnd
  sleep 10
  # set password c if given in flag from migration prep
  passwordFlagExists=$(ls /mnt/hdd/passwordc.flag | grep -c "passwordc.flag")
  if [ "${passwordFlagExists}" == "1" ]; then
    echo "Found /mnt/hdd/passwordc.flag .. changing password" >> ${logFile}
    oldPasswordC=$(cat /mnt/hdd/passwordc.flag)
    # Pipe both passwords as JSON via stdin so they don't appear in
    # /proc/PID/cmdline. Previous form leaked old + new wallet passwords.
    _stdin_json=$(oldPwC="${oldPasswordC}" newPwC="${passwordC}" \
      python3 -c 'import json,os;print(json.dumps({"wallet_password":os.environ["oldPwC"],"wallet_password_new":os.environ["newPwC"]}))')
    printf '%s' "${_stdin_json}" | /home/admin/config.scripts/lnd.initwallet.py change-password mainnet --stdin >> ${logFile}
    unset _stdin_json oldPasswordC
    shred -u /mnt/hdd/passwordc.flag
  else
    echo "No /mnt/hdd/passwordc.flag" >> ${logFile}
  fi
elif [ "${lightning}" == "cl" ];then
  systemctl start lightningd
fi

echo "DONE - Give raspi some cool off time after hard building .... 5 secs sleep" >> ${logFile}
sleep 5

echo "END Provisioning" >> ${logFile}
exit 0
