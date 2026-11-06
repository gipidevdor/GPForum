# GPForum continuous performance evidence

Commit: `7a8e1edd20dc51e0a52f9cf6d50012b6c8275bdf` · mode: **main** · status: **ok**
Run: 38991162157 / attempt 1 · 2026-10-17T01:31:03.612859+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 55ff9335e5050b33511e6271a67d0101a616cc81

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 355.693 | 2.794 | 2.874 | 3.014 | 100.054 / 378.184 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 673.881 | 14.852 | 17.450 | 21.029 | 199.483 / 378.469 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 669.731 | 73.659 | 81.895 | 129.380 | 200.886 / 380.438 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1174.087 | 0.838 | 0.905 | 0.958 | 99.497 / 377.926 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2329.937 | 4.267 | 5.203 | 5.560 | 198.908 / 377.926 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2355.967 | 20.946 | 21.885 | 25.827 | 199.870 / 378.785 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2268.910 | 43.388 | 46.781 | 69.029 | 200.732 / 380.160 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 149.395 | 6.574 | 7.227 | 10.332 | 80.083 / 380.832 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 276.148 | 34.862 | 41.786 | 60.809 | 160.549 / 381.430 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 247.962 | 179.787 | 295.971 | 362.535 | 161.903 / 383.828 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 881.687 | 1.123 | 1.178 | 1.221 | 99.396 / 383.828 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1727.310 | 5.725 | 6.029 | 8.677 | 199.867 / 383.828 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1747.846 | 28.443 | 29.410 | 39.329 | 200.362 / 383.828 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 867.849 | 1.143 | 1.200 | 1.234 | 99.983 / 383.984 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1717.702 | 5.778 | 6.024 | 9.074 | 199.406 / 383.984 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1741.622 | 28.444 | 30.328 | 40.977 | 201.382 / 383.984 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 844.325 | 1.182 | 1.243 | 1.448 | 99.491 / 384.047 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1676.558 | 5.981 | 7.199 | 8.899 | 199.844 / 384.109 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1676.787 | 29.047 | 31.426 | 41.898 | 199.882 / 384.109 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1669.571 | 58.655 | 63.652 | 95.347 | 199.378 / 387.293 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 98.104 | 9.995 | 11.645 | 12.869 | 58.698 / 387.965 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 171.959 | 56.504 | 71.486 | 103.509 | 121.270 / 387.965 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 155.644 | 283.909 | 460.049 | 533.939 | 118.643 / 387.965 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 149.250 | 548.679 | 978.619 | 1061.824 | 119.148 / 387.965 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 871.288 | 1.151 | 1.196 | 1.246 | 100.472 / 387.965 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1716.894 | 5.718 | 5.975 | 8.046 | 198.910 / 387.965 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1755.100 | 28.094 | 29.231 | 40.554 | 201.360 / 387.965 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1695.073 | 57.202 | 59.318 | 93.024 | 199.384 / 387.965 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1255.810 | 7.220 | 10.656 | 11.570 | 23.628 / 387.965 | stable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 819.988 | 11.797 | 15.836 | 17.166 | 36.664 / 388.293 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2416.538 | 24.562 | 33.017 | 55.694 | 381.779 / 629.469 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2452.677 | 41.309 | 56.542 | 74.817 | 385.127 / 633.602 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 209.283 | 157.226 | 506.481 | 738.707 | 220.931 / 635.504 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 212.947 | 401.302 | 836.791 | 838.433 | 226.897 / 636.750 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2115.617 | 19.439 | 33.720 | 35.673 | 300.520 / 636.770 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2528.433 | 38.051 | 50.973 | 64.752 | 387.290 / 636.770 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.493 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.420 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.451 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.560 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.092 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.521 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.992 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.108 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.087 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.506 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.555 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.268 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.350 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.062 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.046 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.442 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.512 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.513 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.629 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.647 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.914 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.367 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.390 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.900 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.401 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.210 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.193 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.193 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.054 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.021 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.125 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.108 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.085 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.096 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 825.065 | 119.740 | 129.377 | 131.826 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1335.781 | 151.082 | 164.260 | 164.855 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +87.9%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -45.9%, p95_ms: -53.7%, p99_ms: -58.4%, requests_per_second: +87.8%, rss_bytes: +0.3% |
| cache_miss | improvement | completed: +75.0%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -41.1%, p95_ms: -47.8%, p99_ms: -51.0%, requests_per_second: +75.1%, rss_bytes: +0.4% |
| cache_miss | improvement | completed: +85.5%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -43.2%, p95_ms: -51.3%, p99_ms: -44.7%, requests_per_second: +85.4%, rss_bytes: +0.4% |
| health_live | stable | completed: -7.9%, cpu_percent: +0.1%, duration_seconds: -4.7%, p50_ms: +3.6%, p95_ms: +4.7%, p99_ms: +6.1%, requests_per_second: -4.2%, rss_bytes: +0.3% |
| health_live | possible-regression | completed: +0.4%, cpu_percent: +0.1%, duration_seconds: +0.2%, p50_ms: -0.0%, p95_ms: +15.9%, p99_ms: +2.0%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| health_live | stable | completed: +0.5%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: -0.5%, p99_ms: +0.7%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| health_live | stable | completed: +2.2%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -1.2%, p95_ms: -5.8%, p99_ms: +5.8%, requests_per_second: +2.1%, rss_bytes: +0.3% |
| home | improvement | completed: +106.2%, cpu_percent: -9.6%, duration_seconds: -0.1%, p50_ms: -53.8%, p95_ms: -53.5%, p99_ms: -36.5%, requests_per_second: +115.2%, rss_bytes: +0.3% |
| home | improvement | completed: +96.8%, cpu_percent: -9.5%, duration_seconds: -0.0%, p50_ms: -49.7%, p95_ms: -46.2%, p99_ms: -51.0%, requests_per_second: +96.9%, rss_bytes: +0.3% |
| home | improvement | completed: +99.6%, cpu_percent: -9.1%, duration_seconds: +0.1%, p50_ms: -48.5%, p95_ms: -51.4%, p99_ms: -46.9%, requests_per_second: +99.4%, rss_bytes: +0.3% |
| categories | stable | completed: -3.2%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +3.3%, p95_ms: +3.7%, p99_ms: +1.5%, requests_per_second: -3.3%, rss_bytes: +0.3% |
| categories | stable | completed: +1.4%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -1.4%, p95_ms: -0.7%, p99_ms: -5.9%, requests_per_second: +1.3%, rss_bytes: +0.3% |
| categories | stable | completed: +2.4%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: -1.5%, p99_ms: -2.1%, requests_per_second: +2.4%, rss_bytes: +0.3% |
| category | stable | completed: +1.3%, cpu_percent: +1.1%, duration_seconds: +0.1%, p50_ms: -1.3%, p95_ms: -1.9%, p99_ms: -7.4%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| category | stable | completed: -1.0%, cpu_percent: +0.1%, duration_seconds: -4.7%, p50_ms: -2.9%, p95_ms: -16.7%, p99_ms: -9.4%, requests_per_second: +3.1%, rss_bytes: +0.3% |
| category | improvement | completed: +5.1%, cpu_percent: +0.9%, duration_seconds: +0.1%, p50_ms: -4.6%, p95_ms: -12.1%, p99_ms: -11.6%, requests_per_second: +5.0%, rss_bytes: +0.3% |
| thread | possible-regression | completed: -0.1%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +3.3%, p95_ms: +1.6%, p99_ms: +11.0%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| thread | stable | completed: +0.2%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +0.8%, p95_ms: +9.7%, p99_ms: -11.6%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| thread | stable | completed: +0.8%, cpu_percent: -0.9%, duration_seconds: +0.1%, p50_ms: -2.8%, p95_ms: -1.1%, p99_ms: -5.9%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| thread | stable | completed: +3.4%, cpu_percent: -0.9%, duration_seconds: +0.0%, p50_ms: -2.9%, p95_ms: +1.0%, p99_ms: -5.7%, requests_per_second: +3.3%, rss_bytes: +0.3% |
| search | improvement | completed: +53.1%, cpu_percent: -15.7%, duration_seconds: +0.1%, p50_ms: -34.1%, p95_ms: -31.1%, p99_ms: -36.2%, requests_per_second: +50.9%, rss_bytes: +0.3% |
| search | improvement | completed: +42.1%, cpu_percent: -13.9%, duration_seconds: -0.1%, p50_ms: -31.0%, p95_ms: -25.5%, p99_ms: -26.7%, requests_per_second: +42.4%, rss_bytes: +0.3% |
| search | improvement | completed: +56.8%, cpu_percent: -14.2%, duration_seconds: +0.1%, p50_ms: -30.1%, p95_ms: -36.3%, p99_ms: -33.7%, requests_per_second: +56.6%, rss_bytes: +0.3% |
| search | improvement | completed: +50.3%, cpu_percent: -15.3%, duration_seconds: +0.0%, p50_ms: -31.7%, p95_ms: -35.6%, p99_ms: -34.3%, requests_per_second: +50.3%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -1.1%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +3.8%, p95_ms: -1.0%, p99_ms: -25.8%, requests_per_second: -1.0%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -2.2%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -1.4%, p95_ms: -6.7%, p99_ms: -13.5%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +4.6%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: -4.3%, p95_ms: -4.7%, p99_ms: -1.6%, requests_per_second: +4.5%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +3.1%, cpu_percent: -1.1%, duration_seconds: -0.0%, p50_ms: -3.3%, p95_ms: -6.7%, p99_ms: -1.9%, requests_per_second: +3.0%, rss_bytes: +0.3% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +0.1%, duration_seconds: -7.0%, p50_ms: -9.6%, p95_ms: -6.9%, p99_ms: -9.7%, requests_per_second: +7.5%, rss_bytes: +0.3% |
| thread | possible-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +6.4%, duration_seconds: +2.5%, p50_ms: +14.0%, p95_ms: -6.9%, p99_ms: -7.6%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| thread | stable | completed: -1.2%, cpu_percent: -1.7%, duration_seconds: +0.0%, p50_ms: +11.2%, p95_ms: -0.3%, p99_ms: +26.3%, requests_per_second: -1.2%, rss_bytes: +0.3% |
| thread | improvement | completed: +3.2%, cpu_percent: -0.7%, duration_seconds: -0.4%, p50_ms: +14.9%, p95_ms: -20.8%, p99_ms: -25.0%, requests_per_second: +3.6%, rss_bytes: +0.2% |
| search | improvement | completed: +24.6%, cpu_percent: -12.8%, duration_seconds: -0.3%, p50_ms: -18.2%, p95_ms: -30.0%, p99_ms: -16.0%, requests_per_second: +25.0%, rss_bytes: +0.3% |
| search | improvement | completed: +44.6%, cpu_percent: -15.4%, duration_seconds: -0.2%, p50_ms: -20.1%, p95_ms: -37.3%, p99_ms: -40.9%, requests_per_second: +46.3%, rss_bytes: +0.2% |
| cache_hit | stable | completed: -7.8%, cpu_percent: -19.5%, duration_seconds: +0.3%, p50_ms: -10.4%, p95_ms: -3.4%, p99_ms: -38.3%, requests_per_second: -10.4%, rss_bytes: +0.2% |
| cache_hit | stable | completed: +3.6%, cpu_percent: +1.5%, duration_seconds: -0.1%, p50_ms: -6.5%, p95_ms: -19.7%, p99_ms: -29.4%, requests_per_second: +3.8%, rss_bytes: +0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -5.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -9.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.2% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -10.0% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +33.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -5.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.9% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -11.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +19.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.3% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +41.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +79.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +37.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +12.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +17.7% |
| sql-plan-functions | possible-regression | nested_statements: +0.0%, sql_execution_ms: +14.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +34.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +21.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.3% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -4.7%, messages_per_second: +4.9%, p50_ms: -6.0%, p95_ms: -4.8%, p99_ms: -3.7% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -3.6%, messages_per_second: +3.7%, p50_ms: -1.0%, p95_ms: -6.0%, p99_ms: -5.7% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +44.4%, cpu_percent: +91.0%, duration_seconds: +0.2%, p50_ms: -15.4%, p95_ms: +5.1%, p99_ms: +32.9%, requests_per_second: +44.1%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | improvement | completed: +47.1%, cpu_percent: +93.2%, duration_seconds: +0.0%, p50_ms: -29.6%, p95_ms: -11.2%, p99_ms: -21.5%, requests_per_second: +46.9%, rss_bytes: +63.6% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +34.6%, cpu_percent: +86.2%, duration_seconds: +0.1%, p50_ms: -44.6%, p95_ms: +10.1%, p99_ms: +38.4%, requests_per_second: +34.5%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 100 | improvement | completed: +43.1%, cpu_percent: +90.4%, duration_seconds: +0.4%, p50_ms: -26.9%, p95_ms: -14.5%, p99_ms: -21.0%, requests_per_second: +42.7%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +23.9%, cpu_percent: +49.2%, duration_seconds: +0.3%, p50_ms: -30.8%, p95_ms: +15.4%, p99_ms: -12.0%, requests_per_second: +20.5%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.2%, cpu_percent: +94.2%, duration_seconds: +0.1%, p50_ms: -33.5%, p95_ms: -14.1%, p99_ms: -30.4%, requests_per_second: +49.2%, rss_bytes: +64.1% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38991162157)
