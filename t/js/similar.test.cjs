/* SPDX-FileCopyrightText: 2026 GPForum Contributors
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
const harness = ({ title = "", suggestions = [], status = 200, deferred = false } = {}) => {
  const requests = [];
  const timers = new Map();
  let timerId = 0;
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
    isConnected: true,
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
    fetch: (url, options) => {
      const request = { url, options };
      requests.push(request);
      const response = (items, code) => ({ ok: code === 200, status: code, json: async () => ({ suggestions: items }) });
      if (deferred) return new Promise((resolve) => {
        request.answer = (items = suggestions, code = status) => resolve(response(items, code));
      });
      return Promise.resolve(response(suggestions, status));
    },
    AbortController,
    setTimeout: (handler) => { timers.set(++timerId, handler); return timerId; },
    clearTimeout: (id) => timers.delete(id),
    encodeURIComponent,
    Array,
    Error,
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  const input = (value) => {
    field.value = value;
    listeners.get("input")();
  };
  const runTimers = () => {
    for (const [id, handler] of [...timers]) {
      timers.delete(id);
      handler();
    }
  };
  return {
    requests, region, list, field, input, runTimers,
    type: async (value) => {
      input(value);
      runTimers();
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

test("changing the title invalidates a pending response before the next lookup starts", async () => {
  const page = harness({ title: "First title", deferred: true });
  page.input("Second title");
  page.requests[0].answer([{ entity_type: "thread", entity_id: "old", title: "Old suggestion" }]);
  await tick();
  assert.equal(page.region.hidden, true, "the old response cannot populate the new title's suggestions");
  assert.equal(page.requests[0].options.signal.aborted, true);
  page.runTimers();
  assert.equal(page.requests.length, 2);
  page.requests[1].answer([{ entity_type: "thread", entity_id: "new", title: "New suggestion" }]);
  await tick();
  assert.equal(page.list.children[0].children[0].textContent, "New suggestion");
});

test("shortening the title hides suggestions immediately and late responses cannot restore them", async () => {
  const page = harness({ title: "First title", deferred: true });
  page.requests[0].answer([{ entity_type: "thread", entity_id: "old", title: "Old suggestion" }]);
  await tick();
  assert.equal(page.region.hidden, false);
  await page.type("Another title");
  page.input("ab");
  assert.equal(page.region.hidden, true, "the earlier title's suggestions disappear on input");
  page.runTimers();
  page.requests[1].answer([{ entity_type: "thread", entity_id: "late", title: "Late suggestion" }]);
  await tick();
  assert.equal(page.region.hidden, true);
  assert.equal(page.requests.length, 2, "a short title never triggers another request");
});
