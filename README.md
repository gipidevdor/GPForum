<p align="center">
  <img src="assets/img/gpforum-hero.png" alt="A dim room with a lit world map on the wall and server racks beyond a doorway" width="100%">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/img/gpforum-logo-dark.svg">
    <img src="assets/img/gpforum-logo.svg" alt="Good Phorum" width="128">
  </picture>
</p>

<h1 align="center">Good Phorum</h1>

<h3 align="center">A self-hosted Perl forum, powered by Mojolicious, Mojo::Pg and PostgreSQL.</h3>

<p align="center">
  <a href="https://github.com/gipidevdor/GPForum/actions/workflows/ci.yml"><img src="https://github.com/gipidevdor/GPForum/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="cpanfile"><img src="https://img.shields.io/badge/Perl-5.40%2B-373630?style=flat-square" alt="Perl 5.40 or newer"></a>
  <a href="docs/DEPLOYMENT.md"><img src="https://img.shields.io/badge/PostgreSQL-16%E2%80%9318-214237?style=flat-square" alt="PostgreSQL 16–18"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-BSD--3--Clause-9B6D32?style=flat-square" alt="BSD-3-Clause license"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#production">Production</a> ·
  <a href="ARCHITECTURE.md">Architecture</a> ·
  <a href="docs/README.md">Documentation</a> ·
  <a href="ROADMAP.md">Roadmap</a>
</p>

<p align="center"><img src="assets/img/gpforum-divider.svg" alt="" width="320"></p>

Good Phorum is a self-hosted forum for conversations that last. It runs as
one Mojolicious application behind nginx or Caddy, with PostgreSQL for storage
and search.

Pages render on the server; read routes also answer in JSON. Application reads
and writes call versioned PostgreSQL functions through **Mojo::Pg**. Local
processes reach PostgreSQL over [Unix sockets](docs/DEPLOYMENT.md#unix-socket-mode).

**GP** means **Good Phorum**; the **P** stands for **Perl**.
[About the name](docs/BRANDING.md).

## What it does

| Area | Features |
| --- | --- |
| **Conversation** | Threads, replies and revisions; reply to and quote a post; likes and reactions; polls; drafts with autosave and live preview. |
| **Discovery** | Full-text search by title or post, tags, similar threads while composing, bookmarks in folders, follows of threads and categories. |
| **Members** | Verified accounts, [passkeys](docs/passkeys-registration.md), TOTP, invitations and staff approval, direct messages, avatars, ignore lists, digests and one-click unsubscribe, data export and erasure. |
| **Moderation** | Queues, first-post review, automod and watched words, IP bans, timed suspensions, reversible actions, a hash-chained audit trail. |
| **Files** | Images, PDFs and text up to 25 MiB, scanned by ClamAV before delivery. |
| **Interfaces** | English and Italian; light, dark and high-contrast themes; keyboard-first semantic HTML. |
| **Protocols** | Atom feeds, mbox export, Ed25519-signed revisions, mail-in replies, WebSub, a Gemini mirror ([guide](docs/ops/community-protocols.md)). |
| **Integrations** | YouTube, Vimeo, GitHub, GitLab, Codeberg, Facebook, Instagram, Spotify, Apple Music, Wikipedia and Mathematics; optional allowlisted Mastodon/PeerTube; selected-topic Discord announcements, moderated feeds and opt-in OIDC; players load on click ([guide](docs/integrations.md)). |
| **Operation** | One command, `gpforum`, for setup, checks, backups and upgrades; an admin console for forum and plugin settings. |

## Requirements

You need **Perl 5.40 or newer**, App::cpm and Carton, and PostgreSQL 16, 17 or 18.
Distribution Perl, Homebrew, perlbrew, plenv, asdf and custom builds are supported.
Select an executable with `GPFORUM_PERL=/absolute/path/to/perl`, or activate
it on `PATH`; `make perl-runtime` reports the selection. Dependencies in
`local/` are tied to that runtime's ABI and CPU architecture, independently
of its installation prefix. See [Perl runtime selection](docs/ops/perl-runtime.md).

<details>
<summary>Host packages</summary>

Debian 13 or Ubuntu 26.04:

```sh
sudo apt install perl build-essential cpanminus libpq-dev libssl-dev zlib1g-dev postgresql postgresql-client
sudo cpanm -M https://cpan.metacpan.org/ App::cpm Carton
```

FreeBSD (client only):

```sh
sudo pkg install perl5 p5-App-cpanminus postgresql16-client
sudo cpanm -M https://cpan.metacpan.org/ App::cpm Carton
```

macOS with Homebrew:

```sh
brew install perl cpanminus postgresql@18 pgvector
brew services start postgresql@18
export PATH="$(brew --prefix postgresql@18)/bin:$PATH"
"$(brew --prefix)/bin/perl" "$(brew --prefix cpanminus)/bin/cpanm" -M https://cpan.metacpan.org/ App::cpm Carton
```

</details>

## Quick start

From a clone:

```sh
make install-deps-postgres                         # cpm installs from cpanfile.snapshot into local/
sudo bin/gpforum setup --environment development   # macOS: without sudo
gpforum admin create --email you@example.com --username you
gpforum start --foreground                         # http://127.0.0.1:3000
```

`setup` puts `gpforum` on your `PATH` and asks three questions — address,
database, mail — where Enter takes the suggestion. It writes
`/etc/gpforum/gpforum.env` (under `$(brew --prefix)/etc` on macOS) with
generated secrets, creates the database and brings the schema up to date;
running it again changes nothing. In development mail goes to the terminal;
this prints the verification link a new member receives:

```sh
bin/gpforum outbox --once
```

`gpforum` alone lists its commands. `gpforum doctor` checks the whole setup,
one line each, and says how to fix what is wrong ([guide](docs/ops/doctor.md)).
For development, `make check` runs the quality gates and `make fresh-checkout`
verifies a clean clone; `script/benchmark-http` and `script/profile-nytprof`
measure.

## Production

From a bare Debian 13 or Ubuntu 26.04 host to a signed-in owner behind TLS:

```sh
sudo apt install git perl build-essential cpanminus libpq-dev libssl-dev zlib1g-dev \
  postgresql nginx certbot python3-certbot-nginx clamav-daemon clamav-freshclam
sudo cpanm -M https://cpan.metacpan.org/ App::cpm Carton

sudo git clone https://github.com/gipidevdor/GPForum.git /opt/gpforum
sudo /opt/gpforum/bin/gpforum setup
sudo gpforum service print --to /etc/systemd/system
sudo systemctl daemon-reload && sudo systemctl enable --now gpforum gpforum-outbox gpforum-scheduled-jobs.timer gpforum-partition-maintenance.timer
sudo certbot certonly --nginx -d forum.example.org
sudo gpforum service print nginx --to /etc/nginx/sites-enabled
sudo nginx -t && sudo systemctl reload nginx
sudo -u gpforum gpforum admin create --email EMAIL --username NAME
```

Each command ends by naming the next. The prefork manager listens on a Unix socket that
the printed nginx and Caddy files already use, and PostgreSQL is reached over
its socket with peer authentication. Mail leaves through the host's
`sendmail` unless you answer `smtp HOST:PORT USER`; ClamAV needs
`StreamMaxLength 251M`. [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) explains every
step, plus FreeBSD and macOS; [deploy/gpforum.env.example](deploy/gpforum.env.example)
lists every setting.

<p align="center"><img src="assets/img/gpforum-divider.svg" alt="" width="320"></p>

## How it is built

- **Native EV.** Persistent Mojolicious workers use `Mojo::Reactor::EV`: epoll on Linux, kqueue on macOS and FreeBSD. Startup verifies the [actual backend](docs/ops/reactor-backend.md).
- **PostgreSQL function API.** Mojo::Pg calls the typed, versioned `api.*_vN` catalogue. A [restricted runtime login](docs/ops/sql-api-role.md) can enforce that boundary. DBIx::Class remains a maintainer dependency for historical fixtures and comparisons ([ADR 0174](docs/adr/0174-mojo-pg-is-the-runtime-stored-function-transport.md)).
- **Templates compiled before fork.** Startup waits for asynchronous warmup to finish. Workers inherit compiled EP templates and partials; [HTTP benchmarks verify each serving worker](benchmarks/README.md#complete-http-workload).
- **Transactional events.** A write commits its rows, domain event and audit record together. Outbox workers deliver events with safe retries.
- **PostgreSQL search.** Full-text search and `pg_trgm`, optional [pgvector semantic search](docs/ops/hybrid-search.md), and keyset pagination.
- **Rebuildable caches.** Process-local caching, with optional GlifiStore sharing. PostgreSQL remains authoritative.
- **Explicit security boundaries.** Argon2id, server sessions, CSRF protection and authorization across pages, search, feeds, files and realtime. The verification target is [OWASP ASVS 5.0](docs/adr/0149-owasp-asvs-5-is-the-security-bar.md) L2, with L3 for accounts and moderation.
- **Reproducible measurements.** [Performance evidence](docs/architecture/sql-functions-performance.md) includes workloads, raw results and commands.

[Architecture](ARCHITECTURE.md) explains the boundaries;
[decision records](docs/adr/README.md) explain the choices.

## Status

**In development.** Local setup and evaluation are available. A release requires
passing quality gates and evidence from the target deployment.

| Target | Remaining qualification |
| --- | --- |
| Private beta | Staging TLS, mail delivery and representative load |
| Public production | Beta qualification, an attachment restore drill and a rehearsed rollback |

There is no tagged release or independent security review yet.
Use the [release criteria](ROADMAP.md#release-readiness) and dated
[readiness review](docs/release/readiness-review.md) to assess a deployment.
Focused checks and historical benchmarks apply to the revisions they tested.

## Contributing

See [CONTRIBUTORS.md](CONTRIBUTORS.md) for individual credits.
Read [CONTRIBUTING.md](CONTRIBUTING.md) and run `make check` before a pull
request; `make integration` runs the PostgreSQL suite on temporary clusters.
Report vulnerabilities privately through [SECURITY.md](SECURITY.md).

[Changelog](CHANGELOG.md) · [Support](SUPPORT.md) · [Governance](GOVERNANCE.md) · [Code of conduct](CODE_OF_CONDUCT.md)

<p align="center"><img src="assets/img/gpforum-divider.svg" alt="" width="320"></p>

<p align="center">
  <img src="assets/img/gpforum-mark.svg" alt="" width="28"><br>
  <sub>Two open arcs and one amber node, after the hero's warm network lights.
  <a href="assets/source/README.md">Artwork</a> · <a href="LICENSE">BSD-3-Clause</a></sub>
</p>
