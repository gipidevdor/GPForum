/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/thread-navigation.js`, "utf8");
function harness(lang = "en", count = 2, observe = false) {
  const events = {};
  const nodes = new Map();
  const element = (tag) => ({
    tag, children: [], attributes: {}, dataset: {}, textContent: "",
    append(...nodes) { this.children.push(...nodes); },
    replaceChildren() { this.children = []; },
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener(name, handler) { this[name] = handler; },
    focus() { this.focused = true; },
  });
  const posts = Array.from({ length: count }, (_, index) => ({
    ...element("article"), id: `post-${index}`,
    querySelector(selector) { return { textContent: selector === ".post__permalink" ? `#${26 + index}` : " Alice  hello ", querySelector() { return { textContent: " Alice " }; } }; },
  }));
  posts.forEach(post => nodes.set(post.id, post));
  nodes.set("posts", { before(node) { nodes.set(node.id, node); } });
  const location = {};
  const document = {
    documentElement: { lang }, createElement: element,
    querySelectorAll() { return posts; },
    getElementById(id) { return nodes.get(id); },
    addEventListener(name, handler) { events[name] = handler; },
  };
  const observers = [];
  class Observer {
    constructor(callback) { this.callback = callback; this.posts = []; observers.push(this); }
    observe(post) { this.posts.push(post); }
    disconnect() { this.disconnected = true; }
  }
  posts.forEach((post, index) => { post.getBoundingClientRect = () => ({ top: index * 200 }); });
  vm.runInNewContext(source, { document, location, ...(observe ? { IntersectionObserver: Observer } : {}) });
  return { nodes, posts, events, location, observers, navigation: () => nodes.get("thread-page-navigation") };
}
test("empty pages have no navigation", () => {
  assert.equal(harness("en", 0).navigation(), undefined);
});
test("navigation links use loaded posts and their actual thread positions", () => {
  const page = harness();
  const children = page.navigation().children;
  assert.equal(children[0].href, "#post-0");
  assert.equal(children[1].href, "#post-1");
  assert.equal(children[2].children[1].textContent, "#26 · Alice");
});
test("selecting a post moves both fragment and keyboard focus", () => {
  const page = harness();
  const select = page.navigation().children[2];
  select.value = "post-1";
  select.change();
  assert.equal(page.location.hash, "post-1");
  assert.equal(page.posts[1].focused, true);
  assert.equal(page.posts[1].attributes.tabindex, "-1");
  select.value = "";
  select.change();
  assert.equal(page.location.hash, "post-1");
});
test("dynamic swaps refresh one navigation bar and include appended replies", () => {
  const page = harness("it");
  const navigation = page.navigation();
  assert.equal(navigation.attributes["aria-label"], "Messaggi in questa pagina");
  page.posts.push({ ...page.posts[1], id: "post-new" });
  page.events["htmx:afterSwap"]();
  page.events["htmx:oobAfterSwap"]();
  assert.equal(page.navigation(), navigation);
  assert.equal(navigation.children.length, 4);
  assert.equal(navigation.children[1].href, "#post-new");
  assert.equal(navigation.children[2].children.length, 4);
});

test("reading controls show loaded positions and jump without losing focus", () => {
  const page = harness("it");
  const [previous, position, progress, next] = page.navigation().children[3].children;
  assert.equal(position.textContent, "#26 · 1/2 in pagina");
  assert.equal(previous.disabled, true);
  assert.equal(progress.max, 2);
  next.click();
  assert.equal(page.location.hash, "post-1");
  assert.equal(page.posts[1].focused, true);
  assert.equal(progress.value, 2);
  assert.equal(next.disabled, true);
  page.events["htmx:afterSwap"]();
  assert.equal(page.navigation().dataset.currentPost, "post-1");
});

test("reading observation updates position without rewriting URL history and is released on swaps", () => {
  const page = harness("en", 2, true);
  assert.equal(page.observers[0].posts.length, 2);
  page.observers[0].callback([{ target: page.posts[1], isIntersecting: true }]);
  assert.equal(page.navigation().dataset.currentPost, "post-1");
  assert.equal(page.navigation().children[3].children[2].value, 2);
  assert.equal(page.location.hash, undefined);
  page.posts[1] = { ...page.posts[1] };
  page.events["htmx:afterSwap"]();
  assert.equal(page.observers[0].disconnected, true);
  assert.equal(page.observers.length, 2);
});

test("unrelated swaps preserve controls and do not rebuild reading observers", () => {
  const page = harness("en", 2, true);
  const selector = page.navigation().children[2];
  page.events["htmx:afterSwap"]();
  assert.equal(page.navigation().children[2], selector);
  assert.equal(page.observers.length, 1);
});
