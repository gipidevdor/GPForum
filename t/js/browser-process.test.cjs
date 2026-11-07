/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {startProcess} = require("../browser/support/process.cjs");

const server = String.raw`
const http = require('node:http');
const server = http.createServer((req,res) => res.end('owned fixture'));
server.listen(0,'127.0.0.1',() => {
  console.log('GPFORUM_BROWSER_READY http://127.0.0.1:' + server.address().port);
});
process.on('SIGTERM',() => server.close(() => process.exit(0)));
`;

test("fixture readiness identifies the child-owned listening socket", async (t) => {
  const running = await startProcess(process.execPath, ["-e", server]);
  t.after(() => running.stop());
  const response = await fetch(running.address);
  assert.equal(await response.text(), "owned fixture");
  await running.stop();
  await assert.rejects(fetch(running.address), /fetch failed/);
});

test("fixture startup failures retain the exit status and diagnostics", async () => {
  await assert.rejects(startProcess(process.execPath, ["-e", "console.error('fixture exploded');process.exit(3)"]),
    (error) => /exited \(3\)/.test(error.message) && /fixture exploded/.test(error.message));
});

test("an unavailable fixture command fails immediately with its spawn error", async () => {
  await assert.rejects(startProcess("/gpforum-missing-test-executable", []), {code: "ENOENT"});
});

test("a silent fixture reaches a bounded startup failure and is stopped", async () => {
  await assert.rejects(startProcess(process.execPath, ["-e", "setInterval(() => {}, 1000)"],
    {startupTimeout: 100}), /startup timed out/);
});

test("an uncooperative fixture is killed rather than hanging cleanup", async () => {
  const stubborn = server.replace("process.on('SIGTERM',() => server.close(() => process.exit(0)));",
    "process.on('SIGTERM',() => {});");
  const running = await startProcess(process.execPath, ["-e", stubborn], {shutdownTimeout: 100});
  await assert.rejects(running.stop(), /required SIGKILL/);
  assert.equal(running.child.signalCode, "SIGKILL");
});
