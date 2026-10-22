# GPForum continuous performance evidence

Commit: `bbe14e7894aea03e20920b4ba4dc28cdfd39ba97` · mode: **main** · status: **failed**
Run: 39000984407 / attempt 1 · 2026-10-17T04:01:43.582736+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: No baseline available.

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 347.416 | 2.847 | 2.969 | 3.677 | 99.508 / 378.863 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 675.958 | 14.648 | 15.204 | 25.507 | 199.821 / 379.270 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 658.542 | 73.767 | 79.565 | 131.359 | 201.292 / 381.270 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1209.768 | 0.820 | 0.868 | 0.964 | 99.535 / 378.941 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2330.491 | 4.288 | 5.111 | 5.797 | 198.864 / 378.941 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2382.732 | 20.797 | 21.589 | 26.674 | 201.343 / 379.938 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2320.264 | 42.773 | 45.520 | 63.533 | 200.766 / 381.297 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 152.918 | 6.491 | 6.737 | 7.461 | 80.126 / 381.863 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 276.633 | 35.916 | 42.825 | 62.007 | 158.579 / 382.461 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 272.845 | 177.824 | 238.858 | 316.062 | 160.917 / 384.895 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 877.317 | 1.142 | 1.184 | 1.260 | 99.458 / 384.895 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1741.698 | 5.636 | 6.137 | 9.635 | 199.307 / 384.895 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1742.237 | 28.384 | 29.833 | 42.168 | 200.252 / 384.895 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 891.696 | 1.114 | 1.168 | 1.369 | 99.415 / 384.926 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1721.171 | 5.755 | 6.029 | 8.071 | 199.395 / 384.926 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1732.882 | 28.526 | 30.580 | 41.661 | 199.667 / 384.926 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 873.632 | 1.135 | 1.192 | 1.234 | 99.979 / 384.988 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1708.502 | 5.867 | 6.202 | 8.060 | 198.884 / 385.051 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1718.857 | 28.615 | 29.417 | 41.178 | 200.250 / 385.051 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1690.953 | 57.387 | 60.152 | 97.912 | 199.859 / 388.188 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 97.156 | 10.028 | 11.549 | 15.558 | 56.201 / 388.719 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 179.772 | 53.201 | 64.716 | 99.414 | 113.348 / 388.719 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 173.714 | 274.937 | 452.800 | 525.458 | 114.192 / 388.719 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 149.603 | 569.739 | 1025.207 | 1103.270 | 115.161 / 388.719 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 913.178 | 1.082 | 1.142 | 1.393 | 99.438 / 388.719 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1738.015 | 5.697 | 6.157 | 7.826 | 199.352 / 388.719 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1742.599 | 28.344 | 29.444 | 40.401 | 200.749 / 388.719 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1721.676 | 56.527 | 59.723 | 90.356 | 201.640 / 388.719 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1272.930 | 7.344 | 10.546 | 10.948 | 23.594 / 388.719 | not-comparable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 961.161 | 8.978 | 14.099 | 18.101 | 31.568 / 389.062 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2492.263 | 20.574 | 30.455 | 47.893 | 385.121 / 631.441 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2500.838 | 31.905 | 64.409 | 88.918 | 387.007 / 635.777 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 213.374 | 124.018 | 570.783 | 822.101 | 216.827 / 637.062 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 219.297 | 386.627 | 809.924 | 956.452 | 224.820 / 638.957 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1741.795 | 28.813 | 36.379 | 47.272 | 205.455 / 638.957 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2558.134 | 37.670 | 55.417 | 74.941 | 388.316 / 638.957 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.491 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.463 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.454 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.618 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.549 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.011 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.102 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.026 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.447 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.562 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.269 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.351 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.092 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.058 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.361 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.489 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.470 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.584 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.484 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.558 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.269 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.343 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.229 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.403 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.186 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.162 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.184 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.054 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.074 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.141 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.054 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.081 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 849.548 | 116.664 | 126.443 | 128.970 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1367.218 | 144.899 | 168.098 | 168.437 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +45.2%, cpu_percent: +92.3%, duration_seconds: +0.1%, p50_ms: -28.1%, p95_ms: +3.5%, p99_ms: +16.3%, requests_per_second: +45.0%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +48.2%, cpu_percent: +93.6%, duration_seconds: +0.5%, p50_ms: -44.4%, p95_ms: +7.1%, p99_ms: -9.2%, requests_per_second: +47.9%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +23.3%, cpu_percent: +89.9%, duration_seconds: +0.3%, p50_ms: -54.9%, p95_ms: +26.1%, p99_ms: +56.5%, requests_per_second: +22.8%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +46.7%, cpu_percent: +95.2%, duration_seconds: +0.1%, p50_ms: -32.1%, p95_ms: -21.0%, p99_ms: -13.3%, requests_per_second: +46.6%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -0.1%, cpu_percent: +2.3%, duration_seconds: +0.0%, p50_ms: +1.7%, p95_ms: +23.6%, p99_ms: +17.0%, requests_per_second: -0.0%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +48.7%, cpu_percent: +92.6%, duration_seconds: +0.2%, p50_ms: -33.4%, p95_ms: -7.2%, p99_ms: -17.1%, requests_per_second: +48.6%, rss_bytes: +64.4% |

## Suite status and skipped tests

- connections_workflow: **failed** — GitHub Actions step outcome: failure
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
- Configured wrk latency budget: 3 seconds.
- Shared runner and load generator share the host; values are comparative evidence, not production capacity.
- wrk uses closed-loop fixed connections and corrected latency histograms; in-flight concurrency is not measured.
- RSS is end-of-sample manager+workers residency, not peak; PostgreSQL and generator resources are separate.
- Cache hits/misses verified by probes; warmed worker-local SSR cache; cache miss uses harness-only expiry policy.
- Only anonymous GETs; migrations, seed and rate-limit accounting write only the dedicated disposable database.

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/performance-data/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/39000984407)
