#!/usr/bin/env bash

#########################################################################
# Build your SD card image based on: 2026-04-21-raspios-trixie-arm64.img.xz
# https://downloads.raspberrypi.com/raspios_arm64/images/raspios_arm64-2026-04-21/
# SHA256: 2b016db1eafc3f642eacfe5a1d9bf9e49be8b8caa0360c293901bf7b88bdebca
# also change in: raspiblesk/ci/arm64-rpi/build.arm64-rpi.pkr.hcl
# PGP fingerprint: 8738CD6B956F460C - to check signature:
# curl -O https://www.raspberrypi.org/raspberrypi_downloads.gpg.key && gpg --import ./raspberrypi_downloads.gpg.key && gpg --verify *.sig
# setup fresh SD card with image above - login via SSH and run this script:
##########################################################################

# debian sources
REQUIRED_SOURCES=(
  "deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware"
  "deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware"
  "deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware"
)

# set locale to en_US.UTF-8 on system & activate for this script
if [ "$1" != "-EXPORT" ] && [ "$1" != "EXPORT" ]; then
  echo "# updating locale ..."
  sed -i "s/^# en_US.UTF-8 UTF-8.*/en_US.UTF-8 UTF-8/g" /etc/locale.gen
  sed -i "s/^# en_US ISO-8859-1.*/en_US ISO-8859-1/g" /etc/locale.gen
  locale-gen en_US.UTF-8 en_US ISO-8859-1 1>/dev/null
  update-locale LANG=en_US.UTF-8 1>/dev/null
  source /etc/default/locale
fi

# Capture script directory before any cd commands change working directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

defaultRepo="raspiblesk" # user that hosts a `raspiblesk` repo
defaultBranch="dev" # latest version branch

defaultAPIuser="fusion44"
defaultAPIrepo="blitz_api"

defaultWEBUIuser="raspiblesk"
defaultWEBUIrepo="raspiblesk-web"

me="${0##*/}"

nocolor="\033[0m"
red="\033[31m"

# Konfiguration für nicht-interaktive Installation
export DEBIAN_FRONTEND=noninteractive

## usage as a function to be called whenever there is a huge mistake on the options
usage(){
  printf %s"${me} [--option <argument>]

Options:
  -EXPORT                                  just print build parameters & exit'
  -h, --help                               this help info
  -i, --interaction [0|1]                  interaction before proceeding with execution (default: 1)
  -f, --fatpack [0|1]                      fatpack mode (default: 1)
  -u, --github-user [raspiblesk|other]     github user to be checked from the repo (default: ${defaultRepo})
  -b, --branch [v1.7|v1.8]                 branch to be built on (default: ${defaultBranch})
  -d, --display [lcd|hdmi|headless]        display class (default: lcd)
  -t, --tweak-boot-drive [0|1]             tweak boot drives (default: 1)
  -w, --wifi-region [off|US|GB|other]      wifi iso code (default: off) — WiFi disabled by default for security
  -c, --credentials-only                   skip package installation — only generate credentials (offline safe)

Notes:
  all options, long and short accept --opt=value mode also
  [0|1] can also be referenced as [false|true]
"
  exit 1
}
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root / may use sudo'"
  exit 1
fi

# Check if /usr/sbin is not in the PATH and add it if necessary
if [[ ":$PATH:" != *":/usr/sbin:"* ]]; then
    export PATH="$PATH:/usr/sbin"
fi

# Check if /usr/bin is not in the PATH and add it if necessary
if [[ ":$PATH:" != *":/usr/bin:"* ]]; then
    export PATH="$PATH:/usr/bin"
fi

if [ "$1" = "-EXPORT" ] || [ "$1" = "EXPORT" ]; then
  activeBranch=$(git -C /home/admin/raspiblesk branch --show-current 2>/dev/null)
  echo "activeBranch='${activeBranch}'"
  if [ "${activeBranch}" == "" ]; then
    activeBranch="${defaultBranch}"
  fi
  echo "githubUser='${defaultRepo}'"
  echo "githubBranch='${activeBranch}'"
  echo "defaultAPIuser='${defaultAPIuser}'"
  echo "defaultAPIrepo='${defaultAPIrepo}'"
  echo "defaultWEBUIuser='${defaultWEBUIuser}'"
  echo "defaultWEBUIrepo='${defaultWEBUIrepo}'"
  exit 0
fi

# ----------------------------------------------------------------------
# Audit-grade install log capture (Schweizer Reproduzierbarkeit).
# Mirrors stdout+stderr from this point on into a persistent file so
# every install run can be reconstructed after first boot. Survives
# reboots; child scripts inherit the redirection automatically.
# ----------------------------------------------------------------------
RASPIBLESK_LOG_DIR="/var/log/raspiblesk"
RASPIBLESK_LOG_RUN="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${RASPIBLESK_LOG_DIR}"
chmod 755 "${RASPIBLESK_LOG_DIR}"
RASPIBLESK_LOG_FILE="${RASPIBLESK_LOG_DIR}/build_sdcard-${RASPIBLESK_LOG_RUN}.log"
ln -sfn "${RASPIBLESK_LOG_FILE}" "${RASPIBLESK_LOG_DIR}/latest.log"
export RASPIBLESK_LOG_FILE RASPIBLESK_LOG_DIR
exec > >(stdbuf -oL tee -a "${RASPIBLESK_LOG_FILE}") 2>&1
echo "==================================================="
echo "# RaspiBlesk build_sdcard.sh"
echo "# start  : $(date -Iseconds)"
echo "# host   : $(hostname) ($(uname -srm))"
echo "# script : $(readlink -f "$0")"
echo "# args   : $*"
echo "# pid    : $$"
echo "# log    : ${RASPIBLESK_LOG_FILE}"
echo "# follow : sudo tail -f ${RASPIBLESK_LOG_DIR}/latest.log"
echo "==================================================="

## default user message
error_msg(){ printf %s"${red}${me}: ${1}${nocolor}\n"; exit 1; }

## assign_value variable_name "${opt}"
## it strips the dashes and assign the clean value to the variable
## assign_value status --on IS status=on
## variable_name is the name you want it to have
## $opt being options with single or double dashes that don't require arguments
assign_value(){
  case "${2}" in
    --*) value="${2#--}";;
    -*) value="${2#-}";;
    *) value="${2}"
  esac
  case "${value}" in
    0) value="false";;
    1) value="true";;
  esac
  ## Escaping quotes is needed because else if will fail if the argument is quoted
  # shellcheck disable=SC2140
  eval "${1}"="\"${value}\""
}

## get_arg variable_name "${opt}" "${arg}"
## get_arg service --service ssh
## variable_name is the name you want it to have
## $opt being options with single or double dashes
## $arg is requiring and argument, else it fails
## assign_value "${1}" "${3}" means it is assining the argument ($3) to the variable_name ($1)
get_arg(){
  case "${3}" in
    ""|-*) error_msg "Option '${2}' requires an argument.";;
  esac
  assign_value "${1}" "${3}"
}

## hacky getopts
## 1. if the option requires an argument, and the option is preceeded by single or double dash and it
##    can be it can be specified with '-s=ssh' or '-s ssh' or '--service=ssh' or '--service ssh'
##    use: get_arg variable_name "${opt}" "${arg}"
## 2. if a bunch of options that does different things are to be assigned to the same variable
##    and the option is preceeded by single or double dash use: assign_value variable_name "${opt}"
##    as this option does not require argument, specifu $shift_n=1
## 3. if the option does not start with dash and does not require argument, assign to command manually.
while :; do
  case "${1}" in
    -*=*) opt="${1%=*}"; arg="${1#*=}"; shift_n=1;;
    -*) opt="${1}"; arg="${2}"; shift_n=2;;
    *) opt="${1}"; arg="${2}"; shift_n=1;;
  esac
  case "${opt}" in
    -i|-i=*|--interaction|--interaction=*) get_arg interaction "${opt}" "${arg}";;
    -f|-f=*|--fatpack|--fatpack=*) get_arg fatpack "${opt}" "${arg}";;
    -u|-u=*|--github-user|--github-user=*) get_arg github_user "${opt}" "${arg}";;
    -b|-b=*|--branch|--branch=*) get_arg branch "${opt}" "${arg}";;
    -d|-d=*|--display|--display=*) get_arg display "${opt}" "${arg}";;
    -t|-t=*|--tweak-boot-drive|--tweak-boot-drive=*) get_arg tweak_boot_drive "${opt}" "${arg}";;
    -w|-w=*|--wifi-region|--wifi-region=*) get_arg wifi_region "${opt}" "${arg}";;
    -c|--credentials-only) credentials_only="true"; shift_n=1;;
    "") break;;
    *) error_msg "Invalid option: ${opt}";;
  esac
  shift "${shift_n}"
done

## if there is a limited option, check if the value of variable is within this range
## $ range_argument variable_name possible_value_1 possible_value_2
range_argument(){
  name="${1}"
  eval var='$'"${1}"
  shift
  if [ -n "${var:-}" ]; then
    success=0
    for tests in "${@}"; do
      [ "${var}" = "${tests}" ] && success=1
    done
    [ ${success} -ne 1 ] && error_msg "Option '--${name}' cannot be '${var}'! It can only be: ${*}."
  fi
}

apt_install() {
  for package in "$@"; do
    apt-get install -y -q "$package"
    if [ $? -eq 100 ]; then
      echo "FAIL! apt-get failed to install package: $package"
      exit 1
    fi
  done
}

# === APP INSTALL TRACKING ===
# Shared log written by both build_sdcard.sh and blesk.fatpack.sh (via BLESK_BUILD_LOG env var).
# Each line: OK|<name>  or  FAIL|<name>
BLESK_BUILD_LOG="/tmp/blesk_build_track.log"
export BLESK_BUILD_LOG
rm -f "${BLESK_BUILD_LOG}" 2>/dev/null

track_install() {
  local name="$1"; shift
  if "$@"; then
    echo "OK|${name}" >> "${BLESK_BUILD_LOG}"
  else
    echo "FAIL|${name}" >> "${BLESK_BUILD_LOG}"
    return 1
  fi
}

print_build_summary() {
  [ ! -f "${BLESK_BUILD_LOG}" ] && {
    [ -n "${RASPIBLESK_LOG_FILE}" ] && echo "# build log saved: ${RASPIBLESK_LOG_FILE}"
    return
  }
  local ok_count=0 fail_count=0 ok_list="" fail_list=""
  while IFS='|' read -r status name; do
    if [ "${status}" = "OK" ]; then
      ok_count=$((ok_count + 1))
      ok_list="${ok_list}    [OK]   ${name}\n"
    elif [ "${status}" = "FAIL" ]; then
      fail_count=$((fail_count + 1))
      fail_list="${fail_list}  [FAIL]  ${name}\n"
    fi
  done < "${BLESK_BUILD_LOG}"
  [ "${ok_count}" -eq 0 ] && [ "${fail_count}" -eq 0 ] && return
  echo ""
  echo "################################################"
  echo "#       RASPIBLESK BUILD APP SUMMARY          #"
  echo "################################################"
  if [ "${ok_count}" -gt 0 ]; then
    echo ""
    echo "  INSTALLED (${ok_count}):"
    printf "${ok_list}"
  fi
  if [ "${fail_count}" -gt 0 ]; then
    echo ""
    echo "  FAILED (${fail_count}):"
    printf "${fail_list}"
    echo ""
    echo "  BUILD INCOMPLETE - check output above for errors."
  else
    echo ""
    echo "  All ${ok_count} apps installed successfully."
  fi
  echo "################################################"
  echo ""
  [ -n "${RASPIBLESK_LOG_FILE}" ] && echo "# build log saved: ${RASPIBLESK_LOG_FILE}"
  rm -f "${BLESK_BUILD_LOG}" 2>/dev/null
}
trap print_build_summary EXIT

general_utils="curl"
## loop through all general_utils to see if program is installed (placed on PATH) and if not, add to the list of commands to be installed
for prog in ${general_utils}; do
  ! command -v ${prog} >/dev/null && general_utils_install="${general_utils_install} ${prog}"
done
## if any of the required programs are not installed, update and if successfull, install packages
if [ -n "${general_utils_install}" ]; then
  echo -e "\n*** SOFTWARE UPDATE ***"
  apt-get update -y || exit 1
  apt_install ${general_utils_install}
fi

## use default values for variables if empty

# INTERACTION
# ----------------------------------------
# When 'false' then no questions will be asked on building .. so it can be used in build scripts
# for containers or as part of other build scripts (default is true)
: "${interaction:=true}"
range_argument interaction "0" "1" "false" "true"

# FATPACK
# -------------------------------
# could be 'true' (default) or 'false'
# When 'true' it will pre-install needed frameworks for additional apps and features
# as a convenience to safe on install and update time for additional apps.
# When 'false' it will just install the bare minimum and additional apps will just
# install needed frameworks and libraries on demand when activated by user.
# Use 'false' if you want to run your node without: go, dot-net, nodejs, docker, ...
: "${fatpack:=true}"
range_argument fatpack "0" "1" "false" "true"

# GITHUB-USERNAME
# ---------------------------------------
# could be any valid github-user that has a fork of the raspiblesk repo
# The 'raspiblesk' repo of this user is used to provisioning sd card with raspiblesk assets/scripts later on.
: "${github_user:=$defaultRepo}"
curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${github_user}/raspiblesk" | grep -q "\"message\": \"Not Found\"" && error_msg "Repository 'raspiblesk' not found for user '${github_user}"

# GITHUB-BRANCH
# -------------------------------------
# could be any valid branch or tag of the given GITHUB-USERNAME forked raspiblesk repo
: "${branch:=$defaultBranch}"
curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${github_user}/raspiblesk/branches/${branch}" | grep -q "\"message\": \"Branch not found\"" && error_msg "Repository 'raspiblesk' for user '${github_user}' does not contain branch '${branch}'"

# DISPLAY-CLASS
# ----------------------------------------
# Could be 'hdmi', 'headless' or 'lcd' (lcd is default)
: "${display:=lcd}"
range_argument display "lcd" "hdmi" "headless"

# TWEAK-BOOTDRIVE
# ---------------------------------------
# could be 'true' (default) or 'false'
# If 'true' it will try (based on the base OS) to optimize the boot drive.
# If 'false' this will skipped.
: "${tweak_boot_drive:=true}"
range_argument tweak_boot_drive "0" "1" "false" "true"

# WIFI
# ---------------------------------------
# WIFI — disabled by default (node uses wired Ethernet; WiFi is unnecessary attack surface)
# Pass --wifi-region US (or your country code) only if you specifically need WiFi
: "${wifi_region:=off}"

echo "*****************************************"
echo "*     RASPIBLESK BOOT IMAGE SETUP       *"
echo "*****************************************"
echo "For details on optional parameters - call with '--help' or check source code."

# output
for key in interaction fatpack github_user branch display tweak_boot_drive wifi_region; do
  eval val='$'"${key}"
  [ -n "${val}" ] && printf '%s\n' "${key}=${val}"
done

# AUTO-DETECTION: CPU-ARCHITECTURE
# ---------------------------------------
cpu="$(uname -m)" && echo "cpu=${cpu}"
case "${cpu}" in
  aarch64|x86_64);;
  *) echo -e "# FAIL #\nCan only build on aarch64 or x86_64 not on: cpu=${cpu}"; exit 1;;
esac
architecture="$(dpkg --print-architecture 2>/dev/null)" && echo "architecture=${architecture}"
case "${architecture}" in
  arm*|amd64);;
  *) echo -e "# FAIL #\nCan only build on arm* or amd64 not on: architecture=${cpu}"; exit 1;;
esac

# AUTO-DETECTION: OPERATINGSYSTEM
# ---------------------------------------
if [ $(cat /etc/os-release 2>/dev/null | grep -c 'Debian') -gt 0 ]; then
  if [ -f /etc/apt/sources.list.d/raspi.list ] && [ "${cpu}" = aarch64 ]; then
    # default image for RaspberryPi
    baseimage="raspios_arm64"
  else
    # experimental: fallback for all to debian
    baseimage="debian"
  fi
else
  echo "\n# FAIL: Base image cannot be detected or is not supported."
  cat /etc/os-release 2>/dev/null
  uname -a
  exit 1
fi
echo "baseimage=${baseimage}"

# AUTO-DETECTION: CONFIGFILES
# ---------------------------------------
raspi_configfile="/boot/config.txt"
raspi_commandfile="/boot/cmdline.txt"
if [ -d /boot/firmware ];then
  raspi_configfile="/boot/firmware/config.txt"
  raspi_commandfile="/boot/firmware/cmdline.txt"
fi
echo "raspi_configfile=${raspi_configfile}"
echo "raspi_commandfile=${raspi_commandfile}"

##############################################################
# setup_credentials — OFFLINE PHASE
# No internet required. Generates all credentials, hardens
# SSH, locks unused accounts. Prints summary to terminal.
# Works for SD card, USB, and NVMe equally.
##############################################################
setup_credentials() {
  echo ""
  echo "############################################################"
  echo "#          RASPIBLESK — CREDENTIAL GENERATION              #"
  echo "#              (no internet required)                      #"
  echo "############################################################"

  # generate ED25519 SSH key pair
  TMPKEYDIR=$(mktemp -d)
  ssh-keygen -t ed25519 -f "${TMPKEYDIR}/raspiblesk_key" -N "" -C "raspiblesk-admin" >/dev/null 2>&1
  SSH_PRIVKEY=$(cat "${TMPKEYDIR}/raspiblesk_key")
  SSH_PUBKEY=$(cat "${TMPKEYDIR}/raspiblesk_key.pub")

  # inject public key for admin
  mkdir -p /home/admin/.ssh
  chmod 700 /home/admin/.ssh
  echo "${SSH_PUBKEY}" > /home/admin/.ssh/authorized_keys
  chmod 600 /home/admin/.ssh/authorized_keys
  chown -R admin:admin /home/admin/.ssh

  # harden sshd — key-only, no passwords, no root
  sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
  sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  grep -q "^PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin no" >> /etc/ssh/sshd_config
  sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  grep -q "^PubkeyAuthentication" /etc/ssh/sshd_config || echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config

  # lock root and pi — no login possible
  passwd -l root
  passwd -l pi 2>/dev/null || true

  # set random admin default password (used for sudo password prompts, not SSH)
  ADMIN_DEFAULT_PW=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9!@#%^&*_+=' | head -c 20)
  echo "admin:${ADMIN_DEFAULT_PW}" | chpasswd

  # v0149 hardening (C-5): the boot partition on a Pi is FAT, which DOES NOT
  # enforce POSIX permissions — chmod 600 is silently ignored. Anyone who
  # plugs the SD card / USB into a laptop can read this file with no
  # credentials. Combined with the sudoers NOPASSWD rule (C-4 above) and
  # SSH key-only auth, the boot-partition copy is a single bearer token to
  # full root over LAN.
  # Default: do NOT write the key to the boot partition. The operator must
  # copy the printed key from this terminal (which is shown ONCE below).
  # Opt-in: set RASPIBLESK_KEY_ON_BOOT=1 to restore the old behaviour, with
  # the explicit understanding that anyone with physical access to the
  # storage device gets the key.
  if [ "${RASPIBLESK_KEY_ON_BOOT:-0}" = "1" ]; then
    BOOT_DIR=""
    [ -d /boot/firmware ] && BOOT_DIR="/boot/firmware"
    [ -d /boot ] && [ -z "${BOOT_DIR}" ] && BOOT_DIR="/boot"
    if [ -n "${BOOT_DIR}" ]; then
      echo "${SSH_PRIVKEY}" > "${BOOT_DIR}/raspiblesk_key"
      chmod 600 "${BOOT_DIR}/raspiblesk_key"
      echo "# WARNING: Private key saved to ${BOOT_DIR}/raspiblesk_key"
      echo "# WARNING: This boot partition is FAT — perms are NOT enforced."
      echo "# WARNING: Anyone with physical access to the storage can read it."
    fi
  else
    echo "# (Skipping boot-partition key copy. To restore old behaviour set"
    echo "#  RASPIBLESK_KEY_ON_BOOT=1 before running build_sdcard.sh.)"
  fi

  # v0149 hardening (C-6): mark the build-time SSH key as a single-use
  # bootstrap credential. The first-login wizard (00raspiblesk.sh / setup
  # menu) MUST require the operator to add their own key and rotate
  # authorized_keys, then this marker file is removed.
  touch /home/admin/.ssh/first-login-rotate-required
  chown admin:admin /home/admin/.ssh/first-login-rotate-required
  chmod 600 /home/admin/.ssh/first-login-rotate-required

  rm -rf "${TMPKEYDIR}"

  # print summary — operator records this before flashing
  echo ""
  echo "############################################################"
  echo "#         SAVE THE FOLLOWING BEFORE FLASHING               #"
  echo "############################################################"
  echo ""
  echo "--- SSH PRIVATE KEY (copy to your laptop as raspiblesk_key) ---"
  echo "${SSH_PRIVKEY}"
  echo "--- END SSH PRIVATE KEY ---"
  echo ""
  echo "First login command:"
  echo "  chmod 600 raspiblesk_key"
  echo "  ssh -i raspiblesk_key admin@<pi-ip>"
  echo ""
  echo "Admin sudo password (for local console use only):"
  echo "  ${ADMIN_DEFAULT_PW}"
  echo ""
  echo "############################################################"
  echo "# v0149 SECURITY:                                          #"
  echo "#  - Boot-partition key copy is OFF by default. Save the   #"
  echo "#    private key shown above to your laptop NOW; it will   #"
  echo "#    not be saved anywhere on the device.                  #"
  echo "#  - On first SSH login as 'admin' you will be prompted to #"
  echo "#    paste your own SSH public key. The bootstrap key is   #"
  echo "#    revoked at that moment. Type 'KEEP' to skip (not      #"
  echo "#    recommended).                                         #"
  echo "#  - Sudo NOPASSWD is now restricted to user 'admin' only  #"
  echo "#    (was: every member of the sudo group).                #"
  echo "############################################################"
  echo ""
}

# USER-CONFIRMATION
if [ "${interaction}" = "true" ] && [ "${credentials_only}" != "true" ]; then
  echo -n "# Do you agree with all parameters above? (yes/no) "
  read -r installRaspiblitzAnswer
  [ "$installRaspiblitzAnswer" != "yes" ] && exit 1
fi

# CREDENTIALS-ONLY MODE — skip all package installation
if [ "${credentials_only}" = "true" ]; then
  echo "# Running in credentials-only mode (offline safe) ..."
  setup_credentials
  echo "# Done. Flash the image and boot the Pi."
  exit 0
fi

echo -e "Building RaspiBlesk ...\n"
sleep 3 ## give time to cancel

export DEBIAN_FRONTEND=noninteractive

echo "*** Prevent sleep ***" # on all platforms https://wiki.debian.org/Suspend
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
mkdir /etc/systemd/sleep.conf.d
echo "[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no" | tee /etc/systemd/sleep.conf.d/nosuspend.conf
mkdir /etc/systemd/logind.conf.d
echo "[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore" | tee /etc/systemd/logind.conf.d/nosuspend.conf

# check if /etc/hosts already has debian entry
# prevent "unable to resolve host debian" error
isDebianInHosts=$(grep -c "debian" /etc/hosts)
if [ ${isDebianInHosts} -eq 0 ]; then
  echo "# Adding debian to /etc/hosts"
  echo "127.0.1.1       debian" | tee -a /etc/hosts > /dev/null
  if [ "${baseimage}" != "raspios_arm64" ]; then
    systemctl restart networking
  fi
fi

# force locale - see #4861
# next major release should make sure to be set during sd build card
echo
echo "*** Forcing locales ..."
sudo sed -i '/^en_US.UTF-8/s/^#//' /etc/locale.gen
sudo sed -i '/^en_GB.UTF-8/s/^/#/' /etc/locale.gen
sudo locale-gen
echo -e "LANG=en_US.UTF-8\nLANGUAGE=en_US.UTF-8\nLC_ALL=en_US.UTF-8" | sudo tee /etc/default/locale > /dev/null

echo "*** Setting Fallback DNS ***"
connName=$(nmcli -g GENERAL.CONNECTION device show eth0 2>/dev/null)
echo "current nmcli eth0 connection (${connName})"
if [ "${connName}" != "" ]; then
  echo "Adding DNS fallback servers ..."
  nmcli connection modify "${connName}" ipv4.dns "208.67.222.222,208.67.220.220,1.1.1.1" ipv4.dns-priority -1 ipv4.ignore-auto-dns no
fi

echo "*** Remove unnecessary packages ***"
unnecessary_packages=(libreoffice* oracle-java* chromium-browser nuscratch scratch sonic-pi plymouth python2 vlc* cups* libcups* libcamera* firefox* ffmpeg libpostproc* eom* evince*)
for pkg in "${unnecessary_packages[@]}"; do
  if dpkg-query -W -f='${Status}' $pkg 2>/dev/null | grep -q "ok installed"; then
    echo "Removing $pkg..."
    apt-get remove --purge -y $pkg
  else
    echo "$pkg is not installed."
  fi
done
apt-get clean -y
apt-get autoremove -y

echo -e "\n*** UPDATE Debian***"  # add sources if not present
echo -e "checking/adding sources ..."
for SOURCE in "${REQUIRED_SOURCES[@]}"; do
  if ! grep -Fxq "$SOURCE" /etc/apt/sources.list && \
     ! grep -Fxq "$SOURCE" /etc/apt/sources.list.d/debian.sources 2>/dev/null; then
    echo "Adding  Source: $SOURCE"
    echo "$SOURCE" | sudo tee -a /etc/apt/sources.list > /dev/null
  fi
done

# If i2pd source is already present from a previous run, ensure key is imported
# before apt-get update to avoid "not signed" errors
if [ -f /etc/apt/sources.list.d/i2pd.list ] && \
   [ ! -f /etc/apt/trusted.gpg.d/i2pd.gpg ]; then
  echo "# Pre-importing i2pd signing key ..."
  wget -q -O /etc/apt/trusted.gpg.d/i2pd.gpg https://repo.i2pd.xyz/r4sas.gpg || true
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -f -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"

echo -e "\n*** SOFTWARE UPDATE ***"
# based on https://raspibolt.org/system-configuration.html#system-update
# htop git curl bash-completion vim jq dphys-swapfile bsdmainutils -> helpers
# autossh telnet vnstat -> network tools bandwidth monitoring for future statistics
# parted dosfstools -> prepare for format data drive
# btrfs-progs -> prepare for BTRFS data drive raid
# fbi -> framebuffer image viewer, needed for display graphics mode (LCD/HDMI)
# sysbench -> prepare for powertest
# build-essential -> check for build dependencies on Ubuntu, Armbian
# dialog -> dialog bc python3-dialog
# rsync -> is needed to copy from HDD
# net-tools -> ifconfig
# xxd -> display hex codes
# netcat-openbsd -> for proxy
# openssh-client openssh-sftp-server sshpass -> install OpenSSH client + server
# psmisc -> install killall, fuser
# ufw -> firewall
# sqlite3 -> database
# fdisk -> create partitions
# lsb-release -> needed to know which distro version we're running to add APT sources
general_utils="sudo htop git curl bash-completion vim jq dphys-swapfile bsdmainutils autossh telnet vnstat parted dosfstools fbi sysbench build-essential dialog bc python3-dialog unzip whois fdisk lsb-release smartmontools rsyslog qrencode dnsutils"
# add btrfs-progs if not trixie on aarch64
[ "${architecture}" = "arm64" ] && ! grep -q "13 (trixie)" /etc/os-release && general_utils="${general_utils} btrfs-progs"
# python3-mako -> template engine required by several bonus services
python_dependencies="python3-venv python3-dev python3-wheel python3-jinja2 python3-pip python3-mako"
server_utils="rsync net-tools xxd netcat-openbsd openssh-client openssh-sftp-server sshpass psmisc ufw sqlite3"
[ "${architecture}" = "amd64" ] && amd64_dependencies="network-manager" # add amd64 dependency

apt_install resolvconf
/sbin/resolvconf -u
apt_install ${general_utils} ${python_dependencies} ${server_utils} ${amd64_dependencies}
apt-get clean -y
apt-get autoremove -y

echo -e "\n*** Python DEFAULT libs & dependencies ***"

if [ -f "/usr/bin/python3.13" ]; then
  # use python 3.13 if available (Debian 13 Trixie)
  update-alternatives --install /usr/bin/python python /usr/bin/python3.13 1
  # keep python backwards compatible — do NOT symlink python3.12, it will be
  # installed as a real binary later (LNBits requires genuine python3.12)
  [ ! -f "/usr/bin/python3.9"  ] && ln -s /usr/bin/python3.13 /usr/bin/python3.9
  [ ! -f "/usr/bin/python3.10" ] && ln -s /usr/bin/python3.13 /usr/bin/python3.10
  [ ! -f "/usr/bin/python3.11" ] && ln -s /usr/bin/python3.13 /usr/bin/python3.11
  echo "python calls python3.13"
elif [ -f "/usr/bin/python3.12" ]; then
  # use python 3.12 if available
  update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1
  # keep python backwards compatible
  ln -s /usr/bin/python3.12 /usr/bin/python3.9
  ln -s /usr/bin/python3.12 /usr/bin/python3.10
  ln -s /usr/bin/python3.12 /usr/bin/python3.11
  echo "python calls python3.12"
elif [ -f "/usr/bin/python3.11" ]; then
  # use python 3.11 if available (Debian 12 Bookworm)
  update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1
  # keep python backwards compatible
  ln -s /usr/bin/python3.11 /usr/bin/python3.9
  ln -s /usr/bin/python3.11 /usr/bin/python3.10
  echo "python calls python3.11"
elif [ -f "/usr/bin/python3.10" ]; then
  # use python 3.10 if available
  update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1
  # keep python backwards compatible
  ln -s /usr/bin/python3.10 /usr/bin/python3.9
  echo "python calls python3.10"
elif [ -f "/usr/bin/python3.9" ]; then
  # use python 3.9 if available
  update-alternatives --install /usr/bin/python python /usr/bin/python3.9 1
  echo "python calls python3.9"
elif [ -f "/usr/bin/python3.8" ]; then
  # use python 3.8 if available
  update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1
  echo "python calls python3.8"
else
  echo "# FAIL #"
  echo "There is no tested version of python present"
  exit 1
fi

# don't protect system packages from pip install
# tracking issue: https://github.com/raspiblesk/raspiblesk/issues/4170
for PYTHONDIR in /usr/lib/python3.*; do
  if [ -f "$PYTHONDIR/EXTERNALLY-MANAGED" ]; then
    rm "$PYTHONDIR/EXTERNALLY-MANAGED"
  fi
done

# make sure /usr/bin/pip exists — reset broken alternative before adding
update-alternatives --remove-all pip 2>/dev/null || true
update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1
# grpcio: use apt to avoid compiling from source on arm64
apt-get install -y -q python3-grpcio || sudo -H python3 -m pip install --prefer-binary --root-user-action=ignore grpcio==1.59.3 || true
# requests[socks]: prefer apt to avoid pip version-pin conflicts with system packages
apt-get install -y -q python3-requests python3-socks 2>/dev/null || true
# install python deps individually so one failure doesn't block the rest
for _pypkg in \
    "googleapis-common-protos==1.61.0" \
    "toml==0.10.2" \
    "protobuf==4.25.1" \
    "pathlib2==2.3.7.post1"; do
  sudo -H python3 -m pip install --prefer-binary --root-user-action=ignore "${_pypkg}" || echo "# WARNING: pip install ${_pypkg} failed - continuing"
done
# j2cli 0.3.10 has broken wheel names in pip >=25.3; try apt first, fall back silently
apt-get install -y -q j2cli 2>/dev/null || \
  sudo -H python3 -m pip install --prefer-binary --root-user-action=ignore "j2cli==0.3.10" 2>/dev/null || \
  echo "# WARNING: j2cli not installed - templating features may be limited"
for _pypkg in pytesseract mechanize PySocks urwid Pillow requests setuptools; do
  sudo -H python3 -m pip install --prefer-binary --root-user-action=ignore "${_pypkg}" || echo "# WARNING: pip install ${_pypkg} failed - continuing"
done

echo -e "\n*** PREPARE ${baseimage} ***"

# make sure the pi user is present
if ! compgen -u pi; then
  echo "# Adding the user pi"
  adduser --system --group --shell /bin/bash --home /home/pi pi
  # copy the skeleton files for login
  sudo -u pi cp -r /etc/skel/. /home/pi/
  adduser pi sudo
fi

# activate watchdog if ls /dev/watchdog exists - see #4534
if [ -e /dev/watchdog ]; then
  echo "Activating watchdog ..."
  if [ "${baseimage}" = "raspios_arm64" ]; then
    echo "dtparam=watchdog=on" | tee -a $raspi_configfile
  fi
  sed -i "s/^#RuntimeWatchdogSec=.*/RuntimeWatchdogSec=600s/g" /etc/systemd/system.conf
  sed -i "s/^#RebootWatchdogSec=.*/RebootWatchdogSec=3min/g" /etc/systemd/system.conf
  sed -i "s/^#WatchdogDevice=.*/WatchdogDevice=\/dev\/watchdog/g" /etc/systemd/system.conf
else
  echo "No watchdog device /dev/watchdog found - keep watchdog like default"
fi

# special prepare when RaspberryPi OS
if [ "${baseimage}" = "raspios_arm64" ]; then

  echo -e "\n*** PREPARE RASPBERRY OS VARIANTS ***"
  apt_install raspi-config
  # set WIFI country so boot does not block
  # this will undo the softblock of rfkill on RaspiOS
  [ "${wifi_region}" != "off" ] && raspi-config nonint do_wifi_country $wifi_region
  # setting wifi country clears rfkill soft block so wifi hardware is usable

  if ! grep "RaspiBlesk" $raspi_configfile; then
    echo "# Adding RaspiBlesk Edits to $raspi_configfile"
    echo | tee -a $raspi_configfile
    echo "# RaspiBlesk" | tee -a $raspi_configfile
    # ensure that kernel8.img is used to set PAGE_SIZE to 4K
    # https://github.com/raspiblesk/raspiblesk/issues/4346
    if [ -f /boot/kernel8.img ] || [ -f /boot/firmware/kernel8.img ]; then
      echo 'kernel=kernel8.img' | tee -a $raspi_configfile
    fi
    echo "max_usb_current=1" | tee -a $raspi_configfile
    echo "dtparam=nvme" | tee -a $raspi_configfile
    echo 'dtoverlay=pi3-disable-bt' | tee -a $raspi_configfile
    echo 'dtoverlay=disable-bt' | tee -a $raspi_configfile
    echo 'dtoverlay=disable-wifi' | tee -a $raspi_configfile
    echo 'program_usb_timeout=1' | tee -a $raspi_configfile #4552
  else
    echo "# RaspiBlesk Edits are already in $raspi_configfile"
  fi

  # run fsck on sd root partition on every startup to prevent "maintenance login" screen
  # on unclean shutdown — without this the Pi drops to emergency console instead of booting
  # use command to check last fsck check: tune2fs -l /dev/mmcblk0p2
  if [ "${tweak_boot_drive}" == "true" ]; then
    echo "* running tune2fs"
    tune2fs -c 1 /dev/mmcblk0p2
  else
    echo "* skipping tweak_boot_drive"
  fi

  # edit kernel parameters
  fsOption1="fsck.mode=force"
  fsOption2="fsck.repair=yes"
  fsOption1InFile=$(grep -c ${fsOption1} ${raspi_commandfile})
  fsOption2InFile=$(grep -c ${fsOption2} ${raspi_commandfile})

  if [ ${fsOption1InFile} -eq 0 ]; then
    sed -i "s/^/$fsOption1 /g" "${raspi_commandfile}"
    echo "$fsOption1 added to ${raspi_commandfile}"
  else
    echo "$fsOption1 already in ${raspi_commandfile}"
  fi
  if [ ${fsOption2InFile} -eq 0 ]; then
    sed -i "s/^/$fsOption2 /g" "${raspi_commandfile}"
    echo "$fsOption2 added to ${raspi_commandfile}"
  else
    echo "$fsOption2 already in ${raspi_commandfile}"
  fi

  # *** SAFE SHUTDOWN ***
  # logind
  echo "[Login]" | tee /etc/systemd/logind.conf.d/safeshutdown.conf
  echo "HandlePowerKey=ignore" | tee -a /etc/systemd/logind.conf.d/safeshutdown.conf
  # sudoers
  echo 'nobody ALL=(ALL) NOPASSWD: /home/admin/config.scripts/blesk.shutdown.sh' |
    tee -a /etc/sudoers
  # triggerhappy
  echo 'KEY_POWER    1    sudo /home/admin/config.scripts/blesk.shutdown.sh' |
    tee /etc/triggerhappy/triggers.d/powerbutton.conf
fi

# special prepare when Nvidia Jetson Nano
if [ $(uname -a | grep -c 'tegra') -gt 0 ] ; then
  echo "Nvidia --> disable GUI on boot"
  systemctl set-default multi-user.target
fi

# remove rpi-first-boot-wizard
apt purge piwiz -y
userdel -r rpi-first-boot-wizard

echo -e "\n*** CONFIG ***"

# lock root and pi — no interactive login (credentials are set in setup_credentials)
passwd -l root
passwd -l pi 2>/dev/null || true

# Auto-Login if RaspberryPi
# (just kicks in if auto-login of pi is activated in HDMI or LCD mode)
if [ "${baseimage}" = "raspios_arm64" ]; then
  homeFile=/home/pi/.bashrc
  autostartDone=$(grep -c "automatic start the LCD" $homeFile)
  if [ ${autostartDone} -eq 0 ]; then
    # bash autostart for pi
    # run as exec to dont allow easy physical access by keyboard
    # exec replaces the shell so Ctrl+C drops the user out rather than to a bash prompt
    bash -c 'echo "# automatic start the LCD info loop" >> /home/pi/.bashrc'
    bash -c 'echo "SCRIPT=\"sudo /home/admin/00infoLCD.sh\"" >> /home/pi/.bashrc'
    bash -c 'echo "# replace shell with script => logout when exiting script" >> /home/pi/.bashrc'
    bash -c 'echo "exec \$SCRIPT" >> /home/pi/.bashrc'
    echo "autostart LCD added to $homeFile"
  else
    echo "autostart LCD already in $homeFile"
  fi

# Auto-Login for all other plaforms
else
  # for setup auto-login with admin user
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin admin --noclear %I \$TERM
EOF
fi

# limit journald system use
sed -i "s/^#SystemMaxUse=.*/SystemMaxUse=250M/g" /etc/systemd/journald.conf
sed -i "s/^#SystemMaxFileSize=.*/SystemMaxFileSize=50M/g" /etc/systemd/journald.conf

## LOG ROTATION

# GLOBAL for all logs: /etc/logrotate.conf
echo "# Optimizing log files: rotate daily max 100M, keep 4 days & compress old"
sed -i "s/^weekly/daily size 100M/g" /etc/logrotate.conf
sed -i "s/^#compress/compress/g" /etc/logrotate.conf

# add the option "copytruncate" to /etc/logrotate.conf below the line staring with "# global options do"
sed -i '/# global options do/a \copytruncate' /etc/logrotate.conf

# SPECIAL FOR SYSLOG: /etc/logrotate.d/rsyslog
# to test config run: sudo logrotate -v /etc/logrotate.d/rsyslog
rm /etc/logrotate.d/rsyslog 2>/dev/null
echo "
/var/log/syslog
/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/mail.log
/var/log/daemon.log
/var/log/kern.log
/var/log/auth.log
/var/log/user.log
/var/log/lpr.log
/var/log/cron.log
/var/log/debug
/var/log/messages
{
  rotate 4
  size 100M
  missingok
  compress
  delaycompress
  copytruncate
  sharedscripts
  postrotate
    service logrotate restart
  endscript
}
" | tee ./rsyslog
mv ./rsyslog /etc/logrotate.d/rsyslog
chown root:root /etc/logrotate.d/rsyslog
service logrotate restart
service rsyslog restart

echo -e "\n*** ADDING MAIN USER admin ***"
# based on https://raspibolt.org/system-configuration.html#add-users
# password set to random value — finalized in setup_credentials()
adduser --disabled-password --gecos "" admin
# make the home folder world readable
chmod 0755 /home/admin
# password set securely in setup_credentials — placeholder only
echo "admin:$(openssl rand -base64 24)" | chpasswd
adduser admin sudo
chsh admin -s /bin/bash
# configure sudo for usage without password entry
# v0149 hardening (C-4): scope NOPASSWD to the 'admin' user only, NOT the
# entire %sudo group. Previously any account that ever joined the sudo group
# (e.g. via a future bonus app misconfig) silently inherited passwordless
# root. Limit to the named admin user; other sudo members must still
# authenticate with their password.
echo 'admin ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo
# check if group "admin" was created
if [ $(sudo cat /etc/group | grep -c "^admin") -lt 1 ]; then
  echo -e "\nMissing group admin - creating it ..."
  groupadd --force --gid 1002 admin
  usermod -a -G admin admin
else
  echo -e "\nOK group admin exists"
fi

echo -e "\n*** ADDING SERVICE USER glcoin"
# based on https://raspibolt.org/guide/raspberry-pi/system-configuration.html
# create user and set default password for user
adduser --system --group --shell /bin/bash --home /home/glcoin glcoin
# copy the skeleton files for login
sudo -u glcoin cp -r /etc/skel/. /home/glcoin/
# service user — lock interactive login
passwd -l glcoin
# make home directory readable
chmod 755 /home/glcoin
usermod -a -G glcoin admin

# WRITE BASIC raspiblesk.info to sdcard
# if further info gets added .. make sure to keep that on: blesk.release.sh
touch /home/admin/raspiblesk.info
echo "baseimage=${baseimage}" | tee raspiblesk.info
echo "cpu=${cpu}" | tee -a raspiblesk.info
echo "displayClass=headless" | tee -a raspiblesk.info
mv raspiblesk.info /home/admin/
chmod 755 /home/admin/raspiblesk.info
chown admin:admin /home/admin/raspiblesk.info

echo -e "\n*** SHELL SCRIPTS & ASSETS ***"
# copy raspiblesk repo from github
cd /home/admin/ || exit 1
sudo -u admin git config --global user.name "${github_user}" || exit 1
sudo -u admin git config --global user.email "johndoe@example.com" || exit 1
sudo -u admin git config --global http.postBuffer 524288000 || exit 1
sudo -u admin rm -rf /home/admin/raspiblesk
sudo -u admin git clone -b "${branch}" https://github.com/${github_user}/raspiblesk.git || exit 1

# Overlay the ENTIRE local home.admin tree over the cloned repo so any fix made
# locally — without an immediate GitHub push — actually reaches the Pi. The old
# whitelist-based overlay missed _background.scan.sh, _cache.sh, the menu/info
# scripts, and the parallel-chain dispatchers, which caused the v0146 hang at the
# waitsync loop: bootstrap waited on glc_default_ready while the GitHub-cloned
# scan script still wrote btc_default_ready (incomplete bitcoin->glcoin port
# upstream). Recursive cp -r guarantees no script can drift between source and
# Pi without us noticing.
echo "# Overlaying entire local home.admin/ over cloned repo (recursive)..."
cp -r "${SCRIPT_DIR}/home.admin/." "/home/admin/raspiblesk/home.admin/"
echo "# Overlay done — local tree wins"
# Same for patches/ which is needed by lnd.install.sh for the btcd Glcoin patch
if [ -d "${SCRIPT_DIR}/patches" ]; then
  mkdir -p "/home/admin/raspiblesk/patches"
  cp -r "${SCRIPT_DIR}/patches/." "/home/admin/raspiblesk/patches/"
  echo "# Overlaid patches/ directory"
fi
# Overlay build_sdcard.sh itself so defaultWEBUIuser/repo stay correct after git clone
cp "${SCRIPT_DIR}/build_sdcard.sh" "/home/admin/raspiblesk/build_sdcard.sh"
echo "# Overlaid local fix: build_sdcard.sh"
if [ -f "${SCRIPT_DIR}/home.admin/assets/glcoin-0.2.3-src.tar.gz" ]; then
  cp "${SCRIPT_DIR}/home.admin/assets/glcoin-0.2.3-src.tar.gz" "/home/admin/raspiblesk/home.admin/assets/glcoin-0.2.3-src.tar.gz"
  echo "# Copied bundled glcoin-0.2.3-src.tar.gz to repo assets"
fi
if [ -f "${SCRIPT_DIR}/home.admin/assets/raspiblitz-web-master.tar.gz" ]; then
  cp "${SCRIPT_DIR}/home.admin/assets/raspiblitz-web-master.tar.gz" "/home/admin/raspiblesk/home.admin/assets/raspiblitz-web-master.tar.gz"
  echo "# Copied bundled raspiblitz-web-master.tar.gz to repo assets"
fi
if [ -f "${SCRIPT_DIR}/home.admin/assets/thunderhub-v0.13.31-src.tar.gz" ]; then
  cp "${SCRIPT_DIR}/home.admin/assets/thunderhub-v0.13.31-src.tar.gz" "/home/admin/raspiblesk/home.admin/assets/thunderhub-v0.13.31-src.tar.gz"
  echo "# Copied bundled thunderhub-v0.13.31-src.tar.gz to repo assets"
fi
# Stage Glcoin source bundles and pre-built tarballs into /tmp
# Source bundles allow offline compilation on the Pi (no internet needed)
_arch="arm64"
[ "$(uname -m)" = "x86_64" ] && _arch="amd64"
# Architecture-independent source/tool bundles
for _staged in \
  "lnd-v0.20.1-beta-vendored.tar.gz" \
  "lnd-v0.20.1-beta-src.tar.gz" \
  "btcd-4f4ea81776d6.tar.gz" \
  "go-1.24.11-linux-${_arch}.tar.gz"; do
  if [ -f "${SCRIPT_DIR}/home.admin/assets/${_staged}" ]; then
    cp "${SCRIPT_DIR}/home.admin/assets/${_staged}" "/tmp/${_staged}"
    echo "# Staged source bundle: ${_staged}"
  fi
done
# Architecture-specific pre-built binaries (optional; install scripts prefer source build)
# LND prebuilt is staged FIRST so lnd.install.sh skips the slow source build path.
for _staged in \
  "lnd-glcoin-0.20.99-beta-r2-linux-${_arch}.tar.gz" \
  "cln-glcoin-v25.12.1-linux-${_arch}.tar.gz" \
  "electrs-glcoin-v0.10.10-linux-${_arch}.tar.gz" \
  "fulcrum-glcoin-v2.1.0-linux-${_arch}.tar.gz"; do
  if [ -f "${SCRIPT_DIR}/home.admin/assets/${_staged}" ]; then
    cp "${SCRIPT_DIR}/home.admin/assets/${_staged}" "/tmp/${_staged}"
    echo "# Staged pre-built tarball: ${_staged}"
  fi
done
# Overlay local patches directory (Glcoin-specific patch files)
if [ -d "${SCRIPT_DIR}/patches" ]; then
  mkdir -p "/home/admin/raspiblesk/patches"
  cp -r "${SCRIPT_DIR}/patches/." "/home/admin/raspiblesk/patches/"
  echo "# Overlaid local patches directory"
fi
# Fix ownership of all overlaid files so admin can read them
# (new files created by root would otherwise block the later sudo -u admin cp)
chown -R admin:admin /home/admin/raspiblesk/home.admin/
chown -R admin:admin /home/admin/raspiblesk/patches/ 2>/dev/null || true

sudo -u admin cp -r /home/admin/raspiblesk/home.admin/*.* /home/admin || exit 1
sudo -u admin cp /home/admin/raspiblesk/home.admin/.tmux.conf /home/admin || exit 1
sudo -u admin cp -r /home/admin/raspiblesk/home.admin/assets /home/admin/ || exit 1
sudo -u admin chmod +x *.sh 2>/dev/null || true
sudo -u admin cp -r /home/admin/raspiblesk/home.admin/config.scripts /home/admin/ || exit 1
sudo -u admin chmod +x /home/admin/config.scripts/*.sh || exit 1
sudo -u admin cp -r /home/admin/raspiblesk/home.admin/setup.scripts /home/admin/ || exit 1
sudo -u admin chmod +x /home/admin/setup.scripts/*.sh || exit 1
sudo -u admin cp -r /home/admin/raspiblesk/patches /home/admin/ || exit 1
sudo -u admin git config --global --add safe.directory /home/admin/raspiblesk
# Also configure safe.directory for root user in case root processes need to access the repo
git config --global --add safe.directory /home/admin/raspiblesk

# install newest version of BlitzPy
blitzpy_wheel=$(ls -t /home/admin/raspiblesk/home.admin/BlitzPy/dist/*.whl 2>/dev/null | head -n 1 | xargs basename 2>/dev/null)
blitzpy_version=$(echo "${blitzpy_wheel}" | grep -oE "([0-9]\.[0-9]\.[0-9])")
echo -e "\n*** INSTALLING BlitzPy Version: ${blitzpy_version} ***"
sudo -H /usr/bin/python -m pip install "/home/admin/raspiblesk/home.admin/BlitzPy/dist/${blitzpy_wheel}" >/dev/null 2>&1

# make sure lndlibs are patched for compatibility for both Python2 and Python3
file="/home/admin/config.scripts/lndlibs/lightning_pb2_grpc.py"
! grep -Fxq "from __future__ import absolute_import" "${file}" && sed -i -E '1 a from __future__ import absolute_import' "${file}"
! grep -Eq "^from . import.*" "${file}" && sed -i -E 's/^(import.*_pb2)/from . \1/' "${file}"

# add /sbin to path for all
bash -c "echo 'PATH=\$PATH:/sbin' >> /etc/profile"

# replace boot splash image when raspbian
[ -d /usr/share/plymouth ] && [ "${baseimage}" = "raspios_arm64" ] && { echo "* replacing boot splash"; cp /home/admin/raspiblesk/pictures/splash.png /usr/share/plymouth/themes/pix/splash.png; }

echo -e "\n*** RASPIBLESK EXTRAS ***"

# screen for background processes
# tmux for multiple (detachable/background) sessions when using SSH
# fzf install a command-line fuzzy finder (https://github.com/junegunn/fzf)
apt_install tmux screen fzf

bash -c "echo '' >> /home/admin/.bashrc"
bash -c "echo '# disable Angular CLI telemetry' >> /home/admin/.bashrc"
bash -c "echo 'NG_CLI_ANALYTICS=ci' >> /home/admin/.bashrc"

# raspiblesk custom command prompt #2400
if ! grep -Eq "^[[:space:]]*PS1.*Ǥ" /home/admin/.bashrc; then
    sed -i '/^unset color_prompt force_color_prompt$/i # raspiblesk custom command prompt' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i raspiIp=$(hostname -I | cut -d " " -f1)' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i if [ "$color_prompt" = yes ]; then' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i \    PS1=\x27${debian_chroot:+($debian_chroot)}\\[\\033[00;33m\\]\\u@$raspiIp:\\[\\033[00;34m\\]\\w\\[\\033[01;35m\\]$(__git_ps1 "(%s)") \\[\\033[01;33m\\]Ǥ\\[\\033[00m\\] \x27' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i else' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i \    PS1=\x27${debian_chroot:+($debian_chroot)}\\u@$raspiIp:\\wǤ \x27' /home/admin/.bashrc
    sed -i '/^unset color_prompt force_color_prompt$/i fi' /home/admin/.bashrc
fi

echo -e "\n*** FUZZY FINDER KEY BINDINGS ***"
homeFile=/home/admin/.bashrc
keyBindingsDone=$(grep -c "source /usr/share/doc/fzf/examples/key-bindings.bash" $homeFile)
if [ ${keyBindingsDone} -eq 0 ]; then
  bash -c "echo 'source /usr/share/doc/fzf/examples/key-bindings.bash' >> /home/admin/.bashrc"
  echo "key-bindings added to $homeFile"
else
  echo "key-bindings already in $homeFile"
fi

echo -e "\n*** AUTOSTART ADMIN SSH MENUS ***"
homeFile=/home/admin/.bashrc
autostartDone=$(grep -c "automatically start main menu" $homeFile)
if [ ${autostartDone} -eq 0 ]; then
  # bash autostart for admin
  bash -c "echo '# shortcut commands' >> /home/admin/.bashrc"
  bash -c "echo 'source /home/admin/_commands.sh' >> /home/admin/.bashrc"
  # v0149 hardening (C-6): force bootstrap-key rotation prompt on first
  # interactive admin login (sourced, so it can `return` on no-marker).
  bash -c "echo '# RaspiBlesk bootstrap key rotation gate (v0149)' >> /home/admin/.bashrc"
  bash -c "echo 'source /home/admin/config.scripts/blesk.bootstrap-key.sh' >> /home/admin/.bashrc"
  bash -c "echo '# automatically start main menu for admin unless' >> /home/admin/.bashrc"
  bash -c "echo '# when running in a tmux session' >> /home/admin/.bashrc"
  bash -c "echo 'if [ -z \"\$TMUX\" ]; then' >> /home/admin/.bashrc"
  bash -c "echo '    ./00raspiblesk.sh newsshsession' >> /home/admin/.bashrc"
  bash -c "echo 'fi' >> /home/admin/.bashrc"
  echo "autostart added to $homeFile"
else
  echo "autostart already in $homeFile"
fi

echo -e "\n*** CREDENTIAL GENERATION (OFFLINE PHASE) ***"
setup_credentials

#  Pause so the operator can copy the SSH private key and admin password
#  before the script continues with package installation and services.
if [ "${interaction}" = "true" ] && [ "${credentials_only}" != "true" ]; then
  echo ""
  echo "############################################################"
  echo "#   CREDENTIALS SHOWN ABOVE — SAVE THEM BEFORE CONTINUING  #"
  echo "############################################################"
  echo ""
  echo -n "# Press SPACEBAR (or any key) to continue with installation... "
  read -r _pause_key
  echo ""
fi

echo -e "\n*** SWAP FILE ***"
# based on https://stadicus.github.io/RaspiBolt/raspibolt_20_pi.html#move-swap-file
# but just deactivating and deleting old (will be created alter when user adds HDD)
dphys-swapfile swapoff
dphys-swapfile uninstall

echo -e "\n*** INCREASE OPEN FILE LIMIT ***"
# based on https://raspibolt.org/guide/raspberry-pi/security.html#increase-your-open-files-limit
sed --in-place -i "56s/.*/*    soft nofile 256000/" /etc/security/limits.conf
bash -c "echo '*    hard nofile 256000' >> /etc/security/limits.conf"
bash -c "echo 'root soft nofile 256000' >> /etc/security/limits.conf"
bash -c "echo 'root hard nofile 256000' >> /etc/security/limits.conf"
bash -c "echo '# End of file' >> /etc/security/limits.conf"
sed --in-place -i "23s/.*/session required pam_limits.so/" /etc/pam.d/common-session
sed --in-place -i "25s/.*/session required pam_limits.so/" /etc/pam.d/common-session-noninteractive
bash -c "echo '# end of pam-auth-update config' >> /etc/pam.d/common-session-noninteractive"

# Increase maximum number of inotify instances
bash -c "echo '# RaspiBlesk Edit: Set maximum number of inotify instances (8192 recommended for min 2GB RAM)' >> /etc/sysctl.conf"
bash -c "echo 'fs.inotify.max_user_instances=8192' >> /etc/sysctl.conf"

# Activate overcommit_memory
bash -c "echo '# RaspiBlesk Edit: Use overcommit to prevent system crashes' >> /etc/sysctl.conf"
bash -c "echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf"

# *** fail2ban ***
# based on https://raspibolt.org/security.html#fail2ban
echo "*** HARDENING ***"
apt_install --no-install-recommends python3-systemd fail2ban
# https://github.com/raspiblesk/raspiblesk/issues/4044
if [ ! -f /var/log/auth.log ]; then
  touch /var/log/auth.log
fi

# v0.15.12: mask rpcbind (NFS portmapper). Pulled in transitively by some
# nfs-utils dependency tree and binds 0.0.0.0:111 + [::]:111 by default.
# RaspiBlesk is not an NFS server and exposes nothing on 111. Mask the unit
# (mask, not just disable — disable can be re-enabled by socket activation).
systemctl mask rpcbind.service rpcbind.socket 2>/dev/null || true
systemctl stop rpcbind.service rpcbind.socket 2>/dev/null || true

# *** CACHE DISK IN RAM & KEYVALUE-STORE ***
echo "Activating CACHE RAM DISK ... "
/home/admin/_cache.sh ramdisk on || exit 1
/home/admin/_cache.sh keyvalue on || exit 1

# *** Wifi, Bluetooth & other RaspberryPi configs ***
if [ "${baseimage}" = "raspios_arm64"  ] || [ "${baseimage}" = "debian" ]; then

  echo -e "\n*** DISABLE WIFI ***"
  # WiFi is always disabled — node runs on wired Ethernet
  # hardware-level disable is in config.txt (dtoverlay=disable-wifi)
  systemctl disable wpa_supplicant.service 2>/dev/null || true
  rfkill block wifi 2>/dev/null || true
  ifconfig wlan0 down 2>/dev/null || true
  if [ "${wifi_region}" != "off" ]; then
    echo "# NOTE: --wifi-region ${wifi_region} was passed but WiFi is still disabled by default."
    echo "# To enable WiFi, remove dtoverlay=disable-wifi from ${raspi_configfile} after flashing."
  fi

  # remove bluetooth services
  systemctl disable bluetooth.service 2>/dev/null || true
  systemctl disable hciuart.service 2>/dev/null || true

  # remove bluetooth packages
  apt-get remove -y --purge pi-bluetooth bluez bluez-firmware

  # disable audio
  echo -e "\n*** DISABLE AUDIO (snd_bcm2835) ***"
  sed -i "s/^dtparam=audio=on/# dtparam=audio=on/g" ${raspi_configfile}

  # disable DRM VC4 V3D
  echo -e "\n*** DISABLE DRM VC4 V3D driver ***"
  dtoverlay=vc4-fkms-v3d
  sed -i "s/^dtoverlay=${dtoverlay}/# dtoverlay=${dtoverlay}/g" ${raspi_configfile}

  # I2C fix (make sure dtparam=i2c_arm is not on)
  # leaving i2c_arm enabled causes conflicts with the RaspiBlesk LCD driver on boot
  sed -i "s/^dtparam=i2c_arm=.*//g" ${raspi_configfile}
fi

# *** BOOTSTRAP ***
echo -e "\n*** RASPI BOOTSTRAP SERVICE ***"
chmod +x /home/admin/_bootstrap.sh
cp /home/admin/assets/bootstrap.service /etc/systemd/system/bootstrap.service
systemctl enable bootstrap

# *** BACKGROUND TASKS ***
echo -e "\n*** RASPI BACKGROUND SERVICE ***"
chmod +x /home/admin/_background.sh
cp /home/admin/assets/background.service /etc/systemd/system/background.service
systemctl enable background

# *** BACKGROUND SCAN ***
/home/admin/_background.scan.sh install || exit 1

# *** INITIALIZE DATA STORAGE LAYOUT (must run BEFORE any app install) ***
# Subsequent app installers (kubo, glcoin, electrs, fulcrum, mempool, lnd, etc.)
# write into /mnt/hdd/app-storage/<app>/ and /mnt/hdd/app-data/<app>/ during the
# build phase. If those parent directories do not exist as symlinks yet,
# `mkdir -p /mnt/hdd/app-storage/<app>` would create /mnt/hdd/app-storage as a
# real directory in the root-FS — and blesk.data.sh link (first-boot) would
# then fail with `error='/mnt/hdd/app-storage is real directory'` because it
# expects to claim that path as a symlink target.
#
# So we set up the bind-mount + symlink chain RIGHT NOW:
#   /mnt/raspiblesk-data/app-storage          (real dir in root-FS, our data)
#     <--bind-mount-->  /mnt/disk_storage     (fstab nofail bind)
#     <-symlink--  /mnt/hdd/app-storage       (canonical path apps reference)
# Same for app-data. After this block, `mkdir -p /mnt/hdd/app-storage/kubo`
# resolves through the symlink + bind into /mnt/raspiblesk-data/app-storage/kubo,
# which is the actual filesystem location and survives a reboot.
#
# raspiblesk.conf is intentionally NOT written here; its absence signals
# "not yet provisioned" to blesk.data.sh's first-boot dialog.
echo -e "\n*** INITIALIZING RASPIBLESK DATA DIRECTORIES ***"
_bleskdata="/mnt/raspiblesk-data"
mkdir -p "${_bleskdata}/app-storage/glcoin"
mkdir -p "${_bleskdata}/app-data/glcoin"
mkdir -p /mnt/disk_storage /mnt/hdd
chown -R glcoin:glcoin "${_bleskdata}" 2>/dev/null || true
chmod 755 "${_bleskdata}" "${_bleskdata}/app-storage" "${_bleskdata}/app-data"

# Register bind-mount in fstab (auto-mounted before bootstrap via local-fs.target)
sed -i "\#/mnt/disk_storage#d" /etc/fstab
echo "${_bleskdata} /mnt/disk_storage none bind,nofail 0 0" >> /etc/fstab

# Activate the bind-mount immediately so the symlinks below resolve right now
# during the build, not only after first reboot.
systemctl daemon-reload
mount /mnt/disk_storage 2>/dev/null || mount -a 2>/dev/null || true

# Lay down the canonical /mnt/hdd/{app-storage,app-data} symlinks NOW so that
# app installers writing under those paths land in the storage layout from
# the very first mkdir. blesk.data.sh link (first-boot) will unlink + recreate
# these — that path is safe because they are symlinks, not real directories.
ln -sfn /mnt/disk_storage/app-storage /mnt/hdd/app-storage
ln -sfn /mnt/disk_storage/app-data    /mnt/hdd/app-data
echo "# storage layout ready: /mnt/hdd/app-storage -> /mnt/disk_storage/app-storage (-> ${_bleskdata}/app-storage)"

#######
# TOR #
#######
echo
track_install "TOR" /home/admin/config.scripts/tor.install.sh install || exit 1

#########
# KUBO  #  (IPFS daemon — mandatory dependency for Glcoin 0.2.x auto-pin)
#########
echo
track_install "Kubo (IPFS)" /home/admin/config.scripts/kubo.install.sh install || exit 1

###########
# GLCOIN #
###########
echo
track_install "Glcoin Core" /home/admin/config.scripts/glcoin.install.sh install || exit 1

#######
# I2P #
#######
echo
track_install "I2P (i2pd)" /home/admin/config.scripts/blesk.i2pd.sh install || exit 1

# Ensure lndadmin group exists before web API and fatpack install apps into it
/usr/sbin/groupadd --force --gid 9700 lndadmin 2>/dev/null || true

# *** BLITZ WEB SERVICE ***
echo "Provisioning BLITZ WEB SERVICE"
track_install "Blitz Web Service" /home/admin/config.scripts/blesk.web.sh http-on || exit 1

# *** FATPACK *** (can be activated by parameter - see details at start of script)
if ${fatpack}; then
  echo "* FATPACK activated"
  /home/admin/config.scripts/blesk.fatpack.sh
  if [ $? -gt 0 ]; then
    echo "FATPACK FAILED - please check the output above."
    exit 1
  fi
else
  echo "* skipping FATPACK"
fi

# seed node fallback — shipped in assets/fallback.glcoin.nodes (glcoin.org:1618)
seedfile="/home/admin/fallback.glcoin.nodes"
if [ ! -f "${seedfile}" ] || [ $(stat -c %s "${seedfile}" 2>/dev/null || echo 0) -lt 10 ]; then
  echo "Seeding fallback list from assets ..."
  rm "${seedfile}" 2>/dev/null
  cp /home/admin/assets/fallback.glcoin.nodes "${seedfile}"
fi
chown admin:admin "${seedfile}"

echo
echo "*** raspiblesk.info ***"
cat /home/admin/raspiblesk.info

# Storage layout was initialized earlier (before kubo/glcoin/lnd installs) so
# that those installers' mkdir -p /mnt/hdd/app-storage/<app> calls resolved
# through the symlink chain. See the "INITIALIZE DATA STORAGE LAYOUT" block
# above. Nothing to do here at end-of-build.

# *** RASPIBLESK IMAGE READY INFO ***
echo -e "\n**********************************************"
echo "BASIC SD CARD BUILD DONE"
echo -e "**********************************************\n"
echo "Your SD Card Image for RaspiBlesk is ready (might still do display config)."
echo "Take the chance & look through the output above if you can spot any errors or warnings."
echo -e "\nIMPORTANT IF YOU WANT TO MAKE A RELEASE IMAGE FROM THIS BUILD:"
echo "1. login fresh --> ssh -i raspiblesk_key admin@<pi-ip>  (key printed during build)"
echo -e "2. run --> release\n"

# make sure that at least the code is available (also if no internet)
echo "** DISPLAY(${display})"
# Debian baseimage doesn't support the Waveshare LCD driver (requires raspios_arm64/debian_rpi64)
# Force headless so the set-display step is skipped on plain Debian Pi installs
if [ "${baseimage}" = "debian" ] && [ "${display}" = "lcd" ]; then
  echo "# debian baseimage detected - overriding display to headless (no LCD driver support)"
  display="headless"
fi
track_install "Display" /home/admin/config.scripts/blesk.display.sh prepare-install || exit 1
# (do last - because it might trigger reboot)
if [ "${display}" != "headless" ] || [ "${baseimage}" = "raspios_arm64" ]; then
  echo "*** ADDITIONAL DISPLAY OPTIONS ***"
  echo "- calling: blesk.display.sh set-display ${display}"
  /home/admin/config.scripts/blesk.display.sh set-display ${display} || exit 1
  /home/admin/config.scripts/blesk.display.sh rotate 1 || exit 1
fi

echo "# BUILD DONE - see above"
