"use strict";

/**
 * Returns the country Vercel's edge already derived from the connection.
 *
 * Only the two-letter `x-vercel-ip-country` header is read. The IP address,
 * city, region and coordinates headers are not read, logged or returned,
 * and nothing is stored. Off Vercel (local dev) the header is absent and
 * the answer is `{"country": null}`.
 */
function handleWhere(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "GET") {
    res.status(405).json({ error: "method" });
    return;
  }
  const raw = req.headers && req.headers["x-vercel-ip-country"];
  const value = Array.isArray(raw) ? raw[0] : raw;
  const code = typeof value === "string" ? value.trim().toUpperCase() : "";
  // "XX" is Vercel's unknown marker. Tor and similar values are not letters.
  const country = /^[A-Z]{2}$/.test(code) && code !== "XX" ? code : null;
  res.status(200).json({ country });
}

module.exports = { handleWhere };
