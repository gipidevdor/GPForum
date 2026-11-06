# GPForum continuous performance evidence

Commit: `b5cc464db7bdcf1a61002d59875c72ce8c8edd2c` · mode: **deep** · status: **ok**
Run: local-apple-m4-20261022T225521Z / attempt 1 · 2026-10-22T23:00:18.839437+00:00

Runner: local-apple-m4-16gib, Darwin/arm64, 10 CPUs, Apple M4.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.44.0","postgres":"18.6 (Homebrew)","wrk":"wrk 4.2.0 [kqueue] Copyright (C) 2012 Will Glozer"}

Dataset: {"counts":{"bookmarks":40,"categories":4,"feed_items":600,"moderation_actions":40,"notifications":120,"permissions":6,"posts":72000,"posts_per_thread":120,"read_states":120,"reports":80,"role_bindings":40,"roles":3,"sessions":40,"subscriptions":40,"threads":600,"users":40},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"70087aabd98bfe86e49cea30c90d786068d53c2470b6d679f9f21e7bf82e1809","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 558.793 | 1.704 | 2.187 | 2.650 | 97.300 / 255.609 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1132.657 | 8.648 | 10.446 | 15.050 | 196.100 / 256.406 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1148.251 | 43.342 | 47.967 | 58.463 | 197.300 / 258.219 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1638.451 | 0.605 | 0.670 | 0.872 | 96.300 / 242.156 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3279.273 | 3.052 | 3.312 | 3.735 | 198.600 / 242.859 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3275.896 | 15.263 | 16.282 | 17.632 | 197.100 / 244.125 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 250.396 | 3.912 | 4.458 | 5.020 | 86.800 / 260.500 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 480.799 | 22.642 | 26.643 | 29.226 | 173.700 / 260.969 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 471.788 | 103.587 | 135.392 | 178.100 | 174.900 / 263.641 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1384.637 | 0.704 | 0.779 | 0.936 | 99.600 / 265.109 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2732.685 | 4.047 | 4.462 | 4.718 | 200.000 / 265.250 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2729.974 | 18.172 | 21.713 | 23.171 | 193.400 / 265.844 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1355.646 | 0.734 | 0.792 | 0.917 | 99.800 / 273.422 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2676.341 | 4.168 | 4.667 | 5.263 | 197.400 / 273.922 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2558.854 | 19.415 | 27.006 | 29.895 | 200.000 / 276.125 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1346.739 | 0.734 | 0.789 | 0.920 | 99.100 / 280.672 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2617.871 | 3.735 | 4.647 | 5.775 | 197.000 / 254.125 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2576.583 | 19.063 | 21.278 | 26.842 | 198.600 / 194.406 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 108.839 | 8.989 | 10.389 | 10.788 | 49.400 / 207.859 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 213.138 | 46.456 | 58.462 | 61.854 | 99.200 / 208.391 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 204.539 | 234.355 | 307.734 | 419.022 | 99.700 / 210.406 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1366.125 | 0.719 | 0.820 | 1.008 | 100.000 / 206.734 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2741.916 | 3.665 | 3.966 | 4.404 | 196.900 / 205.875 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2493.884 | 18.944 | 25.493 | 30.752 | 196.300 / 205.906 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 2429.776 | 3.776 | 5.352 | 7.636 | 50.000 / 206.359 | not-comparable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1547.388 | 5.684 | 9.723 | 11.557 | 25.900 / 208.094 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4607.338 | 9.631 | 14.797 | 20.657 | 388.600 / 396.078 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 387.930 | 106.196 | 198.403 | 247.900 | 202.700 / 356.578 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4996.919 | 9.025 | 16.708 | 18.332 | 386.300 / 347.797 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 8 / 50 | 3 | ok (measured-comparative) | 6976.645 | 6.854 | 12.963 | 16.320 | 762.500 / 634.328 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 8 / 50 | 3 | ok (measured-comparative) | 643.082 | 75.156 | 139.527 | 176.506 | 433.200 / 685.531 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 8 / 50 | 3 | ok (measured-comparative) | 7562.811 | 5.704 | 14.499 | 17.435 | 771.400 / 687.062 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.159 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.475 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.072 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.197 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 5.251 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.710 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.124 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.065 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.012 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.076 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.162 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.077 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.078 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.340 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.084 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.080 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.082 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.050 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.145 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.153 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.801 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.118 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.322 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.041 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.042 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.009 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.065 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.078 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.069 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 2109.278 | 45.949 | 49.257 | 53.019 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 3565.477 | 53.492 | 59.567 | 60.086 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | improvement | completed: +83.1%, cpu_percent: +95.7%, duration_seconds: +2.5%, p50_ms: -49.5%, p95_ms: -30.5%, p99_ms: -23.0%, requests_per_second: +78.8%, rss_bytes: +103.7% |
| search | workers=4 | 2 | 50 | improvement | completed: +89.3%, cpu_percent: +103.3%, duration_seconds: -0.1%, p50_ms: -54.7%, p95_ms: -35.5%, p99_ms: -40.8%, requests_per_second: +89.7%, rss_bytes: +69.5% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +105.3%, cpu_percent: +96.8%, duration_seconds: +2.3%, p50_ms: -52.4%, p95_ms: -34.5%, p99_ms: -40.4%, requests_per_second: +100.4%, rss_bytes: +68.9% |
| thread | workers=8 | 2 | 50 | improvement | completed: +176.6%, cpu_percent: +283.9%, duration_seconds: -0.7%, p50_ms: -64.0%, p95_ms: -39.1%, p99_ms: -39.2%, requests_per_second: +170.8%, rss_bytes: +226.3% |
| search | workers=8 | 2 | 50 | improvement | completed: +212.0%, cpu_percent: +334.5%, duration_seconds: -0.5%, p50_ms: -67.9%, p95_ms: -54.7%, p99_ms: -57.9%, requests_per_second: +214.4%, rss_bytes: +225.8% |
| cache_hit | workers=8 | 2 | 50 | improvement | completed: +209.8%, cpu_percent: +293.0%, duration_seconds: +2.2%, p50_ms: -69.9%, p95_ms: -43.1%, p99_ms: -43.3%, requests_per_second: +203.3%, rss_bytes: +233.7% |

## Suite status and skipped tests

- database: **ok** — See individual gates and artifacts; skipped suites never imply execution
- database-plans-functions: **ok** — Nested function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- database-plans-readers: **ok** — Nested function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- http: **ok** — completed planned HTTP measurements
  - {"reason":"read-only anonymous suite; safe durable auth fixture unavailable","scenario":"authenticated"}
  - {"reason":"bounded targeted plan: every endpoint at low load; high concurrency on health/thread/search/cache_hit; extra workers only thread/search/cache_hit","scenario":"full_cartesian_matrix"}
  - {"reason":"requires explicit --allow-1000 and capable runner","scenario":"concurrency_1000"}
- outbox: **ok** — See individual gates and artifacts; skipped suites never imply execution
- outbox-postgres: **ok** — Full stdout capture recovery; original truncated capture retained separately
- profiling: **skipped** — Reserved for bounded weekly/manual deep mode
- query-budget: **ok** — Catalog drift is deterministic; N+1 request counts remain blocking in the integration tier
- query-plan-static: **ok** — Required index and forbidden OFFSET checks
- sql-functions: **skipped** — Reserved for bounded weekly/manual deep mode

## Limits

- Shared runners and a colocated load generator give comparative CI evidence, not production capacity.
- Local Apple M4 run with ordinary desktop activity; not an isolated production server.
- Source is the exact committed tree; concurrent uncommitted UI changes are excluded.
- Supplementary socket and service corpus suites have distinct datasets and generators; their throughput is not interchangeable.
- Configured wrk latency budget: 3 seconds.
- Shared runner and load generator share the host; values are comparative evidence, not production capacity.
- wrk uses closed-loop fixed connections and corrected latency histograms; in-flight concurrency is not measured.
- RSS is end-of-sample manager+workers residency, not peak; PostgreSQL and generator resources are separate.
- Cache hits/misses verified by probes; warmed worker-local SSR cache; cache miss uses harness-only expiry policy.
- Only anonymous GETs; migrations, seed and rate-limit accounting write only the dedicated disposable database.

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
