#!/bin/bash

# "*** LND ***"
## based on https://raspibolt.github.io/raspibolt/raspibolt_40_lnd.html#lightning-lnd
## see LND releases: https://github.com/lightningnetwork/lnd/releases
### If you change here - make sure to also change interims version in lnd.update.sh #!
lndVersion="0.20.99-beta"
# Real upstream LND tag to clone (v0.20.99-beta doesn't exist in lightningnetwork/lnd)
LND_CLONE_TAG="v0.20.1-beta"
# btcd commit from LND v0.20.1-beta go.mod (pseudo-version: v0.24.3-0.20250318170759-4f4ea81776d6)
BTCD_COMMIT="4f4ea81776d6"
GLCOIN_RELEASE="v0.2.2"
GITHUB_RELEASE_BASE="https://github.com/raspiblesk/raspiblesk/releases/download/${GLCOIN_RELEASE}"

# olaoluwa
PGPauthor="roasbeef"
PGPpkeys="https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/roasbeef.asc"
PGPcheck="A5B61896952D9FDA83BC054CDC42612E89237182"

# -----------------------------------------------------------------------
# Bundled-asset SHA-256 pins. Computed at v0149 release time; bump when
# the bundled tarball is replaced. Any tarball whose hash does not match
# is rejected with a hard fail before being executed or trusted.
# Without this, a wget/cp without verification was the only gate between
# a malicious GitHub release (or MITM'd asset) and a backdoored lnd /
# go toolchain running with channel-funds authority.
# -----------------------------------------------------------------------
# Empty until a fresh r3 prebuilt is cross-compiled and bundled (one-time
# audit-grade rebuild after the btcd wire-magic patch). Empty pin makes
# the install path drop any /tmp prebuilt that happens to be present and
# fall through to the source-compile branch (~30-60 min on Pi5).
SHA256_LND_PREBUILT_arm64=""
SHA256_GO_TOOLCHAIN_arm64="beaf0f51cbe0bd71b8289b2b6fa96c0b11cd86aa58672691ef2f1de88eb621de"
SHA256_LND_VENDORED="d756dadf5fa1b235ac3e5d8880b6c797c3cf44967d48c982f1ab4439f6309d0c"
SHA256_LND_SRC="db479a6d4cf7bd00817f8ce9bad2f57d81933b0b408364dc3f9c1e94682a27d3"
SHA256_BTCD_SRC="f282a697058247ecaef3c86e3b6a38935b6fbf942f2a8fda5477c08f11b17c32"

# verify_sha256 <file> <expected-hash> <human-name>
# Refuses to proceed if hash does not match. No fallback, no "|| true".
verify_sha256() {
  local _file="$1"; local _expected="$2"; local _name="$3"
  if [ ! -f "${_file}" ]; then
    echo "# FAIL - cannot verify ${_name}: file ${_file} missing"
    exit 1
  fi
  local _actual
  _actual="$(sha256sum "${_file}" 2>/dev/null | awk '{print $1}')"
  if [ "${_actual}" != "${_expected}" ]; then
    echo "# FAIL - SHA-256 mismatch for ${_name} (${_file})"
    echo "#   expected: ${_expected}"
    echo "#   got:      ${_actual}"
    echo "# Refusing to install untrusted binary. Wipe ${_file} and retry"
    echo "# with a fresh copy from the official release if the hash is correct,"
    echo "# or update the SHA256_* pin if you intentionally rebuilt the asset."
    rm -f "${_file}" 2>/dev/null
    exit 1
  fi
  echo "# OK - ${_name} sha256 verified (${_expected:0:16}…)"
}

# -----------------------------------------------------------------------
# Glcoin wire-magic patch for btcd's wire/protocol.go.
#
# Why: btcwallet has three switches that compare chainParams.Net against
# the typed constant wire.MainNet (0xd9b4bef9, Bitcoin's magic):
#   vendor/github.com/btcsuite/btcwallet/waddrmgr/scoped_manager.go
#   vendor/github.com/btcsuite/btcwallet/wallet/import.go
#   vendor/github.com/btcsuite/btcwallet/internal/legacy/keystore/keystore.go
# Our btcd_glcoin_params.go init() overrides chaincfg.MainNetParams with
# GlcoinMainNetParams (Net = 0xd9b4b4f9), but the wire.MainNet *constant*
# stays at Bitcoin's value. Result: every wallet RPC fails with
#   "failed to retrieve account public key: unsupported net
#    Unknown BitcoinNet (3652498681)"  (3652498681 == 0xd9b4b4f9).
# LND otherwise starts cleanly (taproot check passes, wallet unlocks,
# chain backend connects) — wallet is just unusable.
#
# Fix: change the wire.MainNet constant to Glcoin's magic. One source-
# level edit, audit-grade. Consistent with our "Glcoin IS our mainnet"
# stance in chaincfg. Side-effect: btcd no longer recognises Bitcoin's
# real magic 0xd9b4bef9 — desired (this build is not in Bitcoin's net).
#
# Idempotent: detects already-patched state and re-fails-closed if the
# expected source pattern is missing (e.g. upstream btcd renamed the
# constant) — better to break the build loudly than ship a wallet bug.
# -----------------------------------------------------------------------
_patch_btcd_wire_magic() {
  local _proto_go="$1"
  if [ ! -f "${_proto_go}" ]; then
    echo "# FAIL - wire/protocol.go not found at ${_proto_go}"
    return 1
  fi
  if grep -q 'MainNet BitcoinNet = 0xd9b4b4f9' "${_proto_go}"; then
    echo "# wire/protocol.go already patched (Glcoin magic in MainNet const)"
    return 0
  fi
  if ! grep -q 'MainNet BitcoinNet = 0xd9b4bef9' "${_proto_go}"; then
    echo "# FAIL - expected Bitcoin MainNet pattern not found in ${_proto_go}"
    echo "#   Pattern: 'MainNet BitcoinNet = 0xd9b4bef9'"
    echo "#   Refusing to build a wallet-broken LND."
    return 1
  fi
  sed -i 's/MainNet BitcoinNet = 0xd9b4bef9/MainNet BitcoinNet = 0xd9b4b4f9/' "${_proto_go}"
  if ! grep -q 'MainNet BitcoinNet = 0xd9b4b4f9' "${_proto_go}"; then
    echo "# FAIL - sed did not apply Glcoin wire-magic patch to ${_proto_go}"
    return 1
  fi
  echo "# Patched btcd wire.MainNet → 0xd9b4b4f9 (Glcoin magic) in ${_proto_go}"
}

# guggero
# PGPauthor="guggero"
# PGPpkeys="https://keybase.io/guggero/pgp_keys.asc"
# PGPcheck="F4FC70F07310028424EFC20A8E4256593F177720"

# bitconner
#PGPauthor="bitconner"
#PGPpkeys="https://keybase.io/bitconner/pgp_keys.asc"
#PGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install or remove LND services on parallel chains"
  echo "lnd.install.sh install - called by the build_sdcard.sh"
  echo "lnd.install.sh info [?compareVersion]"
  echo "lnd.install.sh on [mainnet|testnet|signet] [?initwallet]"
  echo "lnd.install.sh off [mainnet|testnet|signet] <purge>"
  echo "lnd.install.sh display-seed [mainnet|testnet|signet] [?delete]"
  echo
  exit 1
fi

source <(/home/admin/_cache.sh get network)
if [ "${network}" == "" ]; then
  network="glcoin"
fi

if [ "$1" = "info" ] ; then

  # the version that this script installs by default
  echo "lndDefaultInstallVersion='${lndVersion}'"

  # the version that is installed
  lndInstalledVersion=$(sudo -u admin lnd --version 2>/dev/null | cut -d " " -f3)
  echo "lndInstalledVersion='${lndInstalledVersion}'"

  # if a version string is given as second optional parameter - check update compatibility
  # assumption: if the available version is one miner version lower then asked data is not compatible
  compareVersion=$2
  if [ "${compareVersion}" != "" ]; then
    # use version thats either installed or can be installed
    availableVersion="${lndInstalledVersion}"
    if [ "${availableVersion}" == "" ]; then
      availableVersion="${lndVersion}"
    fi
    # check major & miner version value
    availableMajor=$(echo ${availableVersion} | cut -d "." -f1 | grep -o '[[:digit:]]*' | tail -n 1)
    compareMajor=$(echo ${compareVersion} | cut -d "." -f1 | grep -o '[[:digit:]]*' | tail -n 1)
    availableMiner=$(echo ${availableVersion} | cut -d "." -f2 | grep -o '[[:digit:]]*' | tail -n 1)
    compareMiner=$(echo ${compareVersion} | cut -d "." -f2 | grep -o '[[:digit:]]*' | tail -n 1)
    #echo "# ${availableMajor} ${compareMajor} ${availableMiner} ${compareMiner}"
    if [ "${compareMajor}" != "" ] && [ "${compareMiner}" != "" ]; then
      # check major
      if [ ${availableMajor} -lt ${compareMajor} ]; then
       echo "compatible=0"
      else
        if [ ${availableMiner} -lt ${compareMiner} ]; then
          echo "compatible=0"
        else
          echo "compatible=1"
        fi
      fi
    fi
  fi

  exit 0
fi

if [ "$1" = "install" ] ; then

  echo "# *** INSTALL LND ${lndVersion} (Glcoin-patched) ***"
  echo "# Installs LND built from source with Glcoin chain params."
  echo "# Official LND binaries do NOT know about Glcoin's genesis block"
  echo "# and will refuse to connect to glcoind. A patched build is required."

  # check if lnd binary is already installed
  if [ $(sudo -u admin lnd --version 2>/dev/null | grep -c 'lnd') -gt 0 ]; then
    echo "lnd binary already installed - done"
    exit 0
  fi

  # detect architecture
  # Order matters: aarch64 (Pi 5 64-bit) must win over the broader 'arm' match
  # so a hypothetical armv8l reporting kernel doesn't get classified as armv7.
  _uname_m="$(uname -m)"
  case "${_uname_m}" in
    aarch64|arm64) lndArch="arm64" ;;
    armv7l|armv6l|armhf) lndArch="armv7" ;;
    x86_64|amd64) lndArch="amd64" ;;
    *)
      echo "# FAIL - unsupported architecture: ${_uname_m}"
      exit 1
      ;;
  esac
  echo "# Detected architecture: ${_uname_m} -> lndArch=${lndArch}"

  # -----------------------------------------------------------------------
  # OPTION 1: pre-built Glcoin-patched LND binary tarball
  # Place lnd-glcoin-${lndVersion}-linux-${arch}.tar.gz in /tmp before running.
  # Format: contains lnd and lncli binaries at the top level.
  # -----------------------------------------------------------------------
  # Cache filename includes a build-recipe revision so old broken caches
  # are not picked up by newer scripts. Bump LND_CACHE_REV when patch changes.
  #   r2 (2026-05-08): chaincfg init-order fix (zglcoin_params.go).
  #   r3 (2026-05-14): wire.MainNet const change to Glcoin magic (this
  #     fixes "unsupported net Unknown BitcoinNet (3652498681)" on every
  #     wallet RPC; r2 binary built before the patch existed).
  LND_CACHE_REV="r3"
  PREBUILT_NAME="lnd-glcoin-${lndVersion}-${LND_CACHE_REV}-linux-${lndArch}.tar.gz"
  PREBUILT_TARBALL="/tmp/${PREBUILT_NAME}"
  # Clean up older cache revisions to avoid confusion
  for _old in \
    /tmp/lnd-glcoin-${lndVersion}-linux-${lndArch}.tar.gz \
    /tmp/lnd-glcoin-${lndVersion}-r2-linux-${lndArch}.tar.gz
  do
    [ -f "${_old}" ] && rm -f "${_old}"
  done
  # Fallback search order: /tmp (build_sdcard.sh stages here) -> /home/admin/assets
  # (where the full bundle lives after first boot) -> GitHub Release download.
  # In v0146 the cross-compiled arm64 binary ships in assets/, so a fresh Pi
  # finds it without touching the network.
  if [ ! -f "${PREBUILT_TARBALL}" ] && [ -f "/home/admin/assets/${PREBUILT_NAME}" ]; then
    echo "# Found prebuilt LND in /home/admin/assets — using offline copy"
    cp "/home/admin/assets/${PREBUILT_NAME}" "${PREBUILT_TARBALL}"
  fi
  if [ ! -f "${PREBUILT_TARBALL}" ]; then
    echo "# Attempting GitHub Release download: ${GITHUB_RELEASE_BASE}/${PREBUILT_NAME}"
    wget -q --show-progress --timeout=120 \
      -O "${PREBUILT_TARBALL}" \
      "${GITHUB_RELEASE_BASE}/${PREBUILT_NAME}" || rm -f "${PREBUILT_TARBALL}"
  fi
  # Decide if the prebuilt tarball is safe to install: must exist AND have a
  # pinned SHA-256 for our arch AND match. Anything else → drop it and fall
  # through to the source build path.
  _prebuilt_ok=0
  if [ -f "${PREBUILT_TARBALL}" ]; then
    _expected_lnd_sha=""
    case "${lndArch}" in
      arm64) _expected_lnd_sha="${SHA256_LND_PREBUILT_arm64}" ;;
    esac
    if [ -z "${_expected_lnd_sha}" ]; then
      echo "# WARN - no pinned SHA-256 for lndArch=${lndArch} prebuilt tarball"
      echo "# Discarding ${PREBUILT_TARBALL}; will build from source instead."
      rm -f "${PREBUILT_TARBALL}"
    else
      verify_sha256 "${PREBUILT_TARBALL}" "${_expected_lnd_sha}" "LND prebuilt (${lndArch})"
      _prebuilt_ok=1
    fi
  fi

  if [ "${_prebuilt_ok}" -eq 1 ]; then
    echo "# Installing pre-built Glcoin LND tarball: ${PREBUILT_TARBALL}"
    cd /home/admin/download || exit 1
    tar -xzf "${PREBUILT_TARBALL}" || { echo "# FAIL - could not extract tarball"; exit 1; }
    install -m 0755 lnd lncli /usr/local/bin/ || {
      echo "# FAIL - could not install lnd/lncli to /usr/local/bin/"; exit 1
    }
    echo "# Installed from pre-built tarball"
  else
    # -----------------------------------------------------------------------
    # OPTION 2: build from source
    # Requires Go. Downloads btcd + lnd, applies Glcoin patch, builds.
    # On a Raspberry Pi 4 this takes ~30-60 minutes.
    # -----------------------------------------------------------------------
    echo "# No pre-built tarball found at ${PREBUILT_TARBALL}"
    echo "# Building LND from source with Glcoin chain params patch..."
    echo "# (This will take 30-60 minutes on a Raspberry Pi)"

    # -----------------------------------------------------------------------
    # Go installation — prefer bundled asset (offline), fall back to download
    # LND v0.20.1-beta go.mod requires go 1.24.x (confirmed: go 1.24.11)
    # -----------------------------------------------------------------------
    GO_VERSION="1.24.11"
    GO_ARCH="${lndArch}"
    [ "${lndArch}" = "armv7" ] && GO_ARCH="armv6l"
    ASSETS_DIR="/home/admin/assets"
    _GO_NEED_MINOR=24
    _go_ok=0
    if command -v go &>/dev/null; then
      _go_minor=$(go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+' | grep -oE '[0-9]+$')
      if [ -n "${_go_minor}" ] && [ "${_go_minor}" -ge "${_GO_NEED_MINOR}" ]; then
        _go_ok=1
        echo "# Go $(go version | grep -oE 'go[0-9.]+') already installed — sufficient"
      else
        echo "# Go too old (need 1.${_GO_NEED_MINOR}+) — will replace"
      fi
    else
      echo "# Go not found — installing"
    fi
    if [ "${_go_ok}" -eq 0 ]; then
      rm -rf /usr/local/go
      LOCAL_GO="${ASSETS_DIR}/go-${GO_VERSION}-linux-${GO_ARCH}.tar.gz"
      # Pick pinned SHA for this arch (only arm64 is bundled; for other archs
      # we currently allow the upstream go.dev download but still refuse to
      # extract until verification has been added — fail closed).
      _expected_go_sha=""
      case "${GO_ARCH}" in
        arm64) _expected_go_sha="${SHA256_GO_TOOLCHAIN_arm64}" ;;
      esac
      if [ -f "${LOCAL_GO}" ]; then
        echo "# Installing Go ${GO_VERSION} from bundled assets (offline)"
        if [ -z "${_expected_go_sha}" ]; then
          echo "# FAIL - no pinned SHA-256 for Go GO_ARCH=${GO_ARCH}"
          echo "# Bundle should ship a pinned hash; refusing to extract."
          exit 1
        fi
        verify_sha256 "${LOCAL_GO}" "${_expected_go_sha}" "Go ${GO_VERSION} (${GO_ARCH})"
        tar -C /usr/local -xzf "${LOCAL_GO}" || { echo "# FAIL - Go extract failed"; exit 1; }
      else
        if [ -z "${_expected_go_sha}" ]; then
          echo "# FAIL - no pinned SHA-256 for Go GO_ARCH=${GO_ARCH}; refusing"
          echo "# to download an unverified Go toolchain (compiler-as-malware risk)."
          echo "# Add the upstream go.dev SHA to SHA256_GO_TOOLCHAIN_${GO_ARCH} and retry."
          exit 1
        fi
        echo "# Downloading Go ${GO_VERSION} from go.dev"
        wget -q --show-progress -O /tmp/go.tar.gz \
          "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" || {
          echo "# FAIL - could not download Go ${GO_VERSION}"; exit 1
        }
        verify_sha256 /tmp/go.tar.gz "${_expected_go_sha}" "Go ${GO_VERSION} (${GO_ARCH})"
        tar -C /usr/local -xzf /tmp/go.tar.gz && rm -f /tmp/go.tar.gz
      fi
      export PATH=$PATH:/usr/local/go/bin
      grep -qF '/usr/local/go/bin' /home/admin/.bashrc || \
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/admin/.bashrc
      echo "# Go ${GO_VERSION} installed"
    fi
    export GOPATH=/home/admin/go
    export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin

    BUILD_BASE="/home/admin/lnd-glcoin-build"
    mkdir -p "${BUILD_BASE}"
    cd "${BUILD_BASE}" || exit 1

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    GLCOIN_PARAMS_FILE=""
    if [ -f /home/admin/patches/lnd/btcd_glcoin_params.go ]; then
      GLCOIN_PARAMS_FILE="/home/admin/patches/lnd/btcd_glcoin_params.go"
    elif [ -f "${SCRIPT_DIR}/../patches/lnd/btcd_glcoin_params.go" ]; then
      GLCOIN_PARAMS_FILE="${SCRIPT_DIR}/../patches/lnd/btcd_glcoin_params.go"
    else
      echo "# FAIL - could not find btcd_glcoin_params.go patch file"; exit 1
    fi

    # -----------------------------------------------------------------------
    # LND source — prefer vendored bundle (offline+fast), then plain source,
    # then git clone as last resort.
    # The vendored bundle already has btcd patched with glcoin_params.go
    # and all Go module dependencies pre-downloaded (go.sum verified).
    # -----------------------------------------------------------------------
    echo "# Preparing LND ${LND_CLONE_TAG} source..."
    rm -rf "${BUILD_BASE}/lnd"
    LOCAL_LND_VENDORED="${ASSETS_DIR}/lnd-${LND_CLONE_TAG}-vendored.tar.gz"
    LOCAL_LND="${ASSETS_DIR}/lnd-${LND_CLONE_TAG}-src.tar.gz"

    if [ -f "${LOCAL_LND_VENDORED}" ]; then
      echo "# Extracting vendored LND bundle from assets (fully offline — btcd+vendor included)"
      verify_sha256 "${LOCAL_LND_VENDORED}" "${SHA256_LND_VENDORED}" "LND vendored bundle"
      tar -xzf "${LOCAL_LND_VENDORED}" -C "${BUILD_BASE}" || { echo "# FAIL - LND vendored extract"; exit 1; }
      _lnd_dir=$(tar -tzf "${LOCAL_LND_VENDORED}" 2>/dev/null | head -1 | cut -d/ -f1)
      [ -n "${_lnd_dir}" ] && [ -d "${BUILD_BASE}/${_lnd_dir}" ] && \
        mv "${BUILD_BASE}/${_lnd_dir}" "${BUILD_BASE}/lnd"
      # vendored bundle already contains patched btcd in vendor/ — no separate btcd clone needed
      BTCD_ALREADY_VENDORED=1
      # Init-order safety net: glcoin_params.go init() must run AFTER btcd's params.go
      # init() (which calls mustRegister(&MainNetParams)). Otherwise the override
      # MainNetParams = GlcoinMainNetParams runs first, then mustRegister panics with
      # "parameters have already been registered with the network". Go runs init() in
      # alphabetical filename order, so prefix with 'z' to push us last.
      _vendor_chaincfg="${BUILD_BASE}/lnd/vendor/github.com/btcsuite/btcd/chaincfg"
      if [ -f "${_vendor_chaincfg}/glcoin_params.go" ]; then
        echo "# Renaming glcoin_params.go → zglcoin_params.go (fix init order)"
        mv "${_vendor_chaincfg}/glcoin_params.go" "${_vendor_chaincfg}/zglcoin_params.go"
      fi
      _patch_btcd_wire_magic \
        "${BUILD_BASE}/lnd/vendor/github.com/btcsuite/btcd/wire/protocol.go" || {
        echo "# FAIL - btcd wire-magic patch failed in vendored tree"; exit 1
      }
    elif [ -f "${LOCAL_LND}" ]; then
      echo "# Extracting LND source from assets (btcd will still be needed)"
      verify_sha256 "${LOCAL_LND}" "${SHA256_LND_SRC}" "LND source bundle"
      tar -xzf "${LOCAL_LND}" -C "${BUILD_BASE}" || { echo "# FAIL - LND extract"; exit 1; }
      _lnd_dir=$(tar -tzf "${LOCAL_LND}" 2>/dev/null | head -1 | cut -d/ -f1)
      [ -n "${_lnd_dir}" ] && [ -d "${BUILD_BASE}/${_lnd_dir}" ] && \
        mv "${BUILD_BASE}/${_lnd_dir}" "${BUILD_BASE}/lnd"
    else
      echo "# Cloning LND ${LND_CLONE_TAG} from GitHub (no bundled source found)"
      git clone --depth=1 --branch "${LND_CLONE_TAG}" \
        https://github.com/lightningnetwork/lnd.git "${BUILD_BASE}/lnd" || {
        echo "# FAIL - could not clone LND ${LND_CLONE_TAG}"; exit 1
      }
    fi

    # -----------------------------------------------------------------------
    # btcd source — skip if already included in vendored LND bundle
    # -----------------------------------------------------------------------
    if [ "${BTCD_ALREADY_VENDORED:-0}" -eq 0 ]; then
      echo "# Preparing btcd source (commit ${BTCD_COMMIT})..."
      rm -rf "${BUILD_BASE}/btcd"
      LOCAL_BTCD="${ASSETS_DIR}/btcd-${BTCD_COMMIT}.tar.gz"
      if [ -f "${LOCAL_BTCD}" ]; then
        echo "# Extracting btcd source from assets (offline)"
        verify_sha256 "${LOCAL_BTCD}" "${SHA256_BTCD_SRC}" "btcd source bundle"
        tar -xzf "${LOCAL_BTCD}" -C "${BUILD_BASE}" || { echo "# FAIL - btcd extract"; exit 1; }
        _btcd_dir=$(tar -tzf "${LOCAL_BTCD}" 2>/dev/null | head -1 | cut -d/ -f1)
        [ -n "${_btcd_dir}" ] && [ -d "${BUILD_BASE}/${_btcd_dir}" ] && \
          mv "${BUILD_BASE}/${_btcd_dir}" "${BUILD_BASE}/btcd"
      else
        echo "# Cloning btcd ${BTCD_COMMIT} from GitHub (no bundled source found)"
        git clone https://github.com/btcsuite/btcd.git "${BUILD_BASE}/btcd" && \
          git -C "${BUILD_BASE}/btcd" checkout "${BTCD_COMMIT}" || {
          echo "# FAIL - could not clone/checkout btcd"; exit 1
        }
      fi
      # Filename prefixed with 'z' so init() runs AFTER btcd's params.go init()
      cp "${GLCOIN_PARAMS_FILE}" "${BUILD_BASE}/btcd/chaincfg/zglcoin_params.go" || {
        echo "# FAIL - could not copy zglcoin_params.go into btcd"; exit 1
      }
      _patch_btcd_wire_magic "${BUILD_BASE}/btcd/wire/protocol.go" || {
        echo "# FAIL - btcd wire-magic patch failed in standalone btcd tree"; exit 1
      }
      cd "${BUILD_BASE}/lnd" || exit 1
      go mod edit -replace github.com/btcsuite/btcd="${BUILD_BASE}/btcd"
      go mod tidy
    else
      cd "${BUILD_BASE}/lnd" || exit 1
    fi

    echo "# Building LND (this is slow on ARM)..."
    # Go 1.14+ automatically uses -mod=vendor when vendor/ exists.
    # No extra flags needed — vendor/ presence is sufficient for fully offline build.
    if [ -d "${BUILD_BASE}/lnd/vendor" ]; then
      echo "# vendor/ found — building offline (no module downloads needed)"
    fi
    make install tags="autopilotrpc chainrpc invoicesrpc routerrpc signrpc walletrpc watchtowerrpc wtclientrpc" || {
      echo "# FAIL - LND build failed"; exit 1
    }

    install -m 0755 "${GOPATH}/bin/lnd" /usr/local/bin/lnd || {
      echo "# FAIL - could not install lnd to /usr/local/bin/"; exit 1
    }
    install -m 0755 "${GOPATH}/bin/lncli" /usr/local/bin/lncli || {
      echo "# FAIL - could not install lncli to /usr/local/bin/"; exit 1
    }

    # package for future use (saves 30-60 min on reinstall)
    echo "# Packaging built binaries to ${PREBUILT_TARBALL} for reuse..."
    tar -czf "${PREBUILT_TARBALL}" -C "${GOPATH}/bin" lnd lncli && \
      echo "# Saved to ${PREBUILT_TARBALL} — copy to /tmp on future installs to skip rebuild"
  fi

  # verify installation — capture stderr too so panics are visible
  if [ ! -x /usr/local/bin/lnd ]; then
    echo
    echo "# BUILD FAILED --> /usr/local/bin/lnd not found or not executable"
    exit 1
  fi
  installed=$(/usr/local/bin/lnd --version 2>&1)
  rc=$?
  if [ ${rc} -ne 0 ] || [ ${#installed} -eq 0 ]; then
    echo
    echo "# BUILD FAILED --> /usr/local/bin/lnd cannot run --version (exit ${rc})"
    echo "# lnd output:"
    echo "${installed}" | sed 's/^/#   /'
    echo "# binary info:"
    file /usr/local/bin/lnd 2>&1 | sed 's/^/#   /'
    exit 1
  fi
  echo "# Installed: ${installed}"
  sudo chown -R admin /home/admin
  echo "# OK - LND (Glcoin-patched) install done"
  exit 0
fi

# CHAIN is signet | testnet | mainnet
CHAIN=$2
if [ -z "${CHAIN}" ] || [ "$2" = purge ]; then
  source /mnt/hdd/app-data/raspiblesk.conf
  CHAIN=${chain}net
fi
if [ "${CHAIN}" = testnet ]||[ "${CHAIN}" = mainnet ]||[ "${CHAIN}" = signet ];then
  echo "# Configuring the LND instance on ${CHAIN}"
else
  echo "# ${CHAIN} is not supported"
  exit 1
fi

# prefix for parallel services
if [ ${CHAIN} = testnet ];then
  netprefix="t"
  portprefix=1
  rpcportmod=1
  glcoinRpcPort=11617
  glcoinZmqBlock=31617
  glcoinZmqTx=31618
elif [ ${CHAIN} = signet ];then
  netprefix="s"
  portprefix=3
  rpcportmod=3
  glcoinRpcPort=31617
  glcoinZmqBlock=41617
  glcoinZmqTx=41618
elif [ ${CHAIN} = mainnet ];then
  netprefix=""
  portprefix=""
  rpcportmod=0
  glcoinRpcPort=1617
  glcoinZmqBlock=21617
  glcoinZmqTx=21618
fi

source /home/admin/raspiblesk.info
source <(/home/admin/_cache.sh get state)
source /mnt/hdd/app-data/raspiblesk.conf

function removeParallelService() {
  if [ -f "/etc/systemd/system/${netprefix}lnd.service" ];then
    echo "# Stopping ${netprefix}lnd ..."
    #sudo -u glcoin /usr/local/bin/lncli --rpcserver localhost:1${rpcportmod}009 stop
    sudo systemctl stop ${netprefix}lnd
    sudo systemctl disable ${netprefix}lnd
    sudo rm /etc/systemd/system/${netprefix}lnd.service 2>/dev/null
    echo "# ${netprefix}lnd.service on ${CHAIN} is stopped and disabled"
    echo
  fi
}

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "${CHAIN}" == "testnet" ] && [ "${testnet}" != "on" ]; then
    echo "# before activating testnet on lnd, first activate testnet on glcoind"
    echo "err='missing glcoin testnet'"
    exit 1
  fi

  if [ "${CHAIN}" == "signet" ] && [ "${signet}" != "on" ]; then
    echo "# before activating signet on lnd, first activate signet on glcoind"
    echo "err='missing glcoin signet'"
    exit 1
  fi

  initwallet=0
  if [ "$3" == "initwallet" ]; then
    initwallet=1
    echo "# OK will init wallet if not exists (may ask for passwordc)"
  fi

  # make sure binary is installed (will skip if already done)
  /home/admin/config.scripts/lnd.install.sh install

  echo "# Make sure the user glcoin is in the debian-tor group"
  sudo usermod -a -G debian-tor glcoin

  # LND P2P (9735) is the actual Lightning Network peer port — must be Anywhere.
  # LND REST (8080) and gRPC (10009) carry the admin macaroon: any client with
  # that token can move funds. Scope to localhost + LAN by default; remote
  # access goes through the Tor 'lndrest' onion service (tor.network.sh).
  sudo ufw allow ${portprefix}9735 comment "${netprefix}lnd"
  for src in "127.0.0.1" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16"; do
    sudo ufw allow from ${src} to any port ${portprefix}8080 comment "${netprefix}lnd REST $([ \"${src}\" = 127.0.0.1 ] && echo localhost || echo LAN)"
    sudo ufw allow from ${src} to any port 1${rpcportmod}009 comment "${netprefix}lnd RPC $([ \"${src}\" = 127.0.0.1 ] && echo localhost || echo LAN)"
  done

  sudo chown -R glcoin:glcoin /mnt/hdd/app-data/lnd
  sudo chmod -R 750 /mnt/hdd/app-data/lnd

  echo "# Create /mnt/hdd/app-data/lnd/${netprefix}lnd.conf"
  # If a lnd.conf from the GitHub raspiblesk version exists with glcoind. backend
  # entries (wrong ZMQ ports, wrong section prefix), purge it so we write ours.
  if [ -f /mnt/hdd/app-data/lnd/${netprefix}lnd.conf ] && \
     grep -q "^glcoind\." /mnt/hdd/app-data/lnd/${netprefix}lnd.conf; then
    echo "# Detected wrong glcoind. backend entries in lnd.conf - regenerating"
    rm /mnt/hdd/app-data/lnd/${netprefix}lnd.conf
  fi
  # Also purge if rpccookiefile is present — not supported by this LND binary
  if [ -f /mnt/hdd/app-data/lnd/${netprefix}lnd.conf ] && \
     grep -q "^bitcoind\.rpccookiefile=" /mnt/hdd/app-data/lnd/${netprefix}lnd.conf; then
    echo "# Detected unsupported rpccookiefile in lnd.conf - regenerating"
    rm /mnt/hdd/app-data/lnd/${netprefix}lnd.conf
  fi
  # Also purge if lnddir is missing — LND would default to ~/.lnd which breaks if
  # the symlink /home/glcoin/.lnd is a real directory from a failed previous install
  if [ -f /mnt/hdd/app-data/lnd/${netprefix}lnd.conf ] && \
     ! grep -q "^lnddir=" /mnt/hdd/app-data/lnd/${netprefix}lnd.conf; then
    echo "# Detected missing lnddir in lnd.conf - regenerating"
    rm /mnt/hdd/app-data/lnd/${netprefix}lnd.conf
  fi
  # v0145 security migration: rebind rpclisten/restlisten from 0.0.0.0 to 127.0.0.1
  # in-place (preserves user-set alias/color/etc.). Old installs from v0140-v0144
  # exposed gRPC and REST on every interface; v0145 restricts to localhost.
  if [ -f /mnt/hdd/app-data/lnd/${netprefix}lnd.conf ]; then
    if grep -q "^rpclisten=0\.0\.0\.0:" /mnt/hdd/app-data/lnd/${netprefix}lnd.conf; then
      echo "# Migrating rpclisten 0.0.0.0 -> 127.0.0.1 (v0145 hardening)"
      sudo sed -i 's|^rpclisten=0\.0\.0\.0:|rpclisten=127.0.0.1:|' /mnt/hdd/app-data/lnd/${netprefix}lnd.conf
    fi
    if grep -q "^restlisten=0\.0\.0\.0:" /mnt/hdd/app-data/lnd/${netprefix}lnd.conf; then
      echo "# Migrating restlisten 0.0.0.0 -> 127.0.0.1 (v0145 hardening)"
      sudo sed -i 's|^restlisten=0\.0\.0\.0:|restlisten=127.0.0.1:|' /mnt/hdd/app-data/lnd/${netprefix}lnd.conf
    fi
  fi

  # Read RPC credentials from glcoin.conf (set by blesk.passwords.sh before this runs)
  _LNDINSTALL_RPCUSER=$(grep "^rpcuser=" /mnt/hdd/app-data/glcoin/glcoin.conf 2>/dev/null | cut -d= -f2 | tail -1)
  _LNDINSTALL_RPCPASS=$(grep "^rpcpassword=" /mnt/hdd/app-data/glcoin/glcoin.conf 2>/dev/null | cut -d= -f2 | tail -1)

  if [ ! -f /mnt/hdd/app-data/lnd/${netprefix}lnd.conf ];then
    echo "# LND configuration

[Application Options]
# alias=ALIAS # up to 32 UTF-8 characters
# color=COLOR # choose from: https://www.color-hex.com/
lnddir=/mnt/hdd/app-data/lnd
listen=0.0.0.0:${portprefix}9735
rpclisten=127.0.0.1:1${rpcportmod}009
restlisten=127.0.0.1:${portprefix}8080
nat=false
debuglevel=info
gc-canceled-invoices-on-startup=true
gc-canceled-invoices-on-the-fly=true
ignore-historical-gossip-filters=1
stagger-initial-reconnect=true
tlsautorefresh=1
tlsdisableautofill=1
tlscertpath=/mnt/hdd/app-data/lnd/tls.cert
tlskeypath=/mnt/hdd/app-data/lnd/tls.key

# Set to false for nodes with larger amount of channels. This modification leads to increased 
# latency during initialization, yet significantly boosts runtime performance of the daemon.
sync-freelist=true

# Specify the maximum number of logfiles retained in rotation and the threshold size for rotation initiation.
maxlogfiles=2
maxlogfilesize=400

[Bitcoin]
bitcoin.active=1
bitcoin.${CHAIN}=1
bitcoin.node=bitcoind

[Bitcoind]
bitcoind.rpchost=127.0.0.1:${glcoinRpcPort}
bitcoind.rpcuser=${_LNDINSTALL_RPCUSER}
bitcoind.rpcpass=${_LNDINSTALL_RPCPASS}
bitcoind.zmqpubrawblock=tcp://127.0.0.1:${glcoinZmqBlock}
bitcoind.zmqpubrawtx=tcp://127.0.0.1:${glcoinZmqTx}

[bolt]
db.bolt.auto-compact=true
db.bolt.auto-compact-min-age=672h

# Allow for longer latency, especially useful for <8GB RAM Pi and congested mempool
[healthcheck]
healthcheck.chainbackend.attempts=3
healthcheck.chainbackend.timeout=2m0s
healthcheck.chainbackend.interval=1m30s

[workers]
workers.sig=4
workers.write=4

[rpcmiddleware]
rpcmiddleware.enable=true
" | sudo -u glcoin tee /mnt/hdd/app-data/lnd/${netprefix}lnd.conf
  else
    echo "# The file /mnt/hdd/app-data/lnd/${netprefix}lnd.conf is already present"
  fi

  # systemd service
  removeParallelService
  echo "# Create /etc/systemd/system/.lnd.service"
  # based on https://github.com/lightningnetwork/lnd/blob/master/contrib/init/lnd.service
  echo "
[Unit]
Description=Lightning Network Daemon on $CHAIN

# Make sure lnd starts after glcoind is ready
Requires=${netprefix}glcoind.service
After=${netprefix}glcoind.service
PartOf=${netprefix}glcoind.service

[Service]
EnvironmentFile=/mnt/hdd/app-data/raspiblesk.conf

ExecStartPre=-/home/admin/config.scripts/lnd.check.sh prestart ${CHAIN}
ExecStart=/usr/local/bin/lnd --configfile=/mnt/hdd/app-data/lnd/${netprefix}lnd.conf
# avoid hanging on stop
# ExecStop=/usr/local/bin/lncli -n=${CHAIN} --rpcserver localhost:1${rpcportmod}009 stop
PIDFile=/mnt/hdd/app-data/lnd/${netprefix}lnd.pid

User=glcoin
Group=glcoin

# Try to restart lnd always
Restart=always
RestartSec=60

# Type=notify is required for lnd to notify systemd when it is ready
Type=notify

# An extended timeout period is needed to allow for database compaction
# and other time intensive operations during startup. We also extend the
# stop timeout to ensure graceful shutdowns of lnd.
TimeoutStartSec=1200
TimeoutStopSec=3600

StandardOutput=null
StandardError=journal

# Hardening Measures
####################
# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full
# Disallow the process and all of its children to gain
# new privileges through execve().
NoNewPrivileges=true
# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true
# Deny the creation of writable and executable memory mappings.
MemoryDenyWriteExecute=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${netprefix}lnd.service
  sudo systemctl enable ${netprefix}lnd
  echo "# Enabled the ${netprefix}lnd.service"
  if [ "${state}" == "ready" ]; then
    sudo systemctl start ${netprefix}lnd
    echo "# Started the ${netprefix}lnd.service"
  fi

  echo
  echo "# Add aliases ${netprefix}lncli, ${netprefix}lndlog, ${netprefix}lndconf"
  sudo -u admin touch /home/admin/_aliases
  if [ $(grep -c "alias ${netprefix}lncli" < /home/admin/_aliases) -eq 0 ];then
    echo "\
alias ${netprefix}lncli=\"sudo -u glcoin /usr/local/bin/lncli\
 -n=${CHAIN} --rpcserver localhost:1${rpcportmod}009\"\
" | sudo tee -a /home/admin/_aliases
  fi
  if [ $(grep -c "alias ${netprefix}lndlog" < /home/admin/_aliases) -eq 0 ];then
    echo "\
alias ${netprefix}lndlog=\"sudo tail -n 30 -f /mnt/hdd/app-data/lnd/logs/bitcoin/glcoin/lnd.log\"\
" | sudo tee -a /home/admin/_aliases
  fi
  if [ $(grep -c "alias ${netprefix}lndconf" < /home/admin/_aliases) -eq 0 ];then
    echo "\
alias ${netprefix}lndconf=\"sudo nano /mnt/hdd/app-data/lnd/${netprefix}lnd.conf\"\
" | sudo tee -a /home/admin/_aliases
  fi

  # if parameter "initwallet" was set and wallet does not exist yet
  walletExists=$(sudo ls /mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/wallet.db 2>/dev/null | grep -c "wallet.db")
  echo "# initwallet(${initwallet}) walletExists(${walletExists})"
  if [ "${initwallet}" == "1" ] && [ "${walletExists}" == "0" ]; then
      if [ "${CHAIN}" == "mainnet" ]; then
        tempFile="/var/cache/raspiblesk/passwordc.tmp"
        sudo /home/admin/config.scripts/blesk.passwords.sh set x "PASSWORD C - LND Wallet Password" ${tempFile}
        passwordC=$(sudo cat ${tempFile})
        sudo rm ${tempFile}
      else
        # generate random wallet password for testnet/signet — stored in password.info for auto-unlock
        _pwFile="/mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/password.info"
        _blobFile="/mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/password.glce"
        if sudo ls ${_blobFile} &>/dev/null; then
          # decrypt GLCE blob to get wallet password
          _blob=$(sudo cat ${_blobFile})
          passwordC=$(sudo -u glcoin /usr/local/bin/glcoin-cli -rpcport=1617 decryptcontent "${_blob}" 2>/dev/null | \
            python3 -c "import sys,json; print(bytes.fromhex(json.load(sys.stdin)['content']).decode())" 2>/dev/null)
        elif sudo ls ${_pwFile} &>/dev/null; then
          passwordC=$(sudo cat ${_pwFile})
        else
          passwordC=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9!@#%^&*_+=<>?.-' | head -c 32)
          sudo mkdir -p "$(dirname ${_pwFile})"
          # try GLCE encryption
          _hex=$(printf '%s' "${passwordC}" | xxd -p -c 1000 | tr -d '\n')
          _pubkey=$(sudo -u glcoin /usr/local/bin/glcoin-cli -rpcport=1617 getencryptionpubkey 2>/dev/null | \
            python3 -c "import sys,json; print(json.load(sys.stdin)['pubkey'])" 2>/dev/null)
          if [ -n "${_pubkey}" ]; then
            _blob=$(sudo -u glcoin /usr/local/bin/glcoin-cli -rpcport=1617 encryptcontent "${_hex}" "${_pubkey}" 2>/dev/null | \
              python3 -c "import sys,json; print(json.load(sys.stdin)['blob'])" 2>/dev/null)
            if [ -n "${_blob}" ]; then
              echo "${_blob}" | sudo -u glcoin tee ${_blobFile} 1>/dev/null
              sudo chmod 600 ${_blobFile}
              echo "# LND ${CHAIN} wallet password GLCE-encrypted in ${_blobFile}"
              # password.info not needed — auto-unlock reads via wrapper or we store placeholder
            fi
          fi
          # always write plaintext password.info as fallback for auto-unlock compatibility
          echo "${passwordC}" | sudo -u glcoin tee ${_pwFile} 1>/dev/null
          sudo chmod 600 ${_pwFile}
        fi
      fi
      # Pipe wallet password as JSON via stdin so it doesn't appear in
      # /proc/PID/cmdline. Uses `sudo -u glcoin` to keep gRPC TLS access from
      # the right user; `env -i` would break grpc cert path.
      _stdin_json=$(passwordC="${passwordC}" \
        python3 -c 'import json,os;print(json.dumps({"wallet_password":os.environ["passwordC"]}))')
      source <(printf '%s' "${_stdin_json}" | sudo /home/admin/config.scripts/lnd.initwallet.py new ${CHAIN} --stdin)
      unset _stdin_json
      if [ "${err}" != "" ]; then
        clear
        echo "# LND ${CHAIN} wallet creation failed"
        echo "# ${err}"
        echo "# press ENTER to continue"
        read key
      else
        sudo mkdir -p /mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}
        seedFile="/mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/seedwords.info"
        echo "seedwords='${seedwords}'" | sudo tee ${seedFile}
        echo "seedwords6x4='${seedwords6x4}'" | sudo tee -a ${seedFile}
        sudo chown glcoin:glcoin ${seedFile}
        sudo chmod 600 ${seedFile}
      fi
  fi

  if [ "${CHAIN}" != "mainnet" ]; then
    echo "# Setting autounlock for ${CHAIN}"
    source <(/home/admin/config.scripts/network.aliases.sh getvars lnd ${CHAIN})
    passwordFile="/mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/password.info"
    # create passwordfile if not already written during wallet init above
    if ! sudo ls ${passwordFile} &>/dev/null; then
      _newpw=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
      echo "${_newpw}" | sudo -u glcoin tee ${passwordFile} 1>/dev/null
      sudo chmod 600 ${passwordFile}
    fi
    # add autounlock to lnd.conf
    if ! grep "^wallet-unlock-password-file=${passwordFile}" < ${lndConfFile}; then
      if grep "^\[Application Options\]" < ${lndConfFile} &>/dev/null; then
        # add under header
        sudo sed -i "/^\[Application Options\]$/awallet-unlock-password-file=${passwordFile}" ${lndConfFile}
      else
        # just append if no headers used
        echo "wallet-unlock-password-file=${passwordFile}" | sudo -u glcoin tee ${lndConfFile}
      fi
    fi
  fi

  echo
  echo "# The installed LND version is: $(sudo -u glcoin /usr/local/bin/lnd --version)"
  echo
  echo "# To activate the aliases reopen the terminal or use:"
  echo "source ~/_aliases"
  echo "# Monitor the ${netprefix}lnd with:"
  echo "sudo journalctl -fu ${netprefix}lnd"
  echo "sudo systemctl status ${netprefix}lnd"
  echo "# logs:"
  echo "sudo tail -f /mnt/hdd/app-data/lnd/logs/glcoin/${CHAIN}/lnd.log"
  echo "# for the command line options use"
  echo "${netprefix}lncli help"
  echo

  # setting value in raspi blitz config
  /home/admin/config.scripts/blesk.conf.sh set ${netprefix}lnd "on"

  # if this is the first lightning mainnet turned on - make default
  if [ "${CHAIN}" == "mainnet" ]; then
    if [ "${lightning}" == "" ] || [ "${lightning}" == "none" ]; then
      echo "# LND is now default lighthning implementation"
      /home/admin/config.scripts/blesk.conf.sh set lightning "lnd"
    fi
  fi

  # needed to make lnd.newwallet.py work
  pip config set global.break-system-packages true
  pip install --upgrade google-api-python-client

  exit 0
fi

if [ "$1" = "display-seed" ]; then

  # check if sudo
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (with sudo)"
    exit 1
  fi

  # get network and aliasses from second parameter (default mainnet)
  displayNetwork=$2
  if [ "${displayNetwork}" == "" ]; then
    displayNetwork="mainnet"
  fi

  deleteSeedInfoAfterDisplay=0
  if [ "$3" == "delete" ]; then
    echo "# deleting seedinfo after display"
    deleteSeedInfoAfterDisplay=1
  fi

  # check if seedword file exists
  seedwordFile="/mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/seedwords.info"
  echo "# seedwordFile(${seedwordFile})"
  seedwordFileExists=$(ls ${seedwordFile} 2>/dev/null | grep -c "seedwords.info")
  echo "# seedwordFileExists(${seedwordFileExists})"
  if [ "${seedwordFileExists}" == "1" ]; then
    source ${seedwordFile}
  fi
  if [ "${seedwords}" != "" ]; then
    #echo "# seedwords(${seedwords})"
    #echo "# seedwords6x4(${seedwords6x4})"
    ack=0
    while [ ${ack} -eq 0 ]
    do
      whiptail --title "LND ${displayNetwork} Wallet" \
        --msgbox "This is your LND ${displayNetwork} wallet seed. Store these numbered words in a safe location:\n\n${seedwords6x4}" 13 76
      whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
      if [ $? -eq 1 ]; then
        ack=1
      fi
    done
    if [ "${deleteSeedInfoAfterDisplay}" == "1" ]; then
      echo "# deleting seed info"
      sudo shred ${seedwordFile}
      sudo rm ${seedwordFile} 2>/dev/null
    fi
  else
    walletFile="/mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/wallet.db"
    whiptail --title "LND ${displayNetwork} Wallet Info" --msgbox "Your LND ${displayNetwork} wallet was already created before - there are no seed words available.\n\nTo secure your wallet secret you can manually backup the file: ${walletFile}" 11 76
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# removing ${CHAIN} lnd service (if active)"

  removeParallelService

  # setting value in raspiblesk config
  /home/admin/config.scripts/blesk.conf.sh set ${netprefix}lnd "off"
  echo "# ${netprefix}lnd --> off"

  # if lnd mainnet was default - remove
  if [ "${CHAIN}" == "mainnet" ] && [ "${lightning}" == "lnd" ]; then
    echo "# LND is REMOVED as default lightning implementation"
    /home/admin/config.scripts/blesk.conf.sh set lightning "none"
    if [ "${cl}" == "on" ]; then
      echo "# CL is now the new default lightning implementation"
      /home/admin/config.scripts/blesk.conf.sh set lightning "cl"
    fi
  fi

  # purge
  if echo "$@" | grep purge; then
    echo "# Stop on LND all networks and delete lnd binaries"
    /home/admin/config.scripts/lnd.install.sh off mainnet
    /home/admin/config.scripts/lnd.install.sh off testnet
    /home/admin/config.scripts/lnd.install.sh off signet
    sudo rm /usr/local/bin/lncli
    sudo rm /usr/local/bin/lnd
    echo "# Deleted the binaries"
  fi

  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1
