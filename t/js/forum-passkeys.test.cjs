/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/passkeys.js`, "utf8");

function browser({mode = "login", supported = true, cancelled = false, next = "/settings", fail = false} = {}) {
  const events = {}, calls = [], visits = [];
  const button = {disabled: true}, status = {}, cancel = {hidden: true, addEventListener() {}};
  const form = {action: "https://forum.test/begin", dataset: {passkey: mode, finish: "/finish", failed: "Failed",
    unsupported: "Unsupported", waiting: "Waiting", cancelled: "Cancelled"},
    querySelector(selector) { return selector.includes("status") ? status : selector.includes("cancel") ? cancel : button; },
    addEventListener(name, callback) { events[name] = callback; }};
  const document = {querySelectorAll() { return [form]; }, addEventListener() {}};
  const native = async (options) => {
    calls.push({native: mode, options});
    if (cancelled) throw new DOMException("Cancelled", "NotAllowedError");
    return {type: "public-key", rawId: new Uint8Array([4, 5]).buffer, response: {
      clientDataJSON: new Uint8Array([6]).buffer, attestationObject: new Uint8Array([7]).buffer,
      authenticatorData: new Uint8Array([8]).buffer, signature: new Uint8Array([9]).buffer,
      userHandle: new Uint8Array([10]).buffer}};
  };
  class FormData { constructor() { return [["csrf_token", "session-token"], ["password", "current-password"]]; } }
  vm.runInNewContext(source, {document, window: {isSecureContext: supported, PublicKeyCredential: class {}},
    navigator: {credentials: {get: native, create: native}}, FormData, URL, URLSearchParams,
    Uint8Array, AbortController, atob, btoa, location: {origin: "https://forum.test", href: "https://forum.test/login", assign(url) { visits.push(url); }},
    fetch: async (url, options) => {
      calls.push({url, options});
      if (url.endsWith("/begin")) return {ok: true, json: async () => ({publicKey: {challenge: "AQI", rpId: "forum.test",
        ...(mode === "register" ? {user: {id: "Aw", name: "reader"}, excludeCredentials: [{id: "BA", type: "public-key"}]} : {})}})};
      return {ok: !fail, json: async () => ({ok: true, next})};
    }});
  return {calls, visits, button, status, submit: () => events.submit({preventDefault() {}})};
}

for (const mode of ["login", "register"]) {
  test(`${mode} GUI invokes the native ceremony and serializes every binary field`, async () => {
    const page = browser({mode});
    assert.equal(page.button.disabled, false);
    await page.submit();
    assert.equal(page.calls.length, 3);
    const native = page.calls[1];
    assert.deepEqual([...native.options.publicKey.challenge], [1, 2]);
    if (mode === "register") assert.deepEqual([...native.options.publicKey.user.id], [3]);
    const {options} = page.calls[2];
    const payload = JSON.parse(options.body);
    assert.equal(payload.rawId, "BAU");
    assert.equal(payload.response.clientDataJSON, "Bg");
    assert.equal(payload.response[mode === "register" ? "attestationObject" : "signature"], mode === "register" ? "Bw" : "CQ");
    if (mode === "login") assert.equal(payload.response.userHandle, "Cg");
    assert.equal(options.headers["X-CSRF-Token"], "session-token");
    assert.equal(options.credentials, "same-origin");
    assert.equal(options.redirect, "error");
    assert.equal(options.cache, "no-store");
    assert.deepEqual(page.visits, ["https://forum.test/settings"]);
  });
}
test("cancellation keeps the form usable and does not verify or retry", async () => {
  const page = browser({cancelled: true});
  await page.submit();
  assert.equal(page.calls.length, 2);
  assert.equal(page.status.textContent, "Cancelled");
  assert.equal(page.button.disabled, false);
  assert.deepEqual(page.visits, []);
});
test("unsupported contexts explain why passkeys are unavailable", () => {
  const page = browser({supported: false});
  assert.equal(page.button.disabled, true);
  assert.equal(page.status.textContent, "Unsupported");
  assert.equal(page.calls.length, 0);
});
test("failed verification and external redirects keep the member on the page", async () => {
  for (const options of [{fail: true}, {next: "https://evil.test/"}]) {
    const page = browser(options);
    await page.submit();
    assert.equal(page.status.textContent, "Failed");
    assert.deepEqual(page.visits, []);
  }
});
