/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {chromium} = require("playwright");
const {startFixture} = require("./support/process.cjs");

// Only account setup and independent state inspection are fixture endpoints.
// Login, registration, WebAuthn, logout and revocation use the real GUI/services.
const fixture = String.raw`
use v5.40;
use lib 'lib', 't/lib';
use GPForum::Test::TemporaryPostgres;
use GPForum::Test::PgDatabase;
use GPForum::Infrastructure::Id;
use GPForum;
my $database = GPForum::Test::PgDatabase->fresh(seed => 1);
$ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
$ENV{GPFORUM_PUBLIC_BASE_URL} = 'http://localhost:3000';
$ENV{GPFORUM_MINION_ENABLED} = 0;
$ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $app = GPForum->new;
my $dbh = $database->dbh;
my $ids = GPForum::Infrastructure::Id->new;
my $user = $ids->uuid;
my $hash = $app->build_controller->gp_password->hash_password('Browser passkey correct horse 2026!');
$dbh->do(q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status,email_verified_at)
 VALUES(?, 'passkey_browser', 'Passkey browser', 'passkey_browser@example.test', ?, 'active', now())},
 undef, $user, $hash);
$dbh->do(q{INSERT INTO credentials(id,user_id,type,secret_hash) VALUES(?,?,'password',?)},
 undef, $ids->uuid, $user, $hash);
# The fixture's ephemeral bound port is known only after its server starts.
$app->hook(before_dispatch => sub ($c) {
 $c->gp_config->public_base_url('http://localhost:' . $c->req->url->to_abs->port);
});
$app->routes->get('/__browser/passkey-state')->to(cb => sub ($c) {
 my $keys = $dbh->selectall_arrayref(q{SELECT p.id,p.label,p.sign_count,c.revoked_at FROM passkeys p JOIN credentials c ON c.id=p.id WHERE p.user_id=?},
  {Slice => {}}, $user);
 my ($posts) = $dbh->selectrow_array('SELECT count(*) FROM posts WHERE author_user_id=?', undef, $user);
 my ($category) = $dbh->selectrow_array(q{SELECT c.category_id FROM categories c JOIN spaces s USING(space_id)
  WHERE c.visibility='public' AND s.visibility='public' LIMIT 1});
 return $c->render(json => {signed_in => (($c->session('user_id') // '') eq $user ? 1 : 0),
  keys => $keys, posts => 0 + $posts, category => $category});
});
`;

test("passkeys connect the real GUI, browser authenticator and PostgreSQL", {timeout: 120000}, async (t) => {
  const running = await startFixture(t, fixture);
  const address = running.address.replace("127.0.0.1", "localhost");
  const browser = await chromium.launch({headless: true});
  t.after(() => browser.close());
  const context = await browser.newContext({baseURL: address, locale: "en-US"});
  t.after(() => context.close());
  const page = await context.newPage();
  page.setDefaultTimeout(15000);
  const errors = [];
  const dialogs = [];
  page.on("dialog", async (dialog) => { dialogs.push(dialog.type()); await dialog.accept(); });
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("response", (response) => {
    if (response.status() >= 500) errors.push(`${response.status()} ${response.url()}`);
  });
  const cdp = await context.newCDPSession(page);
  await cdp.send("WebAuthn.enable");
  const {authenticatorId} = await cdp.send("WebAuthn.addVirtualAuthenticator", {options: {
    protocol: "ctap2", transport: "internal", hasResidentKey: true,
    hasUserVerification: true, isUserVerified: true, automaticPresenceSimulation: true,
  }});
  const state = async () => {
    const response = await context.request.get("/__browser/passkey-state");
    assert.equal(response.status(), 200, running.log());
    return response.json();
  };

  await page.goto("/login");
  const passwordLogin = page.locator('form[action="/login"]');
  await passwordLogin.locator('[name="identifier"]').fill("passkey_browser");
  await passwordLogin.locator('[name="password"]').fill("Browser passkey correct horse 2026!");
  const signedIn = page.waitForResponse((r) => r.request().method() === "POST" && new URL(r.url()).pathname === "/login");
  await passwordLogin.getByRole("button", {name: "Login", exact: true}).click();
  assert.equal((await signedIn).status(), 302, running.log());
  await page.waitForURL((url) => url.pathname !== "/login");
  assert.equal((await state()).signed_in, 1);

  await page.goto("/menu");
  await page.locator("#menu-account").click();
  await page.getByRole("link", {name: "Passkeys", exact: true}).click();
  await page.waitForURL("**/settings/passkeys");
  const registration = page.locator('form[data-passkey="register"]');
  await registration.locator('[name="label"]').fill("Browser laptop è");
  await registration.locator('[name="password"]').fill("Browser passkey correct horse 2026!");
  const registered = page.waitForResponse((r) => r.url().endsWith("/settings/passkeys/finish"));
  await registration.getByRole("button", {name: "Add passkey", exact: true}).click();
  assert.equal((await registered).status(), 200, running.log());
  await page.getByRole("heading", {name: "Browser laptop è", exact: true}).waitFor();
  const saved = await state();
  assert.equal(saved.keys.length, 1);
  assert.equal(saved.keys[0].label, "Browser laptop è");
  assert.equal(saved.keys[0].revoked_at, null);
  const device = await cdp.send("WebAuthn.getCredentials", {authenticatorId});
  assert.equal(device.credentials.length, 1);
  assert.equal(device.credentials[0].rpId, "localhost");

  const logout = async () => {
    await page.locator("[data-account-menu] > summary").click();
    const loggedOut = page.waitForResponse((r) => r.request().method() === "POST" && r.url().endsWith("/logout"));
    await page.locator('form[action="/logout"]').getByRole("button").click();
    assert.equal((await loggedOut).status(), 202, running.log());
    await page.goto("/login");
    assert.equal((await state()).signed_in, 0);
  };
  await logout();
  const passkeyLogin = page.locator('form[data-passkey="login"]');
  const authenticated = page.waitForResponse((r) => r.url().endsWith("/login/passkey/finish"));
  await passkeyLogin.getByRole("button").click();
  assert.equal((await authenticated).status(), 200, running.log());
  await page.waitForURL((url) => !url.pathname.startsWith("/login"));
  const loggedIn = await state();
  assert.equal(loggedIn.signed_in, 1, "passkey login opens a normal authenticated session");
  assert.ok(Number(loggedIn.keys[0].sign_count) > Number(saved.keys[0].sign_count));

  // A passkey session must authorize ordinary forum features, not just its own settings.
  await page.goto("/menu");
  await page.locator("#menu-forum").click();
  await page.getByRole("link", {name: "Start a thread", exact: true}).click();
  await page.waitForURL("**/new-thread");
  await page.waitForLoadState("load");
  const thread = page.locator('form[action="/threads"]');
  await thread.locator('[name="category_id"]').selectOption(loggedIn.category);
  await thread.getByRole("textbox", {name: "Title", exact: true}).fill("A passkey member can publish è");
  await thread.locator('textarea[name="body_source"]').fill("Pubblicato con una passkey: è.");
  const published = page.waitForResponse((r) => r.request().method() === "POST" && new URL(r.url()).pathname === "/threads")
    .catch(async (error) => { throw new Error(`${error.message}\n${running.log()}\nDraft: ${await thread.locator("[data-draft-status]").innerText()}\nErrors: ${errors}`); });
  await thread.getByRole("button", {name: "Create thread", exact: true}).click();
  assert.equal((await published).status(), 302, running.log());
  await page.waitForURL(/\/t\//);
  assert.equal(await page.locator("#posts .forum-post-body").first().innerText(), "Pubblicato con una passkey: è.");
  assert.equal((await state()).posts, 1, "passkey session publishes as the authenticated account");

  await page.goto("/settings/passkeys");
  const key = page.getByRole("region", {name: "Browser laptop è", exact: true});
  await key.locator('[name="password"]').fill("Browser passkey correct horse 2026!");
  const revoked = page.waitForResponse((r) => r.request().method() === "POST" && r.url().endsWith("/revoke"));
  await key.getByRole("button").click();
  assert.equal((await revoked).status(), 302, running.log());
  await page.waitForURL("**/settings/passkeys");
  assert.notEqual((await state()).keys[0].revoked_at, null, "GUI revocation persists");
  await logout();
  const refused = page.waitForResponse((r) => r.url().endsWith("/login/passkey/finish"));
  await page.locator('form[data-passkey="login"]').getByRole("button").click();
  assert.equal((await refused).status(), 400, running.log());
  await page.locator('[data-passkey="login"] [data-passkey-status]').filter({hasText: /failed|could not/i}).waitFor();
  assert.equal((await state()).signed_in, 0, "revoked device cannot open a session");
  assert.equal(await page.locator('[data-passkey="login"] button').isEnabled(), true);
  assert.deepEqual(errors, [], running.log());
  assert.deepEqual(dialogs, [], "saved publication must not prompt about unsent changes");
});
