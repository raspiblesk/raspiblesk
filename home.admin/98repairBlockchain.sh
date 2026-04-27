#!/bin/bash
echo ""

# load raspiblesk config data
source /home/admin/raspiblesk.info
source /mnt/hdd/app-data/raspiblesk.conf

# Basic Options
OPTIONS=(COPY "Copy from laptop/node over LAN (SKILLED)" \
         RESYNC "Resync thru Peer2Peer Network (TRUSTLESS)" \
         BACKUP "Run Backup LND data first (optional)"
)

CHOICE=$(dialog --backtitle "RaspiBlesk - Repair Script" --clear --title "Repair Blockchain Data" --menu "Choose a repair/recovery option:" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

clear
if [ "${CHOICE}" = "COPY" ]; then
    echo "Starting COPY ..."
    sudo sed -i "s/^state=.*/state=recopy/g" /home/admin/raspiblesk.info
    /home/admin/config.scripts/blesk.copychain.sh target
    sudo sed -i "s/^state=.*/state=na/g" /home/admin/raspiblesk.info

elif [ "${CHOICE}" = "RESYNC" ]; then
    echo "Starting RESYNC ..."
    #TODO #FIXME
    # /home/admin/50syncHDD.sh
    dialog --pause "OK. System will reboot to activate changes." 8 58 8
    clear
    echo "rebooting .. (please wait)"
    sudo /home/admin/config.scripts/blesk.shutdown.sh reboot

elif [ "${CHOICE}" = "BACKUP" ]; then
    /home/admin/config.scripts/lnd.compact.sh interactive
    sudo /home/admin/config.scripts/lnd.backup.sh lnd-export-gui
    echo "PRESS ENTER to continue."
    read key

else
    echo "CANCEL"
fi