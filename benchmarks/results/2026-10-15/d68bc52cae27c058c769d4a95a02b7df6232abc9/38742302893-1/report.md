# GPForum continuous performance evidence

Commit: `d68bc52cae27c058c769d4a95a02b7df6232abc9` · mode: **main** · status: **ok**
Run: 38742302893 / attempt 1 · 2026-10-15T13:24:07.282340+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. df695481d8eea94239b52f9aef751e16a1aa536e

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 153.432 | 6.516 | 7.143 | 7.508 | 94.411 / 371.910 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 281.746 | 32.994 | 46.464 | 52.256 | 189.765 / 371.980 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 249.790 | 187.609 | 278.980 | 348.683 | 189.690 / 373.777 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1133.299 | 0.867 | 0.942 | 1.013 | 99.351 / 371.668 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2197.462 | 4.514 | 4.718 | 5.297 | 198.749 / 371.668 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2172.761 | 22.535 | 23.616 | 29.917 | 200.634 / 372.234 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2169.437 | 45.045 | 49.877 | 67.966 | 201.082 / 373.500 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 78.422 | 12.876 | 14.320 | 15.617 | 87.016 / 374.031 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 127.321 | 78.762 | 88.584 | 136.437 | 173.391 / 374.621 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.751 | 379.764 | 638.544 | 707.121 | 173.150 / 376.941 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 849.567 | 1.165 | 1.296 | 1.500 | 99.440 / 376.941 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1665.741 | 5.887 | 6.972 | 9.127 | 198.735 / 376.941 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1672.705 | 29.636 | 31.277 | 38.833 | 201.177 / 376.941 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 816.815 | 1.212 | 1.302 | 1.792 | 99.842 / 377.098 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1596.941 | 6.198 | 6.619 | 7.194 | 199.141 / 377.098 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1605.881 | 30.461 | 34.615 | 43.091 | 200.177 / 377.098 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 817.621 | 1.202 | 1.305 | 1.710 | 99.871 / 377.223 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1635.537 | 6.073 | 6.465 | 7.844 | 199.213 / 377.223 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1585.871 | 31.003 | 34.819 | 41.059 | 201.117 / 377.223 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1545.301 | 62.926 | 67.940 | 101.248 | 201.129 / 379.984 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 57.444 | 16.987 | 20.481 | 23.088 | 68.606 / 380.758 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 102.928 | 87.787 | 129.668 | 163.008 | 136.053 / 380.758 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 86.831 | 470.713 | 894.411 | 977.742 | 135.303 / 380.758 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.832 | 891.606 | 1666.786 | 1747.326 | 135.761 / 380.758 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 835.732 | 1.179 | 1.267 | 1.642 | 99.407 / 380.758 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1627.569 | 6.066 | 6.499 | 7.815 | 199.201 / 380.758 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1622.005 | 30.484 | 33.183 | 39.584 | 201.598 / 380.758 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1595.436 | 61.730 | 64.505 | 97.373 | 201.195 / 380.758 | stable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1346.568 | 6.703 | 9.911 | 12.622 | 28.309 / 380.758 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 929.758 | 9.722 | 14.783 | 17.461 | 38.745 / 381.039 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2222.092 | 19.986 | 40.557 | 66.822 | 381.130 / 619.145 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2259.286 | 43.332 | 55.430 | 71.297 | 387.921 / 622.969 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 130.184 | 275.746 | 762.996 | 1079.827 | 238.177 / 624.766 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 117.457 | 485.993 | 1384.610 | 1629.341 | 242.109 / 625.828 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1954.434 | 18.868 | 41.930 | 52.091 | 303.715 / 625.828 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 1892.243 | 46.023 | 105.435 | 142.557 | 333.892 / 625.828 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 169.958 | 5.761 | 6.827 | 7.478 | 94.472 / 372.848 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 316.812 | 31.791 | 44.462 | 54.931 | 189.311 / 372.910 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 286.525 | 168.017 | 236.612 | 308.426 | 190.865 / 374.824 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1176.357 | 0.837 | 0.903 | 0.963 | 99.821 / 372.945 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2252.015 | 4.403 | 4.629 | 5.174 | 198.699 / 372.945 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2224.600 | 22.143 | 25.052 | 28.927 | 199.740 / 373.703 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2143.836 | 46.136 | 49.921 | 69.249 | 201.638 / 375.098 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 76.455 | 13.060 | 14.167 | 14.646 | 87.000 / 375.652 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 141.872 | 67.463 | 79.486 | 125.753 | 173.397 / 376.234 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.665 | 339.918 | 615.924 | 683.795 | 174.077 / 378.727 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 843.543 | 1.167 | 1.272 | 1.505 | 99.397 / 378.727 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1642.013 | 5.974 | 6.628 | 10.251 | 199.225 / 378.727 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1611.083 | 30.270 | 34.255 | 43.709 | 201.089 / 378.727 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 855.186 | 1.153 | 1.227 | 1.411 | 99.800 / 378.758 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1588.904 | 6.091 | 8.051 | 10.665 | 199.147 / 378.758 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1605.894 | 30.421 | 33.289 | 41.721 | 199.601 / 378.758 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 851.897 | 1.157 | 1.232 | 1.270 | 99.376 / 378.824 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1630.560 | 6.077 | 7.284 | 10.779 | 199.222 / 378.883 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1626.119 | 31.072 | 36.176 | 47.749 | 200.089 / 378.883 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1541.628 | 62.434 | 74.292 | 104.102 | 199.651 / 381.453 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 55.923 | 17.675 | 19.626 | 21.774 | 69.108 / 382.059 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 98.452 | 95.211 | 111.305 | 176.796 | 135.128 / 382.059 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 99.295 | 481.485 | 873.419 | 943.808 | 136.250 / 382.059 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 75.797 | 725.537 | 1769.645 | 1871.748 | 135.714 / 382.133 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 833.176 | 1.192 | 1.317 | 1.563 | 122.161 / 382.133 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1659.826 | 6.367 | 7.274 | 10.373 | 199.206 / 382.133 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1617.412 | 29.926 | 33.666 | 47.151 | 200.636 / 382.133 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1570.676 | 62.407 | 71.785 | 98.097 | 200.639 / 382.133 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2171.361 | 24.506 | 40.706 | 51.864 | 384.052 / 620.812 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2205.131 | 44.615 | 70.810 | 87.129 | 389.176 / 625.332 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 131.084 | 277.559 | 772.415 | 1057.813 | 239.178 / 626.820 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 120.899 | 652.547 | 1282.837 | 1422.217 | 240.819 / 627.676 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1559.193 | 31.810 | 40.061 | 59.132 | 213.798 / 627.691 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2239.161 | 41.342 | 72.381 | 88.249 | 384.636 / 627.691 | possible-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.556 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.502 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.553 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.781 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.104 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.640 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.125 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.121 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.108 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.646 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.604 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.298 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.376 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.121 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.064 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.060 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.412 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.479 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.539 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.588 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.421 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.551 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.306 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.368 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.965 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.364 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.199 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.172 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.203 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.058 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.089 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.087 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 621.487 | 158.591 | 172.547 | 177.864 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1036.836 | 189.816 | 209.577 | 215.036 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | confirmed-regression | completed: -14.7%, cpu_percent: -0.6%, duration_seconds: -0.1%, p50_ms: +18.9%, p95_ms: +20.6%, p99_ms: +9.9%, requests_per_second: -14.6%, rss_bytes: -0.0% |
| cache_miss | confirmed-regression | completed: -16.2%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +13.7%, p95_ms: +30.6%, p99_ms: +23.3%, requests_per_second: -16.1%, rss_bytes: -0.0% |
| cache_miss | confirmed-regression | completed: -23.1%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +24.6%, p95_ms: +45.8%, p99_ms: +28.2%, requests_per_second: -23.0%, rss_bytes: -0.0% |
| health_live | stable | completed: -4.1%, cpu_percent: -0.6%, duration_seconds: -4.7%, p50_ms: +0.8%, p95_ms: +1.9%, p99_ms: +5.1%, requests_per_second: -1.1%, rss_bytes: -0.1% |
| health_live | stable | completed: -6.7%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +2.3%, p95_ms: +2.7%, p99_ms: +0.3%, requests_per_second: -2.2%, rss_bytes: -0.1% |
| health_live | possible-regression | completed: -4.4%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +4.2%, p95_ms: +4.6%, p99_ms: +13.9%, requests_per_second: -4.4%, rss_bytes: -0.1% |
| health_live | stable | completed: -1.8%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +4.4%, p95_ms: +4.6%, p99_ms: +3.2%, requests_per_second: -1.7%, rss_bytes: -0.1% |
| home | confirmed-regression | completed: -12.8%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +17.9%, p95_ms: +16.8%, p99_ms: +11.1%, requests_per_second: -12.8%, rss_bytes: -0.1% |
| home | confirmed-regression | completed: -24.8%, cpu_percent: -0.9%, duration_seconds: +0.1%, p50_ms: +54.7%, p95_ms: +21.6%, p99_ms: +38.3%, requests_per_second: -24.7%, rss_bytes: -0.1% |
| home | confirmed-regression | completed: -16.7%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +35.6%, p95_ms: +28.3%, p99_ms: +24.2%, requests_per_second: -16.7%, rss_bytes: -0.1% |
| categories | stable | completed: +0.2%, cpu_percent: +0.1%, duration_seconds: +4.8%, p50_ms: +1.7%, p95_ms: +6.0%, p99_ms: +16.3%, requests_per_second: -1.1%, rss_bytes: -0.1% |
| categories | confirmed-regression | completed: -2.8%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +1.9%, p95_ms: +15.9%, p99_ms: +36.2%, requests_per_second: -3.0%, rss_bytes: -0.1% |
| categories | stable | completed: -2.9%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +4.0%, p95_ms: +4.3%, p99_ms: -1.6%, requests_per_second: -2.8%, rss_bytes: -0.1% |
| category | stable | completed: -4.8%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +5.3%, p95_ms: +6.1%, p99_ms: +36.6%, requests_per_second: -4.7%, rss_bytes: -0.0% |
| category | stable | completed: -4.6%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +1.9%, p95_ms: -0.7%, p99_ms: -5.2%, requests_per_second: -4.6%, rss_bytes: -0.0% |
| category | possible-regression | completed: -5.4%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +5.0%, p95_ms: +14.2%, p99_ms: +14.7%, requests_per_second: -5.5%, rss_bytes: -0.0% |
| thread | stable | completed: -0.7%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -1.3%, p95_ms: +2.8%, p99_ms: +9.8%, requests_per_second: -0.7%, rss_bytes: -0.0% |
| thread | stable | completed: -1.4%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +2.1%, p95_ms: -12.4%, p99_ms: +0.9%, requests_per_second: -1.2%, rss_bytes: -0.0% |
| thread | stable | completed: -3.8%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +4.0%, p95_ms: +11.7%, p99_ms: -7.6%, requests_per_second: -3.9%, rss_bytes: -0.0% |
| thread | stable | completed: -3.2%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +3.9%, p95_ms: +6.4%, p99_ms: +3.4%, requests_per_second: -3.2%, rss_bytes: -0.1% |
| search | confirmed-regression | completed: -10.2%, cpu_percent: +2.2%, duration_seconds: +0.0%, p50_ms: +9.3%, p95_ms: +18.8%, p99_ms: +24.8%, requests_per_second: -10.2%, rss_bytes: +0.0% |
| search | confirmed-regression | completed: -6.4%, cpu_percent: +1.0%, duration_seconds: -0.1%, p50_ms: +1.6%, p95_ms: +24.5%, p99_ms: +14.0%, requests_per_second: -6.3%, rss_bytes: -0.1% |
| search | stable | completed: -13.0%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +5.2%, p95_ms: +12.9%, p99_ms: +13.1%, requests_per_second: -13.0%, rss_bytes: -0.1% |
| search | stable | completed: +0.0%, cpu_percent: +1.5%, duration_seconds: -0.1%, p50_ms: +0.1%, p95_ms: -1.3%, p99_ms: -1.5%, requests_per_second: +0.1%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -1.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +1.2%, p95_ms: +2.4%, p99_ms: +12.7%, requests_per_second: -1.5%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -1.5%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +2.7%, p95_ms: +2.3%, p99_ms: -9.4%, requests_per_second: -2.7%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -4.0%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +4.8%, p95_ms: +9.2%, p99_ms: +0.1%, requests_per_second: -4.0%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -3.2%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +4.4%, p95_ms: +1.7%, p99_ms: +2.1%, requests_per_second: -3.0%, rss_bytes: -0.1% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +9.1%, duration_seconds: +0.0%, p50_ms: +5.0%, p95_ms: -6.2%, p99_ms: -13.3%, requests_per_second: +0.2%, rss_bytes: -0.1% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +1.2%, duration_seconds: +6.9%, p50_ms: +4.8%, p95_ms: +9.7%, p99_ms: +2.6%, requests_per_second: -5.9%, rss_bytes: -0.1% |
| thread | confirmed-regression | completed: -5.6%, cpu_percent: +3.7%, duration_seconds: -4.4%, p50_ms: -15.1%, p95_ms: +14.3%, p99_ms: +32.0%, requests_per_second: -5.7%, rss_bytes: -0.0% |
| thread | improvement | completed: -3.8%, cpu_percent: +1.3%, duration_seconds: -0.3%, p50_ms: +8.3%, p95_ms: -22.6%, p99_ms: -22.7%, requests_per_second: -3.7%, rss_bytes: -0.0% |
| search | stable | completed: -6.1%, cpu_percent: +1.5%, duration_seconds: +0.1%, p50_ms: -3.9%, p95_ms: +11.6%, p99_ms: +34.0%, requests_per_second: -6.2%, rss_bytes: -0.0% |
| search | possible-regression | completed: -9.9%, cpu_percent: +1.3%, duration_seconds: +0.0%, p50_ms: -19.9%, p95_ms: +2.3%, p99_ms: +9.8%, requests_per_second: -10.0%, rss_bytes: -0.0% |
| cache_hit | stable | completed: +13.6%, cpu_percent: +45.4%, duration_seconds: -0.2%, p50_ms: -36.1%, p95_ms: +16.7%, p99_ms: -2.2%, requests_per_second: +19.0%, rss_bytes: -0.0% |
| cache_hit | confirmed-regression | completed: -23.0%, cpu_percent: -13.7%, duration_seconds: +0.0%, p50_ms: +16.1%, p95_ms: +62.4%, p99_ms: +78.4%, requests_per_second: -23.1%, rss_bytes: -0.0% |
| cache_miss | confirmed-regression | completed: -5.3%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +4.8%, p95_ms: +13.1%, p99_ms: +17.2%, requests_per_second: -5.3%, rss_bytes: -0.1% |
| cache_miss | confirmed-regression | completed: -5.8%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: +8.1%, p95_ms: +22.4%, p99_ms: +4.4%, requests_per_second: -3.1%, rss_bytes: -0.1% |
| cache_miss | stable | completed: -4.0%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +8.6%, p95_ms: +12.2%, p99_ms: +9.6%, requests_per_second: -4.0%, rss_bytes: -0.1% |
| health_live | stable | completed: +0.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -1.6%, p95_ms: -1.3%, p99_ms: -10.8%, requests_per_second: +1.6%, rss_bytes: +0.0% |
| health_live | stable | completed: +1.1%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +2.0%, p95_ms: -3.6%, p99_ms: -16.0%, requests_per_second: -0.8%, rss_bytes: +0.0% |
| health_live | confirmed-regression | completed: -3.7%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +3.5%, p95_ms: +12.6%, p99_ms: +16.5%, requests_per_second: -3.6%, rss_bytes: +0.0% |
| health_live | stable | completed: +1.1%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -1.6%, p95_ms: -9.4%, p99_ms: -0.2%, requests_per_second: +1.2%, rss_bytes: +0.0% |
| home | confirmed-regression | completed: -18.2%, cpu_percent: +1.1%, duration_seconds: -0.1%, p50_ms: +23.1%, p95_ms: +22.4%, p99_ms: -9.5%, requests_per_second: -18.1%, rss_bytes: +0.0% |
| home | confirmed-regression | completed: -19.8%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +22.2%, p95_ms: +20.3%, p99_ms: +25.1%, requests_per_second: -18.2%, rss_bytes: +0.1% |
| home | confirmed-regression | completed: -22.1%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +20.4%, p95_ms: +24.4%, p99_ms: +18.3%, requests_per_second: -22.2%, rss_bytes: +0.1% |
| categories | confirmed-regression | completed: -4.8%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +4.5%, p95_ms: +8.4%, p99_ms: +22.1%, requests_per_second: -4.8%, rss_bytes: +0.1% |
| categories | confirmed-regression | completed: -2.6%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +3.4%, p95_ms: -9.2%, p99_ms: +16.1%, requests_per_second: -4.1%, rss_bytes: +0.1% |
| categories | stable | completed: -3.6%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: +4.4%, p95_ms: +6.9%, p99_ms: +0.4%, requests_per_second: -5.3%, rss_bytes: +0.1% |
| category | stable | completed: +1.9%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -2.9%, p95_ms: -0.6%, p99_ms: +9.0%, requests_per_second: +1.9%, rss_bytes: +0.1% |
| category | confirmed-regression | completed: -6.6%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +3.3%, p95_ms: +29.8%, p99_ms: +39.1%, requests_per_second: -5.5%, rss_bytes: +0.1% |
| category | stable | completed: -4.8%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +5.5%, p95_ms: +3.7%, p99_ms: -3.6%, requests_per_second: -4.8%, rss_bytes: +0.1% |
| thread | stable | completed: +1.1%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -1.9%, p95_ms: -0.6%, p99_ms: -3.6%, requests_per_second: +0.9%, rss_bytes: +0.1% |
| thread | stable | completed: -1.5%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +2.3%, p95_ms: +11.6%, p99_ms: +5.5%, requests_per_second: -1.5%, rss_bytes: +0.1% |
| thread | confirmed-regression | completed: -2.6%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +5.6%, p95_ms: +17.7%, p99_ms: +5.8%, requests_per_second: -2.5%, rss_bytes: +0.1% |
| thread | possible-regression | completed: -5.8%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: +6.0%, p95_ms: +20.1%, p99_ms: +2.4%, requests_per_second: -5.9%, rss_bytes: -0.1% |
| search | confirmed-regression | completed: -15.8%, cpu_percent: +3.7%, duration_seconds: +0.0%, p50_ms: +20.3%, p95_ms: +21.3%, p99_ms: +25.3%, requests_per_second: -15.8%, rss_bytes: -0.1% |
| search | confirmed-regression | completed: -21.5%, cpu_percent: +1.6%, duration_seconds: -0.1%, p50_ms: +22.3%, p95_ms: +5.4%, p99_ms: +23.0%, requests_per_second: -20.1%, rss_bytes: -0.1% |
| search | confirmed-regression | completed: -11.2%, cpu_percent: +2.9%, duration_seconds: -0.1%, p50_ms: +21.3%, p95_ms: +22.8%, p99_ms: +19.5%, requests_per_second: -11.1%, rss_bytes: -0.1% |
| search | possible-regression | completed: -24.0%, cpu_percent: +1.4%, duration_seconds: -0.0%, p50_ms: -14.1%, p95_ms: +11.3%, p99_ms: +12.1%, requests_per_second: -24.0%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -3.4%, cpu_percent: +22.9%, duration_seconds: +0.0%, p50_ms: +4.9%, p95_ms: +8.9%, p99_ms: +23.6%, requests_per_second: -3.5%, rss_bytes: -0.1% |
| cache_hit | possible-regression | completed: -3.1%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +10.7%, p95_ms: +18.4%, p99_ms: +12.9%, requests_per_second: -3.0%, rss_bytes: -0.1% |
| cache_hit | confirmed-regression | completed: -6.0%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +4.5%, p95_ms: +8.2%, p99_ms: +20.6%, requests_per_second: -5.9%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -7.2%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +8.7%, p95_ms: +16.0%, p99_ms: +4.3%, requests_per_second: -7.2%, rss_bytes: -0.1% |
| thread | possible-regression | completed: -12.2%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +56.3%, p95_ms: -21.7%, p99_ms: -11.0%, requests_per_second: -12.0%, rss_bytes: -0.0% |
| thread | confirmed-regression | completed: -7.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +23.2%, p95_ms: +24.9%, p99_ms: +8.8%, requests_per_second: -8.1%, rss_bytes: +0.0% |
| search | stable | completed: -5.0%, cpu_percent: +3.5%, duration_seconds: -0.2%, p50_ms: +7.6%, p95_ms: +3.4%, p99_ms: -3.8%, requests_per_second: -5.0%, rss_bytes: +0.0% |
| search | stable | completed: -6.5%, cpu_percent: +0.1%, duration_seconds: -0.2%, p50_ms: +8.7%, p95_ms: -3.9%, p99_ms: -10.7%, requests_per_second: -6.7%, rss_bytes: -0.1% |
| cache_hit | improvement | completed: +86.7%, cpu_percent: +56.6%, duration_seconds: +0.0%, p50_ms: -43.6%, p95_ms: -49.3%, p99_ms: -54.8%, requests_per_second: +87.5%, rss_bytes: -0.1% |
| cache_hit | possible-regression | completed: -12.3%, cpu_percent: -1.0%, duration_seconds: -0.2%, p50_ms: +29.8%, p95_ms: +15.0%, p99_ms: +17.7%, requests_per_second: -12.2%, rss_bytes: -0.1% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +13.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +18.1% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +13.8% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +38.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +9.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.4% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +15.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +30.1% |
| sql-plan-readers | confirmed-regression | sql_execution_ms: +16.7% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +12.0% |
| sql-plan-readers | possible-regression | sql_execution_ms: +14.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +50.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +22.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.4% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +12.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +36.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +8.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +15.4% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +21.2% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +14.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +17.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +11.1% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.9% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +9.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -21.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +40.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +60.7% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +7.2%, messages_per_second: -6.7%, p50_ms: +6.7%, p95_ms: +8.8%, p99_ms: +7.2% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +7.4%, messages_per_second: -6.9%, p50_ms: +6.6%, p95_ms: +7.0%, p99_ms: +9.6% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +10.7%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -11.6%, p95_ms: -4.4%, p99_ms: -0.4%, requests_per_second: +10.8%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +12.4%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -3.6%, p95_ms: -4.3%, p99_ms: +5.1%, requests_per_second: +12.4%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +14.8%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -10.4%, p95_ms: -15.2%, p99_ms: -11.5%, requests_per_second: +14.7%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +5.1%, cpu_percent: +0.5%, duration_seconds: +5.0%, p50_ms: -3.5%, p95_ms: -4.1%, p99_ms: -4.9%, requests_per_second: +3.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +7.5%, cpu_percent: -0.0%, duration_seconds: +4.9%, p50_ms: -2.5%, p95_ms: -1.9%, p99_ms: -2.3%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.4%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -1.7%, p95_ms: +6.1%, p99_ms: -3.3%, requests_per_second: +2.4%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.2%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: +2.4%, p95_ms: +0.1%, p99_ms: +1.9%, requests_per_second: -1.2%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +1.4%, p95_ms: -1.1%, p99_ms: -6.2%, requests_per_second: -2.5%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +11.4%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -14.3%, p95_ms: -10.3%, p99_ms: -7.8%, requests_per_second: +11.4%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.0%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: -10.5%, p95_ms: -3.5%, p99_ms: -3.3%, requests_per_second: -0.1%, rss_bytes: +0.5% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.0%, cpu_percent: -0.0%, duration_seconds: -4.7%, p50_ms: +0.2%, p95_ms: -1.9%, p99_ms: +0.3%, requests_per_second: -0.7%, rss_bytes: +0.5% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -0.4%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +1.5%, p95_ms: -4.9%, p99_ms: +12.3%, requests_per_second: -1.4%, rss_bytes: +0.5% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -1.9%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +2.1%, p95_ms: +9.5%, p99_ms: +12.6%, requests_per_second: -3.7%, rss_bytes: +0.5% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.7%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -4.9%, p95_ms: -5.8%, p99_ms: -21.3%, requests_per_second: +4.7%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -0.5%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -1.7%, p95_ms: +21.6%, p99_ms: +48.2%, requests_per_second: -0.5%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.0%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: -0.1%, p95_ms: -3.8%, p99_ms: -3.2%, requests_per_second: +0.0%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.3%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -3.7%, p95_ms: -5.6%, p99_ms: -25.7%, requests_per_second: +4.2%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -0.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +12.7%, p99_ms: +37.4%, requests_per_second: -0.3%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.5%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: +0.2%, p95_ms: +3.9%, p99_ms: +16.3%, requests_per_second: +2.5%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.3%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: -0.8%, p95_ms: +9.3%, p99_ms: +2.8%, requests_per_second: -0.2%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.6%, cpu_percent: +0.7%, duration_seconds: +0.0%, p50_ms: +4.0%, p95_ms: -4.2%, p99_ms: -5.7%, requests_per_second: -2.6%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -4.4%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: +8.5%, p95_ms: -14.2%, p99_ms: +8.5%, requests_per_second: -4.3%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +14.4%, cpu_percent: +0.7%, duration_seconds: +0.0%, p50_ms: +2.3%, p95_ms: -2.3%, p99_ms: -3.5%, requests_per_second: +14.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -24.0%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -18.6%, p95_ms: +6.2%, p99_ms: +7.1%, requests_per_second: -24.1%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.3%, cpu_percent: +22.9%, duration_seconds: -0.0%, p50_ms: +1.1%, p95_ms: +3.9%, p99_ms: -4.8%, requests_per_second: -0.3%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +0.7%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +5.0%, p95_ms: +11.9%, p99_ms: +32.7%, requests_per_second: +2.0%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -0.3%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -1.8%, p95_ms: +1.5%, p99_ms: +19.1%, requests_per_second: -0.3%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.5%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +1.1%, p95_ms: +11.3%, p99_ms: +0.7%, requests_per_second: -1.6%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -2.3%, cpu_percent: +0.8%, duration_seconds: -0.0%, p50_ms: +22.6%, p95_ms: +0.4%, p99_ms: -22.4%, requests_per_second: -2.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | confirmed-regression | completed: -2.2%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +3.0%, p95_ms: +27.7%, p99_ms: +22.2%, requests_per_second: -2.4%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.8%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +0.7%, p95_ms: +1.2%, p99_ms: -2.0%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: +3.4%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +34.3%, p95_ms: -7.3%, p99_ms: -12.7%, requests_per_second: +2.9%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -20.1%, cpu_percent: -29.6%, duration_seconds: +0.0%, p50_ms: +68.6%, p95_ms: -4.5%, p99_ms: +13.5%, requests_per_second: -20.2%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +18.3%, cpu_percent: +15.2%, duration_seconds: -0.1%, p50_ms: -10.2%, p95_ms: -31.4%, p99_ms: -38.1%, requests_per_second: +18.3%, rss_bytes: +0.3% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +40.2%, cpu_percent: +89.5%, duration_seconds: +0.1%, p50_ms: -35.5%, p95_ms: +16.5%, p99_ms: +62.7%, requests_per_second: +40.1%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +46.4%, cpu_percent: +92.9%, duration_seconds: +0.2%, p50_ms: -31.1%, p95_ms: -18.4%, p99_ms: -29.6%, requests_per_second: +46.2%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +50.6%, cpu_percent: +76.0%, duration_seconds: +0.3%, p50_ms: -41.4%, p95_ms: -14.7%, p99_ms: +10.4%, requests_per_second: +49.9%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +18.0%, cpu_percent: +78.3%, duration_seconds: +0.3%, p50_ms: -45.5%, p95_ms: -16.9%, p99_ms: -6.8%, requests_per_second: +17.7%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +20.4%, cpu_percent: +50.7%, duration_seconds: +0.0%, p50_ms: -38.1%, p95_ms: +26.4%, p99_ms: +31.6%, requests_per_second: +20.5%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +19.0%, cpu_percent: +66.0%, duration_seconds: +0.2%, p50_ms: -25.4%, p95_ms: +63.5%, p99_ms: +46.4%, requests_per_second: +18.6%, rss_bytes: +64.4% |
| thread | workers=4 | 2 | 50 | improvement | completed: +33.5%, cpu_percent: +91.9%, duration_seconds: +0.2%, p50_ms: -21.1%, p95_ms: +12.5%, p99_ms: +8.6%, requests_per_second: +33.5%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | improvement | completed: +43.6%, cpu_percent: +94.9%, duration_seconds: +0.1%, p50_ms: -28.5%, p95_ms: -4.7%, p99_ms: -16.3%, requests_per_second: +43.0%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | possible-regression | completed: +32.7%, cpu_percent: +75.5%, duration_seconds: +0.3%, p50_ms: -42.4%, p95_ms: -11.6%, p99_ms: +12.1%, requests_per_second: +32.0%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +60.5%, cpu_percent: +77.4%, duration_seconds: +0.3%, p50_ms: -10.1%, p95_ms: -27.5%, p99_ms: -24.0%, requests_per_second: +59.5%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -3.5%, cpu_percent: +6.6%, duration_seconds: +0.1%, p50_ms: +6.3%, p95_ms: +19.0%, p99_ms: +25.4%, requests_per_second: -3.6%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +42.8%, cpu_percent: +91.7%, duration_seconds: +0.0%, p50_ms: -33.8%, p95_ms: +0.8%, p99_ms: -10.0%, requests_per_second: +42.6%, rss_bytes: +64.3% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38742302893)
