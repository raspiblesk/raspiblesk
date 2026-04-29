#!/bin/bash

# get raspiblesk config
echo "get raspiblesk config"
source /home/admin/raspiblesk.info
source /mnt/hdd/app-data/raspiblesk.conf

source <(/home/admin/_cache.sh get internet_localip internet_localiprange)
localIP="${internet_localip}"
localIPrange="${internet_localiprange}"

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlesk"
TITLE="Connect Options"
MENU=""
OPTIONS=()

OPTIONS+=(MOBILE "Connect Mobile Wallet")
if [ "${ElectRS}" == "on" ]; then
  OPTIONS+=(ELECTRS "Electrum Rust Server")
fi
if [ "${BTCPayServer}" == "on" ] && [ "${lnd}" = "on" ]; then
  OPTIONS+=(BTCPAY-LND "Show LND connection string")
fi
if [ "${BTCPayServer}" == "on" ] && [ "${cl}" = "on" ]; then
  OPTIONS+=(BTCPAY-CLN "Show CLN connection string")
fi
OPTIONS+=(${network}RPC "Connect Specter Desktop or JoinMarket")
OPTIONS+=(BISQ "Connect Bisq to this node")
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  OPTIONS+=(ALBY "Connect Alby to this node")
  OPTIONS+=(EXPORT "Get Macaroons and TLS.cert")
  OPTIONS+=(RESET "Recreate LND Macaroons & tls.cert")
  OPTIONS+=(SYNC "Sync Macaroons & tls.cert with Apps/Users")
fi
if [ -f /mnt/hdd/app-data/selfsignedcert/selfsigned.cert ]; then
  OPTIONS+=(RESET-TLS "Reset the self-signed TLS certificate")
fi

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --ok-label "Select" \
                --cancel-label "Main menu" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

case $CHOICE in

  MOBILE)
    /home/admin/97addMobileWallet.sh;;
  ELECTRS)
    /home/admin/config.scripts/bonus.electrs.sh menu;;
  BTCPAY-LND)
    /home/admin/config.scripts/lnd.export.sh btcpay
    echo "Press ENTER to return to main menu."
    read key
    exit 0;;
  BTCPAY-CLN)
    /home/admin/config.scripts/bonus.btcpayserver.sh cln-lightning-rpc-access
    echo "Press ENTER to return to main menu."
    read key
    exit 0;;
  RESET)
    sudo /home/admin/config.scripts/lnd.credentials.sh reset "${chain:-main}net"
    sudo /home/admin/config.scripts/blesk.shutdown.sh reboot
    exit 0;;
  SYNC)
    sudo /home/admin/config.scripts/lnd.credentials.sh sync "${chain:-main}net"
    echo "Press ENTER to return to main menu."
    read key
    exit 0;;
  EXPORT)
    sudo /home/admin/config.scripts/lnd.export.sh
    exit 0;;
  RESET-TLS)
    sudo /home/admin/config.scripts/internet.selfsignedcert.sh reset
    exit 0;;
  ALBY)
    /home/admin/config.scripts/bonus.alby.sh
    exit 0;
  ;;

  BISQ)
    OPTIONS=()
    if [ $(grep -c "peerbloomfilters=1" < /mnt/hdd/app-data/glcoin/glcoin.conf) -eq 0 ]||\
    [ $(grep -c Bisq < /etc/tor/torrc) -eq 0 ];then
      OPTIONS+=(ADDBISQ "Add a Hidden Service for Bisq")
    fi
    if [ $(grep -c "peerbloomfilters=1" < /mnt/hdd/app-data/glcoin/glcoin.conf) -gt 0 ]&&\
    [ $(grep -c Bisq < /etc/tor/torrc) -gt 0 ];then
      OPTIONS+=(SHOWBISQ "Show the Hidden Service to connect Bisq")
      OPTIONS+=(REMOVEBISQ "Remove the Hidden Service for Bisq")
    fi
    CHOICE=$(dialog --clear \
                --backtitle "" \
                --title "Connect Bisq" \
                --ok-label "Select" \
                --cancel-label "Cancel" \
                --menu "" \
                8 64 2 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

      case $CHOICE in
        ADDBISQ)
          clear
          if [ $(grep -c "peerbloomfilters=1" < /mnt/hdd/app-data/glcoin/glcoin.conf) -eq 0 ]
          then
            echo "peerbloomfilters=1" | sudo tee -a /mnt/hdd/app-data/glcoin/glcoin.conf
            echo "# Restarting glcoind"
            sudo systemctl restart glcoind
          else
            echo "# glcoind is already configured with peerbloomfilters=1"
          fi

          if [ $(grep -c Bisq < /etc/tor/torrc) -eq 0 ];then
            echo "# Creating the Hidden Service for Bisq"
            echo "
# Hidden Service for Bisq (glcoin P2P v3)
HiddenServiceDir /mnt/hdd/app-data/tor/bisq
HiddenServiceVersion 3
HiddenServicePort 1618 127.0.0.1:1618" | sudo tee -a /etc/tor/torrc
            echo "# Reloading Tor"
            sudo systemctl reload tor@default
            sleep 10
            TOR_ADDRESS=$(sudo cat /mnt/hdd/app-data/tor/bisq/hostname)
              if [ -z "$TOR_ADDRESS" ]; then
                echo "Waiting for the Hidden Service"
                sleep 10
                TOR_ADDRESS=$(sudo cat /mnt/hdd/app-data/tor/bisq/hostname)
                if [ -z "$TOR_ADDRESS" ]; then
                  echo "# FAIL - The Hidden Service address could not be found - Tor error?"
                  exit 1
                fi
              fi
          else
            echo "# The Hidden Service for Bisq is already configured"
          fi
          echo
          echo "Install from https://bisq.network/downloads/"
          echo "Go to Bisq Settings -> Network Info -> 'Custom Glcoin Node'."
          echo
          echo "Enter: ${TOR_ADDRESS}:1618 to connect to this node."
          echo
          echo "Press ENTER to return to the menu."
          read key
          exit 0;;
        REMOVEBISQ)
          sudo sed -i '/Bisq/{N;N;N;d}'  /etc/tor/torrc
          echo "# Restarting Tor"
          sudo systemctl reload tor@default;;
        SHOWBISQ)
          clear
          TOR_ADDRESS=$(sudo cat /mnt/hdd/app-data/tor/bisq/hostname)
          echo
          echo "Install from https://bisq.network/downloads/"
          echo "Go to Bisq Settings -> Network Info -> 'Custom Glcoin Node'."
          echo
          echo "Enter: ${TOR_ADDRESS}:1618 to connect to this node."
          echo
          echo "Press ENTER to return to the menu."
          read key;;
      esac
    ;;
  ${network}RPC)
    # vars
    if [ "${chain}net" == "mainnet" ]; then
      GLCOINRPCPORT=1617
    elif [ "${chain}net" == "testnet" ]; then
      GLCOINRPCPORT=11617
    elif [ "${chain}net" == "signet" ]; then
      GLCOINRPCPORT=31617
    else
      # have this to signal that selection went wrong
      GLCOINRPCPORT=0
    fi
    echo "# Running on ${chain:-main}net"
    echo
    allowIPrange=$(grep -c "rpcallowip=$localIPrange" <  /mnt/hdd/app-data/${network}/${network}.conf)
    bindIP=$(grep -c "${chain:-main}.rpcbind=$localIP" <  /mnt/hdd/app-data/${network}/${network}.conf)
    rpcTorService=$(grep -c "HiddenServicePort ${GLCOINRPCPORT} 127.0.0.1:${GLCOINRPCPORT}"  < /etc/tor/torrc)
    TorRPCaddress=$(sudo cat /mnt/hdd/app-data/tor/glcoin${GLCOINRPCPORT}/hostname)

    function showRPCcredentials() {
      RPCUSER=$(sudo cat /mnt/hdd/app-data/${network}/${network}.conf | grep rpcuser | cut -c 9-)
      RPCPSW=$(sudo cat /mnt/hdd/app-data/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
      echo
      echo "RPC username:"
      echo "$RPCUSER"
      echo
      echo "RPC password:"
      echo "$RPCPSW"
      if [ $allowIPrange -gt 0 ]&&[ $bindIP -gt 0 ];then
        echo
        echo "Host on the local network (make sure to connect from the same network):"
        echo $localIP
      fi
      if [ $rpcTorService -gt 0 ];then
        echo
        echo "Host via Tor (Tor needs to run on the client connecting as well):"
        echo $TorRPCaddress
      fi
      echo
      echo "Port:"
      echo "${GLCOINRPCPORT}"
      echo
      echo "More documentation at:"
      echo "https://github.com/openoms/joininbox/blob/master/prepare_remote_node.md"
    }

    # menu
    OPTIONS=()
    if [ $allowIPrange -eq 0 ]&&\
    [ $bindIP -eq 0 ]&&\
    [ $rpcTorService -eq 0 ];then
      OPTIONS+=(ADDRPCLAN "Accept local connections to ${network} RPC")
      OPTIONS+=(ADDRPCTOR "Add a Hidden Service to connect to ${network} RPC")
    else
      OPTIONS+=(CREDENTIALS "Show how to connect to ${network} RPC")
      OPTIONS+=(REMOVERPC "Close all connections to ${network} RPC")
      if [ $allowIPrange -eq 0 ]||[ $bindIP -eq 0 ];then
        OPTIONS+=(ADDRPCLAN "Accept local connections to ${network} RPC")
      fi
      if [ $rpcTorService -eq 0 ];then
        OPTIONS+=(ADDRPCTOR "Add a Hidden Service to connect to ${network} RPC")
      fi
    fi
    CHOICE=$(dialog --clear \
                --backtitle "" \
                --title "${network} RPC" \
                --ok-label "Select" \
                --cancel-label "Cancel" \
                --menu "" 9 66 3 \
                "${OPTIONS[@]}" 2>&1 >/dev/tty)

    case $CHOICE in
      ADDRPCLAN)
        clear
        echo "# Make sure the glcoind wallet is on"
        /home/admin/config.scripts/network.wallet.sh on

        restartCore=0
        if [ $allowIPrange -eq 0 ]; then
          echo "rpcallowip=$localIPrange" | sudo tee -a /mnt/hdd/app-data/${network}/${network}.conf
          restartCore=1
        fi
        if [ $bindIP -eq 0 ]; then
          echo "${chain}.rpcbind=$localIP" | sudo tee -a /mnt/hdd/app-data/${network}/${network}.conf
          restartCore=1
        fi
        if [ $restartCore = 1 ];then
          echo "# Restarting ${network}d"
          sudo systemctl restart ${network}d
        fi
        echo "# ufw allow from $localIPrange to any port ${GLCOINRPCPORT}"
        sudo ufw allow from $localIPrange to any port ${GLCOINRPCPORT}
        echo
        showRPCcredentials
        echo "Press ENTER to return to the menu."
        read key
        ;;
      ADDRPCTOR)
        clear
        echo "# Make sure the glcoind wallet is on"
        /home/admin/config.scripts/network.wallet.sh on
        /home/admin/config.scripts/tor.onion-service.sh glcoin${GLCOINRPCPORT} ${GLCOINRPCPORT} ${GLCOINRPCPORT}
        echo
        echo "The address of the local node is: $TorRPCaddress"
        echo
        showRPCcredentials
        echo
        echo "Press ENTER to return to the menu."
        read key
        ;;

      CREDENTIALS)
        clear
        showRPCcredentials
        echo
        echo "Press ENTER to return to the menu."
        read key
        ;;
      REMOVERPC)
        # remove old entry
        sudo sed -i "/# Hidden Service for GLCOIN RPC (mainnet, testnet, signet)/,/^\s*$/{d}" /etc/tor/torrc
        # remove Hidden Service
        /home/admin/config.scripts/tor.onion-service.sh off glcoin${GLCOINRPCPORT}
        sudo ufw deny from $localIPrange to any port ${GLCOINRPCPORT}
        restartCore=0
        if [ $allowIPrange -gt 0 ]; then
          sudo sed -i "/^rpcallowip=.*/d" /mnt/hdd/app-data/${network}/${network}.conf
          restartCore=1
        fi
        if [ $bindIP -gt 0 ]; then
          sudo sed -i "/^${chain}.rpcbind=$localIP/d" /mnt/hdd/app-data/${network}/${network}.conf
          restartCore=1
        fi
        if [ $restartCore = 1 ];then
          echo "# Restarting ${network}d"
          sudo systemctl restart ${network}d
        fi
        ;;
    esac
  ;;
esac
