# GPForum continuous performance evidence

Commit: `27ca9e53bce99b7fa8691ff4fcdbf3e341fb291e` · mode: **main** · status: **ok**
Run: 38727730528 / attempt 1 · 2026-10-15T11:30:14.963531+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. d4555a313a225fae4739637f216d67c44667571a

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 207.142 | 4.708 | 5.222 | 5.692 | 99.849 / 369.230 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 404.960 | 23.828 | 28.090 | 37.522 | 199.389 / 369.309 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 395.622 | 119.640 | 154.090 | 214.271 | 201.238 / 371.160 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1127.039 | 0.887 | 0.928 | 0.989 | 99.455 / 369.391 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2272.501 | 4.358 | 4.508 | 5.590 | 199.409 / 369.391 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2347.308 | 21.191 | 21.987 | 24.689 | 200.400 / 370.035 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2266.252 | 43.073 | 46.446 | 63.989 | 200.359 / 371.297 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 99.936 | 9.879 | 10.433 | 12.983 | 87.984 / 371.605 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 189.192 | 50.596 | 64.280 | 84.234 | 177.442 / 372.387 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 174.774 | 258.140 | 428.948 | 490.410 | 178.204 / 374.641 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 863.410 | 1.142 | 1.221 | 1.274 | 99.528 / 374.641 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1687.406 | 5.806 | 7.217 | 8.461 | 198.950 / 374.641 | possible-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1759.512 | 27.716 | 29.290 | 35.795 | 201.356 / 374.641 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 845.132 | 1.172 | 1.230 | 1.291 | 99.467 / 374.672 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1664.469 | 6.019 | 7.366 | 8.141 | 199.926 / 374.672 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1713.267 | 29.352 | 32.992 | 37.889 | 200.269 / 374.672 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 850.950 | 1.163 | 1.248 | 1.357 | 99.903 / 374.734 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1647.115 | 5.990 | 6.416 | 7.308 | 199.190 / 374.797 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1598.453 | 30.582 | 33.144 | 47.612 | 200.059 / 374.797 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1621.706 | 59.478 | 67.601 | 97.371 | 200.677 / 377.719 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 69.468 | 14.248 | 16.171 | 18.407 | 67.138 / 378.363 | possible-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 126.358 | 75.802 | 87.012 | 131.297 | 133.681 / 378.363 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.199 | 380.229 | 695.395 | 775.220 | 132.888 / 378.363 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.721 | 775.736 | 1445.188 | 1530.691 | 134.330 / 378.363 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 841.750 | 1.159 | 1.234 | 1.278 | 99.483 / 378.363 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1696.076 | 6.011 | 6.580 | 8.843 | 198.611 / 378.363 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1694.988 | 29.295 | 31.726 | 37.547 | 199.710 / 378.363 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1696.603 | 57.573 | 60.922 | 93.136 | 199.811 / 378.363 | improvement |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1330.018 | 7.048 | 10.318 | 12.648 | 27.270 / 378.363 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 983.420 | 9.388 | 14.138 | 17.191 | 38.289 / 378.668 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2410.594 | 17.948 | 34.354 | 38.519 | 387.464 / 615.039 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2330.977 | 38.069 | 76.324 | 112.184 | 366.975 / 619.094 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 148.947 | 260.561 | 700.719 | 855.168 | 234.843 / 620.414 | possible-regression |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 155.008 | 535.810 | 1451.256 | 1739.080 | 240.484 / 622.078 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1562.491 | 35.347 | 67.645 | 95.762 | 211.631 / 622.148 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2538.582 | 40.531 | 53.243 | 68.494 | 388.975 / 622.148 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 209.266 | 4.753 | 4.875 | 5.113 | 99.878 / 370.375 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 405.692 | 26.886 | 29.037 | 34.284 | 199.898 / 370.488 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 389.865 | 121.673 | 153.192 | 220.495 | 200.335 / 372.375 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1179.959 | 0.836 | 0.905 | 1.041 | 99.957 / 370.422 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2306.335 | 4.296 | 4.493 | 5.530 | 199.188 / 370.422 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2328.114 | 21.540 | 23.091 | 25.758 | 200.282 / 371.195 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2218.015 | 43.534 | 48.526 | 70.054 | 200.117 / 372.535 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 90.259 | 10.727 | 12.383 | 15.361 | 87.879 / 373.180 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 172.787 | 56.895 | 68.985 | 99.256 | 177.407 / 373.637 | possible-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 149.183 | 303.163 | 529.497 | 585.575 | 178.087 / 375.906 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 879.505 | 1.127 | 1.185 | 1.270 | 99.515 / 375.906 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1713.304 | 5.798 | 6.318 | 8.196 | 199.693 / 375.906 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1700.181 | 28.921 | 31.757 | 40.698 | 200.185 / 375.906 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 861.192 | 1.142 | 1.225 | 1.273 | 99.904 / 375.938 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1677.967 | 5.910 | 6.310 | 8.781 | 199.325 / 375.938 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1680.492 | 29.550 | 33.485 | 47.893 | 200.174 / 375.938 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 844.075 | 1.165 | 1.240 | 1.358 | 99.984 / 376.172 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1655.476 | 5.975 | 6.344 | 10.551 | 198.848 / 376.188 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1640.127 | 29.987 | 32.114 | 46.026 | 201.220 / 376.188 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1592.526 | 61.813 | 63.938 | 100.726 | 201.640 / 379.082 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 67.927 | 14.499 | 16.741 | 18.137 | 67.138 / 379.371 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 128.536 | 73.716 | 99.984 | 145.447 | 134.429 / 379.637 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 118.236 | 339.000 | 745.239 | 887.824 | 134.339 / 379.637 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 35.413 | 545.212 | 1385.101 | 1453.156 | 71.868 / 380.535 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 873.807 | 1.130 | 1.236 | 1.505 | 111.895 / 381.535 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1687.515 | 5.861 | 6.945 | 9.243 | 199.366 / 381.535 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1692.394 | 29.214 | 30.773 | 43.579 | 200.288 / 381.535 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1670.424 | 58.476 | 61.097 | 98.014 | 200.275 / 381.535 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2414.609 | 20.750 | 38.346 | 60.902 | 378.430 / 616.570 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2419.386 | 36.113 | 69.398 | 96.028 | 386.405 / 621.055 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 147.947 | 224.411 | 765.968 | 1058.960 | 235.774 / 622.770 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 145.738 | 437.583 | 1549.499 | 1867.187 | 241.928 / 623.309 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1606.676 | 33.288 | 48.262 | 62.428 | 229.517 / 623.410 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2512.083 | 39.021 | 59.878 | 89.475 | 386.277 / 623.410 | possible-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.507 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.422 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.487 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.558 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.546 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.079 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.112 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.106 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.540 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.532 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.269 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.330 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.080 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.438 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.453 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.449 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.552 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.435 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.529 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.270 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.404 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.016 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.358 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.197 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.169 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.200 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.124 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.085 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.084 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 673.092 | 147.230 | 159.843 | 162.946 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1142.631 | 171.422 | 189.075 | 190.097 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: -1.9%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -0.8%, p95_ms: +3.2%, p99_ms: -12.6%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| cache_miss | improvement | completed: -1.8%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -14.4%, p95_ms: -2.9%, p99_ms: +9.5%, requests_per_second: -1.8%, rss_bytes: +0.3% |
| cache_miss | stable | completed: -0.9%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -0.6%, p95_ms: -2.8%, p99_ms: -0.6%, requests_per_second: -1.0%, rss_bytes: +0.3% |
| health_live | stable | completed: -2.6%, cpu_percent: -1.0%, duration_seconds: -0.0%, p50_ms: +3.5%, p95_ms: +1.4%, p99_ms: -4.5%, requests_per_second: -2.2%, rss_bytes: +0.4% |
| health_live | stable | completed: -1.0%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +0.7%, p95_ms: -1.9%, p99_ms: +2.1%, requests_per_second: -0.5%, rss_bytes: +0.4% |
| health_live | stable | completed: +1.2%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -0.6%, p95_ms: -2.2%, p99_ms: -11.1%, requests_per_second: +1.3%, rss_bytes: +0.4% |
| health_live | stable | completed: +0.3%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -0.6%, p95_ms: -0.4%, p99_ms: -1.0%, requests_per_second: +0.2%, rss_bytes: +0.4% |
| home | stable | completed: -3.8%, cpu_percent: -0.2%, duration_seconds: -4.6%, p50_ms: +0.8%, p95_ms: -9.3%, p99_ms: +6.0%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| home | stable | completed: -1.6%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: -0.8%, p95_ms: +8.1%, p99_ms: +0.6%, requests_per_second: +1.1%, rss_bytes: +0.4% |
| home | stable | completed: +0.3%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -3.7%, p95_ms: -0.2%, p99_ms: -3.4%, requests_per_second: +0.4%, rss_bytes: +0.4% |
| categories | improvement | completed: +1.5%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -1.6%, p95_ms: -0.2%, p99_ms: -10.6%, requests_per_second: +1.6%, rss_bytes: +0.4% |
| categories | possible-regression | completed: -1.5%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.1%, p95_ms: +17.8%, p99_ms: +18.5%, requests_per_second: -1.5%, rss_bytes: +0.4% |
| categories | stable | completed: -0.4%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: -0.8%, p95_ms: +0.5%, p99_ms: +0.7%, requests_per_second: -0.4%, rss_bytes: +0.4% |
| category | stable | completed: -0.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -0.8%, p95_ms: -0.6%, p99_ms: +0.9%, requests_per_second: +1.1%, rss_bytes: +0.4% |
| category | stable | completed: -0.1%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +1.9%, p95_ms: +1.6%, p99_ms: -10.4%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| category | stable | completed: +1.0%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +4.2%, p95_ms: +9.8%, p99_ms: -5.3%, requests_per_second: +0.9%, rss_bytes: +0.4% |
| thread | stable | completed: -4.5%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +0.6%, p95_ms: +1.4%, p99_ms: +5.2%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| thread | stable | completed: -5.4%, cpu_percent: -0.1%, duration_seconds: -4.6%, p50_ms: +0.9%, p95_ms: +4.4%, p99_ms: +2.1%, requests_per_second: -1.4%, rss_bytes: +0.3% |
| thread | stable | completed: -5.2%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +5.2%, p95_ms: +1.1%, p99_ms: +10.9%, requests_per_second: -5.1%, rss_bytes: +0.3% |
| thread | stable | completed: -4.4%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +2.3%, p95_ms: +9.4%, p99_ms: +2.1%, requests_per_second: -4.3%, rss_bytes: +0.3% |
| search | possible-regression | completed: -9.2%, cpu_percent: +2.0%, duration_seconds: -4.7%, p50_ms: +7.9%, p95_ms: +8.9%, p99_ms: +11.6%, requests_per_second: -6.5%, rss_bytes: +0.4% |
| search | stable | completed: -5.9%, cpu_percent: +1.5%, duration_seconds: +0.1%, p50_ms: +6.2%, p95_ms: -1.9%, p99_ms: +5.2%, requests_per_second: -6.0%, rss_bytes: +0.4% |
| search | stable | completed: -0.4%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +3.5%, p95_ms: +6.0%, p99_ms: +1.0%, requests_per_second: -0.5%, rss_bytes: +0.4% |
| search | stable | completed: +0.0%, cpu_percent: +1.1%, duration_seconds: +0.0%, p50_ms: +5.5%, p95_ms: +4.7%, p99_ms: +6.7%, requests_per_second: +0.1%, rss_bytes: +0.4% |
| cache_hit | stable | completed: -2.7%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +2.0%, p95_ms: +2.1%, p99_ms: -8.1%, requests_per_second: -2.7%, rss_bytes: +0.4% |
| cache_hit | possible-regression | completed: -0.8%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: +4.9%, p95_ms: +8.8%, p99_ms: +30.4%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +0.7%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +3.7%, p95_ms: +7.0%, p99_ms: +4.6%, requests_per_second: -3.0%, rss_bytes: +0.4% |
| cache_hit | improvement | completed: +1.1%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: -14.6%, p99_ms: +1.3%, requests_per_second: +1.0%, rss_bytes: +0.4% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -0.0%, duration_seconds: +1.4%, p50_ms: +3.4%, p95_ms: -2.8%, p99_ms: +1.5%, requests_per_second: -0.9%, rss_bytes: +0.4% |
| thread | possible-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -0.1%, duration_seconds: +5.2%, p50_ms: +4.8%, p95_ms: +3.0%, p99_ms: +16.6%, requests_per_second: -4.2%, rss_bytes: +0.4% |
| thread | improvement | completed: -1.6%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: -26.9%, p95_ms: +1.4%, p99_ms: -6.8%, requests_per_second: -1.7%, rss_bytes: +0.3% |
| thread | stable | completed: -5.5%, cpu_percent: -5.3%, duration_seconds: -0.0%, p50_ms: +10.4%, p95_ms: +15.6%, p99_ms: +25.3%, requests_per_second: -5.7%, rss_bytes: +0.2% |
| search | possible-regression | completed: -5.1%, cpu_percent: +0.6%, duration_seconds: -0.2%, p50_ms: +11.4%, p95_ms: +10.0%, p99_ms: +23.7%, requests_per_second: -4.9%, rss_bytes: +0.3% |
| search | possible-regression | completed: +9.5%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -4.0%, p95_ms: +49.4%, p99_ms: +54.1%, requests_per_second: +9.4%, rss_bytes: +0.4% |
| cache_hit | confirmed-regression | completed: -25.6%, cpu_percent: -29.5%, duration_seconds: +0.0%, p50_ms: +97.5%, p95_ms: +61.6%, p99_ms: +78.2%, requests_per_second: -25.6%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +0.4%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: +5.1%, p95_ms: -11.3%, p99_ms: +6.1%, requests_per_second: +0.4%, rss_bytes: +0.4% |
| cache_miss | stable | completed: -1.2%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +1.6%, p95_ms: -0.9%, p99_ms: -5.6%, requests_per_second: -1.2%, rss_bytes: +0.3% |
| cache_miss | possible-regression | completed: -5.5%, cpu_percent: -0.2%, duration_seconds: -4.6%, p50_ms: +13.5%, p95_ms: +14.8%, p99_ms: -18.9%, requests_per_second: -1.9%, rss_bytes: +0.4% |
| cache_miss | stable | completed: -2.0%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +1.2%, p95_ms: +3.7%, p99_ms: +1.3%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| health_live | stable | completed: -1.6%, cpu_percent: +0.5%, duration_seconds: -4.7%, p50_ms: +0.1%, p95_ms: +2.1%, p99_ms: +6.4%, requests_per_second: +0.1%, rss_bytes: +0.4% |
| health_live | improvement | completed: +3.8%, cpu_percent: -0.1%, duration_seconds: +4.8%, p50_ms: -1.3%, p95_ms: -13.5%, p99_ms: -5.8%, requests_per_second: +3.9%, rss_bytes: +0.4% |
| health_live | stable | completed: -1.2%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +3.2%, p95_ms: +3.3%, p99_ms: -19.0%, requests_per_second: -1.3%, rss_bytes: +0.4% |
| health_live | stable | completed: -2.9%, cpu_percent: +0.6%, duration_seconds: -0.0%, p50_ms: +1.6%, p95_ms: +7.7%, p99_ms: +1.4%, requests_per_second: -2.9%, rss_bytes: +0.4% |
| home | confirmed-regression | completed: -10.8%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: +10.7%, p95_ms: +20.0%, p99_ms: +32.5%, requests_per_second: -11.1%, rss_bytes: +0.5% |
| home | possible-regression | completed: -10.8%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: +12.5%, p95_ms: +11.2%, p99_ms: +9.1%, requests_per_second: -8.2%, rss_bytes: +0.4% |
| home | confirmed-regression | completed: -13.8%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +18.0%, p95_ms: +19.8%, p99_ms: +17.0%, requests_per_second: -13.7%, rss_bytes: +0.4% |
| categories | stable | completed: +0.7%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -0.4%, p95_ms: -0.8%, p99_ms: -8.2%, requests_per_second: +0.9%, rss_bytes: +0.4% |
| categories | stable | completed: -3.3%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +3.2%, p95_ms: +7.9%, p99_ms: +3.1%, requests_per_second: -2.8%, rss_bytes: +0.4% |
| categories | stable | completed: -3.8%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +3.4%, p95_ms: +7.4%, p99_ms: +4.9%, requests_per_second: -3.8%, rss_bytes: +0.4% |
| category | stable | completed: -0.9%, cpu_percent: +0.5%, duration_seconds: +4.8%, p50_ms: +1.3%, p95_ms: +3.5%, p99_ms: +3.6%, requests_per_second: -1.4%, rss_bytes: +0.4% |
| category | stable | completed: +0.0%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +2.6%, p95_ms: +2.3%, p99_ms: -3.5%, requests_per_second: -2.0%, rss_bytes: +0.4% |
| category | stable | completed: -2.3%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +3.0%, p95_ms: +12.4%, p99_ms: +16.1%, requests_per_second: -2.4%, rss_bytes: +0.4% |
| thread | stable | completed: -2.8%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +2.7%, p95_ms: +2.6%, p99_ms: +7.4%, requests_per_second: -2.8%, rss_bytes: +0.4% |
| thread | stable | completed: -0.5%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +2.3%, p95_ms: -6.3%, p99_ms: +3.7%, requests_per_second: -2.6%, rss_bytes: +0.4% |
| thread | stable | completed: -2.9%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: +3.9%, p95_ms: +1.4%, p99_ms: -0.2%, requests_per_second: -3.0%, rss_bytes: +0.4% |
| thread | stable | completed: -4.4%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: +5.7%, p95_ms: -1.5%, p99_ms: +3.5%, requests_per_second: -4.4%, rss_bytes: +0.4% |
| search | confirmed-regression | completed: -8.7%, cpu_percent: +3.0%, duration_seconds: +0.0%, p50_ms: +9.6%, p95_ms: +15.3%, p99_ms: +16.6%, requests_per_second: -8.7%, rss_bytes: +0.4% |
| search | possible-regression | completed: -0.4%, cpu_percent: +2.0%, duration_seconds: +0.1%, p50_ms: +4.1%, p95_ms: +20.1%, p99_ms: +10.0%, requests_per_second: -4.0%, rss_bytes: +0.4% |
| search | stable | completed: -4.8%, cpu_percent: +1.9%, duration_seconds: +0.1%, p50_ms: -9.2%, p95_ms: +14.9%, p99_ms: +23.8%, requests_per_second: -4.9%, rss_bytes: +0.4% |
| search | possible-regression | completed: -64.3%, cpu_percent: -45.7%, duration_seconds: +0.0%, p50_ms: -24.8%, p95_ms: +1.8%, p99_ms: +2.6%, requests_per_second: -64.3%, rss_bytes: +0.6% |
| cache_hit | stable | completed: +0.5%, cpu_percent: +12.5%, duration_seconds: -0.0%, p50_ms: -0.2%, p95_ms: +4.7%, p99_ms: +9.7%, requests_per_second: +0.4%, rss_bytes: +0.9% |
| cache_hit | stable | completed: -2.4%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +2.8%, p95_ms: +8.0%, p99_ms: +6.5%, requests_per_second: -2.3%, rss_bytes: +0.9% |
| cache_hit | stable | completed: -4.1%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +4.6%, p95_ms: +5.9%, p99_ms: -0.9%, requests_per_second: -4.2%, rss_bytes: +0.9% |
| cache_hit | stable | completed: -2.7%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +4.1%, p95_ms: -0.2%, p99_ms: +2.4%, requests_per_second: -2.8%, rss_bytes: +0.9% |
| thread | confirmed-regression | completed: -4.0%, cpu_percent: -2.4%, duration_seconds: +0.0%, p50_ms: +15.9%, p95_ms: +13.0%, p99_ms: +35.6%, requests_per_second: -3.4%, rss_bytes: +0.3% |
| thread | stable | completed: -3.7%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +16.8%, p95_ms: +4.9%, p99_ms: +23.0%, requests_per_second: -3.7%, rss_bytes: +0.4% |
| search | possible-regression | completed: -0.3%, cpu_percent: +15.3%, duration_seconds: +0.3%, p50_ms: +6.0%, p95_ms: +6.8%, p99_ms: +22.9%, requests_per_second: -0.6%, rss_bytes: +0.4% |
| search | possible-regression | completed: +0.0%, cpu_percent: +1.8%, duration_seconds: +0.0%, p50_ms: -8.7%, p95_ms: +39.9%, p99_ms: +55.3%, requests_per_second: +0.2%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: +84.3%, cpu_percent: +112.0%, duration_seconds: +0.1%, p50_ms: -39.7%, p95_ms: -14.6%, p99_ms: -33.3%, requests_per_second: +84.1%, rss_bytes: +0.1% |
| cache_hit | possible-regression | completed: -2.0%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: +0.1%, p95_ms: +23.0%, p99_ms: +26.9%, requests_per_second: -2.0%, rss_bytes: +0.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.1% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -13.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.3% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +10.9% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +15.2% |
| sql-plan-readers | possible-regression | sql_execution_ms: +16.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.4% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +25.0% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +18.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -12.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +28.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +9.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -4.8% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -41.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.9% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -32.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.6% |
| sql-plan-functions | possible-regression | nested_statements: +0.0%, sql_execution_ms: +14.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +9.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +22.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +17.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +40.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.2% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -1.4%, messages_per_second: +1.4%, p50_ms: -1.5%, p95_ms: -1.1%, p99_ms: -1.1% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -1.2%, messages_per_second: +1.2%, p50_ms: -1.5%, p95_ms: -5.9%, p99_ms: -5.9% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.0%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +1.0%, p95_ms: -6.6%, p99_ms: -10.2%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.2%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +12.8%, p95_ms: +3.4%, p99_ms: -8.6%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.5%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: +1.7%, p95_ms: -0.6%, p99_ms: +2.9%, requests_per_second: -1.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.4%, cpu_percent: +0.5%, duration_seconds: -4.7%, p50_ms: -5.8%, p95_ms: -2.5%, p99_ms: +5.3%, requests_per_second: +4.7%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.5%, cpu_percent: -0.1%, duration_seconds: +4.9%, p50_ms: -1.4%, p95_ms: -0.3%, p99_ms: -1.1%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.7%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +1.6%, p95_ms: +5.0%, p99_ms: +4.3%, requests_per_second: -0.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -2.2%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +1.1%, p95_ms: +4.5%, p99_ms: +9.5%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -9.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +8.6%, p95_ms: +18.7%, p99_ms: +18.3%, requests_per_second: -9.7%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -8.7%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +12.4%, p95_ms: +7.3%, p99_ms: +17.8%, requests_per_second: -8.7%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -14.6%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +17.4%, p95_ms: +23.4%, p99_ms: +19.4%, requests_per_second: -14.6%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -1.3%, p95_ms: -2.9%, p99_ms: -0.3%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +1.5%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: -0.1%, p95_ms: -12.5%, p99_ms: -3.1%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -3.3%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: +4.3%, p95_ms: +8.4%, p99_ms: +13.7%, requests_per_second: -3.4%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +5.5%, cpu_percent: +0.4%, duration_seconds: +4.9%, p50_ms: -2.6%, p95_ms: -0.4%, p99_ms: -1.4%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +2.8%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -1.8%, p95_ms: -14.3%, p99_ms: +7.9%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -1.9%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +0.7%, p95_ms: +1.5%, p99_ms: +26.4%, requests_per_second: -1.9%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.8%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +0.2%, p95_ms: -0.6%, p99_ms: +0.1%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +2.6%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -0.2%, p95_ms: -1.1%, p99_ms: +44.4%, requests_per_second: +0.5%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.6%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: -1.9%, p95_ms: -3.1%, p99_ms: -3.3%, requests_per_second: +2.6%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.8%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +3.9%, p95_ms: -5.4%, p99_ms: +3.4%, requests_per_second: -1.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.2%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +1.8%, p95_ms: +3.5%, p99_ms: -1.5%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +5.5%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: -2.8%, p95_ms: +14.9%, p99_ms: +10.8%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -4.8%, cpu_percent: +1.1%, duration_seconds: -0.0%, p50_ms: -10.8%, p95_ms: +7.2%, p99_ms: +14.5%, requests_per_second: -4.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -64.5%, cpu_percent: -46.5%, duration_seconds: -0.0%, p50_ms: -29.7%, p95_ms: -4.2%, p99_ms: -5.1%, requests_per_second: -64.5%, rss_bytes: +0.6% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: +3.8%, cpu_percent: +12.5%, duration_seconds: -0.0%, p50_ms: -2.5%, p95_ms: +0.2%, p99_ms: +17.8%, requests_per_second: +3.8%, rss_bytes: +0.8% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.6%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -2.5%, p95_ms: +5.5%, p99_ms: +4.5%, requests_per_second: -0.5%, rss_bytes: +0.8% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -3.8%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: -0.3%, p95_ms: -3.0%, p99_ms: +16.1%, requests_per_second: -0.2%, rss_bytes: +0.8% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.5%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +1.6%, p95_ms: +0.3%, p99_ms: +5.2%, requests_per_second: -1.5%, rss_bytes: +0.8% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +0.1%, cpu_percent: -2.3%, duration_seconds: +0.1%, p50_ms: +15.6%, p95_ms: +11.6%, p99_ms: +58.1%, requests_per_second: +0.2%, rss_bytes: +0.2% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +3.8%, cpu_percent: +5.3%, duration_seconds: +0.0%, p50_ms: -5.1%, p95_ms: -9.1%, p99_ms: -14.4%, requests_per_second: +3.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -0.3%, cpu_percent: +0.4%, duration_seconds: +0.3%, p50_ms: -13.9%, p95_ms: +9.3%, p99_ms: +23.8%, requests_per_second: -0.7%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: -6.1%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -18.3%, p95_ms: +6.8%, p99_ms: +7.4%, requests_per_second: -6.0%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +2.8%, cpu_percent: +8.5%, duration_seconds: +0.0%, p50_ms: -5.8%, p95_ms: -28.7%, p99_ms: -34.8%, requests_per_second: +2.8%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.1%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: -3.7%, p95_ms: +12.5%, p99_ms: +30.6%, requests_per_second: -1.0%, rss_bytes: +0.2% |
| thread | workers=4 | 2 | 50 | improvement | completed: +51.0%, cpu_percent: +93.7%, duration_seconds: +0.1%, p50_ms: -41.3%, p95_ms: +3.7%, p99_ms: -19.1%, requests_per_second: +50.8%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +43.9%, cpu_percent: +82.9%, duration_seconds: +0.1%, p50_ms: -36.0%, p95_ms: +12.9%, p99_ms: +15.2%, requests_per_second: +43.7%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +20.1%, cpu_percent: +76.7%, duration_seconds: +0.1%, p50_ms: -31.5%, p95_ms: +0.8%, p99_ms: +10.3%, requests_per_second: +19.9%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +56.0%, cpu_percent: +79.0%, duration_seconds: +0.4%, p50_ms: -30.9%, p95_ms: +0.4%, p99_ms: +13.6%, requests_per_second: +55.4%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -11.1%, cpu_percent: +6.0%, duration_seconds: -0.0%, p50_ms: +20.7%, p95_ms: +113.2%, p99_ms: +155.0%, requests_per_second: -7.8%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.8%, cpu_percent: +94.7%, duration_seconds: -0.0%, p50_ms: -29.6%, p95_ms: -12.6%, p99_ms: -26.5%, requests_per_second: +49.6%, rss_bytes: +64.4% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +47.4%, cpu_percent: +88.1%, duration_seconds: +0.1%, p50_ms: -30.8%, p95_ms: +19.4%, p99_ms: +32.3%, requests_per_second: +47.2%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | improvement | completed: +52.0%, cpu_percent: +91.6%, duration_seconds: +0.1%, p50_ms: -41.6%, p95_ms: +8.5%, p99_ms: -4.7%, requests_per_second: +51.9%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | improvement | completed: +25.7%, cpu_percent: +75.5%, duration_seconds: +0.5%, p50_ms: -33.8%, p95_ms: +2.8%, p99_ms: +19.3%, requests_per_second: +25.1%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +312.7%, cpu_percent: +236.6%, duration_seconds: +0.3%, p50_ms: -19.7%, p95_ms: +11.9%, p99_ms: +28.5%, requests_per_second: +311.5%, rss_bytes: +63.8% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: -5.0%, cpu_percent: +14.6%, duration_seconds: +0.1%, p50_ms: +13.9%, p95_ms: +56.8%, p99_ms: +43.3%, requests_per_second: -5.1%, rss_bytes: +63.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +50.4%, cpu_percent: +92.9%, duration_seconds: +0.0%, p50_ms: -33.3%, p95_ms: -2.0%, p99_ms: -8.7%, requests_per_second: +50.4%, rss_bytes: +63.4% |

## Suite status and skipped tests

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
- Shared runner and load generator share the host; values are comparative evidence, not production capacity.
- wrk uses closed-loop fixed connections and corrected latency histograms; in-flight concurrency is not measured.
- RSS is end-of-sample manager+workers residency, not peak; PostgreSQL and generator resources are separate.
- Cache hits/misses verified by probes; warmed worker-local SSR cache; cache miss uses harness-only expiry policy.
- Only anonymous GETs; migrations, seed and rate-limit accounting write only the dedicated disposable database.

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38727730528)
