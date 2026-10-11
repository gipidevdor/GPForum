# GPForum continuous performance evidence

Commit: `fbf393a6e93a5ca081627adaae148cace6d336ea` · mode: **main** · status: **ok**
Run: 38151370355 / attempt 1 · 2026-10-11T15:28:19.907515+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, INTEL(R) XEON(R) PLATINUM 8573C.

Versions: {"ev": "4.37", "mojolicious": "9.49", "perl": "v5.40.1", "postgres": "16.15 (Debian 16.15-1.pgdg13+2)", "wrk": "wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts": {"bookmarks": 25, "categories": 8, "feed_items": 240, "moderation_actions": 25, "notifications": 75, "permissions": 6, "posts": 4800, "posts_per_thread": 20, "read_states": 75, "reports": 50, "role_bindings": 25, "roles": 3, "sessions": 25, "subscriptions": 25, "threads": 240, "users": 25}, "implementation_sha256": {"lib/GPForum/Benchmark/SeedDataset.pm": "8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb", "lib/GPForum/Command/PerformanceSeed.pm": "ee7d3093ffc5cd7d0cc2

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 320.963 | 3.073 | 3.364 | 3.670 | 100.357 / 368.039 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 624.103 | 15.881 | 16.942 | 22.402 | 200.412 / 368.070 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 623.315 | 78.530 | 91.826 | 129.626 | 200.491 / 369.719 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1344.411 | 0.732 | 0.839 | 0.945 | 100.366 / 367.793 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2597.709 | 3.754 | 4.248 | 6.215 | 199.860 / 367.793 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2706.469 | 18.210 | 19.721 | 22.745 | 199.972 / 368.453 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2740.943 | 35.976 | 40.876 | 53.066 | 200.660 / 369.734 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 153.895 | 6.414 | 7.005 | 7.265 | 84.753 / 370.180 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 295.726 | 32.138 | 43.659 | 50.747 | 169.422 / 370.574 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 280.413 | 174.663 | 238.253 | 325.591 | 170.092 / 372.320 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 923.526 | 1.052 | 1.212 | 1.264 | 99.843 / 372.320 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1817.766 | 5.355 | 6.741 | 8.463 | 199.844 / 372.320 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1886.264 | 25.985 | 28.329 | 36.022 | 200.508 / 372.320 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 903.471 | 1.085 | 1.221 | 1.538 | 99.793 / 372.410 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1753.078 | 6.085 | 7.163 | 7.540 | 199.961 / 372.410 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1835.108 | 26.943 | 29.147 | 36.952 | 200.356 / 372.410 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 876.507 | 1.147 | 1.252 | 1.318 | 100.310 / 372.535 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1744.273 | 6.324 | 7.178 | 7.949 | 199.717 / 372.535 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1821.513 | 27.174 | 29.098 | 33.407 | 200.779 / 373.129 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1771.463 | 55.037 | 58.330 | 87.341 | 200.711 / 376.336 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 96.672 | 10.235 | 11.214 | 11.646 | 65.163 / 376.750 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 175.340 | 56.164 | 76.859 | 105.842 | 129.636 / 376.867 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 173.874 | 280.040 | 451.556 | 529.101 | 129.950 / 376.867 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 149.681 | 553.283 | 1005.101 | 1077.627 | 128.436 / 377.219 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 923.634 | 1.073 | 1.190 | 1.271 | 100.325 / 377.219 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1767.597 | 6.106 | 7.191 | 9.105 | 199.881 / 377.219 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1867.911 | 26.342 | 28.155 | 32.602 | 200.612 / 377.219 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1869.301 | 52.752 | 56.255 | 83.105 | 200.466 / 377.219 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1528.470 | 5.916 | 9.103 | 10.331 | 31.796 / 377.219 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 981.808 | 8.839 | 14.722 | 15.978 | 44.824 / 377.523 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2583.657 | 14.782 | 39.372 | 42.994 | 390.414 / 612.375 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2596.004 | 27.128 | 76.004 | 105.062 | 391.410 / 616.891 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 205.315 | 206.943 | 504.465 | 647.644 | 189.098 / 618.219 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 209.752 | 328.471 | 1268.273 | 1570.483 | 225.164 / 619.035 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 974.221 | 50.574 | 55.667 | 88.866 | 112.136 / 619.645 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2635.832 | 36.749 | 58.874 | 90.657 | 391.273 / 619.906 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 326.331 | 3.014 | 3.331 | 3.459 | 100.269 / 368.988 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 633.555 | 15.383 | 17.483 | 25.013 | 200.036 / 368.988 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 630.438 | 75.488 | 84.504 | 143.601 | 200.216 / 370.781 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1366.508 | 0.714 | 0.834 | 1.079 | 99.857 / 368.840 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2641.095 | 3.725 | 4.138 | 6.211 | 200.229 / 368.840 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2728.037 | 17.848 | 19.678 | 28.598 | 200.422 / 369.617 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2740.573 | 35.713 | 38.180 | 57.502 | 200.847 / 370.965 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 156.802 | 6.257 | 7.078 | 7.250 | 84.849 / 371.371 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 297.773 | 33.785 | 44.485 | 64.881 | 169.091 / 371.750 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 295.585 | 165.531 | 241.472 | 317.443 | 169.117 / 373.422 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 928.555 | 1.065 | 1.191 | 1.461 | 99.841 / 373.422 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1841.835 | 5.372 | 7.019 | 7.710 | 199.519 / 373.422 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1885.754 | 25.828 | 28.627 | 44.206 | 200.410 / 373.422 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 906.875 | 1.091 | 1.203 | 1.324 | 99.841 / 373.578 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1807.078 | 5.462 | 6.101 | 9.783 | 199.827 / 373.578 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1848.585 | 26.672 | 29.796 | 45.979 | 200.361 / 373.609 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 909.562 | 1.092 | 1.190 | 1.256 | 100.158 / 373.766 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1763.984 | 5.474 | 7.437 | 11.240 | 199.596 / 373.766 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1813.347 | 26.617 | 33.046 | 49.619 | 200.390 / 374.383 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1791.734 | 53.836 | 59.208 | 95.563 | 200.029 / 377.539 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 95.461 | 10.127 | 11.215 | 12.551 | 64.878 / 378.367 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 175.312 | 54.869 | 76.533 | 119.107 | 128.658 / 378.367 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 173.205 | 277.933 | 455.647 | 532.078 | 129.715 / 378.367 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 149.225 | 584.044 | 1060.679 | 1139.666 | 128.891 / 378.367 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 948.336 | 1.040 | 1.136 | 1.361 | 101.828 / 378.367 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1862.619 | 5.431 | 6.879 | 9.049 | 199.870 / 378.367 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1879.875 | 26.280 | 29.184 | 43.912 | 200.320 / 378.367 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1813.770 | 53.130 | 63.416 | 93.418 | 200.506 / 378.367 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2562.430 | 19.501 | 33.474 | 44.527 | 387.369 / 614.277 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2566.595 | 41.615 | 61.882 | 78.673 | 393.527 / 619.297 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 215.495 | 156.953 | 461.673 | 624.735 | 227.999 / 620.691 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 211.020 | 276.997 | 1044.087 | 1199.633 | 230.945 / 621.383 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1686.358 | 33.866 | 56.689 | 88.381 | 210.253 / 621.414 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2647.888 | 38.745 | 57.371 | 79.626 | 395.108 / 621.426 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.367 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.348 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.443 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.082 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.520 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.388 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.078 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.025 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.333 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.441 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.199 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.247 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.060 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.040 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.043 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.019 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.341 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.353 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.473 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.334 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.393 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.239 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.256 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.383 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.961 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.178 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.152 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.166 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.077 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.086 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.054 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.070 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 684.449 | 145.589 | 168.411 | 219.342 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1058.253 | 188.109 | 199.680 | 202.062 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -3.1%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: -1.9%, p95_ms: -1.0%, p99_ms: -5.7%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.6%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -3.1%, p95_ms: +3.2%, p99_ms: +11.7%, requests_per_second: +1.5%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +1.3%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -3.9%, p95_ms: -8.0%, p99_ms: +10.8%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.0%, cpu_percent: -0.5%, duration_seconds: +5.0%, p50_ms: -2.5%, p95_ms: -0.6%, p99_ms: +14.2%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +3.1%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -0.8%, p95_ms: -2.6%, p99_ms: -0.1%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.8%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -2.0%, p95_ms: -0.2%, p99_ms: +25.7%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.1%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -0.7%, p95_ms: -6.6%, p99_ms: +8.4%, requests_per_second: -0.0%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.9%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -2.4%, p95_ms: +1.0%, p99_ms: -0.2%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.0%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +5.1%, p95_ms: +1.9%, p99_ms: +27.9%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +5.3%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: -5.2%, p95_ms: +1.4%, p99_ms: -2.5%, requests_per_second: +5.4%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: +2.1%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +1.2%, p95_ms: -1.7%, p99_ms: +15.6%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.8%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: +0.3%, p95_ms: +4.1%, p99_ms: -8.9%, requests_per_second: +1.3%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.1%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -0.6%, p95_ms: +1.1%, p99_ms: +22.7%, requests_per_second: -0.0%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +0.6%, p95_ms: -1.5%, p99_ms: -13.9%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +3.3%, cpu_percent: -0.1%, duration_seconds: +0.2%, p50_ms: -10.2%, p95_ms: -14.8%, p99_ms: +29.7%, requests_per_second: +3.1%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.9%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -1.0%, p95_ms: +2.2%, p99_ms: +24.4%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.8%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -4.8%, p95_ms: -5.0%, p99_ms: -4.7%, requests_per_second: +3.8%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +4.4%, cpu_percent: -0.1%, duration_seconds: +4.8%, p50_ms: -13.4%, p95_ms: +3.6%, p99_ms: +41.4%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -0.3%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -2.0%, p95_ms: +13.6%, p99_ms: +48.5%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.1%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -2.2%, p95_ms: +1.5%, p99_ms: +9.4%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.1%, cpu_percent: -0.4%, duration_seconds: -0.2%, p50_ms: -1.1%, p95_ms: +0.0%, p99_ms: +7.8%, requests_per_second: -1.3%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.0%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: -2.3%, p95_ms: -0.4%, p99_ms: +12.5%, requests_per_second: -0.0%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.3%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -0.8%, p95_ms: +0.9%, p99_ms: +0.6%, requests_per_second: -0.4%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.3%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +5.6%, p95_ms: +5.5%, p99_ms: +5.8%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +6.8%, cpu_percent: +1.5%, duration_seconds: +5.0%, p50_ms: -3.1%, p95_ms: -4.5%, p99_ms: +7.1%, requests_per_second: +2.7%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +5.3%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: -11.1%, p95_ms: -4.3%, p99_ms: -0.6%, requests_per_second: +5.4%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -1.8%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -0.2%, p95_ms: +3.7%, p99_ms: +34.7%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -3.0%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +0.7%, p95_ms: +12.7%, p99_ms: +12.4%, requests_per_second: -3.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -5.4%, cpu_percent: -0.8%, duration_seconds: -4.6%, p50_ms: +31.9%, p95_ms: -15.0%, p99_ms: +3.6%, requests_per_second: -0.8%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -1.2%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +53.4%, p95_ms: -18.6%, p99_ms: -25.1%, requests_per_second: -1.1%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +5.3%, cpu_percent: +20.6%, duration_seconds: +0.2%, p50_ms: -24.2%, p95_ms: -8.5%, p99_ms: -3.5%, requests_per_second: +5.0%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +0.7%, cpu_percent: +2.6%, duration_seconds: +0.2%, p50_ms: -15.7%, p95_ms: -17.7%, p99_ms: -23.6%, requests_per_second: +0.6%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +73.4%, cpu_percent: +87.5%, duration_seconds: +0.1%, p50_ms: -33.0%, p95_ms: +1.8%, p99_ms: -0.5%, requests_per_second: +73.1%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.2%, cpu_percent: +1.0%, duration_seconds: -0.1%, p50_ms: +5.4%, p95_ms: -2.6%, p99_ms: -12.2%, requests_per_second: +0.5%, rss_bytes: +0.2% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +48.7%, cpu_percent: +94.5%, duration_seconds: +4.8%, p50_ms: -45.6%, p95_ms: +35.3%, p99_ms: +28.7%, requests_per_second: +41.8%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +46.6%, cpu_percent: +95.0%, duration_seconds: +0.1%, p50_ms: -50.7%, p95_ms: +30.3%, p99_ms: +20.3%, requests_per_second: +46.5%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +18.4%, cpu_percent: +45.5%, duration_seconds: +0.2%, p50_ms: -26.1%, p95_ms: +11.7%, p99_ms: +22.4%, requests_per_second: +18.1%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | confirmed-regression | completed: +40.3%, cpu_percent: +75.3%, duration_seconds: +0.2%, p50_ms: -40.6%, p95_ms: +26.2%, p99_ms: +45.7%, requests_per_second: +40.1%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -49.2%, cpu_percent: -44.1%, duration_seconds: -0.1%, p50_ms: +92.0%, p95_ms: +97.7%, p99_ms: +172.6%, requests_per_second: -47.8%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +40.9%, cpu_percent: +95.2%, duration_seconds: +0.0%, p50_ms: -30.3%, p95_ms: +4.7%, p99_ms: +9.1%, requests_per_second: +41.0%, rss_bytes: +64.3% |
| thread | workers=4 | 2 | 50 | improvement | completed: +41.2%, cpu_percent: +93.3%, duration_seconds: -0.1%, p50_ms: -26.7%, p95_ms: +1.3%, p99_ms: -10.3%, requests_per_second: +41.3%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +43.3%, cpu_percent: +96.7%, duration_seconds: -0.1%, p50_ms: -22.7%, p95_ms: +4.5%, p99_ms: -17.7%, requests_per_second: +43.2%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | improvement | completed: +25.1%, cpu_percent: +75.8%, duration_seconds: +0.4%, p50_ms: -43.5%, p95_ms: +1.3%, p99_ms: +17.4%, requests_per_second: +24.4%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +41.8%, cpu_percent: +79.2%, duration_seconds: +0.4%, p50_ms: -52.6%, p95_ms: -1.6%, p99_ms: +5.3%, requests_per_second: +41.4%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -10.3%, cpu_percent: +5.0%, duration_seconds: +0.1%, p50_ms: +28.9%, p95_ms: +94.2%, p99_ms: +101.3%, requests_per_second: -10.3%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +46.9%, cpu_percent: +97.1%, duration_seconds: -0.1%, p50_ms: -27.1%, p95_ms: -9.5%, p99_ms: -14.8%, requests_per_second: +46.0%, rss_bytes: +64.2% |

## Suite status and skipped tests

- contracts: **ok** — GitHub Actions step outcome: success
- database: **ok** — See individual gates and diagnostic artifacts; skipped suites never imply execution
- database-plans-functions: **ok** — Nested stored-function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- database-plans-readers: **ok** — Nested stored-function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- databases: **ok** — GitHub Actions step outcome: success
- hotpaths_workflow: **ok** — GitHub Actions step outcome: success
- http: **ok** — completed planned HTTP measurements
  - {"reason": "read-only anonymous suite; safe durable auth fixture unavailable", "scenario": "authenticated"}
  - {"reason": "bounded targeted plan: every endpoint at low load; high concurrency on health/thread/search/cache_hit; extra workers only thread/search/cache_hit", "scenario": "full_cartesian_matrix"}
  - {"reason": "bounded PR/main modes; use deep sweep", "scenario": "concurrency_250_500"}
  - {"reason": "eight-worker sweep reserved for capable deep runners", "scenario": "workers_8"}
  - {"reason": "requires explicit --allow-1000 and capable runner", "scenario": "concurrency_1000"}
  - {"reason": "wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)", "scenario": "wrk_upstream_version"}
- http_workflow: **ok** — GitHub Actions step outcome: success
- migrations: **ok** — GitHub Actions step outcome: success
- outbox: **ok** — See individual gates and diagnostic artifacts; skipped suites never imply execution
- outbox-postgres: **ok** — Fresh owned database is dropped on completion or caught signals; synthetic delivery IDs verify losses and duplicates
- pr_comment: **skipped** — Job Summary and artifacts provide PR results with a read-only token; no privileged fork artifact/comment workflow is enabled.
- profiling: **skipped** — Reserved for bounded weekly/manual deep mode
- query-budget: **ok** — Catalog drift is deterministic; N+1 request counts remain blocking in ci.yml integration tier
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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38151370355)
