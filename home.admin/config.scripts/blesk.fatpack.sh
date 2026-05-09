#!/bin/bash
# setup script - to be called by build_sdcard.sh or on a stopped minimal build sd card image

echo -e "\n*** FATPACK ***"

# check if su
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit 1
fi

# determine correct raspberrypi boot drive path (that easy to access when sd card is insert into laptop)
raspi_bootdir=""
if [ -d /boot/firmware ]; then
  raspi_bootdir="/boot/firmware"
elif [ -d /boot ]; then
  raspi_bootdir="/boot"
fi
echo "# raspi_bootdir(${raspi_bootdir})"

# make sure LCD is on (default for fatpack) - only on RaspberryPi OS, skip on plain Debian
source /home/admin/raspiblesk.info 2>/dev/null || true
if [ "${baseimage}" = "raspios_arm64" ] || [ "${baseimage}" = "debian_rpi64" ]; then
  /home/admin/config.scripts/blesk.display.sh set-display lcd || true
else
  echo "# INFO: skipping LCD setup - not supported on baseimage=${baseimage}"
fi

# check if sd card needs expansion before fatpack
source <(sudo /home/admin/config.scripts/blesk.bootdrive.sh status)
if [ ${rootPartitionBytes} -lt 58465668608 ]; then

    echo "################################################"
    echo "# SD CARD NEEDS EXPANSION BEFORE FATPACK"
    echo "# AND MAKE SURE TO USE 64GB SD CARD"
    echo "# this will be done now ... and trigger a reboot"
    echo "# after reboot run this script again"
    echo "################################################"

    # write a stop file to prevent full bootstrap
    # after fsexpand reboot
    touch ${raspi_bootdir}/stop

    # trigger fsexpand
    /home/admin/config.scripts/blesk.bootdrive.sh fsexpand

    # make sure this expand is not marked (because its not done after release)
    sed -i "s/^fsexpanded=.*/fsexpanded=0/g" /home/admin/raspiblesk.info

    echo "################################################"
    echo "# SD CARD GOT EXPANSION BEFORE FATPACK"
    echo "# triggering a reboot"
    echo "# after reboot run this script again"
    echo "################################################"

    # trigger reboot
    shutdown -h -r now
    exit 0
fi

apt_install() {
  # shellcheck disable=SC2068
  sudo DEBIAN_FRONTEND=noninteractive apt install -y ${@}
  if [ $? -eq 100 ]; then
    echo "FAIL! apt failed to install needed packages!"
    # shellcheck disable=SC2068
    echo ${@}
    exit 1
  fi
}

# Write a single OK|name or FAIL|name line to the shared tracking log (if set by build_sdcard.sh)
_track() {
  [ -n "${BLESK_BUILD_LOG}" ] && echo "${1}|${2}" >> "${BLESK_BUILD_LOG}"
}

echo "# getting default user/repo from build_sdcard.sh"
sudo cp /home/admin/raspiblesk/build_sdcard.sh /home/admin/build_sdcard.sh
sudo chmod +x /home/admin/build_sdcard.sh 2>/dev/null
source <(sudo /home/admin/build_sdcard.sh -EXPORT)
branch="${githubBranch}"
echo "# branch(${branch})"
echo "# defaultAPIuser(${defaultAPIuser})"
echo "# defaultAPIrepo(${defaultAPIrepo})"
echo "# defaultWEBUIuser(${defaultWEBUIuser})"
echo "# defaultWEBUIrepo(${defaultWEBUIrepo})"
sleep 3

if [ "${defaultAPIuser}" == "" ] || [ "${defaultAPIrepo}" == "" ]; then
  echo "FAIL: missing defaultAPIuser or defaultAPIrepo"
  exit 1
fi

if [ "${defaultWEBUIuser}" == "" ] || [ "${defaultWEBUIrepo}" == "" ]; then
  echo "FAIL: missing defaultWEBUIuser or defaultWEBUIrepo"
  exit 1
fi

echo "* Adding nodeJS Framework ..."
if /home/admin/config.scripts/bonus.nodejs.sh on; then
  _track OK "NodeJS"
else
  _track FAIL "NodeJS"
  exit 1
fi

echo "* Optional Packages (may be needed for extended features)"
# fbi/unclutter/xterm are GUI packages - non-fatal if missing on headless builds
sudo DEBIAN_FRONTEND=noninteractive apt install -y qrencode secure-delete msmtp python3-jinja2 socat libopenblas-dev || true
sudo DEBIAN_FRONTEND=noninteractive apt install -y fbi unclutter xterm python3-pyqt5 xfonts-terminus hexyl || true

echo "#############################################################"
echo "* Adding LND ..."
if /home/admin/config.scripts/lnd.install.sh install; then
  _track OK "LND"
else
  _track FAIL "LND"
  exit 1
fi

echo "#############################################################"
echo "* Adding Core Lightning ..."
if /home/admin/config.scripts/cl.install.sh install; then
  _track OK "Core Lightning (CLN)"
else
  _track FAIL "Core Lightning (CLN)"
  exit 1
fi

# *** AUTO UPDATE FALLBACK NODE LIST FROM INTERNET (only in fatpack)
echo "*** FALLBACK NODE LIST ***"
# see https://github.com/rootzoll/raspiblesk/issues/1888
sudo -u admin curl -H "Accept: application/json; indent=4" https://bitnodes.io/api/v1/snapshots/latest/ -o /home/admin/fallback.bitnodes.nodes
# Fallback Nodes List from Glcoin Core
sudo -u admin curl https://raw.githubusercontent.com/glcoin/glcoin/master/contrib/seeds/nodes_main.txt -o /home/admin/fallback.glcoin.nodes

echo "#############################################################"
echo "* Adding Raspiblitz API ..."
if sudo /home/admin/config.scripts/blesk.web.api.sh on "${defaultAPIuser}" "${defaultAPIrepo}" "blitz-${branch}"; then
  _track OK "Blitz API"
else
  _track FAIL "Blitz API"
  exit 1
fi

echo "#############################################################"
echo "* Adding Raspiblitz WebUI ..."
# raspiblesk-web repo may not exist yet — non-fatal, node works without WebUI
if sudo /home/admin/config.scripts/blesk.web.ui.sh on "${defaultWEBUIuser}" "${defaultWEBUIrepo}" "release/${branch}"; then
  _track OK "Blitz WebUI"
  # set build code as new www default
  sudo rm -rf /home/admin/assets/nginx/www_public
  sudo mkdir -p /home/admin/assets/nginx/www_public
  sudo cp -a /home/bleskapi/blitz_web/build/* /home/admin/assets/nginx/www_public
  sudo chown -R admin:admin /home/admin/assets/nginx/www_public
  sudo rm -r /home/bleskapi/blitz_web/build/*
else
  _track FAIL "Blitz WebUI"
  echo "# WARNING: WebUI install skipped — raspiblesk-web repo not available"
  echo "# Node will function normally via SSH/CLI"
fi

# Helper: install a bonus app non-fatally — log failure and continue
_fatpack_bonus() {
  local name="$1"; local script="$2"
  echo "#############################################################"
  echo "* Adding Code&Compile for WEBUI-APP: ${name}"
  if /home/admin/config.scripts/${script} install; then
    echo "# OK: ${name} installed"
    _track OK "${name}"
  else
    echo "# WARNING: ${name} install failed (exit $?) - continuing without it"
    echo "# Node core functionality is unaffected. ${name} can be installed later."
    _track FAIL "${name}"
  fi
}

_fatpack_bonus "ALBYHUB"       "bonus.albyhub.sh"
_fatpack_bonus "LNBITS"        "bonus.lnbits.sh"
_fatpack_bonus "JAM"           "bonus.jam.sh"
_fatpack_bonus "RTL"           "bonus.rtl.sh"
_fatpack_bonus "THUNDERHUB"    "bonus.thunderhub.sh"
_fatpack_bonus "GLC-RPC-EXPLORER" "bonus.glc-rpc-explorer.sh"
_fatpack_bonus "MEMPOOL"       "bonus.mempool.sh"
_fatpack_bonus "ELECTRS"       "bonus.electrs.sh"