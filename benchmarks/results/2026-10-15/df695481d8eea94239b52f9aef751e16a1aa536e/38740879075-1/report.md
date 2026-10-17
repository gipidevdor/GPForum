# GPForum continuous performance evidence

Commit: `df695481d8eea94239b52f9aef751e16a1aa536e` · mode: **main** · status: **ok**
Run: 38740879075 / attempt 1 · 2026-10-15T13:13:57.015489+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. e002385cbaa46b05bb75897c7c3678bd9307f8ab

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 179.706 | 5.478 | 5.922 | 6.833 | 94.964 / 371.945 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 335.895 | 29.022 | 35.568 | 42.380 | 189.708 / 372.043 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 324.518 | 150.628 | 191.382 | 271.891 | 190.798 / 373.898 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1145.765 | 0.860 | 0.924 | 0.964 | 99.930 / 372.016 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2246.163 | 4.411 | 4.594 | 5.283 | 198.944 / 372.016 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2271.621 | 21.636 | 22.577 | 26.261 | 200.219 / 372.586 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2207.554 | 43.166 | 47.705 | 65.855 | 200.834 / 373.879 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 89.938 | 10.919 | 12.264 | 14.062 | 87.057 / 374.230 | possible-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 169.150 | 50.901 | 72.873 | 98.668 | 175.008 / 374.926 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 149.685 | 280.133 | 497.727 | 569.462 | 174.260 / 377.180 | possible-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 859.131 | 1.146 | 1.223 | 1.290 | 99.377 / 377.180 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1716.959 | 5.778 | 6.015 | 6.702 | 199.302 / 377.180 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1721.718 | 28.485 | 29.983 | 39.453 | 200.238 / 377.180 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 857.420 | 1.151 | 1.227 | 1.312 | 99.996 / 377.211 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1673.568 | 6.084 | 6.668 | 7.588 | 199.347 / 377.211 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1698.609 | 29.005 | 30.306 | 37.584 | 200.834 / 377.211 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 822.984 | 1.218 | 1.270 | 1.558 | 99.488 / 377.355 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1655.944 | 5.949 | 7.376 | 7.774 | 199.174 / 377.355 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1650.031 | 29.797 | 31.170 | 44.429 | 200.294 / 377.387 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1595.740 | 60.579 | 63.828 | 97.954 | 200.256 / 380.305 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 63.955 | 15.538 | 17.238 | 18.497 | 67.129 / 380.754 | possible-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 109.859 | 86.412 | 104.160 | 142.978 | 134.657 / 381.141 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 99.842 | 447.502 | 791.893 | 864.483 | 135.298 / 381.141 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.749 | 890.851 | 1689.233 | 1774.410 | 133.730 / 381.141 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 848.271 | 1.165 | 1.237 | 1.457 | 99.416 / 381.141 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1672.692 | 5.907 | 6.355 | 8.625 | 198.784 / 381.141 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1689.300 | 29.081 | 30.379 | 39.529 | 200.214 / 381.141 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1645.453 | 59.116 | 63.454 | 95.335 | 200.712 / 381.141 | stable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1343.510 | 6.381 | 10.568 | 14.554 | 25.957 / 381.141 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 988.453 | 9.275 | 13.481 | 17.024 | 38.291 / 381.422 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2356.704 | 23.552 | 35.476 | 50.606 | 367.612 / 619.230 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2347.281 | 40.011 | 71.649 | 92.264 | 383.018 / 623.266 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 138.760 | 287.010 | 683.963 | 805.656 | 234.553 / 625.062 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 130.547 | 606.472 | 1353.381 | 1484.346 | 239.011 / 626.012 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1642.590 | 29.516 | 35.921 | 53.279 | 208.948 / 626.027 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2460.053 | 39.650 | 64.923 | 79.896 | 386.961 / 626.094 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 179.411 | 5.498 | 6.037 | 6.381 | 94.973 / 373.035 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 326.815 | 29.422 | 36.312 | 52.622 | 189.813 / 373.215 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 298.560 | 154.646 | 210.926 | 281.454 | 190.409 / 375.109 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1157.630 | 0.851 | 0.915 | 1.080 | 99.938 / 372.930 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2269.124 | 4.315 | 4.804 | 6.160 | 198.880 / 372.930 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2308.784 | 21.403 | 22.257 | 24.826 | 199.815 / 373.598 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2118.357 | 46.878 | 55.102 | 69.403 | 200.912 / 375.000 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 93.325 | 10.608 | 11.576 | 16.183 | 86.038 / 375.582 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 173.339 | 55.188 | 66.084 | 100.533 | 173.922 / 376.012 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 160.306 | 282.233 | 495.035 | 578.145 | 174.196 / 378.273 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 885.876 | 1.117 | 1.173 | 1.233 | 99.484 / 378.273 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1712.184 | 5.779 | 7.299 | 8.826 | 199.292 / 378.273 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1700.498 | 29.000 | 32.041 | 43.518 | 200.220 / 378.273 | possible-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 839.397 | 1.187 | 1.235 | 1.295 | 99.924 / 378.305 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1681.614 | 5.899 | 6.205 | 7.666 | 199.318 / 378.305 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1686.835 | 28.837 | 32.104 | 43.275 | 199.801 / 378.305 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 843.878 | 1.179 | 1.239 | 1.318 | 99.503 / 378.430 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1655.710 | 5.943 | 6.524 | 10.214 | 198.824 / 378.430 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1667.474 | 29.436 | 30.736 | 45.122 | 199.767 / 378.430 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1637.502 | 58.922 | 61.834 | 101.673 | 199.726 / 381.797 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 66.395 | 14.693 | 16.182 | 17.383 | 66.640 / 382.328 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 123.274 | 77.839 | 105.648 | 143.730 | 133.005 / 382.328 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 111.695 | 396.880 | 711.057 | 789.553 | 132.362 / 382.328 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.716 | 844.242 | 1590.107 | 1669.736 | 133.834 / 382.328 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 863.068 | 1.136 | 1.209 | 1.265 | 99.438 / 382.328 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1711.626 | 5.750 | 6.141 | 9.184 | 199.720 / 382.328 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1719.403 | 28.640 | 31.114 | 39.092 | 200.331 / 382.328 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1692.025 | 57.433 | 61.900 | 94.067 | 200.768 / 382.328 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2467.734 | 15.683 | 51.988 | 58.269 | 382.784 / 621.004 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2399.478 | 36.218 | 56.671 | 80.114 | 389.715 / 625.059 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 137.915 | 257.904 | 746.792 | 1099.500 | 231.124 / 626.707 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 129.612 | 600.464 | 1335.291 | 1592.310 | 240.510 / 628.496 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 831.652 | 56.375 | 78.972 | 130.876 | 136.507 / 628.496 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2549.349 | 31.859 | 62.931 | 74.995 | 388.351 / 628.496 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.489 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.425 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.486 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.564 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.536 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.978 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.105 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.083 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.025 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.529 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.573 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.265 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.356 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.089 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.059 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.340 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.419 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.459 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.554 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.419 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.496 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.269 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.371 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.896 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.320 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.188 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.164 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.186 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.055 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.023 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.086 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.089 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.062 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.061 | — | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 666.320 | 148.682 | 158.624 | 165.905 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1113.966 | 178.145 | 195.953 | 196.244 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | confirmed-regression | completed: -12.8%, cpu_percent: -5.0%, duration_seconds: +0.1%, p50_ms: +14.0%, p95_ms: +17.9%, p99_ms: +28.7%, requests_per_second: -12.9%, rss_bytes: +0.7% |
| cache_miss | confirmed-regression | completed: -18.6%, cpu_percent: -4.9%, duration_seconds: -0.0%, p50_ms: +21.9%, p95_ms: +43.5%, p99_ms: +28.4%, requests_per_second: -18.6%, rss_bytes: +0.7% |
| cache_miss | confirmed-regression | completed: -18.8%, cpu_percent: -5.0%, duration_seconds: -0.1%, p50_ms: +23.3%, p95_ms: +28.0%, p99_ms: +23.7%, requests_per_second: -18.6%, rss_bytes: +0.7% |
| health_live | stable | completed: +1.2%, cpu_percent: +0.5%, duration_seconds: +4.9%, p50_ms: +2.6%, p95_ms: +2.1%, p99_ms: +0.4%, requests_per_second: -3.0%, rss_bytes: +0.6% |
| health_live | improvement | completed: +4.0%, cpu_percent: +0.0%, duration_seconds: +4.9%, p50_ms: +1.4%, p95_ms: +0.4%, p99_ms: -17.3%, requests_per_second: -0.7%, rss_bytes: +0.6% |
| health_live | stable | completed: -2.5%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +2.3%, p95_ms: +2.0%, p99_ms: -3.0%, requests_per_second: -2.6%, rss_bytes: +0.6% |
| health_live | stable | completed: -4.7%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +1.8%, p95_ms: +8.5%, p99_ms: +5.0%, requests_per_second: -4.9%, rss_bytes: +0.6% |
| home | possible-regression | completed: -9.1%, cpu_percent: -1.1%, duration_seconds: -0.0%, p50_ms: +9.5%, p95_ms: +8.0%, p99_ms: +20.8%, requests_per_second: -9.1%, rss_bytes: +0.5% |
| home | stable | completed: -9.4%, cpu_percent: -1.4%, duration_seconds: -0.1%, p50_ms: -0.9%, p95_ms: +18.1%, p99_ms: +18.4%, requests_per_second: -9.4%, rss_bytes: +0.6% |
| home | possible-regression | completed: -14.3%, cpu_percent: -2.1%, duration_seconds: +0.0%, p50_ms: +6.9%, p95_ms: +6.2%, p99_ms: +1.3%, requests_per_second: -14.3%, rss_bytes: +0.6% |
| categories | stable | completed: -0.8%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +0.5%, p95_ms: +0.7%, p99_ms: +0.2%, requests_per_second: -0.8%, rss_bytes: +0.6% |
| categories | stable | completed: +0.0%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -0.1%, p95_ms: +0.1%, p99_ms: -0.2%, requests_per_second: -0.3%, rss_bytes: +0.6% |
| categories | stable | completed: -2.8%, cpu_percent: -1.0%, duration_seconds: -0.0%, p50_ms: +1.8%, p95_ms: +2.2%, p99_ms: +9.3%, requests_per_second: -2.8%, rss_bytes: +0.6% |
| category | stable | completed: -1.5%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +0.1%, p95_ms: +0.5%, p99_ms: -12.8%, requests_per_second: +0.0%, rss_bytes: +0.6% |
| category | stable | completed: -4.1%, cpu_percent: +0.0%, duration_seconds: -4.6%, p50_ms: +3.9%, p95_ms: +7.2%, p99_ms: -1.1%, requests_per_second: -0.3%, rss_bytes: +0.6% |
| category | stable | completed: -1.4%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +1.3%, p95_ms: +2.4%, p99_ms: +1.6%, requests_per_second: -1.1%, rss_bytes: +0.6% |
| thread | stable | completed: -4.1%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: +4.6%, p95_ms: +1.7%, p99_ms: -10.3%, requests_per_second: -1.6%, rss_bytes: +0.6% |
| thread | stable | completed: +0.0%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: +18.1%, p99_ms: +13.1%, requests_per_second: -0.1%, rss_bytes: +0.6% |
| thread | stable | completed: -1.4%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +2.3%, p95_ms: -9.8%, p99_ms: +9.6%, requests_per_second: -1.3%, rss_bytes: +0.6% |
| thread | stable | completed: -4.4%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +3.0%, p95_ms: +3.2%, p99_ms: +2.2%, requests_per_second: -4.4%, rss_bytes: +0.6% |
| search | possible-regression | completed: -11.7%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +14.2%, p95_ms: +11.0%, p99_ms: +14.6%, requests_per_second: -11.7%, rss_bytes: +0.6% |
| search | confirmed-regression | completed: -15.4%, cpu_percent: +0.7%, duration_seconds: +0.1%, p50_ms: +16.4%, p95_ms: +12.7%, p99_ms: +11.3%, requests_per_second: -15.4%, rss_bytes: +0.6% |
| search | confirmed-regression | completed: -20.0%, cpu_percent: +1.9%, duration_seconds: -0.1%, p50_ms: +23.2%, p95_ms: +30.9%, p99_ms: +27.6%, requests_per_second: -19.9%, rss_bytes: +0.6% |
| search | confirmed-regression | completed: +0.0%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +22.6%, p95_ms: +24.9%, p99_ms: +25.0%, requests_per_second: +0.1%, rss_bytes: +0.6% |
| cache_hit | stable | completed: -4.6%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: +2.1%, p99_ms: +15.6%, requests_per_second: -0.6%, rss_bytes: +0.6% |
| cache_hit | stable | completed: -2.6%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +3.5%, p95_ms: +6.4%, p99_ms: +2.0%, requests_per_second: -2.6%, rss_bytes: +0.6% |
| cache_hit | improvement | completed: +0.3%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -0.8%, p95_ms: -11.6%, p99_ms: +1.0%, requests_per_second: +0.3%, rss_bytes: +0.6% |
| cache_hit | stable | completed: -2.8%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +3.6%, p95_ms: -8.2%, p99_ms: +3.7%, requests_per_second: -2.9%, rss_bytes: +0.6% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -8.3%, duration_seconds: +2.8%, p50_ms: -4.2%, p95_ms: +4.1%, p99_ms: +11.6%, requests_per_second: -3.4%, rss_bytes: +0.6% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -4.7%, duration_seconds: -2.9%, p50_ms: +0.9%, p95_ms: -3.1%, p99_ms: +6.7%, requests_per_second: +2.5%, rss_bytes: +0.6% |
| thread | stable | completed: -5.3%, cpu_percent: -4.6%, duration_seconds: +4.6%, p50_ms: +37.4%, p95_ms: -10.0%, p99_ms: +2.9%, requests_per_second: -5.1%, rss_bytes: +0.6% |
| thread | confirmed-regression | completed: -4.9%, cpu_percent: -1.0%, duration_seconds: +0.2%, p50_ms: +0.3%, p95_ms: +40.4%, p99_ms: +48.0%, requests_per_second: -5.0%, rss_bytes: +0.6% |
| search | stable | completed: -4.1%, cpu_percent: -1.4%, duration_seconds: +0.1%, p50_ms: +45.3%, p95_ms: -15.7%, p99_ms: -22.5%, requests_per_second: -4.2%, rss_bytes: +0.7% |
| search | stable | completed: +6.1%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: +24.4%, p95_ms: -2.7%, p99_ms: +6.5%, requests_per_second: +6.2%, rss_bytes: +0.6% |
| cache_hit | stable | completed: +2.3%, cpu_percent: -3.6%, duration_seconds: +0.1%, p50_ms: -11.3%, p95_ms: -8.2%, p99_ms: -8.4%, requests_per_second: -2.3%, rss_bytes: +0.6% |
| cache_hit | stable | completed: -2.7%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +13.1%, p95_ms: -0.2%, p99_ms: +0.8%, requests_per_second: -2.2%, rss_bytes: +0.7% |
| cache_miss | confirmed-regression | completed: -15.1%, cpu_percent: -4.5%, duration_seconds: -0.0%, p50_ms: +17.3%, p95_ms: +24.4%, p99_ms: +16.8%, requests_per_second: -15.1%, rss_bytes: +0.7% |
| cache_miss | confirmed-regression | completed: -20.4%, cpu_percent: -5.2%, duration_seconds: +0.0%, p50_ms: +25.3%, p95_ms: +26.5%, p99_ms: +22.6%, requests_per_second: -21.5%, rss_bytes: +0.7% |
| cache_miss | confirmed-regression | completed: -26.6%, cpu_percent: -5.6%, duration_seconds: +0.0%, p50_ms: +30.4%, p95_ms: +32.0%, p99_ms: +30.9%, requests_per_second: -26.6%, rss_bytes: +0.7% |
| health_live | stable | completed: +2.1%, cpu_percent: +0.5%, duration_seconds: +4.9%, p50_ms: +2.4%, p95_ms: +2.1%, p99_ms: +10.7%, requests_per_second: -1.1%, rss_bytes: +0.7% |
| health_live | stable | completed: +0.4%, cpu_percent: -0.2%, duration_seconds: +4.9%, p50_ms: +0.8%, p95_ms: +8.3%, p99_ms: +23.8%, requests_per_second: -2.4%, rss_bytes: +0.7% |
| health_live | stable | completed: -1.3%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +1.0%, p95_ms: +0.7%, p99_ms: -4.5%, requests_per_second: -1.0%, rss_bytes: +0.6% |
| health_live | stable | completed: -6.6%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +8.0%, p95_ms: +5.7%, p99_ms: +7.1%, requests_per_second: -6.7%, rss_bytes: +0.6% |
| home | stable | completed: -4.1%, cpu_percent: -2.8%, duration_seconds: +0.1%, p50_ms: +4.2%, p95_ms: +4.8%, p99_ms: +37.3%, requests_per_second: -4.2%, rss_bytes: +0.7% |
| home | stable | completed: -5.9%, cpu_percent: -2.0%, duration_seconds: -0.1%, p50_ms: -5.9%, p95_ms: -9.3%, p99_ms: -0.8%, requests_per_second: -3.2%, rss_bytes: +0.6% |
| home | stable | completed: +2.2%, cpu_percent: -1.8%, duration_seconds: -0.0%, p50_ms: +2.7%, p95_ms: -7.1%, p99_ms: -4.7%, requests_per_second: +2.3%, rss_bytes: +0.6% |
| categories | stable | completed: -1.2%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: +1.1%, p95_ms: +1.3%, p99_ms: -3.3%, requests_per_second: -1.1%, rss_bytes: +0.6% |
| categories | stable | completed: -2.7%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -0.3%, p95_ms: +19.8%, p99_ms: +6.0%, requests_per_second: +0.2%, rss_bytes: +0.6% |
| categories | possible-regression | completed: -1.8%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +1.6%, p95_ms: +6.4%, p99_ms: +10.8%, requests_per_second: -1.8%, rss_bytes: +0.6% |
| category | stable | completed: -4.0%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +4.3%, p95_ms: +2.7%, p99_ms: -8.8%, requests_per_second: -3.2%, rss_bytes: +0.6% |
| category | improvement | completed: +1.9%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +0.3%, p95_ms: -1.0%, p99_ms: -15.6%, requests_per_second: +0.7%, rss_bytes: +0.6% |
| category | stable | completed: -0.3%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: -0.9%, p95_ms: +7.0%, p99_ms: +7.3%, requests_per_second: -0.4%, rss_bytes: +0.6% |
| thread | stable | completed: -1.0%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +1.4%, p95_ms: +2.2%, p99_ms: +0.8%, requests_per_second: -0.9%, rss_bytes: +0.6% |
| thread | possible-regression | completed: -0.6%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -0.1%, p95_ms: -17.3%, p99_ms: +15.7%, requests_per_second: -0.0%, rss_bytes: +0.6% |
| thread | stable | completed: +1.1%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: -4.4%, p99_ms: -8.2%, requests_per_second: +1.2%, rss_bytes: +0.6% |
| thread | stable | completed: +0.2%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -1.6%, p95_ms: -3.9%, p99_ms: +1.5%, requests_per_second: +0.3%, rss_bytes: +0.7% |
| search | stable | completed: -5.7%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: +5.4%, p95_ms: +5.1%, p99_ms: +4.7%, requests_per_second: -5.8%, rss_bytes: +0.6% |
| search | stable | completed: -0.4%, cpu_percent: -0.9%, duration_seconds: +0.1%, p50_ms: +4.5%, p95_ms: +8.4%, p99_ms: +5.0%, requests_per_second: -2.0%, rss_bytes: +0.6% |
| search | stable | completed: +13.1%, cpu_percent: -1.4%, duration_seconds: -0.0%, p50_ms: +5.2%, p95_ms: -2.9%, p99_ms: -1.6%, requests_per_second: +13.0%, rss_bytes: +0.6% |
| search | stable | completed: +0.0%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: -0.1%, p95_ms: -4.4%, p99_ms: -3.5%, requests_per_second: -0.0%, rss_bytes: +0.6% |
| cache_hit | improvement | completed: -2.9%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -0.1%, p95_ms: -1.7%, p99_ms: -18.3%, requests_per_second: -0.1%, rss_bytes: +0.6% |
| cache_hit | stable | completed: -0.8%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: -0.7%, p95_ms: +1.7%, p99_ms: +2.6%, requests_per_second: +0.3%, rss_bytes: +0.6% |
| cache_hit | stable | completed: +1.7%, cpu_percent: -0.6%, duration_seconds: -0.1%, p50_ms: -2.1%, p95_ms: +0.6%, p99_ms: -7.3%, requests_per_second: +1.7%, rss_bytes: +0.6% |
| cache_hit | stable | completed: +2.9%, cpu_percent: +0.8%, duration_seconds: -0.1%, p50_ms: -2.4%, p95_ms: -5.2%, p99_ms: -4.9%, requests_per_second: +3.0%, rss_bytes: +0.6% |
| thread | confirmed-regression | completed: +4.9%, cpu_percent: -0.1%, duration_seconds: -0.2%, p50_ms: -19.0%, p95_ms: +58.7%, p99_ms: +31.9%, requests_per_second: +5.0%, rss_bytes: +0.7% |
| thread | stable | completed: +3.0%, cpu_percent: +0.9%, duration_seconds: -0.1%, p50_ms: -1.7%, p95_ms: -12.2%, p99_ms: +6.5%, requests_per_second: +3.2%, rss_bytes: +0.6% |
| search | stable | completed: -5.1%, cpu_percent: -0.5%, duration_seconds: +0.2%, p50_ms: +8.4%, p95_ms: +6.0%, p99_ms: +18.1%, requests_per_second: -4.9%, rss_bytes: +0.7% |
| search | possible-regression | completed: -7.4%, cpu_percent: -1.1%, duration_seconds: -0.1%, p50_ms: +21.5%, p95_ms: +41.1%, p99_ms: +43.5%, requests_per_second: -7.4%, rss_bytes: +0.8% |
| cache_hit | possible-regression | completed: -50.7%, cpu_percent: -38.1%, duration_seconds: -0.0%, p50_ms: +68.4%, p95_ms: +79.5%, p99_ms: +100.0%, requests_per_second: -50.9%, rss_bytes: +0.8% |
| cache_hit | stable | completed: +2.1%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -16.1%, p95_ms: +6.5%, p99_ms: +7.2%, requests_per_second: +2.0%, rss_bytes: +0.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -7.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -6.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -14.6% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -19.4% |
| sql-plan-readers | improvement | sql_execution_ms: -14.3% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -13.8% |
| sql-plan-readers | improvement | sql_execution_ms: -12.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -20.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -9.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +9.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -10.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -16.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -29.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -18.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +16.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -8.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.5% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +14.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -23.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +27.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -31.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -27.1% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -35.8% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +1.8%, messages_per_second: -1.8%, p50_ms: +1.6%, p95_ms: +5.0%, p99_ms: +2.8% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +3.2%, messages_per_second: -3.1%, p50_ms: +3.5%, p95_ms: +3.5%, p99_ms: +2.5% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.3%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +0.4%, p95_ms: +1.9%, p99_ms: -6.6%, requests_per_second: -0.2%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.0%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +1.4%, p95_ms: +2.1%, p99_ms: +24.2%, requests_per_second: -2.7%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -8.0%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +2.7%, p95_ms: +10.2%, p99_ms: +3.5%, requests_per_second: -8.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.0%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -1.0%, p95_ms: -1.0%, p99_ms: +12.0%, requests_per_second: +1.0%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.8%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -2.2%, p95_ms: +4.6%, p99_ms: +16.6%, requests_per_second: +1.0%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.7%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: -1.4%, p99_ms: -5.5%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -4.1%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +8.6%, p95_ms: +15.5%, p99_ms: +5.4%, requests_per_second: -4.0%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.9%, cpu_percent: -1.2%, duration_seconds: +0.1%, p50_ms: -2.8%, p95_ms: -5.6%, p99_ms: +15.1%, requests_per_second: +3.8%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +4.4%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: +8.4%, p95_ms: -9.3%, p99_ms: +1.9%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +7.0%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +0.8%, p95_ms: -0.5%, p99_ms: +1.5%, requests_per_second: +7.1%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.2%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -2.5%, p95_ms: -4.1%, p99_ms: -4.4%, requests_per_second: +3.1%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -0.6%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +0.0%, p95_ms: +21.3%, p99_ms: +31.7%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -1.2%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +1.8%, p95_ms: +6.9%, p99_ms: +10.3%, requests_per_second: -1.2%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.2%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +3.1%, p95_ms: +0.7%, p99_ms: -1.3%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.7%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -3.0%, p95_ms: -6.9%, p99_ms: +1.0%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.6%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: +5.9%, p99_ms: +15.1%, requests_per_second: -0.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +2.4%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -3.2%, p95_ms: -2.4%, p99_ms: -15.4%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -0.2%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -0.1%, p95_ms: -11.6%, p99_ms: +31.4%, requests_per_second: -0.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.2%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: -1.2%, p95_ms: -1.4%, p99_ms: +1.6%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.6%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -2.7%, p95_ms: -3.1%, p99_ms: +3.8%, requests_per_second: +2.6%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.9%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: -5.4%, p95_ms: -6.1%, p99_ms: -6.0%, requests_per_second: +3.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +14.1%, cpu_percent: -1.2%, duration_seconds: +0.1%, p50_ms: -9.9%, p95_ms: +1.4%, p99_ms: +0.5%, requests_per_second: +12.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +12.0%, cpu_percent: -2.2%, duration_seconds: +0.1%, p50_ms: -11.3%, p95_ms: -10.2%, p99_ms: -8.7%, requests_per_second: +11.9%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -5.2%, p95_ms: -5.9%, p99_ms: -5.9%, requests_per_second: -0.0%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.7%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -2.5%, p95_ms: -2.3%, p99_ms: -13.2%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.3%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: -2.7%, p95_ms: -3.4%, p99_ms: +6.5%, requests_per_second: +2.3%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.8%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -1.5%, p95_ms: +2.4%, p99_ms: -1.1%, requests_per_second: +1.8%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.8%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -2.8%, p95_ms: -2.4%, p99_ms: -1.3%, requests_per_second: +2.8%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +4.9%, cpu_percent: +4.1%, duration_seconds: -4.5%, p50_ms: -33.4%, p95_ms: +46.5%, p99_ms: +15.1%, requests_per_second: +4.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.1%, cpu_percent: +1.7%, duration_seconds: -0.3%, p50_ms: -9.5%, p95_ms: -20.9%, p99_ms: -13.2%, requests_per_second: +2.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: -1.5%, duration_seconds: +0.3%, p50_ms: -10.1%, p95_ms: +9.2%, p99_ms: +36.5%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.4%, cpu_percent: +0.6%, duration_seconds: +0.2%, p50_ms: -1.0%, p95_ms: -1.3%, p99_ms: +7.3%, requests_per_second: -0.7%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -51.4%, cpu_percent: -34.7%, duration_seconds: -0.1%, p50_ms: +91.0%, p95_ms: +119.8%, p99_ms: +145.6%, requests_per_second: -49.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +3.8%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: -19.6%, p95_ms: -3.1%, p99_ms: -6.1%, requests_per_second: +3.6%, rss_bytes: +0.4% |
| thread | workers=4 | 2 | 50 | improvement | completed: +42.9%, cpu_percent: +83.5%, duration_seconds: +4.8%, p50_ms: -21.0%, p95_ms: +13.8%, p99_ms: +13.9%, requests_per_second: +42.8%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +47.3%, cpu_percent: +91.3%, duration_seconds: +0.4%, p50_ms: -34.0%, p95_ms: +12.3%, p99_ms: -5.8%, requests_per_second: +47.1%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +39.5%, cpu_percent: +73.4%, duration_seconds: +0.2%, p50_ms: -35.9%, p95_ms: -13.6%, p99_ms: -6.8%, requests_per_second: +39.0%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +31.0%, cpu_percent: +78.7%, duration_seconds: +0.2%, p50_ms: -31.9%, p95_ms: -19.9%, p99_ms: -16.3%, requests_per_second: +30.9%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +1.8%, cpu_percent: +4.4%, duration_seconds: +0.2%, p50_ms: +1.5%, p95_ms: +18.2%, p99_ms: +34.8%, requests_per_second: -2.8%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.6%, cpu_percent: +92.8%, duration_seconds: +0.1%, p50_ms: -32.9%, p95_ms: +2.3%, p99_ms: -16.2%, requests_per_second: +49.5%, rss_bytes: +64.3% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +48.2%, cpu_percent: +91.6%, duration_seconds: +0.0%, p50_ms: -46.7%, p95_ms: +69.1%, p99_ms: +29.1%, requests_per_second: +48.0%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +46.6%, cpu_percent: +95.1%, duration_seconds: +0.0%, p50_ms: -38.5%, p95_ms: -8.3%, p99_ms: -21.2%, requests_per_second: +46.5%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 50 | improvement | completed: +24.1%, cpu_percent: +74.6%, duration_seconds: +0.4%, p50_ms: -35.0%, p95_ms: +5.0%, p99_ms: +39.3%, requests_per_second: +23.5%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +30.5%, cpu_percent: +79.7%, duration_seconds: +0.4%, p50_ms: -28.9%, p95_ms: -16.0%, p99_ms: -4.6%, requests_per_second: +30.0%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -51.4%, cpu_percent: -31.9%, duration_seconds: +0.0%, p50_ms: +96.8%, p95_ms: +153.8%, p99_ms: +234.8%, requests_per_second: -51.6%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +51.2%, cpu_percent: +93.4%, duration_seconds: +0.3%, p50_ms: -44.5%, p95_ms: +1.7%, p99_ms: -20.3%, requests_per_second: +50.7%, rss_bytes: +64.4% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38740879075)
