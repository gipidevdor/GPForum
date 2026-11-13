/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";

// Run explicitly with Playwright on NODE_PATH; see t/browser/README.md.
// The real app, templates, assets and controllers run against the same service
// doubles as the Perl fragment tests. No PostgreSQL or production writes.
const assert = require("node:assert/strict");
const test = require("node:test");
const {chromium} = require("playwright");
const {startFixture} = require("./support/process.cjs");

const fixture = String.raw`
use v5.40;
use lib 'lib', 't/lib';
use GPForum::OS::Reactor;
use GPForum;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::PostFragmentServices;
my $app = GPForum->new;
my $services = GPForum::Test::PostFragmentServices->new;
for my $helper (qw(
    gp_category_reader gp_thread_reader gp_thread_detail_reader
    gp_thread_composer gp_thread_store gp_post_reader gp_post_composer
    gp_post_store gp_thread_read_state gp_mention_store gp_mention_reader
    gp_bookmark_store gp_bookmark_folders gp_like_store gp_reaction_store
    gp_reply_links gp_thread_tags gp_subscription_store gp_notification_dispatcher
    gp_search_service gp_rate_limiter gp_suspension_store gp_attachment_store
)) {
    $app->helper($helper => sub { return $services; });
}
$app->helper(gp_command_idempotency => sub {
    return GPForum::Test::CommandIdempotency->new;
});
$app->routes->get('/__browser/session/:user')->to(cb => sub ($c) {
    $c->session(user_id => $c->param('user'));
    return $c->render(text => 'ready');
});
$app->log->level('fatal');

`;

test("htmx 4 runs GPForum fragments under its real CSP", {timeout: 60000}, async (t) => {
  const running = await startFixture(t, fixture);
  const {address} = running;
  const browser = await chromium.launch({headless: true});
  t.after(() => browser.close());

  const open = async (options = {}, prepare = async () => {}) => {
    const context = await browser.newContext({baseURL: address, ...options});
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.addInitScript(() => {
      window.fragmentSwaps = 0;
      window.requestCompletions = 0;
      window.requestStarts = 0;
      window.cspViolations = [];
      document.addEventListener("htmx:after:swap", () => window.fragmentSwaps++);
      document.addEventListener("htmx:finally:request", () => window.requestCompletions++);
      document.addEventListener("htmx:before:request", () => window.requestStarts++);
      document.addEventListener("securitypolicyviolation", (e) => window.cspViolations.push(e.violatedDirective));
    });
    await prepare(page);
    await page.goto("/__browser/session/user-2");
    await page.goto("/t/thread-1");
    return {page, context, errors};
  };
  const subscribe = '#thread-toolbar form[action="/t/thread-1/subscribe"]';
  const submit = (page, selector) => page.locator(selector).evaluate((form) => form.requestSubmit());

  await t.test("boosted writes inherit their target and update out-of-band notices", async () => {
    const {page, context, errors} = await open();
    try {
      assert.equal(await page.evaluate(() => htmx.version), "4.0.1");
      assert.equal(await page.evaluate(() => htmx.config.implicitInheritance), false);
      const request = page.waitForRequest((r) => r.method() === "POST" && r.url().endsWith("/subscribe"));
      await submit(page, subscribe);
      const sent = await request;
      await page.waitForFunction(() => window.fragmentSwaps === 1);
      assert.equal(sent.headers()["hx-request"], "true");
      assert.equal(sent.headers()["hx-request-type"], "partial");
      assert.equal(await page.locator("#thread-toolbar").count(), 1);
      assert.equal(await page.locator("#thread-toolbar #thread-toolbar").count(), 0);
      assert.equal(page.url(), `${address}/t/thread-1`);
      assert.equal(await page.locator("#flash .flash--success").count(), 1);
      assert.ok(new URLSearchParams(sent.postData()).get("csrf_token"));
      assert.deepEqual(await page.evaluate(() => window.cspViolations), []);
      assert.deepEqual(errors, []);
    } finally { await context.close(); }
  });

  await t.test("pagination appends posts and replaces its out-of-band control once", async () => {
    const {page, context, errors} = await open();
    try {
      const previous = await page.locator("#posts > li").count();
      await page.locator("#posts-pagination a").evaluate((link) => link.click());
      await page.waitForFunction(() => window.fragmentSwaps === 1);
      assert.ok(await page.locator("#posts > li").count() > previous);
      assert.equal(await page.locator("#posts-pagination").count(), 1);
      assert.equal(await page.locator("#thread-header").count(), 1);
      assert.ok(await page.locator("#posts .post").evaluateAll((posts) =>
        posts.every((post) => post.querySelectorAll(".post-reading-tools").length === 1)));
      assert.deepEqual(await page.evaluate(() => window.cspViolations), []);
      assert.deepEqual(errors, []);
    } finally { await context.close(); }
  });

  await t.test("a rejected reply updates its notice without appending or losing the draft", async () => {
    const {page, context, errors} = await open({}, (p) => p.route("**/composer.js*", (route) =>
      route.fulfill({contentType: "text/javascript", body: ""})));
    try {
      const previous = await page.locator("#posts > li").count();
      await page.locator('#reply textarea[name="body_source"]').fill("Keep my unsent reply");
      await page.locator('#reply input[name="csrf_token"]').evaluate((field) => { field.value = "expired"; });
      const response = page.waitForResponse((r) => r.request().method() === "POST" && r.url().endsWith("/replies"));
      await submit(page, "#reply form");
      const rejected = await response;
      assert.equal(rejected.status(), 403);
      assert.equal(rejected.headers()["hx-reswap"], "none");
      assert.equal(rejected.request().headers()["hx-request"], "true");
      await page.waitForSelector("#flash .flash--error");
      assert.equal(await page.locator("#posts > li").count(), previous);
      assert.equal(await page.locator('#reply textarea[name="body_source"]').inputValue(), "Keep my unsent reply");
      assert.equal(await page.locator('#reply button[type="submit"]:disabled').count(), 0);
      assert.deepEqual(errors, []);
    } finally { await context.close(); }
  });

  await t.test("each reaction submits its own action and command identity", async () => {
    const {page, context, errors} = await open();
    try {
      const buttons = await page.locator('#post-post-1 .post__reactions button[name="command_id"]')
        .evaluateAll((nodes) => nodes.map((button) => ({action: button.formAction, command: button.value})));
      assert.equal(buttons.length, 4);
      for (let index = 0; index < buttons.length; index++) {
        await page.goto("/t/thread-1");
        const button = page.locator('#post-post-1 .post__reactions button[name="command_id"]').nth(index);
        const expected = await button.evaluate((node) => ({action: node.formAction, command: node.value}));
        const request = page.waitForRequest((r) => r.method() === "POST" && r.url() === expected.action);
        await button.evaluate((node) => node.form.requestSubmit(node));
        const sent = await request;
        await page.waitForFunction(() => window.fragmentSwaps === 1);
        assert.equal(new URLSearchParams(sent.postData()).get("command_id"), expected.command);
        assert.equal(await page.locator("#post-post-1").count(), 1);
        assert.equal(await page.locator("#flash .flash--success").count(), 1);
      }
      assert.deepEqual(errors, []);
    } finally { await context.close(); }
  });

  for (const outcome of ["replaced form", "retained form"]) {
    await t.test(`double submission sends one request and releases controls (${outcome})`, async () => {
      const {page, context} = await open();
      let release = () => {};
      try {
        let requests = 0;
        let observed;
        const pending = new Promise((resolve) => { release = resolve; });
        const firstRequest = new Promise((resolve) => { observed = resolve; });
        await page.route("**/t/thread-1/subscribe", async (route) => {
          requests++;
          observed();
          await pending;
          if (outcome === "retained form") {
            // Exercise a failed response that leaves its source form connected,
            // as well as the successful response that replaces the toolbar.
            await route.fulfill({status: 422, contentType: "text/html",
              headers: {"HX-Reswap": "none"},
              body: '<div id="flash" hx-swap-oob="true"><p class="flash--error">Retry</p></div>'});
          } else {
            await route.continue();
          }
        });
        await page.locator(subscribe).evaluate((form) => { form.requestSubmit(); form.requestSubmit(); });
        await firstRequest;
        assert.equal(requests, 1, "only one request is admitted while its response is held");
        release();
        await page.waitForFunction(() => window.fragmentSwaps >= 1 && window.requestCompletions >= 1);
        assert.equal(requests, 1);
        assert.equal(await page.evaluate(() => window.requestStarts), 1, "no deferred duplicate starts after completion");
        assert.equal(await page.locator('#thread-toolbar button[type="submit"]:disabled').count(), 0);
      } finally { release(); await context.close(); }
    });
  }

  await t.test("validation responses replace the fragment and transport failures unlock the form", async () => {
    const {page, context, errors} = await open();
    try {
      const toolbar = await page.locator("#thread-toolbar").evaluate((node) => {
        const copy = node.cloneNode(true);
        const feedback = document.createElement("p");
        feedback.id = "validation-feedback";
        feedback.textContent = "Try again";
        copy.append(feedback);
        return copy.outerHTML;
      });
      await page.route("**/t/thread-1/subscribe", (route) => route.fulfill({
        status: 422, contentType: "text/html", body: toolbar,
      }));
      await submit(page, subscribe);
      await page.waitForSelector("#validation-feedback");
      assert.equal(await page.locator("#thread-toolbar").count(), 1);
      await page.unroute("**/t/thread-1/subscribe");
      await page.goto("/t/thread-1");
      await page.route("**/t/thread-1/subscribe", (route) => route.abort("connectionrefused"));
      await submit(page, subscribe);
      await page.waitForFunction(() => window.requestCompletions === 1);
      assert.equal(await page.locator(`${subscribe} button:disabled`).count(), 0);
      assert.deepEqual(errors, []);
    } finally { await context.close(); }
  });

  await t.test("native forms still work with JavaScript disabled", async () => {
    const {page, context} = await open({javaScriptEnabled: false});
    try {
      const response = page.waitForResponse((r) => r.request().method() === "POST" && r.url().endsWith("/subscribe"));
      await submit(page, subscribe);
      const received = await response;
      assert.equal(received.status(), 302);
      assert.equal(received.request().headers()["hx-request"], undefined);
      await page.waitForSelector("#thread-toolbar");
      assert.equal(await page.locator("#thread-toolbar").count(), 1);
    } finally { await context.close(); }
  });
});
