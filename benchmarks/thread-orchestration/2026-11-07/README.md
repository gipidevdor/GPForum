# Local thread orchestration diagnosis — 7 November 2026

Apple M4, 10 cores, 16 GiB; Perl 5.44.0, Mojolicious 9.51, PostgreSQL 18.6,
EV/kqueue. Eight Hypnotoad workers, 16 admitted connections per worker, two
native query leases per worker. Private local PostgreSQL, durability enabled.
The fixture has 103 users, 240 threads and 4,800 posts. No distributed cache.

## Results

Medians of three repetition statistics. Each concurrent cell lasts six seconds;
10 warmup requests precede the scenario. Single-session cells use 100 requests.
Percentiles are not pooled across repetitions.

| Arm | Thread sessions | req/s | p95 ms |
| --- | ---: | ---: | ---: |
| Published `05f238b` baseline | 100 | 370.0 | 352.8 |
| Isolated native transport subset | 100 | 408.7 | 333.9 |
| Isolated transport plus read adapters | 100 | 420.3 | 311.6 |
| Clean integrated `756374d` confirmation | 100 | 413.4 | 307.0 |

The integrated confirmation improves throughput by 11.7% and p95 by 13.0%
against the local baseline. It does **not** establish the 420 req/s target as
stable, or meet 450 req/s / 300 ms. Its repetitions are 413.4, 422.8 and
407.8 req/s, with p95 294.4, 307.0 and 331.1 ms. The faster isolated subset
must not replace that integrated result.

Baseline and isolated arms use the original 1/10/50/100-session sequence.
The final clean integrated confirmation selects 100 sessions, with the
harness's mandatory one-session cells. The remaining parameters match, but
this workload-order difference is a limitation of the comparison.
Two attempts at broader integrated confirmation overlapped another session's
tests; both are retained under `attempts/` and excluded from capacity claims.

Separate clean local integrated measurements, at 10 sessions and the same
8-worker/16-connection configuration:

| Scenario | HTTP req/s | p95 ms |
| --- | ---: | ---: |
| Mixed reads/writes | 347.1 | 47.6 |
| Authentication | 51.5 | 418.0 |

Authentication counts the login/redirect/logout HTTP journey, not hashes/s.
No matched old eight-worker local authentication/write baseline was measured.
Search measurements from a contaminated integrated attempt are not a clean
new search reference. See [raw summary](summary.json), per-arm JSON and monitors.

## Diagnosis and selected lever

The accepted instrumented run captures all eight serving workers and 6,030
requests. A typical request performs six SQL calls; 23 cold/cache-refresh
requests perform seven. The six top-level PostgreSQL functions average about
0.94 ms of combined server execution time. At 100 sessions the observer sees
at most 25 database connections, excluding itself, against a limit of 80.
No PostgreSQL `Lock` or `IO` wait class is sampled; `ClientRead` predominates,
and `ClientWrite` is also observed. EXPLAIN ANALYZE/BUFFERS output is retained;
function wrapper plans do not expose every nested plan, and no historical
EXPLAIN plan was available.

The instrumented request allocates about 303 Promise objects and schedules
362 Promise deferrals. Estimated summed native-query admission waiting is
213 ms per captured request, about 74% of its instrumented mean application
time. This is an indication of application-side queueing, **not** a measured
production CPU percentage. Observer overhead raises costs and queueing.
Exclusive CPU timings cover selected synchronous boundaries; some CPU is
unassigned. Full counters, wait samples and pg_stat_statements are preserved.

The isolated change reduces Promise relays in admission, lease completion,
row decoding, ready controller results and the existing authenticated read
adapters. SQL, query count, pool budget, workers, admission, authorization,
visibility and session checks remain unchanged in that isolated comparison.
The integrated commit also contains independent native-write work; its
identity is recorded separately. No fragment cache or worker sweep was added.

NYTProf 6.15 failed during startup with a Future::AsyncAwait panic; that
attempt has no measured HTTP cells and is not a performance sample. Two
phase-capture attempts lost worker counters because the harness uses TERM.
The accepted diagnostic harness uses native graceful QUIT to flush counters;
application signal handlers were not changed. See [attempt ledger](attempts.json).

## Validation and reproduction

The isolated read candidate passes 536 general-suite files / 20,403 tests and
175 functional files / 15,336 tests, with 41/41 feature outcomes, PostgreSQL 18
and real ClamAV. Those results apply to the recorded isolated subset.
A diagnostic-only follow-up observes native SQL completions as well as
synchronous calls: the integrated runtime no longer executes every command
in a subprocess. It preserves returned rows and rejection identity and never
records bind values or result contents. The integrated app with this diagnostic follow-up passes **176 functional
files / 15,437 tests and 41/41 feature outcomes**, plus 12 targeted probe tests.
Targeted Perl::Critic passes. Results are recorded separately in `verification/`.

The secret-scanner exception names one archived manifest and only 64-hex
SHA-256 values under the existing AND-constrained rule. The reported digest
was checked against the actual test file. Before/after scans and a synthetic
non-hash negative control are retained; the negative control still fails.

For the clean integrated confirmation, use an isolated checkout of `756374d`
with its locked dependencies, and a new output directory:

```sh
script/gpforum-carton exec script/benchmark-http-complete \
  --output artifacts/local-thread --workers 8 --worker-clients 16 \
  --scenario member.thread --concurrency 100 \
  --iterations 100 --warmup 10 --duration 6 --repetitions 3 --deadline 900
```

Use `--concurrency 1,10,50,100` for the baseline/isolated original sequence.
The source patches apply to `05f238b`; source digests and exact commands
accompany every arm. Diagnostic sources and runners are archived in
`source/reproducers.json`; the captured diagnostic patch embeds its temporary
output directory, which must be replaced when reproducing elsewhere.
The load generator, application and PostgreSQL share the laptop. The process
monitor can detect concurrent tests and benchmarks, not certify an otherwise
idle machine or establish production capacity.

## CI evidence before the diagnostic/scanner fixes

The `756374d` CI run 42350444682 failed its SQL-observability assertion,
while unit, lint, browser and PostgreSQL 16/17/18 jobs passed. The diagnostic
follow-up above fixes that observed boundary without changing application SQL.
Security run 42350444699 failed on the verified archived digest.
Performance run 42350444679 also records **two transport errors** in the third
5,000-connection health repetition (classified `runner_below_bar`). That failure
is retained in the summary; local forum success must not be presented as proof
that every CI performance gate passed. No health tuning or threshold change is
included. New CI results must be checked for the actual follow-up commit.
