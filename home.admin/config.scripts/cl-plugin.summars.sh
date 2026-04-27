#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install and show the output if the summars plugin for Core Lightning"
  echo "Usage:"
  echo "cl-plugin.summars.sh [testnet|mainnet|signet] [runonce]"
  echo
  exit 1
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $1)

if [ $($lightningcli_alias | grep -c "summars") -eq 0 ]; then
  echo "# Starting the summars plugin"

  if [ ! -f /home/glcoin/cl-plugins-available/summars/target/release/summars ]; then
    if [ ! -f /home/glcoin/.cargo/bin/cargo ]; then
      # get Rust
      sudo -u glcoin curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u glcoin sh -s -- -y
    fi
    if [ ! -d "/home/glcoin/cl-plugins-available/summars" ]; then
      sudo -u glcoin mkdir /home/glcoin/cl-plugins-available 2>/dev/null
      cd /home/glcoin/cl-plugins-available || exit 1
      sudo -u glcoin git clone https://github.com/daywalker90/summars.git
    fi
    cd /home/glcoin/cl-plugins-available/summars || exit 1
    sudo -u glcoin /home/glcoin/.cargo/bin/cargo build --release
  fi

  $lightningcli_alias plugin start -H /home/glcoin/cl-plugins-available/summars/target/release/summars 1>/dev/null
fi

echo
echo "# Running:"
echo "${netprefix}lightning-cli -H summars summars-columns=IN_SATS,OUT_SATS,GRAPH_SATS,ALIAS,FLAG,BASE,PPM,UPTIME,HTLCS,STATE summars-sort-by=-IN_SATS"
echo
$lightningcli_alias -H summars summars-columns=IN_SATS,OUT_SATS,GRAPH_SATS,ALIAS,FLAG,BASE,PPM,UPTIME,HTLCS,STATE summars-sort-by=-IN_SATS
echo

if [ "$(echo "$@" | grep -c "runonce")" -gt 0 ]; then
  $lightningcli_alias plugin stop /home/glcoin/cl-plugins-available/summars/target/release/summars
fi
