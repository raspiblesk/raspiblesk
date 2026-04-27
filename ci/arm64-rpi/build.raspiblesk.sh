#!/bin/sh -eux

echo 'Download the build_sdcard.sh script ...'
wget https://raw.githubusercontent.com/${github_user}/raspiblesk/${branch}/build_sdcard.sh

if [ "${pack}" = "fatpack" ]; then
  fatpack="1"
  display="lcd"
else
  fatpack="0"
  display="headless"
fi

# make /dev/shm world writable for qemu
sudo chmod 777 /dev/shm

echo 'Build RaspiBlesk ...'
bash build_sdcard.sh -f ${fatpack} -u ${github_user} -b ${branch} -t false -w off -i false -d ${display}
