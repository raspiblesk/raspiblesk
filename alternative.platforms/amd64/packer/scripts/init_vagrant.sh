#!/bin/bash

echo "************* Vagrant Provisioning ********************"

echo 'Syncing local code with RaspiBleskVM'

# make sure the lastest sync script is in place
cp /vagrant/home.admin/config.scripts/blesk.github.sh /home/admin/config.scripts/blesk.github.sh

# execute 'patch' command to sync laptop with VM
/home/admin/config.scripts/blesk.github.sh -run

source <(/home/admin/config.scripts/internet.sh status local)

echo
echo "************* NEXT ********************"
echo "vagrant ssh --> ssh into your RaspiBleskVM"
echo "ssh admin@${localip} --> ssh into with password A"
echo "vagrant provision --> trigger code sync from outside VM"
echo "patch --> trigger code sync from inside the VM"
echo 