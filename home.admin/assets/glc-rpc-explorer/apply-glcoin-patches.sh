#!/bin/bash
# Apply Glcoin patches to a freshly-cloned btc-rpc-explorer tree.
# Idempotent: re-running on an already-patched tree is a no-op.
#
# Usage: apply-glcoin-patches.sh /home/glcrpcexplorer/glc-rpc-explorer

set -eu

REPO_DIR="${1:?usage: apply-glcoin-patches.sh <explorer_repo_dir>}"
ASSETS_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "${REPO_DIR}/app/coins" ]; then
  echo "# FAIL — ${REPO_DIR}/app/coins not found, wrong tree?"
  exit 1
fi

echo "# Glcoin patch: installing app/coins/glc.js"
cp "${ASSETS_DIR}/glc.js" "${REPO_DIR}/app/coins/glc.js"

# Register glc in app/coins.js — only append if not already there
COINS_JS="${REPO_DIR}/app/coins.js"
if [ -f "${COINS_JS}" ] && ! grep -qF "require(\"./coins/glc.js\")" "${COINS_JS}"; then
  echo "# Glcoin patch: registering 'glc' in app/coins.js"
  # btc-rpc-explorer's coins.js exports module.exports = { BTC: require(...), LTC: ..., ... };
  # We inject a GLC entry before the closing brace of that object.
  python3 - "${COINS_JS}" <<'PY'
import re, sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    src = f.read()
if 'require("./coins/glc.js")' not in src:
    m = re.search(r"module\.exports\s*=\s*\{", src)
    if not m:
        sys.stderr.write("# coins.js shape not recognised — skipping injection\n")
        sys.exit(0)
    insert_at = m.end()
    inject = "\n\tGLC: require(\"./coins/glc.js\"),"
    src = src[:insert_at] + inject + src[insert_at:]
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("# coins.js: GLC registered")
PY
fi

# Patch the default coin override hint in app/config.js (cosmetic — env var wins)
CONFIG_JS="${REPO_DIR}/app/config.js"
if [ -f "${CONFIG_JS}" ]; then
  # No-op for now — BTCEXP_COIN=GLC in the env is the authoritative override.
  :
fi

# Replace BTC favicon/logo placeholders with the Glcoin mark if shipped.
if [ -f "${ASSETS_DIR}/glc.svg" ]; then
  install -m 644 "${ASSETS_DIR}/glc.svg" "${REPO_DIR}/public/img/logo/glc.svg" || true
fi
if [ -f "${ASSETS_DIR}/glc.png" ]; then
  install -m 644 "${ASSETS_DIR}/glc.png" "${REPO_DIR}/public/img/logo/glc.png" || true
fi

# Glcoin-specific routes/views: /miners, /ipfs-links, /ipfs-pins
echo "# Glcoin patch: installing glcRouter + pug views"
install -m 644 "${ASSETS_DIR}/glcRouter.js"        "${REPO_DIR}/routes/glcRouter.js"
install -m 644 "${ASSETS_DIR}/glc-miners.pug"      "${REPO_DIR}/views/glc-miners.pug"
install -m 644 "${ASSETS_DIR}/glc-ipfs-links.pug"  "${REPO_DIR}/views/glc-ipfs-links.pug"
install -m 644 "${ASSETS_DIR}/glc-ipfs-pins.pug"   "${REPO_DIR}/views/glc-ipfs-pins.pug"

# Register glcRouter in app.js — idempotent (marker comment guards re-runs)
APP_JS="${REPO_DIR}/app.js"
if [ -f "${APP_JS}" ] && ! grep -q "GLCOIN_ROUTER_PATCH" "${APP_JS}"; then
  echo "# Glcoin patch: registering glcRouter in app.js"
  python3 - "${APP_JS}" <<'PY'
import re, sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    src = f.read()

# 1. Add require() near the other route requires.
require_line = "const glcRouter = require('./routes/glcRouter.js'); /* GLCOIN_ROUTER_PATCH */"
m = re.search(r"const\s+baseActionsRouter\s*=\s*require\(['\"]\./routes/baseRouter\.js['\"]\);", src)
if not m:
    sys.stderr.write("# app.js: baseRouter require line not found — aborting router patch\n")
    sys.exit(1)
insert_at = m.end()
src = src[:insert_at] + "\n" + require_line + src[insert_at:]

# 2. Mount it before the catch-all baseRouter so its routes win.
m2 = re.search(r"expressApp\.use\(config\.baseUrl,\s*baseActionsRouter\);", src)
if not m2:
    sys.stderr.write("# app.js: baseRouter mount line not found — aborting router patch\n")
    sys.exit(1)
mount_line = "expressApp.use(config.baseUrl, glcRouter); /* GLCOIN_ROUTER_PATCH */\n"
src = src[:m2.start()] + mount_line + src[m2.start():]

with io.open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("# app.js: glcRouter registered before baseRouter")
PY
fi

# Inject nav links for the Glcoin views into views/layout.pug. Idempotent
# via the GLCOIN_NAV_PATCH marker comment.
LAYOUT_PUG="${REPO_DIR}/views/layout.pug"
if [ -f "${LAYOUT_PUG}" ] && ! grep -q "GLCOIN_NAV_PATCH" "${LAYOUT_PUG}"; then
  echo "# Glcoin patch: adding nav links to layout.pug"
  python3 - "${LAYOUT_PUG}" <<'PY'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    src = f.read()

# Find the unique line `ul.navbar-nav.me-auto` (at 6 tabs in upstream).
needle = "ul.navbar-nav.me-auto\n"
idx = src.find(needle)
if idx < 0:
    sys.stderr.write("# layout.pug: ul.navbar-nav.me-auto not found — skipping nav patch\n")
    sys.exit(0)

# Insert nav-items at +1 tab depth from the ul (7 tabs / a.nav-link at 8 tabs).
T7 = "\t" * 7
T8 = "\t" * 8
inject = (
    f"{T7}//- GLCOIN_NAV_PATCH\n"
    f"{T7}li.nav-item\n"
    f"{T8}a.nav-link(href='./miners') Miners\n"
    f"{T7}li.nav-item\n"
    f"{T8}a.nav-link(href='./ipfs-links') IPFS Links\n"
    f"{T7}li.nav-item\n"
    f"{T8}a.nav-link(href='./ipfs-pins') IPFS Pins\n"
)

insert_at = idx + len(needle)
src = src[:insert_at] + inject + src[insert_at:]

with io.open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("# layout.pug: nav links injected")
PY
fi

# --- string rebrand in views (display layer only) ---
# Replace hardcoded "Bitcoin"/"BTC" display strings and "sat" -> "gsat" unit
# labels in pug views and select user-visible JS strings. The Coin module
# (app/coins/glc.js) already provides the currency name, but several upstream
# templates hardcode "BTC"/"Bitcoin" outside the coinConfig path. Idempotent
# via the GLCOIN_REBRAND_PATCH marker in app.js.
APP_JS="${REPO_DIR}/app.js"
if [ -f "${APP_JS}" ] && ! grep -q "GLCOIN_REBRAND_PATCH" "${APP_JS}"; then
  echo "# Glcoin rebrand: views + JS display strings"

  # views/*.pug — display layer
  if [ -d "${REPO_DIR}/views" ]; then
    find "${REPO_DIR}/views" -name '*.pug' -print0 \
      | xargs -0 -r sed -i \
          -e 's| BTC | GLC |g' \
          -e 's| BTC$| GLC|g' \
          -e 's|^BTC | GLC |g' \
          -e 's|Bitcoin Explorer|Glcoin Explorer|g' \
          -e "s|Bitcoin's mainnet|Glcoin's mainnet|g" \
          -e 's|Bitcoiners|Glcoiners|g' \
          -e 's|sat/vB|gsat/vB|g' \
          -e 's|sat/WU|gsat/WU|g' \
          -e 's|satoshi|gsatoshi|g' \
          -e 's|Satoshi|Gsatoshi|g'
  fi

  # app/utils.js and related display helpers — only common display strings
  if [ -d "${REPO_DIR}/app" ]; then
    find "${REPO_DIR}/app" -name '*.js' -not -path '*/coins/*' -print0 \
      | xargs -0 -r sed -i \
          -e 's|"sat/vB"|"gsat/vB"|g' \
          -e "s|'sat/vB'|'gsat/vB'|g" \
          -e 's|"sat/WU"|"gsat/WU"|g' \
          -e "s|'sat/WU'|'gsat/WU'|g"
  fi

  # leave a marker so this block is idempotent
  printf '\n// GLCOIN_REBRAND_PATCH (idempotency marker)\n' >> "${APP_JS}"
  echo "# Glcoin rebrand done"
fi

echo "# Glcoin patches applied to ${REPO_DIR}"
