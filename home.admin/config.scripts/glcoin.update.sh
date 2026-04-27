#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Interim optional Glcoin Core updates between RaspiBlesk releases."
  echo "glcoin.update.sh [info|tested|reckless|custom]"
  echo "info -> get actual state and possible actions"
  echo "tested -> only do a tested update by the RaspiBlesk team"
  echo "reckless -> the update was not tested by the RaspiBlesk team"
  echo "custom <version> <skipverify> -> update to a chosen version"
  echo " the binary checksum and signatures will be checked in all cases"
  echo " except when 'skipverify' is used"
  echo
  exit 1
fi

echo "# Running: glcoin.update.sh $*"

isGlcoinCoreInstalled=$(sudo -u glcoin glcoind --version | head -n 1 | grep -c "Glcoin Core")
if [ ${isGlcoinCoreInstalled} -eq 0 ]; then
  echo "# if you have Glcoin KNOTS installed - you first need to switch back to Glcoin Core"
  echo "# error='Glcoin Core is not installed'"
  sleep 3
  exit 1
fi

# 1. parameter [info|tested|reckless]
mode="$1"

# RECOMMENDED UPDATE BY RASPIBLESK TEAM (latest tested version available)
glcoinVersion="0.1.7" # keep empty if no newer version as sd card build is available

# GATHER DATA
# setting download directory to the current user
downloadDir="/home/$(whoami)/download/glcoin.update"

# glcoinOSversion
if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
  glcoinOSversion="arm-linux-gnueabihf"
elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
  glcoinOSversion="aarch64-linux-gnu"
elif [ "$(uname -m | grep -c 'x86_64')" -gt 0 ]; then
  glcoinOSversion="x86_64-linux-gnu"
fi

# installed version
installedVersion=$(sudo -u glcoin glcoind --version | head -n1 | cut -d" " -f5 | cut -c 2-)

# test if the installed version already the tested/recommended update version
glcoinUpdateInstalled=$(echo "${installedVersion}" | grep -c "${glcoinVersion}")

# get latest release from GitHub releases
glcoinLatestVersion=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s https://api.github.com/repos/glcoin/glcoin/releases | jq -r '.[].tag_name' | sort | tail -n1 | cut -c 2-)

# INFO
function displayInfo() {
  echo "# basic data"
  echo "installedVersion='${installedVersion}'"
  echo "glcoinOSversion='${glcoinOSversion}'"

  echo "# the tested/recommended update option"
  echo "glcoinUpdateInstalled='${glcoinUpdateInstalled}'"
  echo "glcoinVersion='${glcoinVersion}'"

  echo "# reckless update option (latest Glcoin Core release from GitHub)"
  echo "glcoinLatestVersion='${glcoinLatestVersion}'"
}

# COMAPRE TWO VERSION STRINGS
# 0 = first version string is equal
# 1 = first version string is older
# 2 = first version string is newer
function version_compare() {
    if [[ $1 == $2 ]]
    then
        echo "equal"
        return 0
    fi
    IFS='.' read -r -a ver1 <<< "$1"
    IFS='.' read -r -a ver2 <<< "$2"
    len1=${#ver1[@]}
    len2=${#ver2[@]}
    max_len=$((len1>len2?len1:len2))
    for ((i=0; i<max_len; i++))
    do
        part1=${ver1[i]:-0}
        part2=${ver2[i]:-0}
        if ((part1 < part2))
        then
            # older
            return 1
        elif ((part1 > part2))
        then
            # newer
            return 2
        fi
    done
    # equal
    return 0
}

if [ "${mode}" = "info" ]; then
  displayInfo
  exit 1
fi

# tested
if [ "${mode}" = "tested" ]; then

  echo "# glcoin.update.sh tested"

  # check if a tested update is available
  if [ ${#glcoinVersion} -eq 0 ]; then
    echo "# warn='no tested update available'"
    echo "# thats OK on update from older versions"
    /home/admin/config.scripts/blesk.conf.sh delete glcoinInterimsUpdate 2>/dev/null
    exit 1
  fi

  # check for optional second parameter: forced update version
  fixedGlcoinVersion="$2"
  if [ ${#fixedGlcoinVersion} -gt 0 ]; then
    echo "# checking for fixed version update: installed(${installedVersion}) requested(${fixedGlcoinVersion}) available(${glcoinVersion})"
    version_compare "${fixedGlcoinVersion}" "${glcoinVersion}"
    result=$?
    if [ "${result}" -eq 2 ]; then
      echo "# WARNING: requested version is newer then available tested --> ABORT (already up2date)"
      exit 1
    else
      echo "# requested version is older or equal --> OK install available tested version"
    fi
  fi

  # check against installed version
  version_compare "${installedVersion}" "${glcoinVersion}"
  result=$?
  if [ "${result}" -eq 2 ]; then
    # this can happen if glcoin install script already has a higher version then the tested version set by this script (see above)
    echo "# installed version is newer then to be updated version --> ABORT"
    echo
    exit 1
  fi
  if [ "${result}" -eq 0 ]; then
    echo "# version is already installed --> ABORT"
    echo
    exit 1
  fi

  pathVersion=${glcoinVersion}

elif [ "${mode}" = "reckless" ]; then
  # RECKLESS
  # this mode is just for people running test and development nodes - its not recommended
  # for production nodes. In a update/recovery scenario it will not install a fixed version
  # it will always pick the latest release from the github
  echo "# glcoin.update.sh reckless"
  glcoinVersion=${glcoinLatestVersion}
  pathVersion=${glcoinVersion}

elif [ "${mode}" = "custom" ]; then
  if [ $# -gt 1 ]; then
    glcoinVersion="$2"
  else
    clear
    echo
    echo "# Update Glcoin Core to a chosen version."
    echo
    echo "# Input the version you would like to install and press ENTER."
    echo "# Examples (versions below 22.1 are not supported):"
    echo "24.0.1"
    echo "26.0"
    echo
    read glcoinVersion
  fi

  if [ $(echo ${glcoinVersion} | grep -c "rc") -gt 0 ]; then
    cutVersion=$(echo ${glcoinVersion} | awk -F"r" '{print $1}')
    rcVersion=$(echo ${glcoinVersion} | awk -F"r" '{print $2}')
    # https://glcoincore.org/bin/glcoin-core-22.0/test.rc3/
    pathVersion=${cutVersion}/test.r${rcVersion}
  else
    pathVersion=${glcoinVersion}
  fi

  if curl --output /dev/null --silent --head --fail \
    https://glcoincore.org/bin/glcoin-core-${pathVersion}/SHA256SUMS.asc; then
    echo "# OK version exists at https://glcoincore.org/bin/glcoin-core-${pathVersion}"
    if [ "${mode}" = "custom" ] && [ "$3" = "skipverify" ]; then
      echo "# skipping signature verification"
    fi
    echo "# Press ENTER to proceed to install Glcoin Core $glcoinVersion or CTRL+C to abort."
    read key
  else
    echo "# FAIL $glcoinVersion does not exist"
    echo
    echo "# Press ENTER to return to the main menu"
    read key
    exit 0
  fi
fi

# JOINED INSTALL
if [ "${mode}" = "tested" ] || [ "${mode}" = "reckless" ] || [ "${mode}" = "custom" ]; then

  displayInfo

  if [ "$installedVersion" = "$glcoinVersion" ]; then
    echo "# installedVersion = glcoinVersion"
    echo "# exiting script"
    exit 0
  fi

  echo
  echo "# clean & change into download directory"
  sudo rm -rf "${downloadDir}"
  mkdir -p "${downloadDir}"
  cd "${downloadDir}" || exit 1

  echo "# Receive signer keys"
  curl -s "https://api.github.com/repos/glcoin-core/guix.sigs/contents/builder-keys" |
    jq -r '.[].download_url' | while read url; do curl -s "$url" | gpg --import; done

  # download signed binary sha256 hash sum file
  wget --prefer-family=ipv4 --progress=bar:force -O SHA256SUMS https://glcoincore.org/bin/glcoin-core-${glcoinVersion}/SHA256SUMS
  # download the signed binary sha256 hash sum file and check
  wget --prefer-family=ipv4 --progress=bar:force -O SHA256SUMS.asc https://glcoincore.org/bin/glcoin-core-${glcoinVersion}/SHA256SUMS.asc

  if [ "${mode}" = "custom" ] && [ "$3" = "skipverify" ]; then
    echo "# skipping signature verification"
    echo "# display the output of 'gpg --verify SHA256SUMS.asc'"
    gpg --verify SHA256SUMS.asc
  else
    if gpg --verify SHA256SUMS.asc; then
      echo
      echo "****************************************"
      echo "OK --> GLCOIN MANIFEST IS CORRECT"
      echo "****************************************"
      echo
    else
      echo
      echo "# BUILD FAILED --> the PGP verification failed"
      echo "# try again or with a different version"
      echo "# if you want to skip verifying all signatures (and just show them) use the command:"
      echo "# /home/admin/config.scripts/glcoin.update.sh custom ${glcoinVersion:-<version>} skipverify"
      exit 1
    fi
  fi

  echo "# Downloading Glcoin Core v${glcoinVersion} for ${glcoinOSversion} ..."
  binaryName="glcoin-${glcoinVersion}-${glcoinOSversion}.tar.gz"
  wget https://glcoincore.org/bin/glcoin-core-${pathVersion}/${binaryName}
  if [ ! -f "./${binaryName}" ]; then
    echo "# FAIL # Downloading GLCOIN BINARY did not succeed."
    exit 1
  fi

  echo "# Checking the binary checksum ..."
  if ! sha256sum -c --ignore-missing SHA256SUMS; then
    # get the sha256 value for the corresponding platform from signed hash sum file
    glcoinSHA256=$(grep -i "${binaryName}}" SHA256SUMS | cut -d " " -f1)
    echo "# FAIL # Downloaded GLCOIN BINARY CHECKSUM:"
    echo "$(sha256sum ${binaryName})"
    echo "NOT matching SHA256 checksum:"
    echo "${glcoinSHA256}"
    exit 1
  else
    echo
    echo "# OK --> VERIFIED GLCOIN CORE BINARY CHECKSUM IS CORRECT"
    echo
  fi
fi

if [ "${mode}" = "tested" ] || [ "${mode}" = "custom" ]; then
  glcoinInterimsUpdateNew="${glcoinVersion}"
elif [ "${mode}" = "reckless" ]; then
  glcoinInterimsUpdateNew="reckless"
fi

# JOINED INSTALL
if [ "${mode}" = "tested" ] || [ "${mode}" = "reckless" ] || [ "${mode}" = "custom" ]; then

  # install
  echo "# Stopping glcoind ..."
  sudo systemctl stop glcoind 2>/dev/null
  sudo systemctl stop tglcoind 2>/dev/null
  sudo systemctl stop sglcoind 2>/dev/null
  echo
  echo "# Installing Glcoin Core v${glcoinVersion}"
  tar -xvf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin/ glcoin-${glcoinVersion}/bin/*
  sudo install -m 0644 -o root -g root -D -t /usr/local/share/man/man1 glcoin-${glcoinVersion}/share/man/man1/*
  sleep 3
  if ! sudo -u glcoin /usr/local/bin/glcoind --version | grep "${glcoinVersion}"; then
    echo
    echo "# BUILD FAILED --> Was not able to install glcoind version(${glcoinVersion})"
    exit 1
  fi

  echo "# mark update in raspiblesk config"
  /home/admin/config.scripts/blesk.conf.sh set glcoinInterimsUpdate "${glcoinInterimsUpdateNew}"

  echo "# OK Glcoin Core ${glcoinVersion} is installed"
  exit 0

else
  echo "# error='parameter not known'"
  exit 1
fi
