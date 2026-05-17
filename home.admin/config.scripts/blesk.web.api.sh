#!/usr/bin/env bash

# main repo: https://github.com/fusion44/blitz_api

# restart the systemd `bleskapi` when credentials of lnd or glcoind are changed and it will
# excute the `update-config` automatically before restarting

# NORMALLY user/repo/version will be defined by calling script - see build_sdcard.sh
# the following is just a fallback to try during development if script given branch does not exist
FALLACK_BRANCH="dev"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "Manage RaspiBlesk Web API and Celery Services"
  echo "blesk.web.api.sh info"
  echo "blesk.web.api.sh on [GITHUBUSER] [REPO] [BRANCH] [?COMMITORTAG]"
  echo "blesk.web.api.sh on DEFAULT"
  echo "blesk.web.api.sh update-config"
  echo "blesk.web.api.sh update-code [?BRANCH]"
  echo "blesk.web.api.sh off"
  exit 1
fi

###################
# INFO
###################
if [ "$1" = "info" ]; then

  # check if installed
  cd /home/bleskapi/blitz_api 2>/dev/null
  if [ "$?" != "0" ]; then
    echo "installed=0"
    exit 1
  fi
  echo "installed=1"

  # get github origin repo from repo directory with git command
  origin=$(sudo -u bleskapi git config --get remote.origin.url)
  echo "repo='${origin}'"

  # get github branch from repo directory with git command
  branch=$(sudo -u bleskapi git rev-parse --abbrev-ref HEAD)
  echo "branch='${branch}'"

  # get github commit from repo directory with git command
  commit=$(sudo -u bleskapi git rev-parse HEAD)
  echo "commit='${commit}'"

  # Check status of systemd services
  echo "# Checking service status..."
  systemctl is-active --quiet bleskapi && echo "bleskapi_service_status='active'" || echo "bleskapi_service_status='inactive'"
  systemctl is-active --quiet bleskapi-celery-worker && echo "celery_worker_service_status='active'" || echo "celery_worker_service_status='inactive'"
  systemctl is-active --quiet bleskapi-celery-beat && echo "celery_beat_service_status='active'" || echo "celery_beat_service_status='inactive'"


  exit 0
fi

###################
# UPDATE CONFIG
###################
if [ "$1" = "update-config" ]; then

  # prepare configs data
  source /mnt/hdd/app-data/raspiblesk.conf 2>/dev/null
  if [ "${network}" = "" ]; then
    network="glcoin"
    chain="main"
  fi

  # prepare config update
  cd /home/bleskapi/blitz_api || exit 1
  secret=$(cat ./.env 2>/dev/null | grep "BAPI_JWT_SECRET=" | cut -d "=" -f2)
  cp ./.env_sample ./.env
  dateStr=$(date)
  echo "# Update Web API CONFIG (${dateStr})"
  # The upstream fusion44/blitz_api fork does NOT register "raspiblesk" as a
  # known APIPlatform value — it only knows "raspiblitz" and "native_python".
  # Until a proper Glcoin fork of blitz_api exists, declare the platform as
  # raspiblitz so the FastAPI app boots; all the actual config below points
  # at glcoind on 127.0.0.1:1617 and LND with the Glcoin macaroon path, so
  # the runtime semantics are Glcoin's regardless of the platform label.
  sed -i "s/^# BAPI_PLATFORM=.*/BAPI_PLATFORM=raspiblitz/g" ./.env
  sed -i "s/^BAPI_PLATFORM=.*/BAPI_PLATFORM=raspiblitz/g" ./.env

  # configure access token secret
  if [ "${secret}" == "" ] || [ "${secret}" == "please_please_update_me_please" ]; then
    echo "# init secret ..."
    secret=$(dd if=/dev/urandom bs=256 count=1 2>/dev/null | shasum -a256 | cut -d " " -f1)
  else
    echo "# use existing secret"
  fi
  sed -i "s/^BAPI_JWT_SECRET=.*/BAPI_JWT_SECRET=${secret}/g" ./.env

  source /home/admin/raspiblesk.info 2>/dev/null
  # The original gate `setupPhase == done` blocked the daemon/wallet config
  # from ever being written during fatpack provisioning (setupPhase is still
  # "boot" or "setup" at that point), leaving the .env at its placeholder
  # values (RPC user "raspibolt", password "please_please_update_me_please",
  # port 8332). The result was bleskapi crash-looping or talking to nothing.
  # Always patch the daemon credentials — at worst the values are blank if
  # glcoin.conf isn't readable yet, which is fine because the API restarts
  # automatically on every config change anyway.

  # configure glcoin RPC — upstream blitz_api uses BAPI_BITCOIND_* env vars
  # (Bitcoin-named in the codebase, but pointed at Glcoin's daemon here)
  RPCUSER=$(sudo cat /mnt/hdd/app-data/${network}/${network}.conf 2>/dev/null | grep "^rpcuser=" | cut -d= -f2-)
  RPCPASS=$(sudo cat /mnt/hdd/app-data/${network}/${network}.conf 2>/dev/null | grep "^rpcpassword=" | cut -d= -f2-)
  if [ "${RPCUSER}" == "" ]; then
    RPCUSER="raspibolt"
  fi
  if [ "${RPCPASS}" == "" ]; then
    RPCPASS="passwordB"
  fi
  # Glcoin port map: mainnet RPC=1617, testnet=11617, signet=21617.
  # ZMQ pubrawblock per glcoin.check.sh: mainnet=21617, testnet=31617, signet=41617.
  if [ "${chain}" == "main" ]; then
    GLC_RPC_PORT=1617
    GLC_ZMQ_PORT=21617
  elif [ "${chain}" == "test" ]; then
    GLC_RPC_PORT=11617
    GLC_ZMQ_PORT=31617
  elif [ "${chain}" == "sig" ]; then
    GLC_RPC_PORT=21617
    GLC_ZMQ_PORT=41617
  else
    GLC_RPC_PORT=1617
    GLC_ZMQ_PORT=21617
  fi
  sed -i "s/^BAPI_NETWORK=.*/BAPI_NETWORK=${chain}net/g" ./.env
  sed -i "s/^BAPI_BITCOIND_ADDRESS=.*/BAPI_BITCOIND_ADDRESS=127.0.0.1/g" ./.env
  sed -i "s/^BAPI_BITCOIND_PORT_RPC=.*/BAPI_BITCOIND_PORT_RPC=${GLC_RPC_PORT}/g" ./.env
  sed -i "s/^BAPI_BITCOIND_USER=.*/BAPI_BITCOIND_USER=${RPCUSER}/g" ./.env
  sed -i "s/^BAPI_BITCOIND_RPC_PW=.*/BAPI_BITCOIND_RPC_PW=${RPCPASS}/g" ./.env
  sed -i "s/^BAPI_BITCOIND_ZMQ_BLOCK_PORT=.*/BAPI_BITCOIND_ZMQ_BLOCK_PORT=${GLC_ZMQ_PORT}/g" ./.env

  # configure LND — accept both lightning=lnd (primary RaspiBlesk flag) and
  # lnd=on (secondary, used by some provisioning paths). LND is mandatory on
  # RaspiBlesk so default to lnd_grpc when neither flag is set.
  if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ] || { [ -z "${lightning}" ] && [ -z "${lnd}" ]; }; then

      echo "# CONFIG Web API Lightning --> LND"
      tlsCert=$(sudo xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/tls.cert 2>/dev/null)
      adminMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/glcoin/${chain}net/admin.macaroon 2>/dev/null)
      sed -i "s/^BAPI_LN_NODE=.*/BAPI_LN_NODE=lnd_grpc/g" ./.env
      sed -i "s/^BAPI_LND_GRPC_IP=.*/BAPI_LND_GRPC_IP=127.0.0.1/g" ./.env
      sed -i "s/^BAPI_LND_MACAROON=.*/BAPI_LND_MACAROON=${adminMacaroon}/g" ./.env
      sed -i "s/^BAPI_LND_CERT=.*/BAPI_LND_CERT=${tlsCert}/g" ./.env
      if [ "${chain}" == "main" ]; then
        L2rpcportmod=0
        portprefix=""
      elif [ "${chain}" == "test" ]; then
        L2rpcportmod=1
        portprefix=1
      elif [ "${chain}" == "sig" ]; then
        L2rpcportmod=3
        portprefix=3
      fi
      lnd_grpc_port=1${L2rpcportmod}009
      lnd_rest_port=${portprefix}8080

    # configure CL
    elif [ "${lightning}" == "cl" ]; then

      echo "# CONFIG Web API Lightning --> CL"
      sed -i "s/^BAPI_LN_NODE=.*/BAPI_LN_NODE=cln_jrpc/g" ./.env
      sed -i "s#^BAPI_CLN_JRPC_PATH=.*#BAPI_CLN_JRPC_PATH=\"/mnt/hdd/app-data/.lightning/glcoin/lightning-rpc\"#g" ./.env

      # get hex values of pem files
      # hexClient=$(sudo xxd -p -c2000 /home/glcoin/.lightning/glcoin/client.pem)
      # hexClientKey=$(sudo xxd -p -c2000 /home/glcoin/.lightning/glcoin/client-key.pem)
      # hexCa=$(sudo xxd -p -c2000 /home/glcoin/.lightning/glcoin/ca.pem)
      # if [ "${hexClient}" == "" ]; then
      #  echo "# FAIL /home/glcoin/.lightning/glcoin/*.pem files maybe missing"
      # fi

      # update config with hex values
      # sed -i "s/^BAPI_CLN_GRPC_CERT=.*/BAPI_CLN_GRPC_CERT=${hexClient}/g" ./.env
      # sed -i "s/^BAPI_CLN_GRPC_KEY=.*/BAPI_CLN_GRPC_KEY=${hexClientKey}/g" ./.env
      # sed -i "s/^BAPI_CLN_GRPC_CA=.*/BAPI_CLN_GRPC_CA=${hexCa}/g" ./.env
      # sed -i "s/^BAPI_CLN_GRPC_IP=.*/BAPI_CLN_GRPC_IP=127.0.0.1/g" ./.env
      # sed -i "s/^BAPI_CLN_GRPC_PORT=.*/BAPI_CLN_GRPC_PORT=4772/g" ./.env

    else
      echo "# CONFIG Web API Lightning --> OFF"
      sed -i "s/^BAPI_LN_NODE=.*/BAPI_LN_NODE=none/g" ./.env
    fi

  # Note: Celery services might need a restart if config changes affect them.
  # The main bleskapi service restarts automatically due to ExecStartPre.
  # For simplicity, Celery services are only restarted during 'update-code' or 'on'.
  echo "# '.env' config updates - bleskapi service will restart automatically."
  echo "# Celery services may need manual restart or 'update-code' run if config changes affect them."
  exit 0

fi

# all other actions need to be sudo
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root'"
  exit 1
fi

###################
# ON / INSTALL
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "$2" == "DEFAULT" ]; then
    echo "# API: getting default user/repo from build_sdcard.sh"
    # copy build_sdcard.sh out of raspiblesk diretcory to not create "changes" in git
    sudo cp /home/admin/raspiblesk/build_sdcard.sh /home/admin/build_sdcard.sh
    sudo chmod +x /home/admin/build_sdcard.sh 2>/dev/null
    source <(sudo /home/admin/build_sdcard.sh -EXPORT)
    GITHUB_USER="${defaultAPIuser}"
    GITHUB_REPO="${defaultAPIrepo}"
    activeBranch=$(git -C /home/admin/raspiblesk branch --show-current)
    if [ "${activeBranch}" == "" ]; then
      echo "# activeBranch not detected by git command, trying build script repo(${githubBranch})"
      activeBranch="${githubBranch}"
    fi
    echo "# activeBranch detected by raspiblesk repo: ${activeBranch}"
    if [[ "$activeBranch" == *"dev"* || "$activeBranch" != v* ]]; then
      echo "# RELEASE CANDIDATE: using dev branch"
      GITHUB_BRANCH="dev"
    else
      GITHUB_BRANCH="blitz-${activeBranch}"
    fi

    # v0.15.20 (Bug F5): pin to a known-good commit instead of branch HEAD.
    # The dev branch is a moving target — every build_sdcard.sh used to
    # pull whatever HEAD happened to be at clone time, which silently
    # drifted the RASPIBLESK_FORK_PATCH and RASPIBLESK_LOGIN_PATCH apply
    # surface between runs. Commit 62b6438970580d3c5269da8e1caf683607db491e
    # (2026-05-12, "chore(deps): bump urllib3 from 2.6.3 to 2.7.0") is the
    # commit the v0.15.19 Pi-flash actually used, with both patches verified
    # to apply cleanly. Bump this when a newer upstream commit has been
    # exercised end-to-end through a Pi reflash + WebUI login + setup-flow.
    GITHUB_COMMITORTAG="62b6438970580d3c5269da8e1caf683607db491e"
  else
    # get parameters
    GITHUB_USER=$2
    GITHUB_REPO=$3
    GITHUB_BRANCH=$4
    GITHUB_COMMITORTAG=$5
  fi

  # check & output info
  echo "# GITHUB_USER(${GITHUB_USER})"
  if [ "${GITHUB_USER}" == "" ]; then
    echo "# FAIL: No GITHUB_USER provided"
    exit 1
  fi
  echo "# GITHUB_REPO(${GITHUB_REPO})"
  if [ "${GITHUB_REPO}" == "" ]; then
    echo "# FAIL: No GITHUB_REPO provided"
    exit 1
  fi
  echo "# GITHUB_BRANCH(${GITHUB_BRANCH})"
  if [ "${GITHUB_BRANCH}" == "" ]; then
    echo "# FAIL: No GITHUB_BRANCH provided"
    exit 1
  fi
  echo "# GITHUB_COMMITORTAG(${GITHUB_COMMITORTAG})"
  if [ "${GITHUB_COMMITORTAG}" == "" ]; then
    echo "# INFO: No GITHUB_COMMITORTAG provided .. will use latest code on branch"
  fi

  # check if given branch exits on that github user/repo
  branchExists=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/branches/${GITHUB_BRANCH}" | grep -c "\"name\": \"${GITHUB_BRANCH}\"")
  if [ ${branchExists} -lt 1 ]; then
    echo
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "# WARNING! The given API repo is not available:"
    echo "# user(${GITHUB_USER}) repo(${GITHUB_REPO}) branch(${GITHUB_BRANCH})"
    GITHUB_BRANCH="${FALLACK_BRANCH}"
    echo "# SO WORKING WITH FALLBACK REPO:"
    echo "# user(${GITHUB_USER}) repo(${GITHUB_REPO}) branch(${GITHUB_BRANCH})"
    echo "# USE JUST FOR DEVELOPMENT - DONT USE IN PRODUCTION"
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    sleep 10
    GITHUB_BRANCH="${FALLACK_BRANCH}"
  fi

  # re-check (if case its fallback)
  branchExists=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/branches/${GITHUB_BRANCH}" | grep -c "\"name\": \"${GITHUB_BRANCH}\"")
  if [ ${branchExists} -lt 1 ]; then
    echo
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "# FAIL! user(${GITHUB_USER}) repo(${GITHUB_REPO}) branch(${GITHUB_BRANCH})"
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
  fi

  echo "# INSTALL Web API & Celery Services..."
  # clean old source
  rm -r /root/blitz_api 2>/dev/null
  rm -r /home/bleskapi/blitz_api 2>/dev/null

  # create user
  adduser --system --group --home /home/bleskapi bleskapi

  # sudo capability for manipulating passwords
  /usr/sbin/usermod --append --groups sudo bleskapi
  # access password hash and salt
  /usr/sbin/usermod --append --groups admin bleskapi
  # access lnd creds
  /usr/sbin/usermod --append --groups lndadmin bleskapi
  # access cln creds
  /usr/sbin/usermod --append --groups glcoin bleskapi
  echo "# allowing user as part of the glcoin group to RW RPC hook"
  # During fresh provisioning the CLN binary is installed but has never run,
  # so /home/glcoin/.lightning/glcoin and the lightning-rpc socket do not
  # exist yet — pre-create the tree as the glcoin service-user to keep the
  # chmod + config-edit below idempotent and silent on first install. The
  # socket itself is created by lightningd on first start and inherits the
  # rpc-file-mode=0660 we append to the config a few lines below.
  sudo -u glcoin mkdir -p /home/glcoin/.lightning/glcoin
  chmod 770 /home/glcoin/.lightning/glcoin
  chmod 660 /home/glcoin/.lightning/glcoin/lightning-rpc 2>/dev/null || true
  CLCONF="/home/glcoin/.lightning/config"
  sudo -u glcoin touch "${CLCONF}"
  if [ "$(grep -c '^rpc-file-mode=0660' "${CLCONF}" 2>/dev/null)" -eq 0 ]; then
    echo "rpc-file-mode=0660" | sudo -u glcoin tee -a "${CLCONF}" >/dev/null
  fi
  /usr/sbin/usermod --append --groups glcoin bleskapi
  # symlink the CLN data dir for bleskapi
  sudo rm -rf /home/bleskapi/.lightning # not a symlink.. delete it silently
  # create symlink
  sudo -u bleskapi ln -s /mnt/hdd/app-data/.lightning /home/bleskapi/

  cd /home/bleskapi || exit 1

  # git clone https://github.com/fusion44/blitz_api.git /home/bleskapi/blitz_api
  echo "# clone github: ${GITHUB_USER}/${GITHUB_REPO}"
  if ! sudo -u bleskapi git clone https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git blitz_api; then
    echo "error='git clone failed'"
    exit 1
  fi
  cd blitz_api || exit 1
  echo "# checkout branch: ${GITHUB_BRANCH}"
  if ! sudo -u bleskapi git checkout ${GITHUB_BRANCH}; then
    echo "error='git checkout failed'"
    exit 1
  fi
  if [ "${GITHUB_COMMITORTAG}" != "" ]; then
    echo "# setting code to tag/commit: ${GITHUB_COMMITORTAG}"
    if ! git reset --hard ${GITHUB_COMMITORTAG}; then
      echo "error='git reset failed'"
      exit 1
    fi
  else
    echo "# using the latest code in branch"
  fi

  # ----- RASPIBLESK_FORK_PATCH -----
  # Upstream blitz_api (fusion44/blitz_api dev branch) hardcodes RaspiBlitz
  # paths and a charset-restricted password regex. RaspiBlesk renames
  # raspiblitz.conf → raspiblesk.conf, the cache dir to /var/cache/raspiblesk/,
  # and blesk.passwords.sh accepts !@#%^&*()_+=<>?.- in passwords.
  # Without this sed-pass:
  #   - /setup/status reads the wrong config file (always reports "needs setup")
  #   - /system/login returns 401 for any password containing special chars
  #     outside the dev-branch regex `^[\.a-zA-Z0-9-_]*$` (so any of
  #     !@#%^&*()_+=<>? rejects) — even when the hash on disk matches,
  #     password_valid() rejects format BEFORE the hash check runs.
  # File layout matches dev branch:
  #   app/system/impl/raspiblitz_utils.py    — password_valid regex
  #   app/setup/impl/raspiblitz/router.py    — setupFilePath, configFilePath
  #   app/apps/impl/raspiblitz.py            — install log path
  # Idempotent: marked with "RASPIBLESK_FORK_PATCH" inside each patched file.
  # sed delimiters chosen per-line to avoid collision with content chars.
  SYSTEM_UTILS=/home/bleskapi/blitz_api/app/system/impl/raspiblitz_utils.py
  SETUP_ROUTER=/home/bleskapi/blitz_api/app/setup/impl/raspiblitz/router.py
  APPS_IMPL=/home/bleskapi/blitz_api/app/apps/impl/raspiblitz.py
  if ! grep -q 'RASPIBLESK_FORK_PATCH' "${SYSTEM_UTILS}" 2>/dev/null; then
    echo "# applying RASPIBLESK_FORK_PATCH to blitz_api source"

    # password_valid(): widen charset to match blesk.passwords.sh's
    # 'A-Za-z0-9!@#%^&*()_+=<>?.-'. Dev-branch upstream regex is
    # `^[\.a-zA-Z0-9-_]*$` (allows ._- already, missing !@#%^&*()_+=<>?).
    # Use Python heredoc instead of sed — the Python regex string has a
    # literal backslash (\.) inside double quotes inside a Python string,
    # which would require a forest of escaping in BRE. We carefully patch
    # ONLY the password_valid() function (not the identical name_valid()
    # regex on the same module) by anchoring on the function-def line.
    sudo -u bleskapi python3 - "${SYSTEM_UTILS}" <<'PY'
import io, sys
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    src = f.read()
NEEDLE = 'def password_valid(password: str):'
OLD_RX = 'return re.match("^[\\.a-zA-Z0-9-_]*$", password)'
NEW_RX = 'return re.match(r"^[a-zA-Z0-9!@#%^&*()_+=<>?.-]*$", password)\t# RASPIBLESK_FORK_PATCH'
i = src.find(NEEDLE)
if i < 0:
    sys.stderr.write(f"# RASPIBLESK_FORK_PATCH: {NEEDLE!r} not found in {path}\n")
    sys.exit(1)
# scan from i to next 'def ' (or EOF) and replace OLD_RX inside that window
j = src.find('\ndef ', i + len(NEEDLE))
if j < 0:
    j = len(src)
window = src[i:j]
if OLD_RX not in window:
    sys.stderr.write(f"# RASPIBLESK_FORK_PATCH: regex line not found inside password_valid in {path}\n")
    sys.exit(1)
new_window = window.replace(OLD_RX, NEW_RX, 1)
src = src[:i] + new_window + src[j:]
with io.open(path, "w", encoding="utf-8") as f:
    f.write(src)
print(f"# RASPIBLESK_FORK_PATCH: password_valid charset widened in {path}")
PY

    # setupFilePath + configFilePath in app/setup/impl/raspiblitz/router.py.
    # Delimiter `|` chosen — string literals contain `/` (delim-conflict
    # with `/`) and the comment uses `#` (delim-conflict with `#`).
    sudo -u bleskapi sed -i \
      -e 's|"/var/cache/raspiblitz/temp/raspiblitz\.setup"|"/var/cache/raspiblesk/temp/raspiblesk.setup"\t# RASPIBLESK_FORK_PATCH|' \
      -e 's|"/mnt/hdd/raspiblitz\.conf"|"/mnt/hdd/app-data/raspiblesk.conf"\t# RASPIBLESK_FORK_PATCH|' \
      "${SETUP_ROUTER}"

    # install-log path in app/apps/impl/raspiblitz.py (snake_case on dev)
    sudo -u bleskapi sed -i \
      's|f"/var/cache/raspiblitz/temp/install\.{app_id}\.log"|f"/var/cache/raspiblesk/temp/install.{app_id}.log"\t# RASPIBLESK_FORK_PATCH|' \
      "${APPS_IMPL}"

    # Verify each patch landed (sed -i exit-0 on no-match — silent failure)
    for marker_file in "${SYSTEM_UTILS}" "${SETUP_ROUTER}" "${APPS_IMPL}"; do
      if ! grep -q 'RASPIBLESK_FORK_PATCH' "${marker_file}"; then
        echo "error='RASPIBLESK_FORK_PATCH sed missed marker in ${marker_file}'"
        exit 1
      fi
    done
    echo "# RASPIBLESK_FORK_PATCH applied + verified"
  else
    echo "# RASPIBLESK_FORK_PATCH already applied (skipping)"
  fi

  # ----- RASPIBLESK_LOGIN_PATCH (v0.15.16, Bug P-Followup) -----
  # Upstream blitz_api's login() implementation in impl/raspiblitz.py (or
  # impl/native_python.py / service.py) verifies the password with an
  # algorithm that does NOT match the `mkpasswd -m sha-512 -S <salt>` output
  # written by blesk.passwords.sh into /mnt/hdd/app-data/passwords/a.hash.
  # Result: every login returns 401 "Password is incorrect" even with the
  # correct password and the post-v0164 charset-widened password_valid() regex.
  # Fix: replace the body of the first async def login() found with a
  # subprocess shell-out to the same set-side script — same call pattern as
  # main-branch system.py uses for `password_change` (subprocess against
  # blitz.passwords.sh check). Guaranteed match because both sides run the
  # exact same mkpasswd command on the exact same a.hash + salt.txt.
  # Idempotent: marked with RASPIBLESK_LOGIN_PATCH inside the patched file.
  if ! grep -rq 'RASPIBLESK_LOGIN_PATCH' /home/bleskapi/blitz_api/app/system/ 2>/dev/null; then
    echo "# applying RASPIBLESK_LOGIN_PATCH to blitz_api source"
    sudo -u bleskapi python3 - <<'PY'
import io, re, sys

CANDIDATES = [
    "/home/bleskapi/blitz_api/app/system/impl/raspiblitz.py",
    "/home/bleskapi/blitz_api/app/system/impl/native_python.py",
    "/home/bleskapi/blitz_api/app/system/service.py",
]

# Match `async def login(` exactly (NOT login_path, login_user, etc.).
SIG_RE = re.compile(r"^(\s*)async def login\s*\(([^)]*)\)\s*(->\s*[^:]+)?:\s*\n", re.M)

for path in CANDIDATES:
    try:
        with io.open(path, "r", encoding="utf-8") as f:
            src = f.read()
    except FileNotFoundError:
        continue
    if "RASPIBLESK_LOGIN_PATCH" in src:
        print(f"# RASPIBLESK_LOGIN_PATCH: {path} already patched")
        sys.exit(0)
    m = SIG_RE.search(src)
    if not m:
        continue

    indent = m.group(1)
    params = m.group(2)
    body_indent = indent + "    "

    # Derive the password expression from the param signature.
    #   `password: str`                  -> "password"
    #   `i: LoginInput`                  -> "i.password"
    #   `login_data: LoginInput`         -> "login_data.password"
    #   `self, i: LoginInput` (method)   -> "i.password"  (self is stripped)
    # blitz_api/dev moved login() onto a `RaspiBlitzSystem` class — strip the
    # leading `self` with a word-boundary so `self_data: X` is left alone.
    params_clean = re.sub(r"^\s*self\b\s*,?\s*", "", params)
    pm = re.match(r"\s*(\w+)\s*:\s*(\w+)", params_clean)
    if not pm:
        sys.stderr.write(f"# RASPIBLESK_LOGIN_PATCH: unrecognised signature in {path}: {params!r}\n")
        sys.exit(1)
    pname, ptype = pm.group(1), pm.group(2)
    pw_expr = pname if ptype == "str" else f"{pname}.password"

    # Find end of function. Stop at the FIRST of:
    #   (a) next sibling at same indent: another `async def|def|class|@deco`
    #   (b) end of enclosing class: any non-blank line at strictly LESS indent
    # Without (b), if login() is the last method in its class we would
    # overwrite everything past it to EOF — audit-grade defense.
    start = m.end()
    end_candidates = []
    end_re_same = re.compile(rf"^{indent}(async def|def |class |@)", re.M)
    m_same = end_re_same.search(src, start)
    if m_same:
        end_candidates.append(m_same.start())
    if len(indent) > 0:
        end_re_less = re.compile(rf"^[ \t]{{0,{len(indent) - 1}}}\S", re.M)
        m_less = end_re_less.search(src, start)
        if m_less:
            end_candidates.append(m_less.start())
    end = min(end_candidates) if end_candidates else len(src)

    new_body = (
        f"{body_indent}# RASPIBLESK_LOGIN_PATCH (v0.15.16, Bug P-Followup)\n"
        f"{body_indent}# Authenticate by shelling out to blesk.passwords.sh check —\n"
        f"{body_indent}# guaranteed match with the mkpasswd-sha-512 hash format the\n"
        f"{body_indent}# set-side wrote into /mnt/hdd/app-data/passwords/a.hash.\n"
        f"{body_indent}import asyncio, shlex\n"
        f"{body_indent}from fastapi import HTTPException, status\n"
        f"{body_indent}from app.auth.auth_handler import sign_jwt\n"
        f"{body_indent}# blesk.passwords.sh check exits 0 for BOTH correct and wrong\n"
        f"{body_indent}# password (only invalid input / no hash exits 1). Authoritative\n"
        f"{body_indent}# signal is stdout containing 'correct=1'. The script runs `sudo\n"
        f"{body_indent}# cat .hash` internally, so prefix the call with sudo — provisioning\n"
        f"{body_indent}# installs /etc/sudoers.d/30_bleskapi_pwcheck granting bleskapi the\n"
        f"{body_indent}# narrow NOPASSWD right for `blesk.passwords.sh check a *`.\n"
        f"{body_indent}cmd = \"sudo -n /home/admin/config.scripts/blesk.passwords.sh check a \" + shlex.quote({pw_expr})\n"
        f"{body_indent}proc = await asyncio.create_subprocess_shell(\n"
        f"{body_indent}    cmd,\n"
        f"{body_indent}    stdout=asyncio.subprocess.PIPE,\n"
        f"{body_indent}    stderr=asyncio.subprocess.PIPE,\n"
        f"{body_indent})\n"
        f"{body_indent}stdout, _ = await proc.communicate()\n"
        f"{body_indent}if b\"correct=1\" not in stdout:\n"
        f"{body_indent}    raise HTTPException(\n"
        f"{body_indent}        status_code=status.HTTP_401_UNAUTHORIZED,\n"
        f"{body_indent}        detail=\"Password is incorrect\",\n"
        f"{body_indent}    )\n"
        f"{body_indent}return Ok(sign_jwt())\n"
        f"\n"
    )
    src = src[:m.start()] + m.group(0) + new_body + src[end:]
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print(f"# RASPIBLESK_LOGIN_PATCH: rewrote async def login() in {path}")
    sys.exit(0)

sys.stderr.write("# RASPIBLESK_LOGIN_PATCH: no `async def login(` found in any system/impl/* or service.py\n")
sys.exit(1)
PY
    if ! grep -rq 'RASPIBLESK_LOGIN_PATCH' /home/bleskapi/blitz_api/app/system/ 2>/dev/null; then
      echo "error='RASPIBLESK_LOGIN_PATCH failed — no marker in app/system/'"
      exit 1
    fi
    echo "# RASPIBLESK_LOGIN_PATCH applied + verified"
  else
    echo "# RASPIBLESK_LOGIN_PATCH already applied (skipping)"
  fi

  # ----- RASPIBLESK_LOGIN_PATCH sudoers (v0.15.16) -----
  # The patched login() shells out to `sudo -n blesk.passwords.sh check a <pw>`
  # because the script reads /mnt/hdd/app-data/passwords/a.hash (admin:admin 660)
  # via `sudo cat`. bleskapi is NOT in the admin group and has no global
  # NOPASSWD (build_sdcard.sh:923 grants NOPASSWD only to admin). Without this
  # rule the subprocess would either hang on a password prompt or fail with
  # `sudo -n` "a password is required".
  # Pattern `check a *`: sudoers matches command line args as one concatenated
  # string with `*` crossing word boundaries (see sudoers(5) "Wildcards in
  # command arguments"). Hardcoding `check a` pins this rule to password-type-A
  # checks — misuse like `check b <pw>`, `check c <pw>`, `check /etc/shadow`,
  # or a 2-arg `check <onlypw>` no longer matches and is rejected by sudo.
  SUDOERS_PW=/etc/sudoers.d/30_bleskapi_pwcheck
  cat > "${SUDOERS_PW}" <<'SUDO'
# RASPIBLESK_LOGIN_PATCH — allow bleskapi to verify password-A via blesk.passwords.sh
bleskapi ALL=(ALL) NOPASSWD: /home/admin/config.scripts/blesk.passwords.sh check a *, /home/admin/config.scripts/blitz.passwords.sh check a *
SUDO
  chown root:root "${SUDOERS_PW}"
  chmod 440 "${SUDOERS_PW}"
  if ! visudo -c -f "${SUDOERS_PW}" >/dev/null; then
    echo "error='visudo -c rejected ${SUDOERS_PW}'"
    rm -f "${SUDOERS_PW}"
    exit 1
  fi
  echo "# RASPIBLESK_LOGIN_PATCH sudoers installed: ${SUDOERS_PW}"


  # install python dependencies
  echo "# running install (Python venv & dependencies)"
  # Make sure python3-venv is installed
  if ! dpkg -s python3-venv >/dev/null 2>&1; then
     echo "# Installing python3-venv..."
     apt-get update
     apt-get install -y python3-venv
  fi
  if ! sudo -u bleskapi python3 -m venv venv; then
     echo "error='creating python venv failed'"
     exit 1
  fi
  # see https://github.com/raspiblesk/raspiblesk/issues/4169 - requires a Cython upgrade.
  sudo -u bleskapi ./venv/bin/pip install --upgrade pip
  if ! sudo -u bleskapi ./venv/bin/pip install --upgrade Cython; then
    echo "error='pip install upgrade Cython'"
  fi
  echo "# Installing dependencies from requirements.txt ..."
  sudo -u bleskapi ./venv/bin/python -m pip install --upgrade pip
  echo -e "[global]\nindex-url = https://pypi.org/simple" | sudo tee /etc/pip.conf > /dev/nul
  # install with https://www.piwheels.org/simple turned off to avoid issues with some packages
  sudo -u bleskapi env PIP_CONFIG_FILE=/dev/null PIP_INDEX_URL=https://pypi.org/simple PIP_EXTRA_INDEX_URL= ./venv/bin/pip install --no-cache-dir rich-toolkit==0.14.6
  echo -e "[global]\nindex-url = https://pypi.org/simple\nextra-index-url = https://www.piwheels.org/simple" | sudo tee /etc/pip.conf > /dev/null
  if ! sudo -u bleskapi ./venv/bin/pip install --no-cache-dir -r requirements.txt --no-deps; then
    echo "error='pip install failed'"
    exit 1
  fi

  # prepare systemd service
  echo "# Creating bleskapi systemd service..."
  echo "
[Unit]
Description=BlitzBackendAPI
Wants=network.target
After=network.target mnt-hdd.mount

[Service]
WorkingDirectory=/home/bleskapi/blitz_api
# before every start update the config with latest credentials/settings
ExecStartPre=-/home/admin/config.scripts/blesk.web.api.sh update-config
ExecStart=/home/bleskapi/blitz_api/venv/bin/python -m uvicorn app.main:app --port 11111 --host=0.0.0.0 --root-path /api
User=bleskapi
Group=bleskapi
Type=simple
Restart=always
StandardOutput=journal
StandardError=journal
RestartSec=60

# Hardening
PrivateTmp=true

[Install]
WantedBy=multi-user.target
" | tee /etc/systemd/system/bleskapi.service

  # Prepare Celery Worker systemd service
  echo "# Creating bleskapi-celery-worker systemd service..."
  echo "
[Unit]
Description=BlitzBackendAPI Celery Worker
Wants=network.target
After=network.target mnt-hdd.mount

[Service]
WorkingDirectory=/home/bleskapi/blitz_api
ExecStart=/home/bleskapi/blitz_api/venv/bin/celery -A app.celery_app worker --loglevel=info
User=bleskapi
Group=bleskapi
Type=simple
Restart=always
StandardOutput=journal
StandardError=journal
RestartSec=60

# Hardening
PrivateTmp=true

[Install]
WantedBy=multi-user.target
" | tee /etc/systemd/system/bleskapi-celery-worker.service

  # Prepare Celery Beat systemd service
  echo "# Creating bleskapi-celery-beat systemd service..."
  echo "
[Unit]
Description=BlitzBackendAPI Celery Beat Scheduler
Wants=network.target
After=network.target mnt-hdd.mount

[Service]
WorkingDirectory=/home/bleskapi/blitz_api
ExecStart=/home/bleskapi/blitz_api/venv/bin/celery -A app.celery_app beat --loglevel=info
# ExecStart=/home/bleskapi/blitz_api/venv/bin/celery -A app.celery_app beat --loglevel=info --scheduler django_celery_beat.schedulers:DatabaseScheduler
User=bleskapi
Group=bleskapi
Type=simple
Restart=always
StandardOutput=journal
StandardError=journal
RestartSec=60

# Hardening
PrivateTmp=true

[Install]
WantedBy=multi-user.target
" | tee /etc/systemd/system/bleskapi-celery-beat.service

  chown -R bleskapi:bleskapi /home/bleskapi/blitz_api

  # blitz_api's raspiblitz platform module (loaded because BAPI_PLATFORM=raspiblitz
  # in update-config — see comment there for the masquerade rationale) calls
  # /home/admin/config.scripts/blitz.*.sh by hardcoded path. We renamed every
  # blitz.*.sh to blesk.*.sh in this fork, so without these aliases blitz_api
  # crashes on startup with "required file does not exist: blitz.debug.sh".
  # Idempotent: ln -sf is safe to re-run.
  for s in debug shutdown migration backupdevice passwords systemd; do
    if [ -f "/home/admin/config.scripts/blesk.${s}.sh" ]; then
      ln -sfn "blesk.${s}.sh" "/home/admin/config.scripts/blitz.${s}.sh"
    fi
  done

  # Enable and start services
  echo "# Enabling and starting services..."
  systemctl enable bleskapi bleskapi-celery-worker bleskapi-celery-beat
  systemctl start bleskapi bleskapi-celery-worker bleskapi-celery-beat

  # bleskapi listens on 11111; clearnet access goes through nginx :80 /api
  # reverse-proxy. Scope the firewall opening to localhost + LAN so the dev
  # port isn't exposed Anywhere. (v0.15.11 had this Anywhere — public.)
  ufw allow from 127.0.0.1 to any port 11111 comment 'bleskapi dev localhost'
  ufw allow from 10.0.0.0/8 to any port 11111 comment 'bleskapi dev LAN'
  ufw allow from 172.16.0.0/12 to any port 11111 comment 'bleskapi dev LAN'
  ufw allow from 192.168.0.0/16 to any port 11111 comment 'bleskapi dev LAN'

  source <(/home/admin/_cache.sh export internet_localip)

  # install info
  echo "# The API is now running on port 11111 & doc available under:"
  echo "# http://${internet_localip}/api/docs"
  echo "# Celery worker and beat services are also running."
  echo "# Check status:"
  echo "#   sudo systemctl status bleskapi"
  echo "#   sudo systemctl status bleskapi-celery-worker"
  echo "#   sudo systemctl status bleskapi-celery-beat"
  echo "# Check logs:"
  echo "#   sudo journalctl -f -u bleskapi"
  echo "#   sudo journalctl -f -u bleskapi-celery-worker"
  echo "#   sudo journalctl -f -u bleskapi-celery-beat"

  # setting value in raspi blitz config
  /home/admin/config.scripts/blesk.conf.sh set bleskapi "on"
  /home/admin/config.scripts/blesk.conf.sh set bleskapi "on" /home/admin/raspiblesk.info

  exit 0
fi

###################
# UPDATE CODE
###################
if [ "$1" = "update-code" ]; then

  # the branch on which to get the latest code from
  if [ "$2" != "" ]; then
    currentBranch="$2"
  fi

  apiActive=$(ls /etc/systemd/system/bleskapi.service 2>/dev/null | grep -c bleskapi.service)
  if [ "${apiActive}" != "0" ]; then
    echo "# Update Web API CODE for API and Celery Services"

    echo "# Stopping services..."
    systemctl stop bleskapi bleskapi-celery-worker bleskapi-celery-beat

    sudo chown -R bleskapi:bleskapi /home/bleskapi/blitz_api
    cd /home/bleskapi/blitz_api || exit 1
    if [ "$currentBranch" == "" ]; then
      currentBranch=$(sudo -u bleskapi git rev-parse --abbrev-ref HEAD)
    fi
    echo "# Updating local repo (branch: ${currentBranch})..."
    oldCommit=$(sudo -u bleskapi git rev-parse HEAD)
    sudo -u bleskapi git fetch
    if sudo -u bleskapi git show-ref --verify --quiet refs/remotes/origin/${currentBranch}; then
        sudo -u bleskapi git reset --hard origin/${currentBranch}
    else
        echo "# ERROR: Branch 'origin/${currentBranch}' not found in remote. Cannot update."
        echo "# Restarting services with existing code..."
        systemctl start bleskapi bleskapi-celery-worker bleskapi-celery-beat
        exit 1
    fi

    newCommit=$(sudo -u bleskapi git rev-parse HEAD)
    if [ "${oldCommit}" != "${newCommit}" ]; then
      echo "# Code changed, updating dependencies..."
      sudo -u bleskapi ./venv/bin/pip install --upgrade pip
      if ! sudo -u bleskapi ./venv/bin/pip install -r requirements.txt --no-deps; then
         echo "# WARNING: pip install failed during update. Services might not start correctly."
      fi
    else
      echo "# no code changes"
    fi

    echo "# Restarting services..."
    systemctl start bleskapi bleskapi-celery-worker bleskapi-celery-beat

    echo "# BRANCH ---> ${currentBranch}"
    echo "# old commit -> ${oldCommit}"
    echo "# new commit -> ${newCommit}"
    echo "# bleskapi, celery-worker, and celery-beat services updated and restarted."
    exit 0
  else
    echo "# bleskapi not active"
    exit 1
  fi
fi

###################
# OFF / UNINSTALL
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# UNINSTALL Web API & Celery Services"
  echo "# Stopping services..."
  systemctl stop bleskapi bleskapi-celery-worker bleskapi-celery-beat 2>/dev/null
  echo "# Disabling services..."
  systemctl disable bleskapi bleskapi-celery-worker bleskapi-celery-beat 2>/dev/null
  echo "# Removing service files..."
  rm /etc/systemd/system/bleskapi.service 2>/dev/null
  rm /etc/systemd/system/bleskapi-celery-worker.service 2>/dev/null
  rm /etc/systemd/system/bleskapi-celery-beat.service 2>/dev/null
  systemctl daemon-reload # To make systemd forget about the removed services
  echo "# Removing user and home directory..."
  userdel -rf bleskapi
  # clean old source
  rm -r /root/blitz_api 2>/dev/null
  ufw delete allow 11111 2>/dev/null

  # setting value in raspi blitz config
  /home/admin/config.scripts/blesk.conf.sh set bleskapi "off"
  /home/admin/config.scripts/blesk.conf.sh set bleskapi "off" /home/admin/raspiblesk.info

  echo "# Web API & Celery services uninstalled."
  exit 0

fi

# Fallback for unknown commands
echo "error='unknown command'"
exit 1
