#!/bin/bash

# https://github.com/lnbits/lnbits

# https://github.com/lnbits/lnbits/releases
tag="v1.2.1"
VERSION="${tag}"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Config script to switch LNbits on or off."
  echo "Installs the version ${VERSION} by default."
  echo "Usage:"
  echo "bonus.lnbits.sh [install|uninstall] [?GITHUBUSER] [?BRANCH|?TAG]"
  echo "bonus.lnbits.sh on [lnd|tlnd|slnd|cl|tcl|scl]"
  echo "bonus.lnbits.sh switch [lnd|tlnd|slnd|cl|tcl|scl]"
  echo "bonus.lnbits.sh off <--keep-data|--delete-data>"
  echo "bonus.lnbits.sh status"
  echo "bonus.lnbits.sh menu"
  echo "bonus.lnbits.sh prestart"
  echo "bonus.lnbits.sh repo [githubuser] [branch]"
  echo "bonus.lnbits.sh sync"
  echo "bonus.lnbits.sh backup"
  echo "bonus.lnbits.sh restore [?FILE]"
  echo "bonus.lnbits.sh migrate"
  exit 1
fi

echo "# Running: 'bonus.lnbits.sh $*'"
# v0.15.20 (Bug F1): conf is only created during _provision_.sh, after
# bonus.lnbits.sh install has already run from build_sdcard.sh. The
# unconditional source produced "Datei oder Verzeichnis nicht gefunden"
# in the build log. Install path does not read any conf vars so the
# guard is safe — activation paths (on/switch/off) run later when the
# conf file exists.
if [ -f /mnt/hdd/app-data/raspiblesk.conf ]; then
  source /mnt/hdd/app-data/raspiblesk.conf
fi

lnbitsDataDir="/mnt/hdd/app-data/LNBits/data"
lnbitsConfig="${lnbitsDataDir}/.env"

LNBITS_DB_PASS_FILE="/mnt/hdd/app-data/LNBits/db_password.conf"
LNBITS_DB_PASS_RESET_MARKER="/mnt/hdd/app-data/LNBits/.v0166-pw-reset.done"

loadOrGenerateLNBitsDBPassword() {
  # Bug Q (v0.15.16): pre-v0166 passwords could contain URL-unsafe chars
  # (+ = < > ? . - and others) that broke asyncpg's URL-parser in
  # LNBITS_DATABASE_URL. lnbits crashed at startup with InvalidPasswordError
  # for "lnbits_user" even though the user existed in postgres. Invalidate
  # any pre-v0166 password file exactly once so the regenerate path below
  # produces a URL-safe alphanumeric replacement and the postgres user gets
  # recreated with the new password on the next postgresConfig run.
  # Bug Y (v0.15.19): this function is called from _provision_.sh:554 via
  # `sudo -u admin bonus.lnbits.sh on`, but /mnt/hdd/app-data/LNBits is owned
  # lnbits:lnbits mode 0755 — admin has no write permission. Every raw
  # rm/mkdir/touch/echo > $PASS_FILE silent-failed, neither marker nor
  # password file was ever persisted, and each call re-rolled a fresh
  # LNBITS_DB_PASS. postgresConfig (Z.91/97) then created the postgres user
  # with pass A, the .env write (Z.939) used pass B, and lnbits crashed at
  # startup with InvalidPasswordError. All filesystem ops here now run via
  # sudo, and `source` is replaced by `sudo grep | cut` because the password
  # file is chmod 600 owned by lnbits (admin cannot read it directly).
  if ! sudo test -f "${LNBITS_DB_PASS_RESET_MARKER}"; then
    if sudo test -f "${LNBITS_DB_PASS_FILE}"; then
      echo "# Bug Q reset: invalidating pre-v0166 LNbits DB password (URL-unsafe charset)"
      sudo rm -f "${LNBITS_DB_PASS_FILE}"
      if sudo -u postgres psql -tAc "SELECT 1" >/dev/null 2>&1; then
        sudo -u postgres psql -c "drop database if exists lnbits_db;" >/dev/null 2>&1 || true
        sudo -u postgres psql -c "drop user if exists lnbits_user;" >/dev/null 2>&1 || true
      fi
    fi
    sudo mkdir -p "$(dirname "${LNBITS_DB_PASS_RESET_MARKER}")"
    sudo touch "${LNBITS_DB_PASS_RESET_MARKER}"
  fi

  if sudo test -f "${LNBITS_DB_PASS_FILE}"; then
    LNBITS_DB_PASS=$(sudo grep -E '^LNBITS_DB_PASS=' "${LNBITS_DB_PASS_FILE}" | cut -d= -f2-)
  else
    sudo mkdir -p "$(dirname ${LNBITS_DB_PASS_FILE})"
    # Bug Q (v0.15.16): URL-safe alphanumeric-only charset. 32 chars
    # × log2(62) ≈ 190 bits entropy. Previous charset included +=<>?.-
    # which broke postgres:// URL parsing in asyncpg.
    LNBITS_DB_PASS=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)
    echo "LNBITS_DB_PASS=${LNBITS_DB_PASS}" | sudo tee "${LNBITS_DB_PASS_FILE}" >/dev/null
    sudo chmod 600 "${LNBITS_DB_PASS_FILE}"
    sudo chown lnbits:lnbits "${LNBITS_DB_PASS_FILE}" 2>/dev/null || true
  fi
}

# use full path — lnbits is a system user and /usr/local/bin may not be in PATH
POETRY_BIN="/usr/local/bin/poetry"

function postgresConfig() {
  loadOrGenerateLNBitsDBPassword

  sudo /home/admin/config.scripts/bonus.postgresql.sh on || exit 1
  echo "# Generate the database lnbits_db"

  # migrate clean up
  source <(/home/admin/_cache.sh get LNBitsMigrate)
  if [ "${LNBitsMigrate}" == "on" ]; then
    echo "# LNBitsMigrate=on --> Cleaning old lnbits_db & lnbits_user"
    sudo -u postgres psql -c "drop database lnbits_db;"
    sudo -u postgres psql -c "drop user lnbits_user;"
  fi
  # create database for new installations and keep old
  sudo -u postgres psql -c "create database lnbits_db;" 2>/dev/null
  sudo -u postgres psql -c "create user lnbits_user with encrypted password '${LNBITS_DB_PASS}';" 2>/dev/null
  # Bug Q (v0.15.16) hardening: if lnbits_user already existed (rerun after partial
  # install or manually-deleted db_password.conf), CREATE USER silently no-ops and
  # the db user keeps its stale password — but db_password.conf now has a fresh
  # one, so LNBITS_DATABASE_URL fails to connect. ALTER USER realigns both sides
  # to the password currently in db_password.conf on every postgresConfig call.
  sudo -u postgres psql -c "alter user lnbits_user with encrypted password '${LNBITS_DB_PASS}';" 2>/dev/null
  sudo -u postgres psql -c "grant all privileges on database lnbits_db to lnbits_user;" 2>/dev/null

  # v0.15.20 (Bug Y2): PostgreSQL 15+ revoked the historical PUBLIC.CREATE
  # privilege on the `public` schema — only the schema owner (default:
  # `postgres`) can `CREATE TABLE` in it. lnbits_user holds DATABASE-level
  # ALL PRIVILEGES (line above), but database-level grants are independent
  # of schema-level grants in PG 15+. LNbits' first migration tries
  # `CREATE TABLE IF NOT EXISTS dbversions(...)` in `public` and asyncpg
  # raises `InsufficientPrivilegeError: permission denied for schema public`,
  # aborting `Application startup`, so the LNbits worker never binds :5000
  # and nginx returns 502 Bad Gateway on the LNbits frontend. Two-pronged
  # fix: transfer schema ownership AND explicitly grant ALL — either alone
  # would suffice but together they survive a PostgreSQL-side reset of
  # default ACLs across major-version upgrades. Run as the postgres
  # superuser, scoped to the lnbits_db (so `public` resolves to the right
  # per-database schema).
  sudo -u postgres psql -d lnbits_db -c "alter schema public owner to lnbits_user;" 2>/dev/null
  sudo -u postgres psql -d lnbits_db -c "grant all on schema public to lnbits_user;" 2>/dev/null

  # check
  check=$(sudo -u postgres psql -c "SELECT datname FROM pg_database;" | grep lnbits_db)
  if [ "$check" = "" ]; then
    echo "# postgresConfig failed -> SELECT datname FROM pg_database;"
    exit 1
  else
    echo "# Setup PostgreSQL successful, new database found: $check"
  fi

  /home/admin/config.scripts/blesk.conf.sh set LNBitsDB "PostgreSQL"
}

function migrateMsg() {
  source <(/home/admin/_cache.sh get LNBitsDB)
  if [ "${LNBitsDB}" == "PostgreSQL" ]; then
    if [ -e /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar ]; then
      echo "SUCCESS - A backup file was found. The migrate progress will revert automatically on failure."
      echo "For yet unknown reasons, this could be done manually with unpacking the SQLite backup file."
      echo
      echo "/home/admin/config.scripts/bonus.lnbits.sh migrate revert"
      echo
      echo "********************************************************"
      echo "*                                                      *"
      echo "* Revert: /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar *"
      echo "*                                                      *"
      echo "********************************************************"
      echo
    else
      echo "You dont have any migration backup files!"
    fi
  else
    echo "ABORT - Your LNBits is still running on old SQLite database."
    echo "Check for errors, '.dump' and fix your database manually and try again."
  fi
}

function revertMigration() {
  source <(/home/admin/_cache.sh get LNBitsMigrate)
  if [ "${LNBitsMigrate}" == "on" ]; then
    echo "# Revert migration, restore SQLite..."
    sudo systemctl stop lnbits

    # check current backup
    if [ -e /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar ]; then
      echo "# Unpack Backup"
      cd /mnt/hdd/app-data/
      sudo rm -R /mnt/hdd/app-data/LNBits
      sudo tar -xf /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar
      sudo chown lnbits:lnbits -R /mnt/hdd/app-data/LNBits
    else
      echo "# No backup file found!"
    fi

    # update config
    echo "# Configure config .env"
    sudo sed -i "/^LNBITS_DATABASE_URL=/d" $lnbitsConfig

    # clean up
    sudo sed -i "/^LNBITS_DATA_FOLDER=/d" $lnbitsConfig
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits' >> ${lnbitsConfig}"

    # start service
    echo "# Start LNBits"
    sudo systemctl start lnbits

    # set blitz config
    /home/admin/config.scripts/blesk.conf.sh set LNBitsMigrate "off"
    /home/admin/config.scripts/blesk.conf.sh set LNBitsDB "SQLite"

    echo "# OK revert migration done"
  else
    echo "# No migration started yet, nothing to do."
  fi
}

# show info menu
if [ "$1" = "menu" ]; then

  # get LNbits status info
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.lnbits.sh status)

  # display possible problems with IP2TOR setup
  if [ ${#ip2torWarn} -gt 0 ]; then
    whiptail --title " Warning " \
      --yes-button "Back" \
      --no-button "Continue Anyway" \
      --yesno "Your IP2TOR+LetsEncrypt may have problems:\n${ip2torWarn}\n\nCheck if locally responding: https://${localIP}:${httpsPort}\n\nCheck if service is reachable over Tor:\n${toraddress}" 14 72
    if [ "$?" != "1" ]; then
      exit 0
    fi
  fi

  # add info on funding source
  fundinginfo=""
  if [ "${LNBitsFunding}" == "lnd" ] || [ "${LNBitsFunding}" == "tlnd" ] || [ "${LNBitsFunding}" == "slnd" ]; then
    fundinginfo="on LND "
  elif [ "${LNBitsFunding}" == "cl" ] || [ "${LNBitsFunding}" == "tcl" ] || [ "${LNBitsFunding}" == "scl" ]; then
    fundinginfo="on CLN "
  fi

  text="https://${localIP}:${httpsPort}"

  if [ ${#publicDomain} -gt 0 ]; then
    text="${text}
Public Domain: https://${publicDomain}:${httpsPort}
port forwarding on router needs to be active & may change port"
  fi

  text="${text}\n
You need to accept self-signed HTTPS cert with SHA1 Fingerprint:
${sslFingerprintIP}"

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    sudo /home/admin/config.scripts/blesk.display.sh qr "${toraddress}"
    text="${text}\n
TOR Browser Hidden Service address (QR see LCD):
${toraddress}"
  fi

  whiptail --title " LNbits ${fundinginfo}" --yes-button "OK" --no-button "OPTIONS" --yesno "${text}" 15 78
  result=$?
  sudo /home/admin/config.scripts/blesk.display.sh hide
  echo "option (${result}) - please wait ..."

  # exit when user presses OK to close menu
  if [ ${result} -eq 0 ]; then
    exit 0
  fi

  # LNbits OPTIONS menu
  OPTIONS=()

  # IP2TOR options
  if [ "${ip2torDomain}" != "" ]; then
    # IP2TOR+LetsEncrypt active - offer cancel
    OPTIONS+=(IP2TOR-OFF "Cancel IP2Tor Subscription for LNbits")
  elif [ "${ip2torIP}" != "" ]; then
    # just IP2TOR active - offer cancel or Lets Encrypt
    OPTIONS+=(HTTPS-ON "Add free HTTPS-Certificate for LNbits")
    OPTIONS+=(IP2TOR-OFF "Cancel IP2Tor Subscription for LNbits")
  fi

  # Change Funding Source options (only if available)
  if [ "${LNBitsFunding}" == "lnd" ] && [ "${cl}" == "on" ]; then
    OPTIONS+=(SWITCH-CL "Switch: Use CLN as funding source")
  elif [ "${LNBitsFunding}" == "cl" ] && [ "${lnd}" == "on" ]; then
    OPTIONS+=(SWITCH-LND "Switch: Use LND as funding source")
  fi

  # Backup database
  OPTIONS+=(BACKUP "Backup database")
  if [ -d /mnt/hdd/app-data/backup ]; then
    OPTIONS+=(RESTORE "Restore database")
  fi

  # Migrate SQLite to PostgreSQL
  if [ -e /mnt/hdd/app-data/LNBits/database.sqlite3 ]; then
    OPTIONS+=(MIGRATE-DB "Migrate SQLite to PostgreSQL database")
  fi

  # Admin UI
  activatedAdminUI=$(sudo grep -c "LNBITS_ADMIN_UI=true" $lnbitsConfig)
  if [ ${activatedAdminUI} -eq 0 ]; then
    OPTIONS+=(ADMINUI "Activate 'Admin UI'")
  else
    OPTIONS+=(ADMINUI "Deactivate 'Admin UI'")
  fi

  # Allow New Accounts (only if AdminUI is OFF)
  allowNewAccountsFalse=$(sudo grep -c "LNBITS_ALLOW_NEW_ACCOUNTS=false" $lnbitsConfig)
  if [ ${activatedAdminUI} -eq 0 ]; then
    if [ ${allowNewAccountsFalse} -eq 0 ]; then
      OPTIONS+=(NEWACCOUNTS "Disable New Accounts")
    else
      OPTIONS+=(NEWACCOUNTS "Enable New Accounts")
    fi
  fi

  WIDTH=66
  CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
  HEIGHT=$((CHOICE_HEIGHT + 7))
  CHOICE=$(dialog --clear \
    --title " LNbits - Options" \
    --ok-label "Select" \
    --cancel-label "Back" \
    --menu "Choose one of the following options:" \
    $HEIGHT $WIDTH $CHOICE_HEIGHT \
    "${OPTIONS[@]}" \
    2>&1 >/dev/tty)

  case $CHOICE in
  HTTPS-ON)
    python /home/admin/config.scripts/blesk.subscriptions.letsencrypt.py create-ssh-dialog
    exit 0
    ;;
  SWITCH-CL)
    clear
    /home/admin/config.scripts/bonus.lnbits.sh switch cl
    echo "Restarting LNbits ..."
    sudo systemctl restart lnbits
    echo
    echo "OK new funding source for LNbits active."
    echo "PRESS ENTER to continue"
    read key
    exit 0
    ;;
  SWITCH-LND)
    clear
    /home/admin/config.scripts/bonus.lnbits.sh switch lnd
    echo "Restarting LNbits ..."
    sudo systemctl restart lnbits
    echo
    echo "OK new funding source for LNbits active."
    echo "PRESS ENTER to continue"
    read key
    exit 0
    ;;
  BACKUP)
    clear
    /home/admin/config.scripts/bonus.lnbits.sh backup
    echo
    echo "Backup done"
    echo "PRESS ENTER to continue"
    read key
    exit 0
    ;;
  ADMINUI)
    clear
    echo
    if [ ${activatedAdminUI} -eq 0 ]; then
      echo "Activate Admin UI"
      sudo sed -i "/^LNBITS_ADMIN_UI=/d" $lnbitsConfig
      sudo bash -c "echo 'LNBITS_ADMIN_UI=true' >> ${lnbitsConfig}"
    else
      echo "Deactivate Admin UI"
      sudo sed -i "/^LNBITS_ADMIN_UI=/d" $lnbitsConfig
      sudo bash -c "echo 'LNBITS_ADMIN_UI=false' >> ${lnbitsConfig}"
    fi
    echo "Restarting LNbits to activate new setting ..."
    sudo systemctl restart lnbits
    echo "PRESS ENTER to continue"
    read key
    exit 0
    ;;
  NEWACCOUNTS)
    clear
    echo
    if [ ${allowNewAccountsFalse} -eq 0 ]; then
      echo "Disable New Accounts"
      sudo sed -i "/^LNBITS_ALLOW_NEW_ACCOUNTS=/d" $lnbitsConfig
      sudo sed -i "/^# LNBITS_ALLOW_NEW_ACCOUNTS=/d" $lnbitsConfig
      sudo bash -c "echo 'LNBITS_ALLOW_NEW_ACCOUNTS=false' >> ${lnbitsConfig}"
    else
      echo "Enable New Accounts"
      sudo sed -i "/^LNBITS_ALLOW_NEW_ACCOUNTS=/d" $lnbitsConfig
      sudo sed -i "/^# LNBITS_ALLOW_NEW_ACCOUNTS=/d" $lnbitsConfig
      sudo bash -c "echo 'LNBITS_ALLOW_NEW_ACCOUNTS=true' >> ${lnbitsConfig}"
    fi
    echo "Restarting LNbits to activate new setting ..."
    sudo systemctl restart lnbits
    echo "PRESS ENTER to continue"
    read key
    exit 0
    ;;
  RESTORE)
    clear
    # check if backup exist
    source <(/home/admin/_cache.sh get LNBitsDB)
    if [ "${LNBitsDB}" == "PostgreSQL" ]; then
      backup_target="/mnt/hdd/app-data/backup/lnbits_db"
      backup_file=$(ls -t $backup_target/*.sql | head -n1)
    else
      backup_target="/mnt/hdd/app-data/backup/lnbits_sqlite"
      backup_file=$(ls -t $backup_target/*.tar | head -n1)
    fi
    if [ "$backup_file" = "" ]; then
      echo "ABORT - No Backup found to restore from"
      exit 0
    else
      # build dialog to choose backup file from menu
      OPTIONS_RESTORE=()

      counter=0
      cd $backup_target
      for f in $(find *.* -maxdepth 1 -type f); do
        [[ -f "$f" ]] || continue
        counter=$(($counter + 1))
        OPTIONS_RESTORE+=($counter "$f")
      done

      WIDTH_RESTORE=66
      CHOICE_HEIGHT_RESTORE=$(("${#OPTIONS_RESTORE[@]}/2+1"))
      HEIGHT_RESTORE=$((CHOICE_HEIGHT_RESTORE + 7))
      CHOICE_RESTORE=$(dialog --clear \
        --title " LNbits - Backup restore" \
        --ok-label "Select" \
        --cancel-label "Back" \
        --menu "Choose one of the following backups:" \
        $HEIGHT_RESTORE $WIDTH_RESTORE $CHOICE_HEIGHT_RESTORE \
        "${OPTIONS_RESTORE[@]}" \
        2>&1 >/dev/tty)

      # start restore with selected backup
      clear
      if [ "$CHOICE_RESTORE" != "" ]; then
        backup_file=${backup_target}/${OPTIONS_RESTORE[$(($CHOICE_RESTORE * 2 - 1))]}
        /home/admin/config.scripts/bonus.lnbits.sh restore "${backup_file}"
        echo
        echo "Restore done"
        echo "PRESS ENTER to continue"
        read key
      fi
      exit 0
    fi
    ;;
  MIGRATE-DB)
    clear
    dialog --title "MIGRATE LNBITS" --yesno "
Do you want to proceed the migration?

Try to migrate your LNBits SQLite database to PostgreSQL.

This can fail for unknown circumstances. Revert of this process is possible afterwards, a backup will be saved.
            " 12 65
    if [ $? -eq 0 ]; then
      clear
      /home/admin/config.scripts/bonus.lnbits.sh migrate
      echo
      migrateMsg
      echo
      echo "OK please test your LNBits installation."
      echo "PRESS ENTER to continue"
      read key
    fi
    exit 0
    ;;
  *)
    clear
    exit 0
    ;;
  esac

  exit 0
fi

# status
if [ "$1" = "status" ]; then

  echo "version='${VERSION}'"

    fatpack=$(compgen -u | grep -c lnbits)
    echo "fatpack=${fatpack}"

  if [ "${LNBits}" = "on" ]; then
    echo "installed=1"

    localIP=$(hostname -I | awk '{print $1}')
    echo "localIP='${localIP}'"
    echo "httpPort='5000'"
    echo "httpsPort='5443'"
    echo "httpsForced='1'"
    echo "httpsSelfsigned='1'" # TODO: change later if IP2Tor+LetsEncrypt is active
    echo "publicIP='${publicIP}'"

    # auth method is web login
    echo "authMethod='userdefined'"

    # check funding source
    if [ "${LNBitsFunding}" == "" ]; then
      LNBitsFunding="lnd"
    fi
    echo "LNBitsFunding='${LNBitsFunding}'"

    sslFingerprintIP=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout 2>/dev/null | cut -d"=" -f2)
    echo "sslFingerprintIP='${sslFingerprintIP}'"

    toraddress=$(sudo cat /mnt/hdd/app-data/tor/lnbits/hostname 2>/dev/null)
    echo "toraddress='${toraddress}'"

    sslFingerprintTOR=$(openssl x509 -in /mnt/hdd/app-data/nginx/tor_tls.cert -fingerprint -noout 2>/dev/null | cut -d"=" -f2)
    echo "sslFingerprintTOR='${sslFingerprintTOR}'"

    # check for error
    isDead=$(sudo systemctl status lnbits | grep -c 'inactive (dead)')
    if [ ${isDead} -eq 1 ]; then
      echo "error='Service Failed'"
      exit 0
    fi

  else
    echo "installed=0"
  fi
  exit 0
fi

##########################
# PRESTART
# - will be called as prestart by systemd service (as user lnbits)
#########################

if [ "$1" = "prestart" ]; then

  # users need to be `lnbits` so that it can be run by systemd as prestart (no SUDO available)
  if [ "$USER" != "lnbits" ]; then
    echo "# FAIL: run as user lnbits"
    exit 1
  fi

  # get if its for lnd or cl service
  echo "## lnbits.service PRESTART CONFIG"
  echo "# --> ${lnbitsConfig}"

  # set values based in funding source in raspiblesk config
  # portprefix is "" |  1 | 3
  LNBitsNetwork="glcoin"
  LNBitsChain=""
  LNBitsLightning=""
  if [ "${LNBitsFunding}" == "" ] || [ "${LNBitsFunding}" == "lnd" ]; then
    LNBitsFunding="lnd"
    LNBitsLightning="lnd"
    LNBitsChain="main"
    portprefix=""
  elif [ "${LNBitsFunding}" == "tlnd" ]; then
    LNBitsLightning="lnd"
    LNBitsChain="test"
    portprefix="1"
  elif [ "${LNBitsFunding}" == "slnd" ]; then
    LNBitsLightning="lnd"
    LNBitsChain="sig"
    portprefix="3"
  elif [ "${LNBitsFunding}" == "cl" ]; then
    LNBitsLightning="cl"
    LNBitsChain="main"
  elif [ "${LNBitsFunding}" == "tcl" ]; then
    LNBitsLightning="cl"
    LNBitsChain="test"
  elif [ "${LNBitsFunding}" == "scl" ]; then
    LNBitsLightning="cl"
    LNBitsChain="sig"
  else
    echo "# FAIL: Unknown LNBitsFunding=${LNBitsFunding}"
    exit 1
  fi

  echo "# LNBitsFunding(${LNBitsFunding}) --> network(${LNBitsNetwork}) chain(${LNBitsChain}) lightning(${LNBitsLightning})"

  # set lnd config
  if [ "${LNBitsLightning}" == "lnd" ]; then

    echo "# setting lnd config fresh ..."

    # check if lnbits user has read access on lnd data files
    checkReadAccess=$(cat /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/admin.macaroon | grep -c "lnd")
    if [ "${checkReadAccess}" != "1" ]; then
      echo "# FAIL: missing lnd data in '/mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/admin.macaroon' or missing access rights for lnbits user"
      exit 1
    fi

    echo "# Updating LND TLS & macaroon data fresh for LNbits config ..."

    # set tls.cert path (use | as separator to avoid escaping file path slashes)
    sed -i "s|^LND_REST_CERT=.*|LND_REST_CERT=/mnt/hdd/app-data/lnd/tls.cert|g" $lnbitsConfig
    # set macaroon  path info in .env - USING HEX IMPORT
    chmod 600 $lnbitsConfig
    macaroonAdminHex=$(xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/admin.macaroon)
    macaroonInvoiceHex=$(xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/invoice.macaroon)
    macaroonReadHex=$(xxd -ps -u -c 1000 /mnt/hdd/app-data/lnd/data/chain/${LNBitsNetwork}/${LNBitsChain}net/readonly.macaroon)
    sed -i "s/^LND_REST_ADMIN_MACAROON=.*/LND_REST_ADMIN_MACAROON=${macaroonAdminHex}/g" $lnbitsConfig
    sed -i "s/^LND_REST_INVOICE_MACAROON=.*/LND_REST_INVOICE_MACAROON=${macaroonInvoiceHex}/g" $lnbitsConfig
    sed -i "s/^LND_REST_READ_MACAROON=.*/LND_REST_READ_MACAROON=${macaroonReadHex}/g" $lnbitsConfig
    # set the REST endpoint (use | as separator to avoid escaping slashes)
    sed -i "s|^LND_REST_ENDPOINT=.*|LND_REST_ENDPOINT=https://127.0.0.1:${portprefix}8080|g" $lnbitsConfig

    echo "# Checking if LND REST API is responding ..."
    count=0
    while ! curl -s -k --head --request GET "https://127.0.0.1:${portprefix}8080/v1/getinfo" > /dev/null; do
      count=$((count + 1))
      if [ $count -gt 600 ]; then
        echo "# FAIL: LND REST API did not respond after 10 minutes."
        exit 1
      fi
      echo "# Waiting for LND REST API... (${count}s/600s)"
      sleep 1
    done
    echo "# OK: LND REST API is responding."

  elif [ "${LNBitsLightning}" == "cl" ]; then

    isUsingCL=$(cat $lnbitsConfig | grep -c "LNBITS_BACKEND_WALLET_CLASS=CLightningWallet")
    if [ "${isUsingCL}" != "1" ]; then
      echo "# FAIL: ${lnbitsConfig} not set to CLN"
      exit 1
    fi

    CLIGHTNING_RPC=$(grep '^CLIGHTNING_RPC=' ${lnbitsConfig} | cut -d'=' -f2-)
    while ! lightning-cli --rpc-file=${CLIGHTNING_RPC} getinfo &> /dev/null; do
      echo "Waiting for CLN RPC socket to become available..."
      sleep 1
    done

    echo "# everything looks OK for lnbits config on CLN on ${LNBitsChain}net"

  else
    echo "# FAIL: missing or not supported LNBitsLightning=${LNBitsLightning}"
    exit 1
  fi

  # protect the admin user id if exists
  chmod 640 /mnt/hdd/app-data/LNBits/data/.super_user 2>/dev/null

  echo "# OK: prestart finished"
  exit 0 # exit with clean code
fi

if [ "$1" = "repo" ]; then

  # get github parameters
  githubUser="$2"
  if [ ${#githubUser} -eq 0 ]; then
    echo "echo='missing parameter'"
    exit 1
  fi
  githubBranch="$3"
  if [ ${#githubBranch} -eq 0 ]; then
    githubBranch="main"
  fi

  # check if repo exists
  githubRepo="https://github.com/${githubUser}/lnbits"

  httpcode=$(curl -s -o /dev/null -w "%{http_code}" ${githubRepo})
  if [ "${httpcode}" != "200" ]; then
    echo "# tested github repo: ${githubRepo}"
    echo "error='repo for user does not exist'"
    exit 1
  fi

  # fix permissions
  sudo chown -R lnbits:lnbits /home/lnbits/lnbits
  # change origin repo of lnbits code
  echo "# changing LNbits github repo(${githubUser}) branch(${githubBranch})"
  cd /home/lnbits/lnbits || exit 1
  sudo -u lnbits git remote remove origin
  sudo -u lnbits git remote add origin ${githubRepo}
  sudo -u lnbits git fetch
  sudo -u lnbits git checkout ${githubBranch}
  sudo -u lnbits git branch --set-upstream-to=origin/${githubBranch} ${githubBranch}

fi

if [ "$1" = "sync" ] || [ "$1" = "repo" ]; then
  echo "# pull all changes from github repo"
  # fix permissions
  sudo chown -R lnbits:lnbits /home/lnbits/lnbits
  # output basic info
  cd /home/lnbits/lnbits || exit 1
  sudo -u lnbits git remote -v
  sudo -u lnbits git branch -v
  # pull latest code
  sudo -u lnbits git pull

  echo "# check if poetry in installed, if not install it"
  if ! test -x "${POETRY_BIN}"; then
    echo "# install poetry"
    sudo pip3 config set global.break-system-packages true
    sudo pip3 install --upgrade pip
    sudo pip3 install poetry
  fi

  echo "# install"
  sudo -u lnbits "${POETRY_BIN}" install

  echo "# make sure the default virtualenv is used"
  sudo apt-get remove -y python3-virtualenv 2>/dev/null
  sudo pip uninstall -y virtualenv 2>/dev/null
  sudo apt-get install -y python3-virtualenv

  echo "# restart lnbits service"
  sudo systemctl restart lnbits
  echo "# server is restarting ... maybe takes some seconds until available"
  exit 0
fi

# stop service
sudo systemctl stop lnbits 2>/dev/null

# install (code & compile)
if [ "$1" = "install" ]; then

  # check if already installed
  if compgen -u | grep -w lnbits; then
    echo "result='already installed'"
    exit 0
  fi

  # get optional github parameter
  githubUser="lnbits"
  if [ "$2" != "" ]; then
    githubUser="$2"
  fi
  if [ "$3" != "" ]; then
    tag="$3"
  fi

  echo "# *** INSTALL LNBITS ***"
  echo "# githubUser=$githubUser tag=$tag"

  # make sure dependencies are installed
  sudo apt-get install -y pkg-config build-essential python3-dev libsecp256k1-dev libffi-dev libgmp-dev || true
  # Try to install python3.12 (preferred LNbits target). On Debian Trixie
  # this is NOT in the default repo; the install will fail and we fall back
  # to python3.13 via the pyproject.toml widening patch above.
  sudo apt-get update -qq || true
  sudo apt-get install -y python3.12 python3.12-venv python3.12-dev 2>/dev/null || \
    echo "# INFO: python3.12 not available via apt (expected on Debian Trixie) — will use python3.13 via patched pyproject.toml"

  # add lnbits user
  echo "*** Add the 'lnbits' user ***"
  sudo adduser --system --group --home /home/lnbits lnbits
  # add user to group glcoin
  sudo usermod -a -G glcoin lnbits

  # install from GitHub
  echo "# get the github code user(${githubUser}) branch(${tag})"
  sudo rm -r /home/lnbits/lnbits 2>/dev/null
  cd /home/lnbits || exit 1
  sudo -u lnbits git clone https://github.com/${githubUser}/lnbits lnbits
  cd /home/lnbits/lnbits || exit 1
  sudo -u lnbits git checkout ${tag} || exit 1

  # Debian Trixie ships python3.13 but LNbits' upstream pyproject.toml only
  # allows 3.10-3.12, causing poetry to fail at runtime ("not supported by
  # the project (~3.12 | ~3.11 | ~3.10)"). Widen the constraint to include
  # 3.13. LNbits 0.12+ runs cleanly on 3.13 in practice (no syntax/stdlib
  # breakage observed); upstream just hasn't bumped the spec yet.
  if [ -f /home/lnbits/lnbits/pyproject.toml ]; then
    # Replace the entire `python = "..."` line with a constraint that
    # accepts 3.10–3.13 inclusive, regardless of upstream's exact syntax
    # (~3.10|~3.11|~3.12 vs ^3.10 vs >=3.10,<3.13 etc.). Single-quote sed
    # script avoids any shell expansion of pipe chars; `#` delimiter avoids
    # collision with `|` characters inside poetry version specs.
    sudo -u lnbits sed -i \
      's#^python *= *".*"#python = ">=3.10,<3.14"#' \
      /home/lnbits/lnbits/pyproject.toml
    echo "# pyproject.toml python-version widened to include 3.13"
  fi

  # to the install
  echo "# installing application dependencies"
  cd /home/lnbits/lnbits || exit 1

  # check if poetry is installed
  if ! test -x "${POETRY_BIN}"; then
    echo "# install poetry"
    sudo pip3 config set global.break-system-packages true
    sudo pip3 install --upgrade pip || true
    sudo pip3 install poetry || { echo "# FAIL - could not install poetry"; exit 1; }
  fi

  # LNbits supports Python 3.10-3.13 (3.13 enabled by our pyproject.toml
  # widening above). Locate a compatible interpreter.
  # IMPORTANT: on Debian Trixie, /usr/bin/python3.11 may be a symlink to
  # python3.13 (created by build_sdcard.sh for backwards compat). We must
  # verify the actual runtime version, not just the filename.
  LNBITS_PYTHON=""
  for _py in /usr/bin/python3.13 /usr/local/bin/python3.13 "$(which python3.13 2>/dev/null)" \
             /usr/bin/python3.12 /usr/local/bin/python3.12 "$(which python3.12 2>/dev/null)" \
             /usr/bin/python3.11 /usr/local/bin/python3.11 "$(which python3.11 2>/dev/null)" \
             /usr/bin/python3.10 /usr/local/bin/python3.10 "$(which python3.10 2>/dev/null)"; do
    [ -x "${_py}" ] || continue
    _actual_minor=$("${_py}" -c "import sys; print(sys.version_info.minor)" 2>/dev/null)
    if [ -n "${_actual_minor}" ] && [ "${_actual_minor}" -ge 10 ] && [ "${_actual_minor}" -le 13 ]; then
      LNBITS_PYTHON="${_py}"
      break
    fi
  done
  if [ -z "${LNBITS_PYTHON}" ]; then
    # Last resort: system python3 only if it is 3.10-3.13
    _syspy=$(python3 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    _major=$(echo "${_syspy}" | cut -d. -f1)
    _minor=$(echo "${_syspy}" | cut -d. -f2)
    if [ "${_major}" = "3" ] && [ "${_minor:-99}" -ge "10" ] && [ "${_minor:-99}" -le "13" ]; then
      LNBITS_PYTHON="$(which python3)"
      echo "# INFO: using system python ${_syspy} for LNbits"
    else
      echo "# WARNING: LNbits requires Python 3.10-3.13; system python is ${_syspy} (unsupported)"
      echo "# FAIL — aborting LNbits install (caller must not enable the service)"
      exit 1
    fi
  fi
  echo "# Using python for LNBits: ${LNBITS_PYTHON}"
  sudo -u lnbits "${POETRY_BIN}" env use "${LNBITS_PYTHON}" || { echo "# FAIL - poetry env use failed"; exit 1; }

  # Re-render poetry.lock against the pyproject.toml we patched above
  # (python-version widening). Poetry 2.x refuses `install` outright when
  # the lockfile hash does not match pyproject.toml, where 1.x only warned.
  # Default `lock` is conservative: no dep upgrades, only re-hash.
  echo "# refreshing poetry.lock against patched pyproject.toml"
  sudo -u lnbits "${POETRY_BIN}" lock || { echo "# FAIL - poetry lock failed"; exit 1; }

  echo "# install"
  exitCode=0
  if sudo -u lnbits "${POETRY_BIN}" install; then
    echo "Poetry install completed successfully."
  else
    echo "Error: Poetry install failed (see above).. waiting 10 seconds"
    exitCode=1
    sleep 10
  fi

  # v0.15.21 (Bug AA): LNbits pins passlib but never lists bcrypt as a dep,
  # so passlib's CryptContext(schemes=["bcrypt"]) throws MissingBackendError
  # on every password.hash() call -> /login + /create-user return 500
  # "unexpected error". Add bcrypt explicitly via poetry so the lockfile and
  # the venv stay in sync (a bare `pip install bcrypt` in the venv would
  # drift on the next `poetry install` rerun).
  echo "# add bcrypt (passlib backend missing in upstream pin)"
  if sudo -u lnbits "${POETRY_BIN}" add bcrypt; then
    echo "bcrypt added successfully."
  else
    echo "Error: poetry add bcrypt failed; LNbits login will return 500."
    exitCode=1
  fi

  # make sure default virtaulenv is used
  sudo apt-get remove -y python3-virtualenv 2>/dev/null || true
  sudo pip uninstall -y virtualenv 2>/dev/null || true
  sudo apt-get install -y python3-virtualenv || true

  exit $exitCode
fi

# remove from system
if [ "$1" = "uninstall" ]; then

  # check if still active
  isActive=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ "${isActive}" != "0" ]; then
    echo "result='still in use'"
    exit 1
  fi

  echo "# *** UNINSTALL LNBITS ***"

  # always delete user and home directory
  sudo userdel -rf lnbits

  exit 0
fi

# on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if already installed
  if compgen -u | grep -w lnbits; then
    # check poetry if the user exists
    if ! test -x "${POETRY_BIN}"; then
      echo "# Fix faulty installation"
      /home/admin/config.scripts/bonus.lnbits.sh off --keep-data
      /home/admin/config.scripts/bonus.lnbits.sh install || exit 1
    fi
  else
    echo "# Installing code base & dependencies first .."
    /home/admin/config.scripts/bonus.lnbits.sh install || exit 1
  fi

  # check if already active
  isActive=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ "${isActive}" == "1" ]; then
    echo "# FAIL: already installed"
    exit 1
  fi

  # get funding source and check that its available
  fundingsource="$2"

  # run with default funding source if not given as parameter
  if [ "${fundingsource}" == "" ]; then
    echo "# running with default lightning as funing source: ${lightning}"
    fundingsource="${lightning}"
  fi

  if [ "${fundingsource}" == "lnd" ]; then
    if [ "${lnd}" != "on" ]; then
      echo "# FAIL: lnd mainnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "tlnd" ]; then
    if [ "${tlnd}" != "on" ]; then
      echo "# FAIL: lnd testnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "slnd" ]; then
    if [ "${slnd}" != "on" ]; then
      echo "# FAIL: lnd signet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "cl" ]; then
    if [ "${cl}" != "on" ]; then
      echo "# FAIL: CLN mainnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "tcl" ]; then
    if [ "${tcl}" != "on" ]; then
      echo "# FAIL: CLN testnet needs to be activated"
      exit 1
    fi

  elif [ "${fundingsource}" == "scl" ]; then
    if [ "${scl}" != "on" ]; then
      echo "# FAIL: CLN signet needs to be activated"
      exit 1
    fi

  else
    echo "# FAIL: invalid funding source parameter"
    exit 1
  fi

 # prepare data dir file
  sudo mkdir -p $lnbitsDataDir
  sudo chown lnbits:lnbits -R $lnbitsDataDir

  echo "# preparing env file"
  # delete old .env file or old symbolic link
  sudo rm /home/lnbits/lnbits/.env 2>/dev/null
    
  # make sure .env file exists at data drive
  if [ ! -f $lnbitsConfig ]; then
    sudo -u lnbits touch $lnbitsConfig
    sudo bash -c "echo 'LNBITS_ADMIN_UI=true' >> ${lnbitsConfig}"
  fi
  sudo chown lnbits:lnbits $lnbitsConfig

  # crete symbolic link
  sudo -u lnbits ln -s $lnbitsConfig /home/lnbits/lnbits/.env

  if [ ! -e /mnt/hdd/app-data/LNBits/database.sqlite3 ]; then
    echo "# install database: PostgreSQL"

    # POSTGRES
    postgresConfig

    # config update
    # example: postgres://<user>:<password>@<host>/<database>
    sudo sed -i "/^LNBITS_DATABASE_URL=/d" $lnbitsConfig 2>/dev/null
    sudo sed -i "/^LNBITS_DATA_FOLDER=/d" $lnbitsConfig 2>/dev/null
    loadOrGenerateLNBitsDBPassword
    sudo bash -c "echo 'LNBITS_DATABASE_URL=postgres://lnbits_user:${LNBITS_DB_PASS}@localhost:5432/lnbits_db' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits/data' >> ${lnbitsConfig}"

  else

    echo "# install database: SQLite"
    /home/admin/config.scripts/blesk.conf.sh set LNBitsDB "SQLite"

    # new data directory
    sudo mkdir -p /mnt/hdd/app-data/LNBits

    # config update
    sudo sed -i "/^LNBITS_DATA_FOLDER=/d" $lnbitsConfig 2>/dev/null
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits' >> ${lnbitsConfig}"
  fi
  sudo chown lnbits:lnbits -R /mnt/hdd/app-data/LNBits

  # open firewall
  echo
  echo "*** Updating Firewall ***"
  sudo ufw allow 5000 comment 'lnbits HTTP'
  sudo ufw allow 5443 comment 'lnbits HTTPS'
  echo

  # make sure that systemd starts funding source first
  systemdDependency="glcoind.service"
  if [ "${fundingsource}" == "lnd" ]; then
    systemdDependency="lnd.service"
  elif [ "${fundingsource}" == "cl" ]; then
    systemdDependency="lightningd.service"
  fi

  # install service
  echo "*** Install systemd ***"
  cat <<EOF | sudo tee /etc/systemd/system/lnbits.service >/dev/null
# systemd unit for lnbits

[Unit]
Description=lnbits
Wants=${systemdDependency}
After=${systemdDependency}
PartOf=${systemdDependency}

[Service]
WorkingDirectory=/home/lnbits/lnbits
ExecStartPre=/home/admin/config.scripts/bonus.lnbits.sh prestart
ExecStart=/bin/sh -c 'cd /home/lnbits/lnbits && /usr/local/bin/poetry run lnbits --port 5000 --host 0.0.0.0'
User=lnbits
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=journal
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

  # let switch command part do the detail config
  /home/admin/config.scripts/bonus.lnbits.sh switch ${fundingsource}
  cd /home/lnbits/lnbits || exit 1

  sudo systemctl enable lnbits

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# OK - lnbits service is enabled, system is on ready so starting lnbits service"
    sudo systemctl start lnbits
  else
    echo "# OK - lnbits service is enabled, but needs reboot or manual starting: sudo systemctl start lnbits"
  fi

  # setup nginx symlinks
  if ! [ -f /etc/nginx/sites-available/lnbits_ssl.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/lnbits_ssl.conf /etc/nginx/sites-available/lnbits_ssl.conf
  fi
  if ! [ -f /etc/nginx/sites-available/lnbits_tor.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/lnbits_tor.conf /etc/nginx/sites-available/lnbits_tor.conf
  fi
  if ! [ -f /etc/nginx/sites-available/lnbits_tor_ssl.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/lnbits_tor_ssl.conf /etc/nginx/sites-available/lnbits_tor_ssl.conf
  fi
  sudo ln -sf /etc/nginx/sites-available/lnbits_ssl.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/lnbits_tor.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/lnbits_tor_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx

  # setting value in raspi blitz config
  /home/admin/config.scripts/blesk.conf.sh set LNBits "on"

  # Hidden Service if Tor is active
  source /mnt/hdd/app-data/raspiblesk.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    /home/admin/config.scripts/tor.onion-service.sh lnbits 80 5002 443 5003
  fi

  echo "# OK install done ... might need to restart or call: sudo systemctl start lnbits"

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

# config for a special funding source (e.g lnd or CLN as backend)
if [ "$1" = "switch" ]; then

  echo "## bonus.lnbits.sh switch $2"

  # get funding source and check that its available
  fundingsource="$2"
  clrpcsubdir=""
  if [ "${fundingsource}" == "lnd" ]; then
    if [ "${lnd}" != "on" ]; then
      echo "#FAIL: lnd mainnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "tlnd" ]; then
    if [ "${tlnd}" != "on" ]; then
      echo "# FAIL: lnd testnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "slnd" ]; then
    if [ "${slnd}" != "on" ]; then
      echo "# FAIL: lnd signet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "cl" ]; then
    if [ "${cl}" != "on" ]; then
      echo "# FAIL: CLN mainnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "tcl" ]; then
    clrpcsubdir="/testnet"
    if [ "${tcl}" != "on" ]; then
      echo "# FAIL: CLN testnet not installed or running"
      exit 1
    fi

  elif [ "${fundingsource}" == "scl" ]; then
    clrpcsubdir="/signet"
    if [ "${scl}" != "on" ]; then
      echo "# FAIL: CLN signet not installed or running"
      exit 1
    fi

  else
    echo "# FAIL: unvalid fundig source parameter"
    exit 1
  fi

  # make lnd.service fallback
  sudo sed -i 's/Wants=lnd.service/Wants=glcoind.service/' /etc/systemd/system/lnbits.service
  sudo sed -i 's/After=lnd.service/After=glcoind.service/' /etc/systemd/system/lnbits.service

  echo "##############"
  echo "# NOTE: If you switch the funding source of a running LNbits instance all sub account will keep balance."
  echo "# Make sure that the new funding source has enough gsats to cover the LNbits bookeeping of sub accounts."
  echo "##############"

  # remove all old possible settings for former funding source (clean state)
  sudo sed -i "/^LNBITS_BACKEND_WALLET_CLASS=/d" $lnbitsConfig 2>/dev/null
  sudo sed -i "/^LND_REST_ENDPOINT=/d" $lnbitsConfig 2>/dev/null
  sudo sed -i "/^LND_REST_CERT=/d" $lnbitsConfig 2>/dev/null
  sudo sed -i "/^LND_REST_ADMIN_MACAROON=/d" $lnbitsConfig 2>/dev/null
  sudo sed -i "/^LND_REST_INVOICE_MACAROON=/d" $lnbitsConfig 2>/dev/null
  sudo sed -i "/^LND_REST_READ_MACAROON=/d" $lnbitsConfig 2>/dev/null
  sudo /usr/sbin/usermod -G lnbits lnbits
  sudo sed -i "/^CLIGHTNING_RPC=/d" $lnbitsConfig 2>/dev/null

  # LND CONFIG
  if [ "${fundingsource}" == "lnd" ] || [ "${fundingsource}" == "tlnd" ] || [ "${fundingsource}" == "slnd" ]; then

    # make sure lnbits user can access LND credentials
    echo "# adding lnbits user is member of lndreadonly, lndinvoice, lndadmin"
    sudo /usr/sbin/usermod --append --groups lndinvoice lnbits
    sudo /usr/sbin/usermod --append --groups lndreadonly lnbits
    sudo /usr/sbin/usermod --append --groups lndadmin lnbits

    # prepare config entries in lnbits config for lnd
    echo "# preparing lnbits config for lnd"
    sudo bash -c "echo 'LNBITS_BACKEND_WALLET_CLASS=LndRestWallet' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LND_REST_ENDPOINT=https://127.0.0.1:8080' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LND_REST_CERT=' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LND_REST_ADMIN_MACAROON=' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LND_REST_INVOICE_MACAROON=' >> ${lnbitsConfig}"
    sudo bash -c "echo 'LND_REST_READ_MACAROON=' >> ${lnbitsConfig}"

  fi

  if [ "${fundingsource}" == "cl" ] || [ "${fundingsource}" == "tcl" ] || [ "${fundingsource}" == "scl" ]; then

    echo "# add the 'lnbits' user to the 'glcoin' group"
    sudo /usr/sbin/usermod --append --groups glcoin lnbits
    echo "# check user"
    id lnbits

    echo "# allowing lnbits user as part of the glcoin group to RW RPC hook"
    sudo chmod 770 /home/glcoin/.lightning/glcoin${clrpcsubdir}
    sudo chmod 660 /home/glcoin/.lightning/glcoin${clrpcsubdir}/lightning-rpc
    if [ "${fundingsource}" == "cl" ]; then
      CLCONF="/home/glcoin/.lightning/config"
    else
      CLCONF="/home/glcoin/.lightning${clrpcsubdir}/config"
    fi
    # https://github.com/rootzoll/raspiblesk/issues/3007
    if [ "$(sudo cat ${CLCONF} | grep -c "^rpc-file-mode=0660")" -eq 0 ]; then
      echo "rpc-file-mode=0660" | sudo tee -a ${CLCONF}
    fi

    echo "# preparing lnbits config for CLN"
    sudo bash -c "echo 'LNBITS_BACKEND_WALLET_CLASS=CLightningWallet' >> ${lnbitsConfig}"
    sudo bash -c "echo 'CLIGHTNING_RPC=/home/glcoin/.lightning/glcoin${clrpcsubdir}/lightning-rpc' >> ${lnbitsConfig}"
  fi

  # set raspiblesk config value for funding
  /home/admin/config.scripts/blesk.conf.sh set LNBitsFunding "${fundingsource}"

  echo "##############"
  echo "# OK new funding source set - does need restart or call: sudo systemctl restart lnbits"
  echo "##############"

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # check for second parameter: should data be deleted?
  deleteData=0
  if [ "$2" = "--delete-data" ]; then
    deleteData=1
  elif [ "$2" = "--keep-data" ]; then
    deleteData=0
  else
    if (whiptail --title " DELETE DATA? " --yesno "Do you want to delete\nthe LNbits Server Data?" 8 30); then
      deleteData=1
    else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"
  echo "*** REMOVING LNbits ***"

  isInstalled=$(sudo ls /etc/systemd/system/lnbits.service 2>/dev/null | grep -c 'lnbits.service')
  if [ ${isInstalled} -eq 1 ] || [ "${LNBits}" == "on" ]; then
    sudo systemctl stop lnbits
    sudo systemctl disable lnbits
    sudo rm /etc/systemd/system/lnbits.service
    echo "# OK lnbits.service removed."
  else
    echo "# lnbits.service is not installed."
  fi

  echo "# Cleaning up LNbits install ..."
  sudo ufw delete allow 5000
  sudo ufw delete allow 5443

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/lnbits_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/lnbits_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/lnbits_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/lnbits_ssl.conf
  sudo rm -f /etc/nginx/sites-available/lnbits_tor.conf
  sudo rm -f /etc/nginx/sites-available/lnbits_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off lnbits
  fi

  if [ ${deleteData} -eq 1 ]; then
    echo "# deleting data"
    sudo -u postgres psql -c "drop database lnbits_db;"
    sudo -u postgres psql -c "drop user lnbits_user;"
    sudo rm /home/lnbits/lnbits/.env
    sudo rm -R /mnt/hdd/app-data/LNBits
  else
    echo "# keeping data"
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blesk.conf.sh set LNBits "off"

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

# backup
if [ "$1" = "backup" ]; then
  source <(/home/admin/_cache.sh get LNBitsDB)
  echo "# Start Backup LNBits ${LNBitsDB} database"
  if [ "${LNBitsDB}" == "PostgreSQL" ]; then
    # postgresql backup
    sudo /home/admin/config.scripts/bonus.postgresql.sh backup lnbits_db
  else
    # sqlite backup
    backup_target="/mnt/hdd/app-data/backup/lnbits_sqlite"
    backup_file="lnbits_sqlite_$(date +%d)-$(date +%m)-$(date +%Y)_$(date +%H)-$(date +%M)_fs.tar"
    if [ ! -d $backup_target ]; then
      sudo mkdir -p $backup_target 1>&2
    fi
    # Delete old backups (keep last 3 backups)
    sudo chown -R admin:admin $backup_target
    ls -tp $backup_target/*.tar | grep -v '/$' | tail -n +4 | tr '\n' '\0' | xargs -0 rm -- 2>/dev/null

    cd $backup_target
    sudo tar -cf $backup_file -C "/mnt/hdd/app-data" LNBits/
    echo "OK - Backup finished, file saved as ${backup_target}/${backup_file}"
  fi
  sudo systemctl start lnbits
  exit 0
fi

# restore
if [ "$1" = "restore" ]; then
  source <(/home/admin/_cache.sh get LNBitsDB)
  if [ "${LNBitsDB}" == "PostgreSQL" ]; then
    echo "# Restore PostgreSQL database"
    if [ "$2" != "" ]; then
      backup_file=$2
      sudo /home/admin/config.scripts/bonus.postgresql.sh restore lnbits_db lnbits_user raspiblesk "${backup_file}"
    else
      sudo /home/admin/config.scripts/bonus.postgresql.sh restore lnbits_db lnbits_user raspiblesk
    fi
  else
    backup_target="/mnt/hdd/app-data/backup/lnbits_sqlite"
    if [ ! -d $backup_target ]; then
      echo "# ABORT - No backups found"
      exit 1
    else
      echo "# Restore SQLite database"
      cd $backup_target

      if [ "$2" != "" ]; then
        if [ -e $2 ]; then
          backup_file=$2
        else
          echo "ABORT - File not found (${2})"
          exit 1
        fi
      else
        # find recent backup
        backup_file=$(ls -t $backup_target/*.tar | head -n1)
      fi

      echo "Start restore from backup ${backup_file}"

      # unpack backup file
      sudo tar -xf $backup_file || exit 1
      echo "Unpack backup successful, backup current db now ..."

      # backup current db
      /home/admin/config.scripts/bonus.lnbits.sh backup

      # apply backup data
      sudo rm -R /mnt/hdd/app-data/LNBits/
      sudo chown -R lnbits:lnbits LNBits/
      sudo mv LNBits/ /mnt/hdd/app-data/

      echo "Remove restored backup file"
      sudo rm -f $backup_file

      echo "OK - Apply backup data successful"
    fi
  fi

  sudo systemctl start lnbits
  exit 0
fi

# revert migrate to postgresql
if [ "$1" = "migrate" ] && [ "$2" = "revert" ]; then
  /home/admin/config.scripts/blesk.conf.sh set LNBitsMigrate "on"
  revertMigration
  exit 0
fi

# migrate
if [ "$1" = "migrate" ]; then

  if [ -e /mnt/hdd/app-data/LNBits/database.sqlite3 ]; then
    echo "# Backup SQLite database"
    # backup current database, but dont overwrite last backup
    if [ -e /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar ]; then
      if [ -e /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar.old ]; then
        echo "# Remove old backup file"
        sudo rm -f /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar.old
      fi
      # keep the last backup as old backup
      sudo mv /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar.old
    fi
    # create new backup
    sudo tar -cf /mnt/hdd/app-data/LNBits_sqlitedb_backup.tar -C /mnt/hdd/app-data LNBits/

    # restore sqlite database config
    sudo sed -i "/^LNBITS_DATA_FOLDER=/d" $lnbitsConfig 2>/dev/null
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits' >> ${lnbitsConfig}"

    # stop after sync was done
    sudo systemctl stop lnbits

    /home/admin/config.scripts/blesk.conf.sh set LNBitsMigrate "on"

    # POSTGRES
    postgresConfig

    # example: postgres://<user>:<password>@<host>/<database>
    # add new postgres config
    sudo sed -i "/^LNBITS_DATABASE_URL=/d" $lnbitsConfig 2>/dev/null
    loadOrGenerateLNBitsDBPassword
    sudo bash -c "echo 'LNBITS_DATABASE_URL=postgres://lnbits_user:${LNBITS_DB_PASS}@localhost:5432/lnbits_db' >> ${lnbitsConfig}"

    # clean start on new postgres db prior migration
    echo "# LNBits first start with clean PostgreSQL"
    sudo systemctl start lnbits

    # execStartPre is not enough, wait for lnbits is finally running
    count=0
    count_max=30
    while ! nc -zv 127.0.0.1 5000 2>/dev/null; do
      count=$(expr $count + 1)
      echo "wait for LNBIts to start (${count}s/${count_max}s)"
      sleep 1
      if [ $count = $count_max ]; then
        sudo systemctl status lnbits
        echo "# FAIL - LNBits service was not able to start"
        revertMigration
        exit 1
      fi
    done
    # wait a sec for "✔ All migrations done." (TODO make it pretty)
    sleep 5
    echo "# LNBits service looks good"
    sudo systemctl stop lnbits

    echo "# Start convert old SQLite to new PostgreSQL"
    if ! sudo -u lnbits "${POETRY_BIN}" run python tools/conv.py; then
      echo "FAIL - Convert failed, revert migration process"
      revertMigration
      exit 1
    else
      echo "# OK - Convert successful"
    fi

    # cleanup old sqlite data directory
    echo "# Cleanup old data directory"
    sudo rm -R /mnt/hdd/app-data/LNBits/
    # new data directory
    sudo mkdir -p /mnt/hdd/app-data/LNBits/data
    sudo chown lnbits:lnbits -R /mnt/hdd/app-data/LNBits/

    echo "# Configure .env"
    sudo sed -i "/^LNBITS_DATA_FOLDER=/d" $lnbitsConfig 2>/dev/null
    sudo bash -c "echo 'LNBITS_DATA_FOLDER=/mnt/hdd/app-data/LNBits/data' >> ${lnbitsConfig}"

    # setting value in raspi blitz config
    /home/admin/config.scripts/blesk.conf.sh set LNBitsMigrate "off"

    echo "# OK - migration done"
  else
    echo "# ABORT - No SQLite data found to migrate from"
  fi

  sudo systemctl start lnbits
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
