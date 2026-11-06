/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const test = require("node:test");
const { pathToFileURL } = require("node:url");
const path = require("node:path");
const moduleURL = pathToFileURL(path.join(__dirname, "../../examples/passkeys/public/passkeys.mjs"));
const api = import(moduleURL.href);

function browser(t, create) {
  const overrides = {
    isSecureContext: true, PublicKeyCredential: class PublicKeyCredential {},
    navigator: { credentials: { create } },
  };
  const keys = [...Object.keys(overrides), "fetch"];
  const previous = new Map(keys.map((key) => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  for (const [key, value] of Object.entries(overrides)) {
    Object.defineProperty(globalThis, key, { value, writable: true, configurable: true });
  }
  t.after(() => {
    for (const [key, descriptor] of previous) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else delete globalThis[key];
    }
  });
}

function options() {
  return { publicKey: {
    challenge: "AAEC_w", rp: { id: "localhost", name: "Good Phorum" },
    user: { id: "AwQF", name: "demo", displayName: "Demo" },
    pubKeyCredParams: [{ type: "public-key", alg: -7 }],
    authenticatorSelection: { authenticatorAttachment: "platform", residentKey: "required", userVerification: "required" },
    excludeCredentials: [{ type: "public-key", id: "BgcI" }],
  } };
}

test("Base64URL preserves all byte values and typed-array boundaries, and rejects noncanonical encodings", async () => {
  const { fromBase64URL, toBase64URL } = await api;
  const bytes = Uint8Array.from({ length: 256 }, (_, index) => index);
  assert.deepEqual(fromBase64URL(toBase64URL(bytes)), bytes);
  const view = new Uint8Array(bytes.buffer, 10, 3);
  assert.deepEqual(fromBase64URL(toBase64URL(view)), new Uint8Array([10, 11, 12]));
  for (const bad of ["", "***", "A", "AA==", "AB", "é"]) {
    assert.throws(() => fromBase64URL(bad), { name: "PasskeyError" });
  }
});

test("the native ceremony receives bytes and the server receives explicit Base64URL with same-origin session and CSRF", async (t) => {
  const { registerPasskey } = await api;
  let nativeOptions;
  const credential = {
    type: "public-key", rawId: new Uint8Array([9, 10, 11]).buffer,
    response: {
      clientDataJSON: new TextEncoder().encode('{"type":"webauthn.create"}').buffer,
      attestationObject: new Uint8Array([161, 1, 2]).buffer,
    },
  };
  browser(t, async (value) => { nativeOptions = value; return credential; });
  const requests = [];
  globalThis.fetch = async (url, config) => {
    requests.push({ url, config });
    return Response.json(requests.length === 1 ? options() : { verified: true, persisted: false });
  };
  const controller = new AbortController();
  const result = await registerPasskey({ csrfToken: "masked-session-token", signal: controller.signal });
  assert.equal(result.persisted, false);
  assert.deepEqual(nativeOptions.publicKey.challenge, new Uint8Array([0, 1, 2, 255]));
  assert.deepEqual(nativeOptions.publicKey.user.id, new Uint8Array([3, 4, 5]));
  assert.deepEqual(nativeOptions.publicKey.excludeCredentials[0].id, new Uint8Array([6, 7, 8]));
  assert.equal(nativeOptions.publicKey.authenticatorSelection.userVerification, "required");
  assert.equal(nativeOptions.signal, controller.signal);
  assert.deepEqual(requests.map((item) => item.url), ["/api/passkey/register/challenge", "/api/passkey/register/verify"]);
  for (const { config } of requests) {
    assert.equal(config.method, "POST");
    assert.equal(config.credentials, "same-origin");
    assert.equal(config.redirect, "error");
    assert.equal(config.cache, "no-store");
    assert.equal(config.headers["X-CSRF-Token"], "masked-session-token");
    assert.equal(config.signal, controller.signal);
  }
  assert.deepEqual(JSON.parse(requests[1].config.body), {
    type: "public-key", id: "CQoL", rawId: "CQoL", response: {
      clientDataJSON: "eyJ0eXBlIjoid2ViYXV0aG4uY3JlYXRlIn0", attestationObject: "oQEC",
    },
  });
});

test("cancellation and authenticator refusal stop before verification and do not retry", async (t) => {
  const { registerPasskey } = await api;
  let requests = 0;
  browser(t, async () => { throw new DOMException("user cancelled", "NotAllowedError"); });
  globalThis.fetch = async () => { requests++; return Response.json(options()); };
  await assert.rejects(registerPasskey({ csrfToken: "token" }), { name: "PasskeyError", code: "NotAllowedError" });
  assert.equal(requests, 1);
});

test("unsupported context, missing CSRF, invalid JSON, failed server verification and expired challenge are failures", async (t) => {
  const { registerPasskey } = await api;
  browser(t, async () => ({ type: "public-key", rawId: new Uint8Array([1]).buffer, response: {
    clientDataJSON: new Uint8Array([2]).buffer, attestationObject: new Uint8Array([3]).buffer,
  } }));
  globalThis.isSecureContext = false;
  await assert.rejects(registerPasskey({ csrfToken: "token" }), { code: "unsupported" });
  globalThis.isSecureContext = true;
  await assert.rejects(registerPasskey(), { code: "csrf_missing" });
  globalThis.fetch = async () => new Response("<h1>Failure</h1>", { status: 502 });
  await assert.rejects(registerPasskey({ csrfToken: "token" }), { code: "invalid_response" });
  for (const response of [
    () => Response.json({ verified: false }),
    () => Response.json({ error: "challenge_expired_or_used" }, { status: 409 }),
  ]) {
    let calls = 0;
    globalThis.fetch = async () => ++calls === 1 ? Response.json(options()) : response();
    await assert.rejects(registerPasskey({ csrfToken: "token" }), { name: "PasskeyError" });
    assert.equal(calls, 2);
  }
});
