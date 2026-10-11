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

Implemented source revision: `3e1a0af78cee9cb79704f4730b7b7d933bc10874`.
The subsequent `fc031d6` corrects an existing performance-harness JSON clock
rounding bug found by the Debian job; PostgreSQL/application sources are
unchanged by that follow-up.
The following completed checks cover the integrated composer-draft change and
this PostgreSQL work. Local tests used the same Perl source tree; the final
rebase added only previously generated performance-history files.

| Executed check | Result |
| --- | --- |
| Local unit suite | PASS: 409 files, 16,479 assertions |
| Local full PostgreSQL 18 integration | PASS: 100 files, 10,769 assertions |
| Local PostgreSQL 17 diagnostics, plans, API role, reclaim, catalogue, drafts and privacy | PASS: 9 files, 3,263 assertions |
| Existing continuous performance contracts | PASS: 10 files, 249 assertions; after the clock fix, 11 files and 257 assertions |
| Existing composer JavaScript suite | PASS: 10 tests |
| All 22 changed Perl sources/tests | Syntax, strict Perl::Critic and exact perltidy comparison PASS |
| Two performance clock fix files | Syntax, strict Perl::Critic, formatting and independent boundary review PASS |
| Architecture boundaries, all workflow YAML and whitespace | PASS: `script/architecture-check`, `actionlint`, `git diff --check` |
| [Linux PostgreSQL matrix](https://github.com/gpicchiarelli/GPForum/actions/runs/38164142663) | PASS: 16.15 / 17.11 each 100 files and 10,746 assertions; 18.6 100 files and 10,769 assertions; migration reapply and logical drills pass on all |
| [Linux PITR 16.15](https://github.com/gpicchiarelli/GPForum/actions/runs/38164145438) | PASS: verified manifest/archive/target, exact 3→2 rows, recovery 0.551 s, entire drill 3.178 s |
| [Linux PITR 18.6](https://github.com/gpicchiarelli/GPForum/actions/runs/38164142557) | PASS: verified manifest/archive/target, exact 3→2 rows, recovery 0.187 s, entire drill 2.544 s |
| [Existing operations drills](https://github.com/gpicchiarelli/GPForum/actions/runs/38164142597) | PASS: ten evidence reports validated |
| [Security checks](https://github.com/gpicchiarelli/GPForum/actions/runs/38164142588) | PASS, including repository secret scanning and workflow lint |
| [Security checks after the clock fix](https://github.com/gpicchiarelli/GPForum/actions/runs/38165363278) | PASS: dependency/licenses, workflow analysis and secret scanning; conditional Scorecard was skipped |
| [Continuous performance](https://github.com/gpicchiarelli/GPForum/actions/runs/38164142546) | PASS execution/schema/publication; timing comparisons remain advisory |
| [Continuous performance after the clock fix](https://github.com/gpicchiarelli/GPForum/actions/runs/38165363259) | PASS execution/schema/publication: 113 measured configurations, all comparisons explicitly non-comparable because no compatible baseline exists |
| [Debian after the clock fix](https://github.com/gpicchiarelli/GPForum/actions/runs/38165363346) | PASS: 520 files, 27,442 reported TAP tests; `budget.t` and `extreme.t` executed successfully; five files explicitly skipped |

The [permanent evidence archive](ops/evidence/2026-10-11-postgres-reliability/README.md)
contains the two real Linux PITR reports, three diagnostics and three logical
restore reports, copied unchanged from CI. All eight pass generic strict
validation, and the new tool-specific reports pass their versioned schemas.
Each diagnostics report has nine successful sections and 25 ranked statement
observations. These are cumulative fixture snapshots, not before/after SQL
benchmarks. No application SQL optimization or production speedup is claimed.

Failure-path tests exercise missing tools, manifest/archive/data mismatches,
deadlines, occupied directories, cleanup after restore/connect exceptions,
optional extension absence, restricted visibility, missing nested plans and
private-data canaries. The new live lock test uses three independent database
connections. No new runtime privilege is granted. Test-owned local clusters
were stopped and removed after verification.

The first [Debian target run](https://github.com/gpicchiarelli/GPForum/actions/runs/38164142609)
failed in `t/performance/extreme.t`: a valid 1,800-second clock encoded/decoded
through JSON exceeded its upper bound by approximately 2.27e−13 seconds.
The isolated reproducer and eight new deterministic tests establish the
failure and correction. Validation now accepts at most one microsecond of
upper-bound rounding, then clamps to the original hard limit; measurement
ordering remains strict, including sub-microsecond ordering violations.
This changes no workflow, workload, job budget or report reserve. The failed
run remains recorded. The corrected Debian job passed in 809 seconds,
including the 400-second complete suite. Its five skipped files cover a
root-only permissions check, two logical-backup/staging tests where Debian's
pg_dump 17 cannot dump the PG18 service, an unavailable ClamAV socket and
an existing standby fixture without native server tools on PATH. These are
not executed checks. Matching-client logical restores are verified separately
by the successful PostgreSQL 16/17/18 matrix, and the dedicated PITR jobs use
matching native tools. No new replication functionality was introduced.

Suite totals above are the test harness's reported TAP counts; a suite PASS
does not claim execution of its skips or success of existing TODO cases.
Unexecuted or skipped capabilities are not counted as verified. Four pre-existing
`SuspensionStore` timestamp-string TODO expectations remain in the CI matrix;
the local attachment suite also reports five existing TODOs that now pass.
The initial broader Perl quality/coverage run was automatically cancelled by
its existing concurrency policy when the clock fix was pushed. The
[replacement quality/coverage workflow](https://github.com/gpicchiarelli/GPForum/actions/runs/38165363263)
was still running when this report was written; it is not counted above.
Local development snapshots mark their working tree as dirty; archived CI
reports identify the exact clean source revision.
The full application dataset, production load, live attachment/PITR restore,
off-host backup durability and production RPO/RTO remain operator evidence.
The concurrently introduced draft feature's existing sequential tests pass;
this work does not establish its quota behavior under concurrent publish or
privacy erasure. That requires a separate focused concurrency investigation.

Configured incremental CI ceilings are 15 runner-minutes per weekly recovery
run (60–75 per four/five-run month), and four minutes per existing PostgreSQL
matrix job for preload/restart plus collection (12 across its three jobs).
These are timeout budgets, not measured runner usage or billing predictions.
No new PR job or matrix dimension was added; the Sunday extreme workflow is
unchanged. Recovery logs and JSON expire after 14 days; the existing continuous
performance pipeline continues to publish its canonical history separately.
Measured complete PITR job durations were 53 seconds on 18 and 67 on 16,
including runner setup. Cold caches, scheduling and package installation can
increase those times; the 15-minute cap remains the cost ceiling.

The existing performance pipeline published
[this source's complete HTTP/SQL/outbox report](../benchmarks/results/2026-10-11/3e1a0af78cee9cb79704f4730b7b7d933bc10874/38164142546-1/report.md)
automatically. Against the compatible historical `2237bb6` run, its 113
comparisons classify 76 stable, 4 improvements, 20 possible regressions,
12 `confirmed-regression` timing signals and 1 non-comparable observation.
For example, Poll/two workers/homepage/concurrency 10 measured 199.071 req/s
and p95 60.567 ms (throughput −12.386%, p95 +11.778%, p99 +26.244%). The
classifier can flag a latency percentile even when throughput is stable.
These are repeated observations on different shared-runner executions, not
proof of a code-caused slowdown: application reader/search/seed SQL, templates,
assets and migrations are byte-identical to that baseline. Preserve the flags
and recheck them with paired measurements before proposing query changes.
All deterministic plan, correctness and query-budget checks passed.

The follow-up clock fix changes the harness fingerprint. Its
[published run](../benchmarks/results/2026-10-11/fc031d6ec7fb488326b04f2e3b0c78f1c6682352/38165363259-1/report.md)
therefore reports 113 measured configurations with 113 non-comparable timing
classifications and an explicit absent baseline. It does not relabel the
previous advisory flags as stable or claim an improvement. SQL reader/nested
plan and outbox gates passed. Authentication, eight workers, concurrency
250/500/1,000 and deep profiling were explicitly skipped in the ordinary
`main` profile, with reasons retained in its report. Collection and publication
took 641 and 20 seconds respectively; this existing workflow was not expanded.

Two example medians from that latest run use `wrk`, Poll, two workers,
concurrency 10 and three repetitions on the `main` fixture (25 users,
8 categories, 240 threads, 4,800 posts):

| Endpoint | Requests/s | p50 ms | p95 ms | p99 ms | Comparison |
| --- | ---: | ---: | ---: | ---: | --- |
| Homepage | 214.265 | 45.895 | 58.847 | 71.513 | Non-comparable |
| Search | 126.342 | 76.318 | 87.000 | 133.546 | Non-comparable |

These are bounded shared-runner fixture measurements, not a production
capacity claim. The linked JSON records durations, errors, resources, versions
and skipped configurations for every scenario.

## Changed files

No database migration was created or modified by this work. Historical evidence
and the extreme-performance workflow were preserved.

| Area | Files |
| --- | --- |
| Collector and recovery tooling | `script/postgres-diagnostics`, `script/pitr-drill`, `script/lib/GPForum/PostgreSQL/{Queries,Diagnostics,DiagnosticsCLI,PITR}.pm` |
| Measured harness failure correction | `script/lib/GPForum/Performance/Budget.pm`, `t/performance/budget.t` |
| Existing application-side diagnostic/operations tools | `lib/GPForum/Command/QueryPlanEvidence.pm`, `lib/GPForum/Service/Operations/{EvidenceValidate,StagingDrill}.pm` |
| CI | `.github/workflows/{postgres-matrix,postgres-recovery,ops-drills}.yml` |
| Operator schemas/runbooks | `docs/ops/{postgres-diagnostics-schema-v1.json,postgres-pitr-schema-v1.json,postgres-diagnostics.md,backup-and-restore.md,evidence-validate.md}` |
| Project documentation | `docs/{POSTGRESQL_RELIABILITY,CI,DEPLOYMENT,PERFORMANCE,PRODUCTION_READINESS,README}.md` |
| Existing test contracts | `t/{54-query-plan-evidence,166-deploy-contract,371-query-plan-report-pins,431-benchmark-folded-paths,614-drills-take-flags}.t`, `t/lib/GPForum/Test/QueryPlanEvidenceDbh.pm` |
| New deterministic tests | `t/{671-postgres-diagnostics,672-postgres-reliability-workflows,673-postgres-pitr-drill,674-postgres-evidence-types,675-staging-drill-cleanup}.t` |
| Live PostgreSQL tests | `t/integration/{postgres-diagnostics,postgres-sql-function-plans}.t` |
| New immutable archive | `docs/ops/evidence/2026-10-11-postgres-reliability/`: README, eight JSON reports and exit sidecars |

## Local reproduction

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
