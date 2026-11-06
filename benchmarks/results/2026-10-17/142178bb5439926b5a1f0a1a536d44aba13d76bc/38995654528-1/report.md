# GPForum continuous performance evidence

Commit: `142178bb5439926b5a1f0a1a536d44aba13d76bc` · mode: **main** · status: **failed**
Run: 38995654528 / attempt 1 · 2026-10-17T02:38:04.426301+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. ce106f9689d4b3261c08c781141209eee273bb6d

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 498.215 | 1.999 | 2.050 | 2.201 | 99.978 / 378.961 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 995.792 | 9.848 | 14.608 | 17.537 | 199.521 / 379.336 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 975.557 | 51.427 | 57.873 | 94.981 | 201.486 / 381.324 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1811.165 | 0.547 | 0.589 | 0.618 | 99.549 / 378.918 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3602.041 | 2.335 | 3.336 | 4.478 | 199.431 / 378.938 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3724.119 | 13.253 | 14.038 | 21.212 | 199.511 / 379.906 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3606.522 | 27.542 | 36.094 | 39.624 | 199.538 / 381.250 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 207.363 | 4.737 | 5.197 | 6.436 | 78.632 / 381.816 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 421.986 | 23.222 | 31.838 | 50.078 | 154.961 / 382.461 | possible-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 403.199 | 120.384 | 179.711 | 227.662 | 158.722 / 384.906 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1341.714 | 0.735 | 0.788 | 0.896 | 99.513 / 384.906 | possible-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2628.725 | 4.446 | 5.298 | 7.334 | 199.438 / 384.906 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2689.641 | 18.350 | 19.242 | 27.503 | 200.493 / 384.906 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1311.139 | 0.753 | 0.806 | 0.881 | 99.029 / 385.027 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2562.979 | 3.889 | 5.502 | 6.704 | 199.542 / 385.027 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2613.634 | 18.838 | 20.007 | 31.435 | 199.497 / 385.027 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1301.666 | 0.763 | 0.802 | 0.851 | 99.599 / 385.152 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2536.184 | 3.887 | 4.807 | 6.859 | 199.053 / 385.152 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2589.635 | 18.972 | 19.633 | 33.131 | 200.004 / 385.152 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2573.850 | 37.790 | 43.250 | 63.999 | 199.986 / 388.293 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 86.988 | 7.672 | 119.441 | 165.031 | 41.810 / 388.926 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 214.364 | 44.268 | 64.610 | 86.523 | 104.185 / 388.926 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 210.693 | 222.273 | 356.503 | 426.843 | 106.896 / 388.926 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 174.196 | 483.306 | 958.431 | 1026.562 | 106.889 / 388.926 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1336.336 | 0.737 | 0.805 | 0.845 | 99.532 / 388.926 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2617.505 | 3.730 | 4.795 | 7.373 | 199.571 / 388.926 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2673.717 | 18.346 | 18.914 | 30.010 | 199.519 / 388.926 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2684.790 | 36.665 | 39.045 | 60.183 | 199.513 / 388.926 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1723.066 | 5.649 | 7.760 | 8.206 | 21.699 / 388.926 | confirmed-regression |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1332.016 | 6.757 | 10.226 | 11.978 | 27.891 / 389.270 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3538.903 | 15.666 | 24.525 | 31.737 | 385.719 / 631.367 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3446.388 | 23.301 | 49.830 | 64.256 | 383.482 / 636.531 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 262.881 | 128.198 | 375.287 | 549.974 | 187.758 / 637.867 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 222.682 | 339.624 | 710.947 | 829.056 | 155.850 / 639.367 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3634.699 | 10.515 | 28.172 | 35.358 | 383.955 / 639.367 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3627.731 | 18.968 | 48.634 | 64.623 | 387.359 / 639.926 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.432 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.360 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.393 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.435 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.085 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.191 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.759 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.094 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.079 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.023 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.383 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.458 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.223 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.290 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.083 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.049 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.036 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.295 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.536 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.359 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.464 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.385 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.630 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.247 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.283 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.350 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.429 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.169 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.131 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.149 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.045 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.012 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.075 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.077 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.060 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.057 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 1014.573 | 92.344 | 152.984 | 239.247 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 896.760 | 126.658 | 535.405 | 538.671 | — / — | confirmed-regression |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: -1.6%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +2.6%, p95_ms: -0.2%, p99_ms: -0.6%, requests_per_second: -1.6%, rss_bytes: +0.2% |
| cache_miss | confirmed-regression | completed: -2.1%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +1.1%, p95_ms: +21.9%, p99_ms: +1.7%, requests_per_second: -1.6%, rss_bytes: +0.3% |
| cache_miss | possible-regression | completed: -2.9%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +6.0%, p95_ms: +13.2%, p99_ms: +6.6%, requests_per_second: -2.9%, rss_bytes: +0.2% |
| health_live | stable | completed: -0.4%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +0.7%, p95_ms: +0.5%, p99_ms: +1.8%, requests_per_second: -0.4%, rss_bytes: +0.2% |
| health_live | improvement | completed: +0.1%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -14.2%, p95_ms: +4.5%, p99_ms: -5.0%, requests_per_second: +0.1%, rss_bytes: +0.2% |
| health_live | stable | completed: +0.5%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +0.5%, p99_ms: +6.8%, requests_per_second: +0.0%, rss_bytes: +0.2% |
| health_live | stable | completed: -2.5%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +3.3%, p95_ms: +31.1%, p99_ms: -0.7%, requests_per_second: -2.5%, rss_bytes: +0.2% |
| home | stable | completed: -6.1%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: +5.5%, p95_ms: +8.5%, p99_ms: +31.2%, requests_per_second: -6.1%, rss_bytes: +0.2% |
| home | possible-regression | completed: +3.3%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -1.5%, p95_ms: +10.2%, p99_ms: +16.7%, requests_per_second: +2.8%, rss_bytes: +0.2% |
| home | stable | completed: +4.9%, cpu_percent: +1.0%, duration_seconds: -0.0%, p50_ms: -1.5%, p95_ms: +16.9%, p99_ms: +1.5%, requests_per_second: +5.0%, rss_bytes: +0.2% |
| categories | possible-regression | completed: -4.8%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +1.7%, p95_ms: +3.5%, p99_ms: +11.0%, requests_per_second: -2.2%, rss_bytes: +0.2% |
| categories | confirmed-regression | completed: -5.4%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +19.2%, p95_ms: +17.2%, p99_ms: +26.3%, requests_per_second: -0.7%, rss_bytes: +0.2% |
| categories | stable | completed: -1.0%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +1.0%, p95_ms: +3.2%, p99_ms: +0.3%, requests_per_second: -1.0%, rss_bytes: +0.2% |
| category | stable | completed: -2.2%, cpu_percent: -0.5%, duration_seconds: -4.7%, p50_ms: +1.5%, p95_ms: +1.5%, p99_ms: +3.5%, requests_per_second: -1.7%, rss_bytes: +0.2% |
| category | stable | completed: -0.1%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +0.7%, p95_ms: +5.5%, p99_ms: +0.4%, requests_per_second: -0.0%, rss_bytes: +0.2% |
| category | possible-regression | completed: -0.1%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +0.5%, p95_ms: -2.4%, p99_ms: +14.2%, requests_per_second: -0.2%, rss_bytes: +0.2% |
| thread | stable | completed: -0.3%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +1.5%, p95_ms: +0.0%, p99_ms: -11.9%, requests_per_second: -0.3%, rss_bytes: +0.2% |
| thread | stable | completed: +1.0%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: -0.9%, p95_ms: +0.9%, p99_ms: +0.9%, requests_per_second: +0.3%, rss_bytes: +0.2% |
| thread | stable | completed: +0.2%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +1.3%, p95_ms: -2.8%, p99_ms: +3.5%, requests_per_second: -1.2%, rss_bytes: +0.2% |
| thread | possible-regression | completed: -0.7%, cpu_percent: +1.0%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: +10.9%, p99_ms: +1.2%, requests_per_second: -0.6%, rss_bytes: +0.2% |
| search | confirmed-regression | completed: -35.3%, cpu_percent: -24.3%, duration_seconds: -0.0%, p50_ms: +3.7%, p95_ms: +1462.3%, p99_ms: +2007.1%, requests_per_second: -35.3%, rss_bytes: +0.3% |
| search | confirmed-regression | completed: -14.5%, cpu_percent: -5.7%, duration_seconds: +0.1%, p50_ms: +13.6%, p95_ms: +18.9%, p99_ms: +14.9%, requests_per_second: -12.9%, rss_bytes: +0.2% |
| search | confirmed-regression | completed: -14.6%, cpu_percent: -3.6%, duration_seconds: +0.0%, p50_ms: +15.2%, p95_ms: +21.6%, p99_ms: +15.4%, requests_per_second: -14.5%, rss_bytes: +0.2% |
| search | confirmed-regression | completed: -29.9%, cpu_percent: -2.7%, duration_seconds: -0.1%, p50_ms: +23.4%, p95_ms: +39.5%, p99_ms: +33.3%, requests_per_second: -29.9%, rss_bytes: +0.2% |
| cache_hit | stable | completed: -0.4%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +0.4%, p95_ms: +2.2%, p99_ms: +3.9%, requests_per_second: -0.6%, rss_bytes: +0.2% |
| cache_hit | possible-regression | completed: +4.2%, cpu_percent: +0.2%, duration_seconds: +4.9%, p50_ms: -0.7%, p95_ms: +15.0%, p99_ms: +12.9%, requests_per_second: -0.5%, rss_bytes: +0.2% |
| cache_hit | stable | completed: +2.7%, cpu_percent: -0.5%, duration_seconds: +4.9%, p50_ms: +0.7%, p95_ms: -1.4%, p99_ms: +5.2%, requests_per_second: -1.1%, rss_bytes: +0.2% |
| cache_hit | stable | completed: -0.1%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +0.4%, p95_ms: +1.4%, p99_ms: +4.6%, requests_per_second: -0.0%, rss_bytes: +0.2% |
| health_live | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -18.0%, duration_seconds: +7.4%, p50_ms: +15.5%, p95_ms: +4.9%, p99_ms: -0.1%, requests_per_second: -6.3%, rss_bytes: +0.2% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -26.5%, duration_seconds: -8.5%, p50_ms: -6.7%, p95_ms: -8.9%, p99_ms: -5.5%, requests_per_second: +9.2%, rss_bytes: +0.2% |
| thread | stable | completed: -1.0%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +9.1%, p95_ms: -2.1%, p99_ms: -4.3%, requests_per_second: -0.9%, rss_bytes: +0.2% |
| thread | stable | completed: -2.0%, cpu_percent: -1.1%, duration_seconds: +0.3%, p50_ms: +11.3%, p95_ms: -0.8%, p99_ms: +17.8%, requests_per_second: -2.7%, rss_bytes: +0.3% |
| search | stable | completed: -16.6%, cpu_percent: -8.1%, duration_seconds: +0.5%, p50_ms: +8.1%, p95_ms: +9.5%, p99_ms: +16.3%, requests_per_second: -17.1%, rss_bytes: +0.2% |
| search | confirmed-regression | completed: -29.8%, cpu_percent: -27.9%, duration_seconds: +0.1%, p50_ms: +45.7%, p95_ms: +59.9%, p99_ms: +37.1%, requests_per_second: -29.9%, rss_bytes: +0.4% |
| cache_hit | stable | completed: -1.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -23.8%, p95_ms: +13.7%, p99_ms: +22.2%, requests_per_second: -1.7%, rss_bytes: +0.4% |
| cache_hit | stable | completed: -1.5%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -22.1%, p95_ms: +16.8%, p99_ms: +25.7%, requests_per_second: -1.5%, rss_bytes: +0.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.2% |
| sql-plan-readers | possible-regression | sql_execution_ms: +20.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.5% |
| sql-plan-readers | improvement | sql_execution_ms: -14.3% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -25.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -28.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -12.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.8% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -30.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.9% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +23.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +14.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.3% |
| sql-plan-functions | possible-regression | nested_statements: +0.0%, sql_execution_ms: +16.7% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -12.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -14.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +31.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -33.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +18.8% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +7.6%, messages_per_second: -7.0%, p50_ms: +1.5%, p95_ms: +45.1%, p99_ms: +40.7% |
| postgres-dispatch-noop | confirmed-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +94.9%, messages_per_second: -48.7%, p50_ms: +12.7%, p95_ms: +324.2%, p99_ms: +326.4% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +34.7%, cpu_percent: +92.9%, duration_seconds: -0.0%, p50_ms: -17.4%, p95_ms: +24.9%, p99_ms: -4.2%, requests_per_second: +36.7%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | confirmed-regression | completed: +35.2%, cpu_percent: +91.8%, duration_seconds: +0.2%, p50_ms: -38.3%, p95_ms: +15.2%, p99_ms: +0.4%, requests_per_second: +33.9%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | stable | completed: +25.4%, cpu_percent: +75.6%, duration_seconds: +0.4%, p50_ms: -42.3%, p95_ms: +5.3%, p99_ms: +28.8%, requests_per_second: +24.8%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +28.1%, cpu_percent: +45.8%, duration_seconds: +0.2%, p50_ms: -29.7%, p95_ms: -25.8%, p99_ms: -19.2%, requests_per_second: +27.8%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +30.9%, cpu_percent: +92.4%, duration_seconds: -4.6%, p50_ms: -42.7%, p95_ms: +48.9%, p99_ms: +17.8%, requests_per_second: +35.9%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | confirmed-regression | completed: +35.2%, cpu_percent: +94.2%, duration_seconds: +0.1%, p50_ms: -48.3%, p95_ms: +24.6%, p99_ms: +7.4%, requests_per_second: +35.1%, rss_bytes: +64.5% |

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

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38995654528)
