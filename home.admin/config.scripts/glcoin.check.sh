#!/bin/bash

# command info
if [ $# -eq 0 ] || [[ "$1" =~ ^(-h|--help|-help)$ ]]; then
  echo "# glcoin.check.sh prestart [mainnet|testnet|signet]"
  exit 1
fi

######################################################################
# PRESTART
# is executed by systemd glcoind services everytime before glcoin is started
# so it tries to make sure the config is in valid shape
######################################################################

# check/repair lnd config before starting
if [ "$1" == "prestart" ]; then
  echo "### RUNNING glcoin.check.sh prestart"

  # check correct user
  if [ "$(id -un 2>/dev/null)" != "glcoin" ]; then
    echo "# FAIL: run as user 'glcoin'"
    exit 1
  fi

  # check correct parameter
  if ! [[ "$2" =~ ^(mainnet|testnet|signet)$ ]]; then
    echo "# FAIL: missing/wrong parameter"
    exit 1
  fi

  CHAIN="$2"

  ##### DIRECTORY PERMISSIONS #####

  /bin/chgrp glcoin /mnt/hdd/glcoin

  ##### CLEAN UP #####

  # all lines with just spaces to empty lines
  sed -i 's/^[[:space:]]*$//g' /mnt/hdd/app-data/glcoin/glcoin.conf
  # all double empty lines to single empty lines
  sed -i '/^$/N;/^\n$/D' /mnt/hdd/app-data/glcoin/glcoin.conf

  ##### CHECK/SET CONFIG VALUES #####
  case "${CHAIN}" in
    mainnet)
      glcoinlog_entry="main.debuglogfile"
      glcoinlog_path="/mnt/hdd/app-data/glcoin/debug.log"
      glcoin_zmq_prefix="main"
      glcoin_zmq_block="21617"
      glcoin_zmq_tx="21618"
      ;;
    testnet)
      glcoinlog_entry="test.debuglogfile"
      glcoinlog_path="/mnt/hdd/app-data/glcoin/testnet3/debug.log"
      glcoin_zmq_prefix="test"
      glcoin_zmq_block="31617"
      glcoin_zmq_tx="31618"
      ;;
    signet)
      glcoinlog_entry="signet.debuglogfile"
      glcoinlog_path="/mnt/hdd/app-data/glcoin/signet/debug.log"
      glcoin_zmq_prefix="signet"
      glcoin_zmq_block="41617"
      glcoin_zmq_tx="41618"
      ;;
  esac

  # make sure entry exists
  echo "# make sure entry(${glcoinlog_entry}) exists"
  if ! grep -q "^${glcoinlog_entry}=" /mnt/hdd/app-data/glcoin/glcoin.conf; then
    echo "${glcoinlog_entry}=${glcoinlog_path}" >> /mnt/hdd/app-data/glcoin/glcoin.conf
  fi

  # delete any debuglogfile in app-storage and link to new location in app-data
  rm -f /mnt/hdd/app-storage/glcoin/debug.log
  ln -s /mnt/hdd/app-data/glcoin/debug.log /mnt/hdd/app-storage/glcoin/debug.log

  # make sure entry has the correct value
  echo "# make sure entry(${glcoinlog_entry}) has the correct value(${glcoinlog_path})"
  sed -i "s|^${glcoinlog_entry}=.*|${glcoinlog_entry}=${glcoinlog_path}|g" /mnt/hdd/app-data/glcoin/glcoin.conf

  # make sure ZMQ entries exist (required for LND block/tx notifications)
  echo "# make sure ZMQ entries exist for ${CHAIN}"
  if ! grep -q "^${glcoin_zmq_prefix}\.zmqpubrawblock=" /mnt/hdd/app-data/glcoin/glcoin.conf; then
    echo "${glcoin_zmq_prefix}.zmqpubrawblock=tcp://127.0.0.1:${glcoin_zmq_block}" >> /mnt/hdd/app-data/glcoin/glcoin.conf
  fi
  if ! grep -q "^${glcoin_zmq_prefix}\.zmqpubrawtx=" /mnt/hdd/app-data/glcoin/glcoin.conf; then
    echo "${glcoin_zmq_prefix}.zmqpubrawtx=tcp://127.0.0.1:${glcoin_zmq_tx}" >> /mnt/hdd/app-data/glcoin/glcoin.conf
  fi

  # make sure wallet directory entry exists and points to app-data
  echo "# make sure entry(walletdir) is set"
  # remove existing wallet entries first
  sed -i '/^main.walletdir=/d' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i '/^main.wallet=/d' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i '/^walletdir=/d' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i '/^wallet=/d' /mnt/hdd/app-data/glcoin/glcoin.conf
  # add wallet entries with correct values
  echo "main.walletdir=/mnt/hdd/app-data/glcoin/wallets" >> /mnt/hdd/app-data/glcoin/glcoin.conf
  echo "main.wallet=wallet.dat" >> /mnt/hdd/app-data/glcoin/glcoin.conf

  # remove any data directory entries - is already forced by parameter in glcoind.service
  echo "# remove any data directory entries"
  sed -i '/^datadir=/d' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i '/^main.datadir=/d' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i '/^test.datadir=/d' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i '/^signet.datadir=/d' /mnt/hdd/app-data/glcoin/glcoin.conf   
  
  # remove any whitelist entries (whitebind is used instead)
  sed -i '/^whitelist=/d' /mnt/hdd/app-data/glcoin/glcoin.conf

  # make sure glcoin debug file exists
  echo "# make sure glcoin debug file exists"
  touch ${glcoinlog_path}
  chown glcoin:glcoin ${glcoinlog_path}
  chmod 600 ${glcoinlog_path}

  ##### STATISTICS #####

  # count startings
  if [ "${CHAIN}" == "mainnet" ]; then
    /home/admin/config.scripts/blesk.systemd.sh log blockchain STARTED
  fi

  echo "# OK PRESTART DONE"
else
  echo "# FAIL: parameter not known - run with -h for help"
  exit 1
fi