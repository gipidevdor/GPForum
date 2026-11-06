/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/page-enhancements.js`, "utf8");

const clientBindings = [
  ["formNavigation", "[data-account-menu], [data-navigation-filter], [data-transfer-form]", "form-navigation.js"],
  ["composer", "form[data-composer]", "composer.js"],
  ["integrations", "[data-integration-embed]", "integrations.js"],
  ["adminSettings", "[data-settings-search]", "admin-settings.js"],
  ["similar", "[data-similar-threads]", "similar.js"],
  ["threadNavigation", "#posts .post[id]", "thread-navigation.js"],
  ["threadActions", "#posts .post[id]", "thread-actions.js"],
  ["discussionWorkspace", ".thread #reply.composer", "discussion-workspace.js"],
  ["editorSuggestions", "form[data-suggest-url]", "editor-suggestions.js"],
  ["push", "[data-push-settings], [data-push-clear]", "push.js"],
  ["passkeys", "form[data-passkey]", "passkeys.js"],
  ["notifications", "[data-notification-link]", "notifications.js"],
];

test("every GUI enhancement is supplied by the real layout and activates on its controls", () => {
  const layout = fs.readFileSync(`${__dirname}/../../templates/layouts/default.html.ep`, "utf8");
  const assets = {};
  for (const match of layout.matchAll(/data-([a-z-]+)="<%= ui_asset_url\('([^']+)'\) %>"/g)) {
    const name = match[1].replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    assets[name] = `/${match[2]}?v=current`;
  }
  for (const [name, selector, file] of clientBindings) {
    assert.equal(assets[name], `/${file}?v=current`, `${name} has a layout asset binding`);
    assert.ok(fs.existsSync(`${__dirname}/../../assets/js/${file}`), `${file} is shipped`);
    const page = harness({initial: [widget(selector)], assets});
    assert.ok(page.scripts.some(script => script.src === `https://forum.test/${file}?v=current`),
      `${name} loads when its GUI control exists`);
  }
});

function widget(...selectors) {
  return {
    nodeType: 1,
    matches(selector) { return selectors.includes(selector); },
    querySelector() { return null; },
  };
}

function harness({initial = [], mathEnabled = "1", assets = {}} = {}) {
  const scripts = [];
  const events = {};
  let mutation;
  const document = {
    currentScript: {dataset: {
      integrations: "/integrations.js?v=123",
      composer: "/composer.js?v=456",
      katex: "/katex.min.js?v=789",
      mathematics: "/mathematics.js?v=abc",
      ...assets,
    }},
    documentElement: {dataset: {mathEnabled}},
    body: {},
    head: {append(script) { scripts.push(script); }},
    querySelector(selector) { return initial.find((item) => item.matches(selector)) || null; },
    createElement(tag) {
      assert.equal(tag, "script");
      return {remove() { this.removed = true; }};
    },
    addEventListener(name, callback) { events[name] = callback; },
  };
  class MutationObserver {
    constructor(callback) { mutation = callback; }
    observe() {}
  }
  vm.runInNewContext(source, {
    document, MutationObserver, URL,
    location: {href: "https://forum.test/discussion", origin: "https://forum.test"},
  });
  return {scripts, events, mutation};
}

test("pages without matching content do not download optional clients", () => {
  const page = harness();
  assert.equal(page.scripts.length, 0);
  page.mutation([{addedNodes: [{nodeType: 3}, widget()]}]);
  assert.equal(page.scripts.length, 0);
});

test("a fragment activates its client once across swaps and DOM mutations", () => {
  const card = widget("[data-integration-embed]");
  const page = harness({initial: [card]});
  assert.equal(page.scripts.length, 1);
  assert.equal(page.scripts[0].src, "https://forum.test/integrations.js?v=123");
  page.events["htmx:afterSwap"]({detail: {target: card}});
  page.events["htmx:oobAfterSwap"]({target: card});
  page.mutation([{addedNodes: [card]}]);
  assert.equal(page.scripts.length, 1);
  const editor = widget("form[data-composer]");
  page.mutation([{addedNodes: [editor]}]);
  assert.equal(page.scripts.length, 2);
  assert.equal(page.scripts[1].src, "https://forum.test/composer.js?v=456");
});

test("equations wait for the local library and concurrent fragments share the load", async () => {
  const formula = widget(".math-expression");
  const page = harness({initial: [formula]});
  assert.equal(page.scripts.length, 1);
  assert.equal(page.scripts[0].src, "https://forum.test/katex.min.js?v=789");
  page.mutation([{addedNodes: [formula]}]);
  assert.equal(page.scripts.length, 1);
  page.scripts[0].onload();
  await new Promise(setImmediate);
  assert.equal(page.scripts.length, 2);
  assert.equal(page.scripts[1].src, "https://forum.test/mathematics.js?v=abc");
  page.events["htmx:afterSwap"]({target: formula});
  assert.equal(page.scripts.length, 2);
});

test("disabled or unavailable math capability never downloads its renderer", () => {
  for (const options of [{mathEnabled: "0"}, {assets: {katex: undefined}}]) {
    const formula = widget(".math-expression");
    const page = harness({...options, initial: [formula]});
    page.mutation([{addedNodes: [formula]}]);
    assert.equal(page.scripts.length, 0);
  }
});

test("foreign origins and credential-bearing script addresses are refused", () => {
  for (const address of ["https://foreign.test/client.js", "//foreign.test/client.js", "https://user:pass@forum.test/client.js", "javascript:alert(1)"]) {
    const page = harness({
      initial: [widget("[data-integration-embed]")],
      assets: {integrations: address},
    });
    assert.equal(page.scripts.length, 0);
  }
});

test("an unavailable library leaves equations in their native source state", async () => {
  const formula = widget(".math-expression");
  formula.textContent = "x^2";
  const page = harness({initial: [formula]});
  page.scripts[0].onerror();
  await new Promise(setImmediate);
  assert.equal(page.scripts.length, 1);
  assert.equal(page.scripts[0].removed, true);
  assert.equal(formula.textContent, "x^2");
  page.mutation([{addedNodes: [formula]}]);
  assert.equal(page.scripts.length, 1);
});
