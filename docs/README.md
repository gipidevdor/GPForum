# Good Phorum documentation

Choose a task. Each guide gives the procedure, checks and next step.

| I want to… | Start here |
| --- | --- |
| Try the forum | [Quick start](../README.md#quick-start) |
| Deploy it | [Deployment](DEPLOYMENT.md) |
| Check or repair an installation | [Doctor](ops/doctor.md) |
| Back up or upgrade | [Backups](ops/backup-and-restore.md) · [Upgrades](ops/upgrade.md) |
| Change the code | [Contributing](../CONTRIBUTING.md) · [Architecture](../ARCHITECTURE.md) |
| Improve the documentation | [Writing guide](WRITING.md) |
| Measure performance | [Performance guide](PERFORMANCE.md) · [Benchmarks](../benchmarks/README.md) |
| Assess release readiness | [Criteria](../ROADMAP.md#release-readiness) · [Dated review](release/readiness-review.md) |

Guides describe the current system. [ADRs](adr/README.md) record decisions;
[quality reviews](QUALITY_PROGRAM.md) and [operator evidence](ops/evidence)
record what was verified on a given date. Historical references may name retired
migrations: use the [current migration map](../migrations/README.md) for the
installed schema.

Use **Good Phorum** or **GP Forum** in prose; preserve technical identifiers.
See [naming](BRANDING.md), [governance](../GOVERNANCE.md) and
[contribution rules](../CONTRIBUTING.md) when changing the documentation.

## Understand the system

| Document | What it covers |
| --- | --- |
| [BRANDING.md](BRANDING.md) | Good Phorum, the P for Perl, the GP Forum short form and naming conventions |
| [ARCHITECTURE.md](../ARCHITECTURE.md) | The SSR-first modular monolith and its boundaries |
| [adr/0174-mojo-pg-is-the-runtime-stored-function-transport.md](adr/0174-mojo-pg-is-the-runtime-stored-function-transport.md) | Mojo::Pg transport, transaction ownership, notifications and maintainer fixtures |
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
| [PRODUCT_BACKLOG.md](PRODUCT_BACKLOG.md) | Implemented features and proposed priorities, with acceptance criteria |
| [API.md](../API.md) | API posture: JSON responses today, versioning rules for later |
| [passkeys-registration.md](passkeys-registration.md) | Passkey registration, login, revocation and account lifecycle |

## Deploy and operate

| Document | What it covers |
| --- | --- |
| [DEPLOYMENT.md](DEPLOYMENT.md) · [DEPLOYMENT_EVIDENCE.md](DEPLOYMENT_EVIDENCE.md) | Running Good Phorum behind a reverse proxy, and the evidence gate |
| [OBSERVABILITY.md](OBSERVABILITY.md) | Health, logs, and metrics |
| [POSTGRESQL_RELIABILITY.md](POSTGRESQL_RELIABILITY.md) | PostgreSQL 16–18 audit, feature matrix, implementation decisions and verification |
| [Migrations](../migrations/README.md) | Current baseline and migration rules |
| [ops/postgres-diagnostics.md](ops/postgres-diagnostics.md) | Optional SQL cost statistics and read-only lock, vacuum, freeze, WAL and checkpoint diagnostics |
| [ops/reactor-backend.md](ops/reactor-backend.md) | Declared versus actual event-loop reactor |
| [ops/scheduled-jobs.md](ops/scheduled-jobs.md) | Hourly retention/orphan cleanup command |
| [ops/dead-letters.md](ops/dead-letters.md) | Inspect, keep, or purge exhausted outbox messages |
| [ops/search-rebuild.md](ops/search-rebuild.md) | Rebuild the search index; tell a lagging indexer from a stalled one |
| [ops/partition-maintenance.md](ops/partition-maintenance.md) | Rolling monthly log partitions: the daily timer, migrate's window step, conflicts |
| [ops/sql-api-role.md](ops/sql-api-role.md) | Separate migration credentials and a runtime login restricted to the function API |
| [ops/reload-and-restart.md](ops/reload-and-restart.md) | Restart services or resize the worker pool |
| [ops/unix-daemons.md](ops/unix-daemons.md) | Service lifecycle, signal handling, file permissions and native supervisor acceptance checks |
| [ops/backup-and-restore.md](ops/backup-and-restore.md) | Create, verify and restore backups; point-in-time recovery |
| [ops/doctor.md](ops/doctor.md) | Check an installation and act on each result |
| [ops/upgrade.md](ops/upgrade.md) | The upgrade in three commands, ending with `gpforum doctor --upgrade` |
| [ops/mail-check.md](ops/mail-check.md) | Identity mail transport dry-run / SMTP probe |
| [ops/console-and-cli.md](ops/console-and-cli.md) | Choose between the command line and admin console |
| [ops/staging-drills.md](ops/staging-drills.md) | Throwaway migrate / dump / attachments / deploy checklist |
| [ops/staging-host.md](ops/staging-host.md) | Bring up and verify staging behind TLS |
| [ops/stress-load.md](ops/stress-load.md) | Concurrent HTTP stress profiles against a base URL |
| [ops/private-beta-checklist.md](ops/private-beta-checklist.md) | Print the private-beta readiness checklist |
| [ops/evidence/](ops/evidence) | Dated local and staging evidence |
| [ops/evidence-validate.md](ops/evidence-validate.md) | Validate operator-captured evidence JSON before archiving it |
| [release/readiness-review.md](release/readiness-review.md) | Latest go / no-go review |

## Performance

| Document | What it covers |
| --- | --- |
| [PERFORMANCE.md](PERFORMANCE.md) | Query budgets, caching, profiling, tuning and reproducible evidence |
| [architecture/sql-functions-performance.md](architecture/sql-functions-performance.md) | Stored-function architecture and historical DBIx comparison; current transport uses Mojo::Pg |
| [architecture/migration-baseline-2026-11.md](architecture/migration-baseline-2026-11.md) | Current fresh-database baseline, schema equivalence and validation |
| [architecture/migration-baseline-1.0.md](architecture/migration-baseline-1.0.md) | Historical comparison of the earlier 1.0 baseline with the 0.x chain |
| [OS_RUNTIME_ENFORCEMENT.md](OS_RUNTIME_ENFORCEMENT.md) · [OS_RUNTIME_EVIDENCE.md](OS_RUNTIME_EVIDENCE.md) | Runtime enforcement of the OS contract, and its evidence |

## Security and correctness

| Document | What it covers |
| --- | --- |
| [THREAT_MODEL.md](THREAT_MODEL.md) | Assets, actors, trust boundaries, and the mitigation and test at each |
| [security/asvs-5.0.md](security/asvs-5.0.md) | OWASP ASVS 5.0.0 requirements, evidence and remaining gaps |
| [ENGINEERING_CORRECTNESS.md](ENGINEERING_CORRECTNESS.md) | Engineering correctness freeze |
| [audit/](audit) | Audits of transactional correctness, failure modes, and the email lifecycle |
| [CPAN_LICENSE_REVIEW.md](CPAN_LICENSE_REVIEW.md) | Dependency license gate |

## Interface

| Document | What it covers |
| --- | --- |
| [UI_SYSTEM.md](UI_SYSTEM.md) · [ui/design-system.md](ui/design-system.md) | SSR design system built from Mojolicious partials |
| [UI_ACCESSIBILITY.md](UI_ACCESSIBILITY.md) · [ui/accessibility.md](ui/accessibility.md) | WCAG 2.2 AA guidelines |
| [ui/functional-coverage.md](ui/functional-coverage.md) | Interface entry points, feature manifest and PostgreSQL coverage gate |
| [THEMING.md](../THEMING.md) | Themes and design tokens |
