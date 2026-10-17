# GPForum continuous performance evidence

Commit: `7da17b2e5fc693349fa55cd6a14d637ea5c5976d` · mode: **main** · status: **ok**
Run: 38629924024 / attempt 1 · 2026-10-14T20:11:47.562654+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"ee7d3093ffc5cd7d0cc2f564417c6ad7f1e113aa0c1316b1b59386e9b

Baseline: Compatible baseline. b37223a7ff134cc711bbc06f1edfa61f95cc435e

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 315.593 | 3.143 | 3.233 | 3.661 | 99.488 / 370.445 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 622.327 | 15.831 | 16.279 | 23.990 | 199.465 / 370.445 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 622.489 | 81.429 | 83.252 | 138.620 | 201.447 / 372.145 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1232.912 | 0.797 | 0.857 | 1.027 | 99.517 / 370.496 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2473.181 | 4.005 | 4.197 | 4.650 | 198.998 / 370.496 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2521.668 | 19.881 | 21.109 | 25.980 | 199.980 / 371.215 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2499.175 | 39.737 | 46.396 | 64.866 | 200.969 / 372.539 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 146.374 | 6.725 | 7.209 | 8.854 | 84.599 / 372.898 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 280.655 | 34.633 | 42.083 | 54.620 | 169.565 / 373.312 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 266.120 | 179.585 | 255.277 | 337.130 | 170.927 / 375.027 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 942.087 | 1.053 | 1.103 | 1.273 | 99.488 / 375.027 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1846.201 | 5.343 | 5.577 | 6.159 | 199.478 / 375.027 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1874.478 | 25.814 | 27.430 | 33.520 | 200.473 / 375.027 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 908.634 | 1.090 | 1.137 | 1.229 | 99.503 / 375.059 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1784.385 | 5.368 | 5.735 | 6.735 | 199.507 / 375.059 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1808.122 | 27.038 | 28.200 | 34.741 | 199.965 / 375.059 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 880.716 | 1.129 | 1.179 | 1.227 | 99.525 / 375.121 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1741.013 | 5.672 | 5.890 | 6.330 | 199.477 / 375.184 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1772.426 | 27.846 | 28.554 | 36.826 | 200.477 / 375.750 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1745.589 | 55.456 | 62.536 | 92.861 | 201.451 / 379.004 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 89.953 | 10.959 | 12.163 | 13.217 | 63.720 / 379.684 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 159.709 | 60.990 | 78.201 | 102.643 | 130.837 / 379.684 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 149.731 | 315.265 | 503.917 | 581.704 | 130.544 / 379.684 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 149.757 | 603.937 | 1107.821 | 1188.180 | 129.520 / 379.684 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 933.806 | 1.059 | 1.113 | 1.156 | 99.542 / 379.684 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1851.309 | 5.315 | 5.560 | 7.380 | 198.775 / 379.684 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1880.058 | 26.357 | 26.971 | 33.235 | 200.515 / 379.684 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1844.430 | 53.266 | 57.860 | 84.883 | 201.475 / 379.684 | improvement |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1497.206 | 5.984 | 9.070 | 10.602 | 28.685 / 379.684 | improvement |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 967.922 | 9.026 | 15.288 | 16.826 | 40.186 / 379.965 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2478.334 | 15.735 | 31.365 | 36.779 | 390.944 / 616.906 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2444.293 | 28.263 | 59.823 | 86.648 | 391.830 / 620.953 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 183.834 | 186.498 | 589.236 | 711.820 | 234.091 / 622.262 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 172.755 | 341.413 | 1214.159 | 1313.957 | 239.988 / 624.492 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1718.980 | 35.924 | 66.400 | 98.815 | 221.344 / 625.449 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2550.543 | 32.697 | 64.998 | 85.123 | 392.822 / 625.449 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 316.368 | 3.130 | 3.219 | 3.505 | 100.035 / 371.363 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 627.736 | 15.853 | 19.753 | 26.323 | 200.309 / 371.363 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 619.381 | 79.893 | 84.160 | 143.312 | 201.441 / 373.137 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1273.489 | 0.776 | 0.830 | 0.975 | 99.009 / 371.465 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2543.429 | 3.893 | 4.106 | 5.933 | 199.036 / 371.465 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2576.910 | 19.084 | 19.868 | 26.229 | 200.906 / 372.309 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2564.619 | 38.344 | 39.992 | 58.274 | 200.968 / 373.660 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 146.284 | 6.750 | 7.281 | 8.380 | 84.610 / 374.031 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 278.114 | 34.764 | 42.443 | 63.133 | 170.158 / 374.461 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 271.933 | 176.339 | 266.729 | 338.971 | 170.896 / 376.199 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 949.543 | 1.037 | 1.106 | 1.199 | 100.069 / 376.199 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1915.895 | 5.362 | 6.308 | 8.767 | 199.551 / 376.199 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1926.991 | 25.503 | 27.126 | 39.030 | 200.460 / 376.199 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 922.445 | 1.063 | 1.124 | 1.562 | 99.498 / 376.359 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1809.394 | 5.484 | 6.590 | 9.392 | 199.529 / 376.359 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1825.455 | 26.994 | 28.351 | 44.629 | 200.960 / 376.359 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 895.038 | 1.108 | 1.164 | 1.331 | 99.523 / 376.484 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1804.577 | 5.549 | 6.914 | 9.437 | 199.355 / 376.484 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1809.859 | 26.861 | 30.205 | 48.779 | 200.407 / 377.078 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1766.760 | 56.508 | 64.195 | 95.701 | 201.882 / 380.223 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 87.389 | 11.114 | 12.615 | 14.035 | 64.701 / 381.020 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 160.339 | 61.092 | 81.205 | 125.881 | 128.878 / 381.020 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 148.791 | 296.433 | 546.979 | 625.298 | 129.535 / 381.020 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 149.087 | 604.735 | 1127.618 | 1203.706 | 130.044 / 381.020 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 955.997 | 1.038 | 1.093 | 1.119 | 99.408 / 381.020 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1867.240 | 5.312 | 5.530 | 7.712 | 198.997 / 381.020 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1890.886 | 25.756 | 27.386 | 37.990 | 200.424 / 381.020 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1866.951 | 52.692 | 56.974 | 86.573 | 201.866 / 381.020 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2484.100 | 16.926 | 32.342 | 39.356 | 388.276 / 618.762 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2447.501 | 38.239 | 59.609 | 99.160 | 392.627 / 623.148 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 187.092 | 174.250 | 565.383 | 714.773 | 234.378 / 624.945 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 163.932 | 347.561 | 1041.182 | 1135.373 | 243.684 / 625.934 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2572.592 | 18.986 | 31.505 | 41.873 | 391.783 / 625.934 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2540.610 | 43.488 | 62.101 | 76.301 | 393.216 / 625.934 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.446 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.457 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.477 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.082 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.897 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.619 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.092 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.078 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.023 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.423 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.524 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.264 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.301 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.066 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.044 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.043 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.408 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.386 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.478 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.384 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.495 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.267 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.300 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.488 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.078 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.185 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.150 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.172 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.014 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.105 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.055 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.058 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 756.095 | 131.987 | 145.710 | 157.525 | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1257.610 | 156.071 | 169.785 | 170.491 | — / — | improvement |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +37.7%, cpu_percent: -1.0%, duration_seconds: -0.0%, p50_ms: -26.9%, p95_ms: -32.7%, p99_ms: -28.2%, requests_per_second: +37.7%, rss_bytes: +0.2% |
| cache_miss | improvement | completed: +41.2%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -27.2%, p95_ms: -43.1%, p99_ms: -19.5%, requests_per_second: +40.2%, rss_bytes: +0.2% |
| cache_miss | improvement | completed: +57.0%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -29.5%, p95_ms: -51.3%, p99_ms: -32.6%, requests_per_second: +57.0%, rss_bytes: +0.2% |
| health_live | stable | completed: -0.8%, cpu_percent: +0.1%, duration_seconds: -4.8%, p50_ms: -3.3%, p95_ms: -3.1%, p99_ms: +7.5%, requests_per_second: +2.9%, rss_bytes: +0.3% |
| health_live | stable | completed: +11.2%, cpu_percent: +0.1%, duration_seconds: +4.9%, p50_ms: -7.2%, p95_ms: -8.3%, p99_ms: -7.2%, requests_per_second: +7.4%, rss_bytes: +0.3% |
| health_live | improvement | completed: +10.4%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -7.9%, p95_ms: -8.2%, p99_ms: +1.8%, requests_per_second: +10.5%, rss_bytes: +0.3% |
| health_live | improvement | completed: +13.8%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -10.9%, p95_ms: -3.1%, p99_ms: -1.1%, requests_per_second: +13.9%, rss_bytes: +0.3% |
| home | improvement | completed: +38.9%, cpu_percent: -1.1%, duration_seconds: -0.0%, p50_ms: -28.6%, p95_ms: -27.3%, p99_ms: -13.7%, requests_per_second: +38.9%, rss_bytes: +0.3% |
| home | improvement | completed: +57.5%, cpu_percent: -1.7%, duration_seconds: -0.0%, p50_ms: -35.6%, p95_ms: -34.9%, p99_ms: -37.0%, requests_per_second: +56.0%, rss_bytes: +0.3% |
| home | improvement | completed: +52.3%, cpu_percent: -1.2%, duration_seconds: -0.0%, p50_ms: -36.2%, p95_ms: -36.6%, p99_ms: -30.7%, requests_per_second: +52.2%, rss_bytes: +0.3% |
| categories | stable | completed: +4.5%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -4.3%, p95_ms: -5.0%, p99_ms: -0.4%, requests_per_second: +4.6%, rss_bytes: +0.3% |
| categories | improvement | completed: +8.5%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -6.3%, p95_ms: -32.7%, p99_ms: -34.4%, requests_per_second: +8.8%, rss_bytes: +0.3% |
| categories | improvement | completed: +11.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -12.0%, p95_ms: -13.7%, p99_ms: -20.8%, requests_per_second: +11.2%, rss_bytes: +0.3% |
| category | stable | completed: +5.5%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -5.5%, p95_ms: -6.0%, p99_ms: -2.5%, requests_per_second: +5.5%, rss_bytes: +0.3% |
| category | stable | completed: +10.5%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -7.9%, p95_ms: -10.5%, p99_ms: -18.3%, requests_per_second: +8.4%, rss_bytes: +0.3% |
| category | improvement | completed: +11.7%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -10.9%, p95_ms: -17.9%, p99_ms: -13.6%, requests_per_second: +11.5%, rss_bytes: +0.3% |
| thread | stable | completed: +3.1%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -3.0%, p95_ms: -4.4%, p99_ms: -4.7%, requests_per_second: +3.8%, rss_bytes: +0.3% |
| thread | improvement | completed: +9.2%, cpu_percent: +0.3%, duration_seconds: +4.9%, p50_ms: -1.9%, p95_ms: -23.1%, p99_ms: -32.5%, requests_per_second: +8.9%, rss_bytes: +0.3% |
| thread | improvement | completed: +8.6%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: -9.3%, p95_ms: -13.8%, p99_ms: -13.1%, requests_per_second: +8.6%, rss_bytes: +0.3% |
| thread | improvement | completed: +9.2%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -10.0%, p95_ms: -5.7%, p99_ms: -5.5%, requests_per_second: +9.2%, rss_bytes: +0.3% |
| search | improvement | completed: +28.6%, cpu_percent: -5.8%, duration_seconds: +0.0%, p50_ms: -25.7%, p95_ms: -21.5%, p99_ms: -20.0%, requests_per_second: +34.3%, rss_bytes: +0.3% |
| search | improvement | completed: +36.2%, cpu_percent: -4.3%, duration_seconds: +0.1%, p50_ms: -17.0%, p95_ms: -27.3%, p99_ms: -32.5%, requests_per_second: +36.0%, rss_bytes: +0.3% |
| search | improvement | completed: +33.9%, cpu_percent: -3.4%, duration_seconds: -0.0%, p50_ms: -19.2%, p95_ms: -31.2%, p99_ms: -28.6%, requests_per_second: +34.0%, rss_bytes: +0.3% |
| search | improvement | completed: +50.0%, cpu_percent: -4.3%, duration_seconds: -0.1%, p50_ms: -25.0%, p95_ms: -27.4%, p99_ms: -27.4%, requests_per_second: +50.1%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +3.5%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -3.6%, p95_ms: -3.3%, p99_ms: -8.5%, requests_per_second: +3.6%, rss_bytes: +0.3% |
| cache_hit | improvement | completed: +15.6%, cpu_percent: -0.3%, duration_seconds: +4.9%, p50_ms: -13.5%, p95_ms: -20.4%, p99_ms: -5.9%, requests_per_second: +11.5%, rss_bytes: +0.3% |
| cache_hit | improvement | completed: +13.7%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -11.0%, p95_ms: -15.7%, p99_ms: -21.2%, requests_per_second: +13.8%, rss_bytes: +0.3% |
| cache_hit | improvement | completed: +10.5%, cpu_percent: +0.6%, duration_seconds: -0.2%, p50_ms: -9.4%, p95_ms: -6.1%, p99_ms: -9.8%, requests_per_second: +10.5%, rss_bytes: +0.3% |
| health_live | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +1.6%, duration_seconds: -18.3%, p50_ms: -4.0%, p95_ms: -26.0%, p99_ms: -28.1%, requests_per_second: +22.1%, rss_bytes: +0.3% |
| thread | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -6.8%, duration_seconds: -14.2%, p50_ms: -12.9%, p95_ms: -10.2%, p99_ms: -22.7%, requests_per_second: +16.3%, rss_bytes: +0.3% |
| thread | stable | completed: +20.4%, cpu_percent: +0.8%, duration_seconds: +0.1%, p50_ms: -28.6%, p95_ms: -31.3%, p99_ms: -28.6%, requests_per_second: +21.1%, rss_bytes: +0.2% |
| thread | improvement | completed: +28.1%, cpu_percent: -0.2%, duration_seconds: +4.7%, p50_ms: -33.8%, p95_ms: -27.7%, p99_ms: -11.5%, requests_per_second: +22.5%, rss_bytes: +0.2% |
| search | improvement | completed: +17.9%, cpu_percent: -3.6%, duration_seconds: +0.0%, p50_ms: -5.8%, p95_ms: -16.8%, p99_ms: -28.7%, requests_per_second: +17.9%, rss_bytes: +0.1% |
| search | stable | completed: +20.1%, cpu_percent: -1.9%, duration_seconds: -0.1%, p50_ms: -34.1%, p95_ms: +0.7%, p99_ms: -0.8%, requests_per_second: +20.1%, rss_bytes: +0.2% |
| cache_hit | possible-regression | completed: +4.4%, cpu_percent: +3.2%, duration_seconds: +0.3%, p50_ms: +13.8%, p95_ms: +62.7%, p99_ms: +56.5%, requests_per_second: +4.4%, rss_bytes: +0.4% |
| cache_hit | improvement | completed: +17.1%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -24.5%, p95_ms: -12.2%, p99_ms: -4.5%, requests_per_second: +16.2%, rss_bytes: +0.4% |
| cache_miss | improvement | completed: +39.7%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: -28.8%, p95_ms: -31.6%, p99_ms: -29.5%, requests_per_second: +39.7%, rss_bytes: +0.2% |
| cache_miss | improvement | completed: +45.3%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -27.2%, p95_ms: -35.1%, p99_ms: -34.6%, requests_per_second: +45.3%, rss_bytes: +0.1% |
| cache_miss | improvement | completed: +51.6%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -31.4%, p95_ms: -45.7%, p99_ms: -32.4%, requests_per_second: +51.8%, rss_bytes: +0.2% |
| health_live | stable | completed: +5.3%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -5.2%, p95_ms: -5.4%, p99_ms: +0.0%, requests_per_second: +5.3%, rss_bytes: +0.2% |
| health_live | improvement | completed: +12.9%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -10.3%, p95_ms: -16.8%, p99_ms: -23.4%, requests_per_second: +12.8%, rss_bytes: +0.2% |
| health_live | improvement | completed: +16.1%, cpu_percent: +0.3%, duration_seconds: +0.2%, p50_ms: -13.6%, p95_ms: -17.1%, p99_ms: -11.8%, requests_per_second: +15.4%, rss_bytes: +0.3% |
| health_live | improvement | completed: +19.5%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -15.8%, p95_ms: -16.6%, p99_ms: -12.7%, requests_per_second: +19.4%, rss_bytes: +0.3% |
| home | improvement | completed: +34.4%, cpu_percent: -1.1%, duration_seconds: +0.0%, p50_ms: -26.3%, p95_ms: -24.4%, p99_ms: -18.6%, requests_per_second: +34.4%, rss_bytes: +0.3% |
| home | improvement | completed: +58.8%, cpu_percent: -1.5%, duration_seconds: +0.1%, p50_ms: -17.7%, p95_ms: -56.9%, p99_ms: -56.4%, requests_per_second: +58.1%, rss_bytes: +0.3% |
| home | improvement | completed: +55.7%, cpu_percent: -1.6%, duration_seconds: +0.1%, p50_ms: -35.6%, p95_ms: -41.2%, p99_ms: -37.1%, requests_per_second: +55.6%, rss_bytes: +0.3% |
| categories | stable | completed: +6.6%, cpu_percent: -1.3%, duration_seconds: +0.0%, p50_ms: -6.9%, p95_ms: -6.1%, p99_ms: -10.9%, requests_per_second: +6.5%, rss_bytes: +0.3% |
| categories | stable | completed: +16.3%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -9.8%, p95_ms: -7.3%, p99_ms: -4.5%, requests_per_second: +16.3%, rss_bytes: +0.3% |
| categories | improvement | completed: +18.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -18.0%, p95_ms: -20.2%, p99_ms: -20.8%, requests_per_second: +18.7%, rss_bytes: +0.3% |
| category | stable | completed: +9.1%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -8.0%, p95_ms: -14.7%, p99_ms: -8.2%, requests_per_second: +9.1%, rss_bytes: +0.3% |
| category | stable | completed: +10.7%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -9.1%, p95_ms: -4.2%, p99_ms: -10.4%, requests_per_second: +10.5%, rss_bytes: +0.3% |
| category | improvement | completed: +12.4%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -11.3%, p95_ms: -29.6%, p99_ms: -11.3%, requests_per_second: +12.3%, rss_bytes: +0.3% |
| thread | improvement | completed: +12.5%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -7.1%, p95_ms: -26.6%, p99_ms: -32.7%, requests_per_second: +12.6%, rss_bytes: +0.3% |
| thread | stable | completed: +8.2%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: -10.1%, p95_ms: +1.0%, p99_ms: -5.7%, requests_per_second: +13.5%, rss_bytes: +0.3% |
| thread | stable | completed: +18.5%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -14.4%, p95_ms: -19.2%, p99_ms: -3.6%, requests_per_second: +18.4%, rss_bytes: +0.3% |
| thread | stable | completed: +14.2%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -10.4%, p95_ms: -8.6%, p99_ms: -7.5%, requests_per_second: +14.3%, rss_bytes: +0.3% |
| search | improvement | completed: +28.7%, cpu_percent: -5.0%, duration_seconds: -0.1%, p50_ms: -24.8%, p95_ms: -18.9%, p99_ms: -14.2%, requests_per_second: +30.7%, rss_bytes: +0.3% |
| search | improvement | completed: +38.2%, cpu_percent: -6.0%, duration_seconds: +4.8%, p50_ms: -26.9%, p95_ms: -27.0%, p99_ms: -26.3%, requests_per_second: +35.5%, rss_bytes: +0.3% |
| search | improvement | completed: +35.5%, cpu_percent: -4.9%, duration_seconds: -0.0%, p50_ms: -29.8%, p95_ms: -27.1%, p99_ms: -24.5%, requests_per_second: +35.5%, rss_bytes: +0.3% |
| search | improvement | completed: +49.5%, cpu_percent: -3.9%, duration_seconds: +0.1%, p50_ms: -27.4%, p95_ms: -27.8%, p99_ms: -26.4%, requests_per_second: +49.4%, rss_bytes: +0.3% |
| cache_hit | improvement | completed: +5.2%, cpu_percent: -0.0%, duration_seconds: -4.7%, p50_ms: -7.6%, p95_ms: -7.9%, p99_ms: -14.3%, requests_per_second: +8.3%, rss_bytes: +0.3% |
| cache_hit | improvement | completed: +9.6%, cpu_percent: +0.3%, duration_seconds: -4.5%, p50_ms: -6.2%, p95_ms: -29.1%, p99_ms: -32.7%, requests_per_second: +15.0%, rss_bytes: +0.3% |
| cache_hit | improvement | completed: +18.8%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -15.6%, p95_ms: -27.4%, p99_ms: -25.3%, requests_per_second: +18.9%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +17.9%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -14.5%, p95_ms: -18.7%, p99_ms: -14.9%, requests_per_second: +18.0%, rss_bytes: +0.3% |
| thread | stable | completed: +4.9%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: +4.4%, p95_ms: -23.5%, p99_ms: -14.5%, requests_per_second: +5.0%, rss_bytes: +0.2% |
| thread | stable | completed: +21.7%, cpu_percent: +2.1%, duration_seconds: +0.0%, p50_ms: -10.0%, p95_ms: -31.4%, p99_ms: -25.0%, requests_per_second: +21.6%, rss_bytes: +0.2% |
| search | improvement | completed: +28.2%, cpu_percent: -3.2%, duration_seconds: +0.3%, p50_ms: -21.6%, p95_ms: -2.4%, p99_ms: -2.2%, requests_per_second: +27.6%, rss_bytes: +0.2% |
| search | stable | completed: +13.1%, cpu_percent: +2.8%, duration_seconds: +0.0%, p50_ms: -36.2%, p95_ms: -16.0%, p99_ms: -18.5%, requests_per_second: +13.4%, rss_bytes: +0.2% |
| cache_hit | improvement | completed: +48.2%, cpu_percent: +28.1%, duration_seconds: +4.8%, p50_ms: -28.3%, p95_ms: -13.0%, p99_ms: -18.2%, requests_per_second: +47.9%, rss_bytes: +0.2% |
| cache_hit | stable | completed: +6.7%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +0.5%, p95_ms: -18.1%, p99_ms: -32.1%, requests_per_second: +5.8%, rss_bytes: +0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.2% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -17.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -9.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.9% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -12.4% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -14.3% |
| sql-plan-readers | improvement | sql_execution_ms: -25.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -20.7% |
| sql-plan-readers | improvement | sql_execution_ms: -25.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -25.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -6.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -5.9% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -10.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.3% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -12.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -19.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.4% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.1% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -10.7% |
| sql-plan-functions | improvement | nested_statements: +0.0%, sql_execution_ms: -30.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -9.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -20.3% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -22.2% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +23.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -14.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -18.3% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -10.7%, messages_per_second: +12.0%, p50_ms: -9.8%, p95_ms: -14.2%, p99_ms: -8.7% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -10.3%, messages_per_second: +11.5%, p50_ms: -10.0%, p95_ms: -13.6%, p99_ms: -13.4% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.2%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: -0.4%, p95_ms: -0.4%, p99_ms: -4.3%, requests_per_second: +0.2%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.2%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +21.3%, p99_ms: +9.7%, requests_per_second: +0.9%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.6%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: -1.9%, p95_ms: +1.1%, p99_ms: +3.4%, requests_per_second: -0.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +8.4%, cpu_percent: -0.5%, duration_seconds: +5.0%, p50_ms: -2.6%, p95_ms: -3.2%, p99_ms: -5.1%, requests_per_second: +3.3%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -0.6%, cpu_percent: +0.0%, duration_seconds: -4.6%, p50_ms: -2.8%, p95_ms: -2.2%, p99_ms: +27.6%, requests_per_second: +2.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.8%, cpu_percent: +0.5%, duration_seconds: +0.2%, p50_ms: -4.0%, p95_ms: -5.9%, p99_ms: +1.0%, requests_per_second: +2.2%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +2.7%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -3.5%, p95_ms: -13.8%, p99_ms: -10.2%, requests_per_second: +2.6%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.0%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +0.4%, p95_ms: +1.0%, p99_ms: -5.4%, requests_per_second: -0.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -1.4%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: +0.9%, p99_ms: +15.6%, requests_per_second: -0.9%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.3%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -1.8%, p95_ms: +4.5%, p99_ms: +0.5%, requests_per_second: +2.2%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.8%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -1.5%, p95_ms: +0.3%, p99_ms: -5.8%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +3.8%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +0.4%, p95_ms: +13.1%, p99_ms: +42.3%, requests_per_second: +3.8%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +2.7%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -1.2%, p95_ms: -1.1%, p99_ms: +16.4%, requests_per_second: +2.8%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.5%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: -2.5%, p95_ms: -1.1%, p99_ms: +27.1%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -0.4%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +2.2%, p95_ms: +14.9%, p99_ms: +39.5%, requests_per_second: +1.4%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +1.0%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -0.2%, p95_ms: +0.5%, p99_ms: +28.5%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.5%, cpu_percent: -0.0%, duration_seconds: -4.7%, p50_ms: -1.9%, p95_ms: -1.3%, p99_ms: +8.5%, requests_per_second: +1.6%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -1.2%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: -2.2%, p95_ms: +17.4%, p99_ms: +49.1%, requests_per_second: +3.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +2.1%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -3.5%, p95_ms: +5.8%, p99_ms: +32.5%, requests_per_second: +2.1%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.2%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +1.9%, p95_ms: +2.7%, p99_ms: +3.1%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.8%, cpu_percent: +1.5%, duration_seconds: -0.0%, p50_ms: +1.4%, p95_ms: +3.7%, p99_ms: +6.2%, requests_per_second: -2.9%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +2.8%, cpu_percent: -1.5%, duration_seconds: +4.8%, p50_ms: +0.2%, p95_ms: +3.8%, p99_ms: +22.6%, requests_per_second: +0.4%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.7%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: -6.0%, p95_ms: +8.5%, p99_ms: +7.5%, requests_per_second: -0.6%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.3%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: +0.1%, p95_ms: +1.8%, p99_ms: +1.3%, requests_per_second: -0.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.4%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -2.0%, p95_ms: -1.8%, p99_ms: -3.2%, requests_per_second: +2.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -3.9%, cpu_percent: +0.1%, duration_seconds: -4.5%, p50_ms: -0.1%, p95_ms: -0.5%, p99_ms: +4.5%, requests_per_second: +0.9%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +0.5%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: -2.3%, p95_ms: +1.5%, p99_ms: +14.3%, requests_per_second: +0.6%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.1%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -1.1%, p95_ms: -1.5%, p99_ms: +2.0%, requests_per_second: +1.2%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.8%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: +7.6%, p95_ms: +3.1%, p99_ms: +7.0%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -4.2%, cpu_percent: +0.2%, duration_seconds: -4.4%, p50_ms: +35.3%, p95_ms: -0.4%, p99_ms: +14.4%, requests_per_second: +0.1%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.2%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -6.6%, p95_ms: -4.0%, p99_ms: +0.4%, requests_per_second: +1.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -5.2%, cpu_percent: +1.5%, duration_seconds: +0.0%, p50_ms: +1.8%, p95_ms: -14.2%, p99_ms: -13.6%, requests_per_second: -5.1%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +49.8%, cpu_percent: +77.0%, duration_seconds: +4.5%, p50_ms: -47.1%, p95_ms: -52.6%, p99_ms: -57.6%, requests_per_second: +49.7%, rss_bytes: +0.1% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: +0.1%, cpu_percent: +0.1%, duration_seconds: -0.2%, p50_ms: +33.0%, p95_ms: -4.5%, p99_ms: -10.4%, requests_per_second: -0.4%, rss_bytes: +0.1% |
| thread | workers=4 | 2 | 50 | improvement | completed: +45.6%, cpu_percent: +95.0%, duration_seconds: +4.8%, p50_ms: -43.5%, p95_ms: +9.8%, p99_ms: -0.1%, requests_per_second: +39.8%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | improvement | completed: +46.6%, cpu_percent: +94.5%, duration_seconds: +4.8%, p50_ms: -49.0%, p95_ms: -4.3%, p99_ms: -6.7%, requests_per_second: +40.0%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +23.0%, cpu_percent: +79.3%, duration_seconds: +0.2%, p50_ms: -40.8%, p95_ms: +16.9%, p99_ms: +22.4%, requests_per_second: +22.8%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +15.7%, cpu_percent: +85.3%, duration_seconds: +0.2%, p50_ms: -43.5%, p95_ms: +9.6%, p99_ms: +10.6%, requests_per_second: +15.4%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -8.5%, cpu_percent: +10.4%, duration_seconds: +0.2%, p50_ms: +36.3%, p95_ms: +146.2%, p99_ms: +197.3%, requests_per_second: -8.6%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +39.1%, cpu_percent: +95.0%, duration_seconds: +0.3%, p50_ms: -38.6%, p95_ms: +12.3%, p99_ms: +0.3%, requests_per_second: +38.3%, rss_bytes: +64.7% |
| thread | workers=4 | 2 | 50 | improvement | completed: +43.7%, cpu_percent: +93.7%, duration_seconds: +4.8%, p50_ms: -37.0%, p95_ms: +7.1%, p99_ms: -19.3%, requests_per_second: +37.3%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +38.8%, cpu_percent: +94.5%, duration_seconds: +0.1%, p50_ms: -32.3%, p95_ms: -7.1%, p99_ms: +3.6%, requests_per_second: +38.5%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | possible-regression | completed: +26.5%, cpu_percent: +80.9%, duration_seconds: +0.4%, p50_ms: -41.2%, p95_ms: +3.4%, p99_ms: +14.3%, requests_per_second: +25.7%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | stable | completed: +10.0%, cpu_percent: +87.4%, duration_seconds: +0.1%, p50_ms: -42.5%, p95_ms: -7.7%, p99_ms: -5.7%, requests_per_second: +10.0%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +36.3%, cpu_percent: +95.5%, duration_seconds: +4.8%, p50_ms: -26.3%, p95_ms: +15.0%, p99_ms: +10.2%, requests_per_second: +36.1%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +37.6%, cpu_percent: +94.8%, duration_seconds: +0.1%, p50_ms: -17.5%, p95_ms: +9.0%, p99_ms: -11.9%, requests_per_second: +36.1%, rss_bytes: +64.3% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38629924024)
