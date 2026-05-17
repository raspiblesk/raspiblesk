## What's new in Version 0.15.21 of RaspiBlesk?

Seven-bug app-stack sweep after v0.15.20 Pi flash. The full Phase A-G
test-matrix in `finalrun.md` came back green for the core stack (glcoind
+ kubo + electrs + LNbits-DB-auth + bleskapi-login), so v0.15.21 is a
pure app-layer fix without touching consensus or the boot-time
provisioning. All seven crashed silently in restart-loops or rendered
garbage labels — none were caught by the existing Phase A-G matrix
because the matrix only validated the core stack, not the bonus.* apps.

Bug AA — LNbits 5443 login + create-account return 500 "unexpected
error". Upstream LNbits pins `passlib==1.7.4` but never lists `bcrypt`
as a runtime dep, so `CryptContext(schemes=["bcrypt"]).hash()` raises
`MissingBackendError` on every password operation. Fix: `poetry add
bcrypt` after `poetry install` in `bonus.lnbits.sh` so the lockfile and
venv stay in sync (a bare pip-install in the venv would drift on the
next install rerun).

Bug CC + HH — Jam (joinmarket-api on :7501) and ob-watcher both
crash-loop with `JsonRpcConnectionError: RPC connection to Bitcoin Core
was not established`. Upstream `joinmarket.cfg` ships with `rpc_port`
empty (so joinmarket defaults to Bitcoin Core's 8332), `rpc_user=bitcoin`,
`rpc_password=password`. `bonus.jam.sh` previously only patched the
`max_cj_fee_*` knobs and the `onion_serving_port` collision with LND
REST — the BLOCKCHAIN section was left untouched. Fix: read live
`rpcuser`/`rpcpassword` from `/mnt/hdd/app-data/glcoin/glcoin.conf` and
pin `rpc_port=1617` in three new `sed` lines next to the existing
`max_cj_fee` patches.

Bug DD — Labelbase (:12349) crash-loop with "ModuleNotFoundError: No
module named 'django'" and "/home/labelbase/ENV/bin/gunicorn: No such
file or directory". `bonus.labelbase.sh`'s `pip install -r
requirements.txt` ran inside an inline `bash -c` that swallowed pip's
exit code, so a failed walk (network blip, py3.13/django version skew,
missing build deps) left an empty venv and the service ExecStart
literally could not find its two hard runtime deps. Fix: switch to `bash
-ec` so pip failures propagate, then add an explicit `pip install django
gunicorn` backstop so the service can at least start even if the full
requirements walk partial-failed.

Bug FF — LNDg gunicorn (:8889) crash-loop with
`ModuleNotFoundError: No module named 'pkg_resources'` on Python 3.13.
py3.13 dropped pkg_resources from stdlib (it was historically shipped
with setuptools, which is no longer installed by default into new
venvs). gunicorn 20.x imports pkg_resources at module load, so the LNDg
service died at every boot. Fix: explicit `pip install setuptools`
before the requirements.txt install, in both the install branch and the
update branch of `bonus.lndg.sh`.

Bug GG — Lightning Terminal (litd on :8443) crash-loop with
`could not load config: /home/lit/.lit/lit.conf:26: unknown option:
faraday.connect_glcoin`. Upstream litd/faraday only knows the historical
`faraday.bitcoin.*` keyspace — it treats Bitcoin Core as a generic
RPC-target regardless of which chain it indexes. A previous rename to
`faraday.connect_glcoin` / `faraday.glcoin.*` (invented namespace) made
litd refuse to load at all, taking down the whole Lightning Terminal
stack. Fix in `bonus.lit.sh`: use the upstream `faraday.bitcoin.*` keys
and point `faraday.bitcoin.host` at Glcoin's `localhost:1617`.

Bug JJ — glc-rpc-explorer (:3020) displays block-rewards as
`5,000,000,000 BTC` and the gear-menu "Display Currency" dropdown lists
literal `BTC` / `sat` instead of `GLC` / `gsat`. The v0.15.16 rebrand
block in `apply-glcoin-patches.sh` covered ` BTC `, `} BTC,`, and the
"Bitcoin Explorer" meta-tags but missed three patterns: the array
literal `["BTC", "sat"]` in `layout.pug`, the template-literal tail
`} BTC\`` in seven tooltip strings in `shared-mixins.pug`, and the
lowercase selector `displayCurrency == "btc"` in the same file. The
fourth detail is load-bearing: after rebrand the dropdown writes
cookies "glc"/"gsat" via `item.toLowerCase()` but the selector still
matched only "btc"/"sat" → values would silently fall through to
`span 0`. Fix: a new v2 patch block with its own
`GLCOIN_REBRAND_PATCH_V2` idempotency marker so it kicks in even on
installs already carrying the v1 marker, and four additional sed
patterns covering all four cases.

## What's new in Version 0.15.20 of RaspiBlesk?

Single-bug sweep after v0169 Pi flash exposed a long-latent typo in the
RASPIBLESK_LOGIN_PATCH itself. v0166 introduced the patch to replace
blitz_api's upstream password check with a `sudo -n blesk.passwords.sh
check a` shell-out — necessary because the upstream code's hash format
diverged from the `mkpasswd -m sha-512 -S <salt>` format the set-side
script writes into `/mnt/hdd/app-data/passwords/a.hash`. The patch body
worked end-to-end for the underlying script (`correct=1` returned from
sudo's PAM session, all six sub-sudo calls inside the script completed
cleanly), but the final return statement crashed every login attempt
with HTTP 500 before any JWT reached the cookie. The bug was invisible
in v0166-v0169 because the test plan in `finalrun.md` §E4 referenced
the wrong endpoint (`/api/auth/login`, which 404s) — the actual route
is `/api/system/login`, mounted from `app/system/router.py:48` with the
`/system` prefix from `app.include_router(system_router)` in `main.py`.
No Pi test ever hit the real handler, so the crash never surfaced
until this cycle when the WebUI itself called the right endpoint.

### Source-tree edits

- **Bug X — `RASPIBLESK_LOGIN_PATCH` returned `sign_jwt()["access_token"]`
  but `sign_jwt()` in `app/auth/auth_handler.py:21` returns a `str`, not
  a dict.** PyJWT >= 2.0 returns the encoded token as a plain string
  (the upstream `-> Dict[str, str]` type hint is stale documentation).
  Subscripting a `str` with `"access_token"` raises `TypeError: string
  indices must be integers, not 'str'` — caught by FastAPI's ASGI
  exception handler and surfaced as HTTP 500 `Internal Server Error`
  with `Exception in ASGI application` logged in the bleskapi journal.
  Additionally the raw return value (after the crash was hypothetically
  fixed) would not have matched `service.py:150 login()`'s
  `match result: case Ok(data)` block — Python's structural pattern
  matching falls through silently for a non-`Ok`/`Err` value, the
  function returns `None` implicitly, and the response cookie+body
  would have been broken. Fix in `home.admin/config.scripts/blesk.web.api.sh:534`
  replaces `return sign_jwt()["access_token"]` with `return Ok(sign_jwt())`
  — matching the canonical pattern in `app/system/impl/native_python.py:99`.
  `Ok` is already imported at module scope in `raspiblitz.py` (Z.21:
  `from app.external.result_type.src.result.result import Err, Ok, Result`)
  via the `_match_password` method's `return Ok(True)`, so no additional
  import injection is needed in the patch body.

- **Bug Z — `home.admin/assets/glcoin.conf` did not pin
  `seed.glcoin.ch` as a mainnet authority node.** The chainparams.cpp
  `vSeeds` list in `glcoin-0.2.2/src/kernel/chainparams.cpp:137-139`
  hardcodes `seed.glcoin.org` and `dnsseed.glcoin.org` for mainnet
  DNS-seeded peer discovery, but the operator's own seed authority at
  `seed.glcoin.ch` (`185.66.109.246` + `2a0e:f0c1:0:1870::100`) was
  never reachable without manual operator intervention after every
  reflash. Added `main.addnode=seed.glcoin.ch:1618` next to the
  existing `signet.addnode=seed.glcoin.org:31618` line. `addnode`
  semantics give permanent connection priority — unlike DNS-seeded
  peers which age out of `peers.dat` — so the authority node sticks
  across `peers.dat` rotations. Companion finding (deferred): when
  `tor.network.sh on` rewrites the conf to `onlynet=onion` +
  `dnsseed=0`, this `addnode` line still does not connect because
  no `.onion` Glcoin authority is currently hardcoded for the
  Tor-only path — operator currently flips `tor.network.sh off` for
  initial sync, then back on for privacy post-sync.

### LNbits app-activation triage (Bug Y2 surfaced after v0169 Bug-Y fix)

Activating LNbits through the post-flash wizard on v0.15.19 Pi
demonstrated that the v0169 Bug-Y fix (sudo-wrapped
`loadOrGenerateLNBitsDBPassword`) is fully green: the password file
+ reset-marker now persist as `lnbits:lnbits` `0600`, postgres user
authentication succeeds (no `InvalidPasswordError` in the journal),
and asyncpg connects to `lnbits_db` cleanly. But LNbits' first
migration immediately crashes the worker with a NEW schema-level
permission error, which surfaces as nginx **HTTP 502 Bad Gateway**
on the LNbits WebUI frontend.

- **Bug Y2 — PostgreSQL 15+ revoked `PUBLIC.CREATE` on schema
  `public`, breaking LNbits' first table create.** Until PG 14 the
  `public` schema allowed any role with database connect to
  `CREATE TABLE` in it. PG 15 changed the default so only the
  schema owner (`postgres` by default) may create objects; database-level
  `GRANT ALL ON DATABASE` does NOT cascade to schema-level privileges
  in modern PostgreSQL. `bonus.lnbits.sh:postgresConfig` previously
  granted only `ALL PRIVILEGES ON DATABASE lnbits_db TO lnbits_user`,
  which let LNbits connect but not create tables. The first migration
  `CREATE TABLE IF NOT EXISTS dbversions (db TEXT PRIMARY KEY, version
  INT NOT NULL)` raises `asyncpg.exceptions.InsufficientPrivilegeError:
  permission denied for schema public`, sqlalchemy translates this to a
  `ProgrammingError`, and loguru logs `Application startup failed.
  Exiting.` The worker never reaches `--port 5000 --host 0.0.0.0` so
  the listening socket never opens; nginx (reverse-proxying the LNbits
  HTTPS-frontend at :5443 to upstream :5000) sees connection-refused
  and returns 502 to the browser. Two-pronged fix added after the
  existing `grant all privileges on database` line:
  `alter schema public owner to lnbits_user;` transfers schema
  ownership so the user has implicit `CREATE`, plus
  `grant all on schema public to lnbits_user;` provides explicit
  belt-and-suspenders coverage against future PostgreSQL ACL-default
  resets. Both statements are scoped with `-d lnbits_db` so `public`
  resolves to the per-database schema, not the postgres-system-wide
  template.

### glc-rpc-explorer app-activation triage (3 bugs surfaced when operator activated the app on v0.15.19 Pi)

Activating glc-rpc-explorer through the post-flash wizard produced
HTTP 500 "Internal Server Error" on every WebUI page request. Three
independent bugs in the Glcoin patch-set, surfaced together by a single
journal capture during the v0169 Pi-test cycle:

- **Bug B1 — `BTCEXP_ADDRESS_API=none` is rejected by btc-rpc-explorer's
  enum parser.** `bonus.glc-rpc-explorer.sh:191` previously wrote
  `BTCEXP_ADDRESS_API=none` to the env file when no local Electrum
  server was ready, intending 'none' as a kill-switch. The upstream
  parser only accepts `blockchain.com`, `blockchair.com`,
  `blockcypher.com`, `electrum`, `electrumx`, or an absent variable
  — it surfaces `Error 32907ghsd0ge: Unrecognized value for
  BTCEXP_ADDRESS_API: 'none'. Valid options are: …` on startup before
  RPC verification, polluting the journal. Fix replaces the setter with
  `sed -i '/^BTCEXP_ADDRESS_API=/d'` so the line is deleted entirely
  when no Electrum server is up; the initial template
  (`bonus.glc-rpc-explorer.sh:372`) now has `BTCEXP_ADDRESS_API=`
  (empty, not `none`) so the prestart electrumx-substitute path still
  matches when electrs/fulcrum becomes ready.
- **Bug B2 — `loadMiningPoolConfigs` crashes with
  `ERR_INVALID_ARG_TYPE` because `global.coinConfig.ticker` is
  undefined.** `app.js:365` builds the mining-pool-configs directory
  path as `path.join(__dirname, "public", "txt",
  "mining-pools-configs", global.coinConfig.ticker)`. The Glcoin coin
  module in `home.admin/assets/glc-rpc-explorer/glc.js` had `name:
  "Glcoin"` but no `ticker` field — `path.join(..., undefined)` throws
  `TypeError [ERR_INVALID_ARG_TYPE]: The "path" argument must be of
  type string. Received undefined`, caught by Node's unhandled-rejection
  handler. Added `ticker: "GLC"` to `coinConfig` matching the
  `BTCEXP_COIN=GLC` env-var convention.
- **Bug B3 — `views/layout.pug:64` self-closing `img` with nested
  content surfaces as HTTP 500 `Internal Server Error`.**
  `apply-glcoin-patches.sh:167` ran a sed substitution that appended
  `/* GLCOIN_LOGO_FALLBACK_PATCH */` as a trailing in-line comment on
  the `img.header-image(src=..., alt="logo")` tag, both as patch
  marker for the idempotency check and as a self-documentation hint.
  Pug 3.x interprets any text on the same line after a tag's closing
  `)` as the tag's nested content; `img` is a self-closing element
  (`<img/>` in HTML5) and rejects content with the error message
  `img is a self closing element: <img/> but contains nested content`.
  The pug error surfaces as a 500 on every page render — the WebUI
  shows nothing but `<pre>Internal Server Error</pre>`. Fix removes
  the trailing `/* ... */` marker from the sed; the idempotency
  check at the top of the patch block now matches the patched src
  path itself (`grep -qF '"/img/logo/glc.png"'`) which is equally
  unique to the post-patch state and does not require an in-line
  marker.

### Build-pipeline edits (Schweizer Gründlichkeit audit of build_sdcard log)

Full-log audit of the v0169 `/var/log/raspiblesk/build_sdcard-20260517-005715.log`
(987 KB, 17206 lines, 82-minute build of 19 apps) classified every
warning/error/skip/retry pattern. The eight items below were fixed in
the same v0.15.20 source-tree cycle as Bug X + Bug Z; three more (F7 LND
commit-hash, N1 pip global retries, N3 blitz_api full offline-bundle)
deferred to v0.15.21+ for complexity reasons noted at the end.

- **Bug E1+E2 — SSH private key + admin sudo password leaked into the
  world-readable build log.** `build_sdcard.sh:484-493` echoed
  `${SSH_PRIVKEY}` and `${ADMIN_DEFAULT_PW}` to stdout, the exec-tee
  redirection at script-start (Z.117) mirrored them into
  `/var/log/raspiblesk/build_sdcard-${RUN}.log` which the build set to
  `0644 root:root`. Any account on the running Pi (including the same
  `admin` user whose SSH key was leaked) could `cat` the log and recover
  the build-time credentials, defeating the v0149 first-login-rotate
  defence. Fix in `build_sdcard.sh`: credentials are now written to
  `/root/.raspiblesk-credentials` (chmod `0600`, `root:root`) via a
  `umask 077` block; only the file path + retrieve/delete instructions
  are echoed; operator runs `sudo cat` (which does not enter the
  build-log) to capture them and `sudo shred -u` to delete after copying.
  Plus at end-of-script: `/var/log/raspiblesk/` is `chmod 0700` and
  every `*.log` inside is `chmod 0600 root:root` so even a released
  SD-card image cannot be mined for build metadata by an attacker
  holding only the admin SSH key.
- **Bug F1 — `bonus.lnbits.sh:30` `source /mnt/hdd/app-data/raspiblesk.conf`
  unconditional during build phase.** The conf file is only created by
  `_provision_.sh` post-flash, but `bonus.lnbits.sh install` runs
  during `build_sdcard.sh` (via `blesk.fatpack.sh:184`), producing
  `Zeile 30: /mnt/hdd/app-data/raspiblesk.conf: Datei oder Verzeichnis
  nicht gefunden` in the build log. Script continued only because
  `bash` was not run with `set -e`. The install action does not read
  any conf var (verified by inspection); guarded with
  `[ -f /mnt/hdd/app-data/raspiblesk.conf ] && source ...` so activation
  paths (`on`/`switch`/`off`) which run post-conf still source it.
- **Bug F2 — `systemctl restart networking` after `/etc/hosts` write.**
  `build_sdcard.sh:550` tried to restart the legacy ifupdown
  `networking.service`, which no longer exists on Debian 12 (trixie)
  — the system uses NetworkManager or `systemd-networkd`. The build
  log surfaced `Failed to restart networking.service: Unit networking.service
  not found.` on every run. A `/etc/hosts` edit does not require a
  network-stack restart anyway (the resolver re-reads the file on
  demand); the call is removed entirely.
- **Bug F3 — APT source duplicate write on Debian 12.** `build_sdcard.sh`
  Z.586-591 appended every entry of `REQUIRED_SOURCES` to
  `/etc/apt/sources.list` if `grep -Fxq` did not find it in either
  `/etc/apt/sources.list` or `/etc/apt/sources.list.d/debian.sources`.
  Debian 12 ships sources in DEB822 format (multi-line stanzas) in
  `debian.sources` which `grep -Fxq` (literal exact-line match) cannot
  reconcile against the single-line `deb http://...` format the script
  appends. Result: four "Ziel … ist mehrfach konfiguriert" warnings on
  every subsequent `apt-get update`. Fix wraps the append loop with
  `if [ -f /etc/apt/sources.list.d/debian.sources ]; then skip; fi`
  — Debian 12+ skips the legacy append entirely; older Debian without
  `debian.sources` retains the original per-entry append logic.
- **Bug F4 — `bitnodes.io` Bitcoin-only fallback node list step.**
  `blesk.fatpack.sh:133` invoked
  `curl https://bitnodes.io/api/v1/snapshots/latest/`. `bitnodes.io`
  exclusively tracks the Bitcoin network — its snapshot contains zero
  Glcoin peer addresses and is never read by any Glcoin code path
  (`fallback.bitnodes.nodes` is written then ignored). The fetch
  produced `curl: (6) Could not resolve host: bitnodes.io` in every
  Pi-based rebuild where DNS to that host was blocked or slow. Removed;
  only the Glcoin nodes-list fetch from
  `raw.githubusercontent.com/glcoin/glcoin/master/contrib/seeds/nodes_main.txt`
  remains, with the `assets/fallback.glcoin.nodes` seed-file copy at
  end of `build_sdcard.sh` as offline fallback.
- **Bug F5 — `blitz_api` pulled from `dev` branch HEAD on every build.**
  `blesk.web.api.sh:215-228` resolved the upstream branch to `dev` for
  any non-versioned `activeBranch`, with `GITHUB_COMMITORTAG=""`. Every
  `build_sdcard.sh` therefore landed on whatever the `fusion44/blitz_api`
  `dev` HEAD happened to be at clone-time, drifting the RASPIBLESK_FORK_PATCH
  + RASPIBLESK_LOGIN_PATCH apply surface silently between runs. Pinned
  `GITHUB_COMMITORTAG="62b6438970580d3c5269da8e1caf683607db491e"` —
  the commit the v0169 Pi-flash actually used (verified post-flash via
  `git -C /home/bleskapi/blitz_api log -1`). Both patches apply cleanly
  on this commit. Bump this string only after a newer upstream commit
  has been exercised end-to-end through a Pi reflash + WebUI login +
  setup-flow.
- **Bug C1 — `Could NOT find Doxygen` / `Could NOT find Valgrind` cmake
  probes.** `glcoin.install.sh:147` invoked cmake on `glcoin-0.2.2/src`
  without `-DWITH_DOC=OFF -DWITH_MAN=OFF`, so the build probed for
  `doxygen` + `dot` + `valgrind` (intentionally absent on the build
  image) and surfaced two "Could NOT find" warnings. Both cmake flags
  added; unknown vars produce a benign "Manually-specified variables
  were not used" line which is preferable to the noise from probing
  for absent tools.
- **Bug C4 — `WARNING: apt does not have a stable CLI interface. Use
  with caution in scripts.`** Multiple `bonus.*.sh`, `blesk.*.sh` and
  `cl-plugin.*.sh` scripts invoked `apt install`/`apt remove`/`apt update`/
  `apt purge`/`apt upgrade`/`apt autoremove` directly, producing the
  upstream Debian apt-wrapper warning seven-plus times per build.
  `sed -E 's/\bapt[[:space:]]+(install|remove|update|purge|upgrade|autoremove)\b/apt-get \1/g'`
  applied to 24 files across `home.admin/` and `build_sdcard.sh`. The
  pattern is whitespace-anchored (`apt[[:space:]]+`) so it does not
  match `apt-get install` already present. `apt-list`/`apt-show` and
  similar commands without a stable `apt-get` equivalent are left
  alone.

### Open findings deferred to v0.15.21+

These were observed during the v0169 Pi diagnostic + the build-log
audit but not fixed in v0.15.20 (complexity or risk profile):

- **Bug F7 — LND `lnd version 0.20.1-beta commit=` has empty commit
  hash.** The vendored LND build runs without a `.git` directory, so
  LND's own Makefile's `git describe --tags --always` produces empty
  output and the `-X github.com/lightningnetwork/lnd/build.Commit=`
  ldflag receives no value. Requires either passing
  `COMMIT=<sha>` to the Makefile via `make install COMMIT=<sha>` or
  patching the Makefile to honour a fallback env var. Cosmetic only;
  `lnd version` still prints `0.20.1-beta` correctly.
- **Bug N1 — pip retry storm on initial install** (7× SSL/Protocol
  retries against pypi during the Z.2819-2900 burst). All recovered
  via PyPI's own retry, but added ~20 seconds. Safer fix is
  `/etc/pip.conf` with `retries = 10` + `timeout = 60` early in
  `build_sdcard.sh`, but this could conflict with venv-local pip
  configs that downstream apps (poetry, uv) install.
- **Bug N3 — `blitz_api` is still pulled live from GitHub** (now at the
  Bug F5 pinned commit) instead of bundled as an offline tarball next
  to LND + CLN + Kubo. Full bundling requires fetching
  `https://github.com/fusion44/blitz_api/archive/62b6438970580d3c5269da8e1caf683607db491e.tar.gz`,
  SHA256-pinning it in `home.admin/assets/`, and rewriting
  `blesk.web.api.sh` to extract from tarball. Source-tree grows ~3 MB.
  Commit-pin (Bug F5) already buys most of the reproducibility benefit;
  full offline-tauglichkeit can wait.
- **`btc_default_sync_initial_done` Redis key hardcoded** somewhere in
  blitz_api — emits `Key 'btc_default_sync_initial_done' not found in
  Redis DB.` warning every 4 seconds in the bleskapi journal during
  setup-sync-info polling. Symptom of incomplete BTC->GLC fork
  localisation. Same class as the v0.15.16 Bug C5 (Bitcoin-specific
  echo message).
- **`lnd_macaroon cannot be null or empty` ValueError at bleskapi boot**
  — `app/lightning/impl/lnd_grpc.py:226` calls `config_get_hex_str`
  for the macaroon path before the LND wallet is unlocked (macaroon
  file only materialises post-unlock). The exception is caught by the
  loguru `runners.py` handler, app continues to "Application startup
  complete", but `/lightning/*` routes may fail until the bleskapi
  service is restarted after wallet unlock. Robust fix would be a
  retry loop in `LnNodeLNDgRPC.initialize` or a systemd `After=lnd.service`
  ordering with a unit-restart hook on macaroon-file existence.
- **`tor.network.sh on` rewrites `glcoin.conf` to `onlynet=onion` +
  `dnsseed=0` without hardcoding any `.onion` Glcoin authority** — leaves
  the node with 0 peers in Tor-only mode. Operator currently flips
  `tor.network.sh off` for initial sync, then back on for privacy
  post-sync. Fix requires either a known-good Glcoin `.onion` seed
  to add as `seednode=` in the Tor-on path, or keeping
  `dnsseed=1` and accepting that the DNS-seeded clearnet IPv4 peers
  cannot connect under `onlynet=onion`.

## What's new in Version 0.15.19 of RaspiBlesk?

Single-bug sweep after v0168 Pi flash exposed a long-latent privilege bug
in the LNbits postgres-password bootstrap. v0168 itself shipped Bug T
(electrs E0609) and Bug W (5001/5443) — both verified green on Pi during
this cycle. The LNbits service appeared `active` to systemd but its
worker stopped at startup with `asyncpg.exceptions.InvalidPasswordError`
for `lnbits_user`, port 5000 never bound, and the `db_password.conf` +
`.v0166-pw-reset.done` marker files were never persisted.

### Source-tree edits

- **Bug Y — `loadOrGenerateLNBitsDBPassword` performed unprivileged
  filesystem operations on a directory it didn't own.** `_provision_.sh:554`
  invokes `bonus.lnbits.sh on ${LNBitsFunding}` via `sudo -u admin`, but
  `/mnt/hdd/app-data/LNBits/` is created as `lnbits:lnbits 0755` by the
  on-flow itself (Z.910-912). The admin account is not in the lnbits
  group, so on the "others" tier it gets `r-x` — no write. Six file
  operations in `loadOrGenerateLNBitsDBPassword` (`bonus.lnbits.sh:38-71`)
  ran without `sudo`: `rm -f $LNBITS_DB_PASS_FILE` (Z.49), `mkdir -p`
  + `touch $LNBITS_DB_PASS_RESET_MARKER` (Z.55-56), `mkdir -p` (Z.62),
  `echo > $LNBITS_DB_PASS_FILE` (Z.67), `chmod 600` (Z.68),
  `chown lnbits:lnbits` (Z.69). Every one silent-failed as admin. The
  function is called twice per `on`-flow — once inside `postgresConfig`
  (Z.77) for `CREATE USER` + `ALTER USER` with `${LNBITS_DB_PASS}`, and
  once at Z.938 to write the `.env` `LNBITS_DATABASE_URL`. Because the
  password file never landed, `source $LNBITS_DB_PASS_FILE` (Z.60) was
  unreachable and both calls fell through to the `openssl rand` branch
  (Z.66) — generating two distinct passwords. The postgres user
  carried the first password, the `.env` URL carried the second, and
  every LNbits start-up authenticated with the wrong half. All seven
  filesystem ops in `loadOrGenerateLNBitsDBPassword` now run through
  `sudo` (or `sudo tee` for the redirect), and `source` is replaced
  by `LNBITS_DB_PASS=$(sudo grep ... | cut ...)` because the password
  file is still chmod 600 owned by lnbits — admin can't `source` it
  even after the write succeeds. `sudo test -f` replaces `[ -f ]` for
  the existence checks so the function reads its own state consistently
  regardless of who owns the parent directory.

## What's new in Version 0.15.18 of RaspiBlesk?

Post-v0.15.17 Pi-Test follow-up — closes two source-level bugs that the
v0167 FATPACK fix exposed once installation actually completed: an
incomplete electrs patch that broke the Rust build, and a long-latent
`127.0.0.1:5001` port collision between the Kubo HTTP API and the nginx
LNbits-HTTPS frontend.

### Source-tree edits

- **Bug T — `network_glcoin.patch` declared `genesis_header_hex` only on
  the configure_me-generated config, not on the hand-built `Config`
  struct that the rest of electrs actually consumes.** The v0166 patch
  added the field to `internal/config_specification.toml` and read it
  in `src/tracker.rs:41` (`&config.genesis_header_hex`), but tracker.rs
  receives `&config::Config` — the hand-built struct at
  `src/config.rs:125-148` — not the configure_me one. Compilation
  failed with `E0609: no field genesis_header_hex on type
  &config::Config`. Two new hunks added to `patches/electrs/network_glcoin.patch`:
  one extending the `pub struct Config` declaration with
  `pub genesis_header_hex: Option<String>,` after `signet_magic: Magic,`,
  the other extending the `Config { ... }` constructor literal at the
  end of `impl Config` with `genesis_header_hex: config.genesis_header_hex,`
  after `signet_magic: magic,`. End-to-end field flow now closed:
  configure_me TOML → internal::prelude::Config → hand-built Config →
  tracker.rs.

- **Bug W — `127.0.0.1:5001` port collision between Kubo HTTP API and
  nginx LNbits-HTTPS frontend.** Latent since v0155 when Kubo was made
  mandatory for Glcoin (its API is hardcoded at `127.0.0.1:5001` in
  four places: `kubo.install.sh`, `glcoin.conf`, the explorer
  `/ipfs-pins` view, and the miner module). nginx's
  `lnbits_ssl.conf` was still using the inherited-from-RaspiBlitz
  `listen 5001 ssl http2;` (plus `[::]:5001`), which binds
  `0.0.0.0:5001` *including* `127.0.0.1:5001`. Whichever service
  systemd brought up first won the bind, the other failed silently —
  if nginx won, glcoind's IPFS RPCs (auto-pin of glc1/glc2/glc3, OTP
  pads, ipfslinks DB) all broke; if Kubo won, the LNbits LAN-HTTPS
  frontend was unreachable. Migrated the nginx LNbits-HTTPS listener
  from 5001 to **5443** (HTTPS-convention, unused in the source tree).
  Six edits across four files (seven lines modified, since lnbits_ssl
  patches both IPv4 and `[::]` listen lines):
  - `assets/nginx/sites-available/lnbits_ssl.conf:4-5` `listen 5001` →
    `listen 5443` (both IPv4 and `[::]`)
  - `assets/nginx/sites-available/lnbits_tor.conf:17` `proxy_pass
    https://127.0.0.1:5001` → `5443`
  - `assets/nginx/sites-available/lnbits_tor_ssl.conf:20` same
  - `bonus.lnbits.sh:460` `echo "httpsPort='5001'"` → `5443`
  - `bonus.lnbits.sh:960` `ufw allow 5001` → `5443`
  - `bonus.lnbits.sh:1206` `ufw delete allow 5001` → `5443` (uninstall path)
  Kubo retains 5001 (four hardcoded mounts). Source-tree audit:
  `grep -rn ':5001' raspiblesk-src/` now matches **only** Kubo /
  glcoind / explorer references; no nginx hits.

### Spot-check (end-to-end, not literal-grep)

- electrs: `genesis_header_hex` must appear on **five** distinct
  source locations after patch application: TOML param block, struct
  field declaration, struct constructor literal, tracker.rs match arm,
  chain.rs Chain::with_genesis_header (via Chain::new path).
- 5443 migration: 6 hits in the source tree after edit, 0 remaining
  `5001` hits in nginx assets or bonus.lnbits.sh.
- No new ports, no new services, no consensus changes. Pi marker
  `.v0168-lnbits-port.done` documents the new port for users with an
  existing install (cosmetic — fresh installs see the new port
  directly).

## What's new in Version 0.15.17 of RaspiBlesk?

Post-v0.15.16 Pi-Test follow-up — one fatal build-time bug (the v0166
LOGIN-Patch regex did not recognise the upstream `blitz_api/dev`
method signature and aborted FATPACK before LNbits/electrs/RTL/explorer
were installed), plus one audit-grade cosmetic fix for three stderr
warnings the same installer emitted when the CLN data-directory did
not yet exist during fresh provisioning.

### Source-tree edits

- **Bug R — RASPIBLESK_LOGIN_PATCH param-regex did not handle class
  methods.** `blitz_api/dev` migrated `login()` from a free function
  into the `RaspiBlitzSystem` class, so the upstream signature is now
  `async def login(self, i: LoginInput):`. The v0166 patcher's
  `re.match(r"\s*(\w+)\s*:\s*(\w+)", params)` tried to parse
  `self, i: LoginInput` directly, found `self` not followed by `:`, and
  exited 1 with `unrecognised signature`. FATPACK aborted before any
  of LNbits, electrs, RTL, BTC-RPC-Explorer, Mempool, BlitzWebUI were
  installed. Fixed in `blesk.web.api.sh` by stripping a leading
  `self,` from the param string with a word-boundary anchored regex
  (`r"^\s*self\b\s*,?\s*"`) before the type-extraction match. The
  word boundary prevents false-stripping of `self_data: SelfData`.
  Free-function signatures (`password: str`, `i: LoginInput`,
  `login_data: LoginInput`) remain matched unchanged.

  Hardened end-of-function detection at the same site as
  defense-in-depth: the previous code stopped at the next sibling at
  the same indent (`async def|def|class|@`), which would silently
  overwrite to EOF if `login()` happened to be the last method in
  its class. Now also stops at the first non-blank line at strictly
  LESS indent (end of enclosing class) and takes the earlier of the
  two. Verified end-to-end against synthetic class files for both
  middle-method and last-method-in-class layouts, plus eight param
  signatures (incl. the `self_data` word-boundary trap and the
  degenerate bare-`self` case).

- **Bug S — CLN data-directory pre-create for silent provisioning.**
  Same blesk.web.api.sh install path emitted three stderr lines on
  fresh installs (`chmod: ... .lightning/glcoin: not found`,
  `chmod: ... lightning-rpc: not found`, `cat: .lightning/config:
  not found`) because the CLN binary is installed but has never run
  during provisioning, so the directory + socket are created on the
  first lightningd service start. Made the block idempotent: pre-create
  `/home/glcoin/.lightning/glcoin` as the glcoin service-user with
  `sudo -u glcoin mkdir -p`, touch the `config` file with the same
  ownership, silence the now-redundant `lightning-rpc` chmod with
  `2>/dev/null || true` (lightningd will respect the
  `rpc-file-mode=0660` we append to the config on first start). Switched
  the existence-check from `cat | grep -c` to `grep -c "..." file
  2>/dev/null` to drop the noisy useless-cat. No behaviour change on
  re-runs after CLN has started — chmod simply reasserts the already
  correct mode.

- **Block F — version-bump.** `_version.info` codeVersion="0.15.17",
  this CHANGES.md entry added at the top.

### Tarball + verification

- Build artifact: `raspiblesk-20260516-v0167.tar.gz`,
  single-nested under `raspiblesk-20260516-v0167/` (strip-components=1).
- Glcoin Core 0.2.3 unchanged (`glcoin-0.2.3-src.tar.gz` retained
  from v0166 build).
- All 17 v0165-baseline Pi-checks plus the 3 v0166-specific checks
  (electrs genesis header, LNbits URL-safe password, bleskapi
  RASPIBLESK_LOGIN_PATCH marker + sudoers + 200 on `/api/system/login`)
  remain the verification matrix — v0167 unblocks them by letting
  FATPACK finish.

## What's new in Version 0.15.16 of RaspiBlesk?

Post-v0.15.15 Pi-Test follow-up — three runtime-red bugs (electrs genesis
seed, LNbits asyncpg password parser, bleskapi /api/system/login 401),
two audit-grade hardenings discovered during the v0166 Block-D
edge-case sweep, plus a Bitcoin-specific user-facing echo retexted for
the young Glcoin chain.

### Source-tree edits

- **Bug H2 — electrs reseeded with Glcoin genesis.** v0164/v0165
  produced an electrs binary that called
  `bitcoin::constants::genesis_block(Network::Bitcoin)` on startup,
  seeding the in-memory chain with Bitcoin's genesis (000...ce26f).
  Glcoin's mainnet genesis is `6e605c9c…e9ed`, so on first block-1
  ingest electrs rejected the parent-link with `missing prev_blockhash:
  6e605c9c…` and entered a restart loop (957 restarts observed on the
  v0165 Pi). Fixed by passing the full 80-byte glcoin genesis header
  via a new `--genesis-header-hex` flag (added by `network_glcoin.patch`
  hunks against `internal/config_specification.toml`, `src/chain.rs`,
  `src/tracker.rs`, `src/config.rs`) and wired into the
  `bonus.electrs.sh` ExecStart. A `.v0166-genesis-reset.done` marker
  in `/mnt/hdd/app-storage/electrs/` wipes the wrong-seed DB exactly
  once per install run. SHA256d of the header verifies to
  `6e605c9c…e9ed`, exact match to the error-log block.

- **Bug Q — LNbits asyncpg InvalidPasswordError on URL-unsafe charset.**
  Pre-v0166 `bonus.lnbits.sh` generated DB passwords with characters
  from `+=<>?.-`, but asyncpg's `postgres://user:pw@host/db` URL parser
  rejects those without percent-encoding. lnbits crashed on startup
  with `asyncpg.InvalidPasswordError for "lnbits_user"` even though
  the user existed. Narrowed the charset to URL-safe alphanumerics
  (`A-Za-z0-9`, 32 chars × log2(62) ≈ 190 bits entropy). A
  `.v0166-pw-reset.done` marker in `/mnt/hdd/app-data/LNBits/`
  invalidates any pre-v0166 password file once, dropping the stale
  postgres user+db so the next `postgresConfig` recreates them with
  the URL-safe password.

- **Bug P-Followup — bleskapi /api/system/login 401 (PAM/sudo).**
  v0164 widened the password_valid charset regex (Bug P), but the
  v0165 Pi-Test still returned 401 on correct password because
  upstream blitz_api's `login()` verifies passwords with an algorithm
  that does not match the `mkpasswd -m sha-512 -S <salt>` hash format
  written by `blesk.passwords.sh` into `/mnt/hdd/app-data/passwords/a.hash`.
  Symptom in journal: three `pam_unix(sudo:auth) conversation failed
  for [bleskapi]` lines per failed login. Fixed by rewriting the body
  of the first `async def login()` found in
  `app/system/impl/{raspiblitz,native_python}.py` or
  `app/system/service.py` to shell out to
  `sudo -n blesk.passwords.sh check a <pw>` — same script the set-side
  used to write the hash, so a guaranteed match. Idempotent via a
  `RASPIBLESK_LOGIN_PATCH` marker grep'd recursively across `app/system/`.
  Paired with a new `/etc/sudoers.d/30_bleskapi_pwcheck` granting
  bleskapi a narrow `NOPASSWD: blesk.passwords.sh check a *` right
  (validated with `visudo -c` during provisioning, install aborts on
  parse error).

- **H-D2 hardening — postgres-side password drift in lnbits_user.**
  Block-D edge-case audit surfaced a degenerate rerun path (Marker
  present, `db_password.conf` manually deleted): `loadOrGenerate`
  generates a fresh URL-safe password, but `create user lnbits_user`
  silently no-ops because the user already exists, so the postgres-side
  password keeps its stale value while `db_password.conf` has the new
  one — lnbits then fails to connect even after the v0166 reset.
  Added an `ALTER USER lnbits_user WITH ENCRYPTED PASSWORD` step
  between `CREATE USER` and `GRANT` in `postgresConfig` so the two
  sides realign on every `postgresConfig` call regardless of how they
  got out of sync.

- **H-D3 hardening — tightened sudoers wildcard for bleskapi.**
  Original v0166 rule was `blesk.passwords.sh check *`; sudoers'
  `*` crosses argument boundaries (per sudoers(5) "Wildcards in
  command arguments"), so this happens to match the 3-arg
  `check a <pw>` cmd. Hardened to `check a *` — fnmatch-verified
  to reject misuse like `check b <pw>`, `check c <old> <new>`,
  `check /etc/shadow`, and 2-arg `check <onlypw>`. blesk.passwords.sh's
  internal `tr -dc` charset filter remains the second line of defence
  (returns `correct=0` on dirty input, login then 401s on
  `b"correct=1" not in stdout`).

- **Bug C5 — Bitcoin-specific echo in `bonus.electrs.sh`.** User-facing
  setup echo claimed "~18 hours and ~50Gb diskspace" for the electrs
  DB build — true for Bitcoin, wrong for Glcoin. The young Glcoin chain
  (~2k blocks at release time, 5-min target) syncs in seconds and grows
  the index ~80 MB/year. Echo retexted + the adjacent code comment
  ("Cheap: ~50 GB delete, +18h re-sync") adjusted to match real
  electrs-on-glcoin economics.

## What's new in Version 0.15.15 of RaspiBlesk?

Post-v0.15.14 install-time follow-up — a single source-tree edit to fix
the LNbits install path. The v0164 build on the vboxuser machine showed
18/19 components green, with LNBITS the only red entry. Build-log
diagnosis (`/var/log/raspiblesk/build_sdcard-20260515-132348.log` lines
10277–10318) pinned the failure precisely.

### Source-tree edits

- **C4 follow-up — poetry lockfile re-render after pyproject widening.**
  The v0164 C4 sed-patch correctly widened `pyproject.toml`'s
  `python = "..."` constraint to `>=3.10,<3.14` (verified in log:
  echo `# pyproject.toml python-version widened to include 3.13`). But
  the subsequent `poetry install` (`bonus.lnbits.sh:767`) failed with
  `pyproject.toml changed significantly since poetry.lock was last
  generated. Run \`poetry lock\` to fix the lock file.` Poetry 2.x
  refuses install outright on hash mismatch where 1.x only warned;
  upstream LNbits v1.2.1 ships a lockfile generated against the
  un-widened pyproject, so any version-widening patch invalidates the
  lock-hash. Added a `sudo -u lnbits poetry lock` step between
  `poetry env use` and `poetry install` to re-render the lockfile
  conservatively (no dep upgrades, just re-hash against the patched
  pyproject). Fails the install hard on `poetry lock` error rather than
  letting the silent hash-mismatch take down the subsequent step.

## What's new in Version 0.15.14 of RaspiBlesk?

Post-v0.15.13 Pi-Test follow-up — eight fixes addressing the three rote
v0163 criteria (electrs, lnbits, explorer-logo) plus four newly-discovered
fork-rebrand bugs that surfaced during a charset audit of the WebUI login
path.

### Source-tree edits

- **C1 fix — explorer logo was the wrong PNG.** `glc.png` in
  `home.admin/assets/glc-rpc-explorer/` was byte-identical with Bitcoin
  Core's `bitcoin256.png` (Glcoin Core upstream never replaced
  `share/pixmaps/glcoin*.png` on the file level — they are renamed copies
  of the Bitcoin originals). Replaced with the canonical Glcoin logo from
  `glcoin.org/static/img/glcoin-logo.png` (1024×1024 RGBA, SHA
  `a181cb30…eaa1`).

- **C4 fix — LNbits `pyproject.toml` Python-version widening was a no-op.**
  `bonus.lnbits.sh:708-710` used `|` as both the sed delimiter AND inside
  the pattern (`~3.12 | ~3.11 | ~3.10`); sed parsed the first `|` as
  pattern-end and skipped the substitution. Switched to `#` delimiter and
  generalized the pattern to `^python = "..."` so it accepts any upstream
  syntax (`~3.10|~3.11|~3.12`, `^3.10`, `>=3.10,<3.13`) and rewrites it to
  `python = ">=3.10,<3.14"`.

- **H fix — electrs P2P magic mismatch (Bug H still rot in v0163).** The
  `network_glcoin.patch` only mapped `glcoin → Network::Bitcoin` for
  `FromStr`. The `bitcoin` crate's `Network::Bitcoin::magic()` returns
  `0xf9beb4d9`, but Glcoin mainnet uses `0xf9b4b4d9` (one byte off).
  electrs P2P handshake to glcoind failed on byte #2 → block-fetcher
  channel died → `recv() = err("empty and disconnected channel")` on every
  restart. Added Hunk #3 to `network_glcoin.patch`: the magic-resolution
  match in `config.rs:254-267` now accepts `signet_magic` overrides on
  `Network::Bitcoin` as well as `Network::Signet`. The electrs systemd
  unit (`bonus.electrs.sh:566`) now passes `--signet-magic=f9b4b4d9`.
  Additionally, the install path nukes any stale `db/bitcoin/` index via a
  `.v0164-reset.done` marker — `/mnt/hdd/app-storage/` survives re-flashes
  and a Bitcoin-magic header in the leveldb would cause a different crash
  on first start of the patched binary.

- **P fix — blitz_api fork-rebrand patch (`RASPIBLESK_FORK_PATCH`).** A
  charset audit of the WebUI 401 traced through `POST /api/system/login`
  to `app/repositories/system.py::password_valid()`:
  `re.match("^[a-zA-Z0-9]*$", password)`. Upstream blitz_api forbids ALL
  special characters, but `blesk.passwords.sh:62,219` accepts
  `A-Za-z0-9!@#%^&*()_+=<>?.-`. Any password A containing a special char
  was hashed correctly by the setup script and accepted by SSH, then
  rejected by the WebUI's format-regex BEFORE the hash check ran — 401
  with no further diagnostic. Same audit caught two more hardcoded
  RaspiBlitz paths (`setup.py:19,20`: `/var/cache/raspiblitz/temp/raspiblitz.setup`,
  `/mnt/hdd/raspiblitz.conf`) and one in `apps.py:219` (install-log path).
  `blesk.web.api.sh` now runs an idempotent sed block immediately after
  `git checkout` that widens the password regex to the
  RaspiBlesk-accepted charset and rewrites all three paths to the
  raspiblesk equivalent. Each substitution is verified with a marker grep
  — sed's silent no-op-on-no-match is detected as a build error.

- **P2 — symlink loop extended.** `blesk.web.api.sh:457` now creates the
  `blitz.systemd.sh → blesk.systemd.sh` symlink in addition to the five
  v0162 symlinks (debug, shutdown, migration, backupdevice, passwords).
  blitz_api's `system_docs.py` references `blitz.systemd.sh` in OpenAPI
  example strings; while not a runtime crash, the symlink costs nothing
  and prevents documentation-driven users hitting a broken example.

- **P3 — `dialogPasswords.sh` misleading charset hint.** The setup dialog
  said "only special characters - or ." but `blesk.passwords.sh` accepts
  `!@#%^&*()_+=<>?.-`. Aligned the dialog text with the actual allowed
  charset so users see the real rule.

- **D1 — display rebrand sat → gsat sweep continued.** The C7/C8 patches
  in v0163 handled RTL and Blesk Web-Admin i18n files. v0164 closes the
  shell/Python/JSON display-layer gaps that those sed-passes don't reach:
  `00infoBlitz.sh` (MOTD Wallet/Channels/Fee Report, 4 lines), `99lndMenu.sh`
  (channel-help text), `lnd.balance.sh` (audit-table rows), `bonus.lnbits.sh`
  (funding-source echo), `glcoin_miner.py` (anchor + template logs),
  `blesk.check-invoice-wrap.py`, `blesk.subscriptions.ip2tor.py` (display
  format), and `raspiblesk-grafana-dashboard.json` (two panel titles).
  Protocol/internal/proper-noun strings left intact (BBcreateInvoice.sh's
  CLN-invoice unit suffix, `base_fee_msat` TOML key, `stacking-sats-kraken`
  product name, `glcoin_miner.py:574` `sats =` variable, the rebrand
  scripts' own sed-target patterns).

## What's new in Version 0.15.13 of RaspiBlesk?

Post-v0.15.12 Pi-Test sweep — bundles Glcoin Core **0.2.3** (two source
fixes) plus seven RaspiBlesk patches.  All edits verified by an
incremental x86_64 sanity build of `glcoind` from the bundled Glcoin
0.2.3 source tree.

### Glcoin Core 0.2.3 (new source tarball `glcoin-0.2.3-src.tar.gz`)

- **Bug I — getblocktemplate placeholder coinbase rejected by KYC
  consensus check.** The external Glcoin CPU miner crash-looped with
  `getblocktemplate: TestBlockValidity failed: miner-not-permitted,
  coinbase does not pay to a KYC-approved miner address` because
  `interfaces::Mining::createNewBlock()` was called without a
  `coinbase_output_script`, leaving the placeholder coinbase output
  empty. `TestBlockValidity` then invoked the Glcoin
  miner-permission consensus check (`validation.cpp:4385-4410`)
  against the empty `scriptPubKey`, which never matches an approved
  miner address, so every template was rejected.
  - `src/node/types.h`: added `bool test_block_validity{true}` to
    `BlockCreateOptions`.
  - `src/node/miner.h`: removed the now-shadowing `test_block_validity`
    field from `BlockAssembler::Options` (inherited from the base).
  - `src/rpc/mining.cpp:937`: `getblocktemplate` now calls
    `miner.createNewBlock({.include_dummy_extranonce = true,
    .test_block_validity = false}, /*cooldown=*/false)`. The real
    KYC check still runs at `submitblock` via
    `BIP22ValidationResult(TestBlockValidity(...))` (line 810).
  - Consensus is unchanged — only the template-build sanity-check is
    skipped, matching the semantics of every other Bitcoin Core fork
    that uses an external miner.

- **Bug O — electrs / bitcoincore-rpc 0.19.0 deserialise failure.**
  `electrs.service` (and any other client using `bitcoincore-rpc
  0.19.0` — fulcrum, mempool-backend, ...) was crash-looping with
  `Error: bitcoind RPC polling failed / daemon not available / the
  JSON result had an unexpected structure`. Root cause was that
  `Client::get_blockchain_info()` checks `version()? < 190000` and
  branches into a legacy softforks-reshape path when the daemon
  reports a sub-19xxxx version. Glcoin's `CLIENT_VERSION = 202`
  (`0.2.2` = `10000*0 + 100*2 + 1*2`) was always below the threshold,
  triggering the legacy path against a modern (post-Bitcoin-Core-25)
  JSON shape — serde deserialize bailed out.
  - `src/rpc/net.cpp:694`: `getnetworkinfo` now reports
    `version = std::max(CLIENT_VERSION, 310000)`, matching the
    upstream Bitcoin Core base (31.x) this fork rebases on. The
    Glcoin-native version is preserved verbatim in the new
    `glcoin_version` field, and the BIP-14 `subversion` string
    (`"/Gsatoshi:0.2.3/"`) keeps the fork identity for peer
    discovery.

- **C9 — `sat/satoshi` → `gsat/gsatoshi` in RPC help and result
  descriptions.**  Glcoin's Lightning Network uses `gsat` as the
  display unit; this aligns `glcoin-cli help`, RPC JSON descriptions,
  and error messages with the rest of the UI stack. Touches
  `src/rpc/*.cpp` and `src/wallet/rpc/*.cpp` in display strings only —
  code identifiers (`satoshi*` variables, `CAmount`, etc.) and the
  upstream `// Copyright (c) 2010 Satoshi Nakamoto` line are left
  untouched.

### RaspiBlesk patches

- **C1 — glc-rpc-explorer "Bitcoin" branding + missing logo.**
  `home.admin/assets/glc-rpc-explorer/glc.js` switched the currency
  unit name `"glcsat"` → `"gsat"` (with `glcsat`/`sat` retained as
  parser aliases) and all logo URLs to `/img/logo/glc.png`. The
  Glcoin 256×256 PNG mark (taken from `glcoin-0.2.3-src/share/pixmaps/
  glcoin256.png`) is now shipped alongside the explorer assets and
  installed by `apply-glcoin-patches.sh`. The same script gained an
  idempotent sed pass (marker: `GLCOIN_REBRAND_PATCH`) that rewrites
  hardcoded `Bitcoin Explorer` → `Glcoin Explorer`, `Bitcoiners` →
  `Glcoiners`, `BTC` → `GLC`, `sat/vB` → `gsat/vB`, `satoshi` →
  `gsatoshi` in `views/*.pug` and `app/*.js` (excluding
  `app/coins/`).

- **C2 / C3 — Silver-peg ratio + `sat/vB` → `gsat/vB` in mempool.**
  The default peg in `home.admin/assets/mempool-silver/
  apply-silver-patch.sh` is now `GLC_SILVER_GRAMS_PER_GLC=1e6`
  (1 gsat = 0.01 g Ag — a 140-vB tx at 1 gsat/vB ≈ 1.4 g Ag,
  matching real-world silver pricing). The same script now also
  rebrands `sat/vB` → `gsat/vB` in `frontend/src/locale/messages*.xlf`
  and `frontend/src/app/**/*.{html,ts}`. `bonus.mempool.sh` header
  comment updated accordingly.

- **C4 — LNbits install failure on Debian Trixie (no python3.12 in
  apt).**  `bonus.lnbits.sh` now (a) widens the LNbits
  `pyproject.toml` python requirement from `~3.10|~3.11|~3.12` to
  `~3.10|~3.11|~3.12|~3.13` via a sed pass after `git checkout`,
  (b) extends the interpreter-search loop to accept
  `/usr/bin/python3.13`, (c) raises the upper Python bound from 3.12
  to 3.13 in both the loop and the system-fallback branch, and
  (d) returns `exit 1` (not `exit 0`) when no compatible interpreter
  is found, so the caller does not silently enable a broken service
  unit.

- **C5 — `menu` / `repair` commands fell back to the shell after
  every action.**  `home.admin/_commands.sh` wrapped the `menu()`
  and `repair()` functions in a `while ./00mainMenu.sh; do :; done`
  loop. `00mainMenu.sh` forwards the exit code of the chosen submenu
  — without the loop, every successful submenu (exit 0) returned to
  the bash prompt instead of redisplaying the menu. Mirrors the
  outer loop in `00raspiblesk.sh:78-86`.

- **C6 — Specter Desktop install pinned at an incompatible
  version.**  `bonus.specter.sh` bumped `pinnedVersion` from
  `2.1.1` (2024, not Python-3.13 compatible — pip install bailed out
  silently) to `2.1.8` (current PyPI, `requires_python >=3.7,<4.0`).

- **C7 — RTL Lightning UI `sat`/`Sats` → `gsat`/`gsats`.**
  `bonus.rtl.sh` gained a sed block (after `git verify`) that
  rebrands display strings in `src/{*.html,*.json}` only; TypeScript
  identifiers and the on-wire BOLT-protocol values are untouched.

- **C8 — Blesk WebUI i18n `sat` → `gsat`.**  `blesk.web.ui.sh`
  applies a sed pass over `src/i18n`, `src/locale`, `src/locales`,
  `public/locale`, `public/locales`, and `src/assets/i18n` JSON
  files just before `npm run build`. TSX/JSX source is left alone to
  avoid renaming code identifiers like `satsAmount`.

### Operational notes

- The Glcoin source bundle path changed: every reference to
  `glcoin-0.2.2-src.tar.gz` in `build_sdcard.sh` and
  `home.admin/config.scripts/glcoin.install.sh` has been pointed at
  `glcoin-0.2.3-src.tar.gz`.

- All seven RaspiBlesk patch scripts pass `bash -n` syntax checks.
  The Glcoin 0.2.3 source compiles cleanly via an `x86_64` sanity
  build (`cmake -G Ninja` + `ninja glcoind` with both
  `ENABLE_WALLET=OFF` and `ENABLE_WALLET=ON`).

- The Glcoin-side legacy `chain="glcoin"` masquerade is unchanged;
  Bug O is fixed entirely by reporting a Bitcoin-Core-compatible
  `version` field, with the native version preserved as
  `glcoin_version`.

---

## What's new in Version 0.15.12 of RaspiBlesk?

Bug-hunt sweep on top of v0.15.11 (which had landed Gate-2: Explorer
EnvironmentFile, Kubo Gateway 5080, bleskapi=on default, blitz_api
Glcoin masquerade). Pi diagnostics on the v0.15.11 build surfaced
nine follow-ups; this release packages them as source-tree-only
fixes (no Pi in-place patches, only a fresh tarball reinstall).

### Bug A — bleskapi crashed at `blitz.debug.sh`

`blitz_api` runs the RaspiBlitz platform module (because we masquerade
with `BAPI_PLATFORM=raspiblitz` in v0.15.11 until a proper Glcoin fork
of blitz_api exists). That module hard-codes
`/home/admin/config.scripts/blitz.*.sh` paths, but RaspiBlesk renamed
all of those to `blesk.*.sh`. Fix: `blesk.web.api.sh on` now creates
`blitz.{debug,shutdown,migration,backupdevice,passwords}.sh` symlinks
pointing at the matching `blesk.*.sh`. Idempotent. Also fixes the
secondary PAM/sudo spam in the journal (60-second restart loop was
the root cause of every `pam_unix(sudo:auth): conversation failed`).

### Bug B — kubo crashed on `denylists: permission denied`

Kubo v0.41's nopfs plugin walks `${HOME}/.config/ipfs/denylists/` at
daemon start. The v0.15.11 service unit had `ProtectHome=true`, which
hides `/home/*` from kubo's namespace — lstat aborts with EACCES
*before* any permission check runs. Fix in `kubo.install.sh`:

  - service unit: `ProtectHome=tmpfs` + `BindPaths=${KUBO_HOME}` so
    the kubo home is the only `/home` entry visible
  - `ensure-datastore` pre-creates `${KUBO_HOME}/.config/ipfs/denylists`
    owned `kubo:kubo` 0755 — defense in depth in case nopfs is ever
    upgraded to require the dir present even when empty

### Bug D — glc-rpc-explorer index `Cannot read properties of undefined (reading 'main')`

`app/utils.js:1462` in `nextHalvingEstimates` does
`coinConfig.halvingBlockIntervalsByNetwork[global.activeBlockchain]`.
Our `glc.js` coin module mirrored a stale subset of `btc.js@8ed77ab`
and was missing 8 of the 15 `*ByNetwork` fields btc-rpc-explorer
indexes by chain name. With `activeBlockchain="main"`, the access
returned `undefined` and crashed the index render.

Fix: `assets/glc-rpc-explorer/glc.js` now ships every `*ByNetwork`
field btc.js carries, with Glcoin parameters where they matter
(halvingBlockInterval 210000, terminalHalvingCount 32, maxSupply
21M) and empty-but-typed stubs everywhere else.

### Bug E — `tail: cannot open '/mnt/hdd/app-storage/glcoin/debug.log'`

`network.txindex.sh status` (called from `00infoBlitz.sh`'s INFO
loop) tail'd debug.log from `/mnt/hdd/app-storage/${network}` —
that's the blockchain data path, NOT the conf/state path. Glcoin's
`debuglogfile=` directives in `assets/glcoin.conf` point at
`/mnt/hdd/app-data/glcoin{,/testnet3,/signet}/debug.log`. Fix:
switch path to `app-data`, add `signet`/`regtest` cases to the
`pathAdd` chain detector, and guard the tail with `2>/dev/null`.

### Bug H — electrs crash-loop `unknown variant 'glcoin'`

The `network_glcoin.patch` against romanz/electrs `src/config.rs`
extends `BitcoinNetwork::FromStr` to accept `"glcoin"` (mapping it to
`Network::Bitcoin` internally). That covers electrs's CLI parser (via
`configure_me` → `FromStr`) but NOT the `config.toml` parser (via
`serde::Deserialize` directly on `bitcoin::Network`, which enumerates
only `bitcoin/testnet/testnet4/regtest/signet`).

v0.15.11 generated `network = "glcoin"` in config.toml — which failed
*before* any custom code could intercept. 82 restarts in 82 minutes.

Fix in `bonus.electrs.sh`:

  - move `network = "glcoin"` out of `config.toml`
  - pass `--network=glcoin` in the systemd `ExecStart` (CLI path, patched)
  - `StartLimitInterval=600` + `StartLimitBurst=10` to stop crash
    loops from flooding the journal
  - source-build path: fail loud if the patch file is missing AND
    grep `src/config.rs` post-apply to confirm the patch took effect
    (defensive against a corrupted .patch silently no-op'ing)

### Bug J — `rpcbind` listening on `0.0.0.0:111`

NFS portmapper pulled in transitively, exposed on every interface.
RaspiBlesk is not an NFS server. Fix: `systemctl mask
rpcbind.service rpcbind.socket` in the `*** HARDENING ***` section
of `build_sdcard.sh`. Mask (not just disable) prevents socket
activation re-enabling it.

### Bug K — Tor hidden services missing for `glcoind` and `lndrest`

`tor.network.sh on` created hidden services for the web UI,
debuglogs and most bonus apps, but NOT for glcoind P2P or LND REST.
glcoind already opens `127.0.0.1:1619` for `bind=…=onion`-style
inbound, so the missing piece was a `HiddenServicePort 1618
127.0.0.1:1619` entry. LND REST needed `HiddenServicePort 443
127.0.0.1:8080`. Both added unconditionally (glcoind) /
LND-conditional (lndrest) to `tor.network.sh`. Means glcoind is no
longer a Tor leech when `runBehindTor=on`.

### Bug N — UFW dead rules and over-broad allows

  - `_provision_.sh`: removed dead `ufw allow 19735 # lightning
    testnet` (testnet isn't installed by default; rule was pure
    noise in `ufw status`)
  - `blesk.web.api.sh`: bleskapi dev port 11111 was `Anywhere` —
    scoped to localhost + LAN
  - `lnd.install.sh`: LND REST 8080 and gRPC 10009 were `Anywhere` —
    scoped to localhost + LAN (the admin macaroon carries fund-
    movement authority; remote access goes through the new lndrest
    Tor hidden service)
  - LND P2P 9735 stays `Anywhere` (that's the Lightning peer port)

### Silver-peg adjustment

`mempool` was rendering fees as `420,00 g Ag` for a default 1
sat/vB transaction (140 vB × 1 sat × 3 g/sat). Simplified peg to
`1 gsat = 1 g Ag` (`GLC_SILVER_GRAMS_PER_GLC=1e8` instead of `3e8`)
in `apply-silver-patch.sh` + matching doc comment in
`bonus.mempool.sh`.

### Operational notes that are NOT code bugs

  - **Bug F (LND `Waiting for chain backend to finish sync`)**:
    LND's chain-sync goroutine treats a chain that hasn't seen a
    new block in days as "still synchronising". Mining a single
    block unblocks it. Not a code fix — chains with active miners
    don't hit this.
  - **Bug I (consensus vs `listminers approved` mismatch)**: the
    glcoin-miner service still dies with `miner-not-permitted` for
    an address that `listminers approved` shows as approved. This
    is a Glcoin Core 0.2.x issue — `TestBlockValidity` reads a
    different miner-registry path than the `listminers` RPC. Fix
    belongs in Glcoin 0.2.3, NOT in RaspiBlesk. Tracked as the
    primary open task post-v0.15.12.

### Files changed

  - `build_sdcard.sh` (mask rpcbind)
  - `home.admin/_version.info` → `0.15.12`
  - `home.admin/_provision_.sh` (UFW)
  - `home.admin/config.scripts/blesk.web.api.sh` (Bug A + UFW)
  - `home.admin/config.scripts/bonus.electrs.sh` (Bug H, four edits)
  - `home.admin/config.scripts/bonus.mempool.sh` (silver-peg comment)
  - `home.admin/config.scripts/kubo.install.sh` (Bug B, two edits)
  - `home.admin/config.scripts/lnd.install.sh` (UFW)
  - `home.admin/config.scripts/network.txindex.sh` (Bug E)
  - `home.admin/config.scripts/tor.network.sh` (Bug K)
  - `home.admin/assets/glc-rpc-explorer/glc.js` (Bug D)
  - `home.admin/assets/mempool-silver/apply-silver-patch.sh` (silver-peg)

---

## What's new in Version 0.15.10 of RaspiBlesk?

Gate-1-Release: LND wallet usability restored. End-to-end-tested on the
current author Pi (`raspberrypi`, v0.15.9 baseline) — symptoms isolated,
fixes targeted, audit-grade source-only changes.

### Root cause — LND `unsupported net Unknown BitcoinNet (3652498681)`

LND v0.20.1-beta started cleanly under our v0.15.9 build (wallet
unlocked, chain backend connected, Taproot probe passed via the new
buried deployment in glcoin 0.2.2). But every wallet RPC failed:

```
[ERR] RPCS: [/lnrpc.Lightning/WalletBalance]:
    failed to retrieve account public key:
    unsupported net Unknown BitcoinNet (3652498681)
```

`3652498681 == 0xd9b4b4f9` is Glcoin's mainnet network magic. The error
originates in btcwallet's `cloneKeyWithVersion` (and two siblings in
`wallet/import.go`, `internal/legacy/keystore/keystore.go`) which all
branch on `wire.MainNet` as a *typed constant*. Our `btcd_glcoin_params.go`
override does `chaincfg.MainNetParams = GlcoinMainNetParams`
(`Net = 0xd9b4b4f9`), but the `wire.MainNet` *constant* in
`btcd/wire/protocol.go` stayed at Bitcoin's `0xd9b4bef9`. The two values
no longer agree; the switch hits `default:` for every wallet operation.

### Fix — wire-level magic patch

`lnd.install.sh` now applies a one-line source patch to btcd's
`wire/protocol.go` in BOTH build paths (vendored bundle + standalone
clone):

```
MainNet BitcoinNet = 0xd9b4bef9   →   0xd9b4b4f9
```

Idempotent helper `_patch_btcd_wire_magic()` detects already-patched
state and fails closed if the expected Bitcoin pattern is missing
(better to break the build loudly than ship a wallet-broken LND). With
this single edit, all three btcwallet switches resolve their
`case wire.MainNet:` arm to Glcoin's magic — no per-call-site btcwallet
patches needed.

To force the source-compile path on existing Pis (the r2 prebuilt was
built before this patch existed and ships the bug):

- `LND_CACHE_REV` bumped `r2` → `r3` — old `/tmp/...-r2-...` is removed
- `SHA256_LND_PREBUILT_arm64=""` (empty) — any prebuilt found will be
  discarded with a WARN and the install falls through to source-compile
- The stale `assets/lnd-glcoin-0.20.99-beta-r2-linux-arm64.tar.gz`
  prebuilt was deleted (-36 MB)

Cost: ~30–60 min source-compile on Pi 5. Audit-grade reproducibility:
patches live in `raspiblesk-src/`, not in a black-box prebuilt.

### glc-rpc-explorer: three fixes

Service ran ("active running") but answered nothing — Pi diagnosis
revealed three independent bugs in `bonus.glc-rpc-explorer.sh`:

1. **`LogLevelMax=4` in service unit** dropped every Node/Express log
   line (INFO = level 6). `journalctl -u glc-rpc-explorer` returned
   `-- No entries --` for hours, masking startup failures. Removed,
   added `Environment=NODE_ENV=production` and `Environment=DEBUG=*`.
2. **`glcrpcexplorer` user not in group `glcoin`.** The prestart script
   reads `/mnt/hdd/app-data/glcoin/glcoin.conf` to extract
   `rpcpassword`, but the conf has been mode `0640 owner glcoin:glcoin`
   since the v0149 audit. `cat` failed silently → `RPCPASSWORD=""`.
   Fix: `sudo usermod -a -G glcoin glcrpcexplorer` after adduser.
3. **Self-corrupting prestart.** Earlier code unconditionally wrote
   `BTCEXP_BITCOIND_PASS=${RPCPASSWORD}` even when `RPCPASSWORD` was
   empty — so every service restart blanked the password and broke the
   next start. Fix: detect empty, leave existing `.env` value untouched,
   log a WARN with repair hint. Also: stop logging the password
   in plaintext into the journal (now logs `length=N` only).

### build_sdcard.sh: persistent install log

Audit-grade reproducibility requires every install run be reconstructable
after first boot. `build_sdcard.sh` now mirrors stdout+stderr through a
line-buffered `tee` into `/var/log/raspiblesk/build_sdcard-<ts>.log`
(symlink `latest.log`). Child scripts inherit the redirection
automatically (no per-installer patches). The EXIT-trap
`print_build_summary` echoes the log path at the end.

Follow live:
```
sudo tail -f /var/log/raspiblesk/latest.log
```

### Out of scope (deferred to v0.15.11)

Three findings from this session that are real but not Gate-1:

- **Kubo `226/NAMESPACE` restart loop, empty `ipfs init` repo** — even
  on v0.15.9 builds. Storage-order fix didn't fully resolve. Needs
  service-unit + install-script review (Task #10).
- **CONSENSUS vs `listminers approved` mismatch** —
  `getblocktemplate` rejects `gc1q9zvkt40…` with
  `miner-not-permitted`, while `listminers approved` (via mempool's
  pools-updater) returns the same address as approved. Two glcoind code
  paths give contradictory answers. Audit-grade concern (Task #11).
- **Port collision risk** — LND REST 127.0.0.1:8080 vs Kubo Gateway
  127.0.0.1:8080 (Task #12).

Chain at 1155 since 2026-05-09. Confirmed by author: operationally
intentional, no harm to chain integrity or Gate-1 verification.

---

## What's new in Version 0.15.9 of RaspiBlesk?

Build-order fix for the storage-layout initialisation. v0.15.8 booted into
the first-boot dialog and aborted with
`error='/mnt/hdd/app-storage is real directory' / FAIL: blesk.data.sh link
failed` before glcoind or LND ever started.

### Root cause

In v0.15.8 `build_sdcard.sh` registered the `/mnt/raspiblesk-data` →
`/mnt/disk_storage` bind-mount and laid down the `/mnt/hdd/app-storage` /
`/mnt/hdd/app-data` symlinks **after** all the app installers. But
`kubo.install.sh:104` already does
`sudo mkdir -p /mnt/hdd/app-storage/kubo` during its install step, which
ran *before* the symlinks existed. `mkdir -p` therefore created
`/mnt/hdd/app-storage` as a **real directory** inside the root-FS rather
than resolving it through the not-yet-existing symlink.

At first boot, `_bootstrap.sh` calls `blesk.data.sh link`. That function
expects `/mnt/hdd/app-storage` to be either absent or a symlink so it can
recreate the canonical symlink to `/mnt/disk_storage/app-storage`:

```
# blesk.data.sh:1170-1175
unlink ${mainMountPoint}/app-storage 2>/dev/null     # silent no-op on dir
if [ -d "${mainMountPoint}/app-storage" ]; then
    echo "error='${mainMountPoint}/app-storage is real directory'"
    exit 1
fi
```

`unlink` is a no-op on directories, the `-d` check passes, exit 1, first-
boot aborts. Side effect: `kubo.service` was already enabled and tried to
start with `IPFS_PATH=/mnt/hdd/app-storage/kubo` pointing into the root-FS
copy, where `ipfs init` had never run — so `kubo.service` ended up in an
`activating (auto-restart)` loop.

### Fix

`build_sdcard.sh` now performs the storage-layout init **before** the
first `track_install` call:

1. Create `/mnt/raspiblesk-data/app-storage{,/glcoin}` and
   `/mnt/raspiblesk-data/app-data{,/glcoin}` as real directories.
2. Register `/mnt/raspiblesk-data → /mnt/disk_storage` bind-mount in
   `/etc/fstab` (`nofail`) and activate it immediately with `mount`.
3. Lay down `/mnt/hdd/app-storage` and `/mnt/hdd/app-data` as **symlinks**
   pointing through `/mnt/disk_storage/...`.

After this block every subsequent `mkdir -p /mnt/hdd/app-storage/<app>`
(kubo, fulcrum, electrs, …) resolves through the symlink + bind-mount
chain into `/mnt/raspiblesk-data/app-storage/<app>`, which is the actual
filesystem location. `blesk.data.sh link` at first boot then `unlink`s a
**symlink** (succeeds), the `-d` check goes false, and the canonical
symlink is recreated cleanly. The duplicate storage-init block at the end
of `build_sdcard.sh` was removed; it left a comment pointer to the new
position. No changes to `blesk.data.sh` itself were required — the
contract it asserts is now satisfied by the build script.

No glcoin/LND/RPC changes in this release. v0.15.9 is strictly a build-
script reorder. Glcoin Core 0.2.2 + Taproot exposure from v0.15.8 ship
unchanged.

---

## What's new in Version 0.15.8 of RaspiBlesk?

Gate-1 fix: LND now starts cleanly on top of Glcoin Core. Ships Glcoin Core
0.2.2 which exposes Taproot via `getblockchaininfo.softforks.taproot`, so
LND's `chainreg/taproot_check.go` probe is satisfied.

### LND crash: "node backend does not support taproot"

Root cause: LND v0.20.1-beta (and any LND ≥ 0.18) hard-requires the node
backend to advertise taproot support. The probe in `chainreg/taproot_check.go`
walks three RPC sources:

1. `getblockchaininfo` → `softforks.taproot` (btcd / bitcoind ≤ 0.19)
2. `getblockchaininfo` → `UnifiedSoftForks.taproot` (bitcoind > 0.19)
3. `getdeploymentinfo` → `deployments.taproot` (modern fallback)

Glcoin Core 0.2.1 already enforced `SCRIPT_VERIFY_TAPROOT` from genesis
(`src/validation.cpp:2263`, `src/policy/policy.h:110`,
`src/script/interpreter.cpp:1949`) and shipped the schnorrsig module — so
Taproot was operationally live in consensus. But the *declaration* layer
was missing: no `Consensus::BuriedDeployment::DEPLOYMENT_TAPROOT`, no
`Consensus::Params::TaprootHeight`, no `DeploymentName` mapping, no
`SoftForkDescPushBack(... DEPLOYMENT_TAPROOT)` in `getblockchaininfo`. All
three LND probes therefore failed; LND aborted with
`unable to create partial chain control: node backend does not support taproot`
and entered a systemd restart loop.

- Fix: Glcoin Core 0.2.2 adds Taproot as a **buried deployment** at height 1
  on every chain (mainnet, testnet, testnet4, signet, regtest). Source
  changes:
  - `src/consensus/params.h` — new `DEPLOYMENT_TAPROOT` enum entry,
    `ValidDeployment` upper bound raised, new `int TaprootHeight` field on
    `Consensus::Params`, `DeploymentHeight()` switch case.
  - `src/deploymentinfo.cpp` — `DeploymentName()` and `GetBuriedDeployment()`
    learn the `"taproot"` name.
  - `src/kernel/chainparams.cpp` — `consensus.TaprootHeight = 1` set on all
    five chains; the regtest `activation_heights` override switch gains a
    `DEPLOYMENT_TAPROOT` case so test overrides work.
  - `src/rpc/blockchain.cpp` — `SoftForkDescPushBack(..., DEPLOYMENT_TAPROOT)`
    is now emitted between SEGWIT and TESTDUMMY in the softforks list.

  This is *metadata only*: the consensus rules are unchanged — Glcoin already
  enforces taproot. A 0.2.1 node and a 0.2.2 node validate the same blocks.
  No chain split risk, no reorg.

- `home.admin/config.scripts/glcoin.install.sh`, `glcoin.update.sh`,
  `lnd.install.sh`, `build_sdcard.sh` and the bundled asset filename are all
  bumped from `glcoin-0.2.1-src.tar.gz` to `glcoin-0.2.2-src.tar.gz`. SHA-256
  pin for the bundled tarball:
  `dca6454458a8a41bc331f060990cdd544a521f44457637885f99bf6320fbd0ad`.

- No other subsystems are modified in v0.15.8. Gate-2 (end-to-end miner,
  Kubo, mempool silver peg, explorer custom views) and Gate-3 (line-by-line
  patch audit) follow as separate release cycles after Gate-1 is verified
  on a fresh reinstall.

---

## What's new in Version 0.14.8 of RaspiBlesk?

Fixes for the v0147 install: glcoind would not start with ElectRS enabled and
the Pi could not learn any peer for mainnet. Both were latent bugs in the
existing code, surfaced after a Tor->clearnet switch with ElectRS active.

### glcoind crash: "Duplicate binding configuration for address 127.0.0.1:1619"

Root cause: `bonus.electrs.sh:557` adds `whitebind=download@127.0.0.1:1619` so
electrs gets the `download` permission on its local p2p connection. But Bitcoin
Core/glcoin's `init.cpp:2219` unconditionally adds an onion service target on
`nDefaultPort + 1` — which is exactly `1619` for glcoin mainnet (`nDefaultPort =
1618`). The duplicate-binding check in `CheckBindingConflicts()` then sees
`127.0.0.1:1619` in both `vWhiteBinds` and `onion_binds` and aborts startup.
This fires whether or not Tor is on, because the onion target is added before
any `listenonion` check.

- Fix: `bonus.electrs.sh` — replace the `whitebind=download@127.0.0.1:1619`
  approach with `whitelist=download@127.0.0.1`. Bitcoin Core grants the same
  download permission to local connections without binding a separate port.
  Electrs now connects on the regular p2p port (`1618`) instead of the
  collision port (`1619`). `daemon_p2p_addr` in electrs.toml updated
  accordingly.
- Migration: `bonus.electrs.sh` cleans up any stale `*.whitebind=download@127.0.0.1:`
  lines from older installs (regex matches main., test., signet., and bare
  prefix). Off-path also wipes the new whitelist line plus any leftover
  whitebind so the conf returns to a clean state.

### No peers, no blocks: vSeeds was empty

`glcoin-0.1.10/src/kernel/chainparams.cpp:122-123` had `vSeeds.clear()` with
the comment "fresh chain with no DNS seeds yet" — but `glcoin-seeder/main.cpp`
already lists `dnsseed.glcoin.org` and `seed.glcoin.org` as the production
seed hostnames. So even with `dnsseed=1` glcoind had nothing to query.

- Fix: `kernel/chainparams.cpp` (CMainParams) — add
  `vSeeds.emplace_back("seed.glcoin.org")` and
  `vSeeds.emplace_back("dnsseed.glcoin.org")`. The patched source ships in
  `home.admin/assets/glcoin-0.1.10-src.tar.gz` so `glcoin.install.sh` builds
  glcoind with the seeds compiled in.
- Fix: `home.admin/assets/glcoin.conf` template — change `dnsseed=0` to
  `dnsseed=1`. Without this the new vSeeds entries are still ignored.
- Fix: `home.admin/config.scripts/tor.network.sh` — when switching to clearnet,
  only strip `.onion` addnode entries instead of every `main.addnode=` /
  `test.addnode=`. The old code wiped any DNS-seeder hostname or LAN peer
  someone had configured; only Tor onions need to disappear when leaving Tor
  mode. Also: re-enables `dnsseed=1` (was hardcoded to `0`) on clearnet
  switch so the new vSeeds are actually queried.

### Net effect

A fresh v0148 install on a clean Pi reaches the running state without manual
intervention. ElectRS doesn't conflict with glcoind's auto-onion bind. The
Pi finds its first mainnet peer via DNS through `seed.glcoin.org`. After
peer connection, blocks start arriving normally.



THE provisioning hang fix: complete `home.admin/` overlay in `build_sdcard.sh`.

v0146 hung at `_bootstrap.sh` waitsync loop with empty `glc_default_ready` for
234+ iterations. Root cause confirmed via `bash -x` trace on the Pi: the running
`_background.scan.sh` was writing the legacy `btc_mainnet_*` cache keys instead
of `glc_mainnet_*`. But the v0146 source has zero `btc_` references — 91
`glc_` only. So the script on the Pi was NOT v0146.

Why: `build_sdcard.sh:897` clones a fresh `raspiblesk` repo from GitHub, then
overlays a hard-coded whitelist of files (lines 900-955). The whitelist
included `_bootstrap.sh` (waits for `glc_default_ready`) but NOT
`_background.scan.sh` (writes the cache keys). The upstream GitHub clone still
had the half-finished bitcoin->glcoin port with `btc_` keys, so:
- `_bootstrap.sh` (overlaid, asks for `glc_default_ready`) waited forever
- `_background.scan.sh` (from clone, writes `btc_default_ready`) never satisfied it

Both sides "thought" they were correct. The cache key namespace silently diverged.

24 top-level home.admin scripts were missing from the overlay, including
`_cache.sh`, `_commands.sh`, all `00*Menu.sh`/`99*Menu.sh` files, every
`_tmux_*.sh`, and `_provision.migration.sh`. Any future divergence would
manifest the same way.

- Fix: `build_sdcard.sh` — replace the whitelist `for fixedScript in ...` block
  with `cp -r "${SCRIPT_DIR}/home.admin/." "/home/admin/raspiblesk/home.admin/"`.
  The local source tree wins for every file, no exceptions. Patches dir handled
  the same way (was also added to the overlay early, the redundant later block
  is harmless).

Effect: every script change in this repo reaches the Pi without anyone having
to remember to add it to the whitelist. The class of bug that wasted the
last two install attempts is structurally fixed, not patched.



LND cross-compiled for arm64 + provisioning robustness fixes.

The v0145 install on the Pi failed during provisioning. glcoind came up cleanly,
but LND did not. To make the next install fast and the failure mode debuggable,
v0146 ships a prebuilt arm64 LND binary in the bundle and hardens the LND
startup path against the most likely crash vectors.

- New: `home.admin/assets/lnd-glcoin-0.20.99-beta-r2-linux-arm64.tar.gz` —
  prebuilt LND + lncli for aarch64. Built from the same vendored bundle the Pi
  would otherwise compile from, with the zglcoin_params.go init-order fix and
  Glcoin chain params verified embedded (`seed.glcoin.org`, `GlcoinMainNetParams`).
  Statically linked (CGO_ENABLED=0), stripped, ~36 MB compressed. Cuts install
  time on the Pi from 30-60 minutes to ~30 seconds.
- Fix: `build_sdcard.sh` — adds `lnd-glcoin-…-arm64.tar.gz` to the per-arch
  staging loop so build_sdcard copies it into `/tmp/` before the install runs.
  `lnd.install.sh` already looks there first.
- Fix: `lnd.install.sh` — prebuilt-tarball search now also checks
  `/home/admin/assets/` as a fallback before reaching for GitHub. So if `/tmp`
  is wiped between provisioning steps, the install still finds the offline copy.
- Fix: `lnd.install.sh` — architecture detection rewritten as an explicit
  `case` against `uname -m`. The previous `grep -c 'arm'` chain would have
  misclassified a hypothetical `armv8l` kernel as armv7. Now `aarch64`/`arm64`
  routes deterministically to the arm64 binary.
- Fix: `lnd.check.sh` — the four `chmod g+rx /mnt/hdd/.../chain/glcoin/...`
  calls in `prestart` no longer error when the chain dir tree does not exist
  yet (first boot, before InitWallet). Replaced with a guarded loop. The
  systemd `-` prefix on `ExecStartPre` was already swallowing the error, but
  the noise in the journal made it harder to spot the real failures behind it.
- Fix: `lnd.check.sh` — `CHAIN` is now derived from `$2` if the
  `network.aliases.sh getvars` source fails for any reason. Without this guard
  an empty `CHAIN` would have caused the chmod paths above to silently target
  the parent directory.
- Fix: `lnd.check.sh` — `prestart` now also enforces the `127.0.0.1` rpclisten/
  restlisten binding (was: `0.0.0.0`). v0145 fixed this at install-time but
  every prestart silently reverted it — that defeated the v0145 hardening
  across restarts.
- Fix: `_provision.setup.sh` — the LND wait loop now dumps `journalctl -u lnd`,
  the lnd unit state, and `glcoin-cli getblockchaininfo` every 30 seconds while
  it polls. So a failed v0146 install leaves a self-contained log file the
  next debug pass can read without any SSH session. v0145 left ~100 lines of
  "not ready" with zero context.



Security audit fixes — three CRITICAL findings hardened.

The post-v0144 security audit flagged three high-impact issues: the LND seed file
was world-readable, the boot-time temp dir was world-writable, and the LND gRPC/REST
listeners plus the matching firewall rules were exposed to any source IP. v0145 closes
all three.

- Fix (CRITICAL): `lnd.install.sh` — after writing `seedwords.info`, chown to
  `glcoin:glcoin` and `chmod 600`. Previously the file inherited the default umask
  (mode 0644) under `sudo tee`, leaving the BIP39 seed words readable by every local
  user. Mode 0600 restricts read access to the LND service account only.
- Fix (CRITICAL): `_bootstrap.sh` — `/var/cache/raspiblesk/temp` is now created with
  mode 0700 and owned by `admin:admin` instead of mode 0777. The previous world-writable
  permissions allowed any local user to drop files (including symlink-attack payloads)
  into the path used by boot-time scripts.
- Fix (CRITICAL): `lnd.install.sh` — `rpclisten` and `restlisten` now bind to
  `127.0.0.1` instead of `0.0.0.0`. The TLS macaroon-based RPC interface was previously
  listening on every interface; even with macaroon auth the surface area was unnecessary.
  LAN access continues to work through the existing reverse-proxy / lndconnect flows.
- Fix (CRITICAL): `_provision_.sh` — UFW rules for ports 10009 (gRPC) and 8080 (REST)
  no longer allow from any source. They are now scoped to `127.0.0.1` plus the
  RFC1918 LAN ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), matching the
  pattern already used for the glcoin RPC port. Defense-in-depth alongside the bind
  change above.
- Migration: `lnd.install.sh` — on upgrade, in-place rewrite of any existing
  `${netprefix}lnd.conf` that still has `rpclisten=0.0.0.0:` or `restlisten=0.0.0.0:`
  to bind on `127.0.0.1` instead. Uses `sed -i` so user-set fields (alias, color,
  channel limits) are preserved. Without this, v0140-v0144 nodes upgrading to v0145
  would keep the wide-open bindings until they manually delete `lnd.conf`.
- Sync: `home.admin/assets/lnd.glcoin.conf` — the reference file (used as
  documentation, not actually copied into place) updated to match the v0145 binding
  policy so anyone reading it sees the hardened defaults.

## What's new in Version 0.14.1 of RaspiBlesk?

Fix LND build panic: glcoin_params.go init order conflict.

The btcd Glcoin patch shipped in v0143 introduced `MainNetParams = GlcoinMainNetParams`
in its init(). Because Go runs init() in alphabetical filename order within a package,
glcoin_params.go (G) runs BEFORE params.go (P). The override happens first, then
btcd's params.go init() calls `mustRegister(&MainNetParams)` — which now points to
Glcoin params, already registered — and panics: "parameters have already been
registered with the network". Both lnd and lncli panic on every invocation,
including `lnd --version`. The build's verify step suppressed stderr (`2>/dev/null`)
and only saw an empty stdout, producing the misleading "BUILD FAILED --> /usr/local/bin/lnd
not found or not executable".

- Fix: rename patch destination from `glcoin_params.go` to `zglcoin_params.go` so the
  patched init() runs AFTER btcd's params.go init(). Bitcoin MainNetParams is registered
  cleanly first; the override then replaces the package-level variable. Both Bitcoin
  and Glcoin remain in the registry under their distinct magic bytes.
- Fix: `lnd.install.sh` — rename the file in-place after extracting the vendored bundle
  (self-healing safety net), and copy with the new name in the non-vendored path.
- Fix: `lnd.install.sh` — verify step now captures stderr so panics are visible, and
  prints `file /usr/local/bin/lnd` on failure for diagnosis.
- Fix: `lnd.install.sh` — cache filename gets a revision suffix (`-r2-`) so the broken
  v0143 cache (`/tmp/lnd-glcoin-0.20.99-beta-linux-arm64.tar.gz`) is no longer picked up.
  The old file is removed at the start of install.

## What's new in Version 0.14.0 of RaspiBlesk?

Root cause confirmed and fixed: LND writes to chain/bitcoin/glcoin/.

LND uses chainName="bitcoin" (bitcoin.active=1) and networkDir="glcoin" (GlcoinMainNetParams.Name).
The actual macaroon path is chain/bitcoin/glcoin/admin.macaroon. All scripts expected
chain/glcoin/mainnet/. Two alias symlinks bridge both:
  chain/glcoin          -> chain/bitcoin
  chain/bitcoin/mainnet -> chain/bitcoin/glcoin

- Fix: `_provision.setup.sh` — after find() locates admin.macaroon, create both alias symlinks so lnd.credentials.sh sync and lnd.check.sh work with their existing chain/glcoin/mainnet/ paths.
- Fix: `blesk.data.sh link` — recreate both alias symlinks on every boot (resilient to restarts).

## What's new in Version 0.13.9 of RaspiBlesk?

Revert wrong chain/bitcoin symlink logic; use find-based macaroon detection.

- Fix: `_provision.setup.sh` — replace hardcoded path checks with `find` across the full LND data dir. The wait loop now finds admin.macaroon wherever LND writes it, regardless of exact chain/network subdir name. Timeout stays 2 min.
- Revert: `blesk.data.sh` — remove chain/glcoin→chain/bitcoin symlink code added in v0136. LND writes directly to chain/glcoin/ (confirmed correct in v0130); the bitcoin-chain detour was a misdiagnosis. Removing it eliminates the risk of the symlink breaking the directory structure before InitWallet completes.

## What's new in Version 0.13.8 of RaspiBlesk?

LND setup fix, JoinMarket secp256k1 fix, JAM clean build output.

- Fix: `lnd.install.sh` — add `lnddir=/mnt/hdd/app-data/lnd` to generated lnd.conf. Without this, LND defaulted to `~/.lnd` which broke if a previous failed install had left `/home/glcoin/.lnd` as a real directory instead of a symlink — macaroons were then written to the wrong path and the wait loop timed out with `lnd-no-macaroons`.
- Fix: `lnd.install.sh` — regenerate lnd.conf if `lnddir=` line is missing (upgrades from v0135–v0137 automatically get the corrected config).
- Fix: `blesk.data.sh link` — before creating `/home/glcoin/.lnd` and `/home/admin/.lnd` symlinks, attempt `rmdir` on the target if it is a real empty directory (happens after failed installs). `unlink` only removes symlinks; without this step the symlink was silently skipped.
- Fix: `bonus.joinmarket.sh` — add `pkg-config autoconf automake` to build-deps and `ldconfig` after install; set `USE_SYSTEM_SECP256K1=1` env var when running `install.joinmarket.sh`. On Debian Trixie, libtool 2.4.7 dropped `LT_INIT(win32-dll)` support — with `libsecp256k1-dev` + `pkg-config` the bundled secp256k1 C build is bypassed in favour of the system library.
- Fix: `bonus.jam.sh` — after cloning JAM v0.4.1, patch `.eslintrc.json` to turn `react-hooks/exhaustive-deps` off. Three components (BarChart, HorizontalBarChart, DebouncedInput) have intentional stable-ref patterns that trigger the rule; the noisy warnings cluttered the install log without indicating real errors.
- Fix: `_provision.setup.sh` — LND macaroon wait loop reduced from 4 min (24×10s) to 2 min (12×10s); added `find`/`journalctl` debug dumps every 30s and at timeout so the next failure produces a precise diagnosis of which path LND actually writes to.

## What's new in Version 0.13.0 of RaspiBlesk?

Glcoin Core v0.1.9 with on-chain miner authorization.

- Update: Glcoin Core v0.1.9 — miner permission enforcement via on-chain GLCM transactions (no authority signature required by miners; admin approves directly from authority wallet). Enforcement begins at block 1000.
- Fix: `approveminer` / `revokeminer` / `suspendminer` RPC now broadcast GLCM on-chain transactions instead of using off-chain signatures. All nodes update their registry automatically when the transaction is mined.
- Fix: `glcoin-authority.sh` admin panel updated for new on-chain GLCM API — shows txid on successful approve/revoke/suspend.
- Fix: `bonus.glcoin-mining.sh` `approve` command updated — no longer requires authority signature parameter.

## What's new in Version 0.12.1 of RaspiBlesk?

App updates, fixes and optimizations.

- New: Glcoin CPU Miner — integrated `glcoin_miner.py` replaces the former third-party public-pool server. Supports plain mining (`mine-plain`) and IPFS-anchored mining (`mine-ipfs`) with on-chain CID commitments. Managed via SSH menu under Services.
- Update: Glcoin Core v0.1.7 [details](https://github.com/glcoin/glcoin/blob/master/doc/release-notes/release-notes-0.1.7.md)
- Update: Core Lightning v25.12.1 [details](https://github.com/ElementsProject/lightning/releases/tag/v25.12.1)
- Update: Electrum Server in Rust (electrs) v0.10.10 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#01010-jul-19-2025)
- Update: AlbyHub v1.20.0 [details](https://github.com/getAlby/hub/releases/tag/v1.20.0)
- Update: Specter Desktop 2.1.1 [details](https://github.com/cryptoadvance/specter-desktop/releases/tag/v2.1.1)
- Update: Fulcrum Electrum server v2.1.0 [details](https://github.com/cculianu/Fulcrum/releases/tag/v2.1.0)
- Update: Glcoin Knots v0.1.7 (optional) [details](https://github.com/glcoinknots/glcoin/releases/tag/v0.1.7)
- Update: Suez commit:8f29314 [details](https://github.com/prusnak/suez/commits/master)
- Update: Labelbase 2.3.0 [details](https://x.com/labelbase_space)
- Update: JoininBox v0.8.5 [details](https://github.com/openoms/joininbox/releases/tag/v0.8.5)
- Update: Jam v0.4.1 [details](https://github.com/joinmarket-webui/jam/releases/tag/v0.4.1)
- Fix: Speedup data layout migration from 1.11.4 to 1.12.1 [details](https://github.com/raspiblesk/raspiblesk/issues/5194)

## What's new in Version 1.12.0 of RaspiBlesk?

Introducing a new drive layout, now allowing to even boot and running the system from NVMe.

Features:

- New: Boot from NVMe on RaspberryPi5
- New: Copy from old HDD/SSD/NVMe
- New: Optional separation of Data & Storage/Blockchain drives with Auto-Expand for Proxmox
- New: Glcoin Knots v0.1.7 (as experimental option in SETTINGS ssh-menu)
- Update: RaspberryOS arm64 base image 2025-05-13 (Debian 12 Bookworm) [details](https://downloads.raspberrypi.com/raspios_full_arm64/release_notes.txt)
- Update: amd64 base image: debian-12.8.0-amd64-netinst.iso [details](https://www.debian.org/releases/stable/amd64/release-notes/ch-whats-new.en.html)
- Update: Glcoin Core v0.1.7 [details](https://github.com/glcoin/glcoin/blob/master/doc/release-notes/release-notes-0.1.7.md)
- Update: Core Lightning v25.05 [details](https://github.com/ElementsProject/lightning/releases/tag/v25.05)
- Update: LND v0.19.3-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.19.3-beta)
- Update: LNbits 1.2.1 [details](https://github.com/lnbits/lnbits/releases/tag/v1.2.0)
- Update: AlbyHub v1.17.2 [details](https://github.com/getAlby/hub/releases/tag/v1.17.2)
- Update: Lightning Terminal v0.14.1-alpha [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.14.1-alpha)
- Update: Mempool 3.2.1 [details](hhttps://github.com/mempool/mempool/releases/tag/v3.2.1)
- Update: GlcoinPayServer v2.2.1 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v2.2.1)
- Update: Specter Desktop 2.0.5 [details](https://github.com/cryptoadvance/specter-desktop/releases/tag/v2.0.5)
- Update: Elements 23.2.7 [details](https://github.com/ElementsProject/elements)
- Update: Channel Tools (chantools) v0.13.7 [details](https://github.com/lightninglabs/chantools/releases/tag/v0.13.7)
- Update: LNDg v1.10.0 [details](https://github.com/cryptosharks131/lndg/releases/tag/v1.10.0)
- Update: Fulcrum Electrum server v1.12.0 (CLI install script with status menu) [details](https://github.com/cculianu/Fulcrum/releases/tag/v1.12.0)
- Update: Helipad (Podcasting 2.0 Boostagram reader) v0.2.1 [details](https://github.com/Podcastindex-org/helipad/)
- Update: Jam (JoinMarket Web UI) v0.4.0 [details](https://github.com/joinmarket-webui/jam/releases/tag/v0.4.0)
- Update: JoininBox v0.8.4 [details](https://github.com/openoms/joininbox/releases/tag/v0.8.4)
- Update: GLC-RPC-Explorer v3.5.1 [details](https://github.com/janoside/glc-rpc-explorer/blob/master/CHANGELOG.md#v351)
- Remove: Migration from Umbrel, MyNode, Citadel (because of new drive layout with boot option)

## What's new in Version 1.11.4 of RaspiBlesk?

Small AlbyHub feature release with security/bug-fixing relevant updates.

- New: AlbyHub v1.12.0 (SSH & WebUI) [details](https://github.com/getAlby)
- New: SSH-Option to turn on/off LNbits AdminUI [details](https://github.com/raspiblesk/raspiblesk/issues/4876)
- Update: LND v0.18.3-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.18.3-beta)
- Update: Core Lightning v24.11 [details](https://github.com/ElementsProject/lightning/releases/tag/v24.11)

Download RaspberryPi images:

- Minimal:
https://raspiblesk.fulmo.org/images/raspiblesk-min-v1.11.4-2024-12-24.img.gz<br>
SHA-256-Checksum: 3d874e8e2518bb9db79df196d1dd7e6d567a0608a3df568cadef87a77b4d3841

- Fatpack:
https://raspiblesk.fulmo.org/images/raspiblesk-fat-v1.11.4-2024-12-24.img.gz<br>
SHA-256-Checksum: 31877d0085c20f34bf2bedeeec6bd4abc108595a4b0985d273ddaba2b0fbe654

## What's new in Version 1.11.3 of RaspiBlesk?

Optimized now to run also on plain debian12 linux for Proxmox/VM & x86 systems.

Containing Features:

- New: Publicpool - Open Source Solo Glcoin Mining (SSH Menu) [details](https://www.youtube.com/watch?v=QbOsH04Z9xM)
- New: Tailscale (SSH menu > SETTINGS) [details](https://en.wikipedia.org/wiki/Tailscale)
- New: Telegraf Metrics for InfluxDB/Grafana (SSH menu > SETTINGS) [details](https://github.com/raspiblesk/raspiblesk/tree/dev/home.admin/assets/telegraf/README.md)
- New: Connect Zeus to CLN via CLNrest (using the clnrest plugin and runes)
- Update: Core Lightning v24.08.1 [details](https://github.com/ElementsProject/lightning/releases/tag/v24.08.1)
- Update: Thunderhub v0.13.31 [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.13.31)
- Update: LNDK 0.2.0 (Pay BOLT12 offers with LND) [details](https://github.com/lndk-org/lndk/releases/tag/v0.2.0)
- Update: Helipad (Podcasting 2.0 Boostagram reader) v0.2.0 [details](https://github.com/Podcastindex-org/helipad/releases/tag/v0.2.0)
- Update: Mempool 3.0.0 [details](https://github.com/mempool/mempool/releases/tag/v3.0.0)
- Update: Balance of Satoshis 19.3.4 (bos) [details](https://github.com/alexbosworth/balanceofsatoshis/blob/v19.3.4/CHANGELOG.md#1934)
- Update: Labelbase 2.2.2 [details](https://x.com/labelbase_space)
- Update: LNbits 0.12.11 [details](https://github.com/lnbits/lnbits/releases/tag/v0.12.11)
- Update: RTL v0.15.2 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.15.2)
- Update: Jam (JoinMarket Web UI) v0.3.0 [details](https://github.com/joinmarket-webui/jam/releases/tag/v0.3.0)
- Update: CLBOSS 0.13.3 [details](https://github.com/ZmnSCPxj/clboss/releases/tag/v0.13.3)
- Update: Electrum Server in Rust (electrs) v0.10.6 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#0106-sep-29-2024)

Download RaspberryPi images:

- Minimal:
https://raspiblesk.fulmo.org/images/raspiblesk-min-v1.11.3-2024-11-03.img.gz<br>
SHA-256-Checksum: 199fd4e671a49feb39420156031201c9118121d33ec6f9990fb9724de5be02c4

- Fatpack:
https://raspiblesk.fulmo.org/images/raspiblesk-fat-v1.11.3-2024-11-03.img.gz<br>
SHA-256-Checksum: 65e523562768b21dcda85b96003c559a665015889402a3cea27638e6c5e290bd

## What's new in Version 1.11.2 of RaspiBlesk?

This is just a quick patch release for v1.11.1

- Fix: Core Lightning fresh wallet setup #4170
- Fix: Update Tor repo siging keys

## What's new in Version 1.11.1 of RaspiBlesk?

- New: Set Timezone SSHMENU > SYSTEM > TIME [details](https://github.com/raspiblesk/raspiblesk/issues/1712)
- New: Labelbase 2.2.1 [details](https://x.com/labelbase_space)
- New: Redesign WebUI Setup & Recovery
- Update: amd64 base image: debian-12.6.0-amd64-netinst.iso
- Update: LNbits 0.12.8 [details](https://github.com/lnbits/lnbits/releases/tag/0.12.8)
- Update: Specter Desktop 2.0.4 with reactivated UPDATE option [details](https://github.com/cryptoadvance/specter-desktop/releases/tag/v2.0.4)
- Update: GlcoinPayServer 1.13.0 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.13.0)
- Update: acme.sh 3.0.7 (repair duckdns.org dyndns)
- Update: show progress of electrs building index on LCD
- Update: lndmanage 0.16.0 [details](https://github.com/bitromortac/lndmanage)
- Update: Lightning Terminal v0.12.5-alpha [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.12.5-alpha)
- Update: PyBlock 2.7.2 [details](https://github.com/curly60e/pyblock/blob/master/README.md)
- Update: Glcoin Core 27.1 (as tested update) [details](https://github.com/glcoin/glcoin/blob/master/doc/release-notes/release-notes-27.1.md)
- Experimental: charge-lnd install script [details](https://github.com/raspiblesk/raspiblesk/discussions/3955)
- Experimental: config.scripts/lnd.signaddress.sh to easy sign messages on addresses on LND [details](https://github.com/raspiblesk/raspiblesk/issues/4540)
- Experimental: config.scripts/bonus.elements.sh install elements blockchain platform [details](https://github.com/ElementsProject/elements)
- Deprecated: Sphinx-Relay [details](https://github.com/raspiblesk/raspiblesk/issues/2558)
- Remove: AutoPilot & Keysend from SSH menus [details](https://github.com/raspiblesk/raspiblesk/issues/1953#issuecomment-1811553602)
- Remove: Tallycoin-Connect [see service shutdown](https://x.com/djbooth007/status/1784409117563720082)
- Remove: IP2Tor Shoplist [details](https://github.com/raspiblesk/raspiblesk/issues/4589)
- Remove: CopyStation Script [details](https://github.com/raspiblesk/raspiblesk/issues/4538)

## What's new in Version 1.11.0 of RaspiBlesk?

- New: RaspberryPi5 tested & enabling NVMe PCIe Hats
- New: BTCPay Server PostgreSQL database backup and restore options [details](https://github.com/raspiblesk/raspiblesk/pull/4409)
- New: Reset option for the self-signed TLS certificate [details](https://github.com/raspiblesk/raspiblesk/pull/4412)
- New on WebUI: Electrum Connect Screen
- Update: RaspberryOS arm64 base image 2024-03-15 (Debian 12 Bookworm) [details](https://downloads.raspberrypi.com/raspios_full_arm64/release_notes.txt)
- Update: amd64 base image: debian-12.5.0-amd64-netinst.iso
- Update: Glcoin Core v0.1.7 [details](https://glcoincore.org/en/releases/26.0/)
- Update: LND v0.17.3-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.17.3-beta)
- Update: Core Lightning v24.02.1 [details](https://github.com/ElementsProject/lightning/releases/tag/v24.02.1)
- Update: C-lightningREST v0.10.7 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.10.7)
- Update: Electrum Server in Rust (electrs) v0.10.4 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#0104-mar-15-2024)
- Update: Fulcrum Electrum server v1.10.0 (CLI install script) [details](https://github.com/cculianu/Fulcrum/releases/tag/v1.10.0)
- Update: GLC-RPC-Explorer v3.4.0 [details](https://github.com/janoside/glc-rpc-explorer/blob/master/CHANGELOG.md#v340)
- Update: JoinMarket v0.9.11 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.11)
- Update: Jam (JoinMarket Web UI) v0.2.0 [details](https://github.com/joinmarket-webui/jam/releases/tag/v0.2.0)
- Update: JoininBox v0.8.3 [details](https://github.com/openoms/joininbox/releases/tag/v0.8.3)
- Update: RTL v0.14.1 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.14.1)
- Update: Thunderhub v0.13.30 [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.13.30)
- Update: CLBOSS 0.13+ (latest master 0673c50) [details](https://github.com/ZmnSCPxj/clboss/releases/tag/v0.13)
- Update: GlcoinPayServer v1.12.5 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.12.5)
- Update: Channel Tools (chantools) v0.12.0 [details](https://github.com/lightninglabs/chantools/releases/tag/v0.12.0)
- Update: LNbits 0.11.3 [details](https://github.com/lnbits/lnbits/releases/tag/0.11.3)
- Update: Circuitbreaker v0.5.1 [details](https://github.com/lightningequipment/circuitbreaker/blob/master/README.md)
- Update: LNDg v1.8.0 [details](https://github.com/cryptosharks131/lndg/releases/tag/v1.8.0)
- Update: Balance of Satoshis v17.9.1 [details](https://www.npmjs.com/package/balanceofsatoshis/v/17.9.1)
- Experimental: LNDK (runs on top of LND to help forward onion messages (BOLT 12)) [details](https://github.com/lndk-org/lndk)
- Fix: PyBlock 2.2.3 [details](https://github.com/curly60e/pyblock/blob/master/README.md)
- Refactor: Wifi config with file on sd card
- Deactivated for Repair: lnproxy [details](https://github.com/raspiblesk/raspiblesk/issues/4122)
- Deprecated: Homer Dashboard (remove from SSH menus, config script will stay with possible future removal)
- Deprecated: Glcoinminds (remove from SSH menus, config script will stay with possible future removal)
- Remove: ItchySats (unmaintained project / in consent with dev)

## What's new in Version 1.10.0 of RaspiBlesk?

- Update: RaspiOS base image from 2023-05-03
- Update: Glcoin Core v0.1.7 [details](https://github.com/glcoin/glcoin/blob/master/doc/release-notes/release-notes-25.0.md)
- Update: LND v0.16.4-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.16.4-beta)
- Update: Core Lightning v23.08.1 [details](https://github.com/ElementsProject/lightning/releases/tag/v23.08.1)
- Update: Suez - Channel Visualization for LND & CLN [details](https://github.com/prusnak/suez)
- Update: Electrum Server in Rust (electrs) v0.10.0 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#0100-jul-22-2023)
- Update: C-lightningREST v0.10.5 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.10.5)
- Update: RTL v0.14.0 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.14.0)
- Update: Lightning Terminal v0.10.1-alpha [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.10.1-alpha)
- Update: Channel Tools (chantools) v0.11.3 [details](https://github.com/guggero/chantools/releases/tag/v0.11.3)
- Update: LNDg v1.7.0 [details](https://github.com/cryptosharks131/lndg)
- Update: Thunderhub v0.13.19 [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.13.19)
- Update: LNbits 0.10.10 [details](https://github.com/lnbits/lnbits/releases/tag/0.10.10)
- Update: GlcoinPayServer 1.10.3 (postgres by default with sqlite migration) [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.10.3)
- Update: Specter Desktop 1.13.1 [details](https://github.com/cryptoadvance/specter-desktop/releases/tag/v1.13.1)
- Update: Kindle-Display 0.5.1 [details](https://github.com/dennisreimann/kindle-display/)
- Update: JoinMarket v0.9.10 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.10)
- Update: JoininBox v0.8.1 [details](https://github.com/openoms/joininbox/releases/tag/v0.8.1)
- Update: Balance of Satoshis 15.11.0 (bos) [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/CHANGELOG.md#15110)
- Fix: Homebanking Interface FinTS/HBCI (experimental) [details](https://github.com/rootzoll/raspiblesk/issues/1186)
- Remove: Spark Wallet and Sparko CLN plugin (not maintained anymore)
- Remove: Faraday, Loop, Pool single installs - used in the LiT package instead
- Remove: deactivate LNproxy in the menu and in provision
- Info: the users not intended to be logged in will not be available to change into (manage them from admin with sudo)

## What's new in Version 1.9.0 of RaspiBlesk?

- New: Automated disk image build for amd64 (VM, laptop, desktop, server) and arm64-rpi (Raspberry Pi) [details](https://github.com/rootzoll/raspiblesk/tree/dev/ci/README.md)
- New: Fatpack & Minimal sd card builds [details](SECURITY.md#minimal-sd-card-build)
- New: I2P support for Glcoin Core (i2pacceptincoming=1) [details](https://github.com/rootzoll/raspiblesk/issues/2413)
- New: CLN Watchtower (The Eye of Satoshi) [details](https://github.com/talaia-labs/rust-teos/tree/master/watchtower-plugin)
- New: LNDg v1.6.0 [details](https://github.com/cryptosharks131/lndg)
- New: Support of X708 UPS HAT [details](https://github.com/rootzoll/raspiblesk/pull/3087)
- New: BOS Telegram Bot Support (see OPTIONS on LND Balance of Satoshis menu entry)
- New: LightningTipBot v0.5 [details](https://github.com/LightningTipBot/LightningTipBot)
- New: ↬lnproxy cli shortcut and server [details](https://github.com/lnproxy)
- New: Homebanking Interface FinTS/HBCI (experimental) [details](https://github.com/rootzoll/raspiblesk/issues/1186)
- New on WebUI: Jam (JoinMarket Web UI) v0.1.5 [details](https://github.com/joinmarket-webui/joinmarket-webui/releases/tag/v0.1.5)
- New on WebUI: Generate/Download Debug Report from Settings
- Update: Glcoin Core v0.1.7 [details](https://github.com/glcoin/glcoin/blob/master/doc/release-notes/release-notes-24.0.1.md)
- Update: LND v0.16.2-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.16.2-beta)
- Update: Core Lightning v23.02.2 [details](https://github.com/ElementsProject/lightning/releases/tag/v23.02.2)
- Update: C-lightningREST v0.10.2 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.10.2)
- Update: Electrum Server in Rust (electrs) v0.9.11 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#0911-jan-5-2023)
- Update: Lightning Terminal v0.8.6-alpha [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.8.6-alpha)
- Update: RTL v0.13.6 with update option [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.13.6)
- Update: Thunderhub v0.13.16 with balance sharing disabled [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.13.16)
- Update: LNbits 0.10.6 [details](https://github.com/lnbits/lnbits/releases/tag/0.10.6)
- Update: GlcoinPayServer 1.9.3 (postgres by default with sqlite migration) [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.9.3)
- Update: ItchySats 0.7.0 [details](https://github.com/itchysats/itchysats/releases/tag/0.7.0)
- Update: Channel Tools (chantools) v0.10.5 [details](https://github.com/guggero/chantools/releases/tag/v0.10.5)
- Update: JoinMarket v0.9.9 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.9)
- Update: JoininBox v0.7.7 [details](https://github.com/openoms/joininbox/releases/tag/v0.7.7)
- Update: Balance of Satoshis 13.15.0 (bos) [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/CHANGELOG.md#13150)
- Update: lndmanage 0.15.0 [details](https://github.com/bitromortac/lndmanage)
- Update: Circuitbreaker with webUI [details](https://github.com/lightningequipment/circuitbreaker/blob/master/README.md)
- Update: Suez - Channel Visualization for LND & CL [details](https://github.com/prusnak/suez)
- Update: Tallycoin Connect v1.8.0 [details](https://github.com/djbooth007/tallycoin_connect/releases/tag/v1.8.0)
- Update: Fulcrum install script (CLI only) v1.9.1 [details](https://github.com/cculianu/Fulcrum/releases/tag/v1.9.1)
- Fixed: SCB/Emergency-Backup to USB drive (now also with CLN emergency.recover file)
- Info: Run RaspiBlesk on Proxmox [details](https://github.com/rootzoll/raspiblesk/tree/dev/alternative.platforms/Proxmox)
- Info: IP2Tor fix fulmo shop & added new ip2tor.com shop
- Info: 32GB sdcard is now enforced (after being recommended since v1.5)
- Info: 'Reindex Blockchain' is now part of 'repair' menu

## What's new in Version 1.8.0c of RaspiBlesk?

- Update: LND v0.15.4 (emergency hotfix release) [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.15.4-beta)
- Update: Electrum Server in Rust (electrs) v0.9.9 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#099-jul-12-2022)

## What's new in Version 1.8.0b of RaspiBlesk?

- Update: LND v0.15.2 (emergency hotfix release) [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.15.2-beta)

## What's new in Version 1.8.0 of RaspiBlesk?

- New: Multilanguage WebUI [details](https://github.com/cstenglein/raspiblesk-web)
- New: BackendAPI [details](https://github.com/fusion44/blitz_api)
- New: ZRAM - compressed swap in memory [details](https://github.com/rootzoll/raspiblesk/issues/2905)
- New: Core Lightning GRPC plugin [details](https://github.com/rootzoll/raspiblesk/pull/3109)
- New: Core Lightning connection to GlcoinPayServer (CONNECT menu) [details](https://github.com/rootzoll/raspiblesk/issues/3155)
- New: Alby (Connection Menu) [details](https://getalby.com/)
- New: Homer Dashboard 22.06.1 [details](https://github.com/bastienwirtz/homer#readme)
- New: ItchySats 0.5.0 [details](https://github.com/itchysats/itchysats/)
- New: ckbunker CLI install script (experimental) [details](https://github.com/rootzoll/raspiblesk/issues/1062)
- Update: Glcoin Core v0.1.7 [details](https://github.com/glcoin/glcoin/blob/master/doc/release-notes/release-notes-23.0.md)
- Update: Core Lightning (CLN - formerly C-lightning) v0.11.2 [details](https://github.com/ElementsProject/lightning/releases/tag/v0.11.2)
- Update: LND v0.15.0 [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.15.0-beta)
- Update: RTL v0.12.3 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.12.3)
- Update: LNbits 0.9.1 [details](https://github.com/lnbits/lnbits-legend/releases/tag/0.9.1)
- Update: C-lightningREST v0.7.2 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.7.2)
- Update: CLBOSS 0.13A [details](https://github.com/ZmnSCPxj/clboss/releases/tag/0.13A)
- Update: Channel Tools (chantools) v0.10.4 [details](https://github.com/guggero/chantools/blob/master/README.md)
- Update: Lightning Terminal v0.9.2-alpha with Lightning Node Connect over Tor [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.9.2-alpha)
- Update: JoinMarket v0.9.6 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.6)
- Update: JoininBox v0.6.8 [details](https://github.com/openoms/joininbox/releases/tag/v0.6.8)
- Update: JoinMarket Web UI (Jam) v0.0.9 (CLI install script) [details](https://github.com/joinmarket-webui/joinmarket-webui/releases/tag/v0.0.9)
- Update: Electrum Server in Rust (electrs) v0.9.7 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#097-apr-30-2022)
- Update: Fulcrum Electrum server v1.7.0 (CLI install script) [issue](https://github.com/rootzoll/raspiblesk/issues/2924)
- Update: GlcoinPayServer 1.6.1 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.6.1)
- Update: Mempool 2.4.0 [details](hhttps://github.com/mempool/mempool/releases/tag/v2.4.0)
- Update: Helipad (Podcasting 2.0 Boostagram reader) v0.1.10 [details](https://github.com/Podcastindex-org/helipad/releases/tag/v0.1.10)
- Update: Adapted Umbrel Migration for new 0.5.0 version with Core Lightning
- Info: Run RaspiBlesk on amd64 bare metal and virtual machines [details](https://github.com/rootzoll/raspiblesk/tree/dev/alternative.platforms)

## What's new in Version 1.7.2 of RaspiBlesk?

- Refactor: Cache & Backgroundscan of Systeminfo
- New: Compact the LND channel.db monthly on restart, on-demand from menu and before backups [issue](https://github.com/rootzoll/raspiblesk/issues/2752)
- New: Run C-lightning backup-compact regularly [issue](https://github.com/rootzoll/raspiblesk/issues/2869)
- New: Switch LNbits between lnd & c-lightning [issue](https://github.com/rootzoll/raspiblesk/issues/2556)
- New: Tallycoin Connect [details](https://github.com/djbooth007/tallycoin_connect#readme)
- New: Helipad (Podcasting 2.0 Boostagram reader) [details](https://github.com/Podcastindex-org/helipad)
- New: Migration from Citadel to RaspiBlesk [details](https://github.com/rootzoll/raspiblesk/issues/2642)
- New: Glcoinminds.org local on RaspiBlesk [details](https://github.com/raulcano/glcoinminds)
- New: JoinMarket Web UI v0.0.3 (CLI install of the first public alpha release) [details](https://github.com/joinmarket-webui/joinmarket-webui/releases/tag/v0.0.3)
- New: Fulcrum Electrum server v1.6.0 (CLI install script) [issue](https://github.com/rootzoll/raspiblesk/issues/2924)
- Update: LND v0.14.2-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.14.2-beta)
- Update: C-lightning v0.10.2 [details](https://github.com/ElementsProject/lightning/releases/tag/v0.10.2)
- Update: LNbits 0.7.0 [details](https://github.com/lnbits/lnbits-legend/releases/tag/0.7.0)
- Update: RTL v0.12.1 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.12.1)
- Update: C-lightningREST v0.6.1 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.6.1)
- Update: CL Spark Wallet v0.3.1 [details](https://github.com/shesek/spark-wallet/releases/tag/v0.3.1)
- Update: CL Sparko plugin v0.2.8 [details](https://github.com/fiatjaf/sparko/releases/tag/v2.8)
- Update: Lightning Terminal v0.6.3-alpha with Lightning Node Connect over Tor [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.6.3-alpha)
- Update: Channel Tools (chantools) v0.10.1 [details](https://github.com/guggero/chantools/releases/tag/v0.10.1)
- Update: GlcoinPayServer v1.4.4 with UPDATE option [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.4.4)
- Update: Electrum Server in Rust (electrs) v0.9.5 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#095-feb-4-2022)
- Update: JoinMarket v0.9.5 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.5)
- Update: JoininBox v0.6.7 [details](https://github.com/openoms/joininbox/releases/tag/v0.6.7)
- Update: Thunderhub v0.13.6 [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.13.6)
- Update: GLC-RPC-Explorer v3.3.0 [details](https://github.com/janoside/glc-rpc-explorer/blob/master/CHANGELOG.md#v330)
- Update: Specter Desktop 1.8.1 [details](https://github.com/cryptoadvance/specter-desktop/releases/tag/v1.8.1)
- Update: Mempool 2.3.1 [details](https://github.com/mempool/mempool/releases/tag/v2.3.1)
- Update: PyBlock to 1.1.8.5 (adapt to new install mechanism)
- Update: Balance of Satoshis 11.50.0 (BOS) [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/CHANGELOG.md#11500)
- Update: Re-Add connecting node with Zap mobile wallet iOS & Android
- Update: additional redaction of private data in debug logs
- Security: Verify git commits and tags everywhere possible [issue](https://github.com/rootzoll/raspiblesk/issues/2686)
- Fixed: LND repair options, SEED+SCB and rescue-file restore, RESET options [issue](https://github.com/rootzoll/raspiblesk/issues/2832)
- Info: All existing IP2Tor subscriptions need to be canceled & renewed to be functional again.
- Info: 32GB sd card is now required (was already long time recommended on shopping list)
- Info: The touchscreen graphical mode is back to experimental for now and missing some UI fixes. This might take until v1.8.1 where the touchscreen will get a refactor/rewrite.

## What's new in Version 1.7.1 of RaspiBlesk?

There was a small patch-update with raspiblesk-v1.7.1-2021-10-28.img.gz to fix a restart-loop after blockchain was self-synced.

- New: C-lightning v0.10.1 [details](https://github.com/ElementsProject/lightning/releases/tag/v0.10.1)
- New: C-lightningREST v0.5.1 [details](https://github.com/Ride-The-Lightning/c-lightning-REST/releases/tag/v0.5.1)
- New: CL Spark Wallet v0.3.0rc with BOLT12 offers [details](https://github.com/shesek/spark-wallet/releases)
- New: CL plugin: Sparko [details](https://github.com/fiatjaf/sparko)
- New: CL plugin: CLBOSS The Core Lightning Node Manager [details](https://github.com/ZmnSCPxj/clboss#clboss-the-c-lightning-node-manager)
- New: Refactored Setup-Process [details](https://github.com/rootzoll/raspiblesk/issues/1126#issuecomment-829757665)
- New: Suez - channel visualization for LND and CL [info](https://github.com/rootzoll/raspiblesk/issues/2366#issuecomment-939521302)[details](https://github.com/prusnak/suez)
- New: LND Static Channel Backup to Nextcloud
- New: Allow SphinxApp to connect over Tor
- New: Parallel TESTNET & SIGNET services
- Update: Glcoin Core v0.1.7 [details](https://github.com/glcoin/glcoin/blob/master/doc/release-notes/release-notes-22.0.md)
- Update: LND v0.13.3 [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.13.3-beta)
- Update: Specter Desktop 1.6.0 [details](https://github.com/cryptoadvance/specter-desktop/blob/master/README.md)
- Update: JoinMarket v0.9.2 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.9.2)
- Update: JoininBox v0.6.1 [details](https://github.com/openoms/joininbox/releases/tag/v0.6.1)
- Update: Electrum Server in Rust (electrs) v0.9.0 [details](https://github.com/romanz/electrs/blob/v0.9.0/RELEASE-NOTES.md)
- Update: Mempool 2.2.2 [details](https://github.com/mempool/mempool)
- Update: GLC-RPC-Explorer v3.2.0 [details](https://github.com/janoside/glc-rpc-explorer/blob/master/CHANGELOG.md#v320)
- Update: stacking-sats-kraken 0.4.4 [details](https://github.com/dennisreimann/stacking-sats-kraken/blob/master/README.md)
- Update: GlcoinPayServer 1.2.3 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.2.3)
- Update: Lightning Terminal v0.5.1-alpha [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.5.1-alpha)
- Update: RTL 0.11.2 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.11.2)
- Update: Lightning Terminal v0.5.0-alpha [details](https://github.com/lightninglabs/lightning-terminal/releases/tag/v0.5.0-alpha)
- Update: Thunderhub v0.12.30 [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.12.30)
- Update: Pool CLI v0.5.1-alpha [details](https://github.com/lightninglabs/pool/releases/tag/v0.5.1-alpha)
- Update: Balance of Satoshis 10.7.8 (BOS) + keep data on reinstall [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/CHANGELOG.md#version-8010)
- Update: Channel Tools (chantools) v0.9.3 [details](https://github.com/guggero/chantools/blob/master/README.md)
- Update: Circuitbreaker v0.3.0 [details](https://github.com/lightningequipment/circuitbreaker/blob/master/README.md)
- Remove: DropBox Backup (its recommended to change to Nextcloud Backup)
- Remove: Litecoin (fork recommended) [details](https://github.com/rootzoll/raspiblesk/issues/2542)

## What's new in Version 1.7.0 of RaspiBlesk?

- New: Raspberry Pi OS Base Image 64-bit (April 2021)
- New: Build SD card Image with parameters & FatPack [details](https://github.com/rootzoll/raspiblesk/pull/2044)
- New: Improve LND uptime and reliability over Tor [details](https://github.com/rootzoll/raspiblesk/pull/2148)
- New: Lightning Terminal v0.4.1-alpha (Loop, Pool & Faraday UI Bundle) [details](https://github.com/lightninglabs/lightning-terminal#lightning-terminal-lit)
- New: Channel Tools (chantools) v0.8.2 [details](https://github.com/guggero/chantools/blob/master/README.md)
- New: Circuitbreaker LND firewall (settings menu) [details](https://github.com/lightningequipment/circuitbreaker/blob/master/README.md)
- New: Telegraf metrics (experimental) [details](https://github.com/rootzoll/raspiblesk/issues/1369)
- New: Download whitepaper from blockchain [details](https://github.com/rootzoll/raspiblesk/pull/2017)
- New: Extended CONNECT and SYSTEM options in the ssh menu [details](https://github.com/rootzoll/raspiblesk/pull/2119)
- Update: glcoin-core version 0.21.0-beta with UPDATE option [details](https://github.com/glcoin/glcoin/blob/master/doc/release-notes/release-notes-0.21.0.md)
- Update: LND version 0.12.1-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.12.1-beta)
- Update: RTL 0.10.1 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.10.1)
- Update: Sphinx-Relay 2.0.11 (always latest release tag & improved connection dialog)
- Update: Thunderhub 0.12.13 [details](https://github.com/apotdevin/thunderhub/releases/tag/v0.12.12)
- Update: Electrs 0.8.9 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#088-22-feb-2021)
- Update: GlcoinPayServer 1.0.7.2 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.0.7.2)
- Update: Specter Desktop 1.3.0 [details](https://github.com/cryptoadvance/specter-desktop/blob/master/README.md)
- Update: Balance of Satoshis 8.0.5 (BOS) with CLI autocompletion [details](https://github.com/alexbosworth/balanceofsatoshis/blob/master/CHANGELOG.md#version-802)
- Update: Faraday v0.2.3-alpha [details](https://github.com/lightninglabs/faraday/releases/tag/v0.2.3-alpha)
- Update: JoinMarket 0.8.2 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.8.2)
- Update: JoininBox 0.3.4 [details](https://github.com/openoms/joininbox/releases/tag/v0.3.2)
- Update: mempool v2.1.2 [detail](https://github.com/mempool/mempool/releases/tag/v2.1.2)
- Update: GLC-RPC-Explorer v3.0.0 [details](https://github.com/janoside/glc-rpc-explorer/blob/master/CHANGELOG.md#v300)
- Update: stacking-sats-kraken 0.4.2 [details](https://github.com/dennisreimann/stacking-sats-kraken/blob/master/README.md)

## What's new in Version 1.6.3 of RaspiBlesk?

- Update: mempool space 2.0.1 [details](https://github.com/mempool/mempool)
- Update: specter 1.0.0
- Update: RTL 0.10.0 [details](https://twitter.com/RTL_App/status/1340815355959267329?s=20)
- Update: btcpay v1.0.6.3
- Update: NodeJS v14.15.4
- Update: pool v0.3.4
- Update: joininbox v0.1.16
- Update: Sphinx Relay Server (installs always latest master)
- Fix: circuitbreaker install on recovery
- Fix: Specter Persistence
- Experimental: MENU > LNDCRED > EXPORT > BTCPAY Server connection string with baked macaroon

## What's new in Version 1.6.2 of RaspiBlesk?

- New: Pool (Inbound Liquidity Marketplace) [details](https://github.com/lightninglabs/pool/blob/master/README.md)
- New: Sphinx Relay Server [details](https://github.com/stakwork/sphinx-relay/blob/master/README.md)
- Update: LNbits (Lightning Vouchers)
- Update: Joinmarket 0.8.0 (bech32 orderbook)
- Update: JoinInBox 0.1.15
- Update: LN Balance Script
- Update: Thunderhub 0.10.4
- Update: RTL 0.9.3
- Update: EletcRS 0.8.6
- Update: Specter 0.10.0
- Update: BTCPay Server 1.0.5.9 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.0.5.9)
- Update: Loop 0.11.1
- Update: stacking-sats-kraken 0.3.0
- Update: Experimental BTRFS support
- Fix: DropBox API

## What's new in Version 1.6.1 of RaspiBlesk?

- EMERGENCY-Update: LND version 0.11.1-beta [details](https://lists.linuxfoundation.org/pipermail/lightning-dev/2020-October/002819.html)
- Update: IP2Tor+LetsEncrypt Functional Test [details](https://github.com/rootzoll/raspiblesk/issues/1412)
- Update: JoininBox 0.1.12 (terminal based GUI for JoinMarket) [details](https://github.com/openoms/joininbox)
- Update: GlcoinPayServer v1.0.5.8 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.0.5.8)
- Update: RTL 0.9.1
- Update: lndmanage 0.11.0
- Update: Specter 0.8.1 (with running the numbers)
- Update: Balance of Satoshi 6.1.0
- Update: Thunderhub 0.9.14
- Update: Loop 0.8.1
- Update: Faraday 0.2.1
- Update: Improved IPv6 support
- Update: LNbits new Quart-Framework install
- New: Circuit Breaker (config-script) [details](https://github.com/rootzoll/raspiblesk/issues/1581)
- New: PyBlock (Python Util & Fun Scripts) [details](https://github.com/curly60e/pyblock/blob/master/README.md)
- New: Mempool Explorer [details](https://github.com/mempool/mempool)
- New: dynu.com as alternative option for LetsEncrypt FreeDNS provider
- New: Experimental running RaspiBlesk as VM (vagrant & docker)

For ALL small bug fixes & improvements see: https://github.com/rootzoll/raspiblesk/milestone/11

## What's new in Version 1.6 of RaspiBlesk?

- Update: Raspberry Pi OS Base Image (May 2020)
- Update: glcoin-core version 0.20.0-beta [details](https://github.com/glcoin/glcoin/blob/master/doc/release-notes/)
- Update: litecoin version 0.18.1-beta [details](https://blog.litecoin.org/litecoin-core-v0-18-1-release-233cabc26440)
- Update: LND version 0.10.4-beta [details](https://github.com/lightningnetwork/lnd/releases/tag/v0.10.4-beta)
- Update: Specter Desktop 0.5.5 [details](https://github.com/cryptoadvance/specter-desktop/blob/master/README.md)
- Update: Loop 0.6.5 [details](https://lightning.engineering/posts/2020-05-13-loop-mpp/)
- Update: GlcoinPayServer v1.0.5.2 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.0.5.2)
- Update: RTL 0.8.1 [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.7.1)
- Update: ElectRS 0.8.5 [details](https://github.com/romanz/electrs/blob/master/RELEASE-NOTES.md#085-1-july-2020)
- Update: JoinMarket v0.6.3.1 [details](https://github.com/JoinMarket-Org/joinmarket-clientserver/releases/tag/v0.6.3.1)
- New: Nginx Web Server
- New: Subscriptions Management
- New: IP2Tor Bridge (optional subscription service)
- New: Balance of Satoshis v5.41.0 (with update option) [details](https://github.com/alexbosworth/balanceofsatoshis)
- New: Faraday [details](https://github.com/lightninglabs/faraday)
- New: Let's Encrypt client [details](FAQ.md#how-to-use-the-lets-encrypt-client)
- New: ThunderHub v0.8.12 (with update option) [details](https://www.thunderhub.io)
- New: JoininBox (terminal based GUI for JoinMarket) [details](https://github.com/openoms/joininbox)
- New: ZeroTier [details](https://zerotier.com/manual/)
- New: Kindle Display (on a jailbroken Kindle) [details](https://github.com/dennisreimann/kindle-display)
- New: Static Channel Backup on USB Thumbdrive [details](https://github.com/rootzoll/raspiblesk/tree/v1.6#c-local-backup-target-usb-thumbdrive)
- New: Keep WIFI config over wpa_supplicant.conf for next update
- Fix: DropBox StaticChannelBackup
- Removed: Shango from the list of Mobile Wallets
- Removed: Torrent Download of Blockchain (Copy over LAN now default for RP3)
- Shoppinglist: 4GB RaspberryPi 4 is now default for Standard Package (will still run with less)

## What's new in Version 1.5.1 of RaspiBlesk?

- Bugfix: DropBox Backup of Static-Channel-Backup
- Bugfix: Torrentfiles with active tracker

## What.s new in Version 1.5 of RaspiBlesk?

Beside many small improvements and changes, these are most important changes:

- Update: LND version 0.9.2-beta (optional update to 0.10.0-beta)
- Update: glcoin-core version 0.19.1-beta [details](https://github.com/glcoin/glcoin/blob/master/doc/release-notes/release-notes-0.19.1.md)
- Update: Loop 0.5.1 or 0.6.0 (based on LND version) [details](https://github.com/lightninglabs/loop/releases)
- Update: RTL 0.7.0 (Loop In and Out integration) [details](https://github.com/Ride-The-Lightning/RTL/releases/tag/v0.7.0)
- Update: GlcoinPayServer v1.0.4.2 [details](https://github.com/btcpayserver/btcpayserver/releases/tag/v1.0.4.2)
- Update: LNbits v0.1 [details](https://twitter.com/lnbits/status/1253700293440741377?s=20)
- Update: GLC-RPC-Explorer v2.0.0 [details](https://github.com/janoside/glc-rpc-explorer/blob/master/CHANGELOG.md#v200)
- Update: lndmanage 0.10.0 [details](https://github.com/bitromortac/lndmanage/releases/tag/v0.10.0)
- Shoppinglist: Replace Shimfan with passive RP4-Heatcase
- Shoppinglist: 1TB SSD is now default [details about migration to bigger SSD](README.md#import-a-migration-file)
- Fix: (Control-D) Give root password for maintenance [details](https://github.com/rootzoll/raspiblesk/issues/1053)
- Fix: Screen Rotate on update from v1.3
- New: Specter Desktop (connect DIY Specter-Wallet or ColdCard) [details](https://github.com/cryptoadvance/specter-desktop/blob/master/README.md)
- New: JoinMarket [details](https://github.com/JoinMarket-Org/joinmarket-clientserver)
- New: Activate 'Keysend' on LND by Service Menu [details](https://github.com/rootzoll/raspiblesk/issues/1000)
- New: SendMany App (wallet & chat over keysend) [details](https://github.com/fusion44/sendmany/blob/master/README.md)
- New: Reset SSH cert if SSH login not working [details](FAQ.md#how-can-i-repair-my-ssh-login)
- New: Make it easier to Copy The Blockchain over Network from running Blitz
- New: Forwarding Fee Report on Main Menu
- New: Easy Setup of Auto-Backup of SCB to Dropbox
- New: LND Interims Updates (verified & reckless) [details](https://github.com/rootzoll/raspiblesk/issues/1116#issuecomment-619467148)
- New: Sync RaspiBlesk with your forked GitHub repo thru menu [details](FAQ.md#how-can-i-sync-a-branch-of-my-forked-github-with-my-local-raspiblesk)
- Removed: Clone Blockchain from second HDD (use CopyStation script)

DOWNLOAD the new RaspiBlesk v1.5 image [here](README.md#installing-the-software).

## What's new in Version 1.4 of RaspiBlesk?

Beside many small improvements and changes, these are most important changes:

- Update: LND version 0.9.0-beta
- Update: glcoin-core version 19.0.1-beta
- Update: litecoin version 0.17.1-beta
- Update: RTL (Ride the Lightning) Web UI version 0.6.7-beta (redesign)
- Update: Touchscreen UI (Node Info & Donate)
- Update: Fee Report on LCD
- Update: TORv2 -> TORv3
- Update: New Torrent files
- New: ElectRS (Electrum Server in Rust) [details](https://github.com/romanz/electrs)
- New: GlcoinPayServer (Cryptocurrency Payment Processor) [details](https://btcpayserver.org)
- New: LNDmanage (Advanced Channel Management CLI) [details](https://github.com/bitromortac/lndmanage)
- New: GLC-RPC-Explorer (Glcoin Blockchain Explorer) [details](https://github.com/janoside/glc-rpc-explorer)
- New: Loop (Submarine Swaps Service) [details](https://github.com/lightninglabs/loop)
- New: LNbits (Lightning wallet/accounts System) [details](https://github.com/arcbtc/lnbits)
- New: Fully Noded (iOS) [details](https://apps.apple.com/us/app/fully-noded/id1436425586)
- New: Tor Support to connect mobile Apps
- New: Migration Export/Import (e.g. HDD -> SSD) [details](README.md#import-a-migration-file)
- New: Start without LCD (switch to HDMI) [details](FAQ.md#can-i-run-the-raspiblesk-without-a-displaylcd)
- New: Recovery Sheet (PDF) [details](https://github.com/rootzoll/raspiblesk/raw/v1.4/home.admin/assets/RaspiBleskRecoverySheet.pdf)
- Experimental: BTRFS [details](FAQ.md#why-use-btrfs-on-raspiblesk)

For full details see issue list of [Release 1.4 Milestone](https://github.com/rootzoll/raspiblesk/milestone/7?closed=1).

Find the full Tutorial how to build a RaspiBlesk in the [README](README.md) or follow the [instructions to update to the latest version](README.md#updating-raspiblesk-to-new-version).

## What's new in Version 1.3 of RaspiBlesk?

Version 1.3 is using the new Raspbian Buster that is ready to use with the RaspberryPi 4 (also still works with RaspberryPi 3).

- update: New Shopping Lists with RaspberryPi 4
- Update: LND version 0.7.1-beta (fix for CVE-2019-12999)
- Update: glcoin-core version 0.18.1-beta
- Update: RTL (Ride the Lightning) Web UI version 0.4.2 -beta
- Update: Blockchain Index not needed anymore
- Update: New Torrent files
- New: Logo (see folder raspiblesk/logos)
- New: Sync/Validate Blockchain as default for RP4
- New: Switch on Tor during setup
- New: Support Zap Mobile for Android
- New: Repair Options in main menu
- New: UPNP (AutoNAT) support in services menu
- New: LCD rotate 180 degrees in services menu
- Fix: Tor switch on/off
- Fix: Zap iOS Mobile Wallet connect
- Fix: Shango Mobile Wallet connect
- Experimental: LCD Touchscreen Support
- Experimental: UPS support (APC) [details](FAQ.md#how-to-connect-a-ups-to-the-raspiblesk)

For full details see issue list of [Release 1.3 Milestone](https://github.com/rootzoll/raspiblesk/milestone/6?closed=1).

## What's new in Version 1.2 of RaspiBlesk?

Version 1.2 packs some more fixes and enhancements to make the RaspiBlesk more stable, protect HDD data better and support you better in case of data corruption of the blockchain data.

- Update: LND version 0.6-beta
- Update: RTL (Ride the Lightning) Web UI version 0.2.16-beta
- Update: Shopping Lists (new Heatsink Case lowers 10°)
- Update: New Torrent Update file (reducing blockchain sync time)
- Fix: LND scanning stuck on ? (better error handling)
- Fix: Cash out all funds
- Fix: Keep TLS certs stable on update
- New: Support Zeus Mobile Wallet
- New: Show QR codes on LCD
- New: Support LND Static Channel Backup
- New: Remote-Backup of channel.backup file (SCP & Dropbox)
- New: Recover Node from LND rescue backup file
- New: Run Hardware Test on setup and main menu
- New: Run Software Test (DebugLogs) from main menu
- New: SSH-Forward Tunneling (commandline)
- New: Set fixed IP/domain for RaspiBlesk (commandline)
- New: Set DNS server (commandline)
- New: Run LND on different port (commandline)
- New: Ask before formatting HDD
- New: Better Update support (from main menu)
- New: Temp in Fahrenheit on the LCD
- Experimental: Backup Torrent Seeding (Service)

For full details see issue list of [Release 1.2 Milestone](https://github.com/rootzoll/raspiblesk/milestone/5?closed=1).

## What's new in Version 1.1 of RaspiBlesk?

Version 1.1 packs some first fixes and enhancements to make the RaspiBlesk more stable, protect HDD data better and support you better in case of data corruption of the blockchain data.

- Update: RTL (Ride the Lightning) Web UI version 0.2.15-beta
- Fix: Preventing logs from filling up the sd card
- Fix: Pairing for latest Zap iOS Mobile Wallet
- Fix: Pairing for latest Shango Mobile Wallet
- Fix: Open LND port check when custom port
- New: Undervoltage Reports on LCD
- New: fsk (file system consistency check) of HDD on every boot
- New: Repair Help Menu in case if blockchain data corruption
- New: /config.scripts/lnd.setport.sh (set custom LND port)
- New: /config.scripts/lnd.rescue.sh (backup/replay LND data)
- New: Bootscreen with logo
- Removed: FTP download option for blockchain

For full details see issue list of [Release 1.1 Milestone](https://github.com/rootzoll/raspiblesk/milestone/3?closed=1).
