/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/integrations.js`, "utf8");

function harness(id = "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", provider = "youtube") {
  const events = {};
  const frames = [];
  let documentScans = 0;
  const button = {
    hidden: true,
    dataset: { integrationEmbed: id, embedOrigin: "https://www.youtube-nocookie.com", embedKind: "video", embedTitle: "YouTube video player" },
    closest() { return { dataset: { integrationProvider: provider } }; },
    replaceWith(frame) { this.replacement = frame; },
  };
  const document = {
    body: {},
    querySelectorAll() { documentScans++; return [button]; },
    addEventListener(event, callback) { events[event] = callback; },
    createElement(tag) {
      assert.equal(tag, "iframe");
      const frame = { focus() { this.focused = true; } };
      frames.push(frame);
      return frame;
    },
  };
  let mutation;
  class MutationObserver {
    constructor(callback) { mutation = callback; }
    observe() {}
  }
  vm.runInNewContext(source, { document, MutationObserver, URL });
  return { button, frames, events, mutation, scans: () => documentScans, click() { events.click({ target: { closest() { return button; } } }); } };
}

test("no third party frame exists until the reader requests the video", () => {
  const page = harness();
  assert.equal(page.frames.length, 0);
  assert.equal(page.button.hidden, false);
  page.click();
  assert.equal(page.frames.length, 1);
  const frame = page.frames[0];
  assert.equal(frame.src, "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ");
  assert.equal(frame.title, "YouTube video player");
  assert.equal(frame.referrerPolicy, "strict-origin-when-cross-origin");
  assert.equal(frame.focused, true);
  assert.equal(page.button.replacement, frame);
});

test("tampered IDs and providers cannot select an arbitrary frame address", () => {
  for (const [id, provider] of [["../evil.test", "youtube"], ["https://evil.test/embed", "facebook"]]) {
    const page = harness(id, provider);
    page.click();
    assert.equal(page.frames.length, 0);
  }
});

test("cards inserted by a post swap or composer preview remain interactive", () => {
  const page = harness();
  page.button.hidden = true;
  page.events["htmx:afterSwap"]({detail: {target: {querySelectorAll() {return [page.button];}}}});
  assert.equal(page.button.hidden, false);
  page.button.hidden = true;
  page.mutation([{ addedNodes: [{ nodeType: 1, querySelectorAll() { return [page.button]; } }] }]);
  assert.equal(page.button.hidden, false);
  assert.equal(page.frames.length, 0);
  assert.equal(page.scans(), 1, "fragment updates never rescan the entire document");
  const inserted = {nodeType: 1, hidden: true, matches() {return true;}, querySelectorAll() {return [];}};
  page.mutation([{addedNodes: [inserted]}]);
  assert.equal(inserted.hidden, false, "a newly inserted button root is enabled");
});

test("audio players use the same fixed API without provider-specific browser code", () => {
  for (const [url, origin, provider] of [
    ["https://open.spotify.com/embed/track/0Lr4kGOYn9l83EjuK6cZFQ", "https://open.spotify.com", "spotify"],
    ["https://embed.music.apple.com/it/album/example/123?i=456", "https://embed.music.apple.com", "apple_music"],
  ]) {
    const page = harness(url, provider);
    page.button.dataset.embedOrigin = origin;
    page.button.dataset.embedKind = "audio";
    page.click();
    assert.equal(page.frames[0].src, url);
    assert.equal(page.frames[0].className, "integration-card__audio");
  }
});
