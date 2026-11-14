"use strict";

const crypto = require("crypto");
const policy = require("../pb_hooks/gmail_policy");
const box = require("./crypto_box");
const extract = require("./extract");

const SCOPE = policy.GMAIL_READONLY_SCOPE;

function readConfig(env) {
  const source = env || process.env;
  const values = {
    clientId: source.GOOGLE_OAUTH_CLIENT_ID || "",
    clientSecret: source.GOOGLE_OAUTH_CLIENT_SECRET || "",
    tokenKey: source.GMAIL_TOKEN_KEY || "",
    vaultSecret: source.NOMAD_VAULT_SECRET || "",
    pocketbaseOrigin: (
      source.POCKETBASE_ORIGIN || "https://nomad.pockethost.io"
    ).replace(/\/$/, ""),
    publicOrigin: source.NOMAD_PUBLIC_ORIGIN || policy.DEFAULT_PUBLIC_ORIGIN,
    redirectUri: source.GOOGLE_OAUTH_REDIRECT_URI || "",
  };
  const missing = [];
  if (!values.clientId) missing.push("GOOGLE_OAUTH_CLIENT_ID");
  if (!values.clientSecret) missing.push("GOOGLE_OAUTH_CLIENT_SECRET");
  if (!values.tokenKey) missing.push("GMAIL_TOKEN_KEY");
  if (!values.vaultSecret) missing.push("NOMAD_VAULT_SECRET");
  return { ok: missing.length === 0, missing, values };
}

function bearer(req) {
  const raw = req.headers.authorization || req.headers.Authorization || "";
  const value = Array.isArray(raw) ? raw[0] : raw;
  const match = /^Bearer\s+(\S+)$/.exec(String(value));
  return match ? match[1] : "";
}

function publicStatus(body) {
  return {
    state: body && body.status ? body.status : "missing",
    googleEmail: body && body.googleEmail ? body.googleEmail : "",
    scope: body && body.scope ? body.scope : "",
    connectedAt: body && body.connectedAt ? body.connectedAt : "",
  };
}

function noStore(res) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "no-referrer");
}

function sendJson(res, status, body) {
  noStore(res);
  res.status(status).json(body);
}

async function readBody(req) {
  if (req.body && typeof req.body === "object") return req.body;
  const text = await new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => {
      data += chunk;
      if (data.length > 20000) reject(new Error("body"));
    });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
  if (!text) return {};
  return JSON.parse(text);
}

function redirectUriFor(req, config) {
  if (config.values.redirectUri) return config.values.redirectUri;
  const host = String((req.headers && req.headers.host) || "");
  const local = host.startsWith("localhost") || host.startsWith("127.0.0.1");
  return `${local ? "http" : "https"}://${host}/api/gmail/callback`;
}

function authorizeUrl(config, redirectUri, state) {
  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.searchParams.set("client_id", config.values.clientId);
  url.searchParams.set("redirect_uri", redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", SCOPE);
  url.searchParams.set("access_type", "offline");
  url.searchParams.set("prompt", "consent");
  url.searchParams.set("include_granted_scopes", "false");
  url.searchParams.set("state", state);
  return url.toString();
}

async function vault(config, deps, token, path, body) {
  const headers = {
    "content-type": "application/json",
    "x-nomad-vault-secret": config.values.vaultSecret,
  };
  if (token) headers.authorization = `Bearer ${token}`;
  const response = await deps.fetch(
    `${config.values.pocketbaseOrigin}${path}`,
    {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    },
  );
  let parsed = {};
  try {
    parsed = await response.json();
  } catch (err) {
    parsed = {};
  }
  return { httpStatus: response.status, body: parsed || {} };
}

async function handleStart(req, res, deps) {
  const config = readConfig(deps.env);
  if (!config.ok) {
    return sendJson(res, 503, { error: "not_configured" });
  }
  const token = bearer(req);
  if (!token) return sendJson(res, 401, { error: "unauthorized" });
  let body;
  try {
    body = await readBody(req);
  } catch (err) {
    return sendJson(res, 400, { error: "origin" });
  }
  const returnTo = String(body.returnTo || "");
  if (!policy.returnOriginAllowed(returnTo, config.values.publicOrigin)) {
    return sendJson(res, 400, { error: "origin" });
  }
  const nonce = crypto.randomBytes(32).toString("base64url");
  const begun = await vault(config, deps, token, "/api/nomad/gmail/vault", {
    op: "begin",
    nonce,
    returnTo,
  });
  if (begun.httpStatus === 401) {
    return sendJson(res, 401, { error: "unauthorized" });
  }
  if (begun.httpStatus !== 200) {
    return sendJson(res, 502, { error: "vault" });
  }
  const state = box.signState(
    {
      nonce,
      ret: returnTo,
      exp: Math.floor(Date.now() / 1000) + 600,
    },
    config.values.tokenKey,
  );
  return sendJson(res, 200, {
    authorizeUrl: authorizeUrl(config, redirectUriFor(req, config), state),
  });
}

async function handleCallback(req, res, deps) {
  const config = readConfig(deps.env);
  noStore(res);
  if (!config.ok) {
    res.status(503).end("Gmail is not set up on this deployment.");
    return;
  }
  const query = new URL(req.url || "/", "http://localhost").searchParams;
  const state = box.verifyState(query.get("state") || "", config.values.tokenKey);
  const ret =
    state && policy.returnOriginAllowed(state.ret, config.values.publicOrigin)
      ? state.ret
      : "";
  const fail = (code) => {
    if (ret) {
      res.writeHead(302, { Location: `${ret}/?gmail=${code}` });
      res.end();
      return;
    }
    res.status(400).end("Gmail authorization did not finish.");
  };
  if (!state) return fail("error");
  if (query.get("error")) return fail(query.get("error") === "access_denied" ? "denied" : "error");
  const code = query.get("code") || "";
  if (!code) return fail("error");
  const exchanged = await deps.exchange({
    code,
    clientId: config.values.clientId,
    clientSecret: config.values.clientSecret,
    redirectUri: redirectUriFor(req, config),
  });
  if (!exchanged.ok) return fail("error");
  if (!policy.scopeAllowed(exchanged.scope || "")) return fail("scope");
  if (!exchanged.refreshToken) return fail("error");
  const profile = await deps.profile(exchanged.accessToken);
  if (!profile.ok || !profile.email) return fail("error");
  let ciphertext;
  try {
    ciphertext = box.encryptJson(
      {
        refreshToken: exchanged.refreshToken,
        accessToken: exchanged.accessToken || "",
        accessExpiresAt: Date.now() + (exchanged.expiresIn || 0) * 1000,
      },
      config.values.tokenKey,
    );
  } catch (err) {
    return fail("error");
  }
  const completed = await vault(
    config,
    deps,
    "",
    "/api/nomad/gmail/vault/complete",
    {
      pendingId: state.nonce,
      ciphertext,
      googleEmail: profile.email,
      scope: SCOPE,
    },
  );
  if (completed.httpStatus !== 200) return fail("error");
  const storedReturn = String(completed.body.returnTo || "");
  if (storedReturn !== state.ret || !policy.returnOriginAllowed(storedReturn, config.values.publicOrigin)) {
    return fail("error");
  }
  res.writeHead(302, { Location: `${storedReturn}/?gmail=connected` });
  res.end();
}

async function handleStatus(req, res, deps) {
  const config = readConfig(deps.env);
  if (!config.ok) return sendJson(res, 503, { error: "not_configured" });
  const token = bearer(req);
  if (!token) return sendJson(res, 401, { error: "unauthorized" });
  const result = await vault(config, deps, token, "/api/nomad/gmail/vault", {
    op: "status",
  });
  if (result.httpStatus === 401) {
    return sendJson(res, 401, { error: "unauthorized" });
  }
  if (result.httpStatus !== 200) return sendJson(res, 502, { error: "vault" });
  return sendJson(res, 200, publicStatus(result.body));
}

async function handleDisconnect(req, res, deps) {
  const config = readConfig(deps.env);
  if (!config.ok) return sendJson(res, 503, { error: "not_configured" });
  const token = bearer(req);
  if (!token) return sendJson(res, 401, { error: "unauthorized" });
  const got = await vault(config, deps, token, "/api/nomad/gmail/vault", {
    op: "get",
  });
  if (got.httpStatus === 401) {
    return sendJson(res, 401, { error: "unauthorized" });
  }
  if (got.body && got.body.ciphertext) {
    try {
      const tokens = box.decryptJson(got.body.ciphertext, config.values.tokenKey);
      if (tokens && tokens.refreshToken) {
        await deps.revoke(tokens.refreshToken);
      }
    } catch (err) {
      // Local revoke still proceeds. The ciphertext is removed below.
    }
  }
  const done = await vault(config, deps, token, "/api/nomad/gmail/vault", {
    op: "disconnect",
  });
  if (done.httpStatus !== 200) return sendJson(res, 502, { error: "vault" });
  return sendJson(res, 200, publicStatus(done.body));
}

async function handleScan(req, res, deps) {
  const config = readConfig(deps.env);
  if (!config.ok) return sendJson(res, 503, { error: "not_configured" });
  const token = bearer(req);
  if (!token) return sendJson(res, 401, { error: "unauthorized" });
  let body = {};
  try {
    body = await readBody(req);
  } catch (err) {
    body = {};
  }
  const got = await vault(config, deps, token, "/api/nomad/gmail/vault", {
    op: "get",
  });
  if (got.httpStatus === 401) {
    return sendJson(res, 401, { error: "unauthorized" });
  }
  if (got.httpStatus !== 200) return sendJson(res, 502, { error: "vault" });
  const state = publicStatus(got.body).state;
  if (!policy.scanAllowed(state) || !got.body.ciphertext) {
    return sendJson(res, 409, { error: "revoked", state: "revoked" });
  }
  let tokens;
  try {
    tokens = box.decryptJson(got.body.ciphertext, config.values.tokenKey);
  } catch (err) {
    return sendJson(res, 409, { error: "revoked", state: "revoked" });
  }
  let accessToken = tokens.accessToken || "";
  if (!accessToken || Number(tokens.accessExpiresAt || 0) < Date.now() + 60000) {
    const refreshed = await deps.refresh({
      refreshToken: tokens.refreshToken,
      clientId: config.values.clientId,
      clientSecret: config.values.clientSecret,
    });
    if (!refreshed.ok) {
      if (refreshed.invalidGrant) {
        await vault(config, deps, token, "/api/nomad/gmail/vault", {
          op: "disconnect",
        });
      }
      return sendJson(res, 409, { error: "revoked", state: "revoked" });
    }
    accessToken = refreshed.accessToken;
    const next = box.encryptJson(
      {
        refreshToken: tokens.refreshToken,
        accessToken,
        accessExpiresAt: Date.now() + (refreshed.expiresIn || 0) * 1000,
      },
      config.values.tokenKey,
    );
    await vault(config, deps, token, "/api/nomad/gmail/vault", {
      op: "put",
      ciphertext: next,
    });
  }
  const listed = await deps.listMessages({
    accessToken,
    pageToken: String(body.pageToken || ""),
    query: extract.SEARCH_QUERY,
  });
  if (listed.invalidGrant) {
    await vault(config, deps, token, "/api/nomad/gmail/vault", { op: "disconnect" });
    return sendJson(res, 409, { error: "revoked", state: "revoked" });
  }
  const messages = [];
  let skipped = 0;
  for (const item of listed.messages || []) {
    const full = await deps.getMessage({ accessToken, id: item.id });
    if (!full || !full.payload) {
      skipped += 1;
      continue;
    }
    const refs = [];
    extract.attachmentRefs(full.payload, refs);
    const attachments = [];
    for (const ref of refs) {
      if (attachments.length >= 3) break;
      const file = await deps.getAttachment({
        accessToken,
        messageId: item.id,
        attachmentId: ref.id,
      });
      if (file && file.bytes) {
        attachments.push({
          mime: ref.mime,
          filename: ref.filename,
          bytes: file.bytes,
        });
      }
    }
    const reduced = extract.messageText(full.payload, attachments);
    if (!extract.worthParsing(reduced.text)) {
      skipped += 1;
      continue;
    }
    messages.push({
      messageId: String(full.id || item.id),
      from: extract.addressOnly(extract.headerValue(full.payload.headers, "From")),
      date: full.internalDate
        ? new Date(Number(full.internalDate)).toISOString()
        : "",
      text: reduced.text,
      truncated: reduced.truncated,
    });
  }
  return sendJson(res, 200, {
    state: "connected",
    messages,
    skipped,
    nextPageToken: listed.nextPageToken || "",
  });
}

module.exports = {
  SCOPE,
  readConfig,
  bearer,
  publicStatus,
  handleStart,
  handleCallback,
  handleStatus,
  handleDisconnect,
  handleScan,
  authorizeUrl,
};
