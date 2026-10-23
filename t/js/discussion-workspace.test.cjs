/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/discussion-workspace.js`, "utf8");
function harness() {
  const events = {};
  const nodes = [];
  function element() {
    const classes = new Set();
    const handlers = {};
    const node = {
      attributes: {}, children: [], style: {}, isConnected: true,
      classList: { add: name => classes.add(name), remove: name => classes.delete(name), contains: name => classes.has(name) },
      setAttribute(name, value) { this.attributes[name] = value; },
      append(child) { this.children.push(child); },
      before(child) { child.removed = false; }, after(child) { this.afterNode = child; },
      remove() { this.removed = true; },
      addEventListener(name, handler) { handlers[name] = handler; },
      trigger(name, event = {}) { handlers[name]?.(event); },
      focus() { this.focused = true; handlers.focus?.(); },
      getBoundingClientRect() { return { height: 480 }; },
      scrollIntoView() { this.scrolled = true; },
    };
    nodes.push(node);
    return node;
  }
  const section = element();
  const field = element();
  field.value = "La mia bozza";
  const heading = element();
  section.querySelector = selector => selector === "#reply-heading" ? heading : field;
  const document = {
    documentElement: { lang: "it" },
    querySelector: () => section,
    createElement: element,
    addEventListener(name, handler) { events[name] = handler; },
  };
  vm.runInNewContext(source, { document });
  const [dock, minimize] = heading.afterNode.children;
  const reply = (extra = {}) => {
    const event = { target: { closest: () => ({}) }, preventDefault() { this.prevented = true; }, ...extra };
    events.click(event);
    return event;
  };
  return { section, field, dock, minimize, events, nodes, reply };
}
test("reply opens the existing form without replacing its draft", () => {
  const page = harness();
  assert.equal(page.minimize.hidden, true);
  assert.equal(page.reply().prevented, true);
  assert.equal(page.section.classList.contains("composer--docked"), true);
  assert.equal(page.dock.attributes["aria-pressed"], "true");
  assert.equal(page.field.focused, true);
  assert.equal(page.field.value, "La mia bozza");
});
test("minimize, restore and return to page preserve the draft and focus", () => {
  const page = harness();
  page.dock.trigger("click");
  page.minimize.trigger("click");
  assert.equal(page.section.classList.contains("composer--minimized"), true);
  assert.equal(page.minimize.attributes["aria-expanded"], "false");
  assert.equal(page.minimize.focused, true);
  page.minimize.trigger("click");
  assert.equal(page.field.focused, true);
  assert.equal(page.section.classList.contains("composer--minimized"), false);
  page.dock.trigger("click");
  assert.equal(page.section.classList.contains("composer--docked"), false);
  assert.equal(page.section.scrolled, true);
  assert.equal(page.field.value, "La mia bozza");
});
test("Escape minimizes and selection quoting reveals a minimized editor", () => {
  const page = harness();
  page.reply();
  let prevented = false;
  page.section.trigger("keydown", { key: "Escape", preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
  assert.equal(page.section.classList.contains("composer--minimized"), true);
  page.field.trigger("composer:reveal");
  assert.equal(page.section.classList.contains("composer--minimized"), false);
});
test("modified links retain normal browser behavior", () => {
  const page = harness();
  assert.equal(page.reply({ ctrlKey: true }).prevented, undefined);
  assert.equal(page.reply({ button: 1 }).prevented, undefined);
  assert.equal(page.section.classList.contains("composer--docked"), false);
});
test("fragment swaps initialize once and remove a detached draft placeholder", () => {
  const page = harness();
  const count = page.nodes.length;
  page.events["htmx:afterSwap"]();
  assert.equal(page.nodes.length, count);
  page.reply();
  const placeholder = page.nodes.at(-1);
  page.section.isConnected = false;
  page.events["htmx:oobAfterSwap"]();
  assert.equal(placeholder.removed, true);
});
