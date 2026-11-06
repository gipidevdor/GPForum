# GPForum continuous performance evidence

Commit: `0d3ea9e5adad0235fa80698ca02a274d0203b806` · mode: **main** · status: **failed**
Run: 38968378307 / attempt 1 · 2026-10-16T21:18:24.124880+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 55ff9335e5050b33511e6271a67d0101a616cc81

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 210.445 | 4.708 | 4.885 | 5.375 | 99.545 / 375.336 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 408.923 | 24.024 | 27.994 | 38.282 | 199.420 / 375.652 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 395.268 | 120.950 | 160.003 | 225.652 | 202.197 / 377.617 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1241.928 | 0.801 | 0.842 | 0.885 | 99.466 / 375.566 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2386.304 | 4.133 | 4.373 | 5.638 | 199.087 / 375.566 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2407.346 | 20.506 | 21.632 | 23.624 | 200.357 / 376.492 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2368.266 | 40.893 | 46.433 | 61.597 | 200.894 / 377.832 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 87.352 | 11.347 | 11.936 | 13.182 | 88.509 / 378.199 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 163.633 | 57.786 | 74.748 | 105.142 | 177.864 / 379.035 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 153.589 | 297.356 | 511.417 | 602.916 | 178.593 / 381.461 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 920.614 | 1.074 | 1.136 | 1.177 | 99.496 / 381.465 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1783.258 | 5.564 | 5.810 | 8.451 | 199.361 / 381.465 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1800.293 | 27.355 | 28.914 | 40.732 | 200.781 / 381.465 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 895.835 | 1.103 | 1.177 | 1.253 | 99.968 / 381.480 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1724.882 | 5.664 | 6.319 | 7.726 | 198.871 / 381.496 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1731.980 | 28.282 | 30.990 | 42.250 | 200.727 / 381.496 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 880.016 | 1.116 | 1.190 | 1.251 | 99.386 / 381.559 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1736.648 | 5.814 | 6.145 | 9.902 | 199.713 / 381.621 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1665.932 | 28.562 | 34.703 | 44.658 | 200.173 / 381.652 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1692.407 | 57.841 | 60.090 | 96.789 | 201.136 / 384.852 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 75.703 | 12.851 | 14.966 | 16.619 | 67.731 / 385.410 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 139.862 | 68.865 | 87.627 | 123.988 | 136.219 / 385.492 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.194 | 340.391 | 594.770 | 660.660 | 135.850 / 385.492 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 121.131 | 655.438 | 1354.174 | 1486.666 | 137.312 / 385.492 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 901.608 | 1.088 | 1.166 | 1.458 | 100.365 / 385.492 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1778.914 | 5.510 | 5.980 | 8.715 | 199.307 / 385.492 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1815.472 | 27.136 | 28.261 | 36.142 | 199.668 / 385.492 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1794.138 | 55.067 | 58.621 | 91.214 | 202.301 / 385.492 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1251.142 | 7.391 | 9.675 | 11.598 | 25.977 / 385.492 | improvement |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 876.194 | 10.704 | 15.996 | 16.324 | 32.332 / 385.820 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2507.908 | 19.151 | 31.424 | 48.833 | 383.989 / 625.621 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2500.824 | 39.020 | 75.234 | 90.154 | 389.033 / 629.875 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 169.394 | 171.126 | 617.604 | 759.937 | 253.328 / 631.422 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 166.231 | 407.648 | 1391.883 | 1666.139 | 261.160 / 633.516 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1726.474 | 28.629 | 45.047 | 51.476 | 217.154 / 633.516 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2611.987 | 35.907 | 58.705 | 72.748 | 390.571 / 633.516 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.479 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.458 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.475 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.635 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.113 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.502 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.995 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.102 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.081 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.437 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.557 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.266 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.376 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.089 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.062 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.382 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.582 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.452 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.586 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.467 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.572 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.271 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.358 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.983 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.391 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.187 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.164 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.186 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.021 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.123 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.142 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.065 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 818.327 | 123.312 | 128.048 | 129.664 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1308.770 | 151.445 | 162.382 | 163.285 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +11.1%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -8.8%, p95_ms: -21.4%, p99_ms: -25.7%, requests_per_second: +11.1%, rss_bytes: -0.4% |
| cache_miss | improvement | completed: +6.2%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -4.8%, p95_ms: -16.3%, p99_ms: -10.8%, requests_per_second: +6.2%, rss_bytes: -0.4% |
| cache_miss | stable | completed: +9.5%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -6.7%, p95_ms: -4.8%, p99_ms: -3.5%, requests_per_second: +9.4%, rss_bytes: -0.3% |
| health_live | stable | completed: +2.2%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -1.0%, p95_ms: -2.5%, p99_ms: -2.0%, requests_per_second: +1.4%, rss_bytes: -0.4% |
| health_live | stable | completed: +3.0%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -3.2%, p95_ms: -2.6%, p99_ms: +3.4%, requests_per_second: +3.0%, rss_bytes: -0.4% |
| health_live | stable | completed: +2.6%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -2.9%, p95_ms: -1.6%, p99_ms: -7.9%, requests_per_second: +2.6%, rss_bytes: -0.3% |
| health_live | stable | completed: +6.7%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -6.9%, p95_ms: -6.5%, p99_ms: -5.6%, requests_per_second: +6.6%, rss_bytes: -0.3% |
| home | improvement | completed: +20.7%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -20.2%, p95_ms: -23.1%, p99_ms: -19.0%, requests_per_second: +25.8%, rss_bytes: -0.4% |
| home | improvement | completed: +16.7%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: -16.7%, p95_ms: -3.7%, p99_ms: -15.2%, requests_per_second: +16.7%, rss_bytes: -0.3% |
| home | improvement | completed: +23.7%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -14.8%, p95_ms: -16.0%, p99_ms: -11.6%, requests_per_second: +23.5%, rss_bytes: -0.3% |
| categories | stable | completed: +1.2%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -1.2%, p95_ms: +0.0%, p99_ms: -2.2%, requests_per_second: +1.0%, rss_bytes: -0.3% |
| categories | stable | completed: +4.5%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -4.2%, p95_ms: -4.3%, p99_ms: -8.4%, requests_per_second: +4.5%, rss_bytes: -0.3% |
| categories | stable | completed: +5.4%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -4.9%, p95_ms: -3.1%, p99_ms: +1.4%, requests_per_second: +5.4%, rss_bytes: -0.3% |
| category | stable | completed: +4.5%, cpu_percent: +1.1%, duration_seconds: +0.1%, p50_ms: -4.8%, p95_ms: -3.8%, p99_ms: -5.9%, requests_per_second: +4.4%, rss_bytes: -0.3% |
| category | improvement | completed: +1.1%, cpu_percent: -0.2%, duration_seconds: -4.7%, p50_ms: -4.8%, p95_ms: -12.6%, p99_ms: -22.8%, requests_per_second: +3.5%, rss_bytes: -0.3% |
| category | improvement | completed: +4.5%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: -5.1%, p95_ms: -10.2%, p99_ms: -8.9%, requests_per_second: +4.4%, rss_bytes: -0.3% |
| thread | stable | completed: +2.0%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -2.4%, p95_ms: -2.7%, p99_ms: -4.1%, requests_per_second: +2.0%, rss_bytes: -0.3% |
| thread | stable | completed: +3.9%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -2.0%, p95_ms: -6.4%, p99_ms: -1.6%, requests_per_second: +3.8%, rss_bytes: -0.3% |
| thread | stable | completed: +0.1%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: -4.4%, p95_ms: +9.2%, p99_ms: +0.3%, requests_per_second: +0.2%, rss_bytes: -0.3% |
| thread | stable | completed: +4.8%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -4.3%, p95_ms: -4.6%, p99_ms: -4.3%, requests_per_second: +4.7%, rss_bytes: -0.3% |
| search | stable | completed: +20.0%, cpu_percent: -2.7%, duration_seconds: +0.1%, p50_ms: -15.3%, p95_ms: -11.4%, p99_ms: -17.6%, requests_per_second: +16.5%, rss_bytes: -0.3% |
| search | improvement | completed: +15.7%, cpu_percent: -3.3%, duration_seconds: -0.0%, p50_ms: -15.9%, p95_ms: -8.7%, p99_ms: -12.2%, requests_per_second: +15.9%, rss_bytes: -0.3% |
| search | improvement | completed: +25.1%, cpu_percent: -1.7%, duration_seconds: +0.0%, p50_ms: -16.2%, p95_ms: -17.6%, p99_ms: -18.0%, requests_per_second: +25.0%, rss_bytes: -0.3% |
| search | improvement | completed: +22.1%, cpu_percent: -2.4%, duration_seconds: +0.0%, p50_ms: -18.4%, p95_ms: -10.8%, p99_ms: -8.0%, requests_per_second: +22.0%, rss_bytes: -0.3% |
| cache_hit | stable | completed: +2.4%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -1.9%, p95_ms: -3.5%, p99_ms: -13.2%, requests_per_second: +2.5%, rss_bytes: -0.3% |
| cache_hit | stable | completed: +1.3%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -5.0%, p95_ms: -6.6%, p99_ms: -6.3%, requests_per_second: +3.9%, rss_bytes: -0.3% |
| cache_hit | stable | completed: +8.4%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -7.6%, p95_ms: -7.8%, p99_ms: -12.3%, requests_per_second: +8.1%, rss_bytes: -0.3% |
| cache_hit | stable | completed: +9.0%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -6.9%, p95_ms: -7.8%, p99_ms: -3.8%, requests_per_second: +9.0%, rss_bytes: -0.3% |
| health_live | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +10.0%, duration_seconds: -7.0%, p50_ms: -7.5%, p95_ms: -15.5%, p99_ms: -9.5%, requests_per_second: +7.1%, rss_bytes: -0.3% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -6.2%, duration_seconds: -4.2%, p50_ms: +3.4%, p95_ms: -6.0%, p99_ms: -12.1%, requests_per_second: +4.5%, rss_bytes: -0.3% |
| thread | stable | completed: +2.4%, cpu_percent: -1.1%, duration_seconds: -0.1%, p50_ms: -13.3%, p95_ms: -5.1%, p99_ms: +10.7%, requests_per_second: +2.5%, rss_bytes: -0.3% |
| thread | stable | completed: +5.3%, cpu_percent: +0.3%, duration_seconds: -0.4%, p50_ms: +8.5%, p95_ms: +5.4%, p99_ms: -9.6%, requests_per_second: +5.6%, rss_bytes: -0.3% |
| search | stable | completed: +0.9%, cpu_percent: +0.0%, duration_seconds: -0.3%, p50_ms: -11.0%, p95_ms: -14.7%, p99_ms: -13.5%, requests_per_second: +1.2%, rss_bytes: -0.3% |
| search | possible-regression | completed: +12.8%, cpu_percent: -2.7%, duration_seconds: -0.3%, p50_ms: -18.8%, p95_ms: +4.3%, p99_ms: +17.4%, requests_per_second: +14.2%, rss_bytes: -0.3% |
| cache_hit | possible-regression | completed: -26.9%, cpu_percent: -41.8%, duration_seconds: -0.1%, p50_ms: +32.0%, p95_ms: +29.0%, p99_ms: -11.0%, requests_per_second: -26.9%, rss_bytes: -0.3% |
| cache_hit | stable | completed: +6.9%, cpu_percent: +2.3%, duration_seconds: -0.2%, p50_ms: -11.7%, p95_ms: -7.6%, p99_ms: -20.7%, requests_per_second: +7.2%, rss_bytes: -0.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +20.0% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +20.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -5.8% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -6.7% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -12.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -23.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +28.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +12.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +32.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +31.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.3% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -3.9%, messages_per_second: +4.1%, p50_ms: -3.2%, p95_ms: -5.8%, p99_ms: -5.3% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -1.6%, messages_per_second: +1.6%, p50_ms: -0.8%, p95_ms: -7.1%, p99_ms: -6.6% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | improvement | completed: +50.6%, cpu_percent: +91.8%, duration_seconds: +0.0%, p50_ms: -32.9%, p95_ms: -9.4%, p99_ms: +9.3%, requests_per_second: +50.5%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +48.1%, cpu_percent: +93.4%, duration_seconds: +0.1%, p50_ms: -32.5%, p95_ms: +25.2%, p99_ms: -6.9%, requests_per_second: +47.8%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 50 | improvement | completed: +36.5%, cpu_percent: +86.5%, duration_seconds: +0.2%, p50_ms: -49.7%, p95_ms: +3.8%, p99_ms: +15.0%, requests_per_second: +36.4%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 100 | possible-regression | completed: +37.4%, cpu_percent: +90.2%, duration_seconds: +0.2%, p50_ms: -37.8%, p95_ms: +2.8%, p99_ms: +12.1%, requests_per_second: +37.2%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -5.0%, cpu_percent: +8.8%, duration_seconds: +0.0%, p50_ms: +5.5%, p95_ms: +59.4%, p99_ms: +42.4%, requests_per_second: -4.9%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +45.7%, cpu_percent: +93.1%, duration_seconds: +0.1%, p50_ms: -34.8%, p95_ms: +0.1%, p99_ms: -20.2%, requests_per_second: +45.6%, rss_bytes: +64.3% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38968378307)
