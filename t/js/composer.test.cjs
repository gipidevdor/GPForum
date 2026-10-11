/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(path.join(__dirname, "../../assets/js/composer.js"), "utf8");

const tick = async () => {
  for (let i = 0; i < 8; ++i) await new Promise((resolve) => setImmediate(resolve));
};

// Model only the browser interfaces the composer uses. Assertions drive public
// input/click/submit/swap events and inspect requests, content and publication.
const harness = ({ revision = 0, body = "", conflicted = false } = {}) => {
  const requests = [];
  const timers = new Map();
  const listeners = new Map();
  let timerId = 0;
  const node = () => ({
    hidden: true, textContent: "", innerHTML: "", attributes: {},
    classList: { toggle() {} },
    setAttribute(key, value) { this.attributes[key] = value; },
    removeAttribute(key) { delete this.attributes[key]; },
  });
  const makeForm = (initialRevision, initialBody) => {
    const fields = new Map(Object.entries({
      csrf_token: "csrf-test", kind: "reply", thread_id: "thread-1",
      draft_id: "draft-1", draft_revision: String(initialRevision),
      command_id: "publish-1", body_source: initialBody,
    }).map(([name, value]) => [name, {
      get value() { return value; },
      set value(next) { value = String(next); },
    }]));
    const status = node();
    const conflict = node();
    const previewBody = node();
    const previewStatus = node();
    const region = Object.assign(node(), {
      querySelector(selector) { return selector === "[data-preview-body]" ? previewBody : previewStatus; },
    });
    const tools = {
      dataset: {
        saveUrl: "/drafts", previewUrl: "/composer/preview",
        saving: "saving", saved: "saved", unsaved: "unsaved",
        saveFailed: "save failed", conflict: "conflict", previewFailed: "preview failed",
        conflicted: String(conflicted),
      },
      querySelector(selector) { return selector === "[data-draft-status]" ? status : conflict; },
    };
    const events = new Map();
    const form = {
      isConnected: true, fields, status, conflict, previewBody, previewStatus, region,
      publications: [],
      elements: { namedItem(name) { return fields.get(name); } },
      querySelector() { return tools; },
      closest() { return { querySelector() { return region; } }; },
      addEventListener(name, handler) {
        if (!events.has(name)) events.set(name, []);
        events.get(name).push(handler);
      },
      emit(name, props = {}) {
        const event = {
          target: form, defaultPrevented: false,
          preventDefault() { this.defaultPrevented = true; },
          stopImmediatePropagation() { this.stopped = true; },
          ...props,
        };
        for (const handler of events.get(name) || []) {
          handler(event);
          if (event.stopped) break;
        }
        return event;
      },
      requestSubmit(submitter) {
        const event = this.emit("submit", { submitter });
        if (!event.defaultPrevented) this.publications.push({
          submitter,
          body: fields.get("body_source").value,
          revision: fields.get("draft_revision").value,
          command: fields.get("command_id").value,
        });
      },
      edit(value) { fields.get("body_source").value = value; this.emit("input"); },
      button(value) {
        return { name: "composer_action", value, form,
          closest() { return this; } };
      },
      click(value) { return this.emit("click", { target: this.button(value) }); },
    };
    return form;
  };
  const form = makeForm(revision, body);
  const document = {
    forms: [form],
    querySelectorAll() { return this.forms; },
    addEventListener(name, callback) { listeners.set(name, callback); },
  };
  vm.runInNewContext(source, {
    document, URLSearchParams, AbortController,
    window: { addEventListener(name, callback) { listeners.set(name, callback); } },
    FormData: class {
      constructor(selected) { this.selected = selected; }
      *[Symbol.iterator]() {
        for (const [name, field] of this.selected.fields) yield [name, field.value];
      }
    },
    setTimeout(callback, delay) { timers.set(++timerId, { callback, delay }); return timerId; },
    clearTimeout(id) { timers.delete(id); },
    fetch(url, options) {
      return new Promise((resolve, reject) => {
        requests.push({ url, body: options.body.toString(), signal: options.signal,
          reject,
          answer(status, result) { resolve({ status, ok: status >= 200 && status < 300, json: async () => result }); },
          saved(nextRevision, command = "publish-1") { this.answer(200, { ok: 1, draft: { draft_revision: nextRevision, command_id: command } }); },
        });
      });
    },
  });
  return {
    form, requests,
    leaving() {
      const event = { prevented: false, preventDefault() { this.prevented = true; } };
      listeners.get("beforeunload")(event);
      return event;
    },
    runTimers(delay) {
      for (const [id, timer] of [...timers]) if (timer.delay === delay) {
        timers.delete(id);
        timer.callback();
      }
    },
    replace() {
      form.isConnected = false;
      const next = makeForm(0, "");
      document.forms = [next];
      listeners.get("htmx:oobAfterSwap")();
      return next;
    },
  };
};

test("autosaves serialize edits and use acknowledged revisions and publish commands", async () => {
  const h = harness();
  h.form.edit("first");
  h.runTimers(900);
  h.form.edit("second");
  h.runTimers(900);
  assert.equal(h.requests.length, 1);
  h.requests[0].saved(1, "publish-rotated");
  await tick();
  assert.equal(h.requests.length, 2);
  const second = new URLSearchParams(h.requests[1].body);
  assert.equal(second.get("body_source"), "second");
  assert.equal(second.get("draft_revision"), "1");
  assert.equal(second.get("command_id"), "publish-rotated");
  h.requests[1].saved(2, "publish-rotated");
  await tick();
  assert.equal(h.form.status.textContent, "saved");
  h.form.emit("input");
  h.runTimers(900);
  await tick();
  assert.equal(h.requests.length, 2, "an unchanged acknowledgement does not cause a save loop");
});

test("explicitly saving unchanged text refreshes retention and accepts a rotated command", async () => {
  const h = harness({ revision: 2, body: "same text" });
  h.form.click("save");
  assert.equal(h.requests.length, 1);
  h.requests[0].saved(2, "fresh-command");
  await tick();
  assert.equal(h.form.fields.get("command_id").value, "fresh-command");
  assert.equal(h.requests.length, 1);
});

test("a lost acknowledgement retries the exact request before saving newer text", async () => {
  const h = harness({ body: "first" });
  h.form.click("save");
  const original = h.requests[0].body;
  h.requests[0].reject(new TypeError("connection lost"));
  await tick();
  h.form.edit("newer text");
  h.runTimers(900);
  assert.equal(h.requests.length, 1, "automatic saving pauses on failure");
  h.form.click("save");
  assert.equal(h.requests[1].body, original);
  h.requests[1].saved(1);
  await tick();
  assert.equal(new URLSearchParams(h.requests[2].body).get("body_source"), "newer text");
  h.requests[2].saved(2);
  await tick();
  assert.equal(h.form.fields.get("body_source").value, "newer text");
});

test("a conflict stops saving and publishing without replacing typed text", async () => {
  const h = harness({ body: "my text" });
  h.form.click("save");
  h.requests[0].answer(409, { ok: 0, status: "conflict" });
  await tick();
  assert.equal(h.form.conflict.hidden, false);
  assert.equal(h.form.status.textContent, "conflict");
  h.form.edit("still my text");
  h.runTimers(900);
  h.form.requestSubmit({ name: "publish" });
  await tick();
  assert.equal(h.requests.length, 1);
  assert.equal(h.form.publications.length, 0);
  assert.equal(h.form.fields.get("body_source").value, "still my text");
});

test("older preview responses cannot replace the current preview", async () => {
  const h = harness();
  h.form.edit("first");
  h.runTimers(350);
  h.form.edit("second");
  h.runTimers(350);
  assert.equal(h.requests[0].signal.aborted, true);
  h.requests[1].answer(200, { ok: 1, html: "<p>second</p>" });
  await tick();
  h.requests[0].answer(200, { ok: 1, html: "<p>first</p>" });
  await tick();
  assert.equal(h.form.previewBody.innerHTML, "<p>second</p>");
  assert.equal(h.form.region.attributes["aria-busy"], undefined);
});

test("publish waits for saving and replays the original submitter with its acknowledged metadata", async () => {
  const h = harness({ body: "publish this" });
  const submitter = { name: "publish" };
  h.form.requestSubmit(submitter);
  assert.equal(h.form.publications.length, 0);
  h.requests[0].saved(1, "next-publish-command");
  await tick();
  assert.deepEqual(h.form.publications, [{ submitter, body: "publish this", revision: "1", command: "next-publish-command" }]);
});

test("save failure blocks publication; explicit retry reuses the uncertain request", async () => {
  const h = harness({ body: "keep this" });
  h.form.requestSubmit({ name: "publish" });
  h.requests[0].reject(new TypeError("connection lost"));
  await tick();
  assert.equal(h.form.publications.length, 0);
  assert.equal(h.form.status.textContent, "save failed");
  h.form.requestSubmit({ name: "publish" });
  assert.equal(h.requests[1].body, h.requests[0].body);
  h.requests[1].saved(1);
  await tick();
  assert.equal(h.form.publications.length, 1);
});

test("an OOB replacement starts a new composer and ignores the old acknowledgement", async () => {
  const h = harness({ body: "old" });
  h.form.click("save");
  const next = h.replace();
  next.edit("new reply");
  h.runTimers(900);
  h.requests[0].saved(8, "old-command");
  await tick();
  assert.equal(next.fields.get("draft_revision").value, "0");
  h.requests[1].saved(1, "new-command");
  await tick();
  assert.equal(next.fields.get("command_id").value, "new-command");
});

test("an SSR conflict starts with autosave and publish stopped", async () => {
  const h = harness({ revision: 2, body: "retained text", conflicted: true });
  h.form.edit("still retained");
  h.runTimers(900);
  h.form.requestSubmit({ name: "publish" });
  await tick();
  assert.equal(h.requests.length, 0);
  assert.equal(h.form.publications.length, 0);
});

test("navigation warns for unacknowledged text, including failed saves, and stops after acknowledgement", async () => {
  const h = harness();
  assert.equal(h.leaving().prevented, false, "an untouched empty composer does not warn");
  h.form.edit("unsaved text");
  assert.equal(h.leaving().prevented, true);
  h.form.click("save");
  assert.equal(h.leaving().prevented, true, "a pending save is uncertain");
  h.requests[0].reject(new TypeError("lost response"));
  await tick();
  assert.equal(h.leaving().prevented, true);
  h.form.click("save");
  h.requests[1].saved(1);
  await tick();
  assert.equal(h.leaving().prevented, false);
  h.form.edit("newer text");
  h.form.isConnected = false;
  assert.equal(h.leaving().prevented, false, "a removed composer cannot warn after publication");
});
