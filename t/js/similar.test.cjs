/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(path.join(__dirname, "../../assets/js/similar.js"), "utf8");

const tick = async () => {
  for (let i = 0; i < 8; ++i) await new Promise((resolve) => setImmediate(resolve));
};

// Model only what the client touches: a form with a title field, the region
// under it with its list, timers that fire when asked, and fetch.
const harness = ({ title = "", suggestions = [], status = 200 } = {}) => {
  const requests = [];
  const timers = [];
  const listeners = new Map();
  const element = (tag) => ({
    tag, children: [], href: "", textContent: "",
    appendChild(child) { this.children.push(child); return child; },
  });
  const list = { ...element("ul"), replaceChildren(...items) { this.children = items; } };
  const field = {
    value: title,
    addEventListener(name, handler) { listeners.set(name, handler); },
  };
  const form = { elements: { namedItem: (name) => (name === "title" ? field : null) } };
  const region = {
    hidden: true,
    dataset: { field: "title", url: "/search/autocomplete", threadBase: "/t/THREAD_ID" },
    closest: () => form,
    querySelector: (selector) => (selector === "[data-similar-list]" ? list : null),
  };
  const document = {
    readyState: "complete",
    querySelectorAll: () => [region],
    createElement: element,
    addEventListener() {},
  };
  const context = {
    document,
    fetch: async (url, options) => {
      requests.push({ url, options });
      return { ok: status === 200, status, json: async () => ({ suggestions }) };
    },
    AbortController: class { constructor() { this.signal = {}; } abort() {} },
    setTimeout: (handler) => { timers.push(handler); return timers.length; },
    clearTimeout: () => {},
    encodeURIComponent,
    Array,
    Error,
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  return {
    requests, region, list, field,
    type: async (value) => {
      field.value = value;
      listeners.get("input")();
      while (timers.length) timers.shift()();
      await tick();
    },
  };
};

test("a title of three characters or more lists the threads it resembles", async () => {
  const page = harness({
    suggestions: [
      { entity_type: "thread", entity_id: "018f1004-0001-7000-8000-000000000001", title: "Welcome" },
      { entity_type: "post", entity_id: "018f1005-0001-7000-8000-000000000001", title: "A post" },
    ],
  });
  await page.type("Welcome everyone");
  assert.equal(page.requests.length, 1);
  assert.match(page.requests[0].url, /^\/search\/autocomplete\?q=Welcome%20everyone&limit=5$/);
  assert.equal(page.requests[0].options.credentials, "same-origin");
  assert.equal(page.list.children.length, 1, "only threads are listed");
  assert.equal(page.list.children[0].children[0].href, "/t/018f1004-0001-7000-8000-000000000001");
  assert.equal(page.list.children[0].children[0].textContent, "Welcome");
  assert.equal(page.region.hidden, false);
});

test("a short title asks nothing and shows nothing", async () => {
  const page = harness({ suggestions: [{ entity_type: "thread", entity_id: "x", title: "x" }] });
  await page.type("We");
  assert.equal(page.requests.length, 0);
  assert.equal(page.region.hidden, true);
});

test("no match, or a refused lookup, leaves the region hidden", async () => {
  const empty = harness({ suggestions: [] });
  await empty.type("Nothing like it");
  assert.equal(empty.region.hidden, true);
  const refused = harness({ status: 429, suggestions: [{ entity_type: "thread", entity_id: "y", title: "y" }] });
  await refused.type("Rate limited");
  assert.equal(refused.region.hidden, true);
  assert.equal(refused.list.children.length, 0);
});

test("a title already typed is looked up when the page loads", async () => {
  const page = harness({
    title: "Welcome back",
    suggestions: [{ entity_type: "thread", entity_id: "z", title: "Welcome" }],
  });
  await tick();
  assert.equal(page.requests.length, 1);
  assert.equal(page.region.hidden, false);
});
