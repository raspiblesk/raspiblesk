#!/bin/bash

# *** KUBO (IPFS) ***
# Mandatory dependency for Glcoin 0.2.x — provides the local HTTP API
# (-ipfsapi=127.0.0.1:5001) that glcoind uses for auto-pin of glc1/glc2/glc3
# IPFS commitments and that glcoin_miner.py uses to verify anchored CIDs.
#
# Source: https://dist.ipfs.tech/kubo/<version>/kubo_<version>_linux-arm64.tar.gz
# Pinned prebuilt (no Go toolchain needed on the Pi).

KUBO_VERSION="v0.41.0"
KUBO_USER="kubo"
KUBO_HOME="/home/kubo"
KUBO_DATA_DIR="/mnt/hdd/app-storage/kubo"
KUBO_API_PORT="5001"
# Gateway pinned to 5080 (NOT the IPFS default 8080) because LND's REST API
# claims 127.0.0.1:8080 and would otherwise refuse to bind. 5080 is unused on
# the RaspiBlesk port map.
KUBO_GW_PORT="5080"
KUBO_SWARM_PORT="4001"

# SHA-256 pins for the bundled tarball (verified at bundle creation time).
SHA256_KUBO_arm64="df1c1755fb5e059fe381431168efd6faf3a14d532fbd5f8716114cfca8b6950e"
SHA256_KUBO_amd64="6d1927f82a5ea77d02957d6fc8478f42c2a08c2a8fecd6328b3b177cd6352ab8"

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "kubo.install.sh install          - extract binary, create user, init datastore, install systemd unit"
  echo "kubo.install.sh ensure-datastore - re-init datastore if missing (called as ExecStartPre by kubo.service)"
  echo "kubo.install.sh on               - enable + start kubo.service"
  echo "kubo.install.sh off              - stop + disable kubo.service"
  echo "kubo.install.sh status           - report version + service status"
  echo "kubo.install.sh uninstall        - remove binary, service, user (keeps datastore)"
  echo "kubo.install.sh purge            - uninstall + delete datastore"
  echo
  exit 1
fi

# ---------------------------------------------------------------------------
# ensure-datastore — self-heal hook called as ExecStartPre by kubo.service
#
# Why this exists: blesk.data.sh link (first boot) only migrates the glcoin
# subtree from the SD-card build-time location to the freshly-mounted nvme
# partition. The kubo datastore that kubo.install.sh initialised at build
# time lives under /mnt/raspiblesk-data/app-storage/kubo on SD and is NOT
# carried over. After first boot, /mnt/hdd/app-storage/kubo resolves through
# the new symlink chain to a nonexistent path, so systemd's NAMESPACE setup
# fails (ReadWritePaths refuses to mount a missing directory) and the
# service crashes 226/NAMESPACE in an endless restart loop.
#
# Self-heal: if ${KUBO_DATA_DIR}/config is missing, recreate the dir + run
# ipfs init + re-apply the API/Gateway port pin. Idempotent on healthy state.
# ---------------------------------------------------------------------------
if [ "$1" = "ensure-datastore" ]; then
  if [ ! -f "${KUBO_DATA_DIR}/config" ]; then
    echo "# ensure-datastore: ${KUBO_DATA_DIR}/config missing — re-initialising"
    mkdir -p "${KUBO_DATA_DIR}"
    chown -R "${KUBO_USER}:${KUBO_USER}" "${KUBO_DATA_DIR}"
    chmod 0750 "${KUBO_DATA_DIR}"
    sudo -u "${KUBO_USER}" IPFS_PATH="${KUBO_DATA_DIR}" /usr/local/bin/ipfs init --profile=server,lowpower
    sudo -u "${KUBO_USER}" IPFS_PATH="${KUBO_DATA_DIR}" /usr/local/bin/ipfs config \
      Addresses.API "/ip4/127.0.0.1/tcp/${KUBO_API_PORT}"
    sudo -u "${KUBO_USER}" IPFS_PATH="${KUBO_DATA_DIR}" /usr/local/bin/ipfs config \
      Addresses.Gateway "/ip4/127.0.0.1/tcp/${KUBO_GW_PORT}"
    echo "# ensure-datastore: ok"
  fi
  # Kubo v0.41 ships the nopfs plugin enabled by default; it walks
  # ${XDG_CONFIG_HOME}/ipfs/denylists/ (= /home/kubo/.config/ipfs/denylists/)
  # at daemon start and aborts on EACCES. Pre-create the directory with
  # kubo ownership so the walk finds an empty (no denylists) tree. The
  # service unit also drops ProtectHome=true → ProtectHome=tmpfs+BindPaths
  # so the namespace exposes /home/kubo.
  mkdir -p "${KUBO_HOME}/.config/ipfs/denylists"
  chown -R "${KUBO_USER}:${KUBO_USER}" "${KUBO_HOME}/.config"
  chmod 0755 "${KUBO_HOME}/.config" "${KUBO_HOME}/.config/ipfs" "${KUBO_HOME}/.config/ipfs/denylists"
  exit 0
fi

# verify_sha256 <file> <expected> <name>
verify_sha256() {
  local _file="$1"; local _expected="$2"; local _name="$3"
  if [ ! -f "${_file}" ]; then
    echo "# FAIL - ${_name} file ${_file} not found"; exit 1
  fi
  local _actual
  _actual="$(sha256sum "${_file}" | awk '{print $1}')"
  if [ "${_actual}" != "${_expected}" ]; then
    echo "# FAIL - SHA-256 mismatch for ${_name}"
    echo "#   expected: ${_expected}"
    echo "#   got:      ${_actual}"
    rm -f "${_file}" 2>/dev/null
    exit 1
  fi
  echo "# OK - ${_name} sha256 verified (${_expected:0:16}…)"
}

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
if [ "$1" = "install" ]; then
  # idempotency: if binary present and version matches, skip
  if command -v ipfs >/dev/null 2>&1; then
    have="$(/usr/local/bin/ipfs --version 2>/dev/null | awk '{print $3}')"
    if [ "${have}" = "${KUBO_VERSION#v}" ]; then
      echo "# kubo ${KUBO_VERSION} already installed — skipping binary install"
      already=1
    fi
  fi

  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "${arch}" in
    arm64|aarch64) tarball_arch="arm64"; expected_sha="${SHA256_KUBO_arm64}";;
    amd64|x86_64)  tarball_arch="amd64"; expected_sha="${SHA256_KUBO_amd64}";;
    *) echo "# FAIL - unsupported arch: ${arch}"; exit 1;;
  esac

  bundle="/home/admin/assets/kubo-${KUBO_VERSION}-linux-${tarball_arch}.tar.gz"
  if [ "${already}" != "1" ]; then
    if [ ! -f "${bundle}" ]; then
      echo "# bundled kubo not found at ${bundle} — downloading from dist.ipfs.tech"
      tmp_bundle="/tmp/kubo-${KUBO_VERSION}-linux-${tarball_arch}.tar.gz"
      curl --fail --connect-timeout 30 --max-time 300 -sSLo "${tmp_bundle}" \
        "https://dist.ipfs.tech/kubo/${KUBO_VERSION}/kubo_${KUBO_VERSION}_linux-${tarball_arch}.tar.gz" \
        || { echo "# FAIL - kubo download failed"; exit 1; }
      bundle="${tmp_bundle}"
    fi
    verify_sha256 "${bundle}" "${expected_sha}" "kubo ${KUBO_VERSION} (${tarball_arch})"

    echo "# extracting kubo binary"
    tmp_extract="$(mktemp -d -t kubo-extract.XXXXXX)"
    tar -xzf "${bundle}" -C "${tmp_extract}"
    if [ ! -x "${tmp_extract}/kubo/ipfs" ]; then
      echo "# FAIL - extracted tarball has no kubo/ipfs binary"
      rm -rf "${tmp_extract}"
      exit 1
    fi
    sudo install -m 0755 -o root -g root "${tmp_extract}/kubo/ipfs" /usr/local/bin/ipfs
    rm -rf "${tmp_extract}"
  fi

  # user + home
  if ! id -u "${KUBO_USER}" >/dev/null 2>&1; then
    echo "# creating ${KUBO_USER} system user"
    sudo adduser --system --group --home "${KUBO_HOME}" "${KUBO_USER}"
  fi

  # datastore
  sudo mkdir -p "${KUBO_DATA_DIR}"
  sudo chown -R "${KUBO_USER}:${KUBO_USER}" "${KUBO_DATA_DIR}"
  sudo chmod 0750 "${KUBO_DATA_DIR}"

  # init datastore (idempotent — ipfs init refuses if already done)
  if [ ! -f "${KUBO_DATA_DIR}/config" ]; then
    echo "# initialising kubo datastore at ${KUBO_DATA_DIR}"
    sudo -u "${KUBO_USER}" IPFS_PATH="${KUBO_DATA_DIR}" /usr/local/bin/ipfs init --profile=server,lowpower
  else
    echo "# kubo datastore already initialised at ${KUBO_DATA_DIR} — skipping init"
  fi

  # tighten config: bind API + Gateway to 127.0.0.1 only (no remote control)
  sudo -u "${KUBO_USER}" IPFS_PATH="${KUBO_DATA_DIR}" /usr/local/bin/ipfs config \
    Addresses.API "/ip4/127.0.0.1/tcp/${KUBO_API_PORT}"
  sudo -u "${KUBO_USER}" IPFS_PATH="${KUBO_DATA_DIR}" /usr/local/bin/ipfs config \
    Addresses.Gateway "/ip4/127.0.0.1/tcp/${KUBO_GW_PORT}"

  # systemd unit
  echo "# installing kubo.service systemd unit"
  cat <<EOF | sudo tee /etc/systemd/system/kubo.service >/dev/null
[Unit]
Description=Kubo (IPFS) daemon for Glcoin
After=network-online.target
Wants=network-online.target

[Service]
User=${KUBO_USER}
Group=${KUBO_USER}
Environment=IPFS_PATH=${KUBO_DATA_DIR}
# ensure-datastore is a self-heal that re-creates ${KUBO_DATA_DIR} + runs
# ipfs init if the build-time datastore did not survive the first-boot
# SD->nvme migration in blesk.data.sh link. The "+" prefix runs the prestart
# as root (overriding User=kubo) so it can mkdir/chown into /mnt/hdd. systemd
# evaluates the namespace BEFORE any ExecStartPre, so ReadWritePaths must
# tolerate a missing path with the "-" prefix — otherwise the prestart never
# even gets a chance to run.
ExecStartPre=+/home/admin/config.scripts/kubo.install.sh ensure-datastore
ExecStart=/usr/local/bin/ipfs daemon --migrate=true --agent-version-suffix=glcoin
Restart=on-failure
RestartSec=10
TimeoutStartSec=180
LimitNOFILE=8192

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
# ProtectHome=tmpfs masks all other /home/* trees but the BindPaths line
# explicitly mounts kubo's home back in. Required because kubo's nopfs
# plugin (default in v0.41) reads ${HOME}/.config/ipfs/denylists/ at
# daemon start and aborts on EACCES — which ProtectHome=true causes
# (lstat fails before any permission check). See ensure-datastore for
# the mkdir of the denylists dir.
ProtectHome=tmpfs
BindPaths=${KUBO_HOME}
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadWritePaths=-${KUBO_DATA_DIR}

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable kubo.service
  echo "# OK - kubo.service is enabled"

  # firewall: API + Gateway are 127.0.0.1 only; only the swarm port faces the LAN
  if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow "${KUBO_SWARM_PORT}/tcp" comment 'kubo libp2p swarm' >/dev/null 2>&1 || true
    sudo ufw allow "${KUBO_SWARM_PORT}/udp" comment 'kubo libp2p swarm' >/dev/null 2>&1 || true
  fi

  echo "# kubo install complete"
  exit 0
fi

# ---------------------------------------------------------------------------
# on / off
# ---------------------------------------------------------------------------
if [ "$1" = "on" ] || [ "$1" = "1" ]; then
  sudo systemctl enable kubo.service
  sudo systemctl start kubo.service
  echo "# kubo.service started"
  exit 0
fi

if [ "$1" = "off" ] || [ "$1" = "0" ]; then
  sudo systemctl stop kubo.service 2>/dev/null
  sudo systemctl disable kubo.service 2>/dev/null
  echo "# kubo.service stopped"
  exit 0
fi

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------
if [ "$1" = "status" ]; then
  if command -v ipfs >/dev/null 2>&1; then
    echo "version='$(/usr/local/bin/ipfs --version 2>/dev/null | awk '{print $3}')'"
  else
    echo "version=''"
  fi
  if [ -f /etc/systemd/system/kubo.service ]; then
    echo "installed=1"
  else
    echo "installed=0"
  fi
  if systemctl is-active --quiet kubo.service 2>/dev/null; then
    echo "active=1"
  else
    echo "active=0"
  fi
  echo "datadir='${KUBO_DATA_DIR}'"
  echo "apiPort='${KUBO_API_PORT}'"
  exit 0
fi

# ---------------------------------------------------------------------------
# uninstall / purge
# ---------------------------------------------------------------------------
if [ "$1" = "uninstall" ] || [ "$1" = "purge" ]; then
  sudo systemctl stop kubo.service 2>/dev/null
  sudo systemctl disable kubo.service 2>/dev/null
  sudo rm -f /etc/systemd/system/kubo.service
  sudo systemctl daemon-reload
  sudo rm -f /usr/local/bin/ipfs
  if id -u "${KUBO_USER}" >/dev/null 2>&1; then
    sudo userdel -rf "${KUBO_USER}" 2>/dev/null
  fi
  if [ "$1" = "purge" ]; then
    sudo rm -rf "${KUBO_DATA_DIR}"
    echo "# kubo purged (binary, service, user, datastore)"
  else
    echo "# kubo uninstalled (datastore preserved at ${KUBO_DATA_DIR})"
  fi
  exit 0
fi

echo "error='unknown parameter: $1'"
exit 1
