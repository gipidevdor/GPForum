/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";

// User journeys use the real server and a disposable PostgreSQL database.
const assert = require("node:assert/strict");
const test = require("node:test");
const {chromium} = require("playwright");
const {startFixture} = require("./support/process.cjs");

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
  JOIN post_bodies b ON b.body_id=p.current_body_id WHERE t.thread_id=? ORDER BY p.position
 }, {Slice => {}}, $c->param('thread'));
 return $c->render(json => $rows);
});

`;

test("posting journeys against PostgreSQL", {timeout: 180000}, async (t) => {
  const running = await startFixture(t, fixture);
  const {address} = running;
  const browser = await chromium.launch({headless: true});
  t.after(() => browser.close());

  for (const javaScriptEnabled of [true, false]) {
    for (const [name, body] of [
      ["accent", "è"],
      ["Unicode", "Caffè: à é ì ò ù — e\u0300 中文 العربية 🙂"],
    ]) {
      await t.test(`${name}: publish, reply, edit and reload, JavaScript=${javaScriptEnabled}`, async () => {
        const context = await browser.newContext({baseURL: address, javaScriptEnabled, locale: "en-US"});
        try {
          const page = await context.newPage();
          page.setDefaultTimeout(8000);
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
          await form.getByRole("button", {name: "Create thread", exact: true}).click();
          assert.equal(await form.getByRole("textbox", {name: "Title", exact: true})
            .evaluate((field) => field === document.activeElement), true, "native validation focuses the missing title");
          await form.getByRole("textbox", {name: "Title", exact: true}).fill(title);
          await form.locator('textarea[name="body_source"]').fill(body);
          const published = page.waitForResponse((r) => r.request().method() === "POST" && new URL(r.url()).pathname === "/threads");
          await form.getByRole("button", {name: "Create thread", exact: true}).click();
          const response = await published;
          assert.equal(response.status(), 302, running.log());
          await page.waitForURL(/\/t\//);
          const thread = new URL(page.url()).pathname.split("/")[2];
          assert.equal(await page.locator("#posts .forum-post-body").first().innerText(), body);
          assert.equal(await page.getByRole("heading", {name: title, exact: true}).count(), 1);
          const reply = page.locator("#reply form");
          await reply.locator('textarea[name="body_source"]').fill(body);
          const replied = page.waitForResponse((r) => r.request().method() === "POST" && r.url().includes("/replies"));
          await reply.getByRole("button", {name: "Post reply", exact: true}).click();
          const replyResponse = await replied;
          assert.ok([200, 302].includes(replyResponse.status()), `${running.log()}\nReply fields: ${JSON.stringify(Object.fromEntries([...new URLSearchParams(replyResponse.request().postData())].filter(([key]) => key !== "csrf_token")))}`);
          await page.waitForFunction((text) => [...document.querySelectorAll("#posts .forum-post-body")]
            .filter((node) => node.innerText === text).length === 2, body);
          await page.reload();
          assert.deepEqual(await page.locator("#posts .forum-post-body").allInnerTexts(), [body, body]);
          const stored = await context.request.get(`/__browser/stored/${thread}`);
          assert.deepEqual(await stored.json(), [{title, body_source: body}, {title, body_source: body}]);
          // Editing must persist the same Unicode text through a different write path.
          const firstPost = page.locator("#posts .post").first();
          await firstPost.locator(".post-tools > summary").click();
          await firstPost.getByText("Edit post", {exact: true}).click();
          const edit = firstPost.getByRole("dialog", {name: /Edit post/}).locator('form:has(textarea[name="body_source"])');
          const editedBody = `${body} — modificato è`;
          await edit.getByRole("textbox", {name: "Post body", exact: true}).fill(editedBody);
          const edited = page.waitForResponse((r) => r.request().method() === "POST" && /\/p\/[^/]+$/.test(r.url()));
          await edit.getByRole("button", {name: "Save edit", exact: true}).click();
          assert.ok([200, 302].includes((await edited).status()), running.log());
          await page.waitForFunction((text) => document.querySelector("#posts .forum-post-body")?.innerText === text, editedBody);
          await page.reload();
          assert.deepEqual(await page.locator("#posts .forum-post-body").allInnerTexts(), [editedBody, body]);
          const storedEdit = await context.request.get(`/__browser/stored/${thread}`);
          assert.deepEqual(await storedEdit.json(), [{title, body_source: editedBody}, {title, body_source: body}]);
          if (javaScriptEnabled && name === "accent") {
            // Reject a genuine write at the server boundary, then retry through the GUI.
            // Only the token is corrupted; persistence and HTTP error rendering stay real.
            await page.route("**/replies", async (route) => {
              const fields = new URLSearchParams(route.request().postData());
              fields.set("csrf_token", "expired");
              await route.continue({postData: fields.toString()});
            });
            const retryForm = page.locator("#reply form");
            await retryForm.getByRole("textbox").fill("Una risposta è ancora qui");
            const refused = page.waitForResponse((r) => r.request().method() === "POST" && r.url().endsWith("/replies"));
            await retryForm.getByRole("button", {name: "Post reply", exact: true}).click();
            assert.equal((await refused).status(), 403);
            await page.locator("#flash").getByRole("alert").waitFor();
            assert.equal(await retryForm.getByRole("textbox").inputValue(), "Una risposta è ancora qui");
            assert.equal(await retryForm.getByRole("button", {name: "Post reply", exact: true}).isEnabled(), true);
            assert.equal(await page.locator("#posts .post").count(), 2);
            assert.ok((await page.locator("#flash").innerText()).trim().length > 0);
            await page.unroute("**/replies");
            const retried = page.waitForResponse((r) => r.request().method() === "POST" && r.url().endsWith("/replies"))
              .catch(async (error) => { throw new Error(`${error.message}\n${running.log()}\nDraft status: ${await retryForm.locator("[data-draft-status]").innerText()}\nErrors: ${errors}`); });
            await retryForm.getByRole("button", {name: "Post reply", exact: true}).click();
            assert.equal((await retried).status(), 200, running.log());
            await page.waitForFunction(() => document.querySelectorAll("#posts .post").length === 3);
            await page.reload();
            const afterRetry = await context.request.get(`/__browser/stored/${thread}`);
            assert.deepEqual(await afterRetry.json(), [
              {title, body_source: editedBody}, {title, body_source: body},
              {title, body_source: "Una risposta è ancora qui"},
            ]);
          }
          assert.deepEqual(errors, [], running.log());
        } finally { await context.close(); }
      });
    }
  }
});
