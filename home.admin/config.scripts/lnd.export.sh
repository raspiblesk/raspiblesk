#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "tool to export macaroons & tls.cert"
 echo "lnd.export.sh [hexstring|sftp|http] [?key-value]"

 exit 1
fi

# check if lnd is on
source <(/home/admin/_cache.sh get lnd)
if [ "${lnd}" != on ]; then
  echo "error='lnd not active'"
  exit 1
fi

# 1. parameter -> the type of export
exportType=$1

# interactive choose type of export if not set
if [ "$1" = "" ] || [ $# -eq 0 ]; then
    OPTIONS=()
    OPTIONS+=(SFTP "SSH Download (Commands)")
    OPTIONS+=(HTTP "Browserdownload (bit risky)")
    OPTIONS+=(HEX "Hex-String (Copy+Paste)")   
    CHOICE=$(dialog --clear \
                --backtitle "RaspiBlesk" \
                --title "Export Macaroons & TLS.cert" \
                --menu "How do you want to export?" \
                11 50 7 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
    clear
    case $CHOICE in
        HEX)
          exportType='hexstring';
          ;;
        SFTP)
          exportType='sftp';
          ;;
        HTTP)
          exportType='http';
          ;;
    esac

fi

# load data from config
source /home/admin/raspiblesk.info
source /mnt/hdd/app-data/raspiblesk.conf

########################
# CANCEL
########################
if [ ${#exportType} -eq 0 ]; then

  echo "CANCEL"
  exit 0

########################
# HEXSTRING
########################
elif [ "${exportType}" = "hexstring" ]; then

  adminMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/admin.macaroon)
  invoiceMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/invoice.macaroon)
  readonlyMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/readonly.macaroon)
  restTor=$(sudo cat /mnt/hdd/app-data/tor/lndrest/hostname)

  clear
  echo "###### HEXSTRING EXPORT ######"
  echo "restTor=${restTor}:8080"
  echo ""
  echo "adminMacaroon=${adminMacaroon}"
  echo ""
  echo "invoiceMacaroon=${invoiceMacaroon}"
  echo ""
  readonlyMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/readonly.macaroon)
  echo "readonlyMacaroon=${readonlyMacaroon}"
  echo ""
  tlsCert=$(sudo xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/tls.cert)
  echo "tlsCert=${tlsCert}"
  echo ""

###########################
# SHH / SFTP File Download
###########################
elif [ "${exportType}" = "sftp" ]; then

  local_ip=$(hostname -I | awk '{print $1}')
  clear
  echo "###### DOWNLOAD BY SFTP ######"
  echo "Copy, paste and execute these commands in your client terminal to download the files."
  echo "The password needed during download is your Password A."
  echo ""
  echo "Macaroons:"
  echo "scp glcoin@${local_ip}:/mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/\*.macaroon ./"
  echo ""
  echo "TLS Certificate:"
  echo "scp glcoin@${local_ip}:/mnt/hdd/app-data/lnd/tls.cert ./"
  echo ""

###########################
# HTTP File Download
###########################
elif [ "${exportType}" = "http" ]; then

  local_ip=$(hostname -I | awk '{print $1}')
  randomPortNumber=$(shuf -i 20000-39999 -n 1)
  sudo ufw allow from 192.168.0.0/16 to any port ${randomPortNumber} comment 'temp http server'
  clear
  echo "###### DOWNLOAD BY HTTP ######"
  echo ""
  echo "Open in your browser --> http://${local_ip}:${randomPortNumber}"
  echo ""
  echo "You need to be on the same local network - not reachable from outside."
  echo "In browser click on files or use 'save as' from context menu to download."
  echo ""
  echo "Temp HTTP Server is running - use CTRL+C to stop when you are done"
  echo ""
  cd 
  randomFolderName=$(shuf -i 100000000-900000000 -n 1)
  mkdir ${randomFolderName}
  sudo cp /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/admin.macaroon ./${randomFolderName}/admin.macaroon
  sudo cp /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/readonly.macaroon ./${randomFolderName}/readonly.macaroon
  sudo cp /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/invoice.macaroon ./${randomFolderName}/invoice.macaroon
  sudo cp /mnt/hdd/app-data/lnd/tls.cert ./${randomFolderName}/tls.cert
  cd ${randomFolderName}
  sudo chmod 444 *.*
  python3 -m http.server ${randomPortNumber} 2>/dev/null
  sudo ufw delete allow from 192.168.0.0/16 to any port ${randomPortNumber} comment 'temp http server'
  cd ..
  sudo rm -r ${randomFolderName}
  echo "OK - temp HTTP server is stopped."

else
  echo "FAIL: unknown '${exportType}' - run with -h for help"
fi

if [ "$1" = "" ] || [ $# -eq 0 ]; then
  echo "Press ENTER to return to main menu."
  read key
fi
