# GPForum continuous performance evidence

Commit: `bee838a21c91513f92fb332575009608e33232a6` · mode: **main** · status: **ok**
Run: 38637824251 / attempt 1 · 2026-10-14T21:08:27.479285+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"ad45a8bbcd08fe7e6f669798565032b3a9737be3220bb15df4e052240

Baseline: Compatible baseline. 0db21a94d05768f187d6d93fc8e530c080172185

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 281.455 | 3.529 | 3.644 | 4.047 | 99.924 / 370.348 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 548.773 | 17.892 | 18.766 | 24.394 | 199.429 / 370.348 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 547.215 | 88.640 | 94.907 | 157.164 | 201.381 / 372.039 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1159.344 | 0.850 | 0.915 | 0.983 | 99.501 / 370.652 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2234.688 | 4.404 | 4.935 | 5.907 | 199.343 / 370.652 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2330.407 | 21.140 | 22.870 | 24.541 | 200.424 / 371.301 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2269.637 | 42.908 | 47.190 | 64.359 | 199.936 / 372.531 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 119.467 | 8.253 | 8.775 | 10.228 | 87.070 / 372.730 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 224.539 | 43.558 | 52.426 | 64.034 | 174.049 / 373.348 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 211.542 | 219.010 | 339.817 | 412.438 | 174.267 / 375.094 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 846.752 | 1.178 | 1.219 | 1.269 | 99.488 / 375.094 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1745.221 | 4.758 | 6.870 | 7.348 | 198.919 / 375.094 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1772.649 | 27.970 | 28.808 | 34.973 | 200.923 / 375.094 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 852.995 | 1.159 | 1.246 | 1.675 | 99.461 / 375.125 | possible-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1676.466 | 5.924 | 6.152 | 7.363 | 199.463 / 375.137 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1709.069 | 28.761 | 32.060 | 36.639 | 200.427 / 375.137 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 842.457 | 1.177 | 1.263 | 1.440 | 99.473 / 375.375 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1685.443 | 5.889 | 6.196 | 6.836 | 199.930 / 375.375 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1663.416 | 29.474 | 31.556 | 43.906 | 200.216 / 375.941 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1645.545 | 58.348 | 69.603 | 97.661 | 201.653 / 379.148 | possible-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 73.989 | 13.288 | 14.423 | 16.313 | 65.681 / 379.703 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 134.445 | 73.151 | 91.341 | 132.925 | 132.304 / 379.773 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.702 | 357.371 | 606.539 | 674.322 | 129.947 / 379.773 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.765 | 727.537 | 1375.436 | 1430.488 | 131.941 / 379.773 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 864.780 | 1.144 | 1.206 | 1.269 | 99.550 / 379.773 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1695.752 | 5.797 | 6.111 | 7.607 | 198.956 / 379.773 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1759.147 | 28.063 | 29.833 | 36.525 | 200.918 / 379.773 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1719.040 | 57.493 | 69.053 | 90.022 | 199.333 / 379.773 | possible-regression |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1365.898 | 6.191 | 9.408 | 12.574 | 27.281 / 379.773 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1004.438 | 9.072 | 13.526 | 17.651 | 36.073 / 380.055 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2510.777 | 24.234 | 33.669 | 44.284 | 386.142 / 616.875 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2486.846 | 33.080 | 69.993 | 82.613 | 386.393 / 621.305 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 137.542 | 316.051 | 729.229 | 935.623 | 186.420 / 622.711 | possible-regression |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 153.588 | 501.042 | 1109.379 | 1112.769 | 235.319 / 623.984 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2197.982 | 17.793 | 30.497 | 38.459 | 300.027 / 623.984 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2569.041 | 33.099 | 63.909 | 75.577 | 387.847 / 624.043 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 279.521 | 3.551 | 3.664 | 3.968 | 99.964 / 371.504 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 553.482 | 17.915 | 18.382 | 24.343 | 200.422 / 371.504 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 545.348 | 89.363 | 95.196 | 156.765 | 201.322 / 373.293 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1205.684 | 0.818 | 0.886 | 0.951 | 99.509 / 371.551 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2332.605 | 4.259 | 4.422 | 5.021 | 199.422 / 371.551 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2354.583 | 20.995 | 22.639 | 24.883 | 200.429 / 372.340 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2296.787 | 42.442 | 48.679 | 64.105 | 200.304 / 373.738 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 121.306 | 8.186 | 8.417 | 8.798 | 86.065 / 374.133 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 226.853 | 42.138 | 57.337 | 79.499 | 172.949 / 374.535 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 223.509 | 211.404 | 327.808 | 397.768 | 174.805 / 376.309 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 892.844 | 1.102 | 1.173 | 1.210 | 99.495 / 376.309 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1739.539 | 5.635 | 6.230 | 8.800 | 199.431 / 376.309 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1744.320 | 28.038 | 30.185 | 37.034 | 200.899 / 376.309 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 868.339 | 1.142 | 1.201 | 1.247 | 99.566 / 376.465 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1694.000 | 5.868 | 7.134 | 7.782 | 198.462 / 376.465 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1707.477 | 28.834 | 30.951 | 39.208 | 200.402 / 376.465 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 867.234 | 1.131 | 1.208 | 1.254 | 99.520 / 376.527 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1673.445 | 5.902 | 6.522 | 10.128 | 199.277 / 376.590 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1705.979 | 28.898 | 29.981 | 42.557 | 199.884 / 377.113 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1693.817 | 57.607 | 59.361 | 97.516 | 200.860 / 380.340 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 76.398 | 12.905 | 13.666 | 16.154 | 64.689 / 380.699 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 137.317 | 69.173 | 81.670 | 128.538 | 130.292 / 380.965 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.175 | 363.852 | 606.870 | 684.675 | 130.482 / 380.965 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.196 | 715.458 | 1348.345 | 1405.960 | 129.405 / 381.137 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 858.212 | 1.163 | 1.203 | 1.253 | 99.474 / 381.137 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1737.843 | 5.751 | 6.001 | 7.927 | 199.427 / 381.137 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1750.887 | 28.018 | 31.118 | 36.378 | 200.211 / 381.137 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1752.491 | 56.460 | 58.580 | 89.820 | 200.376 / 381.137 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2495.272 | 21.498 | 33.555 | 47.788 | 386.469 / 618.984 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2521.015 | 35.182 | 68.355 | 81.136 | 387.261 / 622.938 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 162.079 | 190.808 | 756.447 | 835.148 | 234.969 / 624.938 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 166.034 | 493.427 | 1151.503 | 1305.852 | 236.094 / 626.090 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1628.049 | 35.203 | 39.502 | 50.218 | 218.519 / 626.945 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2565.439 | 37.105 | 60.272 | 75.844 | 389.532 / 626.945 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.496 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.031 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.502 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.560 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.092 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.497 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.954 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.101 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.094 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.023 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.464 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.550 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.278 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.370 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.044 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.020 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.466 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.435 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.538 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.429 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.478 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.272 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.369 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.974 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.304 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.186 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.160 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.183 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.051 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.087 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.113 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.080 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.096 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 667.070 | 148.300 | 157.781 | 164.557 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1123.590 | 172.210 | 200.056 | 200.784 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: +1.6%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -1.3%, p95_ms: -1.5%, p99_ms: -5.2%, requests_per_second: +1.5%, rss_bytes: -0.0% |
| cache_miss | stable | completed: -0.5%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.9%, p95_ms: +0.5%, p99_ms: +0.9%, requests_per_second: -0.5%, rss_bytes: -0.0% |
| cache_miss | stable | completed: +2.1%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -1.4%, p95_ms: -13.5%, p99_ms: -0.6%, requests_per_second: +1.9%, rss_bytes: -0.0% |
| health_live | stable | completed: +0.5%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.7%, p95_ms: -1.0%, p99_ms: +2.7%, requests_per_second: +0.8%, rss_bytes: +0.1% |
| health_live | stable | completed: +0.3%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +0.5%, p95_ms: -6.1%, p99_ms: +8.9%, requests_per_second: +0.2%, rss_bytes: +0.1% |
| health_live | stable | completed: -0.8%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +0.1%, p95_ms: +5.2%, p99_ms: -3.6%, requests_per_second: -0.7%, rss_bytes: +0.0% |
| health_live | stable | completed: +0.2%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: -6.8%, p99_ms: +0.8%, requests_per_second: +0.1%, rss_bytes: +0.0% |
| home | stable | completed: +1.3%, cpu_percent: +0.6%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: -0.6%, p99_ms: +4.8%, requests_per_second: +1.4%, rss_bytes: -0.0% |
| home | improvement | completed: +1.6%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +0.7%, p95_ms: -3.9%, p99_ms: -13.5%, requests_per_second: +1.5%, rss_bytes: +0.0% |
| home | stable | completed: -1.2%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +1.1%, p95_ms: -5.0%, p99_ms: -5.3%, requests_per_second: -1.2%, rss_bytes: +0.1% |
| categories | stable | completed: -2.6%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +3.7%, p95_ms: +0.8%, p99_ms: +0.2%, requests_per_second: -2.5%, rss_bytes: +0.1% |
| categories | improvement | completed: -2.2%, cpu_percent: +0.0%, duration_seconds: -4.6%, p50_ms: -17.8%, p95_ms: +14.7%, p99_ms: -0.1%, requests_per_second: +2.2%, rss_bytes: +0.1% |
| categories | stable | completed: +0.8%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -0.3%, p95_ms: -4.9%, p99_ms: -7.1%, requests_per_second: +0.8%, rss_bytes: +0.1% |
| category | possible-regression | completed: +0.4%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +0.3%, p95_ms: +0.7%, p99_ms: +26.2%, requests_per_second: +0.4%, rss_bytes: +0.0% |
| category | improvement | completed: +1.4%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -0.2%, p95_ms: -2.0%, p99_ms: -15.8%, requests_per_second: +1.5%, rss_bytes: +0.0% |
| category | improvement | completed: +1.7%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -7.1%, p95_ms: -10.6%, p99_ms: -13.1%, requests_per_second: +1.7%, rss_bytes: -0.0% |
| thread | stable | completed: -0.5%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +0.6%, p95_ms: +2.1%, p99_ms: +9.5%, requests_per_second: +0.1%, rss_bytes: +0.0% |
| thread | stable | completed: +1.7%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -2.1%, p95_ms: -1.7%, p99_ms: -1.2%, requests_per_second: +1.7%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: -1.9%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +1.4%, p95_ms: +5.2%, p99_ms: +16.2%, requests_per_second: -2.0%, rss_bytes: +0.0% |
| thread | possible-regression | completed: -0.5%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -2.2%, p95_ms: +12.4%, p99_ms: +3.9%, requests_per_second: -0.6%, rss_bytes: +0.0% |
| search | stable | completed: -1.3%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: +1.6%, p95_ms: +3.5%, p99_ms: +8.5%, requests_per_second: -1.2%, rss_bytes: +0.0% |
| search | stable | completed: -2.5%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: +0.8%, p95_ms: +7.0%, p99_ms: +1.9%, requests_per_second: +1.9%, rss_bytes: +0.0% |
| search | stable | completed: +0.0%, cpu_percent: -2.1%, duration_seconds: +0.0%, p50_ms: -3.3%, p95_ms: -6.8%, p99_ms: -4.3%, requests_per_second: +2.0%, rss_bytes: +0.0% |
| search | stable | completed: +0.0%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +0.2%, p95_ms: +0.6%, p99_ms: +0.3%, requests_per_second: -0.0%, rss_bytes: +0.0% |
| cache_hit | stable | completed: +3.8%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -1.8%, p95_ms: -2.4%, p99_ms: -13.8%, requests_per_second: +2.0%, rss_bytes: +0.0% |
| cache_hit | stable | completed: -0.2%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: +1.5%, p99_ms: +0.6%, requests_per_second: -0.2%, rss_bytes: +0.0% |
| cache_hit | stable | completed: +0.7%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -0.7%, p95_ms: +3.3%, p99_ms: -1.3%, requests_per_second: +0.7%, rss_bytes: +0.0% |
| cache_hit | possible-regression | completed: -0.1%, cpu_percent: -0.8%, duration_seconds: +0.1%, p50_ms: +1.1%, p95_ms: +14.3%, p99_ms: -3.7%, requests_per_second: -0.1%, rss_bytes: +0.0% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +10.0%, duration_seconds: -1.4%, p50_ms: -3.8%, p95_ms: -4.5%, p99_ms: -11.1%, requests_per_second: +1.1%, rss_bytes: +0.0% |
| thread | possible-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -4.5%, duration_seconds: +0.0%, p50_ms: +1.9%, p95_ms: +7.1%, p99_ms: +26.1%, requests_per_second: +0.7%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: +1.5%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +29.5%, p95_ms: -2.6%, p99_ms: +13.7%, requests_per_second: +2.4%, rss_bytes: -0.0% |
| thread | improvement | completed: +3.2%, cpu_percent: +1.4%, duration_seconds: +0.0%, p50_ms: -19.7%, p95_ms: -23.6%, p99_ms: -32.2%, requests_per_second: +3.1%, rss_bytes: -0.1% |
| search | possible-regression | completed: -11.8%, cpu_percent: -20.0%, duration_seconds: -0.1%, p50_ms: +50.7%, p95_ms: +3.9%, p99_ms: +2.5%, requests_per_second: -11.6%, rss_bytes: -0.1% |
| search | stable | completed: +8.4%, cpu_percent: -2.0%, duration_seconds: +0.2%, p50_ms: +12.9%, p95_ms: -16.5%, p99_ms: -23.8%, requests_per_second: +8.2%, rss_bytes: -0.2% |
| cache_hit | stable | completed: -7.9%, cpu_percent: -22.9%, duration_seconds: -0.0%, p50_ms: -3.5%, p95_ms: -3.5%, p99_ms: +3.6%, requests_per_second: -12.0%, rss_bytes: -0.2% |
| cache_hit | confirmed-regression | completed: +3.2%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: -11.9%, p95_ms: +22.7%, p99_ms: +6.9%, requests_per_second: +3.1%, rss_bytes: -0.2% |
| cache_miss | stable | completed: -1.4%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: -0.5%, p99_ms: +0.2%, requests_per_second: +0.5%, rss_bytes: -0.1% |
| cache_miss | improvement | completed: -3.6%, cpu_percent: +0.3%, duration_seconds: -4.7%, p50_ms: -1.0%, p95_ms: -1.1%, p99_ms: -13.2%, requests_per_second: +1.2%, rss_bytes: -0.1% |
| cache_miss | stable | completed: +1.8%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -1.1%, p95_ms: -2.7%, p99_ms: -3.8%, requests_per_second: +1.7%, rss_bytes: -0.1% |
| health_live | stable | completed: -1.8%, cpu_percent: -0.5%, duration_seconds: -4.7%, p50_ms: -1.1%, p95_ms: -1.0%, p99_ms: -3.5%, requests_per_second: +2.0%, rss_bytes: -0.1% |
| health_live | stable | completed: +3.7%, cpu_percent: +0.2%, duration_seconds: +4.8%, p50_ms: +0.5%, p95_ms: +0.4%, p99_ms: -5.6%, requests_per_second: -0.1%, rss_bytes: -0.1% |
| health_live | stable | completed: -0.7%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: +4.8%, p99_ms: -4.9%, requests_per_second: -0.7%, rss_bytes: -0.1% |
| health_live | stable | completed: -1.1%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +0.4%, p95_ms: +10.8%, p99_ms: +1.5%, requests_per_second: -1.0%, rss_bytes: -0.1% |
| home | improvement | completed: +2.1%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: -1.7%, p95_ms: -6.2%, p99_ms: -15.0%, requests_per_second: +2.7%, rss_bytes: -0.0% |
| home | stable | completed: -1.3%, cpu_percent: -0.1%, duration_seconds: -4.5%, p50_ms: -1.7%, p95_ms: +9.0%, p99_ms: -0.3%, requests_per_second: +2.2%, rss_bytes: -0.0% |
| home | stable | completed: -0.2%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: -2.7%, p95_ms: -0.6%, p99_ms: -2.3%, requests_per_second: -0.3%, rss_bytes: -0.0% |
| categories | stable | completed: +0.8%, cpu_percent: -0.6%, duration_seconds: -0.1%, p50_ms: -0.9%, p95_ms: +0.1%, p99_ms: -2.5%, requests_per_second: +0.8%, rss_bytes: -0.0% |
| categories | stable | completed: -1.6%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -1.1%, p95_ms: +5.4%, p99_ms: +21.0%, requests_per_second: +0.5%, rss_bytes: -0.0% |
| categories | stable | completed: -0.9%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +0.9%, p95_ms: +3.4%, p99_ms: -1.7%, requests_per_second: -0.8%, rss_bytes: -0.0% |
| category | stable | completed: +1.3%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: -1.4%, p95_ms: -1.2%, p99_ms: -2.0%, requests_per_second: +1.4%, rss_bytes: -0.0% |
| category | stable | completed: -0.7%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: +0.7%, p95_ms: +17.2%, p99_ms: +3.4%, requests_per_second: -0.5%, rss_bytes: -0.0% |
| category | stable | completed: -1.4%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +1.1%, p95_ms: +4.4%, p99_ms: +3.1%, requests_per_second: -1.5%, rss_bytes: -0.0% |
| thread | stable | completed: +0.9%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -1.3%, p95_ms: -1.0%, p99_ms: -11.1%, requests_per_second: +0.9%, rss_bytes: -0.0% |
| thread | possible-regression | completed: -2.1%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +1.8%, p95_ms: +6.2%, p99_ms: +11.5%, requests_per_second: -1.5%, rss_bytes: -0.0% |
| thread | stable | completed: +0.1%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +0.5%, p95_ms: -1.0%, p99_ms: +1.2%, requests_per_second: +0.1%, rss_bytes: -0.0% |
| thread | improvement | completed: +4.2%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -2.5%, p95_ms: -17.7%, p99_ms: -11.7%, requests_per_second: +4.3%, rss_bytes: -0.0% |
| search | stable | completed: +2.0%, cpu_percent: -1.5%, duration_seconds: -0.1%, p50_ms: -2.1%, p95_ms: -0.9%, p99_ms: +11.1%, requests_per_second: +2.0%, rss_bytes: -0.1% |
| search | stable | completed: +2.6%, cpu_percent: -1.9%, duration_seconds: +0.1%, p50_ms: -5.1%, p95_ms: -2.4%, p99_ms: -5.5%, requests_per_second: +2.6%, rss_bytes: -0.0% |
| search | stable | completed: +0.0%, cpu_percent: -1.8%, duration_seconds: +0.1%, p50_ms: -5.2%, p95_ms: -7.4%, p99_ms: -6.1%, requests_per_second: -0.1%, rss_bytes: -0.0% |
| search | stable | completed: -0.5%, cpu_percent: -1.9%, duration_seconds: +0.1%, p50_ms: -0.9%, p95_ms: -2.1%, p99_ms: -1.8%, requests_per_second: -0.6%, rss_bytes: -0.0% |
| cache_hit | stable | completed: +3.1%, cpu_percent: -0.0%, duration_seconds: +0.2%, p50_ms: +4.5%, p95_ms: -0.3%, p99_ms: -12.1%, requests_per_second: -1.7%, rss_bytes: -0.0% |
| cache_hit | stable | completed: +0.2%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +1.0%, p95_ms: -8.2%, p99_ms: -2.5%, requests_per_second: +0.1%, rss_bytes: -0.0% |
| cache_hit | stable | completed: -0.9%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +0.3%, p95_ms: +7.7%, p99_ms: -8.0%, requests_per_second: -1.1%, rss_bytes: -0.0% |
| cache_hit | stable | completed: +0.4%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: +0.9%, p95_ms: +1.1%, p99_ms: -0.2%, requests_per_second: +0.4%, rss_bytes: -0.0% |
| thread | stable | completed: +0.8%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +7.3%, p95_ms: -2.7%, p99_ms: +5.2%, requests_per_second: +0.9%, rss_bytes: +0.0% |
| thread | possible-regression | completed: +2.6%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -6.8%, p95_ms: +29.2%, p99_ms: +23.4%, requests_per_second: +2.7%, rss_bytes: -0.0% |
| search | stable | completed: +0.3%, cpu_percent: +1.1%, duration_seconds: +0.1%, p50_ms: -24.4%, p95_ms: +7.0%, p99_ms: -4.5%, requests_per_second: +0.3%, rss_bytes: +0.0% |
| search | improvement | completed: +15.2%, cpu_percent: +4.4%, duration_seconds: +0.1%, p50_ms: -9.9%, p95_ms: -16.6%, p99_ms: -14.8%, requests_per_second: +15.5%, rss_bytes: +0.1% |
| cache_hit | stable | completed: -7.2%, cpu_percent: -3.9%, duration_seconds: -0.1%, p50_ms: +28.3%, p95_ms: +7.7%, p99_ms: -0.3%, requests_per_second: -7.3%, rss_bytes: +0.2% |
| cache_hit | stable | completed: +1.4%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: +11.9%, p99_ms: +15.5%, requests_per_second: +1.4%, rss_bytes: +0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.4% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -17.9% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -18.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.1% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +12.1% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +16.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.3% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +11.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.7% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -34.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.8% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.8% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -19.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.6% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +45.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.0% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +2.6%, messages_per_second: -2.6%, p50_ms: +3.2%, p95_ms: +2.3%, p99_ms: +1.4% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +3.9%, messages_per_second: -3.8%, p50_ms: +3.3%, p95_ms: +8.5%, p99_ms: +8.4% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.7%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +0.6%, p95_ms: +0.5%, p99_ms: -2.0%, requests_per_second: -0.7%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.8%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +0.1%, p95_ms: -2.0%, p99_ms: -0.2%, requests_per_second: +0.9%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.5%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: +0.8%, p95_ms: +0.3%, p99_ms: -0.3%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.5%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: -3.8%, p95_ms: -3.2%, p99_ms: -3.3%, requests_per_second: +4.0%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +9.0%, cpu_percent: +0.0%, duration_seconds: +4.9%, p50_ms: -3.3%, p95_ms: -10.4%, p99_ms: -15.0%, requests_per_second: +4.4%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.1%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.7%, p95_ms: -1.0%, p99_ms: +1.4%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.1%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -1.1%, p95_ms: +3.2%, p99_ms: -0.4%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +1.7%, cpu_percent: -1.2%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: -4.1%, p99_ms: -14.0%, requests_per_second: +1.5%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +1.1%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: -3.3%, p95_ms: +9.4%, p99_ms: +24.2%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +5.7%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -3.5%, p95_ms: -3.5%, p99_ms: -3.6%, requests_per_second: +5.7%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +5.4%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -6.5%, p95_ms: -3.8%, p99_ms: -4.6%, requests_per_second: +5.4%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -0.4%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +18.4%, p95_ms: -9.3%, p99_ms: +19.8%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.6%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +0.2%, p95_ms: +4.8%, p99_ms: +5.9%, requests_per_second: -1.6%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +1.8%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -1.5%, p95_ms: -3.6%, p99_ms: -25.6%, requests_per_second: +1.8%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.0%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -0.9%, p95_ms: +16.0%, p99_ms: +5.7%, requests_per_second: +1.0%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.1%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: -3.5%, p99_ms: +7.0%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +2.9%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -3.9%, p95_ms: -4.4%, p99_ms: -12.9%, requests_per_second: +2.9%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -0.7%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +0.2%, p95_ms: +5.3%, p99_ms: +48.2%, requests_per_second: -0.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.5%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -2.0%, p95_ms: -5.0%, p99_ms: -3.1%, requests_per_second: +2.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +2.9%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -1.3%, p95_ms: -14.7%, p99_ms: -0.1%, requests_per_second: +2.9%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.4%, cpu_percent: -1.5%, duration_seconds: -0.2%, p50_ms: -2.9%, p95_ms: -5.2%, p99_ms: -1.0%, requests_per_second: +3.3%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.2%, cpu_percent: -1.5%, duration_seconds: +0.2%, p50_ms: -5.4%, p95_ms: -10.6%, p99_ms: -3.3%, requests_per_second: +2.1%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +1.8%, p95_ms: +0.1%, p99_ms: +1.5%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: -1.9%, duration_seconds: +0.1%, p50_ms: -1.7%, p95_ms: -2.0%, p99_ms: -1.7%, requests_per_second: -0.6%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.3%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +1.7%, p95_ms: -0.2%, p99_ms: -1.3%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.5%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: -1.8%, p99_ms: +4.2%, requests_per_second: +2.5%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -0.2%, p95_ms: +4.3%, p99_ms: -0.4%, requests_per_second: -0.5%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +1.9%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -1.8%, p95_ms: -15.2%, p99_ms: -0.2%, requests_per_second: +1.9%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.5%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -11.3%, p95_ms: -0.3%, p99_ms: +7.9%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.2%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +6.4%, p95_ms: -2.3%, p99_ms: -1.8%, requests_per_second: +1.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +18.1%, cpu_percent: +26.0%, duration_seconds: +0.2%, p50_ms: -39.6%, p95_ms: +3.7%, p99_ms: -10.7%, requests_per_second: +17.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +8.1%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -1.5%, p95_ms: +3.8%, p99_ms: +17.4%, requests_per_second: +8.1%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -29.3%, cpu_percent: -27.2%, duration_seconds: +0.0%, p50_ms: +97.8%, p95_ms: +29.5%, p99_ms: +30.6%, requests_per_second: -25.9%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.4%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +12.1%, p95_ms: -5.7%, p99_ms: +0.4%, requests_per_second: -0.1%, rss_bytes: +0.5% |
| thread | workers=4 | 2 | 50 | improvement | completed: +50.9%, cpu_percent: +92.9%, duration_seconds: +0.3%, p50_ms: -17.8%, p95_ms: +6.7%, p99_ms: +0.9%, requests_per_second: +50.9%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +51.6%, cpu_percent: +91.6%, duration_seconds: +0.2%, p50_ms: -43.3%, p95_ms: +0.6%, p99_ms: -15.4%, requests_per_second: +51.1%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +10.4%, cpu_percent: +43.5%, duration_seconds: +0.1%, p50_ms: -11.6%, p95_ms: +20.2%, p99_ms: +38.8%, requests_per_second: +10.3%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +54.5%, cpu_percent: +78.4%, duration_seconds: +0.4%, p50_ms: -31.1%, p95_ms: -19.3%, p99_ms: -22.2%, requests_per_second: +54.0%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +30.8%, cpu_percent: +49.3%, duration_seconds: +0.0%, p50_ms: -36.6%, p95_ms: +2.2%, p99_ms: +5.3%, requests_per_second: +24.9%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.7%, cpu_percent: +94.6%, duration_seconds: +0.1%, p50_ms: -42.4%, p95_ms: -7.4%, p99_ms: -16.0%, requests_per_second: +49.4%, rss_bytes: +64.3% |
| thread | workers=4 | 2 | 50 | improvement | completed: +46.5%, cpu_percent: +93.3%, duration_seconds: +0.2%, p50_ms: -25.6%, p95_ms: +11.9%, p99_ms: +12.3%, requests_per_second: +46.3%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +49.0%, cpu_percent: +92.8%, duration_seconds: +0.1%, p50_ms: -38.9%, p95_ms: +15.2%, p99_ms: -16.8%, requests_per_second: +48.8%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | possible-regression | completed: +30.9%, cpu_percent: +80.1%, duration_seconds: +0.3%, p50_ms: -47.6%, p95_ms: +24.6%, p99_ms: +22.0%, requests_per_second: +30.5%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +67.8%, cpu_percent: +82.4%, duration_seconds: +0.3%, p50_ms: -31.0%, p95_ms: -14.6%, p99_ms: -7.1%, requests_per_second: +67.4%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: -7.1%, cpu_percent: +9.1%, duration_seconds: +0.0%, p50_ms: +25.6%, p95_ms: +26.9%, p99_ms: +38.0%, requests_per_second: -7.0%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +46.4%, cpu_percent: +94.4%, duration_seconds: +0.0%, p50_ms: -34.3%, p95_ms: +2.9%, p99_ms: -15.6%, requests_per_second: +46.4%, rss_bytes: +64.5% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38637824251)
