# ADR 0124: The Service Reads Its Metrics Tokens Again From Its Environment File

## Status

Accepted (2026-10-10). This is the owner's decision for operator iteration 4:
a metrics-token rotation is three commands, `gpforum secret rotate metrics`,
the scrapers' new token, then `gpforum secret rotate metrics --finish`, and
the running service re-reads the accepted token list without a restart.
It amends ADR 0120 section 4, where `secret rotate` named a restart for
both secrets. The session secret keeps that restart. It builds on ADR 0120
(the front door reads the environment file, and the process environment
wins) and ADR 0121 (the application is built before Hypnotoad forks).

Amended 2026-10-11, after the iteration-4 token review and walkthrough 4
(friction 1): Hypnotoad's manager reads the file too, so a worker it forks
later never starts from the tokens the service started with (sections 2
and 4).

Amended 2026-10-14, after the adversarial review of that fix: the manager
also writes the list it accepts into its own environment, so a manager
Hypnotoad's hot deployment starts in its place follows the file too
(section 2).

## Context

Walkthrough 3 (`docs/ops/evidence/2026-10-10-operator-walkthrough-3`,
section 4.2, friction 6) counted four commands for a rotation: rotate,
restart, `--finish`, restart. The target was three, straight from
`gpforum help`. The second restart is the one that makes the old token stop
working, so that restart was a security step and could not just be dropped.
The owner chose the other way out: the running service follows the file.

`GPFORUM_METRICS_TOKEN` and `GPFORUM_METRICS_TOKENS` decide two things, and
nothing else depends on them:

- whether `/metrics` answers, and
- whether `/health` and `/health/ready` give the full report or the status
  alone.

The values are compared per request, in constant time
(`GPForum::Web::OperationsAccess`). Changing the list while the service
runs is therefore safe, as long as it never changes to "no token", which
opens both endpoints in development.

## Decision

### 1. Where the list comes from

The tokens follow the environment file the service's supervisor read:

- **The file named in `GPFORUM_ENV_FILE`**, when the process environment
  holds it. This is how a service started for a file that is not the
  host's own names that file. The front door's `start --service`, which
  the printed units run, is to export the file it read before it execs
  Hypnotoad.
- **Otherwise, the file `bin/gpforum` read when Hypnotoad loaded it**
  (`GPForum::Command::Support::ServiceEnvironment->loaded`). That is the
  host's own: `/etc/gpforum/gpforum.env`, FreeBSD's
  `/usr/local/etc/gpforum/gpforum.env`, or Homebrew's on macOS, the file
  every shipped unit names. Installs that predate this release follow it
  with their current units.

### 2. Only a file that holds what the service started with

Whether the tokens follow the file is decided once
(`GPForum::Service::Operations::MetricsTokens->watch`, called from
`GPForum::Bootstrap::Operations`). It happens when the application is
built, before Hypnotoad forks, so every worker inherits the same decision,
including one Hypnotoad starts later to replace another.

A worker inherits the list too, and the manager it is forked from serves
no request, so no check ever made the manager read the file. Hypnotoad
forks a worker after its `accepts`, or after a missed heartbeat, and each
such worker started from the tokens the service started with. Walkthrough
4 reproduced it: rotate A to B, `--finish`, add a line that is not
`NAME=value`, replace the workers, and the new ones accepted A and refused
B. So when the file is followed, a `before_server_start` hook
(`MetricsTokens->follow_in_manager`) subscribes the manager to
`Mojo::Server::Prefork`'s `wait` event. The manager then reads the file
as a worker does, at each turn of its loop, and a worker it forks starts
from the list the manager accepted last. A server that does not fork
(`gpforum start --foreground`, the tests' client) has no manager and is not
subscribed.

Hypnotoad's hot deployment -- `USR2`, or Hypnotoad run against the live
service, which a second `gpforum start --service` is -- does not fork the
new manager from the old one's memory: it execs `bin/gpforum` again, with
the old manager's environment. That environment held the tokens the
service started with. The review reproduced it against a live Hypnotoad:
rotate A to B, `--finish`, `USR2`. The new manager found the file holding B,
not A, did not follow it, and its workers accepted A and refused B until a
restart. So the manager, each time it accepts a new list, writes it into
its environment: `GPFORUM_METRICS_TOKEN` and `GPFORUM_METRICS_TOKENS`, the
latter set even when empty, so the file's own line cannot fill it. The
manager a hot deployment starts begins from the list accepted last, finds
the file holding it, and follows the file. If the file cannot be used at
that moment, it keeps that list, not the start-time one, and does not
follow the file until a restart, logging why at its start.

The file is followed only when its tokens are exactly the ones the service
started with. The supervisor read that same file a moment earlier. If the
file holds others, it is not where the service's tokens came from: it may
belong to another forum on the same host, or the shell may have set the
token apart. In that case the tokens stay as they started, until a
restart, and the start logs why.

At start the process environment still wins, as ADR 0120 says. Once the
file is followed, its two lines win, which is the same precedence every
shipped supervisor applies on a restart:

- systemd's `EnvironmentFile=` overrides `Environment=`;
- the launchd job and the rc script source the file last.

### 3. When it is read again

Each token check (`/metrics`, `/health`, `/health/ready`) makes one `stat`
of the file. The file is read again only when one of these has changed:

- the device;
- the inode (`secret rotate` renames a new file into place);
- the mode;
- the size;
- the modification or change time, to the sub-second.

A read during which the file changed is not kept, and the next check reads
it again. Each Hypnotoad worker reads on its own and logs its own line.

### 4. What the service will not use, and never "none"

A changed file is not used, and the tokens it accepted before stay, when:

- it cannot be read, or it is gone;
- a line is not `NAME=value` (the front door's parser, read strictly);
- an account other than its owner may write it (`mode & 022`, the rule the
  FreeBSD rc scripts apply); a token chosen by another account would open
  `/metrics`;
- it names no `GPFORUM_METRICS_TOKEN`, or an empty one.

Each refusal is logged once, as a warning that names the file and the
reason and never a token. The file's signature is kept, so further checks
are silent until it changes again. The list never becomes "no token":
`/metrics` cannot open by accident. A successful re-read is logged at
`info`, with the number of tokens accepted.

"The tokens it accepted before" are the latest list each process accepted,
never the start-time list once a newer one was accepted. A worker Hypnotoad
forks while the file cannot be used starts from the list the manager
accepted last, and keeps it. The manager's loop turns at least once a
second, since it waits a second at most for the workers' heartbeats. One
case is left: a change that is followed, within that same second, by a
file nobody can use, with a worker forked in between. That worker keeps the
list from before the change until the file can be used again.

### 5. The session secret is not read again

`GPFORUM_SESSION_SECRET` and `GPFORUM_SESSION_SECRETS` sign and verify
cookies. They are Mojolicious's `secrets`, which every worker sets at
start. Changing them in a running service would split the workers, some
signing with the new secret and some refusing it. `gpforum secret rotate
session` keeps its restart.

### 6. What `secret rotate metrics` prints

On a host whose service files are in place, when the file is the host's
own:

```text
$ sudo gpforum secret rotate metrics
✓ A new metrics token is in /etc/gpforum/gpforum.env. The one before stays in GPFORUM_METRICS_TOKENS, and the running service accepts both now, with no restart.
Next: give every scraper the new GPFORUM_METRICS_TOKEN from /etc/gpforum/gpforum.env, then gpforum secret rotate metrics --finish
$ sudo gpforum secret rotate metrics --finish
✓ The previous metrics tokens are gone from /etc/gpforum/gpforum.env, and the running service refuses them now, with no restart.
```

In Italian:

```text
✓ Un nuovo token delle metriche è in /etc/gpforum/gpforum.env. Quello precedente resta in GPFORUM_METRICS_TOKENS, e il servizio in esecuzione li accetta già entrambi, senza riavvio.
Prossimo passo: dai a ogni scraper il nuovo GPFORUM_METRICS_TOKEN da /etc/gpforum/gpforum.env, poi gpforum secret rotate metrics --finish
✓ I token delle metriche precedenti non sono più in /etc/gpforum/gpforum.env, e il servizio in esecuzione li rifiuta già, senza riavvio.
```

A file an account other than its owner may write is one the service
refuses (section 4), so its rotation does not say "with no restart": it
says, with the `chmod 0640` that closes the file, that the service does not
read it again, and names the restart. `gpforum doctor` lists such a file
under `!`, with the same fix. All three judge the mode by one rule,
`MetricsTokens->others_may_write` (amended 2026-10-11; walkthrough 4,
friction 2, found a `0660` file promised a re-read the service refused).

A file named with `--env-file` that is not the host's own keeps the
restart line, because the service is not known to follow it until its
units export `GPFORUM_ENV_FILE`. A host without service files keeps its
`service print` or `start --foreground` step. A session rotation is
unchanged.

## Consequences

- A metrics rotation is three commands, named one after another, with no
  restart. The token before stops working at the first check after
  `--finish`.
- Every token check costs one `stat` system call. Load-balancer probes of
  `/health/ready` pay it too.
- A service whose file is not the host's own, started without
  `GPFORUM_ENV_FILE`, keeps the tokens it started with, as before.
- `gpforum status` (ADR 0120's front door) reads the token from the file.
  Once the service follows the file, the two agree after a rotation with no
  restart.
- Someone who edits the file in place, in pieces, can make a scraper
  refused for the moment of the write. The read is never torn into "no
  token": a token cut short is refused, and nothing is opened.

## Verification

- `t/600-metrics-token-reload.t`:
  - `/metrics` and `/health/ready` through the application, across a
    rotation and its `--finish` with no restart;
  - one read for an unchanged file;
  - every refusal of section 4, logged once;
  - a file holding other tokens is not followed;
  - `GPFORUM_ENV_FILE` before the loaded file;
  - the session secret unchanged;
  - scrapes during 30 rotations, never refused and never opened;
  - a file written in place, in halves, never opening `/metrics`.

  Against the access code before this change, the rotation subtests fail.
- `t/660-metrics-tokens-new-workers.t`: a worker forked from a
  `Mojo::Server::Prefork` manager after `--finish` and a malformed line, once
  the manager has turned its loop (and once it has also found the file
  unusable), refuses the dropped token and accepts the new one; a running
  Prefork manager replacing its worker does the same. All three fail
  without the manager's read. Run once against a live Hypnotoad, 14
  workers, on a free port: after `TERM` to every worker, the 14 new ones
  answered the dropped token 401 and the current one 200.
- `t/680-metrics-tokens-hot-deploy.t`: the manager's environment carries
  the list it accepted, empty earlier tokens included; a service built from
  it follows the file, refuses the token `--finish` dropped and takes a
  later rotation with no restart; built while the file cannot be used, it
  still refuses that token; a worker leaves its environment alone. The
  first three fail without the change. Run once against a live Hypnotoad,
  4 workers, on a free port, with a scraper polling every token: after
  `USR2`, the new manager's workers answered the dropped token 401 and the
  current one 200, and followed the next rotation and its `--finish`.
- `t/601-secret-rotate-metrics-no-restart.t`: the three steps in English
  and Italian with no restart command, and the restart kept for a session
  secret and for a file that is not the host's own; a `0660` and a `0620`
  file name the chmod and the restart, in both languages, and doctor lists
  them under `!`.
