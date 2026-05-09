#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "monitor and troubleshot the glcoin network"
 echo "glcoin.monitor.sh [mainnet|testnet|signet] status"
 echo "glcoin.monitor.sh [mainnet|testnet|signet] info"
 echo "glcoin.monitor.sh [mainnet|testnet|signet] mempool"
 echo "glcoin.monitor.sh [mainnet|testnet|signet] network"
 echo "glcoin.monitor.sh [mainnet] peer-kickstart [ipv4|ipv6|tor|i2p|auto]"
 echo "glcoin.monitor.sh [mainnet] peer-disconnectall"
 exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

# set based on network type
if [ "$1" == "mainnet" ]; then
  glcoincli_alias="/usr/local/bin/glcoin-cli -datadir=/home/glcoin/.glcoin -rpcport=1617"
  service_alias="glcoind"
elif [ "$1" == "testnet" ]; then
  glcoincli_alias="/usr/local/bin/glcoin-cli -datadir=/home/glcoin/.glcoin -rpcport=11617"
  service_alias="tglcoind"
elif [ "$1" == "signet" ]; then
  glcoincli_alias="/usr/local/bin/glcoin-cli -datadir=/home/glcoin/.glcoin -rpcport=31617"
  service_alias="sglcoind"
else
  echo "error='not supported net'"
  exit 1
fi

######################################################
# STATUS
# check general status info
######################################################

if [ "$2" = "status" ]; then

  glc_version=$($glcoincli_alias -version 2>/dev/null | head -1 | cut -d ' ' -f6)
  glc_running=$(systemctl status $service_alias 2>/dev/null | grep -c "active (running)")
  glc_ready="0"
  glc_online="0"
  glc_error_short=""
  glc_error_full=""

  if [ "${glc_running}" != "0" ]; then
    glc_running="1"

    # test connection - record win & fail info
    randStr=$(echo "$RANDOM")
    rm /var/cache/raspiblesk/.glcoind-${randStr}.out 2>/dev/null
    rm /var/cache/raspiblesk/.glcoind-${randStr}.error 2>/dev/null
    touch /var/cache/raspiblesk/.glcoind-${randStr}.out
    touch /var/cache/raspiblesk/.glcoind-${randStr}.error
    $glcoincli_alias getnetworkinfo 1>/var/cache/raspiblesk/.glcoind-${randStr}.out 2>/var/cache/raspiblesk/.glcoind-${randStr}.error
    winData=$(cat /var/cache/raspiblesk/.glcoind-${randStr}.out 2>/dev/null)
    failData=$(cat /var/cache/raspiblesk/.glcoind-${randStr}.error 2>/dev/null)
    rm /var/cache/raspiblesk/.glcoind-${randStr}.out
    rm /var/cache/raspiblesk/.glcoind-${randStr}.error

    # check for errors
    if [ "${failData}" != "" ]; then
      glc_ready="0"
      glc_error_short=$(echo ${failData/error*:/} | sed 's/[^a-zA-Z0-9 ]//g')
      glc_error_full=$(echo ${failData} | tr -d "'" | tr -d '"')
      glc_ready="0"

    # check results if proof for online
    else
      glc_ready="1"
      connections=$( echo "${winData}" | grep "connections\"" | tr -cd '[[:digit:]]')
      if [ "${connections}" != "" ] && [ "${connections}" != "0" ]; then
        glc_online="1"
      fi
    fi

  fi 

  # print results
  echo "glc_version='${glc_version}'"
  echo "glc_running='${glc_running}'"
  echo "glc_ready='${glc_ready}'"
  echo "glc_online='${glc_online}'"
  echo "glc_error_short='${glc_error_short}'"
  echo "glc_error_full='${glc_error_full}'"

  exit 0
fi   

######################################################
# NETWORK
######################################################

if [ "$2" = "network" ]; then

  # get data
  glc_running=$(systemctl status $service_alias 2>/dev/null | grep -c "active (running)")
  getnetworkinfo=$($glcoincli_alias getnetworkinfo 2>/dev/null)
  if [ "${getnetworkinfo}" == "" ]; then
    echo "error='no network data'"
    exit 1
  fi
  getpeerinfo=$($glcoincli_alias getpeerinfo 2>/dev/null)
  if [ "${getpeerinfo}" == "" ]; then
    echo "error='no peer data'"
    exit 1
  fi  

  # parse data
  glc_peers=$(echo "${getnetworkinfo}" | grep "connections\"" | tr -cd '[[:digit:]]')
  glc_address=$(echo ${getnetworkinfo} | jq -r '.localaddresses [0] .address')
  glc_port=$(echo "${getnetworkinfo}" | jq -r '.localaddresses [0] .port')
  glc_peers_onion=$(echo "${getpeerinfo}" | grep -c "network\": \"onion")
  glc_peers_i2p=$(echo "${getpeerinfo}" | grep -c "network\": \"i2p")

  # print data
  echo "glc_running='${glc_running}'"
  echo "glc_peers='${glc_peers}'"
  echo "glc_peers_onion='${glc_peers_onion}'"
  echo "glc_peers_i2p='${glc_peers_i2p}'"
  echo "glc_address='${glc_address}'"
  echo "glc_port='${glc_port}'"
  exit 0
  
fi

######################################################
# INFO
######################################################

if [ "$2" = "info" ]; then

  # get data
  blockchaininfo=$($glcoincli_alias getblockchaininfo 2>/dev/null)
  if [ "${blockchaininfo}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

  subfolder=""
  if [ "$1" == "testnet" ]; then
    subfolder="testnet3/"
  fi
  if [ "$1" == "signet" ]; then
    subfolder="signet/"
  fi

  glc_blocks_data_kb=$(du -s /mnt/hdd/glcoin/${subfolder}blocks | cut -f1)
  if [ "${glc_blocks_data_kb}" == "" ]; then
   glc_blocks_data_kb="0"
  fi

  # parse data
  glc_blocks_headers=$(echo "${blockchaininfo}" | jq -r '.headers')
  glc_blocks_verified=$(echo "${blockchaininfo}" | jq -r '.blocks')
  glc_blocks_behind=$((${glc_blocks_headers} - ${glc_blocks_verified}))
  glc_sync_initialblockdownload=$(echo "${blockchaininfo}" | jq -r '.initialblockdownload' | grep -c 'true')
  glc_sync_progress=$(echo "${blockchaininfo}" | jq -r '.verificationprogress')
  if [[ "${glc_sync_progress}" == *"e-"* ]]; then
    # is still very small - round up to 0.01%
    glc_sync_percentage="0.01"
  elif (( $(awk 'BEGIN { print( '${glc_sync_progress}'<0.99995 ) }') )); then
    # #3620 prevent displaying 100.00%, although incorrect because of rounding
    glc_sync_percentage="${glc_sync_progress:2:2}.${glc_sync_progress:4:2}"
    # remove trailing zero if present (just first one)
    glc_sync_percentage="${glc_sync_percentage#0}"
  elif [ "${glc_blocks_headers}" != "" ] && [ "${glc_blocks_headers}" == "${glc_blocks_verified}" ]; then
    glc_sync_percentage="100.00"
  else
    glc_sync_percentage="99.99"
  fi

  # determine if synced (tolerate falling 1 block behind)
  # and be sure that initial blockdownload is done
  glc_synced=0
  if [ "${glc_sync_initialblockdownload}" == "0" ] && [ ${glc_blocks_behind} -lt 2 ]; then
    glc_synced=1
  fi

  # print data
  echo "glc_synced='${glc_synced}'"
  echo "glc_blocks_headers='${glc_blocks_headers}'"
  echo "glc_blocks_verified='${glc_blocks_verified}'"
  echo "glc_blocks_behind='${glc_blocks_behind}'"
  echo "glc_blocks_data_kb='${glc_blocks_data_kb}'"
  echo "glc_sync_progress='${glc_sync_progress}'"
  echo "glc_sync_percentage='${glc_sync_percentage//[^0-9\..]/}'"
  echo "glc_sync_initialblockdownload='${glc_sync_initialblockdownload}'"
  exit 0
  
fi

######################################################
# MEMPOOL
######################################################

if [ "$2" = "mempool" ]; then

  # get data
  mempoolinfo=$($glcoincli_alias getmempoolinfo 2>/dev/null)
  if [ "${mempoolinfo}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

  # parse data
  glc_mempool_transactions=$(echo "${mempoolinfo}" | jq -r '.size')

  # print data
  echo "glc_mempool_transactions=${glc_mempool_transactions}"
  exit 0
  
fi

###################
# PEER KICK START
###################

if [ "$2" = "peer-kickstart" ]; then

  # check calling only for mainnet
  if [ "$1" != "mainnet" ]; then 
    echo "error='only available for mainnet yet'"
    exit 1
  fi

  bitnodesRawData1=$(sudo -u admin cat /home/admin/fallback.bitnodes.nodes)
  if [ ${#bitnodesRawData1} -lt 100 ]; then
    echo "error='no valid data from bitnodes.io'"
    exit 1
  fi

  bitnodesRawData2=$(sudo -u admin cat /home/admin/fallback.glcoin.nodes)
  if [ ${#bitnodesRawData2} -lt 100 ]; then
    echo "error='no valid data from glcoin core'"
    exit 1
  fi

  # determine which address to choose
  addressFormat="$3"
  # set default to auto
  if [ "${addressFormat}" == "" ]; then
    addressFormat="auto"
  fi
  # check valid value
  if [ "${addressFormat}" != "ipv4" ] && [ "${addressFormat}" != "ipv6" ] && [ "${addressFormat}" != "tor" ] && [ "${addressFormat}" != "i2p" ] && [ "${addressFormat}" != "auto" ]; then
    echo "error='invalid address type'"
    exit 1
  fi
  # if auto then determine whats running
  if [ "${addressFormat}" == "auto" ]; then
    if [ "$(cat /mnt/hdd/app-data/raspiblesk.conf | grep -c "^runBehindTor=on")" != "0" ]; then
      addressFormat="tor"
    else
      source <(/home/admin/config.scripts/internet.sh status global)
      if [ "${ipv6}" == "off" ]; then
        addressFormat="ipv4"
      else
        addressFormat="ipv6"
      fi
    fi
  fi
  echo "addressFormat='${addressFormat}'"

  # filter raw data for node addresses based on what kind of connection is running
  if [ "${addressFormat}" == "tor" ]; then
    # get Tor nodes (v3)
    nodeList=$(echo "${bitnodesRawData1}" | grep -o '[0-9a-z]\{32,56\}\.onion')
  elif [ "${addressFormat}" == "ipv4" ]; then
    # get IPv4 nodes
    nodeList=$(echo "${bitnodesRawData1}" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\:[0-9]\{3,5\}')
  elif [ "${addressFormat}" == "ipv6" ]; then
    # get IPv6 nodes
    nodeList=$(echo "${bitnodesRawData1}" | grep -o '\[.\{5,45\}\]\:[0-9]\{3,5\}')
  elif [ "${addressFormat}" == "i2p" ]; then
    # get I2P nodes (only in fallbacklist from glcoin core)
    nodeList=$(echo "${bitnodesRawData2}" | grep -o '[0-9,a-z]\{32,64\}\.b32\.i2p\:[0-9]\{1,5\}')
  else
    # invalid address
    echo "error='invalid address format'"
    exit 1
  fi
  #echo "${nodeList}"
  nodesAvailable=$(echo "${nodeList}" | wc -l)
  echo "nodesAvailable=${nodesAvailable}"
  if [ "${nodesAvailable}" == "0" ]; then
    echo "error='no nodes available'"
    exit 1
  fi

  # pick random node from list
  randomLineNumber=$((1 + RANDOM % ${nodesAvailable}))
  echo "randomNumber=${randomLineNumber}"
  nodeAddress=$(echo "${nodeList}" | sed -n "${randomLineNumber}p")
  if [ "${nodeAddress}" == "" ]; then
    # if random pick fails pick first line
    nodeAddress=$(echo "${nodeList}" | sed -n "1p")
  fi
  if [ "${nodeAddress}" == "" ]; then
    echo "error='selecting node from list failed'"
    exit 1
  fi
  echo "newpeer='${nodeAddress}'"

  # kick start node with 
  $glcoincli_alias addnode "${nodeAddress}" "onetry" 1>/dev/null
  echo "exitcode=$?"

  exit 0
fi

###################
# DISCONNECT ALL PEERS
# for testing peer kick-start
###################
if [ "$2" = "peer-disconnectall" ]; then

  # check calling only for mainnet
  if [ "$1" != "mainnet" ]; then 
    echo "error='only available for mainnet yet'"
    exit 1
  fi

  # get all peer id and disconnect them
  $glcoincli_alias getpeerinfo | grep '"addr": "' | while read line 
  do
    peerID=$(echo $line | cut -d '"' -f4)
    echo "# disconnecting peer with ID: ${peerID}"
    $glcoincli_alias disconnectnode ${peerID}
  done

  echo "#### FINAL PEER INFO FROM GLCOIND"
  $glcoincli_alias getpeerinfo
  exit 0
fi

echo "FAIL - Unknown Parameter $2"
exit 1
