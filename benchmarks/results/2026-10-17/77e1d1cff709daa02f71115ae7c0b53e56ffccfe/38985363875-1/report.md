# GPForum continuous performance evidence

Commit: `77e1d1cff709daa02f71115ae7c0b53e56ffccfe` · mode: **main** · status: **failed**
Run: 38985363875 / attempt 1 · 2026-10-17T00:13:57.196505+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 55ff9335e5050b33511e6271a67d0101a616cc81

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 311.461 | 3.099 | 3.860 | 4.366 | 99.445 / 377.801 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 597.855 | 16.023 | 20.591 | 32.269 | 199.565 / 378.070 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 637.923 | 76.641 | 84.537 | 142.715 | 201.120 / 380.066 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1162.493 | 0.851 | 0.913 | 1.116 | 99.382 / 378.059 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2278.912 | 4.360 | 5.302 | 6.017 | 199.184 / 378.059 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2216.442 | 21.025 | 27.596 | 28.631 | 199.763 / 378.941 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2142.961 | 45.831 | 49.631 | 67.123 | 200.626 / 380.316 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 101.464 | 9.791 | 10.321 | 10.958 | 83.452 / 380.949 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 228.906 | 41.784 | 54.802 | 72.113 | 165.444 / 381.531 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 223.124 | 206.685 | 350.324 | 430.630 | 165.031 / 383.926 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 874.867 | 1.126 | 1.213 | 1.353 | 99.829 / 383.926 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1683.187 | 5.886 | 7.105 | 10.311 | 199.253 / 383.926 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1604.116 | 31.066 | 34.530 | 41.149 | 201.141 / 383.926 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 858.417 | 1.156 | 1.226 | 1.563 | 99.341 / 383.965 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1680.206 | 5.790 | 6.294 | 8.206 | 199.252 / 383.965 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1682.631 | 29.510 | 32.077 | 40.096 | 200.206 / 383.965 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 814.715 | 1.212 | 1.326 | 1.841 | 99.332 / 384.027 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1587.794 | 6.129 | 8.475 | 11.392 | 198.759 / 384.090 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1503.865 | 32.687 | 38.732 | 51.082 | 199.607 / 384.090 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1545.508 | 63.437 | 70.745 | 102.661 | 200.227 / 387.297 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 78.953 | 12.510 | 13.841 | 15.277 | 65.101 / 387.824 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 143.267 | 68.096 | 78.988 | 116.355 | 129.658 / 387.828 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.340 | 360.679 | 596.005 | 662.781 | 132.024 / 387.828 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.869 | 701.977 | 1312.774 | 1365.666 | 130.339 / 387.828 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 879.712 | 1.122 | 1.211 | 1.301 | 99.314 / 387.828 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1654.900 | 5.953 | 6.388 | 8.994 | 199.202 / 387.828 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1582.750 | 30.633 | 33.748 | 48.932 | 200.678 / 387.828 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1544.181 | 62.892 | 71.676 | 101.647 | 201.106 / 387.828 | possible-regression |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1063.025 | 9.139 | 12.144 | 13.841 | 29.256 / 387.828 | stable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 759.278 | 11.689 | 18.114 | 18.850 | 39.635 / 388.172 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2134.176 | 25.214 | 40.911 | 55.680 | 379.310 / 629.672 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2211.041 | 37.353 | 83.633 | 93.805 | 385.583 / 634.266 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 187.871 | 155.921 | 570.183 | 674.918 | 237.493 / 635.398 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 187.627 | 473.099 | 865.063 | 1073.863 | 239.229 / 636.707 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1480.235 | 32.360 | 45.750 | 57.970 | 207.254 / 636.730 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2268.954 | 40.957 | 58.182 | 75.183 | 390.211 / 636.730 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.511 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.458 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.508 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.621 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.101 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.561 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.092 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.121 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.029 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.455 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.589 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.288 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.380 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.110 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.066 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.054 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.409 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.640 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.422 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.572 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.480 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.486 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.409 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.359 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.969 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.426 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.206 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.178 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.010 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.208 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.063 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.075 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.119 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.071 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.062 | — | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 830.527 | 119.319 | 127.982 | 130.222 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1310.690 | 149.404 | 185.963 | 186.108 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +64.4%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -40.0%, p95_ms: -37.9%, p99_ms: -39.7%, requests_per_second: +64.5%, rss_bytes: +0.2% |
| cache_miss | improvement | completed: +55.3%, cpu_percent: -0.1%, duration_seconds: +4.8%, p50_ms: -36.5%, p95_ms: -38.4%, p99_ms: -24.8%, requests_per_second: +55.3%, rss_bytes: +0.3% |
| cache_miss | improvement | completed: +76.7%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: -40.9%, p95_ms: -49.7%, p99_ms: -39.0%, requests_per_second: +76.6%, rss_bytes: +0.3% |
| health_live | confirmed-regression | completed: -4.9%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +5.2%, p95_ms: +5.7%, p99_ms: +23.6%, requests_per_second: -5.1%, rss_bytes: +0.3% |
| health_live | stable | completed: -0.3%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +2.1%, p95_ms: +18.1%, p99_ms: +10.3%, requests_per_second: -1.7%, rss_bytes: +0.3% |
| health_live | stable | completed: -5.5%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -0.5%, p95_ms: +25.5%, p99_ms: +11.6%, requests_per_second: -5.5%, rss_bytes: +0.3% |
| health_live | stable | completed: -3.4%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +4.4%, p95_ms: -0.0%, p99_ms: +2.9%, requests_per_second: -3.5%, rss_bytes: +0.3% |
| home | improvement | completed: +40.0%, cpu_percent: -5.8%, duration_seconds: -0.1%, p50_ms: -31.1%, p95_ms: -33.5%, p99_ms: -32.7%, requests_per_second: +46.2%, rss_bytes: +0.3% |
| home | improvement | completed: +63.0%, cpu_percent: -6.7%, duration_seconds: -0.1%, p50_ms: -39.8%, p95_ms: -29.4%, p99_ms: -41.9%, requests_per_second: +63.2%, rss_bytes: +0.3% |
| home | improvement | completed: +79.9%, cpu_percent: -7.4%, duration_seconds: +0.1%, p50_ms: -40.8%, p95_ms: -42.5%, p99_ms: -36.9%, requests_per_second: +79.4%, rss_bytes: +0.3% |
| categories | stable | completed: -4.0%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +3.6%, p95_ms: +6.8%, p99_ms: +12.5%, requests_per_second: -4.0%, rss_bytes: +0.3% |
| categories | stable | completed: +1.7%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +1.4%, p95_ms: +17.0%, p99_ms: +11.8%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| categories | confirmed-regression | completed: -6.0%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +8.0%, p95_ms: +15.7%, p99_ms: +2.4%, requests_per_second: -6.0%, rss_bytes: +0.3% |
| category | stable | completed: +0.2%, cpu_percent: +0.5%, duration_seconds: +0.2%, p50_ms: -0.2%, p95_ms: +0.2%, p99_ms: +17.3%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| category | stable | completed: -3.2%, cpu_percent: -0.0%, duration_seconds: -4.5%, p50_ms: -2.7%, p95_ms: -13.0%, p99_ms: -18.0%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| category | stable | completed: +1.4%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -1.0%, p95_ms: -7.0%, p99_ms: -13.5%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| thread | stable | completed: -5.4%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +5.9%, p95_ms: +8.4%, p99_ms: +41.2%, requests_per_second: -5.6%, rss_bytes: +0.3% |
| thread | confirmed-regression | completed: -5.1%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +3.3%, p95_ms: +29.1%, p99_ms: +13.2%, requests_per_second: -5.1%, rss_bytes: +0.3% |
| thread | confirmed-regression | completed: -9.7%, cpu_percent: -1.0%, duration_seconds: +0.2%, p50_ms: +9.4%, p95_ms: +21.9%, p99_ms: +14.8%, requests_per_second: -9.6%, rss_bytes: +0.3% |
| thread | possible-regression | completed: -4.4%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +5.0%, p95_ms: +12.3%, p99_ms: +1.5%, requests_per_second: -4.3%, rss_bytes: +0.3% |
| search | improvement | completed: +21.5%, cpu_percent: -6.5%, duration_seconds: +0.0%, p50_ms: -17.5%, p95_ms: -18.1%, p99_ms: -24.3%, requests_per_second: +21.5%, rss_bytes: +0.3% |
| search | improvement | completed: +18.6%, cpu_percent: -7.9%, duration_seconds: +0.0%, p50_ms: -16.9%, p95_ms: -17.7%, p99_ms: -17.6%, requests_per_second: +18.7%, rss_bytes: +0.3% |
| search | improvement | completed: +25.1%, cpu_percent: -4.5%, duration_seconds: +0.0%, p50_ms: -11.2%, p95_ms: -17.4%, p99_ms: -17.8%, requests_per_second: +25.1%, rss_bytes: +0.3% |
| search | improvement | completed: +0.5%, cpu_percent: -7.4%, duration_seconds: -0.1%, p50_ms: -12.6%, p95_ms: -13.6%, p99_ms: -15.5%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +1.2%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: +1.2%, p95_ms: +0.2%, p99_ms: -22.5%, requests_per_second: -0.0%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -5.8%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +2.6%, p95_ms: -0.2%, p99_ms: -3.3%, requests_per_second: -3.4%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -5.7%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +4.3%, p95_ms: +10.1%, p99_ms: +18.7%, requests_per_second: -5.8%, rss_bytes: +0.3% |
| cache_hit | possible-regression | completed: -6.2%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +6.3%, p95_ms: +12.7%, p99_ms: +7.2%, requests_per_second: -6.2%, rss_bytes: +0.3% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +23.9%, duration_seconds: +9.3%, p50_ms: +14.4%, p95_ms: +6.1%, p99_ms: +8.0%, requests_per_second: -9.0%, rss_bytes: +0.3% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +15.0%, duration_seconds: +10.9%, p50_ms: +12.9%, p95_ms: +6.4%, p99_ms: +1.5%, requests_per_second: -9.4%, rss_bytes: +0.3% |
| thread | possible-regression | completed: -9.0%, cpu_percent: -2.3%, duration_seconds: -0.1%, p50_ms: +14.1%, p95_ms: +23.6%, p99_ms: +26.2%, requests_per_second: -12.8%, rss_bytes: +0.3% |
| thread | confirmed-regression | completed: -7.0%, cpu_percent: -0.6%, duration_seconds: -0.3%, p50_ms: +3.9%, p95_ms: +17.2%, p99_ms: -6.0%, requests_per_second: -6.6%, rss_bytes: +0.3% |
| search | improvement | completed: +13.1%, cpu_percent: -6.2%, duration_seconds: -0.3%, p50_ms: -18.9%, p95_ms: -21.2%, p99_ms: -23.2%, requests_per_second: +12.2%, rss_bytes: +0.3% |
| search | improvement | completed: +27.4%, cpu_percent: -10.8%, duration_seconds: -0.3%, p50_ms: -5.8%, p95_ms: -35.2%, p99_ms: -24.3%, requests_per_second: +28.9%, rss_bytes: +0.2% |
| cache_hit | stable | completed: -37.2%, cpu_percent: -44.5%, duration_seconds: +0.0%, p50_ms: +49.2%, p95_ms: +31.0%, p99_ms: +0.3%, requests_per_second: -37.3%, rss_bytes: +0.2% |
| cache_hit | stable | completed: -6.0%, cpu_percent: +2.3%, duration_seconds: -0.2%, p50_ms: +0.7%, p95_ms: -8.4%, p99_ms: -18.0%, requests_per_second: -6.9%, rss_bytes: +0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +17.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.5% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +17.5% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +14.0% |
| sql-plan-readers | confirmed-regression | sql_execution_ms: +33.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.3% |
| sql-plan-readers | possible-regression | sql_execution_ms: +14.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +66.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +10.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.0% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +19.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +13.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -18.2% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +41.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -4.5% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +53.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.6% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +8.5% |
| sql-plan-functions | confirmed-regression | nested_statements: +0.0%, sql_execution_ms: +42.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +11.2% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +18.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -19.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.4% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -32.6% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -5.3%, messages_per_second: +5.6%, p50_ms: -6.3%, p95_ms: -5.9%, p99_ms: -4.9% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -1.7%, messages_per_second: +1.8%, p50_ms: -2.1%, p95_ms: +6.4%, p99_ms: +6.5% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | improvement | completed: +48.3%, cpu_percent: +90.0%, duration_seconds: -0.0%, p50_ms: -22.9%, p95_ms: +5.6%, p99_ms: +9.0%, requests_per_second: +41.9%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | confirmed-regression | completed: +43.1%, cpu_percent: +92.6%, duration_seconds: +0.2%, p50_ms: -41.1%, p95_ms: +18.2%, p99_ms: -8.6%, requests_per_second: +43.1%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | improvement | completed: +53.0%, cpu_percent: +79.9%, duration_seconds: +0.2%, p50_ms: -56.8%, p95_ms: -4.3%, p99_ms: +1.8%, requests_per_second: +51.1%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 100 | improvement | completed: +88.5%, cpu_percent: +83.5%, duration_seconds: +0.3%, p50_ms: -32.6%, p95_ms: -34.1%, p99_ms: -21.4%, requests_per_second: +87.9%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -6.3%, cpu_percent: +3.3%, duration_seconds: +0.1%, p50_ms: +5.6%, p95_ms: +35.6%, p99_ms: +18.5%, requests_per_second: -6.5%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +48.7%, cpu_percent: +94.0%, duration_seconds: +0.0%, p50_ms: -34.9%, p95_ms: -18.8%, p99_ms: -26.0%, requests_per_second: +46.9%, rss_bytes: +64.2% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38985363875)
