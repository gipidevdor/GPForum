# GPForum continuous performance evidence

Commit: `d4555a313a225fae4739637f216d67c44667571a` · mode: **main** · status: **ok**
Run: 38693699497 / attempt 1 · 2026-10-15T06:39:46.594824+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 8ee4d6eab4696dd43cbb4c51173588b1885d0a28

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 207.780 | 4.748 | 5.059 | 6.514 | 99.460 / 367.980 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 412.263 | 27.840 | 28.927 | 34.265 | 200.376 / 368.105 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 399.658 | 120.322 | 158.510 | 215.590 | 201.346 / 369.934 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1151.891 | 0.857 | 0.915 | 1.036 | 100.455 / 368.035 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2283.456 | 4.328 | 4.597 | 5.473 | 198.914 / 368.035 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2317.274 | 21.327 | 22.486 | 27.786 | 199.790 / 368.676 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2261.031 | 43.328 | 46.626 | 64.619 | 200.190 / 369.941 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 99.871 | 9.801 | 11.502 | 12.253 | 88.160 / 370.480 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 187.111 | 51.015 | 59.457 | 83.714 | 178.000 / 371.000 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 174.092 | 268.118 | 429.702 | 507.729 | 177.561 / 373.250 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 849.639 | 1.160 | 1.223 | 1.425 | 99.509 / 373.250 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1713.487 | 5.809 | 6.127 | 7.138 | 198.924 / 373.250 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1766.778 | 27.936 | 29.140 | 35.541 | 199.918 / 373.250 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 836.221 | 1.181 | 1.237 | 1.280 | 99.500 / 373.328 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1666.000 | 5.906 | 7.250 | 9.090 | 199.407 / 373.352 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1697.216 | 28.169 | 30.046 | 40.009 | 200.409 / 373.352 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 848.843 | 1.156 | 1.231 | 1.290 | 99.997 / 373.469 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1669.983 | 5.935 | 6.148 | 7.157 | 199.366 / 373.531 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1683.726 | 29.060 | 32.790 | 42.931 | 200.224 / 373.539 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1695.189 | 58.152 | 61.788 | 95.394 | 201.822 / 376.469 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 74.283 | 13.201 | 14.849 | 16.489 | 65.850 / 377.023 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 134.409 | 71.388 | 88.727 | 124.752 | 131.746 / 377.023 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.773 | 367.467 | 655.806 | 767.311 | 132.907 / 377.023 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.658 | 735.514 | 1379.860 | 1435.177 | 132.831 / 377.031 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 865.253 | 1.136 | 1.209 | 1.391 | 100.038 / 377.031 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1709.777 | 5.731 | 6.046 | 6.784 | 199.385 / 377.031 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1747.548 | 28.243 | 29.652 | 35.912 | 199.878 / 377.031 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1679.068 | 57.879 | 71.298 | 91.961 | 200.372 / 377.031 | stable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1342.375 | 6.818 | 10.614 | 12.457 | 27.277 / 377.031 | possible-regression |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1027.031 | 8.959 | 13.729 | 14.744 | 38.325 / 377.312 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2451.859 | 24.557 | 33.876 | 41.318 | 388.565 / 613.109 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2470.931 | 34.493 | 66.043 | 89.540 | 387.497 / 617.566 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 156.613 | 233.877 | 636.807 | 691.404 | 233.417 / 618.723 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 141.690 | 558.124 | 971.296 | 1128.427 | 241.674 / 619.727 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2099.931 | 17.899 | 41.849 | 53.750 | 300.110 / 619.727 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2529.551 | 38.578 | 60.023 | 64.586 | 389.090 / 619.727 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 211.769 | 4.679 | 4.917 | 5.415 | 99.510 / 369.094 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 413.411 | 23.687 | 25.298 | 42.263 | 200.341 / 369.188 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 398.114 | 120.213 | 147.780 | 217.676 | 200.853 / 371.129 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1178.603 | 0.835 | 0.886 | 0.978 | 99.496 / 368.797 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2220.447 | 4.353 | 5.197 | 5.873 | 199.378 / 368.797 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2358.886 | 20.878 | 22.360 | 31.807 | 199.906 / 369.594 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2284.274 | 42.866 | 45.067 | 69.071 | 198.902 / 370.977 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 101.481 | 9.690 | 10.318 | 11.590 | 87.558 / 371.461 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 188.128 | 50.581 | 62.041 | 90.956 | 177.874 / 372.090 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 172.947 | 257.010 | 441.995 | 500.342 | 177.755 / 374.316 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 871.813 | 1.132 | 1.194 | 1.384 | 99.479 / 374.344 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1762.839 | 5.617 | 5.855 | 7.947 | 199.398 / 374.344 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1766.731 | 27.964 | 29.568 | 38.804 | 199.847 / 374.344 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 873.025 | 1.127 | 1.183 | 1.229 | 99.441 / 374.422 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1712.391 | 5.760 | 6.166 | 9.104 | 198.912 / 374.500 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1721.243 | 28.686 | 29.796 | 41.248 | 200.369 / 374.500 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 868.752 | 1.134 | 1.208 | 1.265 | 99.950 / 374.625 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1699.987 | 5.842 | 6.769 | 10.175 | 199.283 / 374.625 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1690.058 | 28.850 | 31.677 | 46.106 | 200.729 / 374.625 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1666.488 | 58.489 | 64.904 | 97.333 | 200.350 / 377.457 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 74.376 | 13.231 | 14.521 | 15.560 | 65.190 / 377.785 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 133.845 | 70.845 | 83.270 | 132.248 | 131.734 / 378.113 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.317 | 373.484 | 648.517 | 717.381 | 131.839 / 378.113 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.296 | 725.117 | 1360.860 | 1416.367 | 132.412 / 378.113 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 869.908 | 1.132 | 1.180 | 1.372 | 99.506 / 378.113 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1727.116 | 5.699 | 6.428 | 8.682 | 199.875 / 378.113 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1765.936 | 27.922 | 29.047 | 43.973 | 200.868 / 378.113 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1717.750 | 56.166 | 61.207 | 95.675 | 201.326 / 378.113 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2499.171 | 17.908 | 33.945 | 44.923 | 387.813 / 614.816 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2511.748 | 30.931 | 66.136 | 78.081 | 386.041 / 618.711 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 148.885 | 211.670 | 717.267 | 861.841 | 204.420 / 620.547 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 145.415 | 479.191 | 1107.938 | 1202.072 | 237.647 / 622.488 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 872.740 | 55.165 | 56.499 | 93.612 | 108.276 / 622.523 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2563.520 | 38.981 | 48.668 | 70.481 | 388.897 / 622.523 | possible-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.508 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.459 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.563 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.524 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.096 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.529 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.993 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.101 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.092 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.029 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.456 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.519 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.273 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.325 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.340 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.413 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.459 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.521 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.457 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.903 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.281 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.594 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.940 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.286 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.186 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.160 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.182 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.079 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.088 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.088 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.083 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 663.985 | 149.404 | 161.573 | 164.808 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1129.099 | 174.031 | 200.938 | 201.948 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: -4.5%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +1.6%, p95_ms: +4.3%, p99_ms: +11.1%, requests_per_second: -1.5%, rss_bytes: -0.5% |
| cache_miss | possible-regression | completed: +1.1%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +15.6%, p95_ms: +10.1%, p99_ms: -5.3%, requests_per_second: +1.1%, rss_bytes: -0.5% |
| cache_miss | stable | completed: +2.3%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -0.8%, p95_ms: +9.3%, p99_ms: -2.0%, requests_per_second: +2.5%, rss_bytes: -0.5% |
| health_live | stable | completed: +4.1%, cpu_percent: +1.0%, duration_seconds: +5.0%, p50_ms: +0.2%, p95_ms: -0.3%, p99_ms: +5.0%, requests_per_second: -0.7%, rss_bytes: -0.6% |
| health_live | stable | completed: +0.8%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -1.4%, p95_ms: -0.7%, p99_ms: -1.7%, requests_per_second: +1.0%, rss_bytes: -0.6% |
| health_live | stable | completed: -0.2%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -0.1%, p95_ms: -0.4%, p99_ms: +2.1%, requests_per_second: -0.2%, rss_bytes: -0.6% |
| health_live | stable | completed: +0.8%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: -1.1%, p95_ms: -3.0%, p99_ms: -0.4%, requests_per_second: +0.7%, rss_bytes: -0.6% |
| home | stable | completed: +6.1%, cpu_percent: +0.2%, duration_seconds: +4.9%, p50_ms: -3.0%, p95_ms: +4.8%, p99_ms: -1.1%, requests_per_second: +2.0%, rss_bytes: -0.5% |
| home | stable | completed: +5.8%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: -7.8%, p95_ms: -9.0%, p99_ms: -2.6%, requests_per_second: +8.1%, rss_bytes: -0.6% |
| home | improvement | completed: +7.7%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -4.2%, p95_ms: -15.6%, p99_ms: -12.9%, requests_per_second: +7.7%, rss_bytes: -0.6% |
| categories | stable | completed: -5.8%, cpu_percent: +0.1%, duration_seconds: -4.6%, p50_ms: +1.2%, p95_ms: +0.4%, p99_ms: +8.8%, requests_per_second: -1.2%, rss_bytes: -0.6% |
| categories | stable | completed: -3.1%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +0.7%, p95_ms: -12.6%, p99_ms: -17.7%, requests_per_second: +1.6%, rss_bytes: -0.6% |
| categories | stable | completed: +1.8%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -2.1%, p95_ms: -2.5%, p99_ms: -1.3%, requests_per_second: +1.9%, rss_bytes: -0.6% |
| category | stable | completed: +1.2%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +1.0%, p95_ms: -0.1%, p99_ms: -14.1%, requests_per_second: -0.4%, rss_bytes: -0.6% |
| category | confirmed-regression | completed: +0.1%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -1.0%, p95_ms: +16.4%, p99_ms: +16.6%, requests_per_second: +0.1%, rss_bytes: -0.6% |
| category | stable | completed: -0.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -5.0%, p95_ms: -7.1%, p99_ms: -4.9%, requests_per_second: -0.5%, rss_bytes: -0.6% |
| thread | improvement | completed: +6.2%, cpu_percent: +0.6%, duration_seconds: +4.9%, p50_ms: -0.3%, p95_ms: -1.6%, p99_ms: -29.7%, requests_per_second: +1.2%, rss_bytes: -0.6% |
| thread | stable | completed: +3.3%, cpu_percent: -0.0%, duration_seconds: +4.8%, p50_ms: +1.0%, p95_ms: -0.1%, p99_ms: -7.2%, requests_per_second: -1.0%, rss_bytes: -0.6% |
| thread | stable | completed: +0.7%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -0.6%, p95_ms: +7.2%, p99_ms: +1.6%, requests_per_second: +0.6%, rss_bytes: -0.6% |
| thread | stable | completed: +1.5%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -1.4%, p95_ms: +0.2%, p99_ms: -0.2%, requests_per_second: +1.5%, rss_bytes: -0.5% |
| search | stable | completed: +5.5%, cpu_percent: -0.5%, duration_seconds: +4.9%, p50_ms: -2.4%, p95_ms: +0.5%, p99_ms: -1.3%, requests_per_second: +2.5%, rss_bytes: -0.6% |
| search | stable | completed: +3.1%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -2.6%, p95_ms: -0.8%, p99_ms: -8.0%, requests_per_second: +3.1%, rss_bytes: -0.6% |
| search | stable | completed: +17.4%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: -11.3%, p95_ms: -5.1%, p99_ms: +2.8%, requests_per_second: +17.6%, rss_bytes: -0.6% |
| search | stable | completed: +0.0%, cpu_percent: +1.1%, duration_seconds: +0.1%, p50_ms: -3.6%, p95_ms: -3.7%, p99_ms: -3.8%, requests_per_second: -0.1%, rss_bytes: -0.6% |
| cache_hit | stable | completed: +0.8%, cpu_percent: +1.1%, duration_seconds: +0.0%, p50_ms: -0.7%, p95_ms: -1.6%, p99_ms: +2.6%, requests_per_second: +0.7%, rss_bytes: -0.6% |
| cache_hit | stable | completed: +0.8%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -1.7%, p95_ms: -0.2%, p99_ms: -7.6%, requests_per_second: +0.8%, rss_bytes: -0.6% |
| cache_hit | stable | completed: +0.7%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -2.2%, p95_ms: -2.0%, p99_ms: -4.3%, requests_per_second: +0.8%, rss_bytes: -0.6% |
| cache_hit | stable | completed: +5.0%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: -4.3%, p95_ms: -3.5%, p99_ms: -4.4%, requests_per_second: +5.1%, rss_bytes: -0.6% |
| health_live | possible-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +10.0%, duration_seconds: +4.2%, p50_ms: +11.3%, p95_ms: -4.4%, p99_ms: -9.1%, requests_per_second: -5.2%, rss_bytes: -0.6% |
| thread | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +0.0%, duration_seconds: -4.9%, p50_ms: -3.0%, p95_ms: -18.0%, p99_ms: -19.4%, requests_per_second: +5.0%, rss_bytes: -0.6% |
| thread | stable | completed: +3.0%, cpu_percent: +2.9%, duration_seconds: -0.0%, p50_ms: +18.0%, p95_ms: -6.7%, p99_ms: -8.0%, requests_per_second: +3.0%, rss_bytes: -0.5% |
| thread | stable | completed: +1.8%, cpu_percent: +0.9%, duration_seconds: -0.1%, p50_ms: -3.8%, p95_ms: -8.0%, p99_ms: +4.1%, requests_per_second: +2.0%, rss_bytes: -0.4% |
| search | improvement | completed: +7.5%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -11.6%, p95_ms: -12.5%, p99_ms: -27.6%, requests_per_second: +7.2%, rss_bytes: -0.5% |
| search | stable | completed: +3.6%, cpu_percent: +1.3%, duration_seconds: -0.0%, p50_ms: +19.0%, p95_ms: -21.6%, p99_ms: -18.1%, requests_per_second: +3.6%, rss_bytes: -0.5% |
| cache_hit | stable | completed: +1.0%, cpu_percent: -0.1%, duration_seconds: +0.2%, p50_ms: -16.1%, p95_ms: -3.5%, p99_ms: +11.0%, requests_per_second: +1.2%, rss_bytes: -0.6% |
| cache_hit | possible-regression | completed: +1.0%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +14.6%, p95_ms: -8.2%, p99_ms: -19.8%, requests_per_second: +0.9%, rss_bytes: -0.6% |
| cache_miss | stable | completed: -0.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +0.3%, p95_ms: -0.8%, p99_ms: -7.0%, requests_per_second: -0.5%, rss_bytes: -0.5% |
| cache_miss | stable | completed: +5.8%, cpu_percent: -0.4%, duration_seconds: +4.8%, p50_ms: -1.2%, p95_ms: -5.9%, p99_ms: +0.8%, requests_per_second: +1.9%, rss_bytes: -0.6% |
| cache_miss | stable | completed: +3.4%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -1.7%, p95_ms: -3.8%, p99_ms: -4.0%, requests_per_second: +3.5%, rss_bytes: -0.6% |
| health_live | stable | completed: +2.6%, cpu_percent: +0.1%, duration_seconds: +5.0%, p50_ms: -0.6%, p95_ms: -3.2%, p99_ms: +3.3%, requests_per_second: +0.8%, rss_bytes: -0.5% |
| health_live | possible-regression | completed: -3.8%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: +1.2%, p95_ms: +15.8%, p99_ms: +8.8%, requests_per_second: -3.9%, rss_bytes: -0.5% |
| health_live | stable | completed: +0.7%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -1.7%, p95_ms: +1.1%, p99_ms: +18.8%, requests_per_second: +0.8%, rss_bytes: -0.5% |
| health_live | stable | completed: +0.8%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: -2.0%, p95_ms: -3.2%, p99_ms: +0.4%, requests_per_second: +0.8%, rss_bytes: -0.5% |
| home | stable | completed: +2.0%, cpu_percent: -1.1%, duration_seconds: -0.0%, p50_ms: -2.7%, p95_ms: -1.9%, p99_ms: -6.6%, requests_per_second: +2.1%, rss_bytes: -0.5% |
| home | stable | completed: -0.8%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: +1.0%, p95_ms: +10.5%, p99_ms: +0.9%, requests_per_second: -3.6%, rss_bytes: -0.5% |
| home | stable | completed: -0.3%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: +2.4%, p95_ms: +3.6%, p99_ms: +1.0%, requests_per_second: -0.4%, rss_bytes: -0.5% |
| categories | stable | completed: -0.4%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -0.3%, p95_ms: -0.1%, p99_ms: +0.5%, requests_per_second: -0.4%, rss_bytes: -0.5% |
| categories | stable | completed: -0.8%, cpu_percent: +0.3%, duration_seconds: -4.7%, p50_ms: -2.2%, p95_ms: -5.4%, p99_ms: -8.5%, requests_per_second: +3.0%, rss_bytes: -0.5% |
| categories | improvement | completed: +2.2%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: -15.0%, p99_ms: -18.5%, requests_per_second: +2.1%, rss_bytes: -0.5% |
| category | stable | completed: +3.0%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: -1.4%, p99_ms: -4.2%, requests_per_second: +0.1%, rss_bytes: -0.5% |
| category | stable | completed: +0.7%, cpu_percent: -0.0%, duration_seconds: -4.6%, p50_ms: -2.5%, p95_ms: +0.2%, p99_ms: +7.6%, requests_per_second: +2.3%, rss_bytes: -0.5% |
| category | stable | completed: +1.6%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -0.8%, p95_ms: -6.3%, p99_ms: -5.1%, requests_per_second: +1.6%, rss_bytes: -0.5% |
| thread | improvement | completed: +2.1%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -1.6%, p95_ms: -2.7%, p99_ms: -19.1%, requests_per_second: +2.1%, rss_bytes: -0.5% |
| thread | stable | completed: +5.2%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -2.0%, p95_ms: -6.7%, p99_ms: -2.0%, requests_per_second: +5.2%, rss_bytes: -0.5% |
| thread | stable | completed: +3.0%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -4.6%, p95_ms: -8.4%, p99_ms: -5.6%, requests_per_second: +3.2%, rss_bytes: -0.5% |
| thread | stable | completed: +1.3%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -1.7%, p95_ms: +4.5%, p99_ms: -3.9%, requests_per_second: +1.3%, rss_bytes: -0.5% |
| search | improvement | completed: +10.4%, cpu_percent: -3.6%, duration_seconds: +0.0%, p50_ms: -9.8%, p95_ms: -13.4%, p99_ms: -12.7%, requests_per_second: +10.3%, rss_bytes: -0.6% |
| search | improvement | completed: +9.4%, cpu_percent: -1.6%, duration_seconds: -4.6%, p50_ms: -4.4%, p95_ms: -24.6%, p99_ms: -4.0%, requests_per_second: +10.4%, rss_bytes: -0.5% |
| search | stable | completed: +0.0%, cpu_percent: +1.0%, duration_seconds: -0.1%, p50_ms: -1.2%, p95_ms: -13.9%, p99_ms: -11.7%, requests_per_second: +0.1%, rss_bytes: -0.5% |
| search | stable | completed: -0.5%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -4.5%, p95_ms: -4.8%, p99_ms: -9.9%, requests_per_second: -0.5%, rss_bytes: -0.5% |
| cache_hit | stable | completed: -0.2%, cpu_percent: -0.9%, duration_seconds: -0.1%, p50_ms: +0.8%, p95_ms: -2.8%, p99_ms: -1.3%, requests_per_second: -0.2%, rss_bytes: -0.5% |
| cache_hit | stable | completed: +0.0%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -1.6%, p95_ms: -1.6%, p99_ms: -2.6%, requests_per_second: +1.0%, rss_bytes: -0.5% |
| cache_hit | possible-regression | completed: +1.8%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -1.3%, p95_ms: -11.5%, p99_ms: +17.9%, requests_per_second: +1.8%, rss_bytes: -0.5% |
| cache_hit | stable | completed: +0.9%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -1.5%, p95_ms: -4.3%, p99_ms: -1.9%, requests_per_second: +0.9%, rss_bytes: -0.5% |
| thread | stable | completed: -1.4%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: -19.9%, p95_ms: +6.5%, p99_ms: +9.8%, requests_per_second: -0.3%, rss_bytes: -0.5% |
| thread | stable | completed: +1.1%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: -10.4%, p95_ms: +10.8%, p99_ms: +7.0%, requests_per_second: +1.1%, rss_bytes: -0.5% |
| search | stable | completed: -2.9%, cpu_percent: -11.4%, duration_seconds: -0.5%, p50_ms: +46.0%, p95_ms: +5.8%, p99_ms: +7.0%, requests_per_second: -3.0%, rss_bytes: -0.4% |
| search | stable | completed: +5.0%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: -2.2%, p95_ms: -1.3%, p99_ms: +0.6%, requests_per_second: +4.7%, rss_bytes: -0.3% |
| cache_hit | stable | completed: -47.9%, cpu_percent: -48.9%, duration_seconds: -0.0%, p50_ms: +43.4%, p95_ms: -1.1%, p99_ms: +16.8%, requests_per_second: -47.8%, rss_bytes: -0.3% |
| cache_hit | possible-regression | completed: +0.5%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: +8.1%, p95_ms: -8.9%, p99_ms: +12.6%, requests_per_second: +0.4%, rss_bytes: -0.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.9% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -22.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -22.9% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -10.7% |
| sql-plan-readers | improvement | sql_execution_ms: -14.3% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -19.4% |
| sql-plan-readers | improvement | sql_execution_ms: -12.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -20.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -31.9% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -14.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -11.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -10.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -31.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -6.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -14.3% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -14.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -8.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -8.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.5% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +74.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.1% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +54.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -12.1% |
| sql-plan-functions | improvement | nested_statements: +0.0%, sql_execution_ms: -12.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +12.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -18.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +54.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.5% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -1.4%, messages_per_second: +1.4%, p50_ms: -0.7%, p95_ms: -2.3%, p99_ms: -1.5% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -2.0%, messages_per_second: +2.1%, p50_ms: -2.1%, p95_ms: +2.4%, p99_ms: -0.2% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +0.2%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -1.5%, p95_ms: -2.8%, p99_ms: -16.9%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +4.1%, cpu_percent: -0.0%, duration_seconds: +4.8%, p50_ms: -14.9%, p95_ms: -12.5%, p99_ms: +23.3%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -0.1%, p95_ms: -6.8%, p99_ms: +1.0%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.4%, cpu_percent: -1.0%, duration_seconds: -0.0%, p50_ms: -2.6%, p95_ms: -3.2%, p99_ms: -5.6%, requests_per_second: +2.3%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -3.2%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: +0.6%, p95_ms: +13.1%, p99_ms: +7.3%, requests_per_second: -2.8%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.8%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -2.1%, p95_ms: -0.6%, p99_ms: +14.5%, requests_per_second: +1.8%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.0%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: -3.3%, p99_ms: +6.9%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: -2.4%, cpu_percent: -0.7%, duration_seconds: -4.7%, p50_ms: -1.1%, p95_ms: -10.3%, p99_ms: -5.4%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -0.9%, p95_ms: +4.3%, p99_ms: +8.7%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.6%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -4.1%, p95_ms: +2.9%, p99_ms: -1.5%, requests_per_second: -0.7%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.7%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -2.4%, p95_ms: -2.4%, p99_ms: -2.9%, requests_per_second: +2.6%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +3.4%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -3.3%, p95_ms: -4.4%, p99_ms: +11.3%, requests_per_second: +2.9%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.1%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +1.5%, p99_ms: +9.2%, requests_per_second: -0.0%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +5.9%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -4.6%, p95_ms: -4.4%, p99_ms: -4.0%, requests_per_second: +4.4%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.8%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -2.5%, p95_ms: -15.0%, p99_ms: +0.2%, requests_per_second: +2.8%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.4%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +1.8%, p95_ms: -0.8%, p99_ms: +3.1%, requests_per_second: +1.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.5%, cpu_percent: -0.0%, duration_seconds: -4.7%, p50_ms: -1.9%, p95_ms: -1.9%, p99_ms: -1.9%, requests_per_second: +2.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -2.5%, cpu_percent: -0.0%, duration_seconds: -4.6%, p50_ms: -1.6%, p95_ms: +10.1%, p99_ms: +42.2%, requests_per_second: +1.8%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.2%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: -0.7%, p95_ms: -3.4%, p99_ms: +7.4%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.8%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: +5.0%, p99_ms: +2.0%, requests_per_second: -1.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.6%, cpu_percent: -1.0%, duration_seconds: -4.7%, p50_ms: +0.2%, p95_ms: -2.2%, p99_ms: -5.6%, requests_per_second: +0.1%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.4%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: -6.2%, p99_ms: +6.0%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: +1.6%, p95_ms: -1.1%, p99_ms: -6.5%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -1.4%, p95_ms: -1.4%, p99_ms: -1.3%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.5%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -0.4%, p95_ms: -2.4%, p99_ms: -1.4%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +1.0%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: +6.3%, p99_ms: +28.0%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +1.0%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: -2.0%, p99_ms: +22.4%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +2.3%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -3.0%, p95_ms: -14.2%, p99_ms: +4.0%, requests_per_second: +2.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.6%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -27.1%, p95_ms: +0.2%, p99_ms: +8.7%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.8%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -10.3%, p95_ms: +0.1%, p99_ms: -12.8%, requests_per_second: +1.7%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -5.1%, cpu_percent: -12.4%, duration_seconds: -0.2%, p50_ms: -9.5%, p95_ms: +12.6%, p99_ms: +24.7%, requests_per_second: -4.9%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.8%, cpu_percent: -1.7%, duration_seconds: -0.1%, p50_ms: -14.1%, p95_ms: +14.1%, p99_ms: +6.5%, requests_per_second: +2.6%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -58.5%, cpu_percent: -63.9%, duration_seconds: -0.1%, p50_ms: +208.2%, p95_ms: +35.0%, p99_ms: +74.2%, requests_per_second: -58.4%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +1.3%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +1.0%, p95_ms: -18.9%, p99_ms: +9.1%, requests_per_second: +1.3%, rss_bytes: +0.5% |
| thread | workers=4 | 2 | 50 | improvement | completed: +45.6%, cpu_percent: +94.1%, duration_seconds: -0.0%, p50_ms: -15.5%, p95_ms: +3.3%, p99_ms: -3.8%, requests_per_second: +45.6%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +45.7%, cpu_percent: +92.0%, duration_seconds: +0.2%, p50_ms: -40.7%, p95_ms: +6.9%, p99_ms: -6.1%, requests_per_second: +45.8%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | improvement | completed: +26.0%, cpu_percent: +75.6%, duration_seconds: +0.4%, p50_ms: -36.4%, p95_ms: -2.9%, p99_ms: -9.9%, requests_per_second: +25.5%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +42.5%, cpu_percent: +81.9%, duration_seconds: +0.3%, p50_ms: -24.1%, p95_ms: -29.6%, p99_ms: -21.4%, requests_per_second: +42.2%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +20.3%, cpu_percent: +50.1%, duration_seconds: +0.1%, p50_ms: -36.6%, p95_ms: +41.1%, p99_ms: +49.7%, requests_per_second: +20.2%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +50.8%, cpu_percent: +94.2%, duration_seconds: +0.2%, p50_ms: -33.3%, p95_ms: -15.8%, p99_ms: -29.8%, requests_per_second: +50.7%, rss_bytes: +64.4% |
| thread | workers=4 | 2 | 50 | improvement | completed: +49.0%, cpu_percent: +93.2%, duration_seconds: +0.2%, p50_ms: -37.9%, p95_ms: +7.2%, p99_ms: -2.6%, requests_per_second: +47.9%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +51.0%, cpu_percent: +92.7%, duration_seconds: +0.1%, p50_ms: -47.1%, p95_ms: +1.9%, p99_ms: -19.8%, requests_per_second: +50.7%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +20.1%, cpu_percent: +55.1%, duration_seconds: +0.3%, p50_ms: -43.3%, p95_ms: +10.6%, p99_ms: +20.1%, requests_per_second: +19.8%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +47.2%, cpu_percent: +79.5%, duration_seconds: +0.3%, p50_ms: -33.9%, p95_ms: -18.6%, p99_ms: -15.1%, requests_per_second: +46.4%, rss_bytes: +64.6% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -50.5%, cpu_percent: -46.1%, duration_seconds: +0.0%, p50_ms: +97.6%, p95_ms: +94.5%, p99_ms: +112.9%, requests_per_second: -50.6%, rss_bytes: +64.6% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.3%, cpu_percent: +93.2%, duration_seconds: +0.1%, p50_ms: -30.6%, p95_ms: -20.5%, p99_ms: -26.3%, requests_per_second: +49.2%, rss_bytes: +64.6% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38693699497)
