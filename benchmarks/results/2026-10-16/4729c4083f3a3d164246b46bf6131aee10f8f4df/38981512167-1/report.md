# GPForum continuous performance evidence

Commit: `4729c4083f3a3d164246b46bf6131aee10f8f4df` · mode: **main** · status: **ok**
Run: 38981512167 / attempt 1 · 2026-10-16T23:27:41.921658+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V45 96-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 0876e8f620d4cd96bc1cd68c1cf8d8de893c7fff

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 661.133 | 1.477 | 1.610 | 1.840 | 99.523 / 377.891 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1296.711 | 7.490 | 11.747 | 16.572 | 199.923 / 378.203 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1276.024 | 39.705 | 50.885 | 71.626 | 200.803 / 380.195 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 2491.802 | 0.388 | 0.446 | 0.597 | 99.539 / 377.879 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 4940.262 | 1.966 | 2.537 | 3.131 | 199.015 / 377.879 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 5033.410 | 10.061 | 10.858 | 13.961 | 199.313 / 378.781 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 4950.451 | 20.445 | 22.650 | 25.644 | 199.953 / 380.145 | possible-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 283.220 | 3.433 | 4.310 | 5.869 | 78.170 / 380.449 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 495.652 | 21.843 | 33.286 | 47.475 | 157.143 / 381.438 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 469.111 | 102.596 | 139.257 | 207.763 | 158.119 / 383.832 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1927.266 | 0.512 | 0.556 | 0.642 | 99.583 / 383.832 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3710.450 | 2.583 | 3.433 | 4.960 | 198.957 / 383.832 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3691.308 | 13.705 | 15.237 | 23.107 | 199.898 / 383.832 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1838.289 | 0.539 | 0.568 | 0.607 | 99.544 / 383.863 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3594.860 | 2.872 | 3.650 | 4.804 | 199.497 / 383.863 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3537.265 | 14.085 | 15.813 | 22.216 | 200.482 / 383.863 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1855.371 | 0.530 | 0.578 | 0.625 | 99.142 / 383.988 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3629.208 | 2.725 | 3.334 | 4.716 | 199.452 / 383.988 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3603.537 | 13.542 | 14.537 | 24.281 | 199.769 / 384.062 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3624.995 | 27.166 | 28.792 | 42.723 | 201.427 / 387.180 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 165.878 | 5.791 | 7.703 | 9.217 | 59.229 / 387.711 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 292.203 | 32.050 | 44.756 | 68.514 | 121.857 / 387.711 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 284.182 | 166.710 | 278.782 | 349.546 | 119.864 / 387.711 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 296.396 | 308.603 | 570.829 | 633.274 | 119.670 / 387.711 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1838.982 | 0.541 | 0.580 | 0.593 | 100.540 / 387.711 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3666.137 | 2.721 | 3.675 | 5.265 | 199.191 / 387.711 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3607.601 | 13.805 | 17.366 | 22.701 | 199.982 / 387.711 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3681.428 | 26.616 | 29.298 | 41.681 | 200.948 / 387.711 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 2470.959 | 3.718 | 5.723 | 5.975 | 20.664 / 387.711 | stable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1551.928 | 6.067 | 8.207 | 10.420 | 30.492 / 388.055 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4937.660 | 7.856 | 19.825 | 26.728 | 384.918 / 629.844 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 4930.176 | 17.839 | 33.836 | 42.793 | 384.350 / 634.484 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 304.453 | 130.995 | 288.052 | 397.936 | 174.682 / 636.301 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 346.395 | 218.296 | 576.939 | 727.953 | 185.782 / 638.766 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3574.811 | 17.688 | 26.769 | 39.084 | 204.570 / 638.805 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 5078.952 | 20.448 | 37.619 | 44.855 | 388.588 / 639.336 | confirmed-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.312 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.277 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.267 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.298 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.072 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.210 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.227 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.075 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.065 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.019 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.268 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.319 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.156 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.232 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.068 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.045 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.030 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.241 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.242 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.243 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.331 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.261 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.300 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.243 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.205 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.709 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.861 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.118 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.099 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.116 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.037 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.011 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.051 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.059 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.033 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 1271.914 | 71.762 | 96.526 | 150.200 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1980.722 | 100.383 | 112.959 | 113.464 | — / — | improvement |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: -6.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +5.3%, p95_ms: +8.1%, p99_ms: +15.8%, requests_per_second: -6.8%, rss_bytes: +0.0% |
| cache_miss | confirmed-regression | completed: -10.4%, cpu_percent: +0.2%, duration_seconds: -4.7%, p50_ms: +7.0%, p95_ms: +31.0%, p99_ms: +19.6%, requests_per_second: -6.2%, rss_bytes: +0.0% |
| cache_miss | confirmed-regression | completed: -7.3%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +11.9%, p95_ms: +29.4%, p99_ms: +9.4%, requests_per_second: -7.3%, rss_bytes: +0.0% |
| health_live | confirmed-regression | completed: -3.4%, cpu_percent: -0.1%, duration_seconds: +5.0%, p50_ms: +3.5%, p95_ms: +7.7%, p99_ms: +36.3%, requests_per_second: -5.0%, rss_bytes: -0.0% |
| health_live | stable | completed: -1.0%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +1.2%, p95_ms: +0.6%, p99_ms: -9.0%, requests_per_second: -1.1%, rss_bytes: -0.0% |
| health_live | stable | completed: -4.2%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: +4.5%, p95_ms: +5.6%, p99_ms: +1.4%, requests_per_second: -4.1%, rss_bytes: -0.0% |
| health_live | possible-regression | completed: -3.5%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +6.9%, p95_ms: +10.7%, p99_ms: -9.4%, requests_per_second: -3.7%, rss_bytes: -0.0% |
| home | confirmed-regression | completed: -9.7%, cpu_percent: +1.1%, duration_seconds: -4.7%, p50_ms: +8.0%, p95_ms: +22.0%, p99_ms: +45.2%, requests_per_second: -5.3%, rss_bytes: -0.0% |
| home | confirmed-regression | completed: -8.5%, cpu_percent: +2.8%, duration_seconds: +0.1%, p50_ms: +16.7%, p95_ms: +44.1%, p99_ms: +36.3%, requests_per_second: -8.6%, rss_bytes: -0.0% |
| home | stable | completed: -11.1%, cpu_percent: +1.8%, duration_seconds: -0.0%, p50_ms: +8.1%, p95_ms: +12.9%, p99_ms: +23.1%, requests_per_second: -6.8%, rss_bytes: -0.0% |
| categories | stable | completed: -2.2%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -2.3%, p95_ms: -3.3%, p99_ms: +5.4%, requests_per_second: +2.6%, rss_bytes: -0.0% |
| categories | stable | completed: +8.4%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -9.0%, p95_ms: -12.1%, p99_ms: +6.3%, requests_per_second: +4.0%, rss_bytes: -0.0% |
| categories | stable | completed: -0.7%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -5.6%, p95_ms: -1.9%, p99_ms: -2.3%, requests_per_second: -0.7%, rss_bytes: -0.0% |
| category | improvement | completed: -0.3%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +0.0%, p95_ms: -0.4%, p99_ms: -13.7%, requests_per_second: -0.3%, rss_bytes: -0.0% |
| category | stable | completed: +2.1%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -3.0%, p95_ms: +3.1%, p99_ms: -6.4%, requests_per_second: +2.1%, rss_bytes: -0.0% |
| category | stable | completed: -2.6%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: -0.2%, p99_ms: -2.0%, requests_per_second: +0.1%, rss_bytes: -0.0% |
| thread | stable | completed: -1.7%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +2.3%, p95_ms: +1.4%, p99_ms: +5.6%, requests_per_second: -1.7%, rss_bytes: -0.0% |
| thread | stable | completed: +0.6%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -10.2%, p95_ms: -3.0%, p99_ms: +3.1%, requests_per_second: +0.7%, rss_bytes: -0.0% |
| thread | stable | completed: +1.1%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +1.0%, p95_ms: -20.7%, p99_ms: -7.9%, requests_per_second: -0.1%, rss_bytes: -0.0% |
| thread | stable | completed: -0.9%, cpu_percent: +0.7%, duration_seconds: +0.0%, p50_ms: +1.8%, p95_ms: -3.1%, p99_ms: -2.0%, requests_per_second: -1.1%, rss_bytes: -0.0% |
| search | confirmed-regression | completed: -14.7%, cpu_percent: +8.1%, duration_seconds: -0.0%, p50_ms: +15.3%, p95_ms: +39.0%, p99_ms: +33.5%, requests_per_second: -14.7%, rss_bytes: -0.0% |
| search | possible-regression | completed: -13.5%, cpu_percent: +8.4%, duration_seconds: -0.0%, p50_ms: +11.3%, p95_ms: +2.8%, p99_ms: +27.5%, requests_per_second: -11.9%, rss_bytes: -0.0% |
| search | confirmed-regression | completed: -15.2%, cpu_percent: +8.1%, duration_seconds: +0.1%, p50_ms: +15.9%, p95_ms: +34.8%, p99_ms: +18.2%, requests_per_second: -15.2%, rss_bytes: -0.0% |
| search | stable | completed: -0.2%, cpu_percent: +9.4%, duration_seconds: -0.0%, p50_ms: +3.4%, p95_ms: +14.8%, p99_ms: +11.8%, requests_per_second: -0.2%, rss_bytes: -0.0% |
| cache_hit | stable | completed: +0.4%, cpu_percent: +0.9%, duration_seconds: +0.0%, p50_ms: +5.9%, p95_ms: +3.0%, p99_ms: -3.1%, requests_per_second: -4.2%, rss_bytes: -0.0% |
| cache_hit | stable | completed: +4.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -4.1%, p95_ms: +7.4%, p99_ms: +13.1%, requests_per_second: -0.4%, rss_bytes: -0.0% |
| cache_hit | stable | completed: -4.6%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +2.0%, p95_ms: +11.7%, p99_ms: +1.0%, requests_per_second: -4.6%, rss_bytes: -0.0% |
| cache_hit | stable | completed: -1.4%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +2.1%, p95_ms: -0.5%, p99_ms: +1.3%, requests_per_second: -1.4%, rss_bytes: -0.0% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -0.0%, duration_seconds: -2.4%, p50_ms: +0.1%, p95_ms: +5.0%, p99_ms: +0.3%, requests_per_second: +1.7%, rss_bytes: -0.0% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -11.2%, duration_seconds: -3.0%, p50_ms: -1.5%, p95_ms: -5.0%, p99_ms: -2.6%, requests_per_second: +1.7%, rss_bytes: -0.0% |
| thread | confirmed-regression | completed: +13.2%, cpu_percent: +30.1%, duration_seconds: -0.1%, p50_ms: -31.3%, p95_ms: +12.7%, p99_ms: +28.7%, requests_per_second: +9.2%, rss_bytes: -0.0% |
| thread | confirmed-regression | completed: -9.1%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: +24.7%, p95_ms: +13.5%, p99_ms: +16.6%, requests_per_second: -8.8%, rss_bytes: -0.1% |
| search | possible-regression | completed: -30.7%, cpu_percent: -11.3%, duration_seconds: +0.1%, p50_ms: +1.2%, p95_ms: +12.6%, p99_ms: +13.5%, requests_per_second: -30.8%, rss_bytes: +0.0% |
| search | confirmed-regression | completed: -22.8%, cpu_percent: -13.0%, duration_seconds: -0.1%, p50_ms: +39.6%, p95_ms: +33.7%, p99_ms: +43.6%, requests_per_second: -22.7%, rss_bytes: +0.1% |
| cache_hit | possible-regression | completed: -23.5%, cpu_percent: -30.4%, duration_seconds: -0.0%, p50_ms: +19.9%, p95_ms: +47.5%, p99_ms: +82.0%, requests_per_second: -21.4%, rss_bytes: +0.1% |
| cache_hit | confirmed-regression | completed: -9.1%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +14.2%, p95_ms: +28.5%, p99_ms: +30.2%, requests_per_second: -9.1%, rss_bytes: +0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.6% |
| sql-plan-readers | possible-regression | sql_execution_ms: +20.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.6% |
| sql-plan-readers | possible-regression | sql_execution_ms: +25.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.6% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +16.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -6.8% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +21.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +11.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -8.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.5% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +63.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -25.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -16.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -13.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -19.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +0.2%, messages_per_second: -0.2%, p50_ms: -6.9%, p95_ms: +6.7%, p99_ms: +25.6% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +6.2%, messages_per_second: -5.8%, p50_ms: +8.6%, p95_ms: -29.7%, p99_ms: -29.8% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +37.5%, cpu_percent: +92.7%, duration_seconds: -0.1%, p50_ms: -42.0%, p95_ms: +36.4%, p99_ms: +10.1%, requests_per_second: +37.0%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | confirmed-regression | completed: +36.0%, cpu_percent: +90.8%, duration_seconds: +0.1%, p50_ms: -34.3%, p95_ms: +17.5%, p99_ms: +0.2%, requests_per_second: +36.0%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | stable | completed: +7.4%, cpu_percent: +45.7%, duration_seconds: +0.2%, p50_ms: -21.4%, p95_ms: +3.3%, p99_ms: +13.8%, requests_per_second: +7.1%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +16.8%, cpu_percent: +55.2%, duration_seconds: +0.0%, p50_ms: -29.3%, p95_ms: +1.1%, p99_ms: +15.0%, requests_per_second: +16.9%, rss_bytes: +64.8% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -1.0%, cpu_percent: +2.3%, duration_seconds: -0.0%, p50_ms: +28.1%, p95_ms: +54.1%, p99_ms: +72.2%, requests_per_second: -0.9%, rss_bytes: +64.8% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +38.0%, cpu_percent: +93.4%, duration_seconds: +0.0%, p50_ms: -23.2%, p95_ms: +28.4%, p99_ms: +7.6%, requests_per_second: +38.0%, rss_bytes: +64.9% |

## Suite status and skipped tests

- connections_workflow: **ok** — GitHub Actions step outcome: success
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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38981512167)
