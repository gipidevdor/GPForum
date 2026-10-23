# Continuous performance evidence

[Performance and profiling](../.github/workflows/performance.yml) measures a
real Hypnotoad server against migrated PostgreSQL and the existing
deterministic `PerformanceSeed` dataset. The historical results were merged
from `performance-data` into `main` on 2026-10-17 before retiring that branch.
The preserved snapshot is at [benchmarks/results](results/), with
`latest.json` and `history.json` as its indexes. Every new run keeps its
evidence as a workflow artifact for 14 days and publishes a Job Summary.
Automatic measurements have read-only repository access and do not update
branches.

The preliminary findings and reuse decisions are recorded in [AUDIT.md](AUDIT.md).
All harnesses, report/schema/baseline tools, publication and their tests are
implemented in Perl. Bootstrap and failure reporting use only core modules;
application/database commands use the existing locked Carton tree. The separate
[Sunday extreme workload](EXTREME.md) adds bounded mixed/soak evidence as artifacts.

## Operation diagnostics

`script/benchmark-operations` adds the complete PostgreSQL integration tier as
a diagnostic workload, covering authenticated requests, writes, identity,
administration, moderation, attachments, privacy, discovery, notifications,
search and background processing wherever those workflows exercise them.
It instruments the actual SQL execution boundary and HTTP request observer;
it does not substitute fake services or invent arguments for stored functions.
New routes and SQL catalogue entries appear automatically in the coverage inventory.

```sh
make benchmark-operations BENCHMARK_OUTPUT=artifacts/operations-001
script/gpforum-carton exec script/benchmark-operations \
  --output artifacts/operations-replies \
  --test t/integration/postgres-sql-function-forum-writes.t \
  --repetitions 3
script/gpforum-carton exec script/benchmark-operations --inventory
```

Each run requires a new output directory, starts socket-only temporary
PostgreSQL clusters and discards inherited database DSNs. It owns its test
databases and never points at the running forum. The default is one test
process at a time; `--jobs N` trades diagnostic isolation for run time.
The performance workflow runs this in a separate job on main pushes and
manual/weekly runs, outside the HTTP load harness's deadline.

`operations.json` reports count, total, mean, nearest-rank p50/p95/p99/max,
HTTP database and remaining application time, query counts, contributing
tests and the slowest sample's test. SQL returns/exceptions and individual
HTTP status codes have separate distributions. First observations are kept
apart from subsequent observations per process, operation and outcome; these
are not a guarantee of cold or warm caches. Fewer than 20 samples are flagged.
The coverage lists **missing operations** and operations without a 2xx HTTP
response or a nonexceptional SQL return. A legitimate form redirect remains
a 3xx measurement; a SQL return can still be a rejected domain command.
Workflow assertions, not HTTP status alone, determine test correctness.
`status=ok` means collection and assertions passed, not complete operation coverage.

The report is diagnostic: integration scenarios use different data sizes,
deliberate errors, races and injected failures. SQL time includes DBI and
transport. HTTP time covers application dispatch, excluding client/network;
trace recording adds overhead outside the measured SQL call. Do not compare
these percentiles to the controlled Hypnotoad load baseline. Use the recorded
test to reproduce a slow path, then profile that path on a fixed seed and run
the load suite. External services remain governed by the integration tests'
opt-ins; a skipped ClamAV, standby or external-mail test is not capacity evidence.
`tests-*.log` retains the TAP result and explicit skips; private per-process
JSONL traces omit SQL parameters, URLs, request bodies and exception messages.
Rebuild aggregates without rerunning tests with `--output DIR --summarize`.
This report has its own format and does not change the load evidence schema below.

For repeated measurements on one fixed dataset, `script/bench-render` now
also measures member lists, settings/security/privacy, messages, discovery and
thread/category mbox exports (28 scenarios). Every request must return 200.
It reports request, database, template and remaining time plus query counts:

```sh
GPFORUM_DATABASE_DSN='dbi:Pg:dbname=postgres;host=/path/to/socket' \
  script/gpforum-carton exec script/bench-render --iterations 50 --warmup 5 --json
```

This command creates and drops its own migrated medium-seed database.
The benchmark member's private lists start empty; populated inboxes and
write lifecycles remain covered by the integration diagnostic suite.
Use `--page category_archive` or another label to isolate a measurement;
`--nytprof /tmp/archive.nytprof` profiles only the measured requests, after warmup.

## When measurements run

| Mode | Trigger | HTTP workload | Other evidence |
| --- | --- | --- | --- |
| PR | Relevant changes targeting `main` | Same runner, head and base revisions; 2 workers, native EV, concurrency 1/10, 2-second cells, 3 repetitions | Required index/OFFSET rules, query-budget catalog, reader and stored-function plans, 1-worker/1,000-message PostgreSQL outbox |
| Main | Relevant pushes to `main` | Concurrency 1/10/50/100; targeted 2/4-worker comparisons; native EV; 3 repetitions | 3 plan repetitions; 1/2-worker PostgreSQL outbox, 3,000 messages, 3 repetitions; workflow artifacts |
| Deep | Monday 01:37 UTC or manual `deep` | Concurrency up to 500, targeted 2/4/8 workers where CPU count permits; native EV, 3 repetitions | 600 threads/72,000 posts; 1/2/4-worker, 10,000-message outbox; existing SQL-function service comparison; configured NYTProf profile |

Relevant paths include actual application sources (`lib`, `templates`,
`assets`, `migrations`), `cpanfile*`, runtime/deployment files under `etc`
and `deploy`, entrypoints under `bin` and `script`, benchmark files/tests,
the Perl setup action, and the performance workflow. The generated
`benchmarks/results/**`, `benchmarks/latest.json` and `benchmarks/history.json`
are excluded from measurement triggers. Historical evidence can be retained
through an explicitly reviewed commit on `main`; automatic runs keep artifacts.
Manual runs on other refs use the same artifact policy.
The PostgreSQL/outbox test support actually used by the harness also triggers
measurement and participates in its compatibility fingerprint.

The job has a 40-minute limit. The HTTP harness has separate wall-clock
limits of 4/10/20 minutes for PR/main/deep, stops higher concurrency after
errors or saturation, and reports unfinished cells as skipped. The
1,000/5,000-connection gate below is the exception: it measures every level
it plans, and an unmeasured cell fails it. SQL/outbox/
profiling collection has a separate total deadline of 3/5/10 minutes for
PR/main/deep; command timeouts are capped by remaining time and remaining
tests are explicitly skipped after exhaustion. The
configuration deliberately avoids a full endpoint × worker × reactor ×
concurrency matrix. Concurrency 1,000 requires an explicit local
`--allow-1000 --concurrency ...` request and sufficient file-descriptor/CPU
resources in the general sweep. The separate CI transport comparison below
explicitly schedules 1,000 and 5,000 connections.

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
the harness verifies every serving worker PID. EV is a mandatory locked
dependency: Linux uses epoll, macOS and FreeBSD use kqueue. A missing or
incorrect native backend fails the run. Worker comparisons share dataset,
endpoints, PostgreSQL and cache settings; their order alternates across
repetitions. CPU and RSS are sampled
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
evidence. The historical snapshot retained on `main` has this structure:

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

All workflow jobs use `contents: read`, no persisted Git credentials and no
repository secrets. Artifacts are validated as data and never executed. The
workflow reads the preserved history from `main` for compatible baselines and
keeps new evidence as artifacts; it does not push commits or require a data
branch. The existing standalone publication tool remains covered by its tests,
but CI does not invoke it. Optional PR comments are omitted; the Job Summary
contains the complete report.

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
The stress listener backlog and the runner's accept/SYN queue limits are
8,192, so the initial 5,000-connection burst is queued. The gate refuses to
measure when `net.core.somaxconn` is below the burst, and records the
kernel's `ListenOverflows` and `ListenDrops` across each sample. This stress
comparison uses an explicit three-second response timeout at both connection
levels; the ordinary HTTP sweep retains its three-second default. Zero HTTP
and transport errors are required. The timeout is recorded in the report and
configuration, and failed samples remain available in history.
`wrk` connection counts are configured connections, not measured in-flight
requests or virtual users.

The gate is all or nothing (ADR 0063). It does not apply the sweep's
saturation stop: a slow 1,000 is evidence, not a reason to leave 5,000
unmeasured, and a planned cell or repetition that was not measured fails the
suite. The final CI step reads the gate's own summary
(`performance-workflow-status --check --gate DIR`), which must be `ok`, not
`partial`. Before each sample, a three-second pass at the same concurrency,
not counted in the sample, warms the workers; its own figures stay in the
row, and the sample still opens all its connections at once. On Linux the
row also carries each worker's connections halfway through the sample.

Each 5,000 sample records its margin to the budget and whether the runner
could meet the bar at all. A closed loop of N connections served at R
requests/s waits N/R on average; a Mojolicious worker serves the requests
ready in one event-loop turn and writes their responses in the next, so a
request that just missed a turn waits two, 2N/R. Three seconds hold that
from 3,334 requests/s at 5,000 connections. The hosted four-CPU runners do
not all reach it: in 60 samples from 20 runs on 2026-10-16/17,
`/health/live` served 5,970-6,560 requests/s on AMD EPYC 9V45 hosts and
3,240-4,470 on EPYC 9V74, with no timeouts, but 2,790-3,190 on EPYC 7763 and
Xeon 8370C/8573C hosts, where the p99 reached 2.9 s and 23 of 42 samples
timed out; none above 3,110 requests/s did.
Timeouts on a sample below 3,334 requests/s are reported as
`runner_below_bar`: the gate fails, and the report says the runner cannot
hold 5,000 connections within three seconds rather than passing. Raising
what a worker serves per second is what moves that line.

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
