#!/bin/bash

# This is for developing on your RaspiBlesk VM

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "FOR DEVELOPMENT USE ONLY!"
  echo "RaspiBleskVM Sync with repos in /mnt/vm_shared_folder"
  echo "blesk.vm.sh sync      -> syncs all available repos in shared folder"
  echo "blesk.vm.sh sync code -> syncs only the raspiblesk repo"
  echo "blesk.vm.sh sync api  -> syncs only the raspiblesk API repo"
  echo ""
  exit 1
fi

# check runnig as sudo
if [ "$EUID" -ne 0 ]; then
  echo "error='please run as root'"
  exit 1
fi

# check if running in vm
isVM=$(grep -c 'hypervisor' /proc/cpuinfo)
if [ ${isVM} -eq 0 ]; then
  echo "# This script is only for RaspiBlesk running in a VM"
  echo "error='not a VM'"
  exit 1
fi

# check if shared folder exists
if [ ! -d "/mnt/vm_shared_folder" ]; then
  echo "# Creating shared folder /mnt/vm_shared_folder"
  mkdir /mnt/vm_shared_folder
  chmod 777 /mnt/vm_shared_folder
fi

# check if shared folder is mounted
isMounted=$(mount | grep '/mnt/vm_shared_folder')
if [ ${#isMounted} -eq 0 ]; then
  echo "# Mounting shared folder /mnt/vm_shared_folder"
  mount -t 9p -o trans=virtio share /mnt/vm_shared_folder
  if [ $? -eq 0 ]; then
    echo "# OK - shared folder mounted"
  else
    echo "# make sure to activate shared folder in VM settings (VirtFS)"
    echo "error='mount failed'"
    exit 1
  fi
fi

# RASPIBLESK MAIN REPO
if [ "$2" == "code" ] || [ "$2" == "" ]; then

  echo
  echo  "# ##### RASPIBLESK REPO"

  #check if contains a raspiblesk MAIN repo
  containsRaspiBleskRepo=$(ls /mnt/vm_shared_folder | grep -wc 'raspiblesk')
  if [ ${containsRaspiBleskRepo} -eq 0 ]; then
 
    echo "# /mnt/vm_shared_folder does not contain a raspiblesk repo"
    echo "# make sure to share the directory that contains the raspiblesk repo - not the repo itself"
    echo "# make sure its named 'raspiblesk' and not 'raspiblesk-main' or 'raspiblesk-v1.7'"
 
    if [ "$2" != "" ]; then
      echo "error='no raspiblesk main repo'"
      exit 1
    fi
 
  else

    cd /home/admin
    echo "# COPYING from VM SHARED FOLDER to /home/admin/"
    echo "# - basic admin files"
    rm -f *.sh
    su - admin -c 'cp /mnt/vm_shared_folder/raspiblesk/home.admin/.tmux.conf /home/admin'
    su - admin -c 'cp /mnt/vm_shared_folder/raspiblesk/home.admin/*.* /home/admin 2>/dev/null'
    su - admin -c 'chmod 755 *.sh'
    echo "# - asset directory"
    rm -rf assets
    su - admin -c 'cp -R /mnt/vm_shared_folder/raspiblesk/home.admin/assets /home/admin/assets'
    echo "# - config.scripts directory"
    rm -rf /home/admin/config.scripts
    su - admin -c 'cp -R /mnt/vm_shared_folder/raspiblesk/home.admin/config.scripts /home/admin/config.scripts'
    su - admin -c 'chmod 755 /home/admin/config.scripts/*.sh'
    su - admin -c 'chmod 755 /home/admin/config.scripts/*.py'
    echo "# - setup.scripts directory"
    rm -rf /home/admin/setup.scripts
    su - admin -c 'cp -R /mnt/vm_shared_folder/raspiblesk/home.admin/setup.scripts /home/admin/setup.scripts'
    su - admin -c 'chmod 755 /home/admin/setup.scripts/*.sh'
    su - admin -c 'chmod 755 /home/admin/config.scripts/*.py'
    echo "# ******************************************"

    if [ "$2" != "" ]; then
      exit 0
    fi

  fi
fi  

# RASPIBLESK API REPO
if [ "$2" == "api" ] || [ "$2" == "" ]; then

  echo
  echo  "# ##### RASPIBLESK API REPO"

  # check if bleskapi service is enabled
  systemctl is-enabled bleskapi 2>/dev/null
  notInstalled=$?

  #check if contains a raspiblesk API repo
  containsApiRepo=$(ls /mnt/vm_shared_folder | grep -wc 'blitz_api')
  if [ ${containsApiRepo} -eq 0 ]; then
 
    echo "# /mnt/vm_shared_folder does not contain a api repo"
    echo "# make sure to share the directory that contains the api repo - not the repo itself"
    echo "# make sure its named 'blitz_api'"
 
    if [ "$2" != "" ]; then
      echo "error='no raspiblesk api repo'"
      exit 1
    fi

  elif [ ${notInstalled} -gt 0 ]; then
  
    echo "# bleskapi service is not installed or enabled - skipping"
    if [ "$2" != "" ]; then
      echo "error='bleskapi service not enabled'"
      exit 1
    fi
 
  else

  
    echo "# TODO: Not implemented yet - use /script/updateBlitzAPI.sh instead to sync from host to VM"

    #echo "# Stopping bleskapi service"
    #systemctl stop bleskapi
    #echo "# COPYING from VM SHARED FOLDER to /home/bleskapi/"
    #rm -rf /home/bleskapi/blitz_api
    #cp -R /mnt/vm_shared_folder/blitz_api /home/bleskapi
    #chown -R bleskapi:bleskapi /home/bleskapi/blitz_api
    #cd /home/bleskapi/blitz_api || exit 1
    #su - bleskapi -c './venv/bin/pip install -r requirements.txt'
    #echo "# Starting bleskapi service"
    #systemctl start bleskapi

    if [ "$2" != "" ]; then
      exit 0
    fi

  fi

fi

if [ "$1" == "sync" ]; then
  exit 0
fi

# in case of unknown command
echo "error='unkown command'"
exit 1