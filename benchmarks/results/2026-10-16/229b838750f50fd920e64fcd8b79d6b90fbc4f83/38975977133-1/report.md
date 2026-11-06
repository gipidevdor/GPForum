# GPForum continuous performance evidence

Commit: `229b838750f50fd920e64fcd8b79d6b90fbc4f83` · mode: **main** · status: **failed**
Run: 38975977133 / attempt 1 · 2026-10-16T22:29:10.819817+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 55ff9335e5050b33511e6271a67d0101a616cc81

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 157.458 | 6.299 | 7.347 | 9.038 | 99.798 / 375.855 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 354.248 | 31.191 | 35.666 | 42.637 | 200.094 / 376.164 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 345.776 | 135.335 | 178.723 | 244.721 | 201.600 / 378.160 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1168.696 | 0.837 | 0.917 | 1.073 | 98.954 / 375.879 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2226.086 | 4.613 | 5.215 | 6.627 | 198.677 / 375.879 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2193.852 | 22.352 | 24.299 | 33.011 | 200.159 / 376.824 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2108.906 | 45.649 | 52.559 | 69.489 | 199.625 / 378.188 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 65.920 | 15.106 | 16.342 | 17.026 | 88.877 / 378.785 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 130.863 | 71.703 | 95.159 | 142.870 | 177.792 / 379.367 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 111.760 | 391.689 | 647.145 | 721.825 | 177.479 / 381.730 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 788.315 | 1.222 | 1.556 | 1.783 | 100.796 / 381.738 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1610.165 | 6.170 | 6.963 | 10.132 | 199.140 / 381.738 | possible-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1656.926 | 29.852 | 31.409 | 42.303 | 201.148 / 381.738 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 801.297 | 1.224 | 1.426 | 1.859 | 99.357 / 381.766 | possible-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1612.465 | 5.978 | 6.663 | 8.692 | 198.705 / 381.770 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1572.682 | 30.366 | 38.171 | 43.750 | 200.118 / 381.770 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 767.278 | 1.250 | 1.627 | 2.721 | 98.820 / 381.895 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1589.927 | 6.584 | 8.359 | 11.915 | 199.565 / 381.895 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1589.208 | 30.916 | 36.377 | 50.363 | 200.579 / 381.895 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1466.893 | 65.273 | 81.777 | 108.427 | 201.041 / 385.145 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 55.954 | 17.495 | 19.726 | 22.298 | 72.467 / 385.863 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 112.382 | 83.115 | 110.366 | 187.668 | 143.456 / 385.863 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 99.735 | 466.013 | 790.253 | 877.217 | 142.626 / 385.863 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.309 | 924.048 | 1752.850 | 1891.557 | 141.668 / 385.863 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 807.192 | 1.171 | 1.466 | 1.973 | 100.950 / 385.863 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1621.587 | 6.194 | 7.720 | 9.696 | 199.188 / 385.863 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1566.947 | 31.074 | 35.349 | 47.915 | 200.140 / 385.863 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1566.275 | 62.127 | 69.297 | 102.012 | 201.094 / 385.863 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 925.764 | 10.229 | 13.425 | 15.319 | 34.407 / 385.863 | confirmed-regression |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 705.144 | 13.411 | 21.577 | 22.410 | 37.636 / 386.184 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2186.220 | 23.893 | 52.003 | 70.891 | 386.364 / 626.363 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2285.198 | 36.640 | 65.377 | 80.553 | 385.575 / 630.445 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 155.343 | 194.373 | 585.598 | 802.239 | 265.973 / 631.688 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 132.992 | 470.337 | 1276.952 | 1280.404 | 266.481 / 632.625 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1656.900 | 27.897 | 39.912 | 47.511 | 204.530 / 632.625 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2389.909 | 34.921 | 73.684 | 80.253 | 388.185 / 632.660 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.737 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.433 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.563 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.743 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.105 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.759 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.140 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.122 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.097 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.031 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.010 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.574 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.583 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.283 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.371 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.129 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.074 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.062 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.500 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.421 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.467 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.735 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.549 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.531 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.414 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.359 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.984 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.469 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.213 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.194 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.011 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.215 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.061 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.128 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.297 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.073 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.063 | — | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 668.157 | 148.987 | 177.516 | 178.910 | — / — | confirmed-regression |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 990.367 | 204.892 | 235.485 | 241.656 | — / — | confirmed-regression |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | confirmed-regression | completed: -16.9%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +22.0%, p95_ms: +18.3%, p99_ms: +24.9%, requests_per_second: -16.8%, rss_bytes: -0.3% |
| cache_miss | stable | completed: -3.9%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: +23.6%, p95_ms: +6.7%, p99_ms: -0.7%, requests_per_second: -8.0%, rss_bytes: -0.2% |
| cache_miss | stable | completed: -4.3%, cpu_percent: -0.0%, duration_seconds: +0.2%, p50_ms: +4.4%, p95_ms: +6.3%, p99_ms: +4.6%, requests_per_second: -4.3%, rss_bytes: -0.2% |
| health_live | confirmed-regression | completed: -8.3%, cpu_percent: -0.5%, duration_seconds: -4.7%, p50_ms: +3.5%, p95_ms: +6.1%, p99_ms: +18.8%, requests_per_second: -4.6%, rss_bytes: -0.3% |
| health_live | confirmed-regression | completed: -3.9%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +8.1%, p95_ms: +16.1%, p99_ms: +21.5%, requests_per_second: -3.9%, rss_bytes: -0.3% |
| health_live | stable | completed: -6.5%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +5.8%, p95_ms: +10.5%, p99_ms: +28.7%, requests_per_second: -6.5%, rss_bytes: -0.2% |
| health_live | stable | completed: -4.9%, cpu_percent: -0.8%, duration_seconds: +0.1%, p50_ms: +4.0%, p95_ms: +5.9%, p99_ms: +6.5%, requests_per_second: -5.1%, rss_bytes: -0.2% |
| home | stable | completed: -9.0%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +6.3%, p95_ms: +5.2%, p99_ms: +4.6%, requests_per_second: -5.0%, rss_bytes: -0.2% |
| home | confirmed-regression | completed: -6.8%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +3.4%, p95_ms: +22.5%, p99_ms: +15.2%, requests_per_second: -6.7%, rss_bytes: -0.2% |
| home | stable | completed: -10.0%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +12.3%, p95_ms: +6.3%, p99_ms: +5.8%, requests_per_second: -10.1%, rss_bytes: -0.2% |
| categories | confirmed-regression | completed: -13.5%, cpu_percent: +1.1%, duration_seconds: +0.0%, p50_ms: +12.4%, p95_ms: +37.0%, p99_ms: +48.2%, requests_per_second: -13.5%, rss_bytes: -0.2% |
| categories | possible-regression | completed: -5.5%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +6.3%, p95_ms: +14.7%, p99_ms: +9.9%, requests_per_second: -5.6%, rss_bytes: -0.2% |
| categories | stable | completed: -3.0%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +3.8%, p95_ms: +5.2%, p99_ms: +5.3%, requests_per_second: -2.9%, rss_bytes: -0.2% |
| category | possible-regression | completed: -6.5%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +5.7%, p95_ms: +16.6%, p99_ms: +39.6%, requests_per_second: -6.6%, rss_bytes: -0.2% |
| category | stable | completed: -4.5%, cpu_percent: -0.3%, duration_seconds: -4.7%, p50_ms: +0.5%, p95_ms: -7.9%, p99_ms: -13.2%, requests_per_second: -3.3%, rss_bytes: -0.2% |
| category | stable | completed: -5.1%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +1.9%, p95_ms: +10.7%, p99_ms: -5.6%, requests_per_second: -5.2%, rss_bytes: -0.2% |
| thread | possible-regression | completed: -11.1%, cpu_percent: -1.0%, duration_seconds: +0.0%, p50_ms: +9.3%, p95_ms: +33.0%, p99_ms: +108.7%, requests_per_second: -11.1%, rss_bytes: -0.2% |
| thread | confirmed-regression | completed: -4.9%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +11.0%, p95_ms: +27.3%, p99_ms: +18.3%, requests_per_second: -5.0%, rss_bytes: -0.2% |
| thread | stable | completed: -4.4%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +3.5%, p95_ms: +14.5%, p99_ms: +13.2%, requests_per_second: -4.4%, rss_bytes: -0.2% |
| thread | confirmed-regression | completed: -9.2%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +8.0%, p95_ms: +29.8%, p99_ms: +7.2%, requests_per_second: -9.2%, rss_bytes: -0.2% |
| search | stable | completed: -13.8%, cpu_percent: +4.1%, duration_seconds: +0.1%, p50_ms: +15.3%, p95_ms: +16.8%, p99_ms: +10.5%, requests_per_second: -13.9%, rss_bytes: -0.2% |
| search | stable | completed: -7.0%, cpu_percent: +1.9%, duration_seconds: -0.0%, p50_ms: +1.5%, p95_ms: +15.0%, p99_ms: +32.9%, requests_per_second: -6.9%, rss_bytes: -0.2% |
| search | possible-regression | completed: +0.5%, cpu_percent: +3.2%, duration_seconds: +0.0%, p50_ms: +14.7%, p95_ms: +9.5%, p99_ms: +8.8%, requests_per_second: +0.4%, rss_bytes: -0.2% |
| search | confirmed-regression | completed: +0.0%, cpu_percent: +0.7%, duration_seconds: +0.0%, p50_ms: +15.1%, p95_ms: +15.4%, p99_ms: +17.1%, requests_per_second: -0.0%, rss_bytes: -0.2% |
| cache_hit | stable | completed: -8.2%, cpu_percent: +1.0%, duration_seconds: +0.0%, p50_ms: +5.6%, p95_ms: +21.4%, p99_ms: +17.5%, requests_per_second: -8.3%, rss_bytes: -0.2% |
| cache_hit | possible-regression | completed: -7.7%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +6.8%, p95_ms: +20.6%, p99_ms: +4.3%, requests_per_second: -5.3%, rss_bytes: -0.2% |
| cache_hit | confirmed-regression | completed: -6.7%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +5.8%, p95_ms: +15.3%, p99_ms: +16.2%, requests_per_second: -6.7%, rss_bytes: -0.2% |
| cache_hit | stable | completed: -4.7%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +5.0%, p95_ms: +9.0%, p99_ms: +7.6%, requests_per_second: -4.8%, rss_bytes: -0.2% |
| health_live | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +45.7%, duration_seconds: +25.6%, p50_ms: +28.0%, p95_ms: +17.3%, p99_ms: +19.5%, requests_per_second: -20.8%, rss_bytes: -0.2% |
| thread | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +9.2%, duration_seconds: +19.3%, p50_ms: +29.6%, p95_ms: +26.8%, p99_ms: +20.6%, requests_per_second: -15.9%, rss_bytes: -0.2% |
| thread | stable | completed: -10.7%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +8.2%, p95_ms: +57.1%, p99_ms: +60.7%, requests_per_second: -10.6%, rss_bytes: -0.2% |
| thread | stable | completed: -3.8%, cpu_percent: -0.6%, duration_seconds: -0.3%, p50_ms: +1.9%, p95_ms: -8.4%, p99_ms: -19.3%, requests_per_second: -3.5%, rss_bytes: -0.3% |
| search | improvement | completed: -7.4%, cpu_percent: +5.0%, duration_seconds: -0.2%, p50_ms: +1.1%, p95_ms: -19.1%, p99_ms: -8.7%, requests_per_second: -7.2%, rss_bytes: -0.3% |
| search | stable | completed: -9.8%, cpu_percent: -0.7%, duration_seconds: -0.2%, p50_ms: -6.3%, p95_ms: -4.3%, p99_ms: -9.8%, requests_per_second: -8.6%, rss_bytes: -0.4% |
| cache_hit | possible-regression | completed: -29.8%, cpu_percent: -45.2%, duration_seconds: -0.0%, p50_ms: +28.6%, p95_ms: +14.3%, p99_ms: -17.8%, requests_per_second: -29.8%, rss_bytes: -0.4% |
| cache_hit | stable | completed: -2.0%, cpu_percent: +1.7%, duration_seconds: +0.1%, p50_ms: -14.2%, p95_ms: +16.0%, p99_ms: -12.5%, requests_per_second: -1.9%, rss_bytes: -0.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +53.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +12.8% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +40.5% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +11.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +8.9% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +18.4% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +12.8% |
| sql-plan-readers | stable | sql_execution_ms: +33.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.3% |
| sql-plan-readers | confirmed-regression | sql_execution_ms: +42.9% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +66.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +15.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +9.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.5% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +40.2% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +27.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +19.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +9.1% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +32.4% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +19.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +55.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.8% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +18.3% |
| sql-plan-functions | confirmed-regression | nested_statements: +0.0%, sql_execution_ms: +57.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +15.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +15.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +37.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +175.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.3% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -31.5% |
| postgres-dispatch-noop | confirmed-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +17.7%, messages_per_second: -15.0%, p50_ms: +17.0%, p95_ms: +30.6%, p99_ms: +30.7% |
| postgres-dispatch-noop | confirmed-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +30.1%, messages_per_second: -23.1%, p50_ms: +34.3%, p95_ms: +34.7%, p99_ms: +38.2% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | improvement | completed: +37.6%, cpu_percent: +92.6%, duration_seconds: +0.1%, p50_ms: -22.7%, p95_ms: +43.0%, p99_ms: +40.8%, requests_per_second: +37.6%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +56.0%, cpu_percent: +91.8%, duration_seconds: +0.2%, p50_ms: -43.9%, p95_ms: -20.1%, p99_ms: -25.7%, requests_per_second: +55.8%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 50 | improvement | completed: +56.0%, cpu_percent: +86.5%, duration_seconds: +0.3%, p50_ms: -58.3%, p95_ms: -25.9%, p99_ms: -8.5%, requests_per_second: +55.8%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 100 | improvement | completed: +34.2%, cpu_percent: +88.1%, duration_seconds: +0.4%, p50_ms: -49.1%, p95_ms: -27.1%, p99_ms: -32.3%, requests_per_second: +33.9%, rss_bytes: +64.0% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: +5.9%, cpu_percent: +2.2%, duration_seconds: +0.0%, p50_ms: -10.2%, p95_ms: +12.9%, p99_ms: -0.8%, requests_per_second: +5.7%, rss_bytes: +64.0% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +52.7%, cpu_percent: +93.0%, duration_seconds: +0.3%, p50_ms: -43.8%, p95_ms: +6.3%, p99_ms: -21.3%, requests_per_second: +52.6%, rss_bytes: +64.0% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38975977133)
