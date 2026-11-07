# Roadmap

The implemented system is documented in the [guide index](docs/README.md).
[ADR 0068](docs/adr/0068-mvp-roadmap-sequencing.md) defines MVP sequencing;
[ADR 0091](docs/adr/0091-executable-architecture-contract.md) defines architecture
and event-catalog discipline.

## Where things stand

The implementation covers **Milestones 0–10** in
[ADR 0068](docs/adr/0068-mvp-roadmap-sequencing.md), from the Forum HTTP MVP to
advanced community features. Earlier “Milestone 17” references name the same
HTTP MVP, outside that numbering.

Implemented features and release qualification are separate:

| Target | Qualification |
| --- | --- |
| Local evaluation | Available; run the quality gates for the revision being evaluated |
| Private beta | Requires representative staging TLS, target installation, SMTP `--send`, host verification and stress profiles `100`/`500`/`1000` |
| Public production | Requires all beta evidence, TLS stress profiles `100`/`500`/`1000`, a live attachment restore drill and a rehearsed rollback |

The [dated readiness review](docs/release/readiness-review.md) records verified
evidence and remaining work. A passing local harness does not qualify a target host.

## Shipped

- **Identity and community:** accounts, server sessions, password and email
  lifecycle, forum reads and writes, moderation, administration and audit review.
  See the [feature inventory](docs/PRODUCT_BACKLOG.md) and
  [mail lifecycle audit](docs/audit/email-lifecycle.md).
- **Durable events:** transactional outbox, Minion handlers, retries and dead
  letters. PostgreSQL `LISTEN`/`NOTIFY` supplies process-local websocket fanout
  ([realtime guide](docs/realtime.md)).
- **PostgreSQL data access:** versioned stored functions through Mojo::Pg,
  permission-aware native search, rate limits and rebuildable projections.
  The [migration map](migrations/README.md) starts at baseline 2000–2025.
- **Concurrency and recovery tests:** row locks and command idempotency for
  moderation; two-connection race, retry and outbox-reclaim tests. The
  [failure-mode audit](docs/audit/failure-modes.md) records their evidence.
- **Portable Perl selection:** distribution, Homebrew, perlbrew, plenv, asdf and
  custom builds through `GPFORUM_PERL` or `PATH`. The
  [runtime guide](docs/ops/perl-runtime.md) covers services and upgrades;
  `script/gpforum-homebrew-env` supplies macOS PostgreSQL tool paths.
- **Operator tools:** [database and attachment drills](docs/ops/staging-drills.md),
  [host verification](docs/ops/staging-host.md),
  [stress profiles](docs/ops/stress-load.md) and the print-only
  [private-beta checklist](docs/ops/private-beta-checklist.md).
  These tools prepare evidence; representative target-host runs remain required.

## Next

[Integration plugins](docs/integrations.md) include Vimeo, GitLab and Codeberg,
plus allowlisted Mastodon and PeerTube. Selected-topic Discord announcements,
moderated RSS/Atom imports and explicitly linked OIDC login have separate
core-controlled network services. Reddit, X, TikTok and LinkedIn remain on demand;
live provider metadata and incoming webhooks remain future capabilities.

The [verified product backlog](docs/PRODUCT_BACKLOG.md) reconciles proposed
engagement, identity, messaging, discovery and integration features with the
current code. Its P0–P2 waves are a proposed post-MVP product sequence, not
additional completed milestones or a replacement for ADR 0068. Existing
readiness gates below remain prerequisites; feature adoption follows the
project's ADR and review rules.

- Run `staging-host-verify` with `--unit-dir`, `--systemd`, and an
  `https://` `--base-url` (TLS observe phase), and `stress-load` profiles
  `100`, `500` and `1000`, on a representative **staging TLS** host.
- Live target attachment restore and nginx/systemd **installation/restart** evidence
  (harness shipped; target install still open).
- Walk
  [docs/ops/private-beta-checklist.md](docs/ops/private-beta-checklist.md)
  on staging and close remaining blockers in
  [docs/release/readiness-review.md](docs/release/readiness-review.md)
  (SMTP `--send`, staging deploy, operator runbooks). Do not treat private
  beta as ready until that evidence exists.

## Release readiness

A public release requires:

- stable migrations and rollback discipline: a migration is never undone, a
  broken one is fixed forward ([docs/ops/upgrade.md](docs/ops/upgrade.md));
- CI green on every pull request, with no gate that holds only on a
  maintainer's machine;
- coverage and profiling artifacts for hot paths;
- security policy and private reporting path;
- documented support boundaries;
- ADR coverage for major deviations;
- on a staging host that runs the production PostgreSQL major: the
  migrations applied to an empty and to a restored database, a backup
  restored ([docs/ops/backup-and-restore.md](docs/ops/backup-and-restore.md)),
  outbox retries and dead letters observed, query-plan evidence green on a
  representative dataset, and a rollback rehearsed with the shipped systemd
  and nginx files;
- `/metrics` unreachable from outside the host, with its token set.
