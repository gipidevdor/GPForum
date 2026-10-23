/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/editor-suggestions.js`, "utf8");
function harness() {
  const timers = new Map(), requests = [], events = {};
  let timerId = 0;
  function element() {
    return { attributes: {}, children: [], handlers: {}, isConnected: true,
      setAttribute(key, value) { this.attributes[key] = value; },
      removeAttribute(key) { delete this.attributes[key]; },
      addEventListener(key, fn) { this.handlers[key] = fn; },
      replaceChildren(...children) { this.children = children; },
      after(...children) { this.afterNodes = children; },
      focus() { this.focused = true; },
      dispatchEvent(event) { this.handlers[event.type]?.(event); },
      setRangeText(text, start, end) { this.value = this.value.slice(0, start) + text + this.value.slice(end); this.selectionStart = this.selectionEnd = start + text.length; },
    };
  }
  const field = element();
  const form = { dataset: { suggestUrl: "/search/autocomplete", threadBase: "/t/THREAD_ID" }, querySelector: () => field };
  const authors = [{ href: "/u/alice" }, { href: "/u/alice" }, { href: "/u/bob" }, { href: "/u/%3Cscript%3E" }];
  const document = { documentElement: { lang: "it" }, baseURI: "https://forum.test/", createElement: element,
    querySelectorAll: selector => selector.startsWith("form") ? [form] : authors,
    addEventListener(key, fn) { events[key] = fn; } };
  vm.runInNewContext(source, { document, URL, AbortController, WeakSet, Event: class { constructor(type) { this.type = type; } },
    setTimeout(fn) { timers.set(++timerId, fn); return timerId; }, clearTimeout(id) { timers.delete(id); },
    fetch: async (url, options) => { const row = { url, options }; requests.push(row); return new Promise(resolve => { row.resolve = resolve; }); },
  });
  const input = text => { field.value = text; field.selectionStart = field.selectionEnd = text.length; field.handlers.input(); };
  const key = value => { const event = { key: value, preventDefault() { this.prevented = true; } }; field.handlers.keydown(event); return event; };
  return { field, list: field.afterNodes[1], input, key, requests, events,
    start() { const fn = [...timers.values()].at(-1); timers.clear(); return fn?.(); } };
}
test("mentions use only visible participants and do not make a request", () => {
  const page = harness(); page.input("Ciao @al");
  assert.equal(page.list.children.length, 1);
  assert.equal(page.list.children[0].textContent, "@alice");
  page.list.children[0].handlers.pointerdown({ preventDefault() {} });
  assert.equal(page.field.value, "Ciao @alice ");
  assert.equal(page.requests.length, 0);
});
test("selection replaces only the token and respects cursor changes", () => {
  const page = harness(); page.input("Testo @al");
  page.field.selectionStart = page.field.selectionEnd = 0;
  page.list.children[0].handlers.pointerdown({ preventDefault() {} });
  assert.equal(page.field.value, "Testo @al");
});
test("Enter preserves multiline writing until a suggestion is selected", () => {
  const page = harness(); page.input("@al");
  assert.equal(page.key("Enter").prevented, undefined);
  assert.equal(page.key("ArrowDown").prevented, true);
  assert.equal(page.key("Enter").prevented, true);
  assert.equal(page.field.value, "@alice ");
});
test("discussion lookup is bounded and rejects unsafe identifiers", async () => {
  const page = harness(); page.input("[[ab"); await page.start();
  assert.equal(page.requests.length, 0);
  page.input("[[forum"); const pending = page.start();
  assert.equal(page.requests[0].url.searchParams.get("limit"), "5");
  assert.equal(page.requests[0].options.credentials, "same-origin");
  page.requests[0].resolve({ ok: true, json: async () => ({ suggestions: [
    { entity_type: "thread", entity_id: "javascript:bad", title: "bad" },
    { entity_type: "thread", entity_id: "018f2000-0001-7000-8000-000000000001", title: "<img> [Discussione]" },
  ] }) }); await pending;
  assert.equal(page.list.children.length, 1);
  assert.equal(page.list.children[0].textContent, "<img> [Discussione]");
  page.key("ArrowUp"); page.key("Enter");
  assert.match(page.field.value, /\]\(\/t\/018f2000-0001-7000-8000-000000000001\)/);
});
test("stale responses cannot replace suggestions for new text", async () => {
  const page = harness(); page.input("[[forum"); const pending = page.start();
  page.input("@bo");
  page.requests[0].resolve({ ok: true, json: async () => ({ suggestions: [] }) }); await pending;
  assert.equal(page.list.children[0].textContent, "@bob");
});
test("blur releases requests and fragment swaps do not duplicate controls", async () => {
  const page = harness(); const list = page.list;
  page.events["htmx:afterSwap"]();
  assert.equal(page.field.afterNodes[1], list);
  page.input("[[forum"); const pending = page.start(); page.field.handlers.blur();
  assert.equal(page.requests[0].options.signal.aborted, true);
  page.requests[0].resolve({ ok: true, json: async () => ({ suggestions: [] }) }); await pending;
  assert.equal(page.list.hidden, true);
});
