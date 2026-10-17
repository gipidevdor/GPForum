# GPForum continuous performance evidence

Commit: `0db21a94d05768f187d6d93fc8e530c080172185` · mode: **main** · status: **ok**
Run: 38631562388 / attempt 1 · 2026-10-14T20:23:21.082858+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"ad45a8bbcd08fe7e6f669798565032b3a9737be3220bb15df4e052240

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 277.218 | 3.575 | 3.701 | 4.269 | 99.983 / 370.461 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 551.571 | 18.059 | 18.671 | 24.177 | 199.400 / 370.473 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 536.990 | 89.862 | 109.741 | 158.062 | 201.862 / 372.133 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1150.344 | 0.856 | 0.924 | 0.957 | 99.482 / 370.469 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2230.814 | 4.380 | 5.253 | 5.426 | 199.453 / 370.469 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2345.658 | 21.123 | 21.734 | 25.470 | 200.338 / 371.117 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2266.320 | 43.264 | 50.610 | 63.830 | 200.757 / 372.383 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 117.854 | 8.344 | 8.828 | 9.761 | 86.547 / 372.816 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 221.243 | 43.243 | 54.581 | 73.994 | 173.997 / 373.168 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 214.169 | 216.614 | 357.807 | 435.477 | 174.237 / 374.867 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 868.884 | 1.136 | 1.209 | 1.267 | 99.573 / 374.867 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1707.866 | 5.788 | 5.989 | 7.355 | 198.917 / 374.867 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1758.901 | 28.058 | 30.303 | 37.656 | 200.648 / 374.867 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 849.945 | 1.155 | 1.237 | 1.327 | 99.513 / 375.012 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1652.440 | 5.934 | 6.278 | 8.740 | 199.889 / 375.031 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1681.248 | 30.965 | 35.858 | 42.173 | 201.355 / 375.211 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 841.491 | 1.170 | 1.237 | 1.315 | 98.981 / 375.273 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1657.568 | 6.014 | 6.301 | 6.916 | 199.401 / 375.336 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1697.027 | 29.076 | 29.997 | 37.769 | 200.848 / 375.777 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1655.004 | 59.644 | 61.939 | 93.952 | 201.298 / 378.988 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 74.863 | 13.075 | 13.929 | 15.032 | 66.148 / 379.629 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 131.893 | 72.598 | 85.351 | 130.406 | 132.692 / 379.629 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 122.225 | 369.751 | 650.826 | 704.746 | 132.755 / 379.629 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.809 | 725.912 | 1367.116 | 1425.730 | 131.402 / 379.629 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 847.602 | 1.165 | 1.236 | 1.472 | 100.052 / 379.629 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1698.722 | 5.861 | 6.023 | 7.562 | 199.427 / 379.629 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1746.308 | 28.273 | 28.879 | 37.011 | 200.386 / 379.629 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1720.877 | 56.867 | 60.397 | 93.527 | 200.857 / 379.629 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1350.366 | 6.434 | 9.847 | 14.140 | 24.811 / 379.629 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 997.426 | 8.900 | 12.625 | 14.002 | 37.789 / 379.934 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2452.977 | 18.714 | 34.578 | 38.957 | 387.454 / 617.145 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2410.994 | 41.217 | 91.664 | 121.866 | 380.870 / 622.031 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 155.633 | 209.659 | 701.988 | 912.450 | 233.134 / 623.410 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 141.933 | 443.651 | 1328.352 | 1460.933 | 240.207 / 625.031 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2497.447 | 18.441 | 31.603 | 37.126 | 389.117 / 625.051 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2492.374 | 37.568 | 52.077 | 70.702 | 385.397 / 625.051 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 278.117 | 3.571 | 3.683 | 3.962 | 99.462 / 371.812 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 547.039 | 18.088 | 18.590 | 28.029 | 199.874 / 371.812 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 536.442 | 90.360 | 97.807 | 163.012 | 201.383 / 373.613 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1182.356 | 0.827 | 0.895 | 0.986 | 100.000 / 371.820 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2336.086 | 4.238 | 4.403 | 5.318 | 198.930 / 371.820 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2370.526 | 20.941 | 21.604 | 26.161 | 199.410 / 372.570 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2319.122 | 42.288 | 43.920 | 63.139 | 199.377 / 373.934 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 118.093 | 8.330 | 8.969 | 10.352 | 86.569 / 374.305 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 221.958 | 42.850 | 52.582 | 79.710 | 173.171 / 374.711 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 224.131 | 217.189 | 329.910 | 407.046 | 174.169 / 376.438 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 885.535 | 1.112 | 1.172 | 1.241 | 100.049 / 376.438 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1731.016 | 5.699 | 5.912 | 7.274 | 199.398 / 376.438 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1757.517 | 27.794 | 29.201 | 37.656 | 200.880 / 376.438 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 856.649 | 1.158 | 1.215 | 1.272 | 99.038 / 376.469 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1703.197 | 5.825 | 6.087 | 7.528 | 199.432 / 376.469 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1733.899 | 28.507 | 29.644 | 38.013 | 200.887 / 376.469 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 859.810 | 1.146 | 1.220 | 1.410 | 99.461 / 376.594 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1698.639 | 5.797 | 6.143 | 9.085 | 198.908 / 376.594 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1704.781 | 28.747 | 30.293 | 42.038 | 200.881 / 377.156 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1624.658 | 59.105 | 72.128 | 110.420 | 201.315 / 380.461 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 74.896 | 13.186 | 13.789 | 14.545 | 65.695 / 381.086 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 133.804 | 72.918 | 83.673 | 135.969 | 132.748 / 381.086 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.237 | 383.644 | 655.576 | 729.314 | 132.911 / 381.086 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.755 | 721.614 | 1377.011 | 1432.103 | 131.934 / 381.211 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 872.876 | 1.113 | 1.207 | 1.426 | 99.485 / 381.250 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1735.726 | 5.695 | 6.534 | 8.131 | 198.932 / 381.250 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1771.078 | 27.943 | 28.900 | 39.520 | 200.896 / 381.250 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1744.877 | 55.936 | 57.925 | 89.958 | 200.384 / 381.250 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2473.203 | 20.034 | 34.473 | 45.433 | 386.953 / 618.949 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2454.945 | 37.747 | 52.913 | 65.762 | 385.687 / 623.055 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 161.548 | 252.326 | 706.729 | 874.542 | 232.456 / 624.656 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 143.758 | 547.559 | 1381.275 | 1533.530 | 226.226 / 625.398 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1755.417 | 27.441 | 36.694 | 50.369 | 227.285 / 625.398 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2530.406 | 37.417 | 53.869 | 65.658 | 389.904 / 625.504 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.495 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.032 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.502 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.544 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.094 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.520 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.994 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.110 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.567 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.536 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.284 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.330 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.077 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.046 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.019 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.418 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.421 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.544 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.438 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.518 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.270 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.564 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.899 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.324 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.189 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.163 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.184 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.021 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.086 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.105 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.055 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.097 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 684.614 | 143.765 | 154.181 | 162.302 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1167.696 | 166.765 | 184.401 | 185.194 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.3%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -0.1%, p95_ms: -0.5%, p99_ms: -7.2%, requests_per_second: +0.3%, rss_bytes: +0.4% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +4.1%, cpu_percent: +0.2%, duration_seconds: +4.9%, p50_ms: +0.2%, p95_ms: -0.4%, p99_ms: +15.9%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.1%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: -10.9%, p99_ms: +3.1%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.8%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -3.4%, p95_ms: -3.1%, p99_ms: +3.0%, requests_per_second: +2.8%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +5.3%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -3.2%, p95_ms: -16.2%, p99_ms: -2.0%, requests_per_second: +4.7%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.0%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -0.9%, p95_ms: -0.6%, p99_ms: +2.7%, requests_per_second: +1.1%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +2.4%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: -2.3%, p95_ms: -13.2%, p99_ms: -1.1%, requests_per_second: +2.3%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.8%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: +1.6%, p99_ms: +6.1%, requests_per_second: +0.2%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +4.1%, cpu_percent: -0.5%, duration_seconds: +4.8%, p50_ms: -0.9%, p95_ms: -3.7%, p99_ms: +7.7%, requests_per_second: +0.3%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +4.7%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: -7.8%, p99_ms: -6.5%, requests_per_second: +4.7%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.9%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: -2.1%, p95_ms: -3.1%, p99_ms: -2.1%, requests_per_second: +1.9%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.0%, cpu_percent: +0.2%, duration_seconds: -4.6%, p50_ms: -1.5%, p95_ms: -1.3%, p99_ms: -1.1%, requests_per_second: +1.4%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.0%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -0.9%, p95_ms: -3.6%, p99_ms: +0.0%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.9%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +0.3%, p95_ms: -1.8%, p99_ms: -4.1%, requests_per_second: +0.8%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +3.1%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -1.8%, p95_ms: -3.0%, p99_ms: -13.9%, requests_per_second: +3.1%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +3.1%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -7.9%, p95_ms: -17.3%, p99_ms: -9.9%, requests_per_second: +3.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.5%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -2.1%, p95_ms: -1.4%, p99_ms: +7.2%, requests_per_second: +2.2%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +3.0%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -3.6%, p95_ms: -2.5%, p99_ms: +31.4%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +0.4%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: +1.0%, p99_ms: +11.3%, requests_per_second: +0.5%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.7%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -0.9%, p95_ms: +16.4%, p99_ms: +17.5%, requests_per_second: -1.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.0%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: +0.8%, p95_ms: -1.0%, p99_ms: -3.2%, requests_per_second: +0.0%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -2.9%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +0.4%, p95_ms: -2.0%, p99_ms: +4.3%, requests_per_second: +1.4%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +3.8%, p95_ms: +0.7%, p99_ms: +3.5%, requests_per_second: +1.6%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: +0.7%, p99_ms: +0.4%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.0%, cpu_percent: -0.6%, duration_seconds: -0.1%, p50_ms: -4.5%, p95_ms: -2.3%, p99_ms: -3.1%, requests_per_second: +3.0%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.1%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -2.8%, p95_ms: +8.5%, p99_ms: +7.5%, requests_per_second: +2.2%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.3%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: -1.2%, p95_ms: +0.1%, p99_ms: +6.8%, requests_per_second: +1.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.4%, cpu_percent: -0.2%, duration_seconds: +0.2%, p50_ms: -1.6%, p95_ms: -4.1%, p99_ms: -3.8%, requests_per_second: +1.4%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +0.3%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +7.1%, p95_ms: -0.3%, p99_ms: +16.6%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +1.8%, cpu_percent: +1.3%, duration_seconds: +0.0%, p50_ms: -8.4%, p95_ms: -42.3%, p99_ms: -46.0%, requests_per_second: +1.8%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +3.8%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +20.4%, p95_ms: +0.7%, p99_ms: -4.2%, requests_per_second: +3.8%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.8%, cpu_percent: -5.8%, duration_seconds: +0.2%, p50_ms: +23.4%, p95_ms: +4.0%, p99_ms: +5.0%, requests_per_second: +1.3%, rss_bytes: +0.1% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -29.7%, cpu_percent: -41.6%, duration_seconds: +0.1%, p50_ms: +48.8%, p95_ms: +16.1%, p99_ms: +35.7%, requests_per_second: -29.7%, rss_bytes: +0.1% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.4%, cpu_percent: +1.2%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: +3.4%, p99_ms: -7.1%, requests_per_second: +1.5%, rss_bytes: +0.1% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +45.7%, cpu_percent: +92.9%, duration_seconds: +0.1%, p50_ms: -35.6%, p95_ms: +15.3%, p99_ms: +3.1%, requests_per_second: +44.5%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +46.1%, cpu_percent: +89.2%, duration_seconds: +0.3%, p50_ms: -30.9%, p95_ms: +48.0%, p99_ms: +29.7%, requests_per_second: +45.7%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +25.2%, cpu_percent: +75.6%, duration_seconds: +0.2%, p50_ms: -43.3%, p95_ms: +7.9%, p99_ms: +29.5%, requests_per_second: +27.3%, rss_bytes: +64.2% |
| search | workers=4 | 2 | 100 | improvement | completed: +42.5%, cpu_percent: +82.8%, duration_seconds: +0.2%, p50_ms: -38.9%, p95_ms: -2.8%, p99_ms: +2.5%, requests_per_second: +42.2%, rss_bytes: +64.6% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +43.0%, cpu_percent: +94.2%, duration_seconds: +0.0%, p50_ms: -34.8%, p95_ms: +9.4%, p99_ms: +0.3%, requests_per_second: +43.0%, rss_bytes: +64.6% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +45.0%, cpu_percent: +91.9%, duration_seconds: +0.1%, p50_ms: -33.9%, p95_ms: -13.8%, p99_ms: -24.4%, requests_per_second: +44.8%, rss_bytes: +64.6% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +45.4%, cpu_percent: +92.6%, duration_seconds: +0.1%, p50_ms: -30.3%, p95_ms: +13.8%, p99_ms: +8.1%, requests_per_second: +45.1%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +51.4%, cpu_percent: +91.6%, duration_seconds: +0.2%, p50_ms: -36.1%, p95_ms: -26.6%, p99_ms: -40.4%, requests_per_second: +51.1%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +30.5%, cpu_percent: +74.9%, duration_seconds: +0.3%, p50_ms: -34.2%, p95_ms: +7.8%, p99_ms: +19.9%, requests_per_second: +30.0%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +45.0%, cpu_percent: +71.5%, duration_seconds: +0.3%, p50_ms: -24.1%, p95_ms: +0.3%, p99_ms: +7.1%, requests_per_second: +44.1%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -0.8%, cpu_percent: +13.1%, duration_seconds: +0.2%, p50_ms: -1.8%, p95_ms: +27.0%, p99_ms: +27.5%, requests_per_second: -0.9%, rss_bytes: +64.0% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +44.9%, cpu_percent: +94.6%, duration_seconds: -0.1%, p50_ms: -33.1%, p95_ms: -7.0%, p99_ms: -27.0%, requests_per_second: +45.0%, rss_bytes: +64.1% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38631562388)
