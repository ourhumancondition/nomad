"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");
const zlib = require("node:zlib");
const policy = require("../pb_hooks/gmail_policy");
const box = require("./crypto_box");
const extract = require("./extract");
const handlers = require("./handlers");

const tokenKey = crypto.randomBytes(32).toString("base64");
const env = {
  GOOGLE_OAUTH_CLIENT_ID: "client-id",
  GOOGLE_OAUTH_CLIENT_SECRET: "client-secret",
  GMAIL_TOKEN_KEY: tokenKey,
  NOMAD_VAULT_SECRET: "vault-secret",
  POCKETBASE_ORIGIN: "http://127.0.0.1:8090",
  NOMAD_PUBLIC_ORIGIN: "https://nomad-taupe-omega.vercel.app",
  GOOGLE_OAUTH_REDIRECT_URI:
    "https://nomad-taupe-omega.vercel.app/api/gmail/callback",
};

function mockRes() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    ended: undefined,
    setHeader(name, value) {
      this.headers[String(name).toLowerCase()] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
    writeHead(code, headers) {
      this.statusCode = code;
      for (const [key, value] of Object.entries(headers || {})) {
        this.headers[String(key).toLowerCase()] = value;
      }
    },
    end(text) {
      this.ended = text || "";
    },
  };
}

test("policy refuses other owners, wide scopes, and foreign return addresses", () => {
  assert.equal(policy.secretsMatch("vault-secret", "vault-secret"), true);
  assert.equal(policy.secretsMatch("", "vault-secret"), false);
  assert.equal(
    policy.authorizeVault({
      expectedSecret: "vault-secret",
      presentedSecret: "vault-secret",
      authId: "owner-b",
      authRequired: true,
      recordUserId: "owner-a",
    }).status,
    404,
  );
  assert.equal(policy.vaultWriteOwner("owner-a"), "owner-a");
  assert.deepEqual(
    policy.recordsForOwner("owner-b", [
      { userId: "owner-a", value: "cipher-a" },
      { userId: "owner-b", value: "cipher-b" },
    ]),
    ["cipher-b"],
  );
  assert.equal(policy.scanAllowed("revoked"), false);
  assert.equal(policy.scanAllowed("connected"), true);
  assert.equal(policy.scopeAllowed(policy.GMAIL_READONLY_SCOPE), true);
  assert.equal(
    policy.scopeAllowed(`${policy.GMAIL_READONLY_SCOPE} https://mail.google.com/`),
    false,
  );
  assert.equal(
    policy.returnOriginAllowed("https://nomad-taupe-omega.vercel.app"),
    true,
  );
  assert.equal(
    policy.returnOriginAllowed(
      "https://nomad-taupe-omega-git-cursor-gmail-receipt-import-92da-team.vercel.app",
    ),
    true,
  );
  assert.equal(policy.returnOriginAllowed("https://evil.example"), false);
  assert.equal(policy.returnOriginAllowed("http://127.0.0.1:43123"), true);
});

test("encryption round trip and html or pdf extraction hide scripts", () => {
  const payload = { refreshToken: "refresh-1", accessToken: "access-1" };
  const cipher = box.encryptJson(payload, tokenKey);
  assert.equal(box.decryptJson(cipher, tokenKey).refreshToken, "refresh-1");
  assert.throws(() => box.decryptJson(`${cipher.slice(0, -4)}AAAA`, tokenKey));

  const html = extract.htmlToText(
    "<script>Flight ZZ999 secret-body</script><p>Flight AC123</p>",
  );
  assert.equal(html.includes("secret-body"), false);
  assert.equal(html.includes("AC123"), true);

  const plainPdf = Buffer.from(
    "%PDF-1.1\n1 0 obj << /Length 20 >> stream\n(Flight AC123) Tj\nendstream\n",
  );
  assert.match(extract.pdfText(plainPdf), /AC123/);
  const inner = Buffer.from("(Flight ZH9001)");
  const compressed = zlib.deflateSync(inner);
  const flatePdf = Buffer.concat([
    Buffer.from(
      `%PDF-1.4\n1 0 obj << /Filter /FlateDecode /Length ${compressed.length} >> stream\n`,
    ),
    compressed,
    Buffer.from("\nendstream\nendobj\n"),
  ]);
  assert.match(extract.pdfText(flatePdf), /ZH9001/);
  assert.equal(
    extract.worthParsing("Flight AC123\nBooking reference: AB12CD\n"),
    true,
  );
  assert.equal(extract.worthParsing("Hello from the airline sale"), false);
  assert.match(extract.SEARCH_QUERY, /shenzhenair.com/);
  assert.equal(extract.SEARCH_QUERY.includes("gmail.modify"), false);
});

test("start refuses a missing client and does not send another user's id", async () => {
  const calls = [];
  const res = mockRes();
  await handlers.handleStart(
    {
      headers: {},
      body: { returnTo: "https://nomad-taupe-omega.vercel.app" },
    },
    res,
    { env: {}, fetch: async () => { throw new Error("called"); } },
  );
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.error, "not_configured");

  const ok = mockRes();
  await handlers.handleStart(
    {
      headers: { authorization: "Bearer user-token", host: "nomad-taupe-omega.vercel.app" },
      body: { returnTo: "https://nomad-taupe-omega.vercel.app", user: "owner-b" },
    },
    ok,
    {
      env,
      fetch: async (url, options) => {
        calls.push({ url, body: JSON.parse(options.body) });
        return { status: 200, json: async () => ({ pendingId: "x" }) };
      },
    },
  );
  assert.equal(ok.statusCode, 200);
  assert.match(ok.body.authorizeUrl, /^https:\/\/accounts\.google\.com\//);
  assert.match(ok.body.authorizeUrl, /gmail\.readonly/);
  assert.equal(ok.body.authorizeUrl.includes("gmail.modify"), false);
  assert.deepEqual(Object.keys(calls[0].body).sort(), ["nonce", "op", "returnTo"]);
  assert.equal(calls[0].body.op, "begin");
  assert.equal(calls[0].body.user, undefined);
  assert.equal(ok.headers["cache-control"], "no-store");
});

test("a revoked vault does not call Gmail", async () => {
  let listed = 0;
  const res = mockRes();
  await handlers.handleScan(
    { headers: { authorization: "Bearer user-token" }, body: {} },
    res,
    {
      env,
      fetch: async () => ({
        status: 200,
        json: async () => ({ status: "revoked", ciphertext: "" }),
      }),
      listMessages: async () => {
        listed += 1;
        return { messages: [] };
      },
    },
  );
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "revoked");
  assert.equal(listed, 0);
  assert.equal(JSON.stringify(res.body).includes("ciphertext"), false);
});

test("scan returns receipt text and not the refresh token", async () => {
  const cipher = box.encryptJson(
    {
      refreshToken: "refresh-secret-value",
      accessToken: "access-secret-value",
      accessExpiresAt: Date.now() + 3600 * 1000,
    },
    tokenKey,
  );
  const res = mockRes();
  await handlers.handleScan(
    { headers: { authorization: "Bearer user-token" }, body: {} },
    res,
    {
      env,
      fetch: async () => ({
        status: 200,
        json: async () => ({ status: "connected", ciphertext: cipher }),
      }),
      refresh: async () => {
        throw new Error("refresh");
      },
      listMessages: async () => ({ messages: [{ id: "m1" }], nextPageToken: "" }),
      getMessage: async () => ({
        id: "m1",
        internalDate: "1760000000000",
        payload: {
          headers: [{ name: "From", value: "Air Canada <tickets@aircanada.example>" }],
          mimeType: "text/plain",
          body: {
            data: Buffer.from(
              "Booking reference: AB12CD\nFlight AC123\nFrom: Toronto (YYZ)\n",
            ).toString("base64url"),
          },
        },
      }),
      getAttachment: async () => null,
    },
  );
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.messages.length, 1);
  assert.equal(res.body.messages[0].from, "tickets@aircanada.example");
  assert.match(res.body.messages[0].text, /AC123/);
  const encoded = JSON.stringify(res.body);
  assert.equal(encoded.includes("refresh-secret-value"), false);
  assert.equal(encoded.includes("access-secret-value"), false);
  assert.equal(encoded.includes(cipher), false);
});

test("a wider Google scope is not stored", async () => {
  let profiled = 0;
  let completed = 0;
  const state = box.signState(
    {
      nonce: "n".repeat(40),
      ret: "https://nomad-taupe-omega.vercel.app",
      exp: Math.floor(Date.now() / 1000) + 600,
    },
    tokenKey,
  );
  const res = mockRes();
  await handlers.handleCallback(
    {
      url: `/api/gmail/callback?code=abc&state=${encodeURIComponent(state)}`,
      headers: { host: "nomad-taupe-omega.vercel.app" },
    },
    res,
    {
      env,
      exchange: async () => ({
        ok: true,
        refreshToken: "refresh",
        accessToken: "access",
        expiresIn: 3600,
        scope: `${policy.GMAIL_READONLY_SCOPE} https://mail.google.com/`,
      }),
      profile: async () => {
        profiled += 1;
        return { ok: true, email: "person@example.com" };
      },
      fetch: async () => {
        completed += 1;
        return { status: 200, json: async () => ({}) };
      },
    },
  );
  assert.equal(res.statusCode, 302);
  assert.match(res.headers.location, /gmail=scope/);
  assert.equal(profiled, 0);
  assert.equal(completed, 0);
});

test("status omits ciphertext", () => {
  const pub = handlers.publicStatus({
    status: "connected",
    googleEmail: "person@example.com",
    scope: policy.GMAIL_READONLY_SCOPE,
    connectedAt: "2026-11-14T00:00:00Z",
    ciphertext: "secret-cipher",
  });
  assert.equal(pub.ciphertext, undefined);
  assert.equal(pub.state, "connected");
  assert.equal(JSON.stringify(pub).includes("secret-cipher"), false);
});
