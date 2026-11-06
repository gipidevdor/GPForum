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

<h3 align="center">A discussion forum, written in Perl, kept in PostgreSQL.</h3>

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

**GP** means **Good Phorum**, also shortened to **GP Forum**. The **P** in
**Phorum** stands for **Perl**. It is a general-purpose forum: a place to share
interests, ask questions and keep conversations going.
[About the name](docs/BRANDING.md).

Pages are rendered on the server, and read routes answer in JSON when asked.
PostgreSQL holds every canonical row; search, feeds and caches derive from it.
Perl reaches PostgreSQL on the same host over **Unix-domain sockets**: web
processes, workers, realtime listeners and command-line tools use the local
database connection. See the [socket configuration](docs/DEPLOYMENT.md#unix-socket-mode).
One Mojolicious prefork process group behind nginx or Caddy runs the whole forum — no
Redis, no OpenSearch, no Kubernetes.

## What it does

|  |  |
| --- | --- |
| **Conversation** | Threads, replies and revisions; reply to and quote a post; likes and reactions; polls; drafts with autosave and live preview. |
| **Finding** | Full-text search by title or post, tags, similar threads while composing, bookmarks in folders, follows of threads and categories. |
| **Members** | Verified accounts, [passkeys](docs/passkeys-registration.md), TOTP, invitations and staff approval, direct messages, avatars, ignore lists, digests and one-click unsubscribe, data export and erasure. |
| **Moderation** | Queues, first-post review, automod and watched words, IP bans, suspensions with timed end, reversible actions, a hash-chained audit trail. |
| **Files** | Images, PDFs and text up to 25 MiB, scanned by ClamAV before delivery. |
| **Interfaces** | English and Italian; light, dark and high-contrast themes; keyboard-first semantic HTML. |
| **Protocols** | Atom feeds, mbox export, Ed25519-signed revisions, mail-in replies, WebSub, a Gemini mirror ([guide](docs/ops/community-protocols.md)). |
| **Integrations** | YouTube, Vimeo, GitHub, GitLab, Codeberg, Facebook, Instagram, Spotify, Apple Music, Wikipedia and Mathematics; optional allowlisted Mastodon/PeerTube; selected-topic Discord announcements, moderated feeds and opt-in OIDC; players load on click ([guide](docs/integrations.md)). |
| **Operation** | One command, `gpforum`, to set up, run, check, back up and upgrade; an admin console with graphical plugin and forum settings. |

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

- **Mojolicious on persistent Perl processes.** Controllers speak HTTP; services own the rules.
- **SQL lives in PostgreSQL.** Every statement is a versioned `api.*` function installed by migrations, and a separate login can be held to that API alone ([ADR 0126](docs/adr/0126-sql-lives-in-postgresql-functions.md), [role guide](docs/ops/sql-api-role.md)).
- **One transaction per write.** Rows, domain event and audit record commit together; an outbox carries events to workers that retry safely.
- **Search without extra servers.** PostgreSQL full-text and `pg_trgm`, with optional [local semantic search through pgvector](docs/ops/hybrid-search.md); keyset pagination, never offsets.
- **Caches are disposable.** A process-local cache, optionally GlifiStore shared between hosts; when it is gone, pages come from PostgreSQL.
- **Secure by default.** Argon2id, server sessions, CSRF tokens, authorization on pages, search, feeds, files and realtime; targeting [OWASP ASVS 5.0](docs/adr/0149-owasp-asvs-5-is-the-security-bar.md) L2, L3 for accounts and moderation.
- **Measured, then tuned.** [Performance results](docs/architecture/sql-functions-performance.md) carry raw numbers and the commands that reproduce them.

[ARCHITECTURE.md](ARCHITECTURE.md) describes the design and the
[decision records](docs/adr/README.md) explain each choice.

## Status

| Target | |
| --- | --- |
| Local and personal use | **Ready** |
| Private beta | Not yet — needs staging evidence for TLS, mail delivery and load |
| Public production | Not yet — plus an attachment restore drill and a rehearsed rollback |

There is no tagged release and no independent security review yet.
[Release criteria](ROADMAP.md#release-readiness) · [Current review](docs/release/readiness-review.md)

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
