"use strict";

const { handleCallback } = require("../../gmail_broker/handlers");
const { liveDeps } = require("../../gmail_broker/google");

module.exports = (req, res) => {
  if (req.method !== "GET") {
    res.status(405).end("Gmail authorization did not finish.");
    return;
  }
  return handleCallback(req, res, liveDeps(process.env));
};
