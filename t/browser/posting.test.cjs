/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";

// User journeys use the real server and a disposable PostgreSQL database.
const assert = require("node:assert/strict");
const {spawn} = require("node:child_process");
const {once} = require("node:events");
const net = require("node:net");
const path = require("node:path");
const test = require("node:test");
const {setTimeout: delay} = require("node:timers/promises");
const {chromium} = require("playwright");

const root = path.resolve(__dirname, "../..");
const fixture = String.raw`
use v5.40;
use lib 'lib', 't/lib';
use GPForum::Test::TemporaryPostgres;
use GPForum::Test::PgDatabase;
use GPForum;
my $database = GPForum::Test::PgDatabase->fresh(seed => 1);
$ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
$ENV{GPFORUM_MINION_ENABLED} = 0;
$ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $dbh = $database->dbh;
my ($owner, $category) = $dbh->selectrow_array(q{
 SELECT p.author_user_id,t.category_id FROM posts p JOIN threads t USING(thread_id)
 JOIN categories c USING(category_id) JOIN spaces s USING(space_id)
 JOIN users u ON u.id=p.author_user_id
 WHERE p.visibility='public' AND p.moderation_state='visible' AND p.deleted_at IS NULL
 AND t.visibility='public' AND t.moderation_state='visible' AND t.deleted_at IS NULL
 AND c.visibility='public' AND s.visibility='public' AND u.status='active'
 AND u.deleted_at IS NULL LIMIT 1
});
my $app = GPForum->new;
$app->routes->get('/__browser/session')->to(cb => sub ($c) {
 $c->session(user_id => $owner);
 return $c->render(json => {category => $category});
});
$app->routes->get('/__browser/stored/:thread')->to(cb => sub ($c) {
 my $rows = $dbh->selectall_arrayref(q{
  SELECT t.title,b.body_source FROM threads t JOIN posts p USING(thread_id)
  JOIN post_bodies b USING(post_id) WHERE t.thread_id=? ORDER BY p.position
 }, {Slice => {}}, $c->param('thread'));
 return $c->render(json => $rows);
});
$app->start;
`;

test("posting journeys against PostgreSQL", {timeout: 180000}, async (t) => {
  const reservation = net.createServer();
  reservation.listen(0, "127.0.0.1");
  await once(reservation, "listening");
  const address = `http://127.0.0.1:${reservation.address().port}`;
  await new Promise((resolve) => reservation.close(resolve));
  const app = spawn(path.join(root, "script/gpforum-carton"),
    ["exec", "perl", "-e", fixture, "daemon", "-l", address], {
      cwd: root,
      env: {...process.env, GPFORUM_ENV: "development", MOJO_MODE: "development"},
      stdio: ["ignore", "pipe", "pipe"],
    });
  let log = "";
  for (const stream of [app.stdout, app.stderr]) {
    stream.on("data", (chunk) => { log = (log + chunk).slice(-12000); });
  }
  t.after(async () => {
    if (app.exitCode !== null) return;
    const exited = once(app, "exit");
    app.kill("SIGTERM");
    await exited;
  });
  let ready = false;
  for (let attempt = 0; attempt < 600; attempt++) {
    if (app.exitCode !== null) throw new Error(`fixture exited: ${log}`);
    try { ready = (await fetch(`${address}/health/live`)).ok; } catch {}
    if (ready) break;
    await delay(100);
  }
  assert.ok(ready, `fixture did not start: ${log}`);
  const browser = await chromium.launch({headless: true});
  t.after(() => browser.close());

  for (const javaScriptEnabled of [true, false]) {
    for (const [name, body] of [
      ["accent", "è"],
      ["Unicode", "Caffè: à é ì ò ù — e\u0300 中文 العربية 🙂"],
    ]) {
      await t.test(`${name}: publish, reply and reload, JavaScript=${javaScriptEnabled}`, async () => {
        const context = await browser.newContext({baseURL: address, javaScriptEnabled, locale: "en-US"});
        try {
          const page = await context.newPage();
          const errors = [];
          page.on("pageerror", (error) => errors.push(error.message));
          page.on("response", (response) => {
            if (response.status() >= 500) errors.push(`${response.status()} ${response.url()}`);
          });
          const session = await context.request.get("/__browser/session");
          const {category} = await session.json();
          await page.goto("/new-thread");
          const title = `Browser ${name} ${javaScriptEnabled}: è`;
          const form = page.locator('form[action="/threads"]');
          await form.locator('[name="category_id"]').selectOption(category);
          await form.getByRole("textbox", {name: "Title", exact: true}).fill(title);
          await form.locator('textarea[name="body_source"]').fill(body);
          const published = page.waitForResponse((r) => r.request().method() === "POST" && new URL(r.url()).pathname === "/threads");
          await form.getByRole("button", {name: "Create thread", exact: true}).click();
          const response = await published;
          assert.equal(response.status(), 302, log);
          await page.waitForURL(/\/t\//);
          const thread = new URL(page.url()).pathname.split("/")[2];
          assert.equal(await page.locator(".forum-post-body").first().innerText(), body);
          const reply = page.locator("#reply form");
          await reply.locator('textarea[name="body_source"]').fill(body);
          const replied = page.waitForResponse((r) => r.request().method() === "POST" && r.url().includes("/replies"));
          await reply.getByRole("button", {name: "Post reply", exact: true}).click();
          const replyResponse = await replied;
          assert.ok([200, 302].includes(replyResponse.status()), log);
          await page.waitForFunction((text) => [...document.querySelectorAll(".forum-post-body")]
            .filter((node) => node.innerText === text).length === 2, body);
          await page.reload();
          assert.deepEqual(await page.locator(".forum-post-body").allInnerTexts(), [body, body]);
          const stored = await context.request.get(`/__browser/stored/${thread}`);
          assert.deepEqual(await stored.json(), [{title, body_source: body}, {title, body_source: body}]);
          assert.deepEqual(errors, [], log);
        } finally { await context.close(); }
      });
    }
  }
});
