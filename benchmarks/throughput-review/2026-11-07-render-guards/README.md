# Thread rendering and regression guards — 2026-11-07

The first three requested review items are implemented: aggregate snapshot regression protection, independent engagement fragments, and consumer-aware cancellation of queued rendering. Corrected patch: `334e80a97cd89b1488a4453b8e43389a877e57e0`. Integrated with main `b12d284ac72dfff338eff2ebb79bef6c4739310b` as `60c6d8098aa337b1d881413fe867726e7109750a`.

**The corrected patch and integrated code have no new throughput measurement.** Final preflights stopped before measured commands because tests from another project occupied the host. The user then explicitly requested completion without new measurements. No final cells or performance gain are claimed.

## Valid initial comparison, retained for traceability

This earlier measurement compares `a336fdadb122c9d1519de90c5d160df0c4f8d1e9` → `1971623cbb5b4e553bbb53b033327c871fd4d53e`, a superseded implementation.

| Metric at 100 clients | Before | Initial candidate |
| --- | ---: | ---: |
| Throughput median, req/s | 460.0 | 428.8 |
| p95 median, ms | 294.3 | 295.4 |
| Summed app RSS at cell end, MiB | 920.2 | 908.5 |

The observed throughput change was **-6.8%**. Before repetitions: 444.8 / 460.0 / 492.5; initial candidate: 465.5 / 408.4 / 428.8 req/s. The ranges overlap; three repetitions do not establish causality or a stable regression.

This signal prompted a code correction: independently cached components had introduced multiple lookups for an unchanged post. The corrected implementation adds a bounded composed entry: one warmed lookup per post, while changes reuse independent static, like and reaction components. Tests enforce this work count. The initial reports remain valid evidence for their exact revisions, rather than being discarded or combined with unmeasured code.

## Constructive regression protection

* Four aggregate query-plan endpoints cover guest/member and first/deep pages through the same stored-function call builder as production. The deep-page guard selects the actual posts statement within nested snapshot plans. Missing capture is unmeasured. Deliberately dropping only the aggregate cursor fails the new guard while the separate posts endpoint remains green; removing keyset bounds also fails both aggregate deep-page endpoints.
* Real PostgreSQL HTTP tests install durable sessions and verify the intended actor. Independent budgets including live context are 2 SQL commands for normal and HTMX pages, 3 for an author's full page and 5 for the existing permalink path. Limits 1 and 50 must exercise the intended path. The aggregate path may not hide separate head/post/ancillary reads inside a loose budget. These are CI budgets; permalink aggregation was outside this iteration.
* Like and reaction changes reuse static author/avatar/control presentation and the other engagement component. Warmed compositions require one lookup. Components and compositions share the existing 512-entry and 64-KiB-per-entry bounds. Forms, permissions, command identities and CSRF masks remain response-specific; a total-byte budget including keys was outside this iteration.
* Six deterministic cancellation scenarios use the real gate and real child transport, without sleeps. A departing request releases its subscription. Only the last consumer removes queued work; admitted work stays joinable and completes. Partial overlap and stale rejection cleanup cannot erase replacement work. Both HTTP rendering entry points pass the existing request cancellation context.

Production queries continue to use versioned PostgreSQL functions. This patch adds no application SQL, migration or published-function modification. The merge preserves concurrent service/row-access cleanup and the already published upload migration. The category projection and latency-distribution proposals remain outside this iteration.

## Validation

On integrated source `60c6d8098aa337b1d881413fe867726e7109750a`: **539 unit files / 20,555 checks**, **5 affected PostgreSQL files / 1,938 checks**, 15 browser tests, architecture and all owned Perl::Critic checks pass.

Before integration, the corrected patch passed 538 unit files / 20,533 checks, five affected PostgreSQL files / 1,938 checks, 15 browser tests, 11 performance-contract files / 301 checks, formatting and Perl::Critic. A complete earlier integration run passed 173 files / 15,842 checks before the a336fda rebase; the affected PostgreSQL suites and full unit/browser suites were rerun after rebase and again after integration. `validation.json` records exact commands, revision scope and exit statuses. Test durations are operational metadata, not comparative performance results.

## Initial measurement method and limits

Apple M4, 10 cores, 16 GiB; PostgreSQL 18.6, Perl 5.44.0, Mojolicious 9.51, EV/kqueue. Eight Hypnotoad workers, 16 clients per worker; identical durable disposable seed (103 users, 240 threads, 4,800 posts), locked dependencies, PostgreSQL settings and canonical harness. Both measured checkouts were clean. fsync, full_page_writes and synchronous_commit were enabled.

Each initial run used `--workers 8 --worker-clients 16 --concurrency 100 --iterations 100 --warmup 10 --duration 6 --repetitions 3 --deadline 900 --scenario member.thread`. All six cells per run remain in raw JSON: three one-client cells with 100 requests each and three six-second closed-loop 100-client cells. The table uses medians of repetition statistics, not pooled percentiles. Exact commands, timestamps and source metadata remain in `run.json` and each report.

Both measured runs passed correctness with zero errors and zero detected competing test/benchmark processes. The process monitor sampled known patterns every 0.5s; it does not prove absence of OS/background activity. SQL tracing/profiling was disabled. The app, database and generator shared the laptop. A separate LAN instance remained available. This is not exclusive-host or fixed-arrival production capacity evidence, and it makes no comparison with other forum software or later main revisions.

RSS sums the manager and immediate workers at cell end, counts shared pages per process, excludes PostgreSQL/generator and is neither peak RSS nor unique memory. macOS CPU samples are indicative lifetime averages. Source identity, raw reports, monitors and `SHA256SUMS` preserve provenance; bulk logs, HTML and source copies are omitted.
