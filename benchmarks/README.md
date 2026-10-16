# Continuous performance evidence

[Performance and profiling](../.github/workflows/performance.yml) measures a
real Hypnotoad server against migrated PostgreSQL and the existing
deterministic `PerformanceSeed` dataset. The historical results live on
[main](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
at the canonical path `benchmarks/results/`, alongside the harness, schema
and documentation. Main is the requested permanent destination; a results
branch is not required.

The preliminary findings and reuse decisions are recorded in [AUDIT.md](AUDIT.md).
All harnesses, report/schema/baseline tools, publication and their tests are
implemented in Perl. Bootstrap and failure reporting use only core modules;
application/database commands use the existing locked Carton tree. The separate
[Sunday extreme workload](EXTREME.md) adds bounded mixed/soak evidence as artifacts.

## When measurements run

| Mode | Trigger | HTTP workload | Other evidence |
| --- | --- | --- | --- |
| PR | Relevant changes targeting `main` | Same runner, head and base revisions; 2 workers, Poll, concurrency 1/10, 2-second cells, 3 repetitions | Required index/OFFSET rules, query-budget catalog, reader and stored-function plans, 1-worker/1,000-message PostgreSQL outbox |
| Main | Relevant pushes to `main` | Concurrency 1/10/50/100; targeted 2/4-worker comparisons; Poll/EV on Linux when available; 3 repetitions | 3 plan repetitions; 1/2-worker PostgreSQL outbox, 3,000 messages, 3 repetitions; permanent publication |
| Deep | Monday 01:37 UTC or manual `deep` | Concurrency up to 500, targeted 2/4/8 workers where CPU count permits; Poll/EV, 3 repetitions | 600 threads/72,000 posts; 1/2/4-worker, 10,000-message outbox; existing SQL-function service comparison; configured NYTProf profile |

Relevant paths include actual application sources (`lib`, `templates`,
`assets`, `migrations`), `cpanfile*`, runtime/deployment files under `etc`
and `deploy`, entrypoints under `bin` and `script`, benchmark files/tests,
the Perl setup action, and the performance workflow. Generated
`benchmarks/results/**`, `benchmarks/latest.json` and `benchmarks/history.json`
are excluded from performance triggers, so an evidence publication cannot
retrigger a measurement.
Manual runs on other branches keep artifacts but cannot publish history.
The PostgreSQL/outbox test support actually used by the harness also triggers
measurement and participates in its compatibility fingerprint.

The job has a 40-minute limit. The HTTP harness has separate wall-clock
limits of 4/10/20 minutes for PR/main/deep, stops higher concurrency after
errors or saturation, and reports unfinished cells as skipped. SQL/outbox/
profiling collection has a separate total deadline of 3/5/10 minutes for
PR/main/deep; command timeouts are capped by remaining time and remaining
tests are explicitly skipped after exhaustion. The
configuration deliberately avoids a full endpoint × worker × reactor ×
concurrency matrix. Concurrency 1,000 requires an explicit local
`--allow-1000 --concurrency ...` request and sufficient file-descriptor/CPU
resources; it is never scheduled by default.

## What the numbers mean

Each endpoint is measured separately: `/health/live`, home, categories,
category, thread, search, category page cache hit and category page cache
miss. The independent `wrk` generator is primary; the existing Mojolicious
`bin/gpforum stress-load` generator supplies a smaller comparison. The two
generators' throughput is not interchangeable. Authentication is explicitly
skipped because there is no isolated reproducible session setup in this
read-only HTTP suite.

The cache miss test expires the SSR cache immediately while keeping the
category model cache warm. It is a measured SSR miss, not a claim of a cold
PostgreSQL buffer pool. The cache hit test warms the actual page and checks
the observed `X-GPForum-Cache` header. The run records this policy and cache,
PostgreSQL, generator and runtime versions.

Server workers write private per-PID JSON telemetry before dispatch;
the harness verifies every serving worker PID. On Linux, EV is an
optional distribution package and its actual epoll backend is verified.
Poll and EV share dataset, workers, endpoints, PostgreSQL and cache
settings; their order alternates across repetitions. There is no EV
application requirement on Linux, macOS or FreeBSD. CPU and RSS are sampled
for the server process group. Linux CPU comes from `/proc` tick deltas over
the measured span; `ps` CPU averages are a marked fallback. RSS is a final
sample and can double-count shared pages. Neither is a precise per-request
resource cost.

SQL plans reuse `bin/gpforum query-plan-evidence --analyze --check`, including
`--functions` to expose nested stored-function SQL with `auto_explain`.
Missing privileges/extensions produce failed or unmeasured evidence rather
than a pass. Plan execution times include EXPLAIN overhead and exclude HTTP.
The existing query-budget/N+1 integration tests and functional tests stay
blocking in `ci.yml`; performance timing changes are advisory.

`script/performance-outbox.pl` runs the actual dispatcher on independent
PostgreSQL connections in real forked workers. Each measurement owns a
fresh migrated database, deterministic message IDs and a recording no-op
transport. Seeding and migrations are excluded from its timed span; worker
connection startup is included. Losses, duplicates, acknowledgements and
final `done` rows are checked. Batch p50/p95/p99 cover claim, renewal,
delivery and acknowledgement, not individual message latency or real
delivery cost. The older in-memory `script/bench-outbox-dispatcher` remains
useful for Perl overhead and is not presented as database capacity.

Deep mode also reuses `script/bench-sql-functions` on its own database:
3,000 additional posts, 1,500 category threads, direct and delayed proxy
connections, DBIC/function paths and CPU/statement/round-trip breakdowns.
These are service measurements, separate from pure SQL and HTTP timings.
The configured `script/profile-nytprof` profile is diagnostic; binary
profiles and raw logs are retained only as artifacts for 14 days.

## Comparison and publication

PR measurements compare the base revision and head on the same runner,
with one harness version and each revision's own locked dependency tree
and disposable database. Main/deep find the latest valid compatible run in
history. Compatibility requires the same mode, runner OS/architecture/
label/image/CPU/memory class, versions, deterministic dataset signature and
benchmark configuration. A missing or incompatible baseline is explicitly
`not-comparable`; a rerun of the same commit does not silently become its
own baseline.

The report uses medians and median absolute deviations. Timing changes
under 10%, or under three times the relative MAD, are treated as ordinary
noise. A confirmed regression additionally needs at least three independent
repetitions on both sides, a deterioration of at least 15%, and separated
sample ranges. Classifications are confirmed regression, possible
regression, stable, improvement and not comparable. These thresholds are
conservative screening rules, not a statistical significance test.
CPU/RSS percentage deltas are diagnostic and do not alone confirm a
regression. A single short PR outbox run is indicative.

Every run uploads a Job Summary and artifacts, including partial failure
evidence. The published structure is append-only:

```text
benchmarks/
  README.md
  schema-v1.json
  latest.json
  history.json
  results/YYYY-MM-DD/<full-commit-sha>/<run-id>-<attempt>/
    metadata.json
    summary.json
    http.json       # only when measured
    reactor.json    # only when measured; comparison may be skipped
    workers.json    # only when measured; comparison may be skipped
    database.json  # only when measured
    outbox.json    # only when measured
    report.md
```

All JSON uses [schema version 1](schema-v1.json), validated without a new
dependency. Finalization attaches commit, date, runner, dataset and
configuration provenance to measurement envelopes. `latest.json` points to
the latest valid complete run; `history.json` retains failed/partial runs
too. Same-commit reruns have different run/attempt paths; existing data
cannot be overwritten with different contents. Profiles, credentials,
logs and temporary files are excluded from publication.

Only a separate job on trusted `main` gets `contents: write`; PR jobs and
base checkouts use `contents: read`, no persisted Git credentials and no
repository secrets. Publication validates the expected commit/run/attempt,
schema, sizes, paths and secret patterns; artifacts are treated as data
and never executed. Ordinary Git pushes append only result/index files to
the current main tip and provide an atomic branch update; bounded retries
reload the newest tip after contention, preserving intervening application
commits. No personal token or force push is used. Main publication adds
evidence commits to application history and therefore requires main's rules
to allow the job-scoped `GITHUB_TOKEN` to push these updates. A rule or token
rejection remains visible and the artifact is still retained. Optional PR
comments are omitted to keep this workflow usable for external forks; the
Job Summary contains the complete report.

## Cost and limits

GPForum is public. Standard Linux GitHub-hosted runners are free for public
repositories; larger runners have separate billing. The implementation uses
the existing `ubuntu-26.04` runner and PostgreSQL 16 service, with the exact
OS/architecture/system-Perl/dependency-lock cache key. There are no larger
runners, GPUs, paid services or performance matrix jobs. See
[GitHub-hosted runner limits](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

Budget roughly 6–12 runner minutes per paired PR, 10–15 per main push and
20–30 for one weekly deep run, plus cold dependency-build time. These are
planning estimates. The first complete
[main run](https://github.com/gpicchiarelli/GPForum/actions/runs/38149645101)
actually took 10 minutes 7 seconds for measurement and 11 seconds for
publication; PR/deep durations have not yet been measured. Default wrk sampling
alone is about 96 seconds per PR revision, 408 seconds on main and 864
seconds for the full deep plan with EV and 8-worker rows; startup, seeding,
SQL/outbox, dependency setup and generator comparisons are additional.
Caps are 40 minutes for measurement and 5 for publication. A second run for the same event/ref/commit
queues behind an advanced run; different PRs can progress independently.
Read-only PR artifacts expire after 14 days, while compact main/deep JSON
and Markdown persist in `main`.

Hosted CPUs and neighbours vary. The load generator, PostgreSQL and server
share the runner, so throughput measures comparative CI capacity under
that configuration, not production capacity. Even the deep dataset is far
smaller than production-scale reference data. Endpoints that lack enough
rows for meaningful deep pages report plan limitations explicitly.

## Reproduce locally

Every performance CI run also compares 1,000 and 5,000 configured HTTP
connections against `/health/live`, in three 10-second samples at each level
on the same runner with the same four-worker configuration. This tests HTTP transport
capacity; it does not establish capacity for database-backed pages. Failures
remain visible in the CI gate. The separate `connections-5000` report and
raw generator logs are included in the candidate artifact and Job Summary.
The runner raises its file limit to 32,768; the harness requires at least
16,384 and permits 5,000 clients per worker for this explicit stress test.
`wrk` connection counts are configured connections, not measured in-flight
requests or virtual users.

Use a disposable PostgreSQL cluster/database named `gpforum_perf_*`, never
the application database. The database role needs CREATE DATABASE for the
owned outbox and SQL-function helpers; nested plan inspection needs
`auto_explain` and sufficient privileges. `wrk` is optional locally; use
`--generator mojo` if unavailable and retain its indicative limitation.

```sh
export GPFORUM_DATABASE_DSN='dbi:Pg:dbname=gpforum_perf_local'
export GPFORUM_DATABASE_USER=benchmark_user
# Supply a password via the local environment if required, not a tracked file.
script/bootstrap-deps --postgres
bin/gpforum migrate

perl script/performance-evidence init --output artifacts/performance --mode pr
script/gpforum-carton exec script/performance-http --output artifacts/performance --mode pr \
  --generator wrk --disposable-database
script/gpforum-carton exec script/performance-hotpaths --output artifacts/performance --mode pr \
  --disposable-database
perl script/performance-evidence finalize --output artifacts/performance
perl script/performance-evidence validate --output artifacts/performance
script/gpforum-carton exec prove -I script/lib -I t/lib -lr t/performance
script/gpforum-carton exec prove -lv t/integration/postgres-performance-outbox.t

# Existing helpers remain available independently:
bin/gpforum budgets --check --json
bin/gpforum query-plan-evidence --analyze --functions --check --json
script/gpforum-carton exec script/performance-outbox.pl \
  --json --messages 1000 --workers 1,2 --repetitions 3
```

Use a second finalized output directory with `finalize --baseline DIR` for
a local comparison. Switch both helpers and the metadata initializer to
`--mode main` or `--mode deep` for larger scenarios; do not compare modes.
The HTTP helper reseeds only the explicitly acknowledged disposable
database. Outbox/SQL helpers drop databases they create after success and
caught exceptions; both helpers also handle ordinary termination
signals. Completed outbox repetitions survive a later interruption. A host kill cannot run cleanup code, so a disposable
cluster/service is the final containment boundary.
