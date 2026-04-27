#!/bin/bash

########################################
# AFTER FINAL SETUP TASKS
echo "# AFTER FINAL SETUP TASKS" >> /home/admin/raspiblesk.log
echo "# /home/admin/_provision.xfinal.sh" > /var/cache/raspiblesk/final.log

# signal that setup phase is over
/home/admin/_cache.sh set setupPhase "done"

# source info fresh
source /home/admin/raspiblesk.info
echo "# source /home/admin/raspiblesk.info" >> /home/admin/raspiblesk.log
cat /home/admin/raspiblesk.info >> /home/admin/raspiblesk.log

# make sure for future starts that blockchain service gets started after bootstrap
# so deamon reloas needed ... system will go into reboot after last loop
# needs to be after wait loop because otherwise the "restart" on COPY OVER LAN will not work
echo "# Updating service glcoind.service ..." >> /home/admin/raspiblesk.log
sudo sed -i "s/^Wants=.*/Wants=bootstrap.service/g" /etc/systemd/system/glcoind.service
sudo sed -i "s/^After=.*/After=bootstrap.service/g" /etc/systemd/system/glcoind.service
sudo systemctl daemon-reload 2>/dev/null

# delete setup data from RAM
echo "# removing raspiblesk.setup" >> /home/admin/raspiblesk.log
sudo rm /var/cache/raspiblesk/temp/raspiblesk.setup

########################################
# AFTER SETUP REBOOT
# touchscreen activation, start with configured SWAP, fix LCD text bug
echo "# SHUTTING DOWN ..." >> /home/admin/raspiblesk.log
sudo cp /home/admin/raspiblesk.log /home/admin/raspiblesk.setup.log
sudo chmod 640 /home/admin/raspiblesk.setup.log
sudo chown root:sudo /home/admin/raspiblesk.setup.log
timeout 120 sudo /home/admin/config.scripts/blesk.shutdown.sh reboot finalsetup
# if system has not rebooted yet - force reboot directly
sudo shutdown -r now