# GPForum continuous performance evidence

Commit: `014feff6654ae74d9747e5681006934fcd1d3381` · mode: **main** · status: **ok**
Run: 38942867663 / attempt 1 · 2026-10-16T17:51:46.968894+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: No baseline available.

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 307.078 | 3.237 | 3.343 | 3.484 | 99.533 / 380.996 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 607.170 | 16.113 | 22.276 | 26.070 | 200.502 / 381.066 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 593.793 | 80.763 | 99.907 | 155.431 | 201.943 / 382.969 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1777.857 | 0.559 | 0.599 | 0.628 | 99.982 / 381.039 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3573.930 | 2.769 | 2.939 | 4.775 | 199.571 / 381.039 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3657.401 | 13.467 | 14.146 | 19.103 | 199.058 / 381.715 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3609.425 | 27.621 | 30.509 | 40.988 | 200.864 / 383.070 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 129.004 | 7.730 | 8.031 | 8.984 | 85.122 / 383.441 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 232.376 | 40.657 | 58.587 | 90.695 | 170.594 / 384.230 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 234.975 | 207.763 | 329.698 | 410.808 | 171.914 / 386.566 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1315.821 | 0.746 | 0.806 | 0.929 | 100.036 / 386.566 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2602.073 | 3.792 | 4.638 | 6.637 | 199.084 / 386.566 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2619.456 | 18.801 | 19.465 | 29.119 | 200.038 / 386.566 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1265.586 | 0.779 | 0.828 | 0.847 | 99.557 / 386.723 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2519.879 | 3.912 | 4.388 | 6.777 | 199.069 / 386.723 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2559.399 | 19.243 | 20.240 | 31.525 | 200.026 / 386.723 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1273.846 | 0.774 | 0.827 | 0.856 | 99.555 / 386.848 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2483.739 | 3.941 | 4.911 | 6.927 | 199.557 / 386.848 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2559.437 | 19.373 | 20.279 | 33.210 | 199.538 / 386.848 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2511.590 | 38.646 | 41.035 | 66.847 | 200.348 / 389.664 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 101.924 | 9.616 | 10.473 | 18.373 | 61.221 / 390.219 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 187.610 | 52.313 | 72.075 | 96.763 | 123.699 / 390.219 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 172.552 | 266.620 | 462.768 | 526.943 | 123.651 / 390.219 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 149.028 | 544.076 | 980.231 | 1054.764 | 125.462 / 390.219 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1278.550 | 0.787 | 0.815 | 0.948 | 99.026 / 390.219 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2586.300 | 3.827 | 4.715 | 6.685 | 199.544 / 390.219 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2614.060 | 18.869 | 19.742 | 29.570 | 200.520 / 390.219 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2633.536 | 37.365 | 38.917 | 62.004 | 199.977 / 390.219 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1813.337 | 5.096 | 7.276 | 8.651 | 30.972 / 390.219 | not-comparable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1181.264 | 7.042 | 11.303 | 11.489 | 37.932 / 390.492 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3536.604 | 14.823 | 25.785 | 38.709 | 382.683 / 634.508 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3484.421 | 27.383 | 46.731 | 62.211 | 388.448 / 639.137 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 192.210 | 271.120 | 516.790 | 653.735 | 185.857 / 640.957 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 165.990 | 438.021 | 910.118 | 911.455 | 178.048 / 641.098 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3109.639 | 16.955 | 27.382 | 39.388 | 301.591 / 642.195 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3643.728 | 29.739 | 45.422 | 52.216 | 387.894 / 642.527 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.434 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.358 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.379 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.461 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.084 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.203 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.789 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.073 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.385 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.455 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.223 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.317 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.083 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.040 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.308 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.375 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.459 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.462 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.357 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.447 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.236 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.290 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.522 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.158 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.149 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.129 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.148 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.044 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.014 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.067 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.075 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.061 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.066 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 840.531 | 115.671 | 132.750 | 196.535 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1438.753 | 135.296 | 165.437 | 167.642 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +38.3%, cpu_percent: +91.8%, duration_seconds: +0.1%, p50_ms: -23.5%, p95_ms: +27.2%, p99_ms: +16.6%, requests_per_second: +38.2%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +38.9%, cpu_percent: +93.9%, duration_seconds: +0.2%, p50_ms: -29.1%, p95_ms: +13.9%, p99_ms: -6.9%, requests_per_second: +38.7%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +11.3%, cpu_percent: +50.3%, duration_seconds: +0.2%, p50_ms: +1.7%, p95_ms: +11.7%, p99_ms: +24.1%, requests_per_second: +11.4%, rss_bytes: +64.3% |
| search | workers=4 | 2 | 100 | stable | completed: +11.7%, cpu_percent: +41.9%, duration_seconds: +0.3%, p50_ms: -19.5%, p95_ms: -7.2%, p99_ms: -13.6%, requests_per_second: +11.4%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +19.0%, cpu_percent: +50.4%, duration_seconds: +0.1%, p50_ms: -10.1%, p95_ms: +38.7%, p99_ms: +33.2%, requests_per_second: +19.0%, rss_bytes: +64.6% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +38.5%, cpu_percent: +94.0%, duration_seconds: +0.1%, p50_ms: -20.4%, p95_ms: +16.7%, p99_ms: -15.8%, requests_per_second: +38.4%, rss_bytes: +64.7% |

## Suite status and skipped tests

- contracts: **ok** — GitHub Actions step outcome: success
- database: **ok** — See individual gates and artifacts; skipped suites never imply execution
- database-plans-functions: **ok** — Nested function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- database-plans-readers: **ok** — Nested function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- databases: **ok** — GitHub Actions step outcome: success
- hotpaths_workflow: **ok** — GitHub Actions step outcome: success
- http: **ok** — completed planned HTTP measurements
  - {"reason":"read-only anonymous suite; safe durable auth fixture unavailable","scenario":"authenticated"}
  - {"reason":"bounded targeted plan: every endpoint at low load; high concurrency on health/thread/search/cache_hit; extra workers only thread/search/cache_hit","scenario":"full_cartesian_matrix"}
  - {"reason":"bounded PR/main modes; use deep sweep","scenario":"concurrency_250_500"}
  - {"reason":"eight-worker sweep reserved for capable deep runners","scenario":"workers_8"}
  - {"reason":"requires explicit --allow-1000 and capable runner","scenario":"concurrency_1000"}
  - {"reason":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)","scenario":"wrk_upstream_version"}
- http_workflow: **ok** — GitHub Actions step outcome: success
- migrations: **ok** — GitHub Actions step outcome: success
- outbox: **ok** — See individual gates and artifacts; skipped suites never imply execution
- outbox-postgres: **ok** — Owned database is dropped on completion or caught signals; delivery IDs verify losses and duplicates
- pr_comment: **skipped** — Job Summary and artifacts provide PR results with a read-only token; no privileged fork artifact/comment workflow is enabled.
- profiling: **skipped** — Reserved for bounded weekly/manual deep mode
- query-budget: **ok** — Catalog drift is deterministic; N+1 request counts remain blocking in the integration tier
- query-plan-static: **ok** — Required index and forbidden OFFSET checks
- setup: **ok** — GitHub Actions step outcome: success
- sql-functions: **skipped** — Reserved for bounded weekly/manual deep mode
- tools: **ok** — GitHub Actions step outcome: success

## Limits

- Shared runners and a colocated load generator give comparative CI evidence, not production capacity.
- Shared runner and load generator share the host; values are comparative evidence, not production capacity.
- wrk uses closed-loop fixed connections and corrected latency histograms; in-flight concurrency is not measured.
- RSS is end-of-sample manager+workers residency, not peak; PostgreSQL and generator resources are separate.
- Cache hits/misses verified by probes; warmed worker-local SSR cache; cache miss uses harness-only expiry policy.
- Only anonymous GETs; migrations, seed and rate-limit accounting write only the dedicated disposable database.

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38942867663)
