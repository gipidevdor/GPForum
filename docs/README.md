# GPForum documentation

Start with the [project README](../README.md) for the overview. The documents
below go deeper, grouped by what you are trying to do.

Implementation guides describe the running system; ADRs record design decisions
and their consequences. Use [GOVERNANCE.md](../GOVERNANCE.md) and
[CONTRIBUTING.md](../CONTRIBUTING.md) when changing either.

[QUALITY_PROGRAM.md](QUALITY_PROGRAM.md) is the current audit verdict and the
work plan derived from it: where every engineering dimension stands today, what
is provably broken, and the order in which it is being fixed. Read it before
starting work on any of the areas below.

## Understand the system

| Document | What it covers |
| --- | --- |
| [ARCHITECTURE.md](../ARCHITECTURE.md) | The SSR-first modular monolith and its boundaries |
| [architecture/](architecture) | Bootstrap, presentation, web access, per-area workflow boundaries, operational profiles and partition lifecycle |
| [architecture/composer-drafts.md](architecture/composer-drafts.md) | Private thread/reply drafts, native Save/Preview, progressive autosave, publication and retention contracts |
| [EVENTS.md](../EVENTS.md) | Event envelope and delivery contracts |
| [OUTBOX_LIFECYCLE.md](OUTBOX_LIFECYCLE.md) | Transactional outbox, retries, and dead letters |
| [realtime.md](realtime.md) | Realtime as an enhancement boundary |
| [VIEW_MODELS.md](VIEW_MODELS.md) | SSR view models between controllers and templates |
| [i18n.md](i18n.md) | Locale negotiation and translation boundaries |
| [adr/](adr) | Architecture decision records |

The [ADR index](adr/README.md) lists every decision. For the broader design,
start with [foundational architecture](adr/0049-foundational-architecture.md),
[workflow contracts](adr/0091-executable-architecture-contract.md) and
[engineering invariants](adr/0093-verifiable-engineering-invariants.md).
The [layer map](../ARCHITECTURE.md#layer-map) describes the current module layout.

## Use the product

| Document | What it covers |
| --- | --- |
| [MVP.md](MVP.md) | Every route that is traversable today |
| [PRODUCT_FLOWS.md](PRODUCT_FLOWS.md) | Product workflows present in the repository |
| [PRODUCT_BACKLOG.md](PRODUCT_BACKLOG.md) | Verified feature inventory and proposed post-MVP priorities, with acceptance criteria and licensing/privacy constraints |
| [API.md](../API.md) | API posture: JSON responses today, versioning rules for later |

## Deploy and operate

| Document | What it covers |
| --- | --- |
| [DEPLOYMENT.md](DEPLOYMENT.md) · [DEPLOYMENT_EVIDENCE.md](DEPLOYMENT_EVIDENCE.md) | Running GPForum behind a reverse proxy, and the evidence gate |
| [OBSERVABILITY.md](OBSERVABILITY.md) | Health, logs, and metrics |
| [POSTGRESQL_RELIABILITY.md](POSTGRESQL_RELIABILITY.md) | PostgreSQL 16–18 audit, feature matrix, implementation decisions and verification |
| [Migration history](../migrations/README.md) | Ordered schema, function API and evolution phases; immutable SQL and authoring rules |
| [ops/postgres-diagnostics.md](ops/postgres-diagnostics.md) | Optional SQL cost statistics and read-only lock, vacuum, freeze, WAL and checkpoint diagnostics |
| [ops/reactor-backend.md](ops/reactor-backend.md) | Declared versus actual event-loop reactor |
| [ops/scheduled-jobs.md](ops/scheduled-jobs.md) | Hourly retention/orphan cleanup command |
| [ops/dead-letters.md](ops/dead-letters.md) | Inspect, keep, or purge exhausted outbox messages |
| [ops/search-rebuild.md](ops/search-rebuild.md) | Rebuild the search index; tell a lagging indexer from a stalled one |
| [ops/partition-maintenance.md](ops/partition-maintenance.md) | Rolling monthly log partitions: the daily timer, migrate's window step, conflicts |
| [ops/sql-api-role.md](ops/sql-api-role.md) | Separate migration credentials and a runtime login restricted to the function API |
| [ops/reload-and-restart.md](ops/reload-and-restart.md) | Why reload is unsupported, and how to restart or resize workers |
| [ops/backup-and-restore.md](ops/backup-and-restore.md) | The nightly backup (`gpforum backup`), its check (`gpforum restore --check`), restoring one, and point-in-time recovery |
| [ops/doctor.md](ops/doctor.md) | `gpforum doctor` and `gpforum status`: every check, one line each, with its fix |
| [ops/upgrade.md](ops/upgrade.md) | The upgrade in three commands, ending with `gpforum doctor --upgrade` |
| [ops/mail-check.md](ops/mail-check.md) | Identity mail transport dry-run / SMTP probe |
| [ops/console-and-cli.md](ops/console-and-cli.md) | Every `bin/` command against the admin console route that covers it, or why none does |
| [ops/staging-drills.md](ops/staging-drills.md) | Throwaway migrate / dump / attachments / deploy checklist |
| [ops/staging-host.md](ops/staging-host.md) | Live staging Hypnotoad+TLS bring-up and verify |
| [ops/stress-load.md](ops/stress-load.md) | Concurrent HTTP stress profiles against a base URL |
| [ops/private-beta-checklist.md](ops/private-beta-checklist.md) | Operator private-beta go/no-go aggregate (print-only) |
| [ops/evidence/](ops/evidence) | Archived operator evidence blobs (laptop vs staging; never a beta claim) |
| [ops/evidence-validate.md](ops/evidence-validate.md) | Validate operator-captured evidence JSON before archiving it |
| [release/readiness-review.md](release/readiness-review.md) | Latest go / no-go review |

## Performance

| Document | What it covers |
| --- | --- |
| [PERFORMANCE.md](PERFORMANCE.md) | Principles and budgets; indexes, the plan gate, keyset pages and migrations; query budgets; caching; search costs; profiling; OS tuning; the evidence and how to reproduce it |
| [architecture/sql-functions-performance.md](architecture/sql-functions-performance.md) | Completed stored-function conversion and the measured DBIx comparison |
| [OS_RUNTIME_ENFORCEMENT.md](OS_RUNTIME_ENFORCEMENT.md) · [OS_RUNTIME_EVIDENCE.md](OS_RUNTIME_EVIDENCE.md) | Runtime enforcement of the OS contract, and its evidence |

## Security and correctness

| Document | What it covers |
| --- | --- |
| [THREAT_MODEL.md](THREAT_MODEL.md) | Assets, actors, trust boundaries, and the mitigation and test at each |
| [security/asvs-5.0.md](security/asvs-5.0.md) | OWASP ASVS 5.0.0 verification record (ADR 0149): every requirement in scope, its state and evidence, and the prioritised gaps |
| [ENGINEERING_CORRECTNESS.md](ENGINEERING_CORRECTNESS.md) | Engineering correctness freeze |
| [audit/](audit) | Audits of transactional correctness, failure modes, and the email lifecycle |
| [CPAN_LICENSE_REVIEW.md](CPAN_LICENSE_REVIEW.md) | Dependency license gate |

## Interface

| Document | What it covers |
| --- | --- |
| [UI_SYSTEM.md](UI_SYSTEM.md) · [ui/design-system.md](ui/design-system.md) | SSR design system built from Mojolicious partials |
| [UI_ACCESSIBILITY.md](UI_ACCESSIBILITY.md) · [ui/accessibility.md](ui/accessibility.md) | WCAG 2.2 AA guidelines |
| [THEMING.md](../THEMING.md) | Themes and design tokens |
