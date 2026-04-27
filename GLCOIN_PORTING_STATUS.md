# RaspiBlesk — Glcoin Porting Status

Last updated: 2026-04-25 (ALL tarballs complete — Fulcrum arm64 done; all 8 tarballs ready)

---

## Done

### Scripts and branding
- All `blitz.*` scripts renamed to `blesk.*` (38 files, 868 call references)
- `blitzapi` → `bleskapi`, `blitzhelp` → `bleskhelp` (148 references)
- No `GLCoin`, `RaspiBlitz`, `Bitcoin` text references remain in user-facing content

### Glcoin node source
- Both trees (`glcoin/` and `glcoin-0.1.7-src/`) build cleanly; all 9 binaries verified
- `glcoin.install.sh` uses tarball-first install (`/tmp/glcoin-0.1.7-src.tar.gz`)
- Bitcoin signet addnodes removed; replaced with `seed.glcoin.org:31618`
- `CHANGES.md` version numbers corrected to `v0.1.7`
- `bonus.glcoin-miner.sh` created — installs `glcoin_miner.py` as systemd service

### Port and config fixes — all config.scripts/ clean
All scripts updated to Glcoin ports (RPC 1617/11617/31617, P2P 1618/11618/31618):
`glcoin.install.sh`, `glcoin.monitor.sh`, `network.aliases.sh`, `lnd.check.sh`,
`bonus.btc-rpc-explorer.sh`, `bonus.electrs.sh`, `bonus.fulcrum.sh`,
`bonus.specter.sh`, `bonus.mempool.sh`, `bonus.squeaknode.sh`,
`bonus.fullynoded.sh`, `bonus.publicpool.sh`, `glcoin.testnet.sh`

Cache key fixes: `btc_mainnet_blocks_verified/headers` → `glc_mainnet_blocks_verified/headers`
in `cl.monitor.sh`, `bonus.electrs.sh`, `bonus.fulcrum.sh`, `network.txindex.sh`

`btcrpcexplorer` system user renamed to `glcrpcexplorer`

### LND — ✅ fully patched and built (amd64 + arm64)
- btcd forked at v0.25.1; `chaincfg/glcoin_params.go` added (mainnet, testnet, regtest, signet)
- LND `chainreg/chainparams.go`: all four Glcoin net params added (RPC 1617/11617/31617/41617)
- LND `config.go` maps `bitcoin.*` flags to Glcoin net params
- `lnd.conf` template: `[Bitcoin]` + `[Bitcoind]` sections with correct RPC port/cookie/ZMQ per network
- `lnd.install.sh` rewritten: tarball-first (`/tmp/lnd-glcoin-VERSION-linux-ARCH.tar.gz`), fallback to full source build (clones btcd + lnd, applies patch, `go mod edit -replace`, `make install`)
- Patch files: `patches/lnd/btcd_glcoin_params.go`, `patches/lnd/lnd_chainreg_glcoin.patch`
- **Pre-built amd64**: `lnd-glcoin-0.20.99-beta-linux-amd64.tar.gz` (39 MB)
- **Pre-built arm64**: `lnd-glcoin-0.20.99-beta-linux-arm64.tar.gz` (36 MB) — cross-compiled with Go 1.24

### CLN — ✅ fully patched and built (amd64)
- `cln-v25.12.1/bitcoin/chainparams.c` patched: Glcoin mainnet entry added (RPC 1617, bech32 `gc`, genesis `6e605c9c...`)
- `patches/cln/chainparams_glcoin.patch` created — apply with `patch -p1` to official CLN v25.12.1
- `cl.install.sh` install branch rewritten: arch detection, tarball-first (`/tmp/cln-glcoin-${CLVERSION}-linux-${arch}.tar.gz`), fallback downloads official source + auto-applies chainparams patch + builds
- `cl.install.sh` `on` branch: `glcoin-cli-wrapper` written, correct RPC port per network, full lightningd config with `bitcoin-cli`/`bitcoin-rpcport`/`bitcoin-rpcpassword`/`bitcoin-datadir`
- Built without Rust plugins (no cln-grpc/wss-proxy); all core C subdaemons included
- **Pre-built amd64**: `cln-glcoin-v25.12.1-linux-amd64.tar.gz` (16 MB) — `bin/` + `libexec/c-lightning/`
- **Pre-built arm64**: `cln-glcoin-v25.12.1-linux-arm64.tar.gz` (16 MB) ✅ — `bin/` + `libexec/c-lightning/`

### electrs — ✅ forked, patched, and built (amd64)
- Forked romanz/electrs at v0.10.10; `src/config.rs` patched: `BitcoinNetwork::from_str` maps
  `"glcoin"` → `Network::Bitcoin` (same block/tx structure; only bech32 HRP differs)
- `patches/electrs/network_glcoin.patch` created — apply with `patch -p1` to official electrs v0.10.10
- `bonus.electrs.sh` updated: tarball-first install + applies patch on source build + re-applies on update
- **Pre-built amd64**: `electrs-glcoin-v0.10.10-linux-amd64.tar.gz` (4.7 MB stripped)
- **Pre-built arm64**: `electrs-glcoin-v0.10.10-linux-arm64.tar.gz` (4.3 MB stripped) ✅

---

## Remaining blockers

### 1. LND arm64 tarball — ✅ DONE
Cross-compiled from `/home/vboxuser/porubing/lnd` with Go 1.24 (amd64 host, CGO_ENABLED=0).
```
/home/vboxuser/porubing/lnd-glcoin-0.20.99-beta-linux-arm64.tar.gz  — 36 MB, statically linked
```
Tags used: `autopilotrpc signrpc walletrpc chainrpc invoicesrpc routerrpc watchtowerrpc neutrinorpc monitoring peersrpc`
Place in `/tmp/` on target before running `lnd.install.sh`.

### 2. CLN pre-built tarball — ✅ DONE (amd64 + arm64)
Built from patched source in `cln-v25.12.1/`. Core C subdaemons only (no Rust plugins).
```
cln-glcoin-v25.12.1-linux-amd64.tar.gz  — 16 MB, stripped
cln-glcoin-v25.12.1-linux-arm64.tar.gz  — 16 MB, stripped  ✅ cross-compiled 2026-04-25
# Place in /tmp/ on target; cl.install.sh picks it up automatically
# Contains: bin/lightningd, bin/lightning-cli, libexec/c-lightning/lightning_*d
```
arm64 cross-compiled on amd64 host using `CC=aarch64-linux-gnu-gcc RUST=0`.
Two CLN host tools (headerversions, cdump-enumstr) required native wrappers — see tools/Makefile patches.

### 3. electrs — ✅ DONE (amd64 + arm64)
Patch written and both binaries built. `network = "glcoin"` in config.toml works.
```
electrs-glcoin-v0.10.10-linux-amd64.tar.gz  — 4.7 MB stripped binary
electrs-glcoin-v0.10.10-linux-arm64.tar.gz  — 4.3 MB stripped binary  ✅ cross-compiled 2026-04-25
```
Tarball contains a single `electrs` binary; place in `/tmp/` and run `bonus.electrs.sh install`.
arm64 built with `cargo build --locked --release --target aarch64-unknown-linux-gnu` (Rust cross-compile).

### 4. Fulcrum — ✅ DONE (amd64 + arm64)
**Root cause (fixed):** Fulcrum's `isCore` detection only matched `/Satoshi:`, classifying
Glcoin (`/Gsatoshi:0.1.7/`) as BCH (no segwit). Patch adds `|| subversion.startsWith("/Gsatoshi:")`
to `isCore` in `src/BitcoinD.cpp`.

- Cloned cculianu/Fulcrum at tag `v2.1.0`
- Applied `patches/fulcrum/glcoin_segwit_detection.patch`
- Built with Qt6 6.8.2, system librocksdb 9.10.0, zlib: `qmake6 && make -j2`
- `bonus.fulcrum.sh` updated: tarball-first install + source-build fallback with auto-patch
- **Pre-built amd64**: `fulcrum-glcoin-v2.1.0-linux-amd64.tar.gz` (1.7 MB stripped) — contains `Fulcrum` + `FulcrumAdmin`
- **Pre-built arm64**: `fulcrum-glcoin-v2.1.0-linux-arm64.tar.gz` (1.6 MB stripped) ✅ cross-compiled 2026-04-25
  Cross-compiled on amd64: all .o files built for aarch64, sed fixed Qt6 lib paths (x86_64→aarch64 in Makefile LIBS), re-linked with `aarch64-linux-gnu-g++`.

### 5. BTCPay / NBXplorer — DEFERRED
NBXplorer has hardcoded Bitcoin chain parameters in C#; needs its own fork.
Not critical for v1 node operation.

---

## Apps that require no chain patching

These connect to LND via REST/gRPC and are chain-agnostic — they work as soon as LND works:

| App | Connects to | Notes |
|-----|-------------|-------|
| bonus.lnbits.sh | LND REST | ready |
| bonus.rtl.sh | LND / CLN | ready |
| bonus.thunderhub.sh | LND REST | ready |
| bonus.albyhub.sh | LND REST | ready |
| bonus.lndg.sh | LND | ready |
| bonus.bos.sh | LND | ready |
| bonus.charge-lnd.sh | LND | ready |
| bonus.mempool.sh | electrs / Fulcrum | ready once electrs/Fulcrum work |

---

## Key Glcoin chain parameters

```
Network name:    glcoin / mainnet
Magic bytes:     0xf9b4b4d9
P2P port:        1618  (testnet: 11618, signet: 31618)
RPC port:        1617  (testnet: 11617, signet: 31617)
bech32 HRP:      gc    (testnet/signet: tgc)
Genesis hash:    6e605c9c92a13a4ffe5c062e1fd04a7de9af2589bdaa5c45cb0417fb2fa6e9ed
Genesis merkle:  7f4dd1e60605976b3b3393f0aaa4cc9d2077ad44b547a6b31413d939f3be0e82
Genesis nTime:   1744761600  (2025-04-16 00:00:00 UTC)
Genesis nNonce:  3
Genesis nBits:   0x207fffff
DNS seed:        seed.glcoin.org
```

---

## Source and binary locations

```
/home/vboxuser/porubing/glcoin-0.1.7-src.tar.gz              — Glcoin node source
/home/vboxuser/porubing/glcoin/                               — Glcoin node (built)
/home/vboxuser/porubing/lnd-glcoin-0.20.99-beta-linux-amd64.tar.gz     — LND (amd64, 39 MB)
/home/vboxuser/porubing/lnd-glcoin-0.20.99-beta-linux-arm64.tar.gz     — LND (arm64, 36 MB) ✅
/home/vboxuser/porubing/cln-glcoin-v25.12.1-linux-amd64.tar.gz         — CLN (amd64, 16 MB) ✅
/home/vboxuser/porubing/cln-glcoin-v25.12.1-linux-arm64.tar.gz         — CLN (arm64, 16 MB) ✅
/home/vboxuser/porubing/electrs-glcoin-v0.10.10-linux-amd64.tar.gz     — electrs (amd64, 4.7 MB) ✅
/home/vboxuser/porubing/electrs-glcoin-v0.10.10-linux-arm64.tar.gz     — electrs (arm64, 4.3 MB) ✅
/home/vboxuser/porubing/fulcrum-glcoin-v2.1.0-linux-amd64.tar.gz       — Fulcrum (amd64, 1.7 MB) ✅ (Fulcrum + FulcrumAdmin)
/home/vboxuser/porubing/fulcrum-glcoin-v2.1.0-linux-arm64.tar.gz       — Fulcrum (arm64, 1.6 MB) ✅ (Fulcrum + FulcrumAdmin)
/home/vboxuser/porubing/cln-v25.12.1/                                   — CLN patched source
/home/vboxuser/porubing/raspiblesk.tar.gz                               — RaspiBlesk (this repo, packed)
/home/vboxuser/porubing/glcoin-website.tar.gz                           — glcoin.org website
/home/vboxuser/porubing/glcoin-miner/                                   — Glcoin miner tool
patches/lnd/btcd_glcoin_params.go                                       — btcd chain params (Go)
patches/lnd/lnd_chainreg_glcoin.patch                                   — LND chainreg annotated diff
patches/cln/chainparams_glcoin.patch                                    — CLN chainparams unified diff
patches/electrs/network_glcoin.patch                                    — electrs network name patch (Rust)
patches/fulcrum/glcoin_segwit_detection.patch                           — Fulcrum isCore segwit detection patch (C++, src/BitcoinD.cpp)
```
