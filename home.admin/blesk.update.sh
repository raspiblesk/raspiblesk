#!/bin/bash

# blesk.update.sh - In-place GitHub-based update system for RaspiBlesk
# No SD-card reflash required.
#
# Usage:
#   blesk.update.sh check    - compare installed codeVersion vs latest GitHub release tag
#   blesk.update.sh scripts  - git pull + sync home.admin files to /home/admin/, restart services
#   blesk.update.sh lnd      - download Glcoin-patched LND tarball from GitHub Releases, swap binary
#   blesk.update.sh glcoin   - download new src tarball from GitHub Releases, rebuild, restart daemon
#   blesk.update.sh all      - scripts -> lnd -> glcoin in sequence

RASPIBLESK_GITHUB_ORG="raspiblesk"
RASPIBLESK_GITHUB_REPO="raspiblesk"
GLCOIN_GITHUB_ORG="glcoin"
GLCOIN_GITHUB_REPO="glcoin"

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "blesk.update.sh check    - compare installed version vs latest GitHub release"
  echo "blesk.update.sh scripts  - git pull + sync home.admin files, restart services"
  echo "blesk.update.sh lnd      - update Glcoin-patched LND binary from GitHub Releases"
  echo "blesk.update.sh glcoin   - rebuild Glcoin Core from GitHub Release source tarball"
  echo "blesk.update.sh all      - scripts -> lnd -> glcoin in sequence"
  exit 1
fi

mode="$1"

err()  { echo "# ERROR: $*" >&2; exit 1; }
info() { echo "# $*"; }

detect_arch() {
  if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
    echo "armv7"
  elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
    echo "arm64"
  elif [ "$(uname -m | grep -c 'x86_64')" -gt 0 ]; then
    echo "amd64"
  else
    err "Unsupported architecture: $(uname -m)"
  fi
}

github_latest_tag() {
  local org="$1" repo="$2"
  curl --header "X-GitHub-Api-Version:2022-11-28" -sf \
    "https://api.github.com/repos/${org}/${repo}/releases/latest" \
    | jq -r '.tag_name' 2>/dev/null
}

# returns: 0=equal 1=v1<v2 2=v1>v2  (strips leading 'v'; non-numeric suffixes ignored per-segment)
version_compare() {
  local v1="${1#v}" v2="${2#v}"
  [ "$v1" = "$v2" ] && return 0
  IFS='.' read -r -a a1 <<< "$v1"
  IFS='.' read -r -a a2 <<< "$v2"
  local max=$(( ${#a1[@]} > ${#a2[@]} ? ${#a1[@]} : ${#a2[@]} ))
  for (( i=0; i<max; i++ )); do
    local p1 p2
    p1=$(echo "${a1[i]:-0}" | grep -o '^[0-9]*'); p1="${p1:-0}"
    p2=$(echo "${a2[i]:-0}" | grep -o '^[0-9]*'); p2="${p2:-0}"
    (( p1 < p2 )) && return 1
    (( p1 > p2 )) && return 2
  done
  return 0
}

# -----------------------------------------------------------------------
# check
# -----------------------------------------------------------------------
if [ "$mode" = "check" ]; then

  source /home/admin/_version.info 2>/dev/null || err "_version.info not found at /home/admin/_version.info"

  info "Installed version : v${codeVersion} (${codeRelease})"
  info "Querying GitHub for latest ${RASPIBLESK_GITHUB_ORG}/${RASPIBLESK_GITHUB_REPO} release ..."

  latestTag=$(github_latest_tag "$RASPIBLESK_GITHUB_ORG" "$RASPIBLESK_GITHUB_REPO")
  if [ -z "$latestTag" ] || [ "$latestTag" = "null" ]; then
    err "Could not fetch latest release tag — check internet connectivity"
  fi
  latestVersion="${latestTag#v}"

  info "Latest release    : ${latestTag}"

  version_compare "${codeVersion}" "${latestVersion}"
  cmpResult=$?

  echo "installedVersion='${codeVersion}'"
  echo "latestVersion='${latestVersion}'"

  if [ $cmpResult -eq 0 ]; then
    echo "updateAvailable='0'"
    info "Already up to date."
  elif [ $cmpResult -eq 1 ]; then
    echo "updateAvailable='1'"
    info "Update available: v${codeVersion} -> v${latestVersion}"
    info "Run: blesk.update.sh all"
  else
    echo "updateAvailable='0'"
    info "Installed version is ahead of latest release (dev build)."
  fi
  exit 0
fi

# -----------------------------------------------------------------------
# scripts
# -----------------------------------------------------------------------
if [ "$mode" = "scripts" ]; then

  info "=== UPDATE SCRIPTS ==="

  REPO_DIR="/home/admin/raspiblesk"
  [ -d "${REPO_DIR}/.git" ] || err "Git repo not found at ${REPO_DIR} — cannot update scripts"

  info "Pulling latest code from GitHub ..."
  cd "${REPO_DIR}" || err "Cannot cd to ${REPO_DIR}"
  git config pull.rebase true
  git pull || err "git pull failed"

  cd ..
  info "Syncing home.admin files to /home/admin/ ..."

  sudo -u admin cp "${REPO_DIR}/home.admin/.tmux.conf" /home/admin/ 2>/dev/null
  sudo -u admin cp "${REPO_DIR}/home.admin"/*.* /home/admin/ 2>/dev/null
  sudo -u admin chmod 755 /home/admin/*.sh

  sudo rm -rf /home/admin/assets
  sudo -u admin cp -R "${REPO_DIR}/home.admin/assets" /home/admin/assets

  sudo rm -rf /home/admin/config.scripts
  sudo -u admin cp -R "${REPO_DIR}/home.admin/config.scripts" /home/admin/config.scripts
  sudo -u admin chmod 755 /home/admin/config.scripts/*.sh
  find /home/admin/config.scripts -name "*.py" -exec sudo -u admin chmod 755 {} \; 2>/dev/null

  if [ -d "${REPO_DIR}/home.admin/setup.scripts" ]; then
    sudo rm -rf /home/admin/setup.scripts
    sudo -u admin cp -R "${REPO_DIR}/home.admin/setup.scripts" /home/admin/setup.scripts
    find /home/admin/setup.scripts -name "*.sh" -exec sudo -u admin chmod 755 {} \; 2>/dev/null
  fi

  info "Restarting web services ..."
  if [ -f /home/admin/config.scripts/blesk.web.api.sh ]; then
    sudo /home/admin/config.scripts/blesk.web.api.sh update-code 2>/dev/null
  fi
  if [ -f /home/admin/config.scripts/blesk.web.ui.sh ]; then
    sudo /home/admin/config.scripts/blesk.web.ui.sh update 2>/dev/null
  fi

  info "=== SCRIPTS UPDATE DONE — reboot recommended ==="
  exit 0
fi

# -----------------------------------------------------------------------
# lnd
# -----------------------------------------------------------------------
if [ "$mode" = "lnd" ]; then

  info "=== UPDATE LND ==="

  LND_INSTALL_SH="/home/admin/config.scripts/lnd.install.sh"
  [ -f "${LND_INSTALL_SH}" ] || err "lnd.install.sh not found at ${LND_INSTALL_SH}"

  lndVersion=$(grep   '^lndVersion='      "${LND_INSTALL_SH}" | cut -d'"' -f2)
  glcoinRelease=$(grep '^GLCOIN_RELEASE=' "${LND_INSTALL_SH}" | cut -d'"' -f2)

  [ -n "${lndVersion}" ]    || err "Could not read lndVersion from ${LND_INSTALL_SH}"
  [ -n "${glcoinRelease}" ] || err "Could not read GLCOIN_RELEASE from ${LND_INSTALL_SH}"

  lndArch=$(detect_arch)
  TARBALL="lnd-glcoin-${lndVersion}-linux-${lndArch}.tar.gz"
  DOWNLOAD_URL="https://github.com/${RASPIBLESK_GITHUB_ORG}/${RASPIBLESK_GITHUB_REPO}/releases/download/${glcoinRelease}/${TARBALL}"
  DEST="/tmp/${TARBALL}"

  installedLndVersion=$(lnd --version 2>/dev/null | cut -d" " -f3)
  info "Installed LND : ${installedLndVersion:-not installed}"
  info "Target LND    : ${lndVersion}"
  info "Architecture  : ${lndArch}"

  if [ "${installedLndVersion}" = "${lndVersion}" ]; then
    info "LND is already at version ${lndVersion}. Nothing to do."
    exit 0
  fi

  if [ ! -f "${DEST}" ]; then
    info "Downloading ${TARBALL} ..."
    wget -q --show-progress --timeout=120 -O "${DEST}" "${DOWNLOAD_URL}" || {
      rm -f "${DEST}"
      err "Failed to download LND tarball from ${DOWNLOAD_URL}"
    }
  else
    info "Using cached tarball at ${DEST}"
  fi

  info "Stopping lnd service ..."
  sudo systemctl stop lnd 2>/dev/null

  EXTRACT_DIR="/home/admin/download/lnd.update"
  mkdir -p "${EXTRACT_DIR}"
  tar -xzf "${DEST}" -C "${EXTRACT_DIR}" || err "Could not extract ${DEST}"

  # binaries are at the top level of the tarball
  sudo install -m 0755 -o root -g root "${EXTRACT_DIR}/lnd"   /usr/local/bin/lnd   || err "install lnd failed"
  sudo install -m 0755 -o root -g root "${EXTRACT_DIR}/lncli" /usr/local/bin/lncli || err "install lncli failed"
  rm -rf "${EXTRACT_DIR}"

  info "Starting lnd service ..."
  sudo systemctl start lnd

  newVersion=$(lnd --version 2>/dev/null | cut -d" " -f3)
  info "LND version now: ${newVersion}"
  info "=== LND UPDATE DONE ==="
  exit 0
fi

# -----------------------------------------------------------------------
# glcoin
# -----------------------------------------------------------------------
if [ "$mode" = "glcoin" ]; then

  info "=== UPDATE GLCOIN CORE ==="

  installedGlcoinVersion=$(sudo -u glcoin glcoind --version 2>/dev/null | head -1 | cut -d" " -f5 | cut -c2-)
  info "Installed Glcoin : ${installedGlcoinVersion:-not installed}"

  info "Querying GitHub for latest ${GLCOIN_GITHUB_ORG}/${GLCOIN_GITHUB_REPO} release ..."
  latestTag=$(github_latest_tag "$GLCOIN_GITHUB_ORG" "$GLCOIN_GITHUB_REPO")
  if [ -z "$latestTag" ] || [ "$latestTag" = "null" ]; then
    err "Could not fetch latest Glcoin release tag — check internet connectivity"
  fi
  latestVersion="${latestTag#v}"

  info "Latest Glcoin    : v${latestVersion}"

  if [ -n "${installedGlcoinVersion}" ]; then
    version_compare "${installedGlcoinVersion}" "${latestVersion}"
    cmpResult=$?
    if [ $cmpResult -eq 0 ]; then
      info "Glcoin Core is already at version ${latestVersion}. Nothing to do."
      exit 0
    fi
  fi

  TARBALL="glcoin-${latestVersion}-src.tar.gz"
  DOWNLOAD_URL="https://github.com/${GLCOIN_GITHUB_ORG}/${GLCOIN_GITHUB_REPO}/releases/download/${latestTag}/${TARBALL}"
  DEST="/tmp/${TARBALL}"
  BUILD_LOG="/tmp/glcoin-build-${latestVersion}.log"

  if [ ! -f "${DEST}" ]; then
    info "Downloading ${TARBALL} ..."
    wget -q --show-progress --timeout=600 -O "${DEST}" "${DOWNLOAD_URL}" || {
      rm -f "${DEST}"
      err "Failed to download Glcoin source tarball from ${DOWNLOAD_URL}"
    }
  else
    info "Using cached tarball at ${DEST}"
  fi

  info "Starting background build of Glcoin Core v${latestVersion} ..."
  info "Build log: ${BUILD_LOG}"
  info "(On Raspberry Pi this takes 30-90 minutes)"

  BUILD_CMD="/home/admin/config.scripts/glcoin.install.sh install \"${DEST}\""
  FINISH_CMD="sudo systemctl restart glcoind && echo '# Glcoin daemon restarted.'"
  FULL_CMD="${BUILD_CMD} 2>&1 | tee ${BUILD_LOG}; EXIT=\${PIPESTATUS[0]}; if [ \$EXIT -eq 0 ]; then ${FINISH_CMD}; else echo '# BUILD FAILED — check ${BUILD_LOG}'; fi"

  if command -v tmux &>/dev/null; then
    tmux new-session -d -s glcoin_update "bash -c '${FULL_CMD}'" 2>/dev/null
    info "Build running in tmux session 'glcoin_update'."
    info "Attach with: tmux attach -t glcoin_update"
  else
    info "tmux not available — using nohup background process"
    # shellcheck disable=SC2094
    nohup bash -c "${FULL_CMD}" >> "${BUILD_LOG}" 2>&1 &
    info "Build PID: $!"
  fi

  info "Monitor progress: tail -f ${BUILD_LOG}"
  info "glcoind will restart automatically when the build finishes."
  info "=== GLCOIN UPDATE STARTED ==="
  exit 0
fi

# -----------------------------------------------------------------------
# all
# -----------------------------------------------------------------------
if [ "$mode" = "all" ]; then

  info "=== FULL UPDATE: scripts -> lnd -> glcoin ==="
  echo

  "$0" scripts || err "scripts update failed — aborting"
  echo
  "$0" lnd     || err "lnd update failed — aborting"
  echo
  "$0" glcoin  || err "glcoin update failed"
  echo

  info "=== FULL UPDATE COMPLETE ==="
  info "Glcoin Core build is running in the background."
  info "Monitor: tail -f /tmp/glcoin-build-*.log"
  exit 0
fi

err "Unknown command: '$mode'. Run without arguments for usage."
