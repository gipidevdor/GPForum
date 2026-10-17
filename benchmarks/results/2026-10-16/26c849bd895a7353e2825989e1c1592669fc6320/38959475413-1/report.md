# GPForum continuous performance evidence

Commit: `26c849bd895a7353e2825989e1c1592669fc6320` · mode: **main** · status: **failed**
Run: 38959475413 / attempt 1 · 2026-10-16T20:05:05.091403+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 4a704a82e610749da755f94fba7f425199c59067

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 208.744 | 4.749 | 4.961 | 5.592 | 99.989 / 375.957 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 400.837 | 24.531 | 26.314 | 34.465 | 200.351 / 376.066 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 390.560 | 122.663 | 308.445 | 603.158 | 201.326 / 377.781 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1202.379 | 0.821 | 0.883 | 0.937 | 99.530 / 375.961 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2279.574 | 4.351 | 4.529 | 6.074 | 199.402 / 375.961 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2236.404 | 22.105 | 22.770 | 56.560 | 200.336 / 376.594 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2178.400 | 45.139 | 112.060 | 355.838 | 199.394 / 377.922 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 85.966 | 11.390 | 12.382 | 13.835 | 88.495 / 378.262 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 152.358 | 61.869 | 82.769 | 88.284 | 177.078 / 379.082 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 151.138 | 258.892 | 1135.927 | 1672.875 | 178.557 / 381.066 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 883.358 | 1.113 | 1.193 | 1.273 | 99.554 / 381.066 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1707.082 | 5.816 | 6.117 | 8.011 | 199.320 / 381.066 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1669.107 | 29.285 | 33.560 | 89.780 | 201.880 / 381.066 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 855.666 | 1.173 | 1.214 | 1.274 | 99.948 / 381.195 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1659.464 | 5.964 | 6.261 | 8.427 | 199.287 / 381.195 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1624.163 | 30.229 | 31.930 | 100.563 | 200.861 / 381.195 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 859.821 | 1.147 | 1.219 | 1.314 | 100.020 / 381.320 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1646.782 | 5.978 | 7.113 | 9.176 | 199.292 / 381.348 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1621.679 | 30.231 | 31.654 | 90.418 | 200.833 / 381.348 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1606.827 | 60.675 | 210.106 | 505.777 | 201.343 / 383.637 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 77.398 | 12.741 | 14.089 | 15.912 | 68.135 / 384.160 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 133.930 | 71.293 | 89.506 | 106.170 | 136.366 / 384.188 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 123.371 | 312.472 | 1159.366 | 1727.655 | 136.827 / 384.188 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 132.617 | 333.944 | 813.273 | 1725.877 | 136.832 / 384.188 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 876.404 | 1.128 | 1.195 | 1.244 | 99.479 / 384.188 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1707.860 | 5.817 | 6.036 | 7.920 | 199.417 / 384.188 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1678.856 | 29.294 | 33.419 | 79.792 | 200.886 / 384.188 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1665.531 | 58.887 | 202.175 | 483.959 | 201.333 / 384.188 | confirmed-regression |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1196.690 | 7.977 | 10.613 | 11.998 | 24.796 / 384.188 | stable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 877.332 | 10.690 | 15.464 | 17.930 | 33.825 / 384.484 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2499.469 | 19.944 | 26.059 | 33.658 | 385.166 / 625.047 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2475.966 | 37.295 | 47.365 | 82.660 | 385.726 / 628.488 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 170.576 | 256.750 | 387.612 | 636.831 | 259.347 / 629.672 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 174.850 | 471.813 | 1174.843 | 1798.535 | 259.801 / 630.203 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2558.078 | 23.156 | 26.436 | 43.111 | 384.687 / 630.219 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2559.403 | 37.874 | 47.126 | 101.877 | 387.244 / 630.219 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.485 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.438 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.454 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.563 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.096 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.500 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.019 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.082 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.026 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.530 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.563 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.266 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.366 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.089 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.082 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.409 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.450 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.446 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.575 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.457 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.556 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.302 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.351 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.867 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.264 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.185 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.164 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.185 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.054 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.015 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.122 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.084 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 811.797 | 121.664 | 133.631 | 136.252 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1253.669 | 160.220 | 184.487 | 187.024 | — / — | possible-regression |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: +4.0%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -3.6%, p95_ms: -4.2%, p99_ms: -4.3%, requests_per_second: +3.9%, rss_bytes: -0.0% |
| cache_miss | improvement | completed: +3.3%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -3.3%, p95_ms: -14.8%, p99_ms: -18.6%, requests_per_second: +3.4%, rss_bytes: -0.0% |
| cache_miss | confirmed-regression | completed: +1.7%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -1.6%, p95_ms: +89.4%, p99_ms: +157.9%, requests_per_second: +1.7%, rss_bytes: -0.1% |
| health_live | stable | completed: +5.9%, cpu_percent: -0.4%, duration_seconds: +5.0%, p50_ms: -1.1%, p95_ms: -1.1%, p99_ms: -1.7%, requests_per_second: +1.4%, rss_bytes: +0.0% |
| health_live | improvement | completed: -0.6%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -2.9%, p95_ms: -15.7%, p99_ms: +3.5%, requests_per_second: -0.6%, rss_bytes: +0.0% |
| health_live | confirmed-regression | completed: -4.0%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +4.3%, p95_ms: +1.4%, p99_ms: +90.0%, requests_per_second: -3.9%, rss_bytes: +0.0% |
| health_live | confirmed-regression | completed: -4.0%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: +4.8%, p95_ms: +141.6%, p99_ms: +437.0%, requests_per_second: -4.0%, rss_bytes: +0.0% |
| home | improvement | completed: +3.6%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: -4.6%, p95_ms: -9.5%, p99_ms: -24.5%, requests_per_second: +3.6%, rss_bytes: -0.1% |
| home | stable | completed: +3.2%, cpu_percent: -0.5%, duration_seconds: +4.8%, p50_ms: -3.7%, p95_ms: -2.9%, p99_ms: -22.5%, requests_per_second: -1.6%, rss_bytes: +0.0% |
| home | confirmed-regression | completed: +2.0%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: -15.1%, p95_ms: +115.2%, p99_ms: +183.9%, requests_per_second: +2.0%, rss_bytes: -0.1% |
| categories | stable | completed: -1.0%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +1.6%, p95_ms: +1.4%, p99_ms: -11.4%, requests_per_second: -1.1%, rss_bytes: -0.1% |
| categories | improvement | completed: +0.1%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -9.1%, p95_ms: -14.4%, p99_ms: -7.9%, requests_per_second: +0.0%, rss_bytes: -0.1% |
| categories | confirmed-regression | completed: -2.3%, cpu_percent: +0.6%, duration_seconds: -0.0%, p50_ms: +2.0%, p95_ms: +12.8%, p99_ms: +97.9%, requests_per_second: -2.3%, rss_bytes: -0.1% |
| category | stable | completed: -1.8%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: +3.3%, p95_ms: +1.3%, p99_ms: -2.8%, requests_per_second: -1.8%, rss_bytes: -0.1% |
| category | stable | completed: -1.8%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +2.0%, p95_ms: -0.2%, p99_ms: +2.1%, requests_per_second: -1.7%, rss_bytes: -0.1% |
| category | confirmed-regression | completed: -4.3%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +2.0%, p95_ms: -0.8%, p99_ms: +150.0%, requests_per_second: -4.3%, rss_bytes: -0.1% |
| thread | improvement | completed: +1.2%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: -1.5%, p95_ms: -0.7%, p99_ms: -14.8%, requests_per_second: +1.2%, rss_bytes: -0.1% |
| thread | stable | completed: -0.1%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: +1.6%, p99_ms: -8.6%, requests_per_second: -1.3%, rss_bytes: -0.1% |
| thread | confirmed-regression | completed: -4.7%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +5.3%, p95_ms: +1.5%, p99_ms: +96.6%, requests_per_second: -4.6%, rss_bytes: -0.1% |
| thread | confirmed-regression | completed: -3.6%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +2.4%, p95_ms: +224.0%, p99_ms: +410.6%, requests_per_second: -3.6%, rss_bytes: -0.2% |
| search | improvement | completed: +7.6%, cpu_percent: -2.1%, duration_seconds: -0.0%, p50_ms: -5.2%, p95_ms: -12.6%, p99_ms: -3.7%, requests_per_second: +7.6%, rss_bytes: -0.2% |
| search | improvement | completed: +1.5%, cpu_percent: -1.7%, duration_seconds: -0.1%, p50_ms: -9.1%, p95_ms: +2.4%, p99_ms: -25.1%, requests_per_second: +1.5%, rss_bytes: -0.2% |
| search | confirmed-regression | completed: -0.8%, cpu_percent: -2.4%, duration_seconds: +0.0%, p50_ms: -14.4%, p95_ms: +85.3%, p99_ms: +145.2%, requests_per_second: -0.8%, rss_bytes: -0.2% |
| search | confirmed-regression | completed: +34.3%, cpu_percent: -2.1%, duration_seconds: +0.0%, p50_ms: -55.0%, p95_ms: -41.9%, p99_ms: +18.3%, requests_per_second: +34.3%, rss_bytes: -0.2% |
| cache_hit | stable | completed: +0.3%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -0.6%, p95_ms: -0.1%, p99_ms: -6.9%, requests_per_second: +0.3%, rss_bytes: -0.2% |
| cache_hit | improvement | completed: +0.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +0.7%, p95_ms: -9.7%, p99_ms: -18.5%, requests_per_second: +0.5%, rss_bytes: -0.2% |
| cache_hit | confirmed-regression | completed: -3.0%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +2.6%, p95_ms: +12.5%, p99_ms: +99.5%, requests_per_second: -3.0%, rss_bytes: -0.2% |
| cache_hit | confirmed-regression | completed: -1.9%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +2.6%, p95_ms: +228.9%, p99_ms: +420.4%, requests_per_second: -1.9%, rss_bytes: -0.2% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +10.1%, duration_seconds: +0.0%, p50_ms: -3.0%, p95_ms: -6.3%, p99_ms: -6.4%, requests_per_second: +0.9%, rss_bytes: -0.2% |
| thread | possible-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +0.2%, duration_seconds: -1.7%, p50_ms: +9.3%, p95_ms: +2.0%, p99_ms: +16.8%, requests_per_second: +1.9%, rss_bytes: -0.2% |
| thread | improvement | completed: +3.6%, cpu_percent: -0.9%, duration_seconds: +0.0%, p50_ms: -2.7%, p95_ms: -15.7%, p99_ms: -23.9%, requests_per_second: +3.3%, rss_bytes: -0.0% |
| thread | stable | completed: +3.2%, cpu_percent: -1.0%, duration_seconds: +0.1%, p50_ms: -9.0%, p95_ms: -18.1%, p99_ms: +3.2%, requests_per_second: +3.0%, rss_bytes: -0.1% |
| search | improvement | completed: +11.8%, cpu_percent: +19.9%, duration_seconds: -0.1%, p50_ms: +8.1%, p95_ms: -43.8%, p99_ms: -24.9%, requests_per_second: +11.9%, rss_bytes: -0.2% |
| search | stable | completed: +10.7%, cpu_percent: -1.4%, duration_seconds: +0.0%, p50_ms: +4.7%, p95_ms: +15.7%, p99_ms: +49.7%, requests_per_second: +10.8%, rss_bytes: -0.3% |
| cache_hit | improvement | completed: +19.7%, cpu_percent: +27.6%, duration_seconds: +0.1%, p50_ms: -11.5%, p95_ms: -11.3%, p99_ms: +13.6%, requests_per_second: +19.8%, rss_bytes: -0.3% |
| cache_hit | stable | completed: +0.6%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: +5.4%, p95_ms: -22.2%, p99_ms: +29.6%, requests_per_second: +0.5%, rss_bytes: -0.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -5.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.2% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.0% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +13.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -11.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -22.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -9.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -12.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +9.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -19.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -4.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.6% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -4.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -12.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +40.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -4.1% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +6.7%, messages_per_second: -6.3%, p50_ms: +7.6%, p95_ms: +8.8%, p99_ms: +7.6% |
| postgres-dispatch-noop | possible-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +10.1%, messages_per_second: -9.2%, p50_ms: +10.4%, p95_ms: +11.4%, p99_ms: +12.1% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | improvement | completed: +54.7%, cpu_percent: +91.8%, duration_seconds: +0.1%, p50_ms: -34.0%, p95_ms: -17.7%, p99_ms: -62.8%, requests_per_second: +54.1%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | improvement | completed: +54.6%, cpu_percent: +91.6%, duration_seconds: +0.2%, p50_ms: -38.5%, p95_ms: -77.5%, p99_ms: -83.7%, requests_per_second: +54.1%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | improvement | completed: +38.5%, cpu_percent: +89.5%, duration_seconds: +0.2%, p50_ms: -17.8%, p95_ms: -66.6%, p99_ms: -63.1%, requests_per_second: +38.3%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | confirmed-regression | completed: +32.0%, cpu_percent: +89.9%, duration_seconds: +0.2%, p50_ms: +41.3%, p95_ms: +44.5%, p99_ms: +4.2%, requests_per_second: +31.8%, rss_bytes: +64.0% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +52.4%, cpu_percent: +91.5%, duration_seconds: +0.2%, p50_ms: -21.0%, p95_ms: -20.9%, p99_ms: -46.0%, requests_per_second: +52.4%, rss_bytes: +64.0% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +53.9%, cpu_percent: +92.3%, duration_seconds: +0.1%, p50_ms: -35.7%, p95_ms: -76.7%, p99_ms: -78.9%, requests_per_second: +53.7%, rss_bytes: +64.0% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38959475413)
