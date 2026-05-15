#!/bin/bash

# µD3TN (Delay-Tolerant Networking) — Bundle Protocol v7 (RFC 9171) daemon
# https://gitlab.com/d3tn/ud3tn  — Apache 2 license, D3TN GmbH
#
# Foundation for Glcoin v5 (Interplanetary Trust Federation): per-planet
# chains exchange chain-tip attestations, pad-store bundles, and pinned
# content over store-and-forward DTN bundles. This script provisions the
# router daemon and its AAP (Application Agent Protocol) socket so a
# bridge agent (separate component) can plug into it.

# pinned tag of µD3TN — bump only after testing on a Pi
UD3TN_TAG="v0.14.0"
UD3TN_REPO="https://gitlab.com/d3tn/ud3tn.git"

# default node EID (override via raspiblesk.conf: dtnEID="dtn://earth-1.glcoin/")
DEFAULT_EID="dtn://earth-1.glcoin/"

# AAP socket (local apps talk to the daemon here)
AAP_SOCKET="/var/run/ud3tn/ud3tn.aap.socket"
# BP6/BP7 TCPCL convergence layer port (RFC 7242)
TCPCL_PORT=4556

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "µD3TN Bundle Protocol daemon — Glcoin DTN bridge foundation"
  echo "bonus.dtn.sh [install|uninstall]"
  echo "bonus.dtn.sh [status|on|off|menu]"
  echo "bonus.dtn.sh set-eid <node_eid>     # e.g. dtn://mars-1.glcoin/"
  echo
  exit 1
fi

source /mnt/hdd/app-data/raspiblesk.conf 2>/dev/null

##########################
# STATUS
##########################
if [ "$1" = "status" ]; then
  installed=0
  active=0
  version=""
  nodeEID="${dtnEID:-${DEFAULT_EID}}"
  bridgeReady=0

  if [ -x /usr/local/bin/ud3tn ]; then
    installed=1
    version=$(/usr/local/bin/ud3tn --version 2>/dev/null | head -n1)
  fi
  if [ -f /etc/systemd/system/ud3tn.service ]; then
    active=$(systemctl is-active ud3tn 2>/dev/null | grep -c "^active")
  fi
  # bridgeReady = AAP socket exists and is reachable
  [ -S "${AAP_SOCKET}" ] && bridgeReady=1

  echo "installed=${installed}"
  echo "active=${active}"
  echo "version='${version}'"
  echo "nodeEID='${nodeEID}'"
  echo "tcpclPort=${TCPCL_PORT}"
  echo "aapSocket='${AAP_SOCKET}'"
  echo "bridgeReady=${bridgeReady}"
  exit 0
fi

##########################
# MENU
##########################
if [ "$1" = "menu" ]; then
  source <(sudo /home/admin/config.scripts/bonus.dtn.sh status)
  state="OFF"
  [ "${active}" = "1" ] && state="RUNNING"
  whiptail --title " DTN Bundle Daemon (µD3TN) " --msgbox \
"Glcoin v5 foundation: store-and-forward Bundle Protocol v7 router.

Status:     ${state}
Version:    ${version:-not installed}
Node EID:   ${nodeEID}
TCPCL:      0.0.0.0:${TCPCL_PORT}
AAP socket: ${aapSocket}

The bridge agent that ties this into Glcoin (chain-tip attestations,
pad-store bundles, cross-planet content anchors) is a separate
component and is not started by this script.

Bundles produced here will travel over any DTN convergence layer
(TCPCL, MTCP, serial, sneakernet) — speed of light is the only
hard floor." 18 72
  exit 0
fi

##########################
# SET-EID
##########################
if [ "$1" = "set-eid" ]; then
  newEID="$2"
  if [ -z "${newEID}" ]; then
    echo "# FAIL — usage: bonus.dtn.sh set-eid dtn://earth-1.glcoin/"
    exit 1
  fi
  case "${newEID}" in
    dtn://*) ;;
    ipn:*) ;;
    *) echo "# FAIL — EID must be a dtn:// or ipn: URI"; exit 1 ;;
  esac
  sudo /home/admin/config.scripts/blesk.conf.sh set dtnEID "${newEID}"
  echo "# OK — dtnEID set to ${newEID}"
  echo "# Restart ud3tn to apply: sudo systemctl restart ud3tn"
  exit 0
fi

##########################
# INSTALL
##########################
if [ "$1" = "install" ]; then

  if [ -x /usr/local/bin/ud3tn ]; then
    echo "result='already installed'"
    exit 0
  fi

  echo "# *** INSTALL µD3TN (Bundle Protocol v7) ***"

  # build deps for upstream µD3TN — pure C, no Python runtime required
  sudo apt-get install -y -q \
    build-essential git make pkg-config \
    libsqlite3-dev clang || exit 1

  # dedicated unprivileged user
  if ! id -u dtn >/dev/null 2>&1; then
    sudo adduser --system --group --home /var/lib/ud3tn --shell /usr/sbin/nologin dtn
  fi
  sudo mkdir -p /var/lib/ud3tn /var/log/ud3tn /var/run/ud3tn
  sudo chown -R dtn:dtn /var/lib/ud3tn /var/log/ud3tn /var/run/ud3tn

  # clone + pin
  SRC=/home/admin/ud3tn-src
  sudo rm -rf "${SRC}"
  sudo -u admin git clone --depth 1 --branch "${UD3TN_TAG}" "${UD3TN_REPO}" "${SRC}" || exit 1
  cd "${SRC}" || exit 1
  # build the C daemon target only (avoid Python pyd3tn tests)
  sudo -u admin make -j"$(nproc)" posix || exit 1

  # install binary
  sudo install -m 755 build/posix/ud3tn /usr/local/bin/ud3tn
  if [ -x build/posix/aap2/aap2-tools ]; then
    sudo install -m 755 build/posix/aap2/aap2-tools /usr/local/bin/aap2-tools
  fi

  # baseline config — single TCPCL CLA listener, AAP socket
  sudo install -d -o dtn -g dtn -m 750 /etc/ud3tn
  sudo tee /etc/ud3tn/contacts.json >/dev/null <<'EOF'
{
  "contacts": []
}
EOF
  sudo chown dtn:dtn /etc/ud3tn/contacts.json

  # systemd unit
  sudo tee /etc/systemd/system/ud3tn.service >/dev/null <<EOF
[Unit]
Description=µD3TN Bundle Protocol daemon (Glcoin DTN bridge foundation)
Documentation=https://gitlab.com/d3tn/ud3tn
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=dtn
Group=dtn
EnvironmentFile=-/etc/default/ud3tn
RuntimeDirectory=ud3tn
RuntimeDirectoryMode=0750
ExecStart=/usr/local/bin/ud3tn \\
  --eid \${UD3TN_EID} \\
  --bp-version 7 \\
  --aap-socket ${AAP_SOCKET} \\
  --cla "tcpclv3:*,${TCPCL_PORT}"
Restart=on-failure
RestartSec=10

# Hardening
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

  # default EID (overridable via /etc/default/ud3tn or raspiblesk.conf)
  sudo tee /etc/default/ud3tn >/dev/null <<EOF
# µD3TN node EID. Change per planet/installation.
UD3TN_EID=${DEFAULT_EID}
EOF
  sudo systemctl daemon-reload
  echo "result='OK'"
  exit 0
fi

##########################
# UNINSTALL
##########################
if [ "$1" = "uninstall" ]; then
  # refuse if still active
  if [ -f /etc/systemd/system/ud3tn.service ]; then
    isActive=$(systemctl is-active ud3tn 2>/dev/null | grep -c "^active")
    if [ "${isActive}" -gt 0 ]; then
      echo "result='still active — run bonus.dtn.sh off first'"
      exit 1
    fi
  fi
  sudo rm -f /usr/local/bin/ud3tn /usr/local/bin/aap2-tools
  sudo rm -f /etc/systemd/system/ud3tn.service /etc/default/ud3tn
  sudo rm -rf /etc/ud3tn /var/lib/ud3tn /var/log/ud3tn /var/run/ud3tn
  sudo rm -rf /home/admin/ud3tn-src
  sudo systemctl daemon-reload
  if id -u dtn >/dev/null 2>&1; then
    sudo userdel dtn 2>/dev/null
  fi
  echo "result='OK'"
  exit 0
fi

# everything below stops the service first
if [ "$1" = "1" ] || [ "$1" = "on" ] || [ "$1" = "0" ] || [ "$1" = "off" ]; then
  sudo systemctl stop ud3tn 2>/dev/null
fi

##########################
# ON
##########################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ ! -x /usr/local/bin/ud3tn ]; then
    /home/admin/config.scripts/bonus.dtn.sh install || exit 1
  fi

  # apply EID override from raspiblesk.conf if present
  if [ -n "${dtnEID}" ]; then
    sudo sed -i "s|^UD3TN_EID=.*|UD3TN_EID=${dtnEID}|g" /etc/default/ud3tn
  fi

  # open TCPCL port — convergence layer is reachable from other DTN nodes
  sudo ufw allow "${TCPCL_PORT}/tcp" comment 'ud3tn TCPCLv3' >/dev/null 2>&1

  sudo systemctl enable ud3tn
  sudo systemctl start ud3tn
  sleep 2

  isActive=$(systemctl is-active ud3tn 2>/dev/null | grep -c "^active")
  if [ "${isActive}" -ne 1 ]; then
    echo "# WARN: ud3tn did not start cleanly — check: journalctl -u ud3tn -n 50"
  fi

  sudo /home/admin/config.scripts/blesk.conf.sh set dtn "on"
  echo "result='OK'"
  exit 0
fi

##########################
# OFF
##########################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  sudo systemctl disable ud3tn 2>/dev/null
  sudo rm -f /etc/systemd/system/ud3tn.service
  sudo systemctl daemon-reload
  sudo ufw delete allow "${TCPCL_PORT}/tcp" >/dev/null 2>&1
  sudo /home/admin/config.scripts/blesk.conf.sh set dtn "off"
  echo "result='OK'"
  exit 0
fi

echo "error='unknown parameter'"
exit 1
