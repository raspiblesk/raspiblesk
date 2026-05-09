#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# Usage:"
  echo "# source <(/home/admin/config.scripts/network.aliases.sh getvars <lnd|cl> <mainnet|testnet|signet>)"
  echo "# if no values given uses the default values from the raspiblesk.conf"
  echo
  echo "# chain is: main | test ; from raspiblesk.conf or raspiblesk.info or defaults to main"
  echo
  echo "# LNTYPE is: lnd | cl ; default: lnd"
  echo "# typeprefix is: "" | c"
  echo
  echo "# CHAIN is: mainnet | testnet | signet"
  echo "# netprefix is:  "" | t | s"
  echo "# portprefix is: "" | 1 | 3"
  echo "# CLNETWORK is: glcoin / signet / testnet"
  exit 1
fi

if [ "$1" = getvars ]; then

  source /home/admin/raspiblesk.info
  source /mnt/hdd/app-data/raspiblesk.conf 2>/dev/null

  if [ ${#network} -eq 0 ]; then
    network=glcoin
  fi

  # LNTYPE is: lnd | cl
  if [ $# -gt 1 ]; then
    LNTYPE=$2
  else
    if [ ${#lightning} -gt 0 ]; then
      LNTYPE=${lightning}
    else
      LNTYPE=lnd
    fi
  fi
  echo "LNTYPE=${LNTYPE}"

  # from raspiblesk.conf or raspiblesk.info or defaults to main
  if [ ${#chain} -eq 0 ]; then
    chain=main
  fi
  # CHAIN is: signet | testnet | mainnet
  if [ $# -gt 2 ] && { [ "$3" = "signet" ] || [ "$3" = "testnet" ] || [ "$3" = "mainnet" ]; }; then
    CHAIN=$3
    chain=${CHAIN::-3}
  else
    CHAIN=${chain}net
  fi
  echo "CHAIN=${CHAIN}"
  echo "chain=${chain}"

  # netprefix is:     "" |  t | s
  # portprefix is:    "" |  1 | 3
  # L2rpcportmod is:   0 |  1 | 3
  # glcoinZmqBlock:  21617 | 31617 | 41617
  # glcoinZmqTx:     21618 | 31618 | 41618
  if [ "${chain}" == "main" ]; then
    netprefix=""
    L2rpcportmod=0
    portprefix=""
    glcoinZmqBlock=21617
    glcoinZmqTx=21618
  elif [ "${chain}" == "test" ]; then
    netprefix="t"
    L2rpcportmod=1
    portprefix=1
    glcoinZmqBlock=31617
    glcoinZmqTx=31618
  elif [ "${chain}" == "sig" ]; then
    netprefix="s"
    L2rpcportmod=3
    portprefix=3
    glcoinZmqBlock=41617
    glcoinZmqTx=41618
  fi
  echo "netprefix=${netprefix}"
  echo "portprefix=${portprefix}"
  echo "L2rpcportmod=${L2rpcportmod}"
  echo "glcoinZmqBlock=${glcoinZmqBlock}"
  echo "glcoinZmqTx=${glcoinZmqTx}"

  if [ "${LNTYPE}" == "cl" ]; then
    # CLNETWORK is: glcoin / signet / testnet
    if [ "${chain}" == "main" ]; then
      CLNETWORK=${network}
    else
      CLNETWORK=${chain}net
    fi
    echo "CLNETWORK=${CLNETWORK}"

    # CLCONF is the path to the config
    if [ "${CLNETWORK}" == "glcoin" ]; then
      CLCONF="/home/glcoin/.lightning/config"
    else
      CLCONF="/home/glcoin/.lightning/${CLNETWORK}/config"
    fi
    echo "CLCONF=${CLCONF}"
    typeprefix=c

    echo "lightningcli_alias=\"sudo -u glcoin /usr/local/bin/lightning-cli --conf=${CLCONF}\""
  fi

  # typeprefix is: "" | c
  if [ "${LNTYPE}" == "lnd" ]; then
    typeprefix=''
    lndConfFile="/mnt/hdd/app-data/lnd/${netprefix}lnd.conf"
  fi
  echo "typeprefix=${typeprefix}"
  echo "lndConfFile=${lndConfFile}"

  # instead of all
  # sudo -u glcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net
  echo "lncli_alias=\"sudo -u glcoin /usr/local/bin/lncli -n=${chain}net --rpcserver localhost:1${L2rpcportmod}009\""
  # sudo -u glcoin ${network}-cli -datadir=/home/glcoin/.${network}
  echo "glcoincli_alias=\"/usr/local/bin/${network}-cli -datadir=/home/glcoin/.${network} -rpcport=${portprefix}1617\""

fi

#TODO
# where /lnd.conf is not changed to /${netprefix}lnd.conf the service remains for mainnet only
