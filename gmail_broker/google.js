"use strict";

const extract = require("./extract");

async function exchange(args) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code: args.code,
      client_id: args.clientId,
      client_secret: args.clientSecret,
      redirect_uri: args.redirectUri,
      grant_type: "authorization_code",
    }),
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) return { ok: false };
  return {
    ok: true,
    refreshToken: json.refresh_token || "",
    accessToken: json.access_token || "",
    expiresIn: json.expires_in || 0,
    scope: json.scope || "",
  };
}

async function refresh(args) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      refresh_token: args.refreshToken,
      client_id: args.clientId,
      client_secret: args.clientSecret,
      grant_type: "refresh_token",
    }),
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) {
    return { ok: false, invalidGrant: json.error === "invalid_grant" };
  }
  return {
    ok: true,
    accessToken: json.access_token || "",
    expiresIn: json.expires_in || 0,
  };
}

async function revoke(token) {
  await fetch("https://oauth2.googleapis.com/revoke", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ token }),
  });
}

async function profile(accessToken) {
  const response = await fetch(
    "https://gmail.googleapis.com/gmail/v1/users/me/profile",
    { headers: { authorization: `Bearer ${accessToken}` } },
  );
  const json = await response.json().catch(() => ({}));
  if (!response.ok || !json.emailAddress) return { ok: false };
  return { ok: true, email: json.emailAddress };
}

async function listMessages(args) {
  const url = new URL("https://gmail.googleapis.com/gmail/v1/users/me/messages");
  url.searchParams.set("q", args.query);
  url.searchParams.set("maxResults", "15");
  if (args.pageToken) url.searchParams.set("pageToken", args.pageToken);
  const response = await fetch(url, {
    headers: { authorization: `Bearer ${args.accessToken}` },
  });
  const json = await response.json().catch(() => ({}));
  if (response.status === 401) return { invalidGrant: true, messages: [] };
  if (!response.ok) return { messages: [] };
  return {
    messages: json.messages || [],
    nextPageToken: json.nextPageToken || "",
  };
}

async function getMessage(args) {
  const url = new URL(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages/${encodeURIComponent(args.id)}`,
  );
  url.searchParams.set("format", "full");
  const response = await fetch(url, {
    headers: { authorization: `Bearer ${args.accessToken}` },
  });
  if (!response.ok) return null;
  return response.json();
}

async function getAttachment(args) {
  const url = `https://gmail.googleapis.com/gmail/v1/users/me/messages/${encodeURIComponent(args.messageId)}/attachments/${encodeURIComponent(args.attachmentId)}`;
  const response = await fetch(url, {
    headers: { authorization: `Bearer ${args.accessToken}` },
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok || !json.data) return null;
  return { bytes: extract.decodeB64Url(json.data) };
}

function liveDeps(env) {
  return {
    env,
    fetch,
    exchange,
    refresh,
    revoke,
    profile,
    listMessages,
    getMessage,
    getAttachment,
  };
}

module.exports = { liveDeps };
