# PostgreSQL engineering and reliability audit

Audit date: 2026-10-11. Starting revision: `3ebff4cd4181ad08821092980b2e1a38bdb6cf08`.
This review covers PostgreSQL 16–18 and the existing Perl application and
operator tooling. It introduces no new application domain, distributed
service, replication deployment, CDC, broker or required extension.

The review read `ARCHITECTURE.md`, `ROADMAP.md`, deployment/readiness,
performance/CI documentation, migrations 001–102, the 195-operation SQL
catalogue, forum/search/feed/moderation/notification/outbox services,
backup/restore/partition/retention tools and all database workflows.
Historical evidence remains unchanged. Existing evidence establishes the
items below; the current change's fresh validation is recorded separately.

While implementation was in progress, `main` merged the independent composer
draft feature in `2237bb6` (PR #65): migration 103 and five additional catalogue
operations, making 200. This change preserves that migration, its bounded
expiry policy, API-role boundary and versioned write/privacy/export calls.
Final validation covers the integrated revision; the matrix below records the
initial 195-operation audit baseline.

## Feature matrix

The four states are **already implemented and verified**, **implemented but
incomplete**, **absent and useful**, and **unnecessary or deferred**. They
correspond to the requested “Già implementato e verificato”, “Implementato
ma incompleto”, “Assente e utile” and “Non necessario o da rinviare”.

| Feature | Audit state before this change | Existing evidence or gap | Decision |
| --- | --- | --- | --- |
| Versioned SQL function API and prepared calls | Already implemented and verified | 195 catalogue operations; migrations 052–102; differential and catalogue integration tests | Preserve API and applied migrations |
| Runtime privileges and definer boundaries | Already implemented and verified | API-only login, separate ordinary owner, fixed `pg_catalog, pg_temp` path, `REVOKE PUBLIC`; real restricted-role and workflow tests | No new runtime grants; diagnostics use an operator connection |
| Full-text search, autocomplete and custom plans | Already implemented and verified | Migration 102 preserves custom search planning on 16/17; large search-plan tests and measured prior optimization | Preserve migration 102 and search v6 |
| Query budgets, N+1 and deep keyset plans | Already implemented and verified | HTTP budgets at 1/50 rows; 3,000-post thread and 1,500-thread category plan fixtures; actual reader SQL | Reuse deterministic gates |
| Outbox claims, renewal, retries, reclaim and idempotency | Already implemented and verified | Atomic `SKIP LOCKED`; owner guards; independent-connection lease/reply/moderation races; real PostgreSQL benchmark | No replacement or speculative tuning |
| Monthly event/audit/notification partitions | Already implemented and verified | Migrations 038/049/070; advisory-lock lifecycle; horizon, conflicts and uniqueness tests | Keep existing operator-managed lifecycle |
| Bounded retention | Already implemented and verified | Existing approved expiry settings, holds and bounded purge; detach/archive/drop remain manual | No new deletion policy |
| Logical database backup, attachment archive and manifest | Implemented but incomplete | SHA-256 manifest and check; isolated dump/restore drill; sequential database/file copies lack a shared snapshot | Preserve tool; clarify quiescence, consistency and recovery objectives |
| Physical backup and PITR | Implemented but incomplete | Existing three-row isolated drill and 2026-10-01 PG18 evidence; no manifest verification, strict deadline or CI | Harden the existing drill in Perl; add bounded weekly/manual CI |
| `pg_stat_statements` operator evidence | Absent and useful | Request observer counts statements but has no server cumulative cost, planning, buffers or WAL | Optional read-only collector; no SQL text or bind values |
| `auto_explain` nested diagnostics | Implemented but incomplete | Existing six-call, rollback-contained nested plan gate; parameter logging not disabled; buffers/WAL absent | Harden this existing gate, expose only metric allowlists |
| Vacuum, statistics, freeze, index, lock and checkpoint diagnostics | Absent and useful | No unified bounded operator snapshot; no evidence for global tuning | Add one read-only, version-aware collector |
| PostgreSQL 16/17/18 CI | Implemented but incomplete | Existing complete matrix/drills; missing consumer/tool triggers, wrong `Service/Ops` path, no PITR workflow | Extend existing triggers and disposable fixtures; retain all gates |
| Additional outbox/session partitions or indexes | Unnecessary or deferred | No production growth rate, representative selectivity or before/after benefit; global uniqueness/FK and claim semantics complicate partitions | Collect evidence before proposing a migration |
| RLS, global tuning or automated `VACUUM FULL` | Unnecessary or deferred | Existing SQL API/ACL boundary; no measured protection/performance gain | No additional ACL engine or automatic blocking maintenance |

## Implemented changes

| Phase | Scope and independent verification | Benefit / risk / complexity |
| --- | --- | --- |
| A — Audit | This inventory, existing catalogue/architecture and plan tests | Avoid duplicate systems; documentation only |
| B — Observability | Operator collector/schema (`t/671`, new live diagnostics); existing nested plan gate (`t/54`, `t/371`, live SQL plans) | High diagnostic value; low runtime risk because no web process loads the collector; bounded version-specific catalog queries |
| C — Reliability | Existing PITR tool/schema (`t/673`, real isolated recovery); staging cleanup (`t/675`, live staging drill); bounded recovery workflow (`t/672`) | Integrity/deadline/cleanup gaps demonstrated; low production risk because fixtures are owned and isolated; matching native tools |
| D — Concurrency/performance | Independent three-connection lock observation; existing API-role, lease/reclaim/race, SQL plan and budget gates | Better contention evidence; no application SQL change without measured benefit |
| E — Partitioning | Audit of existing monthly partitions, lifecycle and retention gates | Additional partitions deferred until growth/selectivity/maintenance benefit is demonstrated |

`script/postgres-diagnostics` and its modules under
`script/lib/GPForum/PostgreSQL/` inspect only allowlisted PostgreSQL catalogs
and extension counters. They use a dedicated read-only transaction, a
two-second statement timeout, half-second lock timeout and per-section
savepoints. SQL text is not retrieved: statement statistics explicitly call
`pg_stat_statements(false)`. Reports distinguish optional absence, limited
visibility and disabled planning instrumentation from measured zeros.
The [operator runbook](ops/postgres-diagnostics.md) documents settings,
privileges, activation, reset boundaries and interpretation.

The existing query-plan evidence command now disables parameter logging,
explicitly controls diagnostic sampling, and records buffers/WAL for nested
plans. It publishes per-statement numeric summaries instead of summing
inclusive nested plans. An absent timing or counter is null. This improves
evidence collection, not application query execution; no before/after speed
improvement is claimed.

The existing PITR drill is implemented in Perl and uses matching PostgreSQL
tools, manifest verification, archive-completion polling, exact recovered
records, bounded promotion and cleanup. It uses only an owned, isolated
temporary cluster. It never connects to the forum's configured database.
Its [runbook](ops/backup-and-restore.md) distinguishes restore verification,
database PITR and the attachment consistency requirement.

The existing PostgreSQL matrix enables statistics only on its disposable
service and retains all integration, migration, privilege and plan tests.
Operator workflow paths now match actual directories. The separate recovery
workflow runs once weekly on PostgreSQL 18, or manually on 16/17/18; it does
not add PITR to every PR. Read-only tokens and 14-day diagnostic artifacts
are sufficient. The Sunday extreme workflow is unchanged.

## Decisions and operational impact

No migration, index, function catalogue entry, application default, runtime
privilege or production server setting changes. No new CPAN dependency.
Install no extension unless the operator chooses its overhead and restart
window. Planning tracking and sampled `auto_explain` are diagnostic choices,
not production defaults.

Outbox and session partitioning remain deferred: collect table size and churn
over a representative retention window, then demonstrate maintenance or
query benefits while preserving global keys, FKs and idempotency. The existing
event/audit/notification partition lifecycle already solves its intended
growth problem. There is no authorization to delete additional history.

RPO/RTO are operator-defined targets. The small CI PITR fixture verifies
archive/replay correctness and measures its own recovery time; it does not
establish production recovery guarantees, off-host durability or attachment
consistency. Quiesced matching snapshots or versioned file history are needed
for database/file recovery to the same instant.

Rollback consists of reverting repository tooling and workflow changes;
there is no database migration to undo. Optional production extension or
logging activation follows the operator runbook and is undone separately.
Do not reset shared statistics or change global PostgreSQL parameters merely
to reproduce a CI fixture.

## Validation and residual work

Current validation results and exact CI commit/run references are appended
after implementation tests finish. Unexecuted tests are not counted as passes.
Local reports during development mark their working tree as dirty.
The full application dataset, production load, live attachment/PITR restore,
off-host backup durability and production RPO/RTO remain operator evidence.

Configured incremental CI ceilings are 15 runner-minutes per weekly recovery
run (60–75 per four/five-run month), and four minutes per existing PostgreSQL
matrix job for preload/restart plus collection (12 across its three jobs).
These are timeout budgets, not measured runner usage or billing predictions.
No new PR job or matrix dimension was added; the Sunday extreme workflow is
unchanged. Recovery logs and JSON expire after 14 days; the existing continuous
performance history remains canonical and unchanged by these diagnostics.

Reproduce with the existing locked dependency tree and an operator DSN pointing
at a sacrificial PostgreSQL server where the test account may create databases:

```sh
script/gpforum-carton exec prove -l -It/lib t/*.t
script/gpforum-carton exec prove -l -It/lib -r t/integration
script/gpforum-carton exec script/postgres-diagnostics --json > diagnostics.json
script/postgres-diagnostics --validate diagnostics.json
script/gpforum-carton exec script/pitr-drill --json --timeout 180 > pitr.json
script/pitr-drill --validate pitr.json
```

Use the intended major's PostgreSQL tools on `PATH` for the last command; on
hosts with version-selection wrappers, set that `PATH` through `env` after
`script/gpforum-carton exec`, as the recovery workflow does. Integration tests
create and remove owned databases; PITR always creates a separate cluster.
