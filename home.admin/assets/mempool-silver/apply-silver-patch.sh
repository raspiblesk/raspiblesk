#!/bin/bash
# Replace mempool's fiat-currency display (USD/EUR/...) with grams of silver.
#
# Reason: Glcoin is designed for interplanetary settlement. Fiat exchange
# rates are meaningless at light-speed-delay distances; a fixed peg to a
# universal physical commodity (silver, mass in grams) is the natural unit.
#
# Default peg: 1 gsat = 0.01 g Ag  ->  1 GLC = 1e6 g Ag (since 1 GLC = 1e8 gsat).
# Glcoin renames Bitcoin's display unit "sat/satoshi" to "gsat/gsatoshi"
# across UIs (Mempool, Explorer, RTL, blesk-web). The on-the-wire protocol
# layer keeps the standard 1e-8 GLC fraction; only display labels change.
# Override at install time (rate = grams of silver per 1 GLC):
#   GLC_SILVER_GRAMS_PER_GLC=1e6 apply-silver-patch.sh <repo>
#
# Idempotent — detects prior application by the GLCOIN_SILVER_PATCH marker
# inside price-updater.ts (survives `git checkout <tag>` on update).

set -eu

REPO_DIR="${1:?usage: apply-silver-patch.sh <mempool_repo_dir>}"
RATE="${GLC_SILVER_GRAMS_PER_GLC:-1e6}"

if [ ! -d "${REPO_DIR}/frontend" ] || [ ! -d "${REPO_DIR}/backend" ]; then
  echo "# FAIL — ${REPO_DIR} does not look like a mempool tree"
  exit 1
fi

PIPE_DIR="${REPO_DIR}/frontend/src/app/shared/pipes"
SEL_DIR="${REPO_DIR}/frontend/src/app/components/fiat-selector"
PRICE_UPDATER="${REPO_DIR}/backend/src/tasks/price-updater.ts"
POOLS_UPDATER="${REPO_DIR}/backend/src/tasks/pools-updater.ts"

if grep -q "GLCOIN_SILVER_PATCH" "${PRICE_UPDATER}" 2>/dev/null \
  && grep -q "GLCOIN_KYC_POOLS_PATCH" "${POOLS_UPDATER}" 2>/dev/null; then
  echo "# Glcoin patches already applied — skipping"
  exit 0
fi

echo "# applying Glcoin mempool patches (silver peg + KYC miner pools)"
echo "#   silver peg: 1 GLC = ${RATE} g Ag"

for f in "${PIPE_DIR}/fiat-currency.pipe.ts" "${PIPE_DIR}/fiat-shortener.pipe.ts" \
         "${SEL_DIR}/fiat-selector.component.html" "${PRICE_UPDATER}" \
         "${POOLS_UPDATER}"; do
  if [ ! -f "$f" ]; then
    echo "# FAIL — expected file not found: $f"
    exit 1
  fi
done

# --- frontend: fiat-currency.pipe.ts ---
cat > "${PIPE_DIR}/fiat-currency.pipe.ts" <<'TS'
import { Inject, LOCALE_ID, Pipe, PipeTransform } from '@angular/core';
import { Subscription } from 'rxjs';
import { StateService } from '@app/services/state.service';

@Pipe({ name: 'fiatCurrency' })
export class FiatCurrencyPipe implements PipeTransform {
  fiatSubscription: Subscription;
  currency: string;

  constructor(
    @Inject(LOCALE_ID) public locale: string,
    private stateService: StateService,
  ) {
    this.fiatSubscription = this.stateService.fiatCurrency$.subscribe((fiat) => {
      this.currency = fiat;
    });
  }

  transform(num: number, ...args: any[]): unknown {
    const digits = args[0];
    let minFrac = 2, maxFrac = 6;
    if (typeof digits === 'string') {
      const m = digits.match(/^\d+\.(\d+)-(\d+)$/);
      if (m) { minFrac = parseInt(m[1], 10); maxFrac = parseInt(m[2], 10); }
    }
    if (Math.abs(num) >= 1000) {
      return new Intl.NumberFormat(this.locale, { style: 'decimal', maximumFractionDigits: 0 }).format(num) + ' g Ag';
    }
    return new Intl.NumberFormat(this.locale, {
      style: 'decimal',
      minimumFractionDigits: Math.min(minFrac, 4),
      maximumFractionDigits: maxFrac,
    }).format(num) + ' g Ag';
  }
}
TS

# --- frontend: fiat-shortener.pipe.ts ---
cat > "${PIPE_DIR}/fiat-shortener.pipe.ts" <<'TS'
import { Inject, LOCALE_ID, Pipe, PipeTransform } from '@angular/core';
import { Subscription } from 'rxjs';
import { StateService } from '@app/services/state.service';

@Pipe({ name: 'fiatShortener' })
export class FiatShortenerPipe implements PipeTransform {
  fiatSubscription: Subscription;
  currency: string;

  constructor(
    @Inject(LOCALE_ID) public locale: string,
    private stateService: StateService,
  ) {
    this.fiatSubscription = this.stateService.fiatCurrency$.subscribe((fiat) => {
      this.currency = fiat;
    });
  }

  transform(num: number, ...args: any[]): unknown {
    const digits = args[0] || 1;
    if (Math.abs(num) < 1000) {
      return new Intl.NumberFormat(this.locale, { style: 'decimal', maximumFractionDigits: 2 }).format(num) + ' g Ag';
    }
    const lookup = [
      { value: 1, symbol: '' },
      { value: 1e3, symbol: 'k' },
      { value: 1e6, symbol: 'M' },
      { value: 1e9, symbol: 'B' },
      { value: 1e12, symbol: 'T' },
      { value: 1e15, symbol: 'P' },
      { value: 1e18, symbol: 'E' },
    ];
    const item = lookup.slice().reverse().find((it) => num >= it.value) || lookup[0];
    const scaled = num / item.value;
    const result = new Intl.NumberFormat(this.locale, {
      style: 'decimal',
      maximumFractionDigits: digits,
    }).format(scaled);
    return result + item.symbol + ' g Ag';
  }
}
TS

# --- frontend: hide the fiat selector (single unit, dropdown is meaningless) ---
cat > "${SEL_DIR}/fiat-selector.component.html" <<'HTML'
<div class="text-small text-center" style="opacity: 0.65;">
    <span title="Glcoin is pegged to grams of silver">g Ag</span>
</div>
HTML

# --- backend: price-updater.ts — return constant silver rate, disable feeds ---
python3 - "${PRICE_UPDATER}" "${RATE}" <<'PY'
import sys, io
path, rate = sys.argv[1], sys.argv[2]
with io.open(path, 'r', encoding='utf-8') as f:
    src = f.read()

MARKER = '/* GLCOIN_SILVER_PATCH */'
if MARKER in src:
    sys.exit(0)

def replace_method_body(src, sig):
    idx = src.find(sig)
    if idx < 0:
        return src, False
    brace_idx = src.find('{', idx)
    if brace_idx < 0:
        return src, False
    depth = 1
    end = brace_idx + 1
    while end < len(src) and depth > 0:
        if src[end] == '{':
            depth += 1
        elif src[end] == '}':
            depth -= 1
        end += 1
    return (src[:brace_idx], src[end:])

# 1. getLatestPrices(): return constant silver-rate object
before, after = replace_method_body(src, 'public getLatestPrices(): ApiPrice')
new_body = (
    "{\n"
    "    " + MARKER + "\n"
    "    const GLC_SILVER_GRAMS_PER_GLC = " + rate + ";\n"
    "    const out: any = { time: Math.floor(Date.now() / 1000) };\n"
    "    for (const k of Object.keys(this.latestPrices)) {\n"
    "      if (k === 'time') continue;\n"
    "      out[k] = GLC_SILVER_GRAMS_PER_GLC;\n"
    "    }\n"
    "    return out as ApiPrice;\n"
    "  }"
)
src = before + new_body + after

# 2. $run(): no-op — no external feed calls
before, after = replace_method_body(src, 'public async $run(): Promise<void>')
new_body = (
    "{\n"
    "    " + MARKER + "\n"
    "    // external price feeds disabled — silver peg is constant\n"
    "    return;\n"
    "  }"
)
src = before + new_body + after

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(src)
print('# price-updater.ts patched (rate: 1 GLC = ' + rate + ' g Ag)')
PY

# --- backend: pools-updater.ts — recognise KYC miners via glcoind RPC ---
# Mempool's default fetches mempool/mining-pools/pools-v2.json from GitHub
# (BTC mining pools), so every Glcoin block gets labelled "Unknown".
# We replace updatePoolsJson() to call glcoind RPC `listminers approved` and
# build the pool list dynamically. Stays in sync with on-chain registry.
python3 - "${POOLS_UPDATER}" <<'PY'
import sys, io
path = sys.argv[1]
with io.open(path, 'r', encoding='utf-8') as f:
    src = f.read()

MARKER = '/* GLCOIN_KYC_POOLS_PATCH */'
if MARKER in src:
    sys.exit(0)

def replace_method_body(src, sig):
    idx = src.find(sig)
    if idx < 0:
        raise SystemExit(f"FAIL: method signature not found: {sig}")
    brace_idx = src.find('{', idx)
    depth = 1
    end = brace_idx + 1
    while end < len(src) and depth > 0:
        c = src[end]
        if c == '{': depth += 1
        elif c == '}': depth -= 1
        end += 1
    return src[:brace_idx], src[end:]

before, after = replace_method_body(src, 'public async updatePoolsJson(): Promise<void>')
new_body = (
    "{\n"
    "    " + MARKER + "\n"
    "    if (config.MEMPOOL.ENABLED === false) return;\n"
    "    const now = new Date().getTime() / 1000;\n"
    "    if (now - this.lastRun < config.MEMPOOL.POOLS_UPDATE_DELAY) return;\n"
    "    this.lastRun = now;\n"
    "\n"
    "    try {\n"
    "      if (config.DATABASE.ENABLED === true) {\n"
    "        this.currentSha = await this.getShaFromDb();\n"
    "      }\n"
    "    } catch (e) { /* first run */ }\n"
    "\n"
    "    let miners: any[] = [];\n"
    "    try {\n"
    "      const rpcUrl = 'http://' + config.CORE_RPC.HOST + ':' + config.CORE_RPC.PORT + '/';\n"
    "      const auth = 'Basic ' + Buffer.from(config.CORE_RPC.USERNAME + ':' + config.CORE_RPC.PASSWORD).toString('base64');\n"
    "      const body = { jsonrpc: '1.0', id: 'mempool', method: 'listminers', params: ['approved'] };\n"
    "      const res = await axios.post(rpcUrl, body, { headers: { Authorization: auth, 'Content-Type': 'application/json' }, timeout: 10000 });\n"
    "      miners = (res.data && res.data.result) || [];\n"
    "    } catch (e: any) {\n"
    "      logger.warn('Glcoin listminers RPC failed: ' + (e && e.message), this.tag);\n"
    "      return;\n"
    "    }\n"
    "\n"
    "    const crypto = require('crypto');\n"
    "    const minersSha = crypto.createHash('sha256').update(JSON.stringify(miners)).digest('hex');\n"
    "    if (this.currentSha !== null && this.currentSha === minersSha) return;\n"
    "\n"
    "    const poolsJson: any[] = miners.map((m: any) => {\n"
    "      const label = String(m.display_name || m.kyc_id || m.address);\n"
    "      return {\n"
    "        id: parseInt(crypto.createHash('sha256').update(String(m.address || '')).digest('hex').slice(0, 7), 16) || 1,\n"
    "        name: label,\n"
    "        link: 'https://glcoin.org/miners/' + (m.kyc_id || ''),\n"
    "        addresses: [m.address],\n"
    "        tags: [],\n"
    "      };\n"
    "    });\n"
    "\n"
    "    poolsParser.setMiningPools(poolsJson);\n"
    "\n"
    "    if (config.DATABASE.ENABLED === false) {\n"
    "      logger.info('Glcoin miner pools loaded (' + poolsJson.length + ' approved miners, no database)', this.tag);\n"
    "      return;\n"
    "    }\n"
    "\n"
    "    try {\n"
    "      await DB.query('START TRANSACTION;');\n"
    "      await this.updateDBSha(minersSha);\n"
    "      await poolsParser.migratePoolsJson();\n"
    "      await DB.query('COMMIT;');\n"
    "      logger.info('Glcoin miner pools imported (' + poolsJson.length + ' approved miners)', this.tag);\n"
    "    } catch (e) {\n"
    "      logger.err('Could not migrate Glcoin miner pools: ' + JSON.stringify(e), this.tag);\n"
    "      await DB.query('ROLLBACK;');\n"
    "    }\n"
    "  }"
)
src = before + new_body + after

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(src)
print('# pools-updater.ts patched (KYC miner registry via listminers RPC)')
PY

# --- frontend: rebrand display unit "sat" -> "gsat" ---
# Glcoin Lightning Network displays gsat (gigasat is a misnomer here — gsat is
# the Glcoin display name for what Bitcoin calls satoshi; 1 gsat = 1 sat at
# the protocol level). Touches translation files and component templates only.
# Code identifiers, API keys with "satoshi" in their name, and on-the-wire
# JSON keys are NOT modified.
echo "# rebrand: sat -> gsat in mempool frontend display strings"

LOCALE_DIR="${REPO_DIR}/frontend/src/locale"
if [ -d "${LOCALE_DIR}" ]; then
  # Fee-rate label (primary user-visible string)
  find "${LOCALE_DIR}" -name 'messages*.xlf' -print0 \
    | xargs -0 -r sed -i \
        -e 's|sat/vB|gsat/vB|g' \
        -e 's|sat/WU|gsat/WU|g' \
        -e 's|>sat<|>gsat<|g' \
        -e 's| sat | gsat |g'
fi

TMPL_DIR="${REPO_DIR}/frontend/src/app"
if [ -d "${TMPL_DIR}" ]; then
  find "${TMPL_DIR}" \( -name '*.html' -o -name '*.ts' \) -print0 \
    | xargs -0 -r sed -i \
        -e 's|sat/vB|gsat/vB|g' \
        -e 's|sat/WU|gsat/WU|g'
fi

echo "# Glcoin mempool patches applied to ${REPO_DIR}"
