# GPForum continuous performance evidence

Commit: `55ff9335e5050b33511e6271a67d0101a616cc81` · mode: **main** · status: **ok**
Run: 38966686080 / attempt 1 · 2026-10-16T21:04:06.768907+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 4a704a82e610749da755f94fba7f425199c59067

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 189.362 | 5.164 | 6.212 | 7.239 | 99.829 / 376.914 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 384.894 | 25.236 | 33.435 | 42.935 | 199.763 / 376.996 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 361.195 | 129.620 | 168.146 | 233.859 | 201.645 / 378.926 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1225.080 | 0.809 | 0.864 | 0.903 | 99.441 / 376.980 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2317.436 | 4.269 | 4.490 | 5.453 | 198.752 / 376.980 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2345.259 | 21.124 | 21.992 | 25.655 | 200.322 / 377.691 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2221.415 | 43.906 | 49.652 | 65.251 | 201.328 / 379.070 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 69.419 | 14.215 | 15.530 | 16.271 | 88.579 / 379.703 | possible-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 140.246 | 69.362 | 77.657 | 124.031 | 177.367 / 380.234 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.348 | 348.918 | 608.924 | 682.246 | 178.153 / 382.676 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 911.376 | 1.087 | 1.136 | 1.203 | 99.730 / 382.676 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1705.820 | 5.807 | 6.073 | 9.221 | 198.863 / 382.676 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1707.274 | 28.769 | 29.843 | 40.176 | 200.135 / 382.676 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 857.894 | 1.158 | 1.223 | 1.332 | 98.891 / 382.691 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1666.853 | 5.950 | 7.233 | 10.013 | 199.257 / 382.707 | possible-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1658.277 | 29.814 | 34.494 | 46.353 | 199.628 / 382.707 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 862.872 | 1.144 | 1.223 | 1.304 | 99.866 / 382.832 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1673.400 | 5.933 | 6.565 | 10.068 | 199.218 / 382.832 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1663.072 | 29.879 | 31.784 | 44.508 | 201.639 / 382.832 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1615.728 | 60.413 | 62.999 | 101.138 | 201.158 / 386.051 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 64.993 | 15.168 | 16.892 | 20.176 | 69.594 / 386.684 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 120.717 | 81.916 | 95.965 | 141.244 | 140.832 / 386.684 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 99.361 | 406.286 | 721.684 | 805.910 | 138.234 / 386.684 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.311 | 802.845 | 1518.967 | 1615.341 | 140.693 / 386.684 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 880.009 | 1.109 | 1.208 | 1.679 | 99.939 / 386.684 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1712.638 | 5.802 | 6.401 | 9.298 | 198.734 / 386.684 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1679.730 | 29.357 | 30.660 | 41.223 | 200.665 / 386.684 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1645.571 | 59.175 | 63.581 | 94.783 | 201.700 / 386.684 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1168.375 | 7.989 | 11.444 | 12.816 | 23.608 / 386.684 | stable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 838.125 | 10.351 | 17.017 | 18.580 | 34.462 / 386.965 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2446.186 | 22.091 | 33.105 | 44.112 | 388.189 / 627.602 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2368.409 | 35.957 | 71.360 | 99.765 | 387.831 / 632.090 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 167.400 | 192.224 | 723.632 | 878.977 | 253.232 / 633.641 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 145.549 | 501.992 | 1334.674 | 1419.377 | 268.320 / 635.387 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2361.303 | 21.695 | 34.922 | 57.821 | 373.274 / 635.387 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2436.748 | 40.681 | 63.512 | 91.690 | 381.607 / 635.387 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.479 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.445 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.499 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.529 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.094 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.505 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.965 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.086 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.030 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.498 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.534 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.275 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.369 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.092 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.058 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.500 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.453 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.428 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.555 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.459 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.509 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.267 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.366 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.920 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.376 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.187 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.164 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.187 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.020 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.108 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.070 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.092 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 786.327 | 127.351 | 135.970 | 136.919 | — / — | possible-regression |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1288.027 | 152.607 | 174.810 | 174.819 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | confirmed-regression | completed: -5.7%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +4.8%, p95_ms: +19.9%, p99_ms: +23.9%, requests_per_second: -5.7%, rss_bytes: +0.2% |
| cache_miss | stable | completed: -0.8%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -0.5%, p95_ms: +8.3%, p99_ms: +1.5%, requests_per_second: -0.7%, rss_bytes: +0.2% |
| cache_miss | stable | completed: -5.9%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +3.9%, p95_ms: +3.2%, p99_ms: -0.0%, requests_per_second: -5.9%, rss_bytes: +0.2% |
| health_live | stable | completed: +7.0%, cpu_percent: -0.5%, duration_seconds: +4.9%, p50_ms: -2.5%, p95_ms: -3.2%, p99_ms: -5.2%, requests_per_second: +3.3%, rss_bytes: +0.3% |
| health_live | improvement | completed: +1.1%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -4.8%, p95_ms: -16.4%, p99_ms: -7.1%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| health_live | stable | completed: +0.7%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -0.3%, p95_ms: -2.1%, p99_ms: -13.8%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| health_live | stable | completed: -2.2%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: +2.0%, p95_ms: +7.1%, p99_ms: -1.5%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| home | possible-regression | completed: -12.7%, cpu_percent: -0.5%, duration_seconds: +0.2%, p50_ms: +19.1%, p95_ms: +13.5%, p99_ms: -11.2%, requests_per_second: -16.3%, rss_bytes: +0.3% |
| home | stable | completed: -9.4%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +7.9%, p95_ms: -8.9%, p99_ms: +8.9%, requests_per_second: -9.4%, rss_bytes: +0.3% |
| home | confirmed-regression | completed: -16.2%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: +14.4%, p95_ms: +15.3%, p99_ms: +15.8%, requests_per_second: -16.1%, rss_bytes: +0.3% |
| categories | stable | completed: +2.0%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -0.8%, p95_ms: -3.5%, p99_ms: -16.2%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| categories | improvement | completed: -0.1%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -9.2%, p95_ms: -15.0%, p99_ms: +6.0%, requests_per_second: -0.1%, rss_bytes: +0.3% |
| categories | stable | completed: -0.0%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +0.2%, p95_ms: +0.3%, p99_ms: -11.4%, requests_per_second: -0.0%, rss_bytes: +0.3% |
| category | stable | completed: -1.6%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +2.0%, p95_ms: +2.0%, p99_ms: +1.6%, requests_per_second: -1.6%, rss_bytes: +0.3% |
| category | possible-regression | completed: +2.7%, cpu_percent: -0.1%, duration_seconds: +4.8%, p50_ms: +1.7%, p95_ms: +15.3%, p99_ms: +21.3%, requests_per_second: -1.2%, rss_bytes: +0.3% |
| category | stable | completed: -2.3%, cpu_percent: -0.8%, duration_seconds: +0.1%, p50_ms: +0.6%, p95_ms: +7.1%, p99_ms: +15.2%, requests_per_second: -2.3%, rss_bytes: +0.3% |
| thread | improvement | completed: +1.5%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -1.8%, p95_ms: -0.4%, p99_ms: -15.4%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| thread | stable | completed: +0.2%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -0.5%, p95_ms: -6.3%, p99_ms: +0.3%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| thread | stable | completed: -2.2%, cpu_percent: +0.9%, duration_seconds: -0.1%, p50_ms: +4.0%, p95_ms: +1.9%, p99_ms: -3.2%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| thread | stable | completed: -3.1%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: +1.9%, p95_ms: -2.8%, p99_ms: +2.1%, requests_per_second: -3.0%, rss_bytes: +0.4% |
| search | confirmed-regression | completed: -9.7%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +12.8%, p95_ms: +4.8%, p99_ms: +22.1%, requests_per_second: -9.7%, rss_bytes: +0.5% |
| search | stable | completed: -8.3%, cpu_percent: +1.6%, duration_seconds: -0.0%, p50_ms: +4.5%, p95_ms: +9.8%, p99_ms: -0.3%, requests_per_second: -8.5%, rss_bytes: +0.4% |
| search | possible-regression | completed: -20.1%, cpu_percent: -1.4%, duration_seconds: +0.1%, p50_ms: +11.3%, p95_ms: +15.4%, p99_ms: +14.4%, requests_per_second: -20.1%, rss_bytes: +0.4% |
| search | stable | completed: +0.5%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +8.2%, p95_ms: +8.5%, p99_ms: +10.7%, requests_per_second: +0.6%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +0.8%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -2.3%, p95_ms: +1.0%, p99_ms: +25.7%, requests_per_second: +0.7%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +3.4%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: -4.3%, p99_ms: -4.3%, requests_per_second: +0.8%, rss_bytes: +0.4% |
| cache_hit | stable | completed: -3.0%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +2.9%, p95_ms: +3.2%, p99_ms: +3.1%, requests_per_second: -2.9%, rss_bytes: +0.4% |
| cache_hit | stable | completed: -3.0%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +3.1%, p95_ms: +3.4%, p99_ms: +1.9%, requests_per_second: -3.0%, rss_bytes: +0.4% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +4.9%, duration_seconds: +2.4%, p50_ms: -2.9%, p95_ms: +1.0%, p99_ms: -0.0%, requests_per_second: -1.5%, rss_bytes: +0.4% |
| thread | possible-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +2.1%, duration_seconds: +2.6%, p50_ms: +5.8%, p95_ms: +12.2%, p99_ms: +21.1%, requests_per_second: -2.6%, rss_bytes: +0.4% |
| thread | stable | completed: +1.2%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +7.8%, p95_ms: +7.1%, p99_ms: -0.2%, requests_per_second: +1.1%, rss_bytes: +0.4% |
| thread | possible-regression | completed: -1.1%, cpu_percent: -0.4%, duration_seconds: +0.4%, p50_ms: -12.2%, p95_ms: +23.4%, p99_ms: +24.5%, requests_per_second: -1.5%, rss_bytes: +0.5% |
| search | stable | completed: +10.1%, cpu_percent: +17.1%, duration_seconds: +0.3%, p50_ms: -19.1%, p95_ms: +5.0%, p99_ms: +3.7%, requests_per_second: +9.8%, rss_bytes: +0.5% |
| search | stable | completed: -6.6%, cpu_percent: +1.8%, duration_seconds: +0.3%, p50_ms: +11.4%, p95_ms: +31.4%, p99_ms: +18.2%, requests_per_second: -7.8%, rss_bytes: +0.5% |
| cache_hit | stable | completed: +10.5%, cpu_percent: +23.8%, duration_seconds: +0.1%, p50_ms: -17.1%, p95_ms: +17.1%, p99_ms: +52.3%, requests_per_second: +10.5%, rss_bytes: +0.5% |
| cache_hit | stable | completed: -4.0%, cpu_percent: -2.3%, duration_seconds: +0.2%, p50_ms: +13.3%, p95_ms: +4.8%, p99_ms: +16.7%, requests_per_second: -4.3%, rss_bytes: +0.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.6% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +20.0% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -25.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -23.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -9.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -28.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.6% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +25.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -14.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +24.1% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -16.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.2% |
| postgres-dispatch-noop | possible-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +10.2%, messages_per_second: -9.2%, p50_ms: +12.7%, p95_ms: +10.7%, p99_ms: +8.1% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +7.2%, messages_per_second: -6.7%, p50_ms: +5.1%, p95_ms: +5.6%, p99_ms: +4.8% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | improvement | completed: +47.2%, cpu_percent: +92.5%, duration_seconds: +0.2%, p50_ms: -26.1%, p95_ms: +4.2%, p99_ms: -0.9%, requests_per_second: +47.1%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +47.3%, cpu_percent: +92.8%, duration_seconds: +0.5%, p50_ms: -40.5%, p95_ms: +13.3%, p99_ms: -1.4%, requests_per_second: +46.6%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 50 | improvement | completed: +69.3%, cpu_percent: +83.2%, duration_seconds: +0.5%, p50_ms: -52.7%, p95_ms: +0.3%, p99_ms: +9.1%, requests_per_second: +68.5%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +48.7%, cpu_percent: +90.7%, duration_seconds: +0.6%, p50_ms: -37.5%, p95_ms: -12.1%, p99_ms: -12.1%, requests_per_second: +46.6%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +40.6%, cpu_percent: +86.0%, duration_seconds: +0.1%, p50_ms: -26.1%, p95_ms: +13.9%, p99_ms: +40.3%, requests_per_second: +40.6%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +48.5%, cpu_percent: +89.2%, duration_seconds: +0.2%, p50_ms: -31.3%, p95_ms: -0.1%, p99_ms: -3.3%, requests_per_second: +48.1%, rss_bytes: +64.3% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38966686080)
