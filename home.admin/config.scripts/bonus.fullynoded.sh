#!/bin/bash
clear

# load raspiblesk config data
source /home/admin/raspiblesk.info
source /mnt/hdd/app-data/raspiblesk.conf

# make sure txindex and wallet of glcoin is on
/home/admin/config.scripts/network.wallet.sh on
/home/admin/config.scripts/network.txindex.sh on

# extract RPC credentials from glcoin.conf - store only in var
RPC_USER=$(sudo cat /mnt/hdd/app-data/glcoin/glcoin.conf | grep rpcuser | cut -c 9-)
PASSWORD_B=$(sudo cat /mnt/hdd/app-data/glcoin/glcoin.conf | grep rpcpassword | cut -c 13-)

if [ "${chain}net" == "mainnet" ]; then
  GLCOINRPCPORT=1617
elif [ "${chain}net" == "testnet" ]; then
  GLCOINRPCPORT=11617
elif [ "${chain}net" == "signet" ]; then
  GLCOINRPCPORT=31617
fi

# check and set up the HS
/home/admin/config.scripts/tor.onion-service.sh glcoin${GLCOINRPCPORT} ${GLCOINRPCPORT} ${GLCOINRPCPORT}

hiddenService=$(sudo cat /mnt/hdd/app-data/tor/glcoin${GLCOINRPCPORT}/hostname)
# https://github.com/rootzoll/raspiblesk/issues/2339
if [ ${#hiddenService} -eq 0 ];then
  hiddenService=$(sudo cat /mnt/hdd/app-data/tor/glcoin/hostname)
fi

echo "# The Hidden Service for glcoind port ${GLCOINRPCPORT} is:"
echo "${hiddenService}"

# btcstandup://<rpcuser>:<rpcpassword>@<hidden service hostname>:<hidden service port>/?label=<optional node label>
quickConnect="btcstandup://${RPC_USER}:${PASSWORD_B}@${hiddenService}:${GLCOINRPCPORT}/?label=${hostname}"
echo
echo "scan the QR Code with Fully Noded to connect to your node:"
sudo /home/admin/config.scripts/blesk.display.sh qr "${quickConnect}"
qrencode -t ANSI256 $quickConnect
echo "Press ENTER to return to the menu"
read key

# clean up
sudo /home/admin/config.scripts/blesk.display.sh hide
clear