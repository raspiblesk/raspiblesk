#!/usr/bin/env python3
# Copyright (c) 2026 Glcoin developers
# Distributed under the MIT software license.

"""
glcoin-miner — Glcoin mining + verification worker.

Two mining paths are supported, switched at the command line:

  • ``mine-plain``      Assemble a block from mempool transactions only.
                        No IPFS commitment is written into the coinbase.
                        Used whenever there is no pending IPFS link.

  • ``mine-ipfs``       Before assembling the block the miner must
                        successfully verify the IPFS link (transaction
                        exists on-chain, CID parses, content reachable
                        and — for raw-codec CIDs — hash matches).  Only
                        then an ``OP_RETURN`` commitment
                        ``"glc1" || cid-bytes`` is appended to the
                        coinbase and the block is submitted.

Additional subcommands:

  • ``verify`` / ``watch`` / ``check-cid`` — the existing verification
    pipeline kept for operators who want to audit the on-node IPFS
    link database without mining.

The tool talks exclusively to a local ``glcoind`` via JSON-RPC:
``getblocktemplate`` → local assembly/hashing → ``submitblock``.
It never performs consensus decisions itself — the node has the final
say — but it enforces the dual-path policy *before* submission.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import logging
import os
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


# ---------------------------------------------------------------------------
# Debug log (`buglog`)
# ---------------------------------------------------------------------------
# Why this exists: running under systemd with stdout/stderr piped to journal,
# CPython block-buffers writes by default unless PYTHONUNBUFFERED=1 is set or
# python is launched with -u. That made the miner look like a silent zombie:
# no startup banner, no errors, no progress lines for many minutes. buglog()
# always flushes after every line AND mirrors to a persistent file so
# diagnostics survive a journal rotation. Use it for everything in the hot
# mining loops; reserve `print(json.dumps(...))` for the machine-readable
# block-accepted records on stdout.
DEFAULT_BUGLOG_FILE = "/mnt/hdd/app-data/glcoin-miner/miner.log"
_BUGLOG: logging.Logger | None = None


def _init_buglog() -> logging.Logger:
    global _BUGLOG
    if _BUGLOG is not None:
        return _BUGLOG
    log = logging.getLogger("glcoin-miner")
    log.setLevel(logging.DEBUG)
    log.propagate = False
    fmt = logging.Formatter(
        "%(asctime)s %(levelname)-5s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    # stderr handler — visible in `journalctl -u glcoin-miner`. AutoFlush via
    # StreamHandler's emit() + flush(); combined with PYTHONUNBUFFERED=1 in
    # the service unit, lines appear in journal in real time.
    sh = logging.StreamHandler(sys.stderr)
    sh.setFormatter(fmt)
    log.addHandler(sh)
    # File handler — survives journal vacuum + lets `tail -f` work cleanly.
    path = os.environ.get("GLCOIN_MINER_LOG", DEFAULT_BUGLOG_FILE)
    try:
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, mode=0o755, exist_ok=True)
        fh = logging.FileHandler(path, mode="a", encoding="utf-8")
        fh.setFormatter(fmt)
        log.addHandler(fh)
    except OSError as e:
        # No file — keep going with stderr only. Note via stderr what failed.
        sys.stderr.write(f"buglog: cannot open {path}: {e}\n")
        sys.stderr.flush()
    _BUGLOG = log
    return log


def buglog(msg: str, level: str = "info") -> None:
    """Timestamped, always-flushed log line to stderr + a file. Safe to call
    before/during/after mining loops. Levels: debug, info, warn, error."""
    log = _init_buglog()
    lvl = level.lower()
    if lvl in ("warn", "warning"):
        log.warning(msg)
    elif lvl == "error":
        log.error(msg)
    elif lvl == "debug":
        log.debug(msg)
    else:
        log.info(msg)
    for h in log.handlers:
        try:
            h.flush()
        except Exception:
            pass


DEFAULT_RPC_URL = "http://127.0.0.1:1617/"
DEFAULT_RPC_URL_REGTEST = "http://127.0.0.1:41617/"
DEFAULT_RPC_URL_SIGNET = "http://127.0.0.1:31617/"
DEFAULT_RPC_URL_TESTNET4 = "http://127.0.0.1:21617/"
# Local Kubo gateway only — RaspiBlesk runs Kubo as a mandatory dependency,
# and public gateways break the threat model (third party sees which CIDs the
# miner fetches, and can lie about content / hashes if reachability is faked).
DEFAULT_GATEWAYS = (
    "http://127.0.0.1:8080/ipfs/",
)


# ---------------------------------------------------------------------------
# JSON-RPC client
# ---------------------------------------------------------------------------
class RPCError(RuntimeError):
    pass


@dataclass
class RPCClient:
    url: str
    user: str
    password: str
    timeout: float = 30.0
    _id: int = 0

    def call(self, method: str, *params: Any) -> Any:
        self._id += 1
        body = json.dumps(
            {"jsonrpc": "1.0", "id": str(self._id), "method": method, "params": list(params)}
        ).encode()

        auth = base64.b64encode(f"{self.user}:{self.password}".encode()).decode()
        req = urllib.request.Request(
            self.url,
            data=body,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Basic {auth}",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as exc:
            raw = exc.read() or b""
            try:
                payload = json.loads(raw)
            except ValueError:
                raise RPCError(f"HTTP {exc.code}: {raw[:200]!r}") from None
            err = payload.get("error") or {}
            raise RPCError(f"{method}: {err.get('message') or payload}") from None
        except urllib.error.URLError as exc:
            raise RPCError(f"RPC transport error: {exc.reason}") from None
        except socket.timeout:
            raise RPCError(f"RPC timeout after {self.timeout}s")

        payload = json.loads(raw)
        if payload.get("error"):
            raise RPCError(f"{method}: {payload['error']}")
        return payload["result"]


def load_cookie(datadir: Path) -> tuple[str, str] | None:
    for subdir in ["", "regtest", "testnet4", "signet"]:
        cookie = datadir / subdir / ".cookie" if subdir else datadir / ".cookie"
        if not cookie.is_file():
            continue
        try:
            user, password = cookie.read_text().split(":", 1)
            return user, password
        except ValueError:
            continue
    return None


# ---------------------------------------------------------------------------
# CID parsing & hash verification
# ---------------------------------------------------------------------------
B58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def b58decode(s: str) -> bytes:
    n = 0
    for ch in s:
        idx = B58_ALPHABET.find(ch)
        if idx < 0:
            raise ValueError(f"invalid base58 char {ch!r}")
        n = n * 58 + idx
    body = n.to_bytes((n.bit_length() + 7) // 8, "big") if n else b""
    # Preserve leading 1s → leading zero bytes
    pad = len(s) - len(s.lstrip("1"))
    return b"\x00" * pad + body


def b32_rfc4648_lower_decode(s: str) -> bytes:
    s = s.upper()
    pad = (-len(s)) % 8
    return base64.b32decode(s + "=" * pad)


@dataclass
class ParsedCID:
    version: int
    codec: int          # multicodec (0x70 dag-pb, 0x55 raw, ...)
    hash_fn: int        # multihash hash function code (0x12 = sha2-256)
    hash_len: int
    digest: bytes
    raw: str


def _read_varint(buf: bytes, offset: int) -> tuple[int, int]:
    value, shift = 0, 0
    while True:
        if offset >= len(buf):
            raise ValueError("varint truncated")
        b = buf[offset]
        offset += 1
        value |= (b & 0x7F) << shift
        if not (b & 0x80):
            return value, offset
        shift += 7
        if shift > 63:
            raise ValueError("varint too long")


def parse_cid(cid: str) -> ParsedCID:
    # CIDv0 — base58btc, always dag-pb + sha2-256
    if len(cid) == 46 and cid.startswith("Qm"):
        data = b58decode(cid)
        if len(data) != 34 or data[0] != 0x12 or data[1] != 0x20:
            raise ValueError("malformed CIDv0 multihash")
        return ParsedCID(0, 0x70, 0x12, 0x20, data[2:], cid)

    if not cid:
        raise ValueError("empty CID")

    prefix, body = cid[0], cid[1:]
    if prefix == "b":
        data = b32_rfc4648_lower_decode(body)
    elif prefix == "B":
        data = base64.b32decode(body + "=" * ((-len(body)) % 8))
    elif prefix == "z":
        data = b58decode(body)
    elif prefix == "f":
        data = binascii.unhexlify(body)
    else:
        raise ValueError(f"unsupported multibase prefix {prefix!r}")

    version, o = _read_varint(data, 0)
    if version != 1:
        raise ValueError(f"unexpected CID version {version}")
    codec, o = _read_varint(data, o)
    hash_fn, o = _read_varint(data, o)
    hash_len, o = _read_varint(data, o)
    digest = data[o:o + hash_len]
    if len(digest) != hash_len:
        raise ValueError("multihash digest truncated")
    return ParsedCID(1, codec, hash_fn, hash_len, digest, cid)


def verify_content_hash(parsed: ParsedCID, content: bytes) -> bool:
    """Only applies to raw-codec (0x55) CIDs — dag-pb wraps content in a
    protobuf envelope so a naive hash over the gateway bytes will not
    match. For dag-pb we fall back to reachability-only."""
    if parsed.codec != 0x55:
        return True
    if parsed.hash_fn == 0x12:
        return hashlib.sha256(content).digest() == parsed.digest
    if parsed.hash_fn == 0x1B:
        try:
            return hashlib.new("blake2b", content, digest_size=parsed.hash_len).digest() == parsed.digest
        except ValueError:
            return False
    return False


# ---------------------------------------------------------------------------
# IPFS reachability
# ---------------------------------------------------------------------------
def fetch_from_gateways(cid: str, gateways: Iterable[str], timeout: float = 15.0,
                       max_bytes: int = 4 * 1024 * 1024) -> tuple[str, bytes] | None:
    for base in gateways:
        url = urllib.parse.urljoin(base, cid)
        try:
            with urllib.request.urlopen(url, timeout=timeout) as resp:
                content = resp.read(max_bytes + 1)
                if len(content) > max_bytes:
                    return url, content[:max_bytes]
                return url, content
        except (urllib.error.URLError, socket.timeout, ConnectionError):
            continue
    return None


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
@dataclass
class VerificationResult:
    txid: str
    cid: str
    description: str
    timestamp: int
    tx_ok: bool
    tx_confirmations: int | None
    cid_format_ok: bool
    gateway_url: str | None
    hash_match: bool | None
    error: str = ""

    def as_row(self) -> str:
        flags = []
        flags.append("TX" if self.tx_ok else "tx")
        flags.append("CID" if self.cid_format_ok else "cid")
        flags.append("GW" if self.gateway_url else "gw")
        if self.hash_match is True:
            flags.append("H")
        elif self.hash_match is False:
            flags.append("h!")
        else:
            flags.append("h?")
        conf = "-" if self.tx_confirmations is None else str(self.tx_confirmations)
        return f"[{'|'.join(flags)}] conf={conf:>4} {self.cid}  ({self.txid[:16]}…) {self.error}"

    @property
    def passed(self) -> bool:
        if not (self.tx_ok and self.cid_format_ok and self.gateway_url):
            return False
        return self.hash_match is not False


def verify_link(rpc: RPCClient, link: dict, gateways: Iterable[str],
                fetch: bool = True) -> VerificationResult:
    txid = link["txid"]
    cid = link["cid"]
    result = VerificationResult(
        txid=txid,
        cid=cid,
        description=link.get("description", ""),
        timestamp=int(link.get("timestamp", 0)),
        tx_ok=False,
        tx_confirmations=None,
        cid_format_ok=False,
        gateway_url=None,
        hash_match=None,
    )

    try:
        tx = rpc.call("getrawtransaction", txid, True)
        result.tx_ok = True
        result.tx_confirmations = tx.get("confirmations")
    except RPCError as exc:
        result.error = f"tx lookup failed: {exc}"

    try:
        parsed = parse_cid(cid)
        result.cid_format_ok = True
    except ValueError as exc:
        result.error = (result.error + f" cid parse: {exc}").strip()
        return result

    if not fetch:
        return result

    got = fetch_from_gateways(cid, gateways)
    if got is None:
        result.error = (result.error + " gateway: unreachable").strip()
        return result
    result.gateway_url, body = got
    result.hash_match = verify_content_hash(parsed, body)
    return result


# ---------------------------------------------------------------------------
# Address → scriptPubKey (without wallet / getaddressinfo)
# ---------------------------------------------------------------------------
_BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
_BECH32M_CONST = 0x2BC830A3


def _bech32_polymod(values: Iterable[int]) -> int:
    GEN = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    chk = 1
    for v in values:
        b = chk >> 25
        chk = (chk & 0x1FFFFFF) << 5 ^ v
        for i in range(5):
            chk ^= GEN[i] if (b >> i) & 1 else 0
    return chk


def _bech32_hrp_expand(hrp: str) -> list:
    return [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]


def _bech32_decode_raw(bech: str):
    bech = bech.lower()
    if any(ord(c) < 33 or ord(c) > 126 for c in bech):
        return None
    pos = bech.rfind("1")
    if pos < 1 or len(bech) - pos - 1 < 6:
        return None
    hrp = bech[:pos]
    data_chars = bech[pos + 1:]
    if any(c not in _BECH32_CHARSET for c in data_chars):
        return None
    data = [_BECH32_CHARSET.index(c) for c in data_chars]
    const = _bech32_polymod(_bech32_hrp_expand(hrp) + data)
    if const == 1:
        enc = "bech32"
    elif const == _BECH32M_CONST:
        enc = "bech32m"
    else:
        return None
    return hrp, data[:-6], enc


def _convertbits_addr(data: list, frombits: int, tobits: int, pad: bool = True):
    acc, bits = 0, 0
    ret: list = []
    maxv = (1 << tobits) - 1
    max_acc = (1 << (frombits + tobits - 1)) - 1
    for value in data:
        if value < 0 or value >> frombits:
            return None
        acc = ((acc << frombits) | value) & max_acc
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            ret.append((acc >> bits) & maxv)
    if pad:
        if bits:
            ret.append((acc << (tobits - bits)) & maxv)
    elif bits >= frombits or ((acc << (tobits - bits)) & maxv):
        return None
    return ret


def _segwit_scriptpubkey(addr: str) -> bytes | None:
    """Derive the scriptPubKey from a bech32/bech32m address without wallet RPC."""
    decoded = _bech32_decode_raw(addr)
    if decoded is None:
        return None
    _hrp, data, enc = decoded
    if not data:
        return None
    witver = data[0]
    if witver > 16:
        return None
    witprog = _convertbits_addr(data[1:], 5, 8, False)
    if witprog is None or len(witprog) < 2 or len(witprog) > 40:
        return None
    if witver == 0 and enc != "bech32":
        return None
    if witver != 0 and enc != "bech32m":
        return None
    if witver == 0 and len(witprog) not in (20, 32):
        return None
    op = 0x00 if witver == 0 else (0x50 + witver)
    return bytes([op, len(witprog)] + witprog)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def rpc_from_args(args: argparse.Namespace) -> RPCClient:
    user, password = args.rpc_user, args.rpc_password
    datadir = args.datadir
    if datadir is None:
        datadir = str(Path.home() / ".glcoin")

    url = args.rpc_url
    datadir_path = Path(datadir)

    if url == DEFAULT_RPC_URL and datadir:
        chain_try_order = [
            (DEFAULT_RPC_URL_REGTEST, datadir_path / "regtest"),
            (DEFAULT_RPC_URL_TESTNET4, datadir_path / "testnet4"),
            (DEFAULT_RPC_URL_SIGNET, datadir_path / "signet"),
            (DEFAULT_RPC_URL, datadir_path),
        ]
        for try_url, cookie_path in chain_try_order:
            cookie_file = cookie_path / ".cookie"
            if not cookie_file.is_file():
                continue
            try:
                cred_user, cred_pass = cookie_file.read_text().split(":", 1)
            except ValueError:
                continue
            try:
                temp_rpc = RPCClient(url=try_url, user=cred_user, password=cred_pass, timeout=10.0)
                chain_info = temp_rpc.call("getblockchaininfo")
                chain = chain_info.get("chain", "main")
                if chain == "regtest":
                    url = DEFAULT_RPC_URL_REGTEST
                elif chain == "signet":
                    url = DEFAULT_RPC_URL_SIGNET
                elif chain == "test":
                    url = DEFAULT_RPC_URL_TESTNET4
                else:
                    url = try_url
                user, password = cred_user, cred_pass
                break
            except RPCError:
                continue
        else:
            url = DEFAULT_RPC_URL

    if not user or not password:
        creds = load_cookie(datadir_path)
        if creds:
            user, password = creds

    if not user or not password:
        print("error: no RPC credentials (pass --rpc-user/--rpc-password or --datadir with .cookie)",
              file=sys.stderr)
        sys.exit(2)

    return RPCClient(url=url, user=user, password=password, timeout=args.timeout)


# ---------------------------------------------------------------------------
# Glcoin block assembly (two mining paths)
# ---------------------------------------------------------------------------
# Both paths share the same header-hashing loop; they only differ in the
# coinbase output set.  The IPFS path appends one extra OP_RETURN carrying
# a 4-byte magic ("glc1") + the raw CID bytes, but only after the link has
# passed verify_link().
IPFS_COMMIT_MAGIC = b"glc1"

# Anti-spam burn rates per chain (sat / CID byte).
# Must match consensus.IPFSCommitBurnPerByte in kernel/chainparams.cpp.
BURN_PER_BYTE: dict[str, int] = {
    "main":    69,
    "test":    69,     # testnet3
    "test4":   69,     # testnet4
    "signet":  100,
    "regtest": 0,
}


def get_anchor_burn_sats(rpc: RPCClient, anchor_txid: str) -> int:
    """Sum the satoshi values of all OP_RETURN outputs in the anchor tx."""
    raw = rpc.call("getrawtransaction", anchor_txid, True)
    total = 0
    for vout in raw.get("vout", []):
        spk = vout.get("scriptPubKey", {})
        # "nulldata" is the gettxoutsetinfo/getrawtransaction type name for OP_RETURN.
        if spk.get("type") == "nulldata":
            sats = round(vout.get("value", 0.0) * 1e8)
            total += sats
    return total


def check_anchor_burn(rpc: RPCClient, anchor_txid: str, cid: str) -> None:
    """Raise RPCError if the anchor tx does not satisfy the burn rule."""
    chain_info = rpc.call("getblockchaininfo")
    chain = chain_info.get("chain", "main")
    burn_per_byte = BURN_PER_BYTE.get(chain, 1000)
    if burn_per_byte == 0:
        return  # disabled on this chain
    cid_bytes = cid_to_binary(cid)
    required = len(cid_bytes) * burn_per_byte
    actual = get_anchor_burn_sats(rpc, anchor_txid)
    if actual < required:
        raise RPCError(
            f"anchor tx {anchor_txid[:16]}… burns only {actual} gsat; "
            f"need {required} gsat ({len(cid_bytes)} CID bytes × {burn_per_byte} gsat/byte) — "
            f"consensus would reject with ipfs-commit-anchor-underpaid"
        )


def dsha256(data: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def varint(n: int) -> bytes:
    if n < 0xFD:
        return bytes([n])
    if n <= 0xFFFF:
        return b"\xfd" + n.to_bytes(2, "little")
    if n <= 0xFFFFFFFF:
        return b"\xfe" + n.to_bytes(4, "little")
    return b"\xff" + n.to_bytes(8, "little")


def push_data(data: bytes) -> bytes:
    """Minimal script push for arbitrary ``data``."""
    n = len(data)
    if n < 0x4C:
        return bytes([n]) + data
    if n <= 0xFF:
        return b"\x4c" + bytes([n]) + data
    if n <= 0xFFFF:
        return b"\x4d" + n.to_bytes(2, "little") + data
    return b"\x4e" + n.to_bytes(4, "little") + data


def encode_num(n: int) -> bytes:
    """BIP34 height encoding - matches Bitcoin Core's CScript() << nHeight"""
    if n == 0:
        return bytes([0x00])  # OP_0
    if 1 <= n <= 16:
        return bytes([0x50 + n])  # OP_1 to OP_16
    # For n >= 17, use minimal push encoding
    neg = n < 0
    n = abs(n)
    out = bytearray()
    while n:
        out.append(n & 0xFF)
        n >>= 8
    if out[-1] & 0x80:
        out.append(0x80 if neg else 0x00)
    elif neg:
        out[-1] |= 0x80
    return bytes([len(out)]) + bytes(out)


def encode_coinbase(height: int, extra_nonce: int, reward_sats: int,
                    payout_script: bytes,
                    witness_commitment_spk: bytes | None,
                    ipfs_commitment_spk: bytes | None) -> bytes:
    """Serialise a coinbase transaction (with witness when commitment is present)."""
    script_sig = encode_num(height) + push_data(extra_nonce.to_bytes(8, "little"))

    outputs: list[tuple[int, bytes]] = [(reward_sats, payout_script)]
    if ipfs_commitment_spk is not None:
        outputs.append((0, ipfs_commitment_spk))
    if witness_commitment_spk is not None:
        outputs.append((0, witness_commitment_spk))

    has_witness = witness_commitment_spk is not None
    out = bytearray()
    out += (1).to_bytes(4, "little")                 # version
    if has_witness:
        out += b"\x00\x01"                            # segwit marker + flag
    out += varint(1)                                  # vin count
    out += b"\x00" * 32                               # prev txid
    out += b"\xff\xff\xff\xff"                        # prev vout
    out += varint(len(script_sig)) + script_sig
    out += b"\xff\xff\xff\xff"                        # sequence
    out += varint(len(outputs))
    for value, spk in outputs:
        out += value.to_bytes(8, "little")
        out += varint(len(spk)) + spk
    if has_witness:
        out += varint(1) + varint(32) + (b"\x00" * 32)  # single-stack reserved value
    out += (0).to_bytes(4, "little")                  # locktime
    return bytes(out)


def coinbase_txid(coinbase_bytes: bytes) -> bytes:
    """Coinbase txid is computed from the *stripped* (no-witness) serialisation."""
    # Locate marker+flag (bytes 4,5). If present strip witness section before final 4 locktime bytes.
    if len(coinbase_bytes) >= 6 and coinbase_bytes[4:6] == b"\x00\x01":
        stripped = coinbase_bytes[:4] + coinbase_bytes[6:]
        # Remove witness stack (sits before the final 4-byte locktime).  The
        # previously-serialised witness has varint(1)+varint(32)+32 = 34 bytes.
        stripped = stripped[:-4 - 34] + stripped[-4:]
        return dsha256(stripped)
    return dsha256(coinbase_bytes)


def merkle_root(leaves: list[bytes]) -> bytes:
    if not leaves:
        return b"\x00" * 32
    level = leaves[:]
    while len(level) > 1:
        if len(level) % 2 == 1:
            level.append(level[-1])
        level = [dsha256(level[i] + level[i + 1]) for i in range(0, len(level), 2)]
    return level[0]


def assemble_header(template: dict, merkle: bytes, nonce: int, time_override: int | None = None) -> bytes:
    version = int(template["version"]).to_bytes(4, "little", signed=False)
    prev = bytes.fromhex(template["previousblockhash"])[::-1]
    ts = int(time_override if time_override is not None else template["curtime"]).to_bytes(4, "little")
    bits = bytes.fromhex(template["bits"])[::-1]
    return version + prev + merkle + ts + bits + nonce.to_bytes(4, "little")


def bits_to_target(bits_hex: str) -> int:
    bits = int(bits_hex, 16)
    exp = bits >> 24
    mant = bits & 0x007FFFFF
    if exp <= 3:
        return mant >> (8 * (3 - exp))
    return mant << (8 * (exp - 3))


def cid_to_binary(cid: str) -> bytes:
    """Canonical binary form of a CID, byte-for-byte identical to what
    ``ParseCIDBytes`` in ``src/consensus/ipfscommit.cpp`` expects.

    CIDv0 → raw 34-byte multihash (``0x12 0x20 <sha256>``).
    CIDv1 → multibase-decoded bytes (``varint(version) varint(codec)
    varint(hash_fn) varint(hash_len) digest``)."""
    if len(cid) == 46 and cid.startswith("Qm"):
        data = b58decode(cid)
        if len(data) != 34 or data[0] != 0x12 or data[1] != 0x20:
            raise ValueError("malformed CIDv0 multihash")
        return data

    if not cid:
        raise ValueError("empty CID")

    prefix, body = cid[0], cid[1:]
    if prefix == "b":
        return b32_rfc4648_lower_decode(body)
    if prefix == "B":
        return base64.b32decode(body + "=" * ((-len(body)) % 8))
    if prefix == "z":
        return b58decode(body)
    if prefix == "f":
        return binascii.unhexlify(body)
    raise ValueError(f"unsupported multibase prefix {prefix!r}")


def build_ipfs_commitment_script(anchor_txid_hex: str, cid: str) -> bytes:
    """Build the consensus OP_RETURN commitment expected by
    ``CheckBlockIPFSCommitment``:

        OP_RETURN push( "glc1" || anchor_txid(32) || cid_binary )

    ``anchor_txid_hex`` is the RPC/display-order hex string; the node
    stores txids in internal byte order, so we reverse before
    embedding."""
    anchor_bytes = bytes.fromhex(anchor_txid_hex)[::-1]
    if len(anchor_bytes) != 32:
        raise ValueError(f"anchor txid must be 32 bytes, got {len(anchor_bytes)}")
    cid_bytes = cid_to_binary(cid)
    payload = IPFS_COMMIT_MAGIC + anchor_bytes + cid_bytes
    if len(payload) > 80:
        raise ValueError(f"OP_RETURN payload too large ({len(payload)} > 80)")
    return b"\x6a" + push_data(payload)               # OP_RETURN + push


def decode_address_to_scriptpubkey(rpc: RPCClient, address: str) -> bytes:
    spk = _segwit_scriptpubkey(address)
    if spk is not None:
        return spk
    # Fall back to RPC for non-bech32 addresses (requires wallet)
    info = rpc.call("getaddressinfo", address)
    spk_hex = info.get("scriptPubKey")
    if not spk_hex:
        raise RPCError(f"cannot derive scriptPubKey for {address}")
    return bytes.fromhex(spk_hex)


def mine_block(rpc: RPCClient, payout_address: str, ipfs_cid: str | None,
               ipfs_anchor_txid: str | None = None,
               max_tries: int = 1_000_000, progress_every: int = 500_000) -> dict:
    """Assemble + PoW-search a single block.  Returns the submit result
    (empty string on success)."""
    template = rpc.call("getblocktemplate", {"rules": ["segwit"]})
    height = int(template["height"])
    reward = int(template["coinbasevalue"])
    payout_spk = decode_address_to_scriptpubkey(rpc, payout_address)
    buglog(
        f"template fetched height={height} reward={reward} gsats "
        f"txs={len(template.get('transactions', []))} target_bits={template.get('bits')}",
        level="debug",
    )

    witness_spk: bytes | None = None
    wc_hex = template.get("default_witness_commitment")
    if wc_hex:
        witness_spk = bytes.fromhex(wc_hex)

    tx_entries = template.get("transactions", [])

    ipfs_spk: bytes | None = None
    if ipfs_cid is not None:
        if not ipfs_anchor_txid:
            raise ValueError("mine_block: ipfs_cid requires ipfs_anchor_txid")
        # Consensus requires the anchor tx to live in the same block as
        # the coinbase commitment, so reject upfront if the template
        # does not contain it — otherwise submitblock will bounce with
        # ``ipfs-commit-anchor-missing``.
        template_txids = {t["txid"] for t in tx_entries}
        if ipfs_anchor_txid not in template_txids:
            raise RPCError(
                f"anchor txid {ipfs_anchor_txid[:16]}… is not in the block template "
                f"(mempool does not contain it) — consensus would reject the block"
            )
        ipfs_spk = build_ipfs_commitment_script(ipfs_anchor_txid, ipfs_cid)

    tx_hashes = [bytes.fromhex(tx["txid"])[::-1] for tx in tx_entries]
    tx_hex_blob = "".join(tx["data"] for tx in tx_entries)

    target = bits_to_target(template["bits"])
    extra_nonce = 0
    tries = 0
    start = time.monotonic()

    # Each extra_nonce iteration covers the full 32-bit nonce space (4G hashes).
    # max_tries caps the total search regardless of how many extra_nonce steps are used.
    while tries < max_tries:
        cb = encode_coinbase(height, extra_nonce, reward, payout_spk, witness_spk, ipfs_spk)
        cb_id = coinbase_txid(cb)
        root = merkle_root([cb_id] + tx_hashes)
        for nonce in range(0, 0x100000000):
            header = assemble_header(template, root, nonce)
            h = int.from_bytes(dsha256(header)[::-1], "big")
            if h < target:
                block_hex = header.hex() + varint(1 + len(tx_hashes)).hex() + cb.hex() + tx_hex_blob
                result = rpc.call("submitblock", block_hex)
                elapsed = time.monotonic() - start
                return {
                    "accepted": result in (None, ""),
                    "result": result,
                    "height": height,
                    "nonce": nonce,
                    "extra_nonce": extra_nonce,
                    "hash": dsha256(header)[::-1].hex(),
                    "elapsed_s": round(elapsed, 2),
                    "tries": tries,
                    "ipfs": ipfs_cid,
                }
            tries += 1
            if tries % progress_every == 0:
                rate = tries / max(time.monotonic() - start, 1e-6)
                buglog(
                    f"mining h={height} {tries:,} hashes {rate/1e3:.1f} kH/s "
                    f"extra_nonce={extra_nonce}",
                    level="debug",
                )
            if tries >= max_tries:
                break
        extra_nonce += 1
    raise RPCError(f"no solution in {max_tries:,} hashes")


# ---------------------------------------------------------------------------
# Mining subcommands
# ---------------------------------------------------------------------------
def cmd_mine_plain(args: argparse.Namespace) -> int:
    rpc = rpc_from_args(args)
    buglog(f"mine-plain: payout={args.address} max_tries={args.max_tries:,}")
    consecutive_rpc_errors = 0
    while True:
        try:
            info = mine_block(rpc, args.address, ipfs_cid=None, max_tries=args.max_tries)
            consecutive_rpc_errors = 0
        except RPCError as exc:
            msg = str(exc)
            if "no solution" in msg:
                buglog(f"template exhausted (no solution in {args.max_tries:,} hashes) — refreshing template", level="debug")
                continue
            consecutive_rpc_errors += 1
            buglog(f"RPC error #{consecutive_rpc_errors}: {exc} — sleeping 30s", level="error")
            time.sleep(30)
            continue
        # Block found — keep stdout JSON for machine consumers, but also tag
        # the human log so journal users see it.
        buglog(
            f"block FOUND height={info.get('height')} hash={info.get('hash','')[:16]}… "
            f"tries={info.get('tries'):,} elapsed={info.get('elapsed_s')}s accepted={info.get('accepted')}"
        )
        print(json.dumps(info, indent=2), flush=True)
        if not info["accepted"]:
            buglog(f"block rejected by node: {info.get('result')} — retry in 5s", level="warn")
            time.sleep(5)


def cmd_mine_ipfs(args: argparse.Namespace) -> int:
    rpc = rpc_from_args(args)

    if not args.from_store and not args.cid:
        print("error: --cid is required when --from-store is not set", file=sys.stderr)
        return 2

    link = {"txid": args.txid, "cid": args.cid, "description": args.description,
            "timestamp": int(time.time())}
    if args.from_store:
        stored = rpc.call("getipfslink", args.txid)
        link = stored

    gateways = args.gateway or list(DEFAULT_GATEWAYS)
    verify = verify_link(rpc, link, gateways, fetch=not args.no_fetch)
    print("IPFS verification:", verify.as_row(), file=sys.stderr)
    if not verify.passed and not args.force:
        print("refusing to mine — IPFS link did not pass verification (use --force to override)",
              file=sys.stderr)
        return 2

    # Pre-flight: verify burn rule before starting PoW.
    # The node enforces this at submitblock time; checking here gives a
    # clear error message and avoids wasted hashing work.
    if not getattr(args, "skip_burn_check", False):
        try:
            check_anchor_burn(rpc, link["txid"], link["cid"])
        except RPCError as exc:
            print(f"burn check failed: {exc}", file=sys.stderr)
            if not args.force:
                return 2

    while True:
        try:
            info = mine_block(rpc, args.address, ipfs_cid=link["cid"],
                              ipfs_anchor_txid=link["txid"], max_tries=args.max_tries)
        except RPCError as exc:
            msg = str(exc)
            if "no solution" in msg:
                continue
            print(f"error: {exc}", file=sys.stderr)
            return 1
        print(json.dumps(info, indent=2), flush=True)
        # After success: persist the link in the node DB (idempotent).
        try:
            rpc.call("storeipfslink", link["txid"], link["cid"], link.get("description", ""))
        except RPCError:
            pass
        return 0 if info["accepted"] else 1


def cmd_verify(args: argparse.Namespace) -> int:
    rpc = rpc_from_args(args)
    links = rpc.call("listipfslinks")
    if args.txid:
        links = [l for l in links if l["txid"] in args.txid]
    if not links:
        print("no IPFS links stored on this node")
        return 0

    gateways = args.gateway or list(DEFAULT_GATEWAYS)
    failed: list[VerificationResult] = []
    for link in links:
        res = verify_link(rpc, link, gateways, fetch=not args.no_fetch)
        print(res.as_row())
        if not res.passed:
            failed.append(res)

    if failed and args.remove_bad:
        for res in failed:
            if res.tx_ok and res.cid_format_ok:
                continue  # only prune records whose anchor or CID is invalid
            try:
                rpc.call("removeipfslink", res.txid)
                print(f"  removed {res.txid[:16]}… ({res.error})", file=sys.stderr)
            except RPCError as exc:
                print(f"  remove failed for {res.txid[:16]}…: {exc}", file=sys.stderr)

    print(f"\n{len(links) - len(failed)}/{len(links)} records verified OK")
    return 0 if not failed else 1


def cmd_watch(args: argparse.Namespace) -> int:
    rpc = rpc_from_args(args)
    seen: set[str] = set()
    gateways = args.gateway or list(DEFAULT_GATEWAYS)
    print(f"watching node {args.rpc_url}  interval={args.interval}s")
    while True:
        try:
            links = rpc.call("listipfslinks")
        except RPCError as exc:
            print(f"rpc error: {exc}", file=sys.stderr)
            time.sleep(args.interval)
            continue
        new = [l for l in links if l["txid"] not in seen]
        for link in new:
            seen.add(link["txid"])
            res = verify_link(rpc, link, gateways, fetch=not args.no_fetch)
            print(res.as_row())
        time.sleep(args.interval)


def cmd_check_cid(args: argparse.Namespace) -> int:
    try:
        parsed = parse_cid(args.cid)
    except ValueError as exc:
        print(f"invalid CID: {exc}", file=sys.stderr)
        return 1
    print(
        f"version=v{parsed.version} codec=0x{parsed.codec:02x} "
        f"hash_fn=0x{parsed.hash_fn:02x} hash_len={parsed.hash_len} "
        f"digest={parsed.digest.hex()}"
    )
    if args.fetch:
        got = fetch_from_gateways(args.cid, args.gateway or list(DEFAULT_GATEWAYS))
        if got is None:
            print("unreachable via any gateway")
            return 1
        url, body = got
        match = verify_content_hash(parsed, body)
        print(f"fetched {len(body)} bytes from {url} hash_match={match}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="glcoin-miner", description=__doc__)
    p.add_argument("--rpc-url", default=os.environ.get("GLCOIN_RPC_URL", DEFAULT_RPC_URL))
    p.add_argument("--rpc-user", default=os.environ.get("GLCOIN_RPC_USER", ""))
    p.add_argument("--rpc-password", default=os.environ.get("GLCOIN_RPC_PASSWORD", ""))
    p.add_argument("--datadir", default=os.environ.get("GLCOIN_DATADIR",
                                                       str(Path.home() / ".glcoin")))
    p.add_argument("--gateway", action="append",
                   help="IPFS HTTP gateway (default: local Kubo at http://127.0.0.1:8080/ipfs/)")
    p.add_argument("--timeout", type=float, default=30.0)

    sub = p.add_subparsers(dest="cmd", required=True)

    v = sub.add_parser("verify", help="verify stored ipfslink records")
    v.add_argument("--no-fetch", action="store_true", help="skip IPFS gateway fetch")
    v.add_argument("--remove-bad", action="store_true",
                   help="delete records whose tx or cid is invalid")
    v.add_argument("--txid", action="append", help="only verify given txid(s)")
    v.set_defaults(func=cmd_verify)

    w = sub.add_parser("watch", help="continuously verify newly added links")
    w.add_argument("--interval", type=float, default=30.0)
    w.add_argument("--no-fetch", action="store_true")
    w.set_defaults(func=cmd_watch)

    c = sub.add_parser("check-cid", help="parse + optionally fetch a single CID")
    c.add_argument("cid")
    c.add_argument("--fetch", action="store_true")
    c.set_defaults(func=cmd_check_cid)

    mp = sub.add_parser("mine-plain",
                        help="assemble + hash a block without any IPFS commitment")
    mp.add_argument("--address", required=True, help="coinbase payout address")
    mp.add_argument("--max-tries", type=int, default=20_000_000)
    mp.set_defaults(func=cmd_mine_plain)

    mi = sub.add_parser("mine-ipfs",
                        help="verify an IPFS link, then mine a block that commits to it")
    mi.add_argument("--address", required=True, help="coinbase payout address")
    mi.add_argument("--txid", required=True)
    mi.add_argument("--cid", help="(ignored when --from-store is used)")
    mi.add_argument("--description", default="")
    mi.add_argument("--from-store", action="store_true",
                    help="load the link from the node DB via getipfslink")
    mi.add_argument("--no-fetch", action="store_true",
                    help="skip gateway reachability (format+tx checks only)")
    mi.add_argument("--force", action="store_true",
                    help="mine even when verification fails (not recommended)")
    mi.add_argument("--max-tries", type=int, default=20_000_000)
    mi.set_defaults(func=cmd_mine_ipfs)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    # Startup banner — proves the service launched and shows what it'll do.
    cmd = getattr(args, "cmd", "?")
    addr = getattr(args, "address", None)
    txid = getattr(args, "txid", None)
    buglog(
        f"glcoin-miner starting: cmd={cmd}"
        + (f" address={addr}" if addr else "")
        + (f" anchor_txid={txid}" if txid else "")
        + f" rpc={args.rpc_url}"
    )
    try:
        return args.func(args)
    except KeyboardInterrupt:
        buglog("interrupted (KeyboardInterrupt)", level="warn")
        return 130
    except Exception as exc:
        buglog(f"unhandled exception: {type(exc).__name__}: {exc}", level="error")
        raise


if __name__ == "__main__":
    sys.exit(main())
