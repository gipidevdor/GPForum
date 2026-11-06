/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/thread-navigation.js`, "utf8");
function harness(lang = "en", count = 2, observe = false, resize = false, icons = false) {
  const events = {};
  const nodes = new Map();
  const element = (tag) => ({
    tag, children: [], attributes: {}, dataset: {}, textContent: "",
    append(...nodes) { this.children.push(...nodes); },
    replaceChildren() { this.children = []; },
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener(name, handler) { this[name] = handler; },
    focus() { this.focused = true; },
    getBoundingClientRect() { return { top: 52, bottom: 140, height: 88 }; },
  });
  const posts = Array.from({ length: count }, (_, index) => ({
    ...element("article"), id: `post-${index}`,
    querySelector(selector) { return { textContent: selector === ".post__permalink" ? `#${26 + index}` : " Alice  hello ", querySelector() { return { textContent: " Alice " }; } }; },
  }));
  posts.forEach(post => nodes.set(post.id, post));
  nodes.set("posts", { before(node) { nodes.set(node.id, node); } });
  if (icons) {
    for (const direction of ["previous", "next"]) {
      nodes.set(`ui-icon-${direction}`, { content: { firstElementChild: {
        cloneNode() { return { approvedIcon: direction }; },
      } } });
    }
  }
  const location = {};
  const properties = new Map();
  const header = { height: 52, getBoundingClientRect() { return { height: this.height }; } };
  const document = {
    documentElement: { lang, style: { setProperty(name, value) { properties.set(name, value); } } }, createElement: element,
    querySelector(selector) { return selector === '.site-header' ? header : null; },
    querySelectorAll() { return posts; },
    getElementById(id) { return nodes.get(id); },
    addEventListener(name, handler) { events[name] = handler; },
  };
  const observers = [];
  const sizeObservers = [];
  class SizeObserver {
    constructor(callback) { this.callback = callback; this.targets = []; sizeObservers.push(this); }
    observe(target) { this.targets.push(target); }
    disconnect() { this.disconnected = true; }
  }
  class Observer {
    constructor(callback) { this.callback = callback; this.posts = []; observers.push(this); }
    observe(post) { this.posts.push(post); }
    disconnect() { this.disconnected = true; }
  }
  posts.forEach((post, index) => { post.getBoundingClientRect = () => ({ top: index * 200, bottom: index * 200 + 180 }); });
  vm.runInNewContext(source, { document, location, ...(observe ? { IntersectionObserver: Observer } : {}), ...(resize ? { ResizeObserver: SizeObserver } : {}) });
  return { nodes, posts, events, location, observers, sizeObservers, properties, header, navigation: () => nodes.get("thread-page-navigation") };
}
test("empty pages have no navigation", () => {
  assert.equal(harness("en", 0).navigation(), undefined);
});

test("reading arrows clone approved SSR symbols rather than drawing another family", () => {
  const page = harness("en", 2, false, false, true);
  const [previous, , , next] = page.navigation().children[1].children;
  assert.equal(previous.children[0].approvedIcon, "previous");
  assert.equal(next.children[0].approvedIcon, "next");
  assert.equal(previous.attributes["aria-label"], "Previous");
  assert.equal(next.attributes["aria-label"], "Next");
});
test("the selector reaches every loaded post, including the first and last", () => {
  const page = harness();
  const children = page.navigation().children;
  assert.equal(children[0].children[1].value, "post-0");
  assert.equal(children[0].children[2].value, "post-1");
  assert.equal(children[0].children[1].textContent, "#26 · Alice");
});
test("selecting a post moves both fragment and keyboard focus", () => {
  const page = harness();
  const select = page.navigation().children[0];
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
  assert.equal(navigation.children.length, 2);
  assert.equal(navigation.children[0].children.length, 4);
  assert.equal(navigation.children[0].children[3].value, "post-new");
});

test("reading controls show loaded positions and jump without losing focus", () => {
  const page = harness("it");
  const [previous, position, progress, next] = page.navigation().children[1].children;
  assert.equal(position.textContent, "#26 · 1/2 in pagina");
  assert.equal(previous.disabled, true);
  assert.equal(previous.attributes["aria-label"], "Precedente");
  assert.equal(next.attributes["aria-label"], "Successivo");
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
  assert.equal(page.navigation().children[1].children[2].value, 2);
  assert.equal(page.location.hash, undefined);
  page.posts[1] = { ...page.posts[1] };
  page.events["htmx:afterSwap"]();
  assert.equal(page.observers[0].disconnected, true);
  assert.equal(page.observers.length, 2);
});

test("unrelated swaps preserve controls and do not rebuild reading observers", () => {
  const page = harness("en", 2, true);
  const selector = page.navigation().children[0];
  page.events["htmx:afterSwap"]();
  assert.equal(page.navigation().children[0], selector);
  assert.equal(page.observers.length, 1);
});

test("anchor clearance follows the actual header and navigation size", () => {
  const page = harness("en", 2, false, true);
  assert.equal(page.properties.get('--header-clearance'), '52px');
  assert.equal(page.properties.get('--reading-clearance'), '88px');
  assert.equal(page.sizeObservers[0].targets.length, 2);
  page.header.height = 116.5;
  page.navigation().getBoundingClientRect = () => ({ height: 132.25 });
  page.sizeObservers[0].callback();
  assert.equal(page.properties.get('--header-clearance'), '117px');
  assert.equal(page.properties.get('--reading-clearance'), '133px');
  page.events['htmx:afterSwap']();
  assert.equal(page.sizeObservers.length, 1);
  page.posts[1] = { ...page.posts[1] };
  page.events['htmx:afterSwap']();
  assert.equal(page.sizeObservers[0].disconnected, true);
  assert.equal(page.sizeObservers.length, 2);
});

test("a post behind the reading controls cannot replace the visible position", () => {
  const page = harness("en", 2, true);
  page.posts[0].getBoundingClientRect = () => ({ top: 0, bottom: 130 });
  page.observers[0].callback([
    { target: page.posts[0], isIntersecting: true },
    { target: page.posts[1], isIntersecting: true },
  ]);
  assert.equal(page.navigation().dataset.currentPost, 'post-1');
});
