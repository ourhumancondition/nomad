"use strict";

const crypto = require("crypto");

function decodeKey(keyB64) {
  const key = Buffer.from(String(keyB64 || ""), "base64");
  if (key.length !== 32) {
    const error = new Error("key");
    error.code = "not_configured";
    throw error;
  }
  return key;
}

function encryptJson(value, keyB64) {
  const key = decodeKey(keyB64);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const enc = Buffer.concat([
    cipher.update(JSON.stringify(value), "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, enc]).toString("base64");
}

function decryptJson(payload, keyB64) {
  const key = decodeKey(keyB64);
  const raw = Buffer.from(String(payload || ""), "base64");
  if (raw.length < 13) {
    const error = new Error("payload");
    error.code = "unreadable";
    throw error;
  }
  const iv = raw.subarray(0, 12);
  const tag = raw.subarray(12, 28);
  const enc = raw.subarray(28);
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(tag);
  const text = Buffer.concat([decipher.update(enc), decipher.final()]).toString(
    "utf8",
  );
  return JSON.parse(text);
}

function signState(payload, key) {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const sig = crypto.createHmac("sha256", String(key)).update(body).digest("base64url");
  return `${body}.${sig}`;
}

function verifyState(state, key) {
  const parts = String(state || "").split(".");
  if (parts.length !== 2 || !parts[0] || !parts[1]) return null;
  const expected = crypto
    .createHmac("sha256", String(key))
    .update(parts[0])
    .digest("base64url");
  const a = Buffer.from(expected);
  const b = Buffer.from(parts[1]);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  let payload;
  try {
    payload = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
  } catch (err) {
    return null;
  }
  if (!payload || typeof payload.exp !== "number" || payload.exp < Date.now() / 1000) {
    return null;
  }
  return payload;
}

module.exports = {
  encryptJson,
  decryptJson,
  signState,
  verifyState,
};
