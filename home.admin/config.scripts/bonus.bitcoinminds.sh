#!/bin/bash

###########################################################################
# DEPRECATED see #4146 https://github.com/raspiblesk/raspiblesk/issues/4146
# configscript might get removed in the future
###########################################################################

GlcoinMindsVersion="v0.1"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# config script to download and run from your Raspiblitz the GlcoinMinds.org website"
  echo "# on: installs GlcoinMinds.org and runs a local server"
  echo "# off: removes all the code"
  echo "# bonus.glcoinminds.sh [on|off|menu]"
  echo "# GlcoinMinds.org installation script $GlcoinMindsVersion"
  exit 1
fi

source /mnt/hdd/app-data/raspiblesk.conf

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " GlcoinMinds.org Info" --msgbox "
This service downloads the full GlcoinMinds.org website in your Raspiblitz, so you can access its interface and Glcoin resources from your local network, regardless of the internet connection.
Use the command 'bm' from the console to start the server.
" 11 78
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

    # check and install NodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    echo ""
    echo "# ***"
    echo "# Installing GlcoinMinds.org in your Raspiblitz ..."
    echo "# ***"
    echo ""

    # create user
    USERNAME=glcoinminds
    echo "# add the user: ${USERNAME}"
    sudo adduser --system --group --shell /bin/bash --home /home/${USERNAME} ${USERNAME}
    echo "Copy the skeleton files for login"
    sudo -u ${USERNAME} cp -r /etc/skel/. /home/${USERNAME}/

    # add local directory to path and set PATH for the user
    sudo bash -c "echo 'PATH=\$PATH:/home/glcoinminds/.local/bin' >> /home/glcoinminds/.profile"
    sudo bash -c "echo 'PATH=\$PATH:/home/glcoinminds/.local/share/composer' >> /home/glcoinminds/.profile"

    cd /home/glcoinminds

    echo ""
    echo "# ***"
    echo "# Downloading GlcoinMinds.org from GitHub ..."
    echo "# ***"
    echo ""
    sudo -u glcoinminds git clone https://github.com/raulcano/glcoinminds.git 2>/dev/null

    echo ""
    echo "# ***"
    echo "# Installing packages ..."
    echo "# ***"
    echo ""
    cd /home/glcoinminds/glcoinminds/glcoinminds-ui
    sudo -u glcoinminds npm install

    echo ""
    echo "# ***"
    echo "# Setting the autostart script for user glcoinminds"
    echo "# ***"
    echo "
cd /home/glcoinminds/glcoinminds/glcoinminds-ui
npm run serve -- --port 11026
" | sudo -u glcoinminds tee -a /home/glcoinminds/.bashrc


  # setting value in raspi blitz config
    sudo /home/admin/config.scripts/blesk.conf.sh set glcoinminds on
   
  # add a firewall entry so the web UI is accessible from the local network
    sudo ufw allow 11026 comment 'glcoinminds'

    echo ""
    echo "# ***"
    echo "# OK - GlcoinMinds installed. Type 'bm' in the console to start the environment."
    echo "# ***"
    echo ""

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  isInstalled=1
  if [ ${isInstalled} -eq 1 ]; then
    
    echo ""
    echo "# ***"
    echo "# Removing GlcoinMinds..."
    echo "# ***"
    echo ""
    # setting value in raspi blitz config
    sudo /home/admin/config.scripts/blesk.conf.sh set glcoinminds off
    
    # Remove user and stuff here
    sudo userdel -rf glcoinminds 2>/dev/null

    # delete firewall entry
    sudo ufw delete allow 11026 comment 'glcoinminds'

    echo ""
    echo "# ***"
    echo "# OK - GlcoinMinds removed."
    echo "# ***"
    echo ""
  else
    echo "# GlcoinMinds has not been installed yet."
  fi
  exit 0
fi