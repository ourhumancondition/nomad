"use strict";

const test = require("node:test");
const assert = require("node:assert");
const { handleWhere } = require("./where");

function call(method, headers) {
  const out = { headers: {} };
  const res = {
    setHeader(name, value) {
      out.headers[name.toLowerCase()] = value;
    },
    status(code) {
      out.status = code;
      return this;
    },
    json(body) {
      out.body = body;
    },
  };
  handleWhere({ method, headers }, res);
  return out;
}

test("returns the edge country code", () => {
  const out = call("GET", { "x-vercel-ip-country": "ph" });
  assert.strictEqual(out.status, 200);
  assert.deepStrictEqual(out.body, { country: "PH" });
  assert.strictEqual(out.headers["cache-control"], "no-store");
});

test("unknown, missing or malformed values are null", () => {
  for (const value of [undefined, "", "XX", "T1", "CAN", "1A"]) {
    const headers = value === undefined ? {} : { "x-vercel-ip-country": value };
    assert.deepStrictEqual(call("GET", headers).body, { country: null }, String(value));
  }
});

test("never echoes the address or finer location", () => {
  const out = call("GET", {
    "x-vercel-ip-country": "CA",
    "x-forwarded-for": "203.0.113.7",
    "x-real-ip": "203.0.113.7",
    "x-vercel-ip-city": "Toronto",
    "x-vercel-ip-latitude": "43.7",
    "x-vercel-ip-longitude": "-79.4",
  });
  assert.deepStrictEqual(out.body, { country: "CA" });
  assert.ok(!JSON.stringify(out.body).includes("203.0.113.7"));
});

test("only GET is allowed", () => {
  assert.strictEqual(call("POST", {}).status, 405);
});
