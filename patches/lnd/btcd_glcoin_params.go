// Drop this file into btcd/chaincfg/ in a forked btcd repo.
// It adds Glcoin mainnet chain parameters alongside Bitcoin's.
//
// Target: github.com/btcsuite/btcd (any recent version used by LND 0.19.x)
// Place:  chaincfg/glcoin_params.go

package chaincfg

import (
	"math/big"
	"time"

	"github.com/btcsuite/btcd/chaincfg/chainhash"
	"github.com/btcsuite/btcd/wire"
)

// Glcoin mainnet magic bytes: 0xf9 0xb4 0xb4 0xd9
// Stored as little-endian uint32: 0xD9B4B4F9
const GlcoinMainnet wire.BitcoinNet = 0xD9B4B4F9

// glcoinGenesisHash is the hash of the first block in the Glcoin blockchain.
// nTime=1744761600  nNonce=3  nBits=0x207fffff
var glcoinGenesisHash = chainhash.Hash([chainhash.HashSize]byte{
	// 6e605c9c92a13a4ffe5c062e1fd04a7de9af2589bdaa5c45cb0417fb2fa6e9ed
	// stored in little-endian (reversed)
	0xed, 0xe9, 0xa6, 0x2f, 0xfb, 0x17, 0x04, 0xcb,
	0x45, 0x5c, 0xaa, 0xbd, 0x89, 0x25, 0xaf, 0xe9,
	0x7d, 0x4a, 0xd0, 0x1f, 0x2e, 0x06, 0x5c, 0xfe,
	0x4f, 0x3a, 0xa1, 0x92, 0x9c, 0x5c, 0x60, 0x6e,
})

// glcoinGenesisMerkleRoot is the merkle root of the Glcoin genesis block.
// 7f4dd1e60605976b3b3393f0aaa4cc9d2077ad44b547a6b31413d939f3be0e82
var glcoinGenesisMerkleRoot = chainhash.Hash([chainhash.HashSize]byte{
	0x82, 0xe0, 0x3b, 0xf3, 0x39, 0xd9, 0x13, 0x14,
	0xb3, 0xa6, 0x47, 0xb5, 0x44, 0xad, 0x77, 0x20,
	0x9d, 0xcc, 0xa4, 0xaa, 0xf0, 0x93, 0x33, 0x3b,
	0x6b, 0x97, 0x05, 0x06, 0xe6, 0xd1, 0x4d, 0x7f,
})

// glcoinGenesisBlock is the genesis block of the Glcoin mainnet.
var glcoinGenesisBlock = wire.MsgBlock{
	Header: wire.BlockHeader{
		Version:    1,
		PrevBlock:  chainhash.Hash{}, // all zeros
		MerkleRoot: glcoinGenesisMerkleRoot,
		Timestamp:  time.Unix(1744761600, 0), // 2025-04-16 00:00:00 UTC
		Bits:       0x207fffff,
		Nonce:      3,
	},
	Transactions: []*wire.MsgTx{glcoinGenesisCoinbaseTx},
}

// glcoinGenesisCoinbaseTx is the coinbase transaction of the Glcoin genesis block.
// Message: "Glcoin Genesis 2026-04-16 - Built for the community"
// Pubkey:  04678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb6
//          49f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5f
var glcoinGenesisCoinbaseTx = &wire.MsgTx{
	Version: 1,
	TxIn: []*wire.TxIn{
		{
			PreviousOutPoint: wire.OutPoint{
				Hash:  chainhash.Hash{},
				Index: 0xffffffff,
			},
			SignatureScript: []byte{
				0x04, 0xff, 0xff, 0x00, 0x1d, // push 4 bytes: 486604799 (nBits)
				0x01, 0x04,                   // push 1 byte: 4
				// push 51 bytes: "Glcoin Genesis 2026-04-16 - Built for the community"
				0x33,
				0x47, 0x6c, 0x63, 0x6f, 0x69, 0x6e, 0x20, 0x47,
				0x65, 0x6e, 0x65, 0x73, 0x69, 0x73, 0x20, 0x32,
				0x30, 0x32, 0x36, 0x2d, 0x30, 0x34, 0x2d, 0x31,
				0x36, 0x20, 0x2d, 0x20, 0x42, 0x75, 0x69, 0x6c,
				0x74, 0x20, 0x66, 0x6f, 0x72, 0x20, 0x74, 0x68,
				0x65, 0x20, 0x63, 0x6f, 0x6d, 0x6d, 0x75, 0x6e,
				0x69, 0x74, 0x79,
			},
			Sequence: 0xffffffff,
		},
	},
	TxOut: []*wire.TxOut{
		{
			Value: 0x12a05f200, // 50 * 1e8 = 5000000000 satoshi
			PkScript: []byte{
				0x41, // OP_DATA_65
				0x04, 0x67, 0x8a, 0xfd, 0xb0, 0xfe, 0x55, 0x48,
				0x27, 0x19, 0x67, 0xf1, 0xa6, 0x71, 0x30, 0xb7,
				0x10, 0x5c, 0xd6, 0xa8, 0x28, 0xe0, 0x39, 0x09,
				0xa6, 0x79, 0x62, 0xe0, 0xea, 0x1f, 0x61, 0xde,
				0xb6, 0x49, 0xf6, 0xbc, 0x3f, 0x4c, 0xef, 0x38,
				0xc4, 0xf3, 0x55, 0x04, 0xe5, 0x1e, 0xc1, 0x12,
				0xde, 0x5c, 0x38, 0x4d, 0xf7, 0xba, 0x0b, 0x8d,
				0x57, 0x8a, 0x4c, 0x70, 0x2b, 0x6b, 0xf1, 0x1d,
				0x5f,
				0xac, // OP_CHECKSIG
			},
		},
	},
	LockTime: 0,
}

// GlcoinMainNetParams defines the network parameters for the main Glcoin network.
var GlcoinMainNetParams = Params{
	Name:        "glcoin",
	Net:         GlcoinMainnet,
	DefaultPort: "1618",
	DNSSeeds: []DNSSeed{
		{"seed.glcoin.org", false},
	},

	// Chain parameters
	GenesisBlock: &glcoinGenesisBlock,
	GenesisHash:  &glcoinGenesisHash,
	PowLimit: func() *big.Int {
		// 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
		p, _ := new(big.Int).SetString(
			"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", 16)
		return p
	}(),
	PowLimitBits:             0x207fffff,
	BIP0034Height:            1,
	BIP0065Height:            1,
	BIP0066Height:            1,
	CoinbaseMaturity:         100,
	SubsidyReductionInterval: 210000,
	TargetTimespan:           14 * 24 * time.Hour, // 2 weeks
	TargetTimePerBlock:       10 * time.Minute,
	RetargetAdjustmentFactor: 4,
	ReduceMinDifficulty:      false,
	MinDiffReductionTime:     0,
	GenerateSupported:        true,

	// Checkpoints — none for fresh chain
	Checkpoints: nil,

	// Rule change activation thresholds (BIP 9)
	RuleChangeActivationThreshold: 1916,
	MinerConfirmationWindow:       2016,

	// Consensus rule change deployments — inherit Bitcoin's but activate from 0
	Deployments: [DefinedDeployments]ConsensusDeployment{},

	// Address encoding
	PubKeyHashAddrID:        0x00, // P2PKH starts with '1'
	ScriptHashAddrID:        0x05, // P2SH starts with '3'
	PrivateKeyID:            0x80, // WIF starts with '5' (uncompressed) or 'K'/'L' (compressed)
	WitnessPubKeyHashAddrID: 0x06,
	WitnessScriptHashAddrID: 0x0A,

	// BIP32 hierarchical deterministic key derivation
	HDPrivateKeyID: [4]byte{0x04, 0x88, 0xad, 0xe4}, // xprv
	HDPublicKeyID:  [4]byte{0x04, 0x88, 0xb2, 0x1e}, // xpub

	// BIP44 coin type
	HDCoinType: 1337, // custom Glcoin coin type

	// Bech32 HRP for SegWit addresses
	Bech32HRPSegwit: "gc",
}

func init() {
	// Register the Glcoin mainnet params so they can be looked up by name or magic.
	if err := Register(&GlcoinMainNetParams); err != nil {
		panic(err)
	}
}
