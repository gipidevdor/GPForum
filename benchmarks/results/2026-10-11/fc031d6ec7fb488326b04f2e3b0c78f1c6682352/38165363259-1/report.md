# GPForum continuous performance evidence

Commit: `fc031d6ec7fb488326b04f2e3b0c78f1c6682352` · mode: **main** · status: **ok**
Run: 38165363259 / attempt 1 · 2026-10-11T18:49:04.402626+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"ee7d3093ffc5cd7d0cc2f564417c6ad7f1e113aa0c1316b1b59386e9b

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 273.677 | 3.626 | 3.757 | 4.300 | 99.945 / 369.730 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 542.754 | 17.947 | 19.007 | 22.519 | 199.992 / 369.758 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 527.179 | 90.712 | 104.443 | 161.597 | 200.789 / 371.441 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1151.834 | 0.854 | 0.922 | 0.999 | 99.527 / 369.801 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2292.043 | 4.326 | 4.520 | 5.529 | 199.365 / 369.801 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2321.337 | 21.349 | 22.167 | 24.994 | 199.811 / 370.453 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2237.626 | 43.688 | 46.884 | 65.427 | 200.279 / 371.699 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 116.822 | 8.416 | 9.371 | 10.476 | 86.071 / 372.148 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 214.265 | 45.895 | 58.847 | 71.513 | 173.938 / 372.520 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 199.596 | 222.616 | 369.673 | 451.043 | 174.083 / 374.227 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 875.743 | 1.123 | 1.203 | 1.277 | 100.013 / 374.227 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1705.285 | 5.780 | 6.142 | 8.490 | 198.847 / 374.227 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1760.754 | 28.144 | 29.372 | 35.668 | 200.318 / 374.227 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 860.467 | 1.150 | 1.210 | 1.256 | 99.480 / 374.250 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1663.637 | 5.886 | 6.501 | 8.200 | 199.161 / 374.258 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1697.022 | 29.000 | 30.190 | 39.320 | 199.830 / 374.258 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 841.008 | 1.169 | 1.270 | 1.723 | 98.989 / 374.383 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1670.616 | 5.942 | 6.153 | 7.262 | 198.872 / 374.383 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1677.863 | 29.638 | 31.618 | 39.208 | 201.210 / 374.969 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1638.521 | 59.953 | 62.766 | 96.922 | 201.270 / 378.188 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 71.418 | 13.756 | 15.545 | 17.365 | 66.590 / 379.035 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 126.342 | 76.318 | 87.000 | 133.546 | 133.139 / 379.035 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.739 | 373.175 | 644.294 | 730.720 | 132.387 / 379.035 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.813 | 815.806 | 1507.383 | 1570.215 | 132.900 / 379.035 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 860.924 | 1.146 | 1.219 | 1.259 | 99.521 / 379.035 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1688.372 | 5.833 | 6.278 | 7.737 | 198.364 / 379.035 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1721.473 | 28.550 | 30.917 | 36.713 | 200.708 / 379.035 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1695.291 | 58.697 | 60.386 | 92.114 | 200.758 / 379.035 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1329.841 | 6.648 | 10.685 | 14.770 | 27.049 / 379.035 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 960.006 | 9.808 | 14.444 | 16.304 | 37.188 / 379.324 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2413.674 | 21.506 | 30.553 | 42.601 | 379.175 / 616.023 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2439.820 | 39.270 | 52.197 | 72.358 | 386.246 / 619.645 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 151.861 | 249.536 | 642.301 | 871.274 | 232.381 / 621.094 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 143.803 | 547.314 | 1125.469 | 1223.262 | 244.154 / 622.102 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2088.793 | 24.320 | 40.442 | 56.887 | 301.318 / 622.102 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2490.128 | 37.501 | 53.076 | 63.715 | 387.635 / 622.102 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 276.036 | 3.598 | 3.709 | 4.226 | 99.932 / 370.461 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 547.056 | 18.075 | 19.043 | 25.469 | 199.323 / 370.480 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 533.964 | 91.050 | 96.623 | 166.240 | 201.266 / 372.273 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1197.399 | 0.827 | 0.885 | 0.940 | 99.458 / 370.738 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2297.565 | 4.311 | 4.504 | 5.057 | 198.882 / 370.738 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2319.053 | 21.225 | 22.571 | 27.133 | 200.311 / 371.496 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2207.243 | 45.678 | 53.735 | 66.936 | 199.317 / 372.883 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 113.887 | 8.582 | 9.703 | 11.759 | 86.035 / 373.312 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 215.722 | 45.041 | 53.660 | 80.601 | 174.427 / 373.695 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 199.053 | 227.473 | 365.793 | 436.560 | 174.197 / 375.453 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 891.619 | 1.111 | 1.170 | 1.261 | 99.546 / 375.453 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1727.955 | 5.724 | 6.377 | 8.498 | 199.798 / 375.453 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1745.689 | 28.452 | 29.522 | 38.175 | 200.812 / 375.453 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 862.531 | 1.138 | 1.212 | 1.276 | 99.491 / 375.469 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1687.383 | 5.882 | 6.096 | 8.680 | 198.909 / 375.484 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1694.663 | 29.108 | 32.487 | 40.670 | 200.295 / 375.617 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 853.365 | 1.154 | 1.239 | 1.400 | 99.520 / 375.766 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1663.340 | 5.905 | 6.343 | 10.230 | 199.340 / 375.766 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1681.124 | 29.431 | 31.628 | 44.021 | 201.299 / 376.293 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1658.594 | 59.012 | 60.830 | 96.702 | 200.778 / 379.508 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 71.458 | 13.931 | 15.047 | 16.473 | 66.654 / 380.039 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 127.826 | 75.571 | 90.764 | 145.757 | 134.582 / 380.039 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 123.716 | 384.751 | 664.524 | 744.160 | 133.302 / 380.039 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.256 | 770.773 | 1472.154 | 1529.103 | 132.878 / 380.039 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 901.023 | 1.098 | 1.155 | 1.256 | 98.978 / 380.039 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1699.854 | 5.839 | 6.128 | 8.045 | 198.862 / 380.039 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1708.551 | 28.733 | 29.846 | 40.163 | 200.788 / 380.039 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1692.687 | 57.069 | 62.147 | 93.182 | 200.666 / 380.039 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2428.203 | 18.263 | 33.185 | 47.295 | 384.448 / 617.699 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2420.452 | 35.274 | 66.593 | 76.701 | 388.614 / 621.867 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 157.031 | 244.176 | 678.685 | 892.463 | 236.455 / 623.254 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 151.060 | 557.134 | 1132.566 | 1339.141 | 243.209 / 623.805 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1679.233 | 21.207 | 52.074 | 67.925 | 206.353 / 624.590 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2529.832 | 37.396 | 52.568 | 63.439 | 388.165 / 624.590 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.477 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.031 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.500 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.562 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.092 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.518 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.992 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.113 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.097 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.029 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.447 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.537 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.298 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.331 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.079 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.046 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.023 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.412 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.481 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.558 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.452 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.890 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.269 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.318 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.118 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.347 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.196 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.170 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.192 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.085 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.086 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.073 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.063 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 676.231 | 146.531 | 153.652 | 165.534 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1150.503 | 170.257 | 194.919 | 195.209 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: -1.3%, p99_ms: -1.7%, requests_per_second: +0.9%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.6%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: +0.7%, p95_ms: +0.2%, p99_ms: +13.1%, requests_per_second: +0.8%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.2%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: -7.5%, p99_ms: +2.9%, requests_per_second: +1.3%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +6.9%, cpu_percent: -0.1%, duration_seconds: +4.9%, p50_ms: -3.2%, p95_ms: -4.0%, p99_ms: -5.9%, requests_per_second: +4.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +5.0%, cpu_percent: -0.2%, duration_seconds: +4.9%, p50_ms: -0.3%, p95_ms: -0.4%, p99_ms: -8.5%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.1%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: +1.8%, p99_ms: +8.6%, requests_per_second: -0.1%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -1.2%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +4.6%, p95_ms: +14.6%, p99_ms: +2.3%, requests_per_second: -1.4%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.6%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +2.0%, p95_ms: +3.5%, p99_ms: +12.2%, requests_per_second: -2.5%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.9%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -1.9%, p95_ms: -8.8%, p99_ms: +12.7%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.2%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +2.2%, p95_ms: -1.1%, p99_ms: -3.2%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.9%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -1.1%, p95_ms: -2.7%, p99_ms: -1.3%, requests_per_second: +1.8%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.3%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -1.0%, p95_ms: +3.8%, p99_ms: +0.1%, requests_per_second: +1.3%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.8%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: +1.1%, p95_ms: +0.5%, p99_ms: +7.0%, requests_per_second: -0.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.2%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -1.0%, p95_ms: +0.2%, p99_ms: +1.6%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.5%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -0.1%, p95_ms: -6.2%, p99_ms: +5.9%, requests_per_second: +1.4%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.2%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +0.4%, p95_ms: +7.6%, p99_ms: +3.4%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.0%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -1.3%, p95_ms: -2.4%, p99_ms: -18.7%, requests_per_second: +1.5%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +2.0%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -0.6%, p95_ms: +3.1%, p99_ms: +40.9%, requests_per_second: -0.4%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.1%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.7%, p95_ms: +0.0%, p99_ms: +12.3%, requests_per_second: +0.2%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.3%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -1.6%, p95_ms: -3.1%, p99_ms: -0.2%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.0%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: +1.3%, p95_ms: -3.2%, p99_ms: -5.1%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.2%, cpu_percent: +1.1%, duration_seconds: -0.0%, p50_ms: -1.0%, p95_ms: +4.3%, p99_ms: +9.1%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.8%, cpu_percent: +0.7%, duration_seconds: +0.0%, p50_ms: +3.1%, p95_ms: +3.1%, p99_ms: +1.8%, requests_per_second: -0.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -5.5%, p95_ms: -2.3%, p99_ms: -2.6%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.7%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -4.2%, p95_ms: -5.2%, p99_ms: -0.2%, requests_per_second: +4.7%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -2.6%, cpu_percent: +0.3%, duration_seconds: -4.7%, p50_ms: +0.1%, p95_ms: -2.4%, p99_ms: +4.0%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.8%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +0.6%, p95_ms: -3.5%, p99_ms: +9.4%, requests_per_second: -0.8%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.1%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -2.8%, p95_ms: +2.9%, p99_ms: +1.2%, requests_per_second: -0.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +3.9%, cpu_percent: +1.4%, duration_seconds: +4.6%, p50_ms: -15.1%, p95_ms: +8.6%, p99_ms: +11.0%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -0.8%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -10.2%, p95_ms: +27.6%, p99_ms: +6.0%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.9%, cpu_percent: +1.8%, duration_seconds: +0.1%, p50_ms: -2.1%, p95_ms: +5.7%, p99_ms: +2.4%, requests_per_second: +3.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +5.2%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: +1.8%, p95_ms: +0.6%, p99_ms: +9.5%, requests_per_second: +5.0%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -19.6%, cpu_percent: -31.5%, duration_seconds: +0.0%, p50_ms: -12.8%, p95_ms: +28.8%, p99_ms: +19.4%, requests_per_second: -19.6%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.2%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -0.3%, p95_ms: -1.0%, p99_ms: -0.4%, requests_per_second: +1.6%, rss_bytes: +0.4% |
| thread | workers=4 | 2 | 50 | improvement | completed: +44.1%, cpu_percent: +88.4%, duration_seconds: +0.2%, p50_ms: -27.4%, p95_ms: -3.4%, p99_ms: +8.7%, requests_per_second: +43.9%, rss_bytes: +64.3% |
| thread | workers=4 | 2 | 100 | improvement | completed: +49.1%, cpu_percent: +91.9%, duration_seconds: +0.2%, p50_ms: -34.5%, p95_ms: -16.8%, p99_ms: -25.3%, requests_per_second: +48.9%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +22.4%, cpu_percent: +75.5%, duration_seconds: +0.2%, p50_ms: -33.1%, p95_ms: -0.3%, p99_ms: +19.2%, requests_per_second: +21.7%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +44.5%, cpu_percent: +83.7%, duration_seconds: +0.3%, p50_ms: -32.9%, p95_ms: -25.3%, p99_ms: -22.1%, requests_per_second: +44.1%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +21.4%, cpu_percent: +50.1%, duration_seconds: +0.1%, p50_ms: -14.8%, p95_ms: +30.8%, p99_ms: +55.0%, requests_per_second: +21.3%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +47.6%, cpu_percent: +93.1%, duration_seconds: +0.2%, p50_ms: -36.1%, p95_ms: -12.1%, p99_ms: -30.8%, requests_per_second: +46.9%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 50 | improvement | completed: +49.6%, cpu_percent: +91.0%, duration_seconds: +4.9%, p50_ms: -37.9%, p95_ms: +4.9%, p99_ms: +7.4%, requests_per_second: +44.4%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | improvement | completed: +46.0%, cpu_percent: +93.6%, duration_seconds: +0.1%, p50_ms: -40.2%, p95_ms: +9.5%, p99_ms: -20.7%, requests_per_second: +45.9%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +27.0%, cpu_percent: +77.4%, duration_seconds: +0.2%, p50_ms: -36.5%, p95_ms: +2.1%, p99_ms: +19.9%, requests_per_second: +26.9%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +52.8%, cpu_percent: +83.0%, duration_seconds: +0.2%, p50_ms: -27.7%, p95_ms: -23.1%, p99_ms: -12.4%, requests_per_second: +52.2%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -1.6%, cpu_percent: +2.8%, duration_seconds: +0.1%, p50_ms: -26.2%, p95_ms: +74.5%, p99_ms: +69.1%, requests_per_second: -1.7%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.5%, cpu_percent: +93.4%, duration_seconds: +0.0%, p50_ms: -34.5%, p95_ms: -15.4%, p99_ms: -31.9%, requests_per_second: +49.5%, rss_bytes: +64.3% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38165363259)
