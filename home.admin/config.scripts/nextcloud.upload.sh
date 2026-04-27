#!/bin/bash

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# script to upload a file to Nextcloud"
  echo "# nextcloud.upload.sh on [server] [user] [password]"
  echo "# nextcloud.upload.sh off"
  echo "# nextcloud.upload.sh upload [filepath]"
  echo "err='just informational output'"
  exit 1
fi

source /mnt/hdd/app-data/raspiblesk.conf

on() {

  local server="${1}"
  local user="${2}"
  local password="${3}" 

  sudo touch /var/cache/raspiblesk/.tmp
  sudo chmod 777 /var/cache/raspiblesk/.tmp

  if [ -z "${server}" ]; then
    whiptail --title "Static Channel Backup on Nextcloud" --inputbox "Enter your Nextcloud server URL\nExample: https://cloud.johnsmith.com" 11 70 2>/var/cache/raspiblesk/.tmp
    server=$(cat /var/cache/raspiblesk/.tmp)
  fi

  if [ -z "${user}" ]; then
    whiptail --title "Static Channel Backup on Nextcloud" --inputbox "\nEnter your Nextcloud username:\n(best to use a dedicated user for backup)" 10 70 2>/var/cache/raspiblesk/.tmp
    user=$(cat /var/cache/raspiblesk/.tmp)
  fi

  if [ -z "${password}" ]; then
    whiptail --title "Static Channel Backup on Nextcloud" --inputbox "\nEnter your Nextcloud password:\n(will get stored in cleartext on raspiblesk)" 10 70 2>/var/cache/raspiblesk/.tmp
    password=$(cat /var/cache/raspiblesk/.tmp)
  fi

  # normal delete is OK because it a mem drive
  sudo rm -f /var/cache/raspiblesk/.tmp

  if [ "${server}" ] && [ "${user}" ] && [ "${password}" ]; then
    /home/admin/config.scripts/blesk.conf.sh set nextcloudBackupServer "${server}"
    /home/admin/config.scripts/blesk.conf.sh set nextcloudBackupUser "${user}"
    /home/admin/config.scripts/blesk.conf.sh set nextcloudBackupPassword "${password}"
  else
    echo "Please provide nextcloud server, username and password"
    exit 1
  fi
}

off() {
  /home/admin/config.scripts/blesk.conf.sh delete nextcloudBackupServer
  /home/admin/config.scripts/blesk.conf.sh delete nextcloudBackupUser
  /home/admin/config.scripts/blesk.conf.sh delete nextcloudBackupPassword
}

upload() {
  local filepath="${1}"

  if [ -z "${filepath}" ]; then
    echo "err='Missing argument: filepath'"
    exit 1
  fi

  if [ -z "${nextcloudBackupServer}" ] || [ -z "${nextcloudBackupUser}" ] || [ -z "${nextcloudBackupPassword}" ]; then
    echo "err='Nextcloud credentials are missing'"
    exit 1
  fi

  local remoteDirUrl="$nextcloudBackupServer/remote.php/dav/files/$nextcloudBackupUser/raspiblesk/"
  
  # checking if remote directory exists
  local response
  response=$(curl "${remoteDirUrl}" \
    --user "${nextcloudBackupUser}:${nextcloudBackupPassword}" \
    --request PROPFIND \
    --silent)

  # if remote directory doesn't exist, we need to create it
  if [[ "${response}" = *DAV\\Exception\\NotFound* ]]; then
    curl "${remoteDirUrl}" \
      --user "${nextcloudBackupUser}:${nextcloudBackupPassword}" \
      --request MKCOL \
      --silent
  fi

  if curl "${remoteDirUrl}" \
    --user "${nextcloudBackupUser}:${nextcloudBackupPassword}" \
    --upload-file "${filepath}" \
    --silent;
  then
    echo "File ${filepath} has been uploaded"
    echo "upload=1"
  else
    echo "err='File upload failed'"
    echo "upload=0"
    exit 1
  fi
}

case "${1}" in
  on) on "${2}" "${3}" "${4}" ;;
  off) off ;;
  upload) upload "${2}" ;;
  *) echo "err=Unknown action: ${1}" ; exit 1 ;;
esac