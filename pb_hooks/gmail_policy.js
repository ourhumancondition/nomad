"use strict";

// Shared by the PocketBase hook and the Vercel broker.
// Keep the decisions aligned with lib/engine/gmail_access.dart.

var GMAIL_READONLY_SCOPE = "https://www.googleapis.com/auth/gmail.readonly";
var DEFAULT_PUBLIC_ORIGIN = "https://nomad-taupe-omega.vercel.app";

function secretsMatch(expected, presented) {
  if (!expected || !presented) return false;
  if (expected.length !== presented.length) return false;
  var mismatch = 0;
  for (var i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ presented.charCodeAt(i);
  }
  return mismatch === 0;
}

function authorizeVault(args) {
  if (!secretsMatch(args.expectedSecret, args.presentedSecret)) {
    return { ok: false, status: 403 };
  }
  if (args.authRequired && !args.authId) {
    return { ok: false, status: 401 };
  }
  if (args.recordUserId && args.recordUserId !== args.authId) {
    return { ok: false, status: 404 };
  }
  return { ok: true, status: 200 };
}

function vaultWriteOwner(authId) {
  return authId;
}

function recordsForOwner(authId, rows) {
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].userId === authId) out.push(rows[i].value);
  }
  return out;
}

function scanAllowed(state) {
  return state === "connected";
}

function scopeAllowed(scope) {
  var parts = String(scope || "").split(/\s+/);
  var kept = [];
  for (var i = 0; i < parts.length; i++) {
    if (parts[i]) kept.push(parts[i]);
  }
  return kept.length === 1 && kept[0] === GMAIL_READONLY_SCOPE;
}

function splitOrigin(origin) {
  if (typeof origin !== "string") return null;
  if (origin.indexOf("?") !== -1 || origin.indexOf("#") !== -1) return null;
  if (origin.indexOf("@") !== -1) return null;
  var match = /^(https?):\/\/([A-Za-z0-9.-]+)(?::(\d+))?(\/[^?#]*)?$/.exec(
    origin,
  );
  if (!match) return null;
  var path = match[4] || "";
  if (path && path !== "/") return null;
  return { scheme: match[1], host: match[2] };
}

function returnOriginAllowed(origin, publicOrigin) {
  var parts = splitOrigin(origin);
  if (!parts) return false;
  if (
    parts.scheme === "http" &&
    (parts.host === "localhost" || parts.host === "127.0.0.1")
  ) {
    return true;
  }
  if (parts.scheme !== "https") return false;
  var pub = splitOrigin(publicOrigin || DEFAULT_PUBLIC_ORIGIN);
  if (!pub) return false;
  if (parts.host === pub.host) return true;
  var suffix = ".vercel.app";
  if (
    parts.host.slice(-suffix.length) !== suffix ||
    pub.host.slice(-suffix.length) !== suffix
  ) {
    return false;
  }
  var prefix = pub.host.slice(0, -suffix.length);
  return parts.host.indexOf(prefix + "-") === 0;
}

module.exports = {
  GMAIL_READONLY_SCOPE: GMAIL_READONLY_SCOPE,
  DEFAULT_PUBLIC_ORIGIN: DEFAULT_PUBLIC_ORIGIN,
  secretsMatch: secretsMatch,
  authorizeVault: authorizeVault,
  vaultWriteOwner: vaultWriteOwner,
  recordsForOwner: recordsForOwner,
  scanAllowed: scanAllowed,
  scopeAllowed: scopeAllowed,
  returnOriginAllowed: returnOriginAllowed,
};
