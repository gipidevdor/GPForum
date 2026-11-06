# Good Phorum Deployment

Deploy the Mojolicious prefork service behind nginx or Caddy, with PostgreSQL
and the outbox worker on the same host. Start with the procedure for your OS;
use the later sections for configuration and verification.

Install the pgvector package matching the PostgreSQL server major before
setup or migrations. Setup installs the extension administratively. For a
manually provisioned database or local inference, follow the
[hybrid search runbook](ops/hybrid-search.md). GlifiStore is an optional,
disposable shared cache.

## Production Shape

Recommended baseline:

```text
nginx or Caddy
-> Mojolicious prefork manager
-> PostgreSQL
-> gpforum outbox (required worker)
-> optional Minion workers
```

The proxy handles TLS, compression, static files, attachment transfer, buffering
and network limits. Good Phorum handles identity, authorization, forum workflows,
transactional events, page rendering and JSON responses.

## Install on Debian or Ubuntu

From a bare Debian 13 or Ubuntu 26.04 host to a forum behind TLS. Every
command runs as a user who may use `sudo`. Set your forum's address once; the
commands below use it:

```sh
site=forum.example.com
```

1. **Packages and CPAN tools.** PostgreSQL, nginx with certbot, ClamAV for the
   upload scan, and App::cpm (v1.1 or newer) plus Carton for the system Perl.

   ```sh
   sudo apt install git perl build-essential cpanminus libpq-dev libssl-dev zlib1g-dev \
     postgresql postgresql-client nginx certbot python3-certbot-nginx \
     clamav-daemon clamav-freshclam
   sudo cpanm -M https://cpan.metacpan.org/ App::cpm Carton
   ```

2. **The code.** The code belongs to root, so the service cannot rewrite it.

   ```sh
   sudo git clone https://github.com/gipidevdor/GPForum.git /opt/gpforum
   ```

3. **Setup.** Install production dependencies and link `gpforum` into
   `/usr/local/bin`. Answer three questions: public address, database and mail
   transport (step 5). Enter accepts each suggestion; the database default
   creates `gpforum` on this host.

   ```sh
   sudo /opt/gpforum/bin/gpforum setup
   ```

   <details>
   <summary>Example setup report (values vary by release)</summary>

   ```text
   gpforum setup installs the dependencies into /opt/gpforum/local first, as make install-deps-production does: cpm install ... --workers 5 --no-test --final-install all --top-level-phase configure,build,test,runtime --feature postgres
   ...
   ✓ dependencies: installed into /opt/gpforum/local, for Perl 5.40.1
   GPForum setup. Three questions; Enter accepts the suggestion.
   Public address [https://forum.example.org]:
   Database [create 'gpforum' on this host]:
   Mail (sendmail, smtp HOST:PORT USER, or log) [sendmail]:
   ✓ account gpforum: made, with /opt/gpforum/var/attachments for its uploads
   ✓ /etc/gpforum/gpforum.env: written, 0640 root:gpforum, with a new session secret and metrics token
   ✓ gpforum: linked into /usr/local/bin, so it runs from any directory
   ✓ database gpforum at /var/run/postgresql/.s.PGSQL.5432: made, with its role gpforum
   ✓ Applied NN migrations, 1000 to NNNN; synced the query budgets (NN changed)

   Next: make the forum's owner, with sudo -u gpforum gpforum admin create --email EMAIL --username NAME
   Then: install and start the services, with sudo gpforum service print systemd --to /etc/systemd/system
   Then: check the whole forum, with sudo -u gpforum gpforum doctor
   ```

   </details>

   It makes the service's account, `gpforum`, and the directory its uploads
   go in. It writes `/etc/gpforum/gpforum.env`, readable by root and the
   `gpforum` group only, with a new session secret, metrics token and
   database password, and prints none of them. It makes the database role
   and the database as PostgreSQL's superuser, the `postgres` account, and
   brings the schema up to date as `gpforum migrate` does: the tables, the
   monthly partitions and the query budgets `/health/ready` compares the
   plans with (`gpforum budgets --sync` syncs those alone; without them
   readiness answers 503). Run again, it changes nothing and says so; a
   setting the file has is replaced only when you say so.

   The normal deployment keeps PostgreSQL on this host and uses its Unix
   socket, as shown in [Unix socket mode](#unix-socket-mode). Only when
   deliberately choosing a database on another host, answer its data source
   (`dbi:Pg:dbname=gpforum;host=db.internal;port=5432`). Setup reaches its
   superuser as psql would -- `PGUSER` names it, `~/.pgpass` holds its
   password -- then with the user and password the data source, or
   `GPFORUM_DATABASE_USER` and `GPFORUM_DATABASE_PASSWORD`, give. When none
   answers, it says what PostgreSQL told each, offers the `PGUSER=...` run,
   and prints the `psql` commands that make what is missing, to run there
   before `sudo gpforum setup` again.
   `sudo gpforum setup --yes --public-url "https://$site" --database create
   --mail sendmail` answers for a script, and `--dry-run` shows what setup
   would do. The file holds what setup asked and made, each under one line
   saying what it is; every other setting keeps its default, and
   `deploy/gpforum.env.example` lists them all. There is no size to choose:
   `GPFORUM_ENV=production` runs as many web processes as the CPUs carry,
   each caching its part of the memory. A setting Good Phorum cannot use stops
   the start, and every command, with every problem at once, each with the
   variable to set and the file to set it in.

4. **Commands as the service runs them.** `gpforum` reads
   `/etc/gpforum/gpforum.env` itself, as the service does, so a command typed
   by hand sees the service's settings. Run it as the service's user, so it
   also has the service's permissions:

   ```sh
   sudo -u gpforum gpforum
   ```

   On its own it lists its commands, by what you are doing, and says which
   environment file it read. What the shell sets comes first:
   `GPFORUM_ENV=staging gpforum ...` overrides the file for one command, and
   `gpforum --env-file FILE ...` reads another file.

5. **Mail.** Verification and reset mail leaves as setup's mail answer
   says (`GPFORUM_MAIL_TRANSPORT`). The suggestion, `sendmail`, needs a
   mail server on the host: `sudo apt install postfix` and choose "Internet
   Site". Many VPS providers block port 25, and many mail servers refuse a
   host without SPF and reverse DNS; then relay through a provider instead:
   run `sudo gpforum setup` again and answer the mail question with `smtp
   HOST:PORT USER`, Enter for the other two. It asks for the password
   without echo. TLS follows `GPFORUM_SMTP_PORT`: STARTTLS on 587, implicit
   TLS on 465 (`GPFORUM_SMTP_TLS` says otherwise), through IO::Socket::SSL,
   which the dependencies install. Then send yourself a probe:

   ```sh
   sudo -u gpforum gpforum mail-check --send --to ADDRESS --human   # an address you read
   ```

6. **Antivirus.** Set the upload scan limits in `/etc/clamav/clamd.conf`, so
   clamd scans a file as large as the upload limit, and prove it detects the
   test file ([ops/antivirus.md](ops/antivirus.md) explains the report):

   ```sh
   printf 'StreamMaxLength 251M\nMaxFileSize 250M\nMaxScanSize 512M\nAlertExceedsMax yes\n' | sudo tee -a /etc/clamav/clamd.conf
   sudo systemctl restart clamav-daemon
   sudo -u gpforum gpforum antivirus-check
   ```

7. **The services.** The web application, the outbox worker that sends the
   mail, and the hourly and daily timers. `gpforum service print` writes
   the units of `deploy/systemd/` for this host -- the code directory, the
   environment file it read -- into the directory systemd reads them from:
   its own six names, and nothing else there is touched. Then start them,
   in one line:

   ```sh
   sudo gpforum service print --to /etc/systemd/system
   sudo systemctl daemon-reload && sudo systemctl enable --now gpforum gpforum-outbox gpforum-scheduled-jobs.timer gpforum-partition-maintenance.timer
   ```

   It ends with that same line. To read the units before they go in place,
   give `--to` a directory of your own; it then ends with the `cp`. The web
   unit checks the host first ([Preflight](#preflight)); if it does not
   start, `journalctl -u gpforum` says why.

8. **TLS and nginx.** Take a certificate, then put Good Phorum's site where
   Debian's nginx reads it. `gpforum service print nginx` writes it for the
   address in `GPFORUM_PUBLIC_BASE_URL` and the one the application listens
   on, with the upload limit and `/metrics` kept to this host, and refuses
   to put it in place before its certificate is there, since nginx would
   refuse the site:

   ```sh
   sudo certbot certonly --nginx -d "$site"
   sudo gpforum service print nginx --to /etc/nginx/sites-enabled
   sudo nginx -t && sudo systemctl reload nginx
   ```

   Debian's default site stays: it answers only the names no other site
   claims. Without nginx or certbot, the steps `service print nginx` and
   `gpforum doctor` print begin with the `apt install` that brings them.
   certbot's own timer renews the certificate.
   Once the forum is serving, `curl -sS "https://$site/health/ready"`
   answers `{"check":"ready","status":"ok"}` (or `degraded`, with a reason
   under the metrics token, see [Health endpoints](#health-endpoints)).

9. **The forum's owner.** Make your account, which can sign in at once:
   no mail and no database query are needed. It asks for the password
   twice.

   ```sh
   sudo -u gpforum gpforum admin create --email you@example.com --username you
   ```

   Sign in at `https://$site/login`. To make another member an owner later:
   `sudo -u gpforum gpforum admin grant their@example.com`.

Then check it all: `sudo -u gpforum gpforum doctor` goes from the settings
to the public address, one line each, with the command for anything to
fix. Under the settings it says what the host sized the forum for, such as
`sized for 2 CPUs, 2 GB: 4 web processes, 4096 cache entries a process`.
`sudo -u gpforum gpforum status` shows the running service's readiness
report ([ops/doctor.md](ops/doctor.md)).

Upgrading later is three commands, which `sudo -u gpforum gpforum upgrade`
prints for this host. The last one, `sudo -u gpforum gpforum doctor
--upgrade`, says what the upgrade left behind
([ops/upgrade.md](ops/upgrade.md)).

### The front door

Every command is a verb of `gpforum`, the one entrypoint in `bin/`. It
reads the service's environment file and the checkout's dependencies by
itself, so no shell sources the file first and nothing runs
`script/gpforum-carton exec`. `gpforum help --all` lists every verb, and
[ops/console-and-cli.md](ops/console-and-cli.md) gives each one's console
counterpart, or why there is none.

### Rotating a secret

`gpforum secret rotate session` writes a new `GPFORUM_SESSION_SECRET` into
the environment file and keeps the one before in `GPFORUM_SESSION_SECRETS`,
which still accepts the cookies it signed, so nobody is signed out. Restart
the service, and after 30 days, when every session has been renewed, drop
the old one:

```sh
sudo gpforum secret rotate session
sudo systemctl restart gpforum gpforum-outbox
sudo gpforum secret rotate session --finish     # 30 days later
sudo systemctl restart gpforum gpforum-outbox
```

`gpforum secret rotate metrics` does the same for `GPFORUM_METRICS_TOKEN`,
with no restart, because the running service reads the tokens from the file
again (ADR 0124). Give every scraper the new token from the file, then run
`--finish`:

```sh
sudo gpforum secret rotate metrics
sudo gpforum secret rotate metrics --finish     # once every scraper sends the new one
```

Both commands keep the file's owner and mode, print no secret, and say each
next step. `--dry-run` says what would change.

## Values production refuses

| Setting | Refused | Why |
| --- | --- | --- |
| `GPFORUM_PUBLIC_BASE_URL`, `GPFORUM_MAIL_FROM` | an address under `example.com`, `.net`, `.org`, `.example` or `.invalid`, in staging and production | The template's placeholders, left as copied, put a link nobody can follow in every mail, from a sender no server delivers for. |
| `GPFORUM_MAIL_TRANSPORT` | `test`, in production | It keeps mail in memory and sends none. |
| `GPFORUM_FORUM_READ_RATE_LIMIT` | anything but a whole number of at least 1 | It is now a setting like the others, and on the settings page; any other value used to be ignored without a word. |

## Preflight

The service files check the host before every start, with `gpforum
os-preflight --strict --json`; run the same check by hand before the first
one:

```sh
gpforum os-preflight          # one line per finding
gpforum os-preflight --json   # the same report as one JSON document
```

A check that fails -- no CPU count, no event backend -- stops the start, and
the command exits 1. A degraded one -- one CPU, a file descriptor limit below
65536, more web processes than the CPUs carry under
`GPFORUM_RUNTIME_WORKER_POLICY=configured` -- is reported and does not stop
it. Under the default `cap-to-cpu` policy the check counts the web processes
the manager is given, not the ones configured, so a 1-vCPU host starts.

`--strict`, which the systemd units and the FreeBSD rc script pass, also
writes each check that is not ok to stderr, one line each, so `journalctl -u
gpforum` shows it without the JSON around it:

```text
os-preflight: degraded recommended_worker_count: recommended worker count below configured threshold
```

### Upgrade note: the units run `bin/gpforum`

The service files run `bin/gpforum` alone, which finds the Perl and the
dependencies the checkout installed: `gpforum os-preflight --strict --json`
before the start, `gpforum start --service --foreground` for the prefork manager under
systemd, launchd and daemon(8), and `gpforum outbox`, `gpforum
scheduled-jobs` and `gpforum partitions` for the others. `script/` is the
maintainers' (owner decision D9). A unit copied before that ran
`script/os-preflight` and a `bin/gpforum-*` command through
`script/gpforum-carton exec`, and both are gone: `gpforum doctor` fails
such a unit and gives the `gpforum service print` that writes it again and
the restart that reads it.

## Identity mail delivery

Probe the transport before relying on verification, reset and email-change
mail: `gpforum mail-check --dry-run --human` checks it without sending
(`smtp`: a TCP connect, the password never printed; `sendmail`: the binary is
there), and `gpforum mail-check --send --to ADDRESS --human` delivers a
real verification probe to an address you read.
[ops/mail-check.md](ops/mail-check.md) explains each transport.

To sign in the forum before delivery, set `GPFORUM_DKIM_DOMAIN` to the From
domain, `GPFORUM_DKIM_SELECTOR` to the published selector and
`GPFORUM_DKIM_KEY_FILE` to a regular, readable private key with mode `0600`.
Publish its public key at `SELECTOR._domainkey.DOMAIN`. `gpforum doctor`
signs a probe and verifies it against DNS without sending it. A signing
failure makes the outbox retry. Leave the key path empty to keep MTA signing.

## Upload antivirus

Staging and production scan every upload with the operating system's ClamAV
and serve no new upload until it is clean (ADR 0108); attachments uploaded
before stay served until the hourly backfill has scanned them. Install the
system package (`apt install clamav-daemon clamav-freshclam`, `pkg install
clamav`, `brew install clamav`), set `StreamMaxLength 251M` in `clamd.conf`,
and prove it detects the EICAR test file with `gpforum antivirus-check`. To
run without an antivirus, set `GPFORUM_ANTIVIRUS=none` explicitly.
[ops/antivirus.md](ops/antivirus.md) has each system's steps and the socket
permissions.

## Connection admission

Hypnotoad recycles worker processes automatically after a randomized share of
10,000 accepted connections. `GPFORUM_RUNTIME_REQUESTS` instead limits requests
on each keep-alive connection; it does not recycle a worker.

At up to 250 configured clients per worker, listeners accept one connection per
event-loop turn. Larger client budgets admit small groups, capped at 16 per
turn, through the native Mojolicious listener API. This keeps bursts moving
without letting one worker drain the entire listen queue. Native connection
limits and graceful shutdown still govern every resume. Explicit
`single_accept` listener settings take precedence; TLS listeners retain native
single-accept handshake behavior.

## Deployment Evidence

Run the Hypnotoad evidence gate before treating a deployment profile as
measured:

```sh
bin/gpforum hypnotoad-benchmark --check --profile small --workers 2 \
  --iterations 20 --warmup 3 \
  --route /categories \
  --route /t/018f1004-0001-7000-8000-000000000001 \
  --route /search?q=performance \
  --route /health/ready \
  --route /metrics
```

The benchmark starts an isolated temporary Hypnotoad runtime, records worker
metadata, compares against in-process evidence when enabled, observes DB query
counts through benchmark-only headers, and stops the server gracefully. See
`docs/DEPLOYMENT_EVIDENCE.md` for current local values and methodology.

## Perl dependencies

Good Phorum runs on **Perl 5.40 or newer**, independently of the host's Perl
package. Distribution packages, Homebrew, perlbrew, plenv, asdf, custom
prefixes are supported.
`GPFORUM_PERL` explicitly selects an executable path or command; otherwise
the active Perl on `PATH` is tried first, followed by common install paths.
An invalid explicit selection fails rather than choosing another runtime.
The historical script and `make system-perl` remain compatibility entry points.

```sh
export GPFORUM_PERL=/opt/perl/bin/perl  # or activate a supported Perl on PATH
make perl-runtime
script/gpforum-system-perl --require
```

`local/` records the Perl version, architecture and ABI options used to
build its native dependencies. A mismatch requires
`script/bootstrap-deps --postgres --rebuild-local`, which preserves the old
tree. Equivalent interpreters at different prefixes remain compatible.
See [Perl runtime selection](ops/perl-runtime.md) for perlbrew,
supervisor environments and interpreter upgrades.

Host packages (before cpm):

- Debian/Ubuntu: `perl`, `build-essential`, `cpanminus`, `libpq-dev`,
  `libssl-dev`, `zlib1g-dev`, `postgresql-client`
- FreeBSD: `perl5`, `p5-App-cpanminus`, `gtar`, and a PostgreSQL client matching
  the server major. A self-contained PostgreSQL 18 host also needs
  `postgresql18-server`, `postgresql18-contrib` (`pg_trgm`, `unaccent`) and
  `postgresql18-pgvector` before migrations.
- macOS (Homebrew): `brew install perl cpanminus postgresql@18`. Homebrew
  installs a versioned PostgreSQL keg-only, so put its client tools on
  `PATH` with:

  ```sh
  eval "$(script/gpforum-homebrew-env)"
  script/gpforum-homebrew-env --check
  ```

  That prepends `$(brew --prefix)/opt/postgresql@NN/bin` so `pg_config`,
  `psql`, `pg_dump`, and `pg_restore` resolve from Homebrew. The helper
  no-ops on Linux CI. After `brew upgrade perl`, rebuild `local/`
  (`script/bootstrap-deps --postgres --rebuild-local`): its XS modules are
  built for one Perl.
- Then: `cpanm -M https://cpan.metacpan.org/ App::cpm Carton` for the selected Perl

IO::Socket::SSL, for mail over TLS, builds Net::SSLeay against the host's
OpenSSL headers: `libssl-dev` on Debian and Ubuntu (`libpq-dev` does not
bring them), FreeBSD's base, and on macOS Homebrew's `openssl@3`, which
`postgresql@18` installs and `script/bootstrap-deps` finds (or set
`OPENSSL_PREFIX`).

Good Phorum recognizes runtime modules from `cpanfile`, PostgreSQL modules from
`cpanfile.postgres` (feature `postgres`), and exact distribution pins
from `cpanfile.snapshot`. Install through cpm under the selected Perl:

```sh
make install-deps-production
# equivalent: script/bootstrap-deps --postgres --production
```

That runs App::cpm (v1.1 or newer) through `script/gpforum-cpm`, with five
parallel workers, into `local/`. It reads the committed `cpanfile.snapshot`
using `--resolver snapshot --no-default-resolvers`: a missing or incompatible
pin fails instead of falling back to current CPAN releases. The lock is not
rewritten. Runtime and test requirements and the postgres feature are selected;
the develop tools (Perl::Critic, Perl::Tidy, Devel::Cover, Devel::NYTProf and
their dependencies) are omitted, per ADR 0109. Development and CI keep them
with `make install-deps-postgres`.

Set `GPFORUM_CPM_WORKERS=2 make install-deps-production` to limit concurrent
builds on a host with little memory. The default is five; the value must be a
positive integer. `PERL_CARTON_MIRROR=https://cpan.metacpan.org/` remains the
mirror setting; another HTTPS mirror or a local path is accepted.
`--home local` keeps source archives in `local/cache`, where Carton bundling
expects them. `--final-install all` retains build dependencies as
before. `--cached` uses only the `vendor/cache` mirror produced by
`script/gpforum-carton bundle`.
Upstream module tests remain disabled (`--no-test`), matching the previous
Carton install policy.

App::cpm and Carton are host tools for the selected Perl. Carton supplies
`Carton::Snapshot` to cpm and still handles `--update`, `check` and `bundle`.
`GPFORUM_CPM=/path/to/cpm` locates a cpm executable outside the PATH; the
wrapper still runs it with the validated selected Perl.
`script/bootstrap-deps --postgres --update` refreshes the lock on a development
host; production cannot combine `--production` with `--update`. Running
Good Phorum needs neither installer: the front door and service units put `local/`
on `@INC` under the Perl that installed it.

Reproduce an install:

1. Use the same Perl ABI and architecture that produced `local/` (do not delete
   `local/` to paper over a mismatch after a distro Perl upgrade).
2. Keep `cpanfile`, `cpanfile.postgres`, and `cpanfile.snapshot` from the
   same git commit.
3. Run `script/bootstrap-deps --postgres --production` then
   `script/gpforum-carton check`.
4. Optional air-gap: `carton bundle` on a trusted host, copy `vendor/cache`,
   then `script/bootstrap-deps --postgres --production --cached`.

## Linux With systemd

The units in `deploy/systemd/` are what the [install](#install-on-debian-or-ubuntu)
copies, as `gpforum service print systemd` writes them for the host:
`gpforum.service`, `gpforum-outbox.service`, the
outbox worker without which no mail leaves, and the two timers below. They
run as `gpforum` from the code directory (`/opt/gpforum` in the templates),
read the environment file (`/etc/gpforum/gpforum.env`), and stop
gracefully with `systemctl stop`. Restart after changing the environment
file; `systemctl reload` is refused on purpose
([ops/reload-and-restart.md](ops/reload-and-restart.md)).

The web unit uses `Type=notify` and supervises the foreground manager directly.
`systemctl start` waits for a healthy worker to answer `/health/ready`.
The manager then probes `/health/live` every ten seconds and sends watchdog
notifications; systemd restarts it if notifications stop for 30 seconds.
Graceful stop sends `TERM` to the manager and allows 150 seconds to drain.
Watchdog abort handling has a separate 15-second deadline before forced cleanup.
See [ADR 0155](adr/0155-host-readiness-mail-and-reproducible-data.md), including
the Linux validation requirement.

The systemd units create `/run/gpforum` with `RuntimeDirectory=gpforum`, and
The manager keeps its internal PID file there. systemd does not read that file.
The units set only `GPFORUM_ENV=production` and the log path; every other
setting takes its default unless
`/etc/gpforum/gpforum.env` sets it, so an override belongs in that file, not
in a copy of the unit.

Hourly operational sweeps are a timer, not a daemon
(`gpforum-scheduled-jobs.timer`, which the install starts with the rest).
The oneshot unit runs `gpforum scheduled-jobs --once --limit 100` through
`bin/gpforum`. It deletes stale sessions, rate-limit buckets,
identity tokens, completed outbox rows, and dead letters in bounded
batches, then calls attachment orphan cleanup and partition
policy/evidence. It does not loop and does not execute partition DDL.
See `docs/ops/scheduled-jobs.md`.

The monthly partitions of `audit_log`, `event_log` and `notifications` are
kept ahead by a daily timer of their own (ADR 0113),
`gpforum-partition-maintenance.timer`, also started by the install. It runs
`gpforum partitions --apply`, which creates the current month and the two
after it where they are missing. The parent tables stay open to writes;
reads that open the DEFAULT partition, and the event and audit writes that
start with one, wait for each attach, half a second at most plus the scan
of DEFAULT. Enable it on every node: the runs take an advisory lock, and
the ones that do not get it do nothing. It needs the role
that owns those tables -- the one the migrations run as; if the application's
role is not the owner, give the unit an `EnvironmentFile` with the migration
role's DSN. `gpforum migrate` does the same after every deploy's
migrations. See `docs/ops/partition-maintenance.md`.

## FreeBSD With rc.d

Example:

```text
deploy/freebsd/gpforum
deploy/freebsd/gpforum_outbox
deploy/freebsd/gpforum_jobs
deploy/nginx/gpforum.conf
```

Recommended operator actions:

- install under `/usr/local/www/gpforum`;
- run as a dedicated `gpforum` user: `sudo gpforum setup` makes it with
  `pw useradd`, writes the environment file below and makes the database,
  as on Debian;
- put the service's environment -- `GPFORUM_DATABASE_DSN`,
  `GPFORUM_SESSION_SECRET` and the rest of `GPFORUM_*`, as on Linux -- in
  `/usr/local/etc/gpforum/gpforum.env` (`gpforum_env_file` in rc.conf to move
  it), owned by `root:gpforum` with mode `0640`. The rc script exports it into
  the service and refuses to start if the file is readable by others or
  writable by its group: rc.conf variables are never exported, so this file
  is the only way the configuration reaches the application. Its
  `GPFORUM_ENV` is the mode; rc.conf's `gpforum_env` is the mode of a file
  that names none;
- put both rc scripts in `/usr/local/etc/rc.d/` and the jobs' crontab in
  `/usr/local/etc/cron.d/`, and enable both services:
  `sudo gpforum service print rc --to ~/gpforum-rc` writes the three for
  this checkout and environment file, and ends with the copies and
  `sysrc gpforum_enable=YES`, `sysrc gpforum_outbox_enable=YES` and the
  starts. `gpforum_outbox` is the outbox worker, which sends the mail; it
  reads the same environment file, and both create `/var/log/gpforum` for
  the `gpforum` user;
- `service gpforum stop` sends TERM to daemon(8), disabling restart and
  forwarding TERM to the foreground manager to drain requests; rc waits
  for the supervisor tracked through `/var/run/gpforum/daemon.pid`;
  the manager defaults to `/var/run/gpforum/app/gpforum.pid`, in a private
  directory owned by its service account;
- tune file descriptor limits through login class or service wrapper;
- use nginx, Caddy, or another local reverse proxy for TLS/static transfer;
- consider jails for process isolation;
- the crontab (`deploy/freebsd/gpforum_jobs`) runs `gpforum scheduled-jobs
  --once` hourly and `gpforum partitions --apply` daily as `gpforum`, the
  systemd timers' counterparts, through `bin/gpforum`, which reads the
  environment file.

## macOS With launchd

`gpforum service print launchd` writes these for the host -- the code
directory in place of `/opt/gpforum`, the logs under Homebrew's prefix:

```text
deploy/launchd/com.gpforum.app.plist
deploy/launchd/com.gpforum.outbox.plist
deploy/launchd/com.gpforum.scheduled-jobs.plist
deploy/launchd/com.gpforum.partition-maintenance.plist
```

`com.gpforum.outbox` keeps the outbox worker running, which sends the mail.
`com.gpforum.scheduled-jobs` is a 3600s interval sample for the same oneshot
command. It is not KeepAlive. `com.gpforum.partition-maintenance` runs
`gpforum partitions --apply` every 86400s, as the systemd timer does daily.

Each plist runs as the `gpforum` account, not as root, and through
`bin/gpforum`, which reads `$(brew --prefix)/etc/gpforum/gpforum.env` too.
launchd has no environment file, so each job reads it before it starts and
takes its mode from the file's `GPFORUM_ENV` -- `production` when it names
none, as under systemd -- and the plists set only the log and, for the web
service, the pid file. Clone the code where the `gpforum` account can read
it, such as `/opt/gpforum`, not under a home directory, which macOS keeps
closed to other accounts.

From a Mac with Homebrew to a signed-in owner behind TLS, this section is
the one document. First the packages -- PostgreSQL, nginx with certbot --
and App::cpm plus Carton for Homebrew's Perl:

```sh
brew install perl cpanminus postgresql@18 nginx certbot
brew services start postgresql@18
"$(brew --prefix)/bin/perl" "$(brew --prefix cpanminus)/bin/cpanm" -M https://cpan.metacpan.org/ App::cpm Carton
```

Then eight commands, with your forum's name for `forum.example.org`:

```sh
sudo git clone https://github.com/gipidevdor/GPForum.git /opt/gpforum
sudo /opt/gpforum/bin/gpforum setup
sudo gpforum service print --to /Library/LaunchDaemons
sudo launchctl bootstrap system /Library/LaunchDaemons/com.gpforum.*.plist
sudo certbot certonly --standalone -d forum.example.org --pre-hook 'brew services stop nginx' --post-hook 'brew services start nginx'
sudo gpforum service print nginx --to "$(brew --prefix)/etc/nginx/servers"
sudo nginx -t && sudo brew services restart nginx
sudo -u gpforum gpforum admin create --email EMAIL --username NAME
```

`/opt/gpforum/bin/gpforum setup` does what it does on Debian, the account
included: it installs the dependencies, links `gpforum` into Homebrew's
`bin`, makes the group and the account `gpforum` with `dscl`, under the
highest id below 500 that no user and no group has, and `var/`, where
the manager keeps its PID file and the uploads go, under the checkout. It
writes the environment file (`$(brew --prefix)/etc/gpforum/gpforum.env`,
0640 root:gpforum), makes the database as your own PostgreSQL role, which
Homebrew's trusts, and brings the schema up to date. `service print --to
/Library/LaunchDaemons` puts the plists in place and, as root, makes the
directory they log to, `$(brew --prefix)/var/log/gpforum`, the `gpforum`
account's, 0750; then they are loaded at once, and the site goes where
Homebrew's nginx reads it, after its certificate. Each command ends by
saying the next one for this host; nginx runs as root under `brew
services`, which reads the certificate certbot keeps root's, and certbot's
renewals stop and start it as the first one did.

The jobs are loaded too: a plist launchd has not loaded never runs. With
`gpforum --env-file FILE service print launchd`, each job hands that file to
`bin/gpforum` with `--env-file`, as the systemd units and the rc scripts
do, so the web service follows its metrics tokens with no restart.

macOS remains primarily a development and profiling platform. It is supported
for local persistent runs, but production throughput tuning should be measured
on the target FreeBSD or Linux deployment host.

## Reverse Proxy

Examples, which `gpforum service print nginx` and `gpforum service print
caddy` write for the host -- the forum's name from
`GPFORUM_PUBLIC_BASE_URL`, the address the application listens on, the
code directory and the attachment store -- and end with where this
operating system's nginx or Caddy reads them:

```text
deploy/nginx/gpforum.conf
deploy/caddy/Caddyfile
```

The proxy should preserve:

- `Host`
- `X-Forwarded-For`
- `X-Forwarded-Proto`
- WebSocket upgrade headers for `/realtime`

Static `/assets/` files live in the repository `assets/` tree
(`/opt/gpforum/assets` after install). Do not point the proxy at
`public/assets`; that path does not exist.

At the site root, nginx and Caddy search `assets/css`, `assets/img` and
`assets/js`, in the same order as the application. Missing files go to the
application. nginx explicitly buffers request bodies before forwarding them
and buffers upstream responses, isolating the application from slow client
transfers within the proxy's buffer and timeout limits.

The nginx site enables sendfile and gzip for static text assets. Its upstream
pool reuses normal HTTP connections: `Connection` is cleared for those
requests and set to `upgrade` only for an upgrade request. WebSocket
connections still use their explicit handshake. Application response
compression remains handled by GPForum. After updating the site, run
`nginx -t` before reloading nginx.

Web processes are sized automatically by default. Compare worker counts on
the target host before overriding `GPFORUM_WEB_PROCESSES`, and reassess the
PostgreSQL connection/memory budget across every web and background node.
Worker recycling is automatic from the first start and needs no environment
setting. Each web process is gracefully replaced after at most 10,000
accepted connections; The prefork manager randomizes the threshold to stagger
replacements. This is built-in application policy.
`GPFORUM_RUNTIME_REQUESTS=1000` limits requests on one keep-alive connection.
Lowering that request limit does not recycle the process and increases
connection churn.

`GET /attachments/:attachment_id/download` is an application route. Nginx must
proxy that URL to the application. A `location /attachments/ { internal; }` prefix
intercepts the download and returns 404.

For the filesystem backend, nginx can send the file once the application has
authorized the download. Set `GPFORUM_ATTACHMENT_ACCEL_REDIRECT=/internal-attachments/` in the
environment file: the application then answers with an `X-Accel-Redirect`
header instead of the bytes, and nginx serves the file from its
`/internal-attachments/` alias. The shipped alias is
`/opt/gpforum/var/attachments/`, the default `GPFORUM_ATTACHMENT_ROOT`; if you
move the attachment store, change both. nginx reads the files as its own user,
and the store belongs to `gpforum` with mode `0750`: put nginx's user in the
`gpforum` group (`sudo usermod -aG gpforum www-data`, then `sudo systemctl
restart nginx`), or every download answers 403. Leave the setting empty
behind Caddy, which has no internal alias in the sample: a proxy that does not
understand the header would pass it to the browser.

The default PostgreSQL attachment backend returns an application asset rather
than a filesystem path. Downloads use native `Mojo::Pg` promises and retain at
most one 1 MiB database chunk per response. The next HTTP chunk is read only
after the preceding write completes; disconnects stop further reads. HEAD,
ETag and range requests keep their usual semantics. `X-Accel-Redirect` applies
to filesystem assets only.

HTTP dispatch prepares configuration, validates the server session and resolves
viewer state asynchronously. Controllers use Mojolicious async/await; native
readers cover category and thread listings, search, thread extras, permission
checks, rate limits and session reads. Other persistent service operations run
as complete workflows in the bounded subprocess executor. A synchronous
PostgreSQL checkout in the HTTP request context is rejected before it can
block the reactor. CLI service interfaces remain synchronous.

Native transactions own one leased connection through BEGIN, savepoints,
COMMIT and rollback. They never borrow another workflow's transaction or
replay an ambiguous commit. Query cancellation (SQLSTATE 57014) rejects even
when DBD::Pg reports a zero-row result. Prepared-plan retirement runs
asynchronously; DBI statement destruction does not send synchronous DEALLOCATE.
Connection handshakes use libpq asynchronous connect and reactor readiness
watchers with a five-second deadline. OS hostname resolution runs in the
bounded Mojolicious subprocess executor; numeric addresses are pinned while
retaining the configured hostname for TLS. A libpq service definition with a
hidden hostname uses an isolated connection probe before the owned connection.

Cache invalidation and realtime share one dedicated, idle LISTEN connection.
Cache reads drain local notification queues without checking a database handle
out or pinging it. Realtime authorization, current visibility, badge counts,
session revocation and backstop polling complete asynchronously; registries
and sockets stay in the web process. OIDC uses approved public HTTPS peers and
reactor-driven DNS. WebSub resolves its operator-configured hub outside the
reactor and retains its native user agent until forwarding completes.

Argon2id, account transactions, avatar processing, upload validation and scans,
archive generation, uncached Markdown and QR generation run in bounded
`Mojo::IOLoop::Subprocess` children. Password hashing costs and validation rules
are unchanged. The manager warms the cost-keyed decoy hash before forking, so
unknown-account checks verify it without generating a second hash per child.
Queued work from a disconnected request is skipped; active mutations finish.
Legacy filesystem downloads and archives stream at most 256 KiB at a time,
with the next read admitted only after the preceding write drains. Database
media retains its existing one-chunk bound. HEAD, ranges and conditional
responses keep their semantics.

Each worker admits two concurrent native SQL operations, one subprocess and
four outbound integration HTTP requests. Executor queues hold at most 256
additional operations for at most fifteen seconds. Saturation rejects work.
The database budget remains four connections per web worker: two native query
leases, one shared listener and one isolated workflow connection, plus the
existing operational headroom. Worker startup warms the two query leases
asynchronously after fork. No operator setting is required for this behavior.

`Mojo::File` itself is synchronous. Small metadata operations and Mojolicious's
request parsing, logging and template machinery retain their normal framework
semantics. Keep nginx or Caddy in front for static assets, upload buffering,
TLS and slow clients. GlifiStore is not required or enabled by this migration.

nginx accepts request bodies up to 251 MiB (`client_max_body_size`), enough for
audio or video at Good Phorum's 250 MiB limit and the form around it. Images
and documents retain 25 MiB; profile originals retain 5 MiB.
`/metrics` answers the loopback only, in the nginx configurations and the
Caddyfile alike: the scraper runs on the same host.

PostgreSQL-backed media is streamed by Good Phorum; the internal attachment
alias applies to the filesystem compatibility backend.

For static assets and filesystem attachments, prefer web-server file transfer with cache
headers and sendfile support. Good Phorum can authorize access, but Perl should not
be the ordinary large-file transfer path.

## Health endpoints

`/health/live` answers `status`, `check` and `time` to anyone and depends on
nothing: point process supervisors and liveness probes at it.

`/health/ready` answers 200 while the node can serve (`ok` or `degraded`)
and 503 when it cannot (`fail`). Load balancers and probes act on that code
alone. Without the metrics token the body is the overall status only,
`{"check":"ready","status":"degraded"}`; the full report -- every check, its
error, the replication slots and partitions it names, the runtime -- goes
only to a request carrying the same token `/metrics` takes, as
`Authorization: Bearer <token>` or `X-GPForum-Metrics-Token: <token>`, the
current `GPFORUM_METRICS_TOKEN` or one of `GPFORUM_METRICS_TOKENS` during a
rotation. On the host, `sudo -u gpforum gpforum status` asks for it with
the token from the environment file and writes it one line per check; a
scraper sends the header itself:

```sh
curl --unix-socket /opt/gpforum/var/run/gpforum.sock \
  -sS -H "X-GPForum-Metrics-Token: $GPFORUM_METRICS_TOKEN" \
  http://localhost/health/ready | jq '.checks[] | select(.status != "ok")'
```

A wrong or stale token gets the status alone, not a 401 as on `/metrics`:
the code must not change with the token, or a probe left with an old token
after a rotation would take every node out of service. `GET /health`, the
config/runtime/OS summary, answers `{"status":"ok"}` without the token and
the full summary with it. Development and test, where no token has to be
configured, serve the full reports to anyone, as they serve `/metrics`;
staging and production refuse to start without one. Both token-dependent
endpoints answer `Cache-Control: no-store`, so no shared cache replays a full
report to an anonymous client. Unlike `/metrics`, which the shipped nginx
configurations also restrict to `127.0.0.1`, the health endpoints stay
reachable from outside because load balancers need the code: the full reports
rest on the token alone, so keep it out of probe configurations that only need
the status.

## UNIX Socket Mode

Unix sockets are the default for both local PostgreSQL and proxy-to-application
connections. The default `GPFORUM_DATABASE_DSN=dbi:Pg:dbname=gpforum` uses
libpq's packaged socket directory when no libpq host environment override is
present. For an explicit local connection in `/etc/gpforum/gpforum.env`, use:

```sh
# Debian / Ubuntu
GPFORUM_DATABASE_DSN="dbi:Pg:dbname=gpforum;host=/var/run/postgresql"
# macOS / Homebrew or FreeBSD, when PostgreSQL uses its packaged default
# GPFORUM_DATABASE_DSN="dbi:Pg:dbname=gpforum;host=/tmp"
```

`host=` takes the **directory**, not the socket filename. A directory selects
Unix-domain communication; `host=localhost` or `host=127.0.0.1` selects TCP.
If a DSN also includes `port=5432`, that number selects `.s.PGSQL.5432` in
the directory; it does not turn a Unix socket connection into TCP. These are
[libpq connection parameters](https://www.postgresql.org/docs/18/libpq-connect.html#LIBPQ-PARAMKEYWORDS).
Keep `hostaddr` and `PGHOSTADDR` unset for this local configuration, and avoid
an inherited `PGHOST` when relying on the directory default.

Use the same socket directory for an explicit `GPFORUM_ADMIN_DATABASE_DSN`
and, when enabled, the separate `GPFORUM_MINION_PG_URL`. For example,
`postgresql://gpforum@%2Fvar%2Frun%2Fpostgresql/gpforum` selects the Debian
socket directory for Minion; its role still needs the corresponding local
authentication and job permissions. `gpforum doctor` prints the actual
`DIRECTORY/.s.PGSQL.PORT` endpoint and reports a deployed loopback TCP DSN.

A remote database takes an explicit TCP host as a separate topology. The
systemd units run with `PrivateTmp=true`; for a socket under
`/tmp` the printed units bind its directory in read-only, and for one in
`/tmp` itself they run without a private `/tmp` and say how to give the
server a directory of its own (`unix_socket_directories`); `gpforum doctor`
fails `database_socket` when an installed unit hides the socket (ADR 0137).
Over the socket a distribution authenticates by `peer`, which admits an
account only as the role of its name: the `gpforum` account as
`gpforum_runtime` (ADR 0127) and the operator as `gpforum` need a map.
`sudo gpforum setup` prints the `pg_hba.conf` and `pg_ident.conf` lines
this host needs, and `gpforum doctor` repeats them under a refusal; the
[runtime role guide](ops/sql-api-role.md#peer-authentication-on-the-socket)
explains them.
When root runs `setup`, database provisioning stays privileged; connection
checks, migrations and owner lookup use the service account. This matches
the identity PostgreSQL sees after the service starts, including peer auth.

The service's default is `http+unix://var%2Frun%2Fgpforum.sock`. The service
starts in the code directory and creates `var/run` with mode `0750` before
binding the socket. The socket, mode `0660`, is the `gpforum` group's to
connect to and closed to other users. The service itself runs under umask
`027`: the uploads it stores are `0640` and their directories `0750`, so the
proxy's account, which joins the group, reads them and cannot replace them.
nginx and Caddy configurations printed with
`gpforum service print` resolve the same path under the deployed code
directory, and say the command that adds the proxy's account (`www-data`,
`caddy` or `www`) to the group. `gpforum start --service` refuses a TCP
`GPFORUM_RUNTIME_LISTEN` and says what to set; the printed sites forward
to the socket whatever that setting says. There is one unit and one site: the `gpforum-unix-socket`
variants are gone, so a host that installed one installs `gpforum.service`
and `gpforum.conf` in its place (ADR 0137).

A connection on the socket carries no client address, so the service takes
the client from the last `X-Forwarded-For` entry: the one the proxy appends
(`$proxy_add_x_forwarded_for` in the nginx files, Caddy's default). A proxy
of your own must append it too, or every request is keyed by its connection
alone and the rate limits stop following a client. Entries before the last
are never read, so a client cannot choose its own address (ADR 0086).

The browser-facing development command `gpforum start --foreground` retains
its explicit HTTP listener on port 3000. Internal local connections use Unix
sockets; the public browser-to-proxy listener remains HTTP/HTTPS.

For an absolute socket path, the environment file can set:

```text
GPFORUM_RUNTIME_LISTEN=http+unix://%2Frun%2Fgpforum%2Fgpforum.sock
```

In a unit file each `%` must be written `%%`: systemd
reads `%2` as a specifier it does not know and drops the whole line, and the
service keeps its default listen address instead. Prefer the environment file,
which takes single `%` characters and does not duplicate the unit.

When using Unix sockets, `reuseport` is not applied. Add the proxy's worker
account to the `gpforum` group before starting it: on Debian, use
`sudo usermod -aG gpforum www-data` for nginx or
`sudo usermod -aG gpforum caddy` for Caddy, then restart the proxy. On FreeBSD,
use `sudo pw groupmod gpforum -m www` for nginx (or its configured worker
account). The code directory and every socket parent must allow that group
to traverse them. For a custom socket outside the code directory, provision
its parent with ownership `gpforum:gpforum` and mode `0750` before startup.

## Realtime

Every web process LISTENs on PostgreSQL and serves only its own websockets;
nodes need no sticky sessions and share no presence state. See
`docs/realtime.md`.

- Keep `GPFORUM_REALTIME_LISTENER_ENABLED=1` (the default) on every web
  process. Notification badges reach sockets only through NOTIFY and the
  listener, including those changed by the same process.
- The connection quota (8 per user) is counted per worker process. The
  cross-node limit is the PostgreSQL-backed `realtime.connect` rate limit
  (30 per minute per user).
- After a PostgreSQL restart or failover, each web process clears its L1
  cache once, on its next cache read, and re-sends notification badge counts
  to its sockets, one count query per connected user: expect a short rise in
  queries.
- A web process that cannot LISTEN (pointed at a standby, say) clears its L1
  on every cache read until it can, and `listen_failures` rises in
  `/metrics`.
- After a deploy or a worker recycle, the outbox backstop starts at the head
  of the outbox; nothing is replayed. It runs only in processes that have
  websocket connections.
- Keep every host's clock on NTP. The backstop waits five seconds for an
  outbox row to settle, and that window also absorbs the offset between a
  worker's clock, which stamps the row, and the database's.

## GlifiStore (optional)

A single host needs no GlifiStore: with `GPFORUM_GLIFISTORE_URL` empty, the
default, each process keeps its own cache in front of PostgreSQL and readiness
says so in a note. Set it to share one cache between hosts. PostgreSQL remains
the only source of truth. An unreachable GlifiStore degrades readiness to
process-local L1 and PostgreSQL; it does not become authoritative.

After a failed call (unreachable, timed out, overloaded) each process skips
GlifiStore for 15 seconds, then tries again; the pause is fixed, not
configured. While it runs:

- readiness reports `local-fallback` without connecting;
- pages come from L1 or are rendered from PostgreSQL;
- cache invalidations do not reach GlifiStore, so an entry that should have
  been invalidated stays in L2 until its TTL (`category_cache_ttl_seconds`).
  L1 never keeps an entry filled from L2 longer than L2 would.

`/metrics` shows the pause under `local_caches[0].l2`: `retry_after_epoch`
while it runs, and `stats.skipped` for the calls it skipped. `stats.failures`
counts real failures only; erasing a key that is not there is not one.

Invalidating a tag is one ERASE of that tag's token. Entries cached by a
release before tokens carry none, so each misses once after the upgrade.

`GlifiStore::Client` is **not** a Carton or `cpanfile` pin: it is not published
on PAUSE, and this repository does not vendor a GlifiStore server or Perl
client. `Service::Operations::SharedCache` loads the client at runtime:

```perl
require GlifiStore::Client;
GlifiStore::Client->connect(%endpoint);
```

The expected client surface is `connect`, `get`, `put`, `erase`, and `ping`
(`t/lib/GPForum/Test/SharedCacheClient.pm` is the in-tree stand-in). There is
no installable GlifiStore binary or CPAN distribution in this project.

To use one:

1. Run a GlifiStore server on a Unix socket and set `GPFORUM_GLIFISTORE_URL`
   to `unix://var/run/glifistore.sock` (or an absolute socket path).
2. Install `GlifiStore::Client` onto the same Perl that owns `local/` (private
   distribution or extra `PERL5LIB`).
3. Set `GPFORUM_GLIFISTORE_URL` in `/etc/gpforum/gpforum.env`.

Without the operator-supplied server and client, shared L2 cannot connect;
leave the URL empty instead.

## PostgreSQL Baseline

Select and verify an explicit sized PostgreSQL profile before production:
[`gpforum postgres-performance`](ops/postgres-performance.md) inspects effective
settings, exports a plan, applies individually authorized changes to an identified
controlled cluster, and verifies activation. Production and staging connections
warn on drift, readiness exposes findings, and opt-in
`GPFORUM_POSTGRES_STRICT=1` refuses nonconforming connections. Remote/managed
servers require declared server resources; shared hosts default to conservative
memory reserves. Server restarts remain an operator action.

Minimum recommended posture:

- application role is not PostgreSQL superuser;
- migrations use a separate role;
- `statement_timeout` defaults to 15s on app connect
  (`GPFORUM_DATABASE_STATEMENT_TIMEOUT_MS`; `gpforum migrate`
  clears it);
- `idle_in_transaction_session_timeout` defaults to 10s on app connect
  (`GPFORUM_DATABASE_IDLE_IN_TRANSACTION_TIMEOUT_MS`);
- `lock_timeout` defaults to 3s on app connect
  (`GPFORUM_DATABASE_LOCK_TIMEOUT_MS`);
- search and autocomplete set their own `statement_timeout` of 2s for the
  transaction they run in (`GPFORUM_SEARCH_STATEMENT_TIMEOUT_MS`; 0 leaves
  them under the 15s above) and rank only the newest 1000 matches
  (`GPFORUM_SEARCH_CANDIDATE_LIMIT`);
- each connection names its process in `application_name` (`gpforum-web`,
  `gpforum-outbox`, `gpforum-migrate`, ...) and gives up after
  `connect_timeout=5`, unless the DSN sets them (ADR 0137);
- backups and restore tests exist before production launch: `gpforum
  backup` nightly and `gpforum restore --check` on each
  ([ops/backup-and-restore.md](ops/backup-and-restore.md));
- with a streaming standby ([ops/standby-and-failover.md](ops/standby-and-failover.md)),
  the application role is granted `pg_read_all_stats`
  (`GRANT pg_read_all_stats TO gpforum;`): `/metrics` reports each standby's
  replay lag and bytes behind under `replication`, and without the grant
  PostgreSQL hides them (`standby_details_visible` is 0). Not `pg_monitor`:
  it adds `pg_read_all_settings`, which reads a standby's `primary_conninfo`,
  replication password included when one was given. `/health/ready` degrades
  its `replication_slots` check when an inactive replication slot keeps more
  than 1 GiB of WAL or a slot is lost: a standby that stopped following, whose
  slot keeps the primary's WAL until the disk fills. The runbook is
  [ops/standby-and-failover.md#watch-the-lag](ops/standby-and-failover.md#watch-the-lag).

For a repeatable local/staging migrate + `pg_dump`/`pg_restore` rehearsal on
throwaway databases, see `docs/ops/staging-drills.md`
(`bin/gpforum staging-drill`). For populated `var/attachments` filesystem
backup/restore plus static and host-available nginx/systemd checks, use
`bin/gpforum staging-drill-attachments`. Live service/TLS host bring-up is
documented in `docs/ops/staging-host.md` with non-destructive
`bin/gpforum staging-host-verify` (env-file key presence, systemd activity, HTTP
health). That verify does not install units or claim private-beta readiness.

## Tuning By OS

For read-only SQL cost, lock, vacuum/freeze, index and checkpoint diagnostics,
use [ops/postgres-diagnostics.md](ops/postgres-diagnostics.md) with a separate
operator connection. The extension is optional; absence and insufficient
visibility are explicit. Do not grant additional catalog access to the web
role merely for this command. The current PostgreSQL audit and decisions are
in [POSTGRESQL_RELIABILITY.md](POSTGRESQL_RELIABILITY.md).

Linux:

- use `epoll` through Mojolicious runtime selection;
- prefer systemd unit limits over application-side tuning;
- use nginx/Caddy for TLS, compression, static files, and sendfile;
- inspect sockets with `ss` and process limits with `/proc`.

FreeBSD:

- use `kqueue`;
- prefer rc.d and login class limits;
- consider jails for isolation;
- inspect runtime with `sockstat`, `systat`, `top`, and `netstat`.

macOS:

- use `kqueue`;
- keep runtime simple for development;
- do not treat macOS benchmark results as production throughput proof.

## Non-Goals

Good Phorum does not automatically:

- modify sysctl;
- require root;
- pin CPU affinity;
- install systemd/rc.d/launchd files;
- require Redis;
- require Kubernetes;
- replace PostgreSQL as authoritative storage.

## Optional Push sender

When `GPFORUM_PUSH_ENABLED=1`, `gpforum service print` also generates the
separate encrypted-notification sender for the selected service manager.
Its start, restart and doctor checks follow the configured service list.
Generate the persistent keys and configure the provider/contact prerequisites
before starting it; see [Web Push](ops/web-push.md). Stop the sender before
disabling an already deployed Push installation.
