# Throughput review — 2026-11-07

Application comparison: `756374d9720764e4dfc468e45df3c8fb3d469961` → `2ade1f06b4ea65a591161551c00f9d6abca7b71b`. The audit's B01–B14 are addressed below, with **B06 (GlifiStore/shared cache) excluded**. This is evidence for these exact revisions, not a measurement of later thread-page work.

## Dedicated authenticated thread

Apple M4, 10 cores, 16 GiB; PostgreSQL 18.6, Perl 5.44.0, Mojolicious 9.51, EV/kqueue. Eight Hypnotoad workers, 16 connections per worker, 100 independently authenticated sessions; the same durable disposable seed (103 users, 240 threads, 4,800 posts), harness and locked dependencies. Three repetitions per revision.

| Metric | Before | After |
| --- | ---: | ---: |
| Throughput median, req/s | 425.5 | 438.4 |
| p95 median, ms | 293.3 | 293.3 |
| Summed app RSS at cell end, MiB | 874.0 | 883.9 |

The observed throughput change is **+3.0%**; p95 is effectively unchanged and RSS is **+1.1%**. Before repetitions: 425.5 / 430.3 / 423.9 req/s; after: 423.7 / 438.4 / 441.3 req/s. The ranges overlap. This small sample does **not** establish a stable speedup or meet the earlier 450 req/s median target. No 1,000 req/s or cross-forum claim follows from it.

## Guest paths and workload order

The unchanged harness runs guest paths at **one client**, even with `--concurrency 100`. The following are sequential latency measurements, not saturated guest capacity. All repetitions and the authenticated results from that selected-scenario sequence remain in the raw data; its authenticated medians (317.0 → 426.6 req/s) are more variable than the dedicated run and must not replace the dedicated comparison.

| Guest path | Before p95 median, ms | After p95 median, ms |
| --- | ---: | ---: |
| guest.home | 9.83 | 3.20 |
| guest.thread | 4.54 | 3.52 |
| guest.search | 16.32 | 8.76 |

## Structural changes and functional evidence

| Audit | Change |
| --- | --- |
| B01–B02 | Versioned PostgreSQL request context combines durable session validation, viewer and fresh configuration/epoch. Unchanged encrypted settings are omitted. Bundled static assets and liveness bypass database preparation. Published 2045/2046 remain byte-for-byte intact; 2047 adds the new entry points. |
| B03 | Guest home full-page cache uses the existing eligibility, privacy epoch, tags and conditional-response rules. Signed-in, fragment and JSON responses retain their own behavior. |
| B04–B05 | Rendering uses progressive bounded LRU eviction and coalesces concurrent misses; its child admission lane is separated from blocking services. Children do not dirty the inherited rendering memo. |
| B06 | Excluded: no changes to the GlifiStore/shared-cache implementation. |
| B07 | One persistent child and descriptor per bounded file transfer; backpressure, range/HEAD/304 and disconnect cleanup remain covered. |
| B08–B09 | Queue admission observes request cancellation/deadlines; abandoned waiting jobs release residency immediately. Queue/run counters are exposed separately. Admitted writes are neither interrupted nor replayed. SQL concurrency stays at the existing bounded default; no unmeasured pool-size increase. |
| B10 | Reuse a lease only after a mapped clean business refusal or confirmed rollback and no command in flight; uncertain/transport failures still retire it. |
| B11 | Cache required-attribute metadata and reuse stateless services within a request; SQL API roots are weakly memoized by schema. |
| B12 | Bounded process-local search-result cache (64 entries, 5s, at most 64 KiB payload each), complete scope plus fresh privacy epoch in keys, independent returned copies. Hybrid embedding overlaps lexical reads without retaining an idle SQL transaction. Rate limiting still runs on cache hits. |
| B13 | Background outbox dispatch uses bounded aggregate lanes, preserving per-aggregate order within a claimed batch and lease/ack/retry checks. Canonical request writes retain their direct path. |
| B14 | Keyset pages bound fanout candidates and use a covering partial index. Existing home/category/search/thread nested-plan gates pass; the retained report includes deep pages with 3,000 extra posts and 1,500 extra threads. Public fanout result arrays remain proportional to recipients. |

Observed SQL commands on warmed real HTTP requests, in a **separate instrumented operation-count probe**:

| Path | Before | After |
| --- | ---: | ---: |
| Signed-in thread / HTMX thread | 6 | 4 |
| Guest home hit | 3 | 1 |
| Guest search hit | 6 | 2 |
| Bundled static asset | 1 | 0 |

Guest cached thread/category still read a fresh configuration/privacy epoch once. A 1 MiB file with metadata and four 256 KiB chunks needs **one child instead of five**. These counts are not throughput measurements. Outbox/fanout/hybrid-search improvements have functional evidence here; no end-to-end capacity gain is claimed for them.

## Validation and measurement limits

Final unit suite: **537 files / 20,426 checks**. Instrumented functional/PostgreSQL suite: **179 files / 15,487 checks**, **41/41 features**. Browser: **15 tests**; JavaScript: **101 tests**; performance evidence contracts: **11 files / 301 checks**. Syntax, formatting, Perl::Critic, architecture policies and ADR index pass. The database checks include fresh installation, 2046→2047 upgrade, schema snapshot, previous-release signatures, least privilege, cancellation, lease refusal/rollback, fanout equivalence and real parallel outbox. Initial stale API expectations were corrected and complete final runs pass. Normal platform/prerequisite skips remain; this is not certification of every OS/PostgreSQL major.

All four accepted runs have **zero detected competing tests/benchmarks** and **zero errors** across **32,869 measured responses**. One earlier run overlapped a six-second test and was excluded completely. The monitor samples processes every 0.5s; it does not prove absence of all background OS activity. SQL tracing/profiling is disabled for timed runs. Raw JSON, exact commands, process monitors, source/harness identity and checksums are retained; no bulk logs, HTML or source copies are added.

Statistics are medians of three repetition statistics, not pooled percentiles. Warmup10, iterations100, duration6s, repetitions3, deadline900; see each `run.json`. The canonical run selects only `member.thread`; the sequence additionally selects `guest.home`, `guest.thread`, `guest.search`. One-client cells use 100 requests; concurrent cells use the six-second closed-loop workload. The app, database and generator share the laptop, so these are not fixed-arrival production SLOs. The revisions also include other async/UI changes; gains are not isolated per audit point.

RSS sums the manager and immediate workers at the end of each cell, including shared pages counted per process. It is not peak RSS or unique memory and excludes PostgreSQL/generator. CPU on macOS comes from the indicative `ps` lifetime average; no precise per-core efficiency claim is made.
