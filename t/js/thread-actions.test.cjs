/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/thread-actions.js`, "utf8");
function harness({ ignored = false, authenticated = true, failCopy = false } = {}) {
  const events = {};
  const copied = [];
  const element = () => ({
    children: [], attributes: {}, handlers: {}, textContent: "",
    append(...items) { this.children.push(...items); },
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener(name, handler) { this.handlers[name] = handler; },
  });
  const selection = { isCollapsed: false, anchorNode: {}, focusNode: {}, toString: () => "selected\npassage" };
  const anchor = selection.anchorNode;
  const focus = selection.focusNode;
  const body = { contains: node => node === anchor || node === focus };
  const block = {
    closest: () => ignored,
    querySelector: () => ({ textContent: "<hello>\n  code" }),
    after(tools) { this.tools = tools; },
  };
  const post = {
    ...element(), id: "post-one", dataset: { pageUrl: "/forum/t/thread?after=cursor" },
    querySelector(selector) {
      if (selector === ".forum-post-body") return body;
      if (selector === ".post__ignored") return ignored;
      if (selector === ".post__permalink") return { textContent: "#26" };
    },
    querySelectorAll: () => [block],
  };
  const field = {
    value: "unsaved draft", dataset: {}, inputEvents: 0,
    setRangeText(text, start, end) { this.value = this.value.slice(0, start) + text + this.value.slice(end); },
    dispatchEvent(event) { if (event.type === "input") this.inputEvents++; },
    focus() { this.focused = true; },
  };
  const document = {
    documentElement: { lang: "it" }, createElement: element,
    querySelectorAll: () => [post],
    querySelector: () => authenticated ? field : null,
    addEventListener(name, handler) { events[name] = handler; },
  };
  vm.runInNewContext(source, {
    document, URL, window: { location: { href: "https://example.test/forum/t/thread" }, getSelection: () => selection },
    navigator: { clipboard: { async writeText(text) { if (failCopy) throw Error("denied"); copied.push(text); } } },
    Event: class { constructor(type) { this.type = type; } },
  });
  return { post, field, block, selection, events, copied, tools: post.children[0] };
}
test("quoting a selection appends to the unsaved draft and triggers autosave", () => {
  const page = harness();
  page.tools.children[1].handlers.click();
  assert.equal(page.field.value, "unsaved draft\n\n[#26](https://example.test/forum/t/thread?after=cursor#post-one)\n\n> selected\n> passage\n\n");
  assert.equal(page.field.inputEvents, 1);
  assert.equal(page.field.focused, true);
});
test("multiple selections accumulate in the same draft", () => {
  const page = harness();
  page.tools.children[1].handlers.click();
  page.selection.toString = () => "another";
  page.tools.children[1].handlers.click();
  assert.match(page.field.value, /> passage\n\n\[#26\].*\n\n> another\n\n$/);
  assert.equal(page.field.inputEvents, 2);
});
test("pointer selection survives focus movement to the quote button", () => {
  const page = harness();
  page.tools.children[1].handlers.pointerdown();
  page.selection.isCollapsed = true;
  page.tools.children[1].handlers.click();
  assert.match(page.field.value, /> selected\n> passage/);
});
test("a selection outside the message or no selection never changes the draft", () => {
  const page = harness();
  page.selection.anchorNode = null;
  page.tools.children[1].handlers.click();
  assert.equal(page.field.value, "unsaved draft");
  assert.equal(page.field.inputEvents, 0);
  assert.match(page.tools.children[2].textContent, /Seleziona/);
});
test("copy link retains the page cursor of a dynamically appended post", async () => {
  const page = harness();
  await page.tools.children[0].handlers.click();
  assert.equal(page.copied[0], "https://example.test/forum/t/thread?after=cursor#post-one");
  assert.equal(page.tools.children[2].textContent, "Copiato");
});
test("copy code uses its literal text", async () => {
  const page = harness();
  await page.block.tools.children[0].handlers.click();
  assert.equal(page.copied[0], "<hello>\n  code");
});
test("clipboard rejection produces visible manual-copy guidance", async () => {
  const page = harness({ failCopy: true });
  await page.tools.children[0].handlers.click();
  assert.match(page.tools.children[2].textContent, /Copia non disponibile/);
});
test("ignored content and anonymous readers never get selection quote tools", () => {
  const ignored = harness({ ignored: true });
  assert.equal(ignored.tools.children.length, 2);
  assert.equal(ignored.block.tools, undefined);
  assert.equal(harness({ authenticated: false }).tools.children.length, 2);
});
test("dynamic refreshes never duplicate reading controls", () => {
  const page = harness();
  page.events["htmx:afterSwap"]();
  page.events["htmx:oobAfterSwap"]();
  assert.equal(page.post.children.length, 1);
});
