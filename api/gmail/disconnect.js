"use strict";

const { handleDisconnect } = require("../../gmail_broker/handlers");
const { liveDeps } = require("../../gmail_broker/google");

module.exports = (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method" });
    return;
  }
  return handleDisconnect(req, res, liveDeps(process.env));
};