"use strict";

const zlib = require("zlib");

const SEARCH_QUERY = [
  "newer_than:1825",
  "(",
  "from:(aircanada.ca OR aircanada.com OR evaair.com OR flyasiana.com OR asiana.com OR united.com OR trip.com OR lot.com OR shenzhenair.com)",
  'OR subject:(itinerary OR "e-ticket" OR "flight confirmation" OR "booking confirmation" OR "schedule change" OR "flight cancelled" OR "flight canceled")',
  ")",
  "-category:promotions",
].join(" ");

function htmlToText(raw) {
  let text = String(raw || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  text = text.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ");
  text = text.replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ");
  text = text.replace(/<br\s*\/?>/gi, "\n");
  text = text.replace(/<\/(p|div|tr|li|h[1-6]|table)>/gi, "\n");
  text = text.replace(/<[^>]+>/g, " ");
  text = text
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"');
  return text;
}

function pdfText(buffer) {
  const bytes = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer);
  const chunks = [];
  let index = 0;
  while (index < bytes.length) {
    const start = bytes.indexOf("stream", index);
    if (start < 0) break;
    let dataStart = start + "stream".length;
    if (bytes[dataStart] === 13) dataStart += 1;
    if (bytes[dataStart] === 10) dataStart += 1;
    const end = bytes.indexOf("endstream", dataStart);
    if (end < 0) break;
    const slice = bytes.subarray(dataStart, end);
    const dict = bytes.subarray(Math.max(0, start - 240), start).toString("latin1");
    if (dict.includes("FlateDecode")) {
      try {
        chunks.push(zlib.inflateSync(slice).toString("latin1"));
      } catch (err) {
        chunks.push(slice.toString("latin1"));
      }
    } else {
      chunks.push(slice.toString("latin1"));
    }
    index = end + "endstream".length;
  }
  if (chunks.length === 0) chunks.push(bytes.toString("latin1"));
  return extractPdfStrings(chunks.join("\n"));
}

function extractPdfStrings(raw) {
  const out = [];
  const re = /\((?:\\\)|\\.|[^\\)])*\)/g;
  let match;
  while ((match = re.exec(raw))) {
    const inner = match[0].slice(1, -1);
    out.push(
      inner
        .replace(/\\n/g, "\n")
        .replace(/\\r/g, "")
        .replace(/\\\(/g, "(")
        .replace(/\\\)/g, ")")
        .replace(/\\\\/g, "\\"),
    );
  }
  return out.join(" ");
}

function worthParsing(text) {
  const flight = /\b(?:[A-Z]{2}|[A-Z]\d|\d[A-Z])\s?\d{1,4}\b/.test(text);
  const airport = /\([A-Z]{3}\)/.test(text);
  const booking = /booking reference|record locator|confirmation code|\bpnr\b/i.test(
    text,
  );
  const cancel = /cancell?ed|cancellation/i.test(text);
  return (flight && (airport || booking)) || (cancel && booking);
}

function decodeB64Url(data) {
  const pad = data.length % 4 === 0 ? "" : "=".repeat(4 - (data.length % 4));
  return Buffer.from(String(data).replace(/-/g, "+").replace(/_/g, "/") + pad, "base64");
}

function headerValue(headers, name) {
  const list = Array.isArray(headers) ? headers : [];
  for (const header of list) {
    if (String(header.name || "").toLowerCase() === name.toLowerCase()) {
      return String(header.value || "");
    }
  }
  return "";
}

function addressOnly(from) {
  const match = /<([^>]+)>/.exec(from);
  const raw = (match ? match[1] : from).trim();
  return raw.length > 200 ? raw.slice(0, 200) : raw;
}

function messageText(payload, attachments) {
  const parts = [];
  walk(payload, parts);
  let plain = "";
  let html = "";
  for (const part of parts) {
    if (!part.data) continue;
    const text = decodeB64Url(part.data).toString("utf8");
    if (part.mime === "text/plain") plain += `\n${text}`;
    if (part.mime === "text/html") html += `\n${text}`;
  }
  let text = plain.trim() ? plain : htmlToText(html);
  for (const attachment of attachments || []) {
    if (!attachment || !attachment.bytes) continue;
    const mime = String(attachment.mime || "");
    if (mime === "text/plain") text += `\n${attachment.bytes.toString("utf8")}`;
    else if (mime === "text/html") text += `\n${htmlToText(attachment.bytes.toString("utf8"))}`;
    else if (mime === "application/pdf" || /\.pdf$/i.test(attachment.filename || "")) {
      text += `\n${pdfText(attachment.bytes)}`;
    }
  }
  const truncated = text.length > 20000;
  return { text: text.slice(0, 20000), truncated };
}

function walk(part, out) {
  if (!part || typeof part !== "object") return;
  const mime = String(part.mimeType || "");
  const data = part.body && part.body.data;
  if (data && (mime === "text/plain" || mime === "text/html")) {
    out.push({ mime, data });
  }
  const children = Array.isArray(part.parts) ? part.parts : [];
  for (const child of children) walk(child, out);
}

function attachmentRefs(part, out) {
  if (!part || typeof part !== "object") return;
  const body = part.body || {};
  if (body.attachmentId) {
    out.push({
      id: String(body.attachmentId),
      filename: String(part.filename || ""),
      mime: String(part.mimeType || ""),
    });
  }
  const children = Array.isArray(part.parts) ? part.parts : [];
  for (const child of children) attachmentRefs(child, out);
}

module.exports = {
  SEARCH_QUERY,
  htmlToText,
  pdfText,
  worthParsing,
  decodeB64Url,
  headerValue,
  addressOnly,
  messageText,
  attachmentRefs,
};
