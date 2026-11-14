"use strict";

const { handleStatus } = require("../../gmail_broker/handlers");
const { liveDeps } = require("../../gmail_broker/google");

module.exports = (req, res) => {
  if (req.method !== "GET") {
    res.status(405).json({ error: "method" });
    return;
  }
  return handleStatus(req, res, liveDeps(process.env));
};
