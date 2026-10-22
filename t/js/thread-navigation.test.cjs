/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/thread-navigation.js`, "utf8");
function harness(lang = "en", count = 2) {
  const events = {};
  const nodes = new Map();
  const element = (tag) => ({
    tag, children: [], attributes: {}, textContent: "",
    append(node) { this.children.push(node); },
    replaceChildren() { this.children = []; },
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener(name, handler) { this[name] = handler; },
    focus() { this.focused = true; },
  });
  const posts = Array.from({ length: count }, (_, index) => ({
    ...element("article"), id: `post-${index}`,
    querySelector(selector) { return { textContent: selector === ".post__permalink" ? `#${26 + index}` : " Alice  hello " }; },
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
  vm.runInNewContext(source, { document, location });
  return { nodes, posts, events, location, navigation: () => nodes.get("thread-page-navigation") };
}
test("empty pages have no navigation", () => {
  assert.equal(harness("en", 0).navigation(), undefined);
});
test("navigation links use loaded posts and their actual thread positions", () => {
  const page = harness();
  const children = page.navigation().children;
  assert.equal(children[0].href, "#post-0");
  assert.equal(children[1].href, "#post-1");
  assert.equal(children[2].children[1].textContent, "#26 · Alice hello");
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
  assert.equal(navigation.children.length, 3);
  assert.equal(navigation.children[1].href, "#post-new");
  assert.equal(navigation.children[2].children.length, 4);
});
