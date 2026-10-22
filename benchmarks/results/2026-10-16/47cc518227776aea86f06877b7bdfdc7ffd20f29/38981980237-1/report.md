# GPForum continuous performance evidence

Commit: `47cc518227776aea86f06877b7bdfdc7ffd20f29` · mode: **main** · status: **failed**
Run: 38981980237 / attempt 1 · 2026-10-16T23:32:59.563941+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 55ff9335e5050b33511e6271a67d0101a616cc81

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 327.475 | 2.968 | 3.510 | 4.230 | 99.828 / 377.918 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 624.843 | 15.421 | 20.345 | 32.607 | 199.651 / 378.184 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 535.277 | 91.559 | 107.876 | 160.187 | 201.599 / 380.164 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1187.117 | 0.835 | 0.897 | 0.988 | 99.451 / 377.926 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2253.733 | 4.466 | 5.290 | 6.918 | 199.190 / 377.926 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2209.012 | 22.541 | 24.285 | 29.207 | 200.137 / 378.820 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2095.436 | 46.951 | 50.375 | 68.450 | 201.115 / 380.203 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 104.957 | 9.331 | 10.331 | 12.790 | 82.958 / 380.523 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 211.376 | 45.838 | 53.345 | 76.885 | 166.913 / 381.453 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 210.695 | 218.231 | 377.085 | 455.738 | 165.757 / 383.832 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 840.946 | 1.180 | 1.240 | 1.328 | 99.817 / 383.832 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1696.450 | 5.821 | 6.357 | 9.443 | 198.709 / 383.832 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1662.536 | 29.706 | 30.897 | 44.409 | 201.089 / 383.832 | possible-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 845.772 | 1.158 | 1.270 | 1.757 | 99.343 / 383.902 | possible-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1656.831 | 5.942 | 6.427 | 9.499 | 199.179 / 383.902 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1623.023 | 30.316 | 32.343 | 39.408 | 200.658 / 383.902 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 840.350 | 1.153 | 1.303 | 6.078 | 99.767 / 384.027 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1597.259 | 6.091 | 6.897 | 10.822 | 199.200 / 384.027 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1581.513 | 31.020 | 35.480 | 46.334 | 200.591 / 384.027 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1491.452 | 63.342 | 73.796 | 105.140 | 201.364 / 387.164 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 72.962 | 13.590 | 14.564 | 16.157 | 65.575 / 387.555 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 145.716 | 67.217 | 73.911 | 118.487 | 129.164 / 387.695 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 136.232 | 353.872 | 593.612 | 685.364 | 128.801 / 387.695 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 124.213 | 682.505 | 1242.193 | 1328.209 | 128.374 / 387.695 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 862.920 | 1.157 | 1.216 | 1.335 | 99.825 / 387.695 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1653.376 | 5.993 | 6.551 | 8.882 | 198.688 / 387.695 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1631.325 | 29.850 | 33.407 | 42.550 | 200.198 / 387.695 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1593.776 | 61.228 | 64.564 | 100.931 | 201.092 / 387.695 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1175.972 | 8.307 | 11.743 | 12.203 | 25.934 / 387.695 | stable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 751.315 | 11.953 | 16.808 | 17.379 | 39.214 / 388.039 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2216.198 | 23.680 | 43.178 | 59.993 | 386.333 / 629.746 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2250.585 | 38.930 | 73.702 | 95.072 | 388.527 / 633.883 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 197.121 | 204.238 | 612.699 | 770.164 | 239.354 / 635.543 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 181.586 | 461.863 | 999.028 | 1044.370 | 238.688 / 637.281 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1935.805 | 29.566 | 41.882 | 49.735 | 304.193 / 637.281 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2321.363 | 39.326 | 77.607 | 90.117 | 387.895 / 637.977 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.499 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.431 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.490 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.587 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.611 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.087 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.121 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.106 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.508 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.585 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.276 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.362 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.099 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.068 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.399 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.460 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.488 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.565 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.423 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.576 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.405 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.365 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.959 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.402 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.231 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.177 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.009 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.203 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.057 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.100 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.108 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.085 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 791.138 | 125.213 | 136.550 | 137.011 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1260.373 | 156.365 | 180.004 | 180.666 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +73.1%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -42.5%, p95_ms: -43.5%, p99_ms: -41.6%, requests_per_second: +72.9%, rss_bytes: +0.3% |
| cache_miss | improvement | completed: +62.4%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -38.9%, p95_ms: -39.2%, p99_ms: -24.1%, requests_per_second: +62.3%, rss_bytes: +0.3% |
| cache_miss | improvement | completed: +48.2%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -29.4%, p95_ms: -35.8%, p99_ms: -31.5%, requests_per_second: +48.2%, rss_bytes: +0.3% |
| health_live | stable | completed: -6.8%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +3.2%, p95_ms: +3.8%, p99_ms: +9.4%, requests_per_second: -3.1%, rss_bytes: +0.3% |
| health_live | possible-regression | completed: -2.8%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +4.6%, p95_ms: +17.8%, p99_ms: +26.9%, requests_per_second: -2.7%, rss_bytes: +0.3% |
| health_live | possible-regression | completed: -5.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +6.7%, p95_ms: +10.4%, p99_ms: +13.8%, requests_per_second: -5.8%, rss_bytes: +0.3% |
| health_live | stable | completed: -5.6%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +6.9%, p95_ms: +1.5%, p99_ms: +4.9%, requests_per_second: -5.7%, rss_bytes: +0.3% |
| home | improvement | completed: +44.8%, cpu_percent: -6.3%, duration_seconds: -0.1%, p50_ms: -34.4%, p95_ms: -33.5%, p99_ms: -21.4%, requests_per_second: +51.2%, rss_bytes: +0.2% |
| home | improvement | completed: +53.0%, cpu_percent: -5.9%, duration_seconds: -0.0%, p50_ms: -33.9%, p95_ms: -31.3%, p99_ms: -38.0%, requests_per_second: +50.7%, rss_bytes: +0.3% |
| home | improvement | completed: +69.9%, cpu_percent: -7.0%, duration_seconds: +0.1%, p50_ms: -37.5%, p95_ms: -38.1%, p99_ms: -33.2%, requests_per_second: +69.4%, rss_bytes: +0.3% |
| categories | stable | completed: -7.7%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +8.6%, p95_ms: +9.2%, p99_ms: +10.4%, requests_per_second: -7.7%, rss_bytes: +0.3% |
| categories | stable | completed: -0.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +0.2%, p95_ms: +4.7%, p99_ms: +2.4%, requests_per_second: -0.5%, rss_bytes: +0.3% |
| categories | possible-regression | completed: -2.6%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +3.3%, p95_ms: +3.5%, p99_ms: +10.5%, requests_per_second: -2.6%, rss_bytes: +0.3% |
| category | possible-regression | completed: -1.3%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +0.0%, p95_ms: +3.8%, p99_ms: +31.9%, requests_per_second: -1.4%, rss_bytes: +0.3% |
| category | stable | completed: -4.5%, cpu_percent: -0.0%, duration_seconds: -4.7%, p50_ms: -0.1%, p95_ms: -11.1%, p99_ms: -5.1%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| category | stable | completed: -2.1%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +1.7%, p95_ms: -6.2%, p99_ms: -15.0%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| thread | possible-regression | completed: -0.4%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +0.8%, p95_ms: +6.5%, p99_ms: +366.1%, requests_per_second: -2.6%, rss_bytes: +0.3% |
| thread | stable | completed: -4.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +2.7%, p95_ms: +5.1%, p99_ms: +7.5%, requests_per_second: -4.5%, rss_bytes: +0.3% |
| thread | possible-regression | completed: -4.9%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +3.8%, p95_ms: +11.6%, p99_ms: +4.1%, requests_per_second: -4.9%, rss_bytes: +0.3% |
| thread | confirmed-regression | completed: -7.7%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +4.8%, p95_ms: +17.1%, p99_ms: +4.0%, requests_per_second: -7.7%, rss_bytes: +0.3% |
| search | stable | completed: +12.3%, cpu_percent: -5.8%, duration_seconds: +0.1%, p50_ms: -10.4%, p95_ms: -13.8%, p99_ms: -19.9%, requests_per_second: +12.3%, rss_bytes: +0.2% |
| search | improvement | completed: +20.7%, cpu_percent: -8.3%, duration_seconds: +0.0%, p50_ms: -17.9%, p95_ms: -23.0%, p99_ms: -16.1%, requests_per_second: +20.7%, rss_bytes: +0.3% |
| search | improvement | completed: +37.2%, cpu_percent: -6.8%, duration_seconds: +0.0%, p50_ms: -12.9%, p95_ms: -17.7%, p99_ms: -15.0%, requests_per_second: +37.1%, rss_bytes: +0.3% |
| search | improvement | completed: +25.1%, cpu_percent: -8.8%, duration_seconds: +0.1%, p50_ms: -15.0%, p95_ms: -18.2%, p99_ms: -17.8%, requests_per_second: +25.1%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -1.6%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +4.3%, p95_ms: +0.7%, p99_ms: -20.5%, requests_per_second: -1.9%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -3.1%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: +3.3%, p95_ms: +2.3%, p99_ms: -4.5%, requests_per_second: -3.5%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -2.8%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +1.7%, p95_ms: +9.0%, p99_ms: +3.2%, requests_per_second: -2.9%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -3.1%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +3.5%, p95_ms: +1.5%, p99_ms: +6.5%, requests_per_second: -3.1%, rss_bytes: +0.3% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +9.9%, duration_seconds: -1.2%, p50_ms: +4.0%, p95_ms: +2.6%, p99_ms: -4.8%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +13.8%, duration_seconds: +11.8%, p50_ms: +15.5%, p95_ms: -1.2%, p99_ms: -6.5%, requests_per_second: -10.4%, rss_bytes: +0.3% |
| thread | possible-regression | completed: -9.5%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: +7.2%, p95_ms: +30.4%, p99_ms: +36.0%, requests_per_second: -9.4%, rss_bytes: +0.3% |
| thread | stable | completed: -5.3%, cpu_percent: +0.2%, duration_seconds: -0.2%, p50_ms: +8.3%, p95_ms: +3.3%, p99_ms: -4.7%, requests_per_second: -5.0%, rss_bytes: +0.3% |
| search | improvement | completed: +17.5%, cpu_percent: -5.5%, duration_seconds: -0.1%, p50_ms: +6.2%, p95_ms: -15.3%, p99_ms: -12.4%, requests_per_second: +17.8%, rss_bytes: +0.3% |
| search | improvement | completed: +23.3%, cpu_percent: -11.0%, duration_seconds: -0.3%, p50_ms: -8.0%, p95_ms: -25.1%, p99_ms: -26.4%, requests_per_second: +24.8%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -15.4%, cpu_percent: -18.5%, duration_seconds: +0.1%, p50_ms: +36.3%, p95_ms: +19.9%, p99_ms: -14.0%, requests_per_second: -18.0%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -5.0%, cpu_percent: +1.6%, duration_seconds: -0.1%, p50_ms: -3.3%, p95_ms: +22.2%, p99_ms: -1.7%, requests_per_second: -4.7%, rss_bytes: +0.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +11.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +9.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +17.5% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +23.3% |
| sql-plan-readers | confirmed-regression | sql_execution_ms: +16.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -10.0% |
| sql-plan-readers | possible-regression | sql_execution_ms: +14.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +66.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +9.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +17.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -20.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.5% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +14.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.2% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +51.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.9% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +23.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.9% |
| sql-plan-functions | confirmed-regression | nested_statements: +0.0%, sql_execution_ms: +28.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +8.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -15.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +30.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.6% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -0.6%, messages_per_second: +0.6%, p50_ms: -1.7%, p95_ms: +0.4%, p99_ms: +0.1% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +2.2%, messages_per_second: -2.1%, p50_ms: +2.5%, p95_ms: +3.0%, p99_ms: +3.3% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +40.1%, cpu_percent: +92.6%, duration_seconds: -0.0%, p50_ms: -23.7%, p95_ms: +21.7%, p99_ms: +29.5%, requests_per_second: +40.1%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +51.1%, cpu_percent: +92.9%, duration_seconds: +0.3%, p50_ms: -38.5%, p95_ms: -0.1%, p99_ms: -9.6%, requests_per_second: +50.9%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 50 | improvement | completed: +45.1%, cpu_percent: +85.8%, duration_seconds: +0.4%, p50_ms: -42.3%, p95_ms: +3.2%, p99_ms: +12.4%, requests_per_second: +44.7%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +46.6%, cpu_percent: +85.9%, duration_seconds: +0.2%, p50_ms: -32.3%, p95_ms: -19.6%, p99_ms: -21.4%, requests_per_second: +46.2%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +22.5%, cpu_percent: +51.9%, duration_seconds: +0.2%, p50_ms: -1.0%, p95_ms: +25.4%, p99_ms: +16.9%, requests_per_second: +18.7%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +45.7%, cpu_percent: +92.9%, duration_seconds: +0.2%, p50_ms: -35.8%, p95_ms: +20.2%, p99_ms: -10.7%, requests_per_second: +45.7%, rss_bytes: +64.6% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38981980237)
