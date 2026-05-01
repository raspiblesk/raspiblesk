#!/bin/bash

# WireGuard VPN — self-hosted admin tunnel
# Keeps admin access (SSH, web UI) available even in Tor-only mode.
# Server: 10.9.0.1 (Pi), peers start at 10.9.0.2

WG_CONF="/etc/wireguard/wg0.conf"
WG_DIR="/etc/wireguard"
WG_PORT=51820
WG_SUBNET="10.9.0"
WG_SERVER_IP="10.9.0.1"
PEER_STORE="/mnt/hdd/app-data/wireguard"

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "internet.wireguard.sh [on|off|menu|status]"
  echo "internet.wireguard.sh addpeer <name>"
  echo "internet.wireguard.sh removepeer <name>"
  echo "internet.wireguard.sh showpeer <name>"
  exit 1
fi

source /mnt/hdd/app-data/raspiblesk.conf 2>/dev/null
source /home/admin/raspiblesk.info 2>/dev/null

# detect primary outbound interface
IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
[ -z "${IFACE}" ] && IFACE="eth0"

##############
# STATUS
##############
if [ "$1" = "status" ]; then
  isInstalled=0
  [ -f "${WG_CONF}" ] && isInstalled=1
  echo "isInstalled=${isInstalled}"

  isRunning=0
  systemctl is-active --quiet wg-quick@wg0 2>/dev/null && isRunning=1
  echo "isRunning=${isRunning}"

  publicIP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "unknown")
  echo "publicIP=${publicIP}"
  echo "wgPort=${WG_PORT}"
  echo "serverIP=${WG_SERVER_IP}"

  if [ ${isRunning} -eq 1 ]; then
    peerCount=$(sudo wg show wg0 peers 2>/dev/null | wc -l)
    echo "peerCount=${peerCount}"
  fi
  exit 0
fi

##############
# ON / INSTALL
##############
if [ "$1" = "on" ] || [ "$1" = "1" ]; then

  if [ -f "${WG_CONF}" ]; then
    echo "result='already installed'"
    exit 0
  fi

  echo "# Installing WireGuard..."
  apt-get install -y wireguard wireguard-tools qrencode 2>/dev/null

  # enable IP forwarding
  grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || \
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1

  # generate server keys
  mkdir -p "${WG_DIR}"
  chmod 700 "${WG_DIR}"
  SERVER_PRIVKEY=$(wg genkey)
  SERVER_PUBKEY=$(echo "${SERVER_PRIVKEY}" | wg pubkey)

  # write server config
  cat > "${WG_CONF}" << EOF
[Interface]
PrivateKey = ${SERVER_PRIVKEY}
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${IFACE} -j MASQUERADE
EOF
  chmod 600 "${WG_CONF}"

  # store public key for peer generation
  mkdir -p "${PEER_STORE}"
  echo "${SERVER_PUBKEY}" > "${PEER_STORE}/server.pub"
  echo "${WG_PORT}" > "${PEER_STORE}/server.port"

  # firewall — allow WireGuard UDP (survives Tor-only mode switch)
  ufw allow ${WG_PORT}/udp comment 'WireGuard VPN'

  # enable and start
  systemctl enable wg-quick@wg0
  systemctl start wg-quick@wg0

  /home/admin/config.scripts/blesk.conf.sh set wireguard "on"

  echo "# OK - WireGuard installed and running"
  echo "# Add a peer with: internet.wireguard.sh addpeer <name>"
  exit 0
fi

##############
# OFF / UNINSTALL
##############
if [ "$1" = "off" ] || [ "$1" = "0" ]; then

  systemctl stop wg-quick@wg0 2>/dev/null
  systemctl disable wg-quick@wg0 2>/dev/null
  ufw delete allow ${WG_PORT}/udp 2>/dev/null
  rm -f "${WG_CONF}"
  rm -rf "${PEER_STORE}"
  /home/admin/config.scripts/blesk.conf.sh delete wireguard 2>/dev/null

  echo "# OK - WireGuard removed"
  exit 0
fi

##############
# ADD PEER
##############
if [ "$1" = "addpeer" ]; then

  PEER_NAME="$2"
  if [ -z "${PEER_NAME}" ]; then
    echo "error='usage: internet.wireguard.sh addpeer <name>'"
    exit 1
  fi

  if [ ! -f "${WG_CONF}" ]; then
    echo "error='WireGuard not installed — run: internet.wireguard.sh on'"
    exit 1
  fi

  SERVER_PUBKEY=$(cat "${PEER_STORE}/server.pub" 2>/dev/null)
  if [ -z "${SERVER_PUBKEY}" ]; then
    echo "error='server public key not found'"
    exit 1
  fi

  # assign next available IP
  USED=$(grep "AllowedIPs" "${WG_CONF}" | grep -oP '10\.9\.0\.\K\d+' | sort -n | tail -1)
  NEXT=$(( ${USED:-1} + 1 ))
  PEER_IP="${WG_SUBNET}.${NEXT}"

  # generate peer keys
  PEER_PRIVKEY=$(wg genkey)
  PEER_PUBKEY=$(echo "${PEER_PRIVKEY}" | wg pubkey)
  PEER_PSK=$(wg genpsk)

  # get public IP for endpoint
  PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "YOUR_PUBLIC_IP")

  # append peer to server config
  cat >> "${WG_CONF}" << EOF

# Peer: ${PEER_NAME}
[Peer]
PublicKey = ${PEER_PUBKEY}
PresharedKey = ${PEER_PSK}
AllowedIPs = ${PEER_IP}/32
EOF

  # build client config
  PEER_CONF="${PEER_STORE}/${PEER_NAME}.conf"
  cat > "${PEER_CONF}" << EOF
[Interface]
PrivateKey = ${PEER_PRIVKEY}
Address = ${PEER_IP}/24
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBKEY}
PresharedKey = ${PEER_PSK}
Endpoint = ${PUBLIC_IP}:${WG_PORT}
AllowedIPs = 10.9.0.0/24
PersistentKeepalive = 25
EOF
  chmod 600 "${PEER_CONF}"

  # reload WireGuard live (no restart needed)
  wg addconf wg0 <(cat << EOF
[Peer]
PublicKey = ${PEER_PUBKEY}
PresharedKey = ${PEER_PSK}
AllowedIPs = ${PEER_IP}/32
EOF
)

  echo "# OK - Peer '${PEER_NAME}' added at ${PEER_IP}"
  echo "# Config saved to: ${PEER_CONF}"
  echo "# Show QR code with: internet.wireguard.sh showpeer ${PEER_NAME}"
  exit 0
fi

##############
# SHOW PEER (QR + text)
##############
if [ "$1" = "showpeer" ]; then

  PEER_NAME="$2"
  PEER_CONF="${PEER_STORE}/${PEER_NAME}.conf"

  if [ ! -f "${PEER_CONF}" ]; then
    echo "error='peer config not found: ${PEER_NAME}'"
    exit 1
  fi

  echo "# WireGuard client config for: ${PEER_NAME}"
  echo "#"
  cat "${PEER_CONF}"
  echo ""
  echo "# QR code (scan with WireGuard mobile app):"
  qrencode -t ansiutf8 < "${PEER_CONF}"
  exit 0
fi

##############
# REMOVE PEER
##############
if [ "$1" = "removepeer" ]; then

  PEER_NAME="$2"
  PEER_CONF="${PEER_STORE}/${PEER_NAME}.conf"

  if [ ! -f "${PEER_CONF}" ]; then
    echo "error='peer not found: ${PEER_NAME}'"
    exit 1
  fi

  # get public key to remove from server config
  PEER_PUBKEY=$(grep "^PublicKey" "${PEER_CONF}" | awk '{print $3}')

  # remove from live wg interface
  wg set wg0 peer "${PEER_PUBKEY}" remove 2>/dev/null

  # remove peer block from wg0.conf
  # find start line of peer block and remove it + following lines until next empty line or EOF
  python3 - "${WG_CONF}" "${PEER_NAME}" << 'PYEOF'
import sys, re
conf = sys.argv[1]
name = sys.argv[2]
with open(conf) as f:
    content = f.read()
# remove the peer block including its comment
pattern = r'\n# Peer: ' + re.escape(name) + r'\n\[Peer\].*?(?=\n# Peer:|\Z)'
content = re.sub(pattern, '', content, flags=re.DOTALL)
with open(conf, 'w') as f:
    f.write(content)
PYEOF

  rm -f "${PEER_CONF}"
  echo "# OK - Peer '${PEER_NAME}' removed"
  exit 0
fi

##############
# MENU
##############
if [ "$1" = "menu" ]; then

  isInstalled=0
  [ -f "${WG_CONF}" ] && isInstalled=1
  isRunning=0
  systemctl is-active --quiet wg-quick@wg0 2>/dev/null && isRunning=1

  if [ ${isInstalled} -eq 0 ]; then
    if (whiptail --title " WireGuard VPN " \
      --yesno "WireGuard is not installed.\n\nInstall it now? It will open UDP port ${WG_PORT} and survive Tor-only mode." \
      10 60); then
      clear
      sudo /home/admin/config.scripts/internet.wireguard.sh on
      echo ""
      echo "Press ENTER to continue."
      read -r key
    fi
    exit 0
  fi

  # list current peers
  PEERS=""
  if [ -d "${PEER_STORE}" ]; then
    PEERS=$(ls "${PEER_STORE}"/*.conf 2>/dev/null | xargs -I{} basename {} .conf | grep -v "^server" | tr '\n' ' ')
  fi
  PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "unknown")
  STATUS_LINE="$([ ${isRunning} -eq 1 ] && echo 'RUNNING' || echo 'stopped')"
  PEER_COUNT=$(echo "${PEERS}" | wc -w)

  OPTIONS=()
  OPTIONS+=(ADDPEER  "Add new peer (generates config + QR)")
  if [ -n "${PEERS}" ]; then
    OPTIONS+=(SHOWPEER "Show peer config / QR code")
    OPTIONS+=(RMPEER   "Remove a peer")
  fi
  OPTIONS+=(UNINSTALL "Remove WireGuard")

  CHOICE=$(dialog --clear \
    --backtitle "RaspiBlesk" \
    --title " WireGuard VPN " \
    --menu "\nStatus:  ${STATUS_LINE}\nEndpoint: ${PUBLIC_IP}:${WG_PORT}\nPeers:   ${PEER_COUNT} (${PEERS})\n" \
    16 62 5 \
    "${OPTIONS[@]}" \
    2>&1 >/dev/tty)

  case $CHOICE in
    ADDPEER)
      NAME=$(dialog --clear --title " Add Peer " \
        --inputbox "Enter a name for this peer (e.g. laptop, phone):" \
        8 50 2>&1 >/dev/tty)
      if [ -n "${NAME}" ]; then
        clear
        sudo /home/admin/config.scripts/internet.wireguard.sh addpeer "${NAME}"
        echo ""
        sudo /home/admin/config.scripts/internet.wireguard.sh showpeer "${NAME}"
        echo ""
        echo "Press ENTER to return to menu."
        read -r key
      fi
      ;;
    SHOWPEER)
      NAME=$(dialog --clear --title " Show Peer " \
        --menu "Select peer:" 12 50 6 \
        $(for p in ${PEERS}; do echo "$p $p"; done) \
        2>&1 >/dev/tty)
      if [ -n "${NAME}" ]; then
        clear
        sudo /home/admin/config.scripts/internet.wireguard.sh showpeer "${NAME}"
        echo ""
        echo "Press ENTER to return to menu."
        read -r key
      fi
      ;;
    RMPEER)
      NAME=$(dialog --clear --title " Remove Peer " \
        --menu "Select peer to remove:" 12 50 6 \
        $(for p in ${PEERS}; do echo "$p $p"; done) \
        2>&1 >/dev/tty)
      if [ -n "${NAME}" ]; then
        clear
        sudo /home/admin/config.scripts/internet.wireguard.sh removepeer "${NAME}"
        echo ""
        echo "Press ENTER to return to menu."
        read -r key
      fi
      ;;
    UNINSTALL)
      if (whiptail --title " Remove WireGuard? " \
        --yesno "This will remove WireGuard and all peer configs.\nAre you sure?" 8 50); then
        clear
        sudo /home/admin/config.scripts/internet.wireguard.sh off
        echo ""
        echo "Press ENTER to return to menu."
        read -r key
      fi
      ;;
  esac

  exit 0
fi
