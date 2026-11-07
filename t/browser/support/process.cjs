/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";

const {spawn} = require("node:child_process");
const path = require("node:path");
const readline = require("node:readline");

const root = path.resolve(__dirname, "../../..");
const marker = "GPFORUM_BROWSER_READY ";

function exited(child, timeout) {
  if (child.exitCode !== null || child.signalCode !== null || !child.pid) return Promise.resolve(true);
  return new Promise((resolve) => {
    const finish = (result) => {
      clearTimeout(timer);
      child.removeListener("exit", onExit);
      resolve(result);
    };
    const onExit = () => finish(true);
    const timer = setTimeout(() => finish(false), timeout);
    child.once("exit", onExit);
  });
}

async function stop(child, timeout) {
  if (child.exitCode !== null || child.signalCode !== null || !child.pid) return;
  const stopped = exited(child, timeout);
  child.kill("SIGTERM");
  if (await stopped) return;
  const killed = exited(child, 1000);
  child.kill("SIGKILL");
  if (!await killed) {
    child.stdout.destroy();
    child.stderr.destroy();
    child.unref();
  }
  throw new Error("browser fixture ignored SIGTERM and required SIGKILL");
}

// Readiness comes from the child that owns the bound socket. Reserving and
// releasing a port before spawning could probe an unrelated process instead.
async function startProcess(command, args, {cwd = root, env = process.env,
  startupTimeout = 30000, shutdownTimeout = 5000} = {}) {
  const child = spawn(command, args, {cwd, env, stdio: ["ignore", "pipe", "pipe"]});
  let log = "";
  for (const stream of [child.stdout, child.stderr]) {
    stream.on("data", (chunk) => { log = (log + chunk).slice(-12000); });
  }
  const lines = readline.createInterface({input: child.stdout});
  try {
    const address = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => finish(new Error(`browser fixture startup timed out\n${log}`)), startupTimeout);
      const onClose = (code, signal) => finish(new Error(`browser fixture exited (${code ?? signal})\n${log}`));
      const onError = (error) => finish(error);
      const onLine = (line) => {
        if (!line.startsWith(marker)) return;
        try {
          const url = new URL(line.slice(marker.length));
          if (url.protocol !== "http:" || url.hostname !== "127.0.0.1" || !url.port || url.username || url.password) {
            throw new Error("invalid browser fixture listen address");
          }
          finish(null, url.origin);
        } catch (error) { finish(error); }
      };
      const finish = (error, value) => {
        clearTimeout(timer);
        child.removeListener("close", onClose);
        child.removeListener("error", onError);
        lines.removeListener("line", onLine);
        if (error) reject(error); else resolve(value);
      };
      child.once("error", onError);
      child.once("close", onClose);
      lines.on("line", onLine);
    });
    return {address, child, log: () => log, stop: () => stop(child, shutdownTimeout)};
  } catch (error) {
    try { await stop(child, shutdownTimeout); } catch (cleanup) { error.cause = cleanup; }
    throw error;
  } finally { lines.close(); }
}

async function startFixture(t, fixture, options = {}) {
  const program = fixture + String.raw`
require Mojo::Server::Daemon;
require IO::Handle;
my $server = Mojo::Server::Daemon->new(
    app => $app, listen => ['http://127.0.0.1:0'], silent => 1);
$server->start;
STDOUT->autoflush(1);
say 'GPFORUM_BROWSER_READY http://127.0.0.1:' . $server->ports->[0];
$server->run;
`;
  const running = await startProcess(path.join(root, "script/gpforum-carton"),
    ["exec", "perl", "-e", program], {
      ...options,
      env: {...process.env, GPFORUM_ENV: "development", MOJO_MODE: "development", ...options.env},
    });
  t.after(() => running.stop());
  return running;
}

module.exports = {startFixture, startProcess};
