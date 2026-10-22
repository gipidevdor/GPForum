/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/composer.js`, "utf8");
function harness(value, lang = "en") {
  const listeners = {};
  const field = {
    value, dataset: {}, selectionStart: 0, selectionEnd: value.length,
    before(bar) { this.bar = bar; }, after(count) { this.count = count; },
    addEventListener(name, handler) { listeners[name] = handler; },
    setRangeText(text, start, end) { this.value = this.value.slice(0, start) + text + this.value.slice(end); },
    setSelectionRange(start, end) { this.selectionStart = start; this.selectionEnd = end; },
    focus() { this.focused = true; },
    dispatchEvent(event) { this.inputEvents = (this.inputEvents || 0) + 1; listeners[event.type]?.(event); },
  };
  const document = {
    documentElement: { lang },
    querySelectorAll(selector) { return selector.includes("textarea") ? [field] : []; },
    addEventListener() {},
    createElement() { return {
      children: [], setAttribute() {}, append(child) { this.children.push(child); },
      addEventListener(name, fn) { this[name] = fn; },
    }; },
  };
  vm.runInNewContext(source, { document, window: { addEventListener() {} }, Event: class { constructor(type) { this.type = type; } } });
  return field;
}
test("formatting preserves selection and emits input for draft saving", () => {
  const field = harness("hello");
  field.bar.children[0].click();
  assert.equal(field.value, "**hello**");
  assert.equal(field.selectionStart, 2);
  assert.equal(field.selectionEnd, 7);
  assert.equal(field.inputEvents, 1);
  assert.equal(field.focused, true);
});
test("quotes prefix every selected line", () => {
  const field = harness("one\ntwo");
  field.bar.children[3].click();
  assert.equal(field.value, "\n> one\n> two\n");
});
test("code blocks retain line breaks", () => {
  const field = harness("one\ntwo");
  field.bar.children[4].click();
  assert.equal(field.value, "\n```\none\ntwo\n```\n");
});
test("counter counts Unicode characters and localizes labels", () => {
  const field = harness("ciao 😀", "it");
  assert.equal(field.count.textContent, "6 caratteri · 2 parole");
  assert.equal(field.bar.children[0].textContent, "Grassetto");
});
test("list tools mark every selected line and preserve input events", () => {
  const bullets = harness("one\ntwo");
  bullets.bar.children[5].click();
  assert.equal(bullets.value, "\n- one\n- two\n");
  assert.equal(bullets.inputEvents, 1);
  const numbers = harness("one\ntwo\nthree");
  numbers.bar.children[6].click();
  assert.equal(numbers.value, "\n1. one\n2. two\n3. three\n");
  assert.equal(numbers.inputEvents, 1);
});
