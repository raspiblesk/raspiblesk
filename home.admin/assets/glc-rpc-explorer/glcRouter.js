"use strict";

// Glcoin-specific routes for btc-rpc-explorer.
// Mounted from app.js by apply-glcoin-patches.sh.
//
// /miners        — listminers <status> (KYC registry)
// /ipfs-links    — listipfslinks (anchored CIDs)
// /ipfs-pins     — listipfspins (locally pinned CIDs on the connected kubo)

const express = require("express");
const router = express.Router();
const asyncHandler = require("express-async-handler");
const rpcApi = require("./../app/api/rpcApi.js");

const VALID_MINER_STATUS = ["approved", "pending", "revoked", "suspended", "all"];

router.get("/miners", asyncHandler(async (req, res, next) => {
	const requested = (req.query.status || "approved").toLowerCase();
	const filter = VALID_MINER_STATUS.includes(requested) ? requested : "approved";

	res.locals.filter = filter;
	res.locals.allFilters = VALID_MINER_STATUS;
	res.locals.miners = [];
	res.locals.error = null;

	try {
		const data = await rpcApi.getRpcDataWithParams({
			method: "listminers",
			parameters: [filter],
		});
		res.locals.miners = Array.isArray(data) ? data : [];
	} catch (e) {
		res.locals.error = (e && e.message) ? e.message : String(e);
	}

	res.render("glc-miners");
	next();
}));

router.get("/ipfs-links", asyncHandler(async (req, res, next) => {
	const limit = Math.max(1, Math.min(500, parseInt(req.query.limit || "50", 10) || 50));
	const offset = Math.max(0, parseInt(req.query.offset || "0", 10) || 0);

	res.locals.limit = limit;
	res.locals.offset = offset;
	res.locals.links = [];
	res.locals.error = null;

	try {
		const data = await rpcApi.getRpcDataWithParams({
			method: "listipfslinks",
			parameters: [limit, offset],
		});
		res.locals.links = Array.isArray(data) ? data : [];
	} catch (e) {
		res.locals.error = (e && e.message) ? e.message : String(e);
	}

	res.render("glc-ipfs-links");
	next();
}));

router.get("/ipfs-pins", asyncHandler(async (req, res, next) => {
	const type = (req.query.type || "all").toLowerCase();
	res.locals.type = type;
	res.locals.pins = {};
	res.locals.error = null;

	try {
		const data = await rpcApi.getRpcDataWithParams({
			method: "listipfspins",
			parameters: [type],
		});
		// listipfspins returns { Keys: { <cid>: { Type: "..." } } } from kubo,
		// passed through. Defensive: accept any shape.
		if (data && typeof data === "object") {
			res.locals.pins = data.Keys || data.keys || data;
		}
	} catch (e) {
		res.locals.error = (e && e.message) ? e.message : String(e);
	}

	res.render("glc-ipfs-pins");
	next();
}));

module.exports = router;
