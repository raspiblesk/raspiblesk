#!/bin/bash
# v0149 hardening (C-6): bootstrap SSH key rotation.
#
# build_sdcard.sh generates a single ed25519 key with empty passphrase and
# stores its public half in admin's authorized_keys. The matching private
# key is printed once on the build console and (optionally, opt-in) saved
# to the boot partition. Until the operator rotates that key, anyone who
# captured it from build logs / boot partition / scrollback has bearer
# root access via SSH + sudoers.
#
# This script:
#   - On every interactive admin login, checks for the marker file
#     /home/admin/.ssh/first-login-rotate-required.
#   - If present, refuses to proceed to the main menu until the operator
#     either pastes a new SSH public key OR explicitly accepts the
#     bootstrap key (with an "I-understand" prompt).
#   - On accept, removes the marker.
#
# Marker is created by build_sdcard.sh's setup_credentials().
# Sourced from /home/admin/.bashrc before the main-menu autostart.

_marker="/home/admin/.ssh/first-login-rotate-required"
_authkeys="/home/admin/.ssh/authorized_keys"

if [ ! -f "${_marker}" ]; then
  return 0 2>/dev/null || exit 0
fi

# Only nag interactive logins, not script invocations or non-tty sessions.
if [ -z "${PS1}" ] || [ ! -t 0 ]; then
  return 0 2>/dev/null || exit 0
fi

cat <<'EOF'

================================================================
  RASPIBLESK FIRST-LOGIN: SSH KEY ROTATION REQUIRED
================================================================

The SSH key used to log you in was generated during image build,
printed once on the build console, and (optionally) copied to the
boot partition. It is treated as a single-use BOOTSTRAP credential.

Anyone who captured it during build (terminal scrollback, build log,
SD-card swap) currently has the same root access you do.

You must either:
  (1) Paste your own SSH public key now — the bootstrap key will be
      replaced and the old one revoked.
  (2) Type 'KEEP' to accept the risk and continue with the bootstrap
      key. Marker will be removed; this prompt will not reappear.

EOF

while true; do
  echo -n "Paste your SSH public key (ssh-ed25519 / ssh-rsa …) or type KEEP: "
  read -r _line
  case "${_line}" in
    "")
      echo "(empty input — try again)"
      ;;
    KEEP)
      echo "# Accepting bootstrap key. You can rotate later via:"
      echo "#   sudo /home/admin/config.scripts/blesk.bootstrap-key.sh rotate"
      rm -f "${_marker}"
      break
      ;;
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-ssh-ed25519@*\ *|sk-ecdsa-sha2-*\ *)
      # Validate via ssh-keygen — refuse anything that doesn't parse as a key.
      _tmp=$(mktemp -p /dev/shm)
      printf '%s\n' "${_line}" > "${_tmp}"
      if ssh-keygen -l -f "${_tmp}" >/dev/null 2>&1; then
        cat "${_tmp}" > "${_authkeys}"
        chmod 600 "${_authkeys}"
        chown admin:admin "${_authkeys}"
        rm -f "${_tmp}" "${_marker}"
        echo ""
        echo "# OK — your key is installed. Bootstrap key revoked."
        echo "# Open a NEW SSH session with your key to verify before"
        echo "# closing this one (otherwise you may lose access)."
        break
      else
        echo "# That doesn't parse as a valid SSH public key. Try again."
        rm -f "${_tmp}"
      fi
      ;;
    *)
      echo "# Doesn't look like an SSH public key. Lines start with"
      echo "# ssh-ed25519 / ssh-rsa / ecdsa-sha2-* / sk-* …"
      ;;
  esac
done

# Manual re-arm: 'rotate' flag from outside the auto-prompt
if [ "$1" = "rotate" ]; then
  touch "${_marker}"
  chown admin:admin "${_marker}"
  chmod 600 "${_marker}"
  echo "# Marker re-armed; next interactive admin login will prompt for rotation."
fi
