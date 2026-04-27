#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# Switches on glcoind mainnet behind the scenes to testnet."
  echo "# !!! JUST USE FOR DEVELOPEMNT - NOT FOR PRODUCTION !!!"
  echo "# "
  echo "# glcoin.testnet.sh [activate|revert]"
  echo
  exit 1
fi

# make sure user is root
if [ $UID -ne 0 ]; then
  echo "error='run this script with sudo'"
  exit 1
fi

echo "# Running: glcoin.testnet.sh $*"

if [ "$1" == "activate" ]; then

  # check if glcoin testnet is already activated
  testnetSet=$(cat /mnt/hdd/app-data/glcoin/glcoin.conf | grep -c "^testnet=1")
  if [ $testnetSet -gt 0 ]; then
   echo "error='testnet is already activated'"
   exit 1
  fi

  echo "# SWITCHING TO TESTNET .."

  # make changes to glcoin.conf
  sed -i 's|^testnet=0|testnet=1|' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i 's/^\(main.debuglogfile=.*\)/#\1/' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i 's|^test.debuglogfile=/mnt/hdd/glcoin/testnet3/debug.log|test.debuglogfile=/mnt/hdd/glcoin/debug.log|' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i 's/^\(main.rpcbind=.*\)/#\1/' /mnt/hdd/app-data/glcoin/glcoin.conf 
  sed -i 's|^test.rpcbind=127.0.0.1:11617|test.rpcbind=127.0.0.1:1617|' /mnt/hdd/app-data/glcoin/glcoin.conf

  # restart glcoind service
  systemctl restart glcoind.service

  echo "# OK glcoind should now run testnet on mainnet ports"
  echo "# If you want to save space you can delete old mainnet blockchain with:"
  echo "# rm -rf /mnt/hdd/glcoin/blocks"
  echo "# rm -rf /mnt/hdd/glcoin/chainstate"

  exit 0
fi

if [ "$1" == "revert" ]; then

  # check if glcoin testnet is already activated
  testnetSet=$(cat /mnt/hdd/app-data/glcoin/glcoin.conf | grep -c "^testnet=1")
  if [ $testnetSet -eq 0 ]; then
   echo "error='testnet is not activated'"
   exit 1
  fi

  echo "# SWITCHING BACK TO MAINNET .."

  # make changes to glcoin.conf
  sed -i 's|^testnet=1|testnet=0|' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i 's|^#main.debuglogfile=.*|main.debuglogfile=/mnt/hdd/glcoin/debug.log|' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i 's|^test.debuglogfile=/mnt/hdd/glcoin/debug.log|test.debuglogfile=/mnt/hdd/glcoin/testnet3/debug.log|' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i 's|^#main.rpcbind=.*|main.rpcbind=127.0.0.1:1617|' /mnt/hdd/app-data/glcoin/glcoin.conf
  sed -i 's|^test.rpcbind=127.0.0.1:1617|test.rpcbind=127.0.0.1:11617|' /mnt/hdd/app-data/glcoin/glcoin.conf

  # restart glcoind service
  systemctl restart glcoind.service

  echo "# OK glcoind should now run normal mainnet again"
  echo "# If you want to save space you can delete old testnet blockchain with:"
  echo "# rm -rf /mnt/hdd/glcoin/testnet3/blocks"
  echo "# rm -rf /mnt/hdd/glcoin/testnet3/chainstate"

  exit 0
fi

echo "error='unkown parameter'"
exit 1