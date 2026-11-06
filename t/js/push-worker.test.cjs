/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const source = fs.readFileSync("assets/push-worker.js", "utf8");
const boot = () => {
  const handlers = {}, shown = [], opened = [], requests = [];
  const context = {
    URL, URLSearchParams,
    self: {
      navigator: {language: "it-IT"}, location: {origin: "https://forum.example"},
      addEventListener: (type, handler) => { handlers[type] = handler; },
      registration: {showNotification: async (title, options) => { shown.push({title, ...options}); }},
      clients: {matchAll: async () => [], openWindow: async (url) => { opened.push(url); }},
    },
    fetch: async (url, options) => {
      requests.push({url, options});
      return {ok: true, json: async () => ({enabled: true, csrf_token: "own-session-token"})};
    },
  };
  vm.runInNewContext(source, context);
  const push = async (payload) => {
    let pending;
    handlers.push({data: {arrayBuffer: () => Buffer.from(JSON.stringify(payload)), json: () => payload},
      waitUntil: (promise) => { pending = promise; }});
    await pending;
  };
  return {context, handlers, shown, opened, requests, push};
};
test("generic alert cannot expose content or select an external click target", async () => {
  const app = boot();
  await app.push({type: "alert", title: "private thread", body: "secret message", url: "https://evil.example"});
  assert.equal(app.shown.length, 1);
  assert.equal(app.shown[0].body, "Hai nuove notifiche");
  assert.equal(app.requests.length, 0, "no background content lookup");
  let pending;
  app.handlers.notificationclick({notification: {close() {}, data: {url: "https://evil.example"}},
    waitUntil: (promise) => { pending = promise; }});
  await pending;
  assert.deepEqual(app.opened, ["https://forum.example/notifications"]);
  assert.equal(app.handlers.fetch, undefined, "no interception or caching of private pages");
});
test("activation proves receipt through an authenticated CSRF protected same-origin write", async () => {
  const app = boot();
  await app.push({type: "activation", subscription_id: "0193a5c4-0000-7000-8000-000000000001", nonce: "a".repeat(43)});
  assert.equal(app.shown.length, 1, "activation is user-visible");
  assert.deepEqual(app.requests.map((r) => r.url), ["/push/configuration", "/push/confirm"]);
  assert.equal(app.requests[1].options.credentials, "same-origin");
  assert.equal(app.requests[1].options.redirect, "error");
  assert.equal(app.requests[1].options.body.get("csrf_token"), "own-session-token");
});
test("unknown and oversized payloads cannot activate or display arbitrary data", async () => {
  const app = boot();
  await app.push({type: "silent", body: "hidden"});
  await app.push({type: "alert", body: "x".repeat(1025)});
  assert.equal(app.shown.length, 0);
  assert.equal(app.requests.length, 0);
});
