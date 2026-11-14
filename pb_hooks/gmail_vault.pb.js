/// Token vault for one PocketBase user.
///
/// Handlers are self-contained. This PocketBase build does not let a route
/// call a function declared elsewhere in the file. gmail_policy.js mirrors
/// the same decisions for the Node tests.
///
/// gmail_links is locked on the records API. A request can only touch the
/// signed-in user's row. Complete uses the user stored when the attempt began.

routerAdd("POST", "/api/nomad/gmail/vault", (e) => {
  const headers = e.requestInfo().headers || {};
  const presented = String(
    headers.x_nomad_vault_secret ||
      headers["x-nomad-vault-secret"] ||
      headers["X-Nomad-Vault-Secret"] ||
      "",
  );
  const expected = $os.getenv("NOMAD_VAULT_SECRET") || "";
  let mismatch = 0;
  let matched = expected && presented && expected.length === presented.length;
  if (matched) {
    for (let i = 0; i < expected.length; i++) {
      mismatch |= expected.charCodeAt(i) ^ presented.charCodeAt(i);
    }
    matched = mismatch === 0;
  }
  if (!matched) throw new ForbiddenError("The vault secret was refused.");
  if (!e.auth || !e.auth.id) {
    throw new UnauthorizedError("Sign in is required.");
  }
  const owner = String(e.auth.id);
  const body = e.requestInfo().body || {};
  const op = String(body.op || "");
  let link = null;
  try {
    link = $app.findFirstRecordByFilter("gmail_links", "user = {:user}", {
      user: owner,
    });
  } catch (err) {
    link = null;
  }
  const status = link
    ? {
        status: String(link.get("status") || "missing"),
        googleEmail: String(link.get("google_email") || ""),
        scope: String(link.get("scope") || ""),
        connectedAt: String(link.get("connected_at") || ""),
      }
    : { status: "missing", googleEmail: "", scope: "", connectedAt: "" };

  if (op === "status") return e.json(200, status);
  if (op === "get") {
    return e.json(200, {
      status: status.status,
      googleEmail: status.googleEmail,
      scope: status.scope,
      connectedAt: status.connectedAt,
      ciphertext:
        link && status.status === "connected"
          ? String(link.get("token_ciphertext") || "")
          : "",
    });
  }
  if (op === "disconnect") {
    if (!link) return e.json(200, status);
    link.set("status", "revoked");
    link.set("token_ciphertext", "");
    $app.save(link);
    return e.json(200, {
      status: "revoked",
      googleEmail: status.googleEmail,
      scope: status.scope,
      connectedAt: status.connectedAt,
    });
  }
  if (op === "put") {
    if (!link || status.status !== "connected") {
      throw new BadRequestError("Gmail is not connected.");
    }
    const ciphertext = String(body.ciphertext || "");
    if (!/^[A-Za-z0-9+/=_-]{20,8000}$/.test(ciphertext)) {
      throw new BadRequestError("The token payload was refused.");
    }
    link.set("token_ciphertext", ciphertext);
    $app.save(link);
    return e.json(200, status);
  }
  if (op === "begin") {
    const nonce = String(body.nonce || "");
    if (!/^[A-Za-z0-9_-]{32,80}$/.test(nonce)) {
      throw new BadRequestError("The pending id was refused.");
    }
    const returnTo = String(body.returnTo || "");
    const publicOrigin =
      $os.getenv("NOMAD_PUBLIC_ORIGIN") ||
      "https://nomad-taupe-omega.vercel.app";
    const publicHost =
      publicOrigin.indexOf("https://") === 0 ? publicOrigin.slice(8) : "";
    const httpsHost =
      returnTo.indexOf("https://") === 0 ? returnTo.slice(8) : "";
    const suffix = ".vercel.app";
    const allowed =
      (httpsHost &&
        publicHost &&
        httpsHost === publicHost &&
        httpsHost.indexOf("/") === -1) ||
      (publicHost.slice(-suffix.length) === suffix &&
        httpsHost.indexOf(publicHost.slice(0, -suffix.length) + "-") === 0 &&
        httpsHost.slice(-suffix.length) === suffix &&
        httpsHost.indexOf("/") === -1) ||
      /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(returnTo);
    if (!allowed) throw new BadRequestError("The return address was refused.");
    const record = new Record($app.findCollectionByNameOrId("gmail_pending"));
    record.set("user", owner);
    record.set("nonce", nonce);
    record.set("return_to", returnTo);
    record.set("expires_at", String(Date.now() + 10 * 60 * 1000));
    record.set("consumed", false);
    $app.save(record);
    return e.json(200, { pendingId: nonce });
  }
  throw new BadRequestError("The operation is not supported.");
});

routerAdd("POST", "/api/nomad/gmail/vault/complete", (e) => {
  const headers = e.requestInfo().headers || {};
  const presented = String(
    headers.x_nomad_vault_secret ||
      headers["x-nomad-vault-secret"] ||
      headers["X-Nomad-Vault-Secret"] ||
      "",
  );
  const expected = $os.getenv("NOMAD_VAULT_SECRET") || "";
  let matched = !!(expected && presented && expected.length === presented.length);
  if (matched) {
    let mismatch = 0;
    for (let i = 0; i < expected.length; i++) {
      mismatch |= expected.charCodeAt(i) ^ presented.charCodeAt(i);
    }
    matched = mismatch === 0;
  }
  if (!matched) throw new ForbiddenError("The vault secret was refused.");
  const body = e.requestInfo().body || {};
  const scope = String(body.scope || "");
  if (scope !== "https://www.googleapis.com/auth/gmail.readonly") {
    throw new BadRequestError("The Gmail scope was refused.");
  }
  const ciphertext = String(body.ciphertext || "");
  if (!/^[A-Za-z0-9+/=_-]{20,8000}$/.test(ciphertext)) {
    throw new BadRequestError("The token payload was refused.");
  }
  const googleEmail = String(body.googleEmail || "");
  if (
    googleEmail.length > 200 ||
    !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(googleEmail)
  ) {
    throw new BadRequestError("The Google account email was refused.");
  }
  let pending;
  try {
    pending = $app.findFirstRecordByFilter(
      "gmail_pending",
      "nonce = {:nonce}",
      { nonce: String(body.pendingId || "") },
    );
  } catch (err) {
    throw new NotFoundError("The Gmail connection attempt was not found.");
  }
  if (pending.get("consumed")) {
    throw new BadRequestError("The Gmail connection attempt was already used.");
  }
  const expires = Number(pending.get("expires_at"));
  if (!expires || Date.now() > expires) {
    throw new BadRequestError("The Gmail connection attempt expired.");
  }
  const ownerValue = pending.get("user");
  const owner = Array.isArray(ownerValue)
    ? String(ownerValue[0] || "")
    : String(ownerValue || "");
  pending.set("consumed", true);
  let link = null;
  try {
    link = $app.findFirstRecordByFilter("gmail_links", "user = {:user}", {
      user: owner,
    });
  } catch (err) {
    link = null;
  }
  if (!link) {
    link = new Record($app.findCollectionByNameOrId("gmail_links"));
    link.set("user", owner);
  }
  link.set("status", "connected");
  link.set("google_email", googleEmail);
  link.set("scope", scope);
  link.set("connected_at", new Date().toISOString());
  link.set("token_ciphertext", ciphertext);
  $app.save(pending);
  $app.save(link);
  return e.json(200, {
    status: "connected",
    returnTo: String(pending.get("return_to") || ""),
    googleEmail: googleEmail,
    scope: scope,
  });
});
