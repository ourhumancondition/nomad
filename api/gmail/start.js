"use strict";

const { handleStart } = require("../../gmail_broker/handlers");
const { liveDeps } = require("../../gmail_broker/google");

module.exports = (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method" });
    return;
  }
  return handleStart(req, res, liveDeps(process.env));
};
