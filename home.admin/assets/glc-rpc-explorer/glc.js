"use strict";

// Glcoin coin definition for btc-rpc-explorer.
// Mirrors the shape of app/coins/btc.js but with Glcoin parameters.
// Glcoin is a Bitcoin Core fork: same emission schedule (50 coin subsidy,
// 210000-block halving, 10-minute target), bech32 HRP "gc", base58 prefixes
// "G" (P2PKH) / "M" (P2SH), and 8 decimals.
//
// All *ByNetwork fields below are accessed via [global.activeBlockchain]
// in app/utils.js (nextHalvingEstimates, supply estimates, layout templates).
// A missing key on the active chain crashes the render with
// "Cannot read properties of undefined (reading '<chainName>')". Keep every
// field populated for all four chains: main/test/regtest/signet.

const Decimal = require("decimal.js");
Decimal.set({ precision: 32 });

const baseCurrencyUnit = {
	type: "native",
	name: "GLC",
	multiplier: 1,
	default: true,
	values: ["glc", "GLC"],
	decimalPlaces: 8,
};

const coinConfig = {
	name: "Glcoin",
	// v0.15.20 (Bug B2): `ticker` is used by app.js:loadMiningPoolConfigs to
	// build `public/txt/mining-pools-configs/<ticker>` path. Without it,
	// `path.join(__dirname, "public", "txt", "mining-pools-configs", undefined)`
	// throws `ERR_INVALID_ARG_TYPE` at startup (caught as Unhandled Rejection,
	// non-fatal but pollutes the journal). "GLC" matches the BTCEXP_COIN env
	// var the .env template sets and the directory name we'd ship pool configs
	// under if/when Glcoin has multiple mining pools to enumerate.
	ticker: "GLC",
	logoUrlsByNetwork: {
		main: "/img/logo/glc.png",
		test: "/img/logo/glc.png",
		signet: "/img/logo/glc.png",
		regtest: "/img/logo/glc.png",
	},
	coinIconUrlsByNetwork: {
		main: "/img/logo/glc.png",
		test: "/img/logo/glc.png",
		signet: "/img/logo/glc.png",
		regtest: "/img/logo/glc.png",
	},
	coinColorsByNetwork: {
		main: "#C0C0C0",
		test: "#1daf00",
		signet: "#af008c",
		regtest: "#777",
	},
	siteTitle: "Glcoin Explorer",
	siteTitleSuffix: " - Glcoin Explorer",
	siteTitlesByNetwork: {
		main: "Glcoin Explorer",
		test: "Glcoin Testnet Explorer",
		regtest: "Glcoin Regtest Explorer",
		signet: "Glcoin Signet Explorer",
	},
	nodeTitle: "Glcoin Full Node",
	nodeUrl: "https://glcoin.org",
	demoSiteUrl: "https://explorer.glcoin.org",
	demoSiteUrlsByNetwork: {
		main: "https://explorer.glcoin.org",
		test: "https://explorer.glcoin.org",
		signet: "https://explorer.glcoin.org",
	},
	miningPoolsConfigUrls: [],
	maxBlockWeight: 4_000_000,
	maxBlockSize: 1_000_000,
	difficultyAdjustmentBlockCount: 2016,
	targetBlockTimeSeconds: 600,
	targetBlockTimeMinutes: 10,
	currencyUnits: [
		baseCurrencyUnit,
		{ type: "native", name: "mGLC", multiplier: 1_000, values: ["mglc"], decimalPlaces: 5 },
		{ type: "native", name: "bits", multiplier: 1_000_000, values: ["bits"], decimalPlaces: 2 },
		{ type: "native", name: "gsat", multiplier: 100_000_000, values: ["gsat", "glcsat", "sat"], decimalPlaces: 0 },
	],
	baseCurrencyUnit,
	defaultCurrencyUnit: baseCurrencyUnit,
	feeSatoshiPerByteBucketMaxima: [150, 100, 75, 50, 25, 15, 10, 5, 1],

	// Emission schedule — same as Bitcoin (50 GLC subsidy, 210000-block halving).
	// terminalHalvingCount=32: at halving 33 the subsidy 50/2^33 satoshis
	// rounds to 0, so 32 halvings is the effective end of issuance.
	halvingBlockIntervalsByNetwork: {
		main: 210000,
		test: 210000,
		regtest: 150,
		signet: 210000,
	},
	terminalHalvingCountByNetwork: {
		main: 32,
		test: 32,
		regtest: 32,
		signet: 32,
	},
	maxSupplyByNetwork: {
		main: new Decimal(20999999.9769),
		test: new Decimal(21000000),
		regtest: new Decimal(21000000),
		signet: new Decimal(21000000),
	},
	// No historical supply checkpoints yet — chain is young. Empty pair
	// [blockHeight, supply] is still parseable by the UI summary code.
	coinSupplyCheckpointsByNetwork: {
		main: [ 0, new Decimal(0) ],
		test: [ 0, new Decimal(0) ],
		signet: [ 0, new Decimal(0) ],
		regtest: [ 0, new Decimal(0) ],
	},
	utxoSetCheckpointsByNetwork: {
		main: {},
		test: {},
		signet: {},
		regtest: {},
	},
	knownTransactionsByNetwork: {
		main: "",
		test: "",
		signet: "",
		regtest: "",
	},

	genesisBlockHashesByNetwork: {
		// Glcoin chainparams genesis hashes — keep in sync with chainparams.cpp
		// (placeholder values; runtime explorer falls back to RPC anyway)
		main: "",
		test: "",
		signet: "",
		regtest: "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206",
	},
	genesisCoinbaseTransactionIdsByNetwork: {
		main: "",
		test: "",
		signet: "",
		regtest: "",
	},
	genesisCoinbaseTransactionsByNetwork: {
		main: {},
		test: {},
		signet: {},
		regtest: {},
	},
	genesisBlockStatsByNetwork: {
		main: {},
		test: {},
		signet: {},
		regtest: {},
	},
	genesisCoinbaseOutputAddressScripthash: "",
	historicalData: [],
	exchangeRateData: null,
	goldExchangeRateData: null,
	blockRewardFunction: function(blockHeight, chain) {
		const halvings = Math.floor(blockHeight / 210_000);
		if (halvings >= 64) return 0;
		return 50 / Math.pow(2, halvings);
	},
};

module.exports = coinConfig;
