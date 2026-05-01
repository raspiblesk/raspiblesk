# RaspiBlesk Access & Security Guide

## Philosophy

RaspiBlesk is designed for a two-phase security model:

1. **Install phase** — clearnet, SSH key authentication from day one
2. **Operations phase** — Tor-only P2P, WireGuard VPN for admin access, no password auth ever

The goal: by the time the node is serving real funds, your real IP is not publicly associated with any service, and every authentication path is cryptographic — no passwords exposed to the internet at any point.

---

## Phase 1 — Build the SD Card

The build process has two clearly separated phases:

| Phase | Needs internet? | What it does |
|---|---|---|
| **Online** | Yes | Installs packages, downloads services |
| **Offline** | No | Generates all credentials, hardens SSH |

Credentials are born offline and never transmitted over the network.

### Standard build (online + offline in one step)

```bash
sudo bash build_sdcard.sh
```

At the end of the build, the script automatically:
- Generates a fresh ED25519 SSH key pair
- Injects the public key into the image
- Disables password authentication in sshd
- Locks the root and service accounts
- Prints the private key to the terminal

**Copy and save the private key printed to the terminal before proceeding.**

### Credentials-only mode (fully offline)

If you have a pre-built image (packages already installed) and want to generate fresh credentials on an air-gapped machine:

```bash
sudo bash build_sdcard.sh --credentials-only
```

This skips all package installation and only runs the credential generation. Works identically for SD card, USB, and NVMe.

### What the credential phase does

- Generates ED25519 SSH key pair (local crypto only, no network)
- Writes public key to `/home/admin/.ssh/authorized_keys`
- Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config`
- Sets `PermitRootLogin no` in `/etc/ssh/sshd_config`
- Locks `root` and `pi` accounts — no password login possible
- Saves private key to boot partition if accessible (SD/USB convenience)
- Generates a random admin sudo password (for local console use)
- Prints full summary to terminal

**Password-based SSH is never open — not even on first boot.**

### First login

After flashing, save the printed private key to your laptop:

```bash
# Save the key (printed during build) to a file
nano raspiblesk_key   # paste the key, save

chmod 600 raspiblesk_key
ssh -i raspiblesk_key admin@<pi-local-ip>
```

For SD card users: the private key is also saved to the boot partition as `raspiblesk_key` — readable when the card is plugged into your laptop before flashing.

### Flash and boot

Flash the image to your storage (SD card, USB, or NVMe) and insert/connect it to the Pi.

---

## Phase 2 — Initial Setup (Clearnet)

Connect to the Pi over your local network:

```bash
ssh admin@<pi-local-ip>
```

Authentication is key-only. The RaspiBlesk setup menu will launch automatically.

During this phase:
- Glcoin syncs over clearnet (IPv4/IPv6)
- All services install and download dependencies over clearnet
- Port 1618 (Glcoin P2P) is open — peers can connect during sync
- SSH is open on port 22 but **password auth is disabled** — brute force is not possible

Complete the initial setup:
1. Set passwords A, B, C via the setup wizard
   - Passwords now support: `A-Za-z0-9!@#%^&*()_+=<>?.-`
   - Minimum 8 characters
   - Spaces, quotes, and backslash are not allowed
2. Let the blockchain sync fully
3. Set up Lightning (LND or CLN)
4. Install any bonus services you need (GLCPay, Electrs, etc.)

---

## Phase 3 — Enable WireGuard

Before switching to Tor-only, establish your secure admin tunnel first.
**Do this while you still have direct LAN access.**

In the RaspiBlesk SSH menu:

```
SERVICES → WireGuard VPN (admin tunnel) → enable
```

Or from the terminal:

```bash
sudo /home/admin/config.scripts/internet.wireguard.sh on
```

Then add a peer for each device you administer from:

```bash
sudo /home/admin/config.scripts/internet.wireguard.sh addpeer laptop
sudo /home/admin/config.scripts/internet.wireguard.sh showpeer laptop
```

Scan the QR code with the WireGuard app on your device (iOS/Android/desktop).

**Test the tunnel before proceeding:**

```bash
# Connect WireGuard on your device, then:
ssh admin@10.9.0.1
```

If that works, your admin tunnel is operational.

### WireGuard network layout

| Address | Role |
|---|---|
| `10.9.0.1` | RaspiBlesk (server) |
| `10.9.0.2` | First peer (e.g. laptop) |
| `10.9.0.3` | Second peer (e.g. phone) |
| `10.9.0.x` | Additional peers |

The VPN uses UDP port **51820**. This is the only port that remains open after switching to Tor-only mode.

---

## Phase 4 — Switch to Tor-Only

Once WireGuard is confirmed working, switch the node to Tor-only operation:

```
SETTINGS → Tor on
```

Or from the terminal:

```bash
sudo /home/admin/config.scripts/tor.network.sh on
sudo reboot
```

What happens:
- `glcoin.conf` updated: `onlynet=onion`, `proxy=127.0.0.1:9050`, `bind=127.0.0.1`
- UFW **blocks** port 1618 and 11618 (Glcoin P2P clearnet)
- UFW **blocks** port 9735, 10009, 8080 (Lightning clearnet) — Lightning uses Tor hidden service
- All app services get `.onion` hidden service addresses
- Port 51820 (WireGuard) remains open — admin tunnel survives
- Your real IP is no longer associated with any Glcoin or Lightning traffic

**After the reboot:**
- Connect via WireGuard first, then SSH to `10.9.0.1`
- The node is no longer reachable on any clearnet port except 51820

---

## Phase 5 — Lock SSH to WireGuard Subnet

As a final hardening step, restrict SSH so it only accepts connections from the WireGuard subnet. This means even if someone somehow reaches port 22, they cannot attempt to authenticate unless they are already inside the VPN.

```bash
sudo ufw allow from 10.9.0.0/24 to any port 22 comment 'SSH via WireGuard only'
sudo ufw deny 22 comment 'block direct SSH'
sudo ufw reload
```

After this, the attack surface from the internet is exactly **one port: UDP 51820**, and only valid WireGuard handshakes are processed — there is no username/password to brute force.

---

## Password Reference

### User passwords (set during setup)

| Password | Purpose | Where used |
|---|---|---|
| **A** | Admin/SSH login | System user `admin`, SSH |
| **B** | RPC / app password | `glcoin.conf rpcpassword`, service configs |
| **C** | LND wallet unlock | LND wallet encryption |

Allowed characters: `A-Za-z0-9!@#%^&*()_+=<>?.-`
Minimum length: 8 characters

### Service passwords (auto-generated, GLCE-encrypted)

| Password | Purpose | Storage |
|---|---|---|
| GLCPay DB (NBXplorer) | PostgreSQL access | `/mnt/hdd/app-data/btcpay/db_passwords.conf` |
| GLCPay DB (BTCPay) | PostgreSQL access | `/mnt/hdd/app-data/btcpay/db_passwords.conf` |
| LND testnet wallet | Auto-unlock | `/mnt/hdd/app-data/lnd/data/chain/bitcoin/testnet/password.info` |
| LND signet wallet | Auto-unlock | `/mnt/hdd/app-data/lnd/data/chain/bitcoin/signet/password.info` |

Service passwords are generated with full character entropy and encrypted with GLCE before storage. The plaintext password exists only in memory during use.

To view GLCPay service passwords (for cold backup):

```
MAINMENU → GLCPay Server Info → OPTIONS → Show database passwords
```

---

## Port Reference

### Clearnet phase (before Tor)

| Port | Protocol | Purpose | Restriction |
|---|---|---|---|
| 22 | TCP | SSH | Key-only auth |
| 1618 | TCP | Glcoin P2P mainnet | Open (sync) |
| 9735 | TCP | Lightning P2P | Open (Lightning) |
| 51820 | UDP | WireGuard VPN | Open |
| 443 | TCP | Web UI HTTPS | LAN only |
| 80 | TCP | HTTP redirect | LAN only |

### Tor-only phase (after `tor.network.sh on`)

| Port | Protocol | Purpose | Status |
|---|---|---|---|
| 22 | TCP | SSH | WireGuard subnet only |
| 51820 | UDP | WireGuard VPN | Open |
| 1618 | TCP | Glcoin P2P | **Blocked** (Tor hidden service) |
| 9735 | TCP | Lightning P2P | **Blocked** (Tor hidden service) |
| 10009 | TCP | LND gRPC | **Blocked** (LAN only or not needed) |
| 8080 | TCP | LND REST | **Blocked** (LAN only or not needed) |
| 443 | TCP | Web UI | LAN + WireGuard only |

---

## GLCE Encryption

Glcoin includes a built-in asymmetric encryption layer (GLCE) that uses the node's own secp256k1 key pair. Service passwords are encrypted with GLCE before being written to disk.

**How it works:**

```
Random password (in memory)
    ↓ hex-encode
glcoin-cli encryptcontent <hex> <node_pubkey>
    ↓
GLCE blob (hex) written to disk
    ↓ (to use)
glcoin-cli decryptcontent <blob>
    ↓ decode hex
Password in memory — never touches disk as plaintext
```

**Manual decrypt** (for recovery):

```bash
# Get the blob
cat /mnt/hdd/app-data/btcpay/db_passwords.conf

# Decrypt
sudo -u glcoin glcoin-cli -rpcport=1617 decryptcontent "<blob_hex>"
```

**IPFS cold backup** (available in Glcoin v0.2.0):
GLCE blobs can be pinned to IPFS, giving you a decentralized cold backup of encrypted credentials. The CID serves as the recovery reference — even if the disk fails, you can recover as long as you have the `glce.key` from the node's data directory.

---

## Recovery Checklist

Store these items in cold backup (offline, separate from the node):

- [ ] SSH private key (`~/.ssh/id_ed25519`)
- [ ] WireGuard peer config (from `showpeer` command)
- [ ] LND seed words (24 words, shown once during wallet creation)
- [ ] GLCPay database passwords (from the Show passwords menu)
- [ ] `glce.key` file from `/mnt/hdd/app-data/glcoin/` (for GLCE blob recovery)
- [ ] Password B (RPC password — needed to recover service configs)

---

## Summary

```
Build SD card (--ssh-pubkey injected)
         ↓
First boot — key-only SSH, no password auth
         ↓
Install & sync over clearnet
         ↓
Enable WireGuard — test tunnel
         ↓
Switch to Tor-only (tor.network.sh on)
         ↓
Lock SSH to WireGuard subnet
         ↓
Attack surface: UDP 51820 only
         No brute force possible
         Real IP not exposed
```
