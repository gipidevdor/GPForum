# GPForum continuous performance evidence

Commit: `3e1a0af78cee9cb79704f4730b7b7d933bc10874` · mode: **main** · status: **ok**
Run: 38164142546 / attempt 1 · 2026-10-11T18:31:30.213620+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"ee7d3093ffc5cd7d0cc2f564417c6ad7f1e113aa0c1316b1b59386e9b

Baseline: Compatible baseline. 2237bb6d6f0f3a784c29924f74535c7bac0bdb01

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 272.804 | 3.642 | 3.771 | 4.200 | 99.453 / 369.543 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 524.594 | 18.361 | 20.026 | 27.192 | 199.808 / 369.555 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 486.298 | 96.734 | 110.590 | 175.106 | 201.521 / 371.238 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1152.177 | 0.848 | 0.961 | 1.049 | 99.976 / 369.645 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2196.854 | 4.356 | 5.136 | 5.958 | 198.780 / 369.645 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2146.580 | 22.156 | 31.088 | 36.939 | 199.652 / 370.359 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2243.518 | 43.685 | 47.200 | 66.324 | 201.557 / 371.598 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 111.402 | 8.770 | 10.097 | 10.306 | 86.989 / 371.957 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 199.071 | 48.317 | 60.567 | 76.047 | 173.957 / 372.352 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 186.613 | 252.562 | 422.091 | 499.632 | 174.184 / 374.121 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 834.642 | 1.157 | 1.371 | 1.451 | 99.442 / 374.121 | possible-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1630.157 | 5.907 | 7.013 | 8.240 | 198.541 / 374.121 | possible-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1740.298 | 28.416 | 30.160 | 38.347 | 200.779 / 374.121 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 845.371 | 1.180 | 1.245 | 1.456 | 99.877 / 374.152 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1667.740 | 5.879 | 6.548 | 7.665 | 199.402 / 374.152 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1667.509 | 29.354 | 30.544 | 41.962 | 201.731 / 374.176 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 836.196 | 1.184 | 1.252 | 1.783 | 99.415 / 374.238 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1678.342 | 5.941 | 6.155 | 6.627 | 198.782 / 374.301 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1671.402 | 29.281 | 32.374 | 40.308 | 199.760 / 374.887 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1612.530 | 60.109 | 66.630 | 98.723 | 201.636 / 378.047 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 66.964 | 14.857 | 15.866 | 17.659 | 68.122 / 378.723 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 119.390 | 81.686 | 96.821 | 133.843 | 135.197 / 378.723 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 103.851 | 416.699 | 698.725 | 781.819 | 134.322 / 378.723 | possible-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.762 | 844.110 | 1587.745 | 1676.932 | 134.343 / 378.723 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 863.231 | 1.149 | 1.209 | 1.292 | 99.417 / 378.723 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1728.612 | 5.753 | 6.025 | 6.810 | 199.776 / 378.723 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1745.905 | 28.359 | 30.695 | 35.874 | 201.210 / 378.723 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1696.780 | 57.531 | 62.333 | 91.396 | 199.251 / 378.723 | stable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1311.372 | 6.375 | 10.937 | 12.935 | 24.774 / 378.723 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 934.772 | 9.442 | 17.275 | 20.262 | 34.470 / 379.012 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2407.349 | 21.566 | 35.737 | 45.664 | 386.988 / 615.512 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2417.355 | 39.745 | 66.757 | 75.827 | 390.618 / 619.488 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 151.455 | 237.780 | 736.225 | 911.068 | 238.943 / 621.105 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 137.134 | 501.925 | 1227.397 | 1421.617 | 240.946 / 622.164 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2137.562 | 20.979 | 40.341 | 44.216 | 304.584 / 622.164 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2415.729 | 38.997 | 72.142 | 80.327 | 387.998 / 622.164 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 269.750 | 3.646 | 4.115 | 4.654 | 99.877 / 370.797 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 530.259 | 18.464 | 23.502 | 25.827 | 199.666 / 370.797 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 523.446 | 91.264 | 105.045 | 166.347 | 201.249 / 372.578 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1158.555 | 0.850 | 0.911 | 0.947 | 99.486 / 370.777 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2305.733 | 4.310 | 4.894 | 5.590 | 199.317 / 370.777 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2275.747 | 21.152 | 25.514 | 30.666 | 199.325 / 371.535 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2116.596 | 44.379 | 52.376 | 67.671 | 199.280 / 372.879 | possible-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 116.362 | 8.448 | 9.255 | 9.597 | 86.546 / 373.133 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 213.731 | 44.883 | 57.001 | 83.353 | 174.455 / 373.641 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 194.582 | 244.874 | 395.273 | 465.801 | 174.071 / 375.398 | possible-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 885.518 | 1.111 | 1.240 | 1.327 | 99.487 / 375.398 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1682.477 | 5.742 | 6.628 | 6.769 | 199.282 / 375.398 | possible-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1656.798 | 29.074 | 33.413 | 38.253 | 199.337 / 375.398 | possible-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 860.914 | 1.142 | 1.286 | 1.431 | 99.468 / 375.477 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1587.475 | 6.687 | 8.686 | 9.580 | 199.183 / 375.555 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1555.933 | 33.700 | 42.758 | 51.053 | 201.384 / 375.555 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 827.245 | 1.200 | 1.311 | 1.469 | 98.951 / 375.680 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1627.018 | 6.039 | 6.895 | 9.768 | 199.263 / 375.680 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1629.563 | 30.683 | 36.466 | 49.565 | 200.663 / 376.180 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1567.734 | 61.802 | 66.637 | 101.787 | 199.851 / 379.500 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 67.602 | 14.611 | 16.038 | 19.380 | 67.268 / 379.883 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 123.822 | 78.899 | 89.023 | 142.123 | 133.713 / 380.117 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.193 | 370.750 | 678.202 | 764.100 | 132.813 / 380.117 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.273 | 809.511 | 1526.052 | 1648.611 | 133.290 / 380.117 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 852.932 | 1.114 | 1.342 | 1.392 | 99.561 / 380.117 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1707.495 | 5.792 | 6.336 | 7.735 | 199.324 / 380.117 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1672.533 | 28.473 | 33.400 | 37.819 | 199.819 / 380.117 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1687.610 | 58.968 | 71.357 | 98.857 | 200.817 / 380.117 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2419.767 | 21.782 | 36.341 | 45.265 | 385.651 / 617.758 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2380.486 | 40.298 | 63.772 | 79.203 | 385.547 / 621.805 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 155.595 | 210.539 | 747.777 | 808.610 | 236.280 / 622.992 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 134.315 | 501.338 | 1141.172 | 1292.234 | 238.390 / 624.594 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2078.038 | 24.570 | 65.330 | 78.143 | 300.331 / 625.016 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2518.080 | 41.017 | 62.250 | 72.450 | 390.196 / 625.016 | confirmed-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.502 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.033 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.501 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.536 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.092 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.548 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.012 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.108 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.029 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.463 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.561 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.285 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.366 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.077 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.046 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.449 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.460 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.559 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.453 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.568 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.303 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.416 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.919 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.289 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.188 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.161 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.191 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.016 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.097 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.073 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.083 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 675.883 | 146.573 | 162.180 | 162.929 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1136.777 | 172.523 | 199.960 | 200.842 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: +0.9%, cpu_percent: -1.0%, duration_seconds: +0.1%, p50_ms: +1.0%, p95_ms: +1.6%, p99_ms: +4.3%, requests_per_second: -1.1%, rss_bytes: -0.0% |
| cache_miss | stable | completed: -6.7%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +1.5%, p95_ms: +6.9%, p99_ms: +17.3%, requests_per_second: -3.2%, rss_bytes: -0.0% |
| cache_miss | possible-regression | completed: -11.0%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +9.2%, p95_ms: +17.6%, p99_ms: +10.1%, requests_per_second: -11.0%, rss_bytes: -0.0% |
| health_live | stable | completed: -0.4%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: +4.3%, p99_ms: -9.1%, requests_per_second: -0.4%, rss_bytes: -0.0% |
| health_live | stable | completed: -1.1%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: -10.7%, p95_ms: -2.9%, p99_ms: +7.4%, requests_per_second: -4.3%, rss_bytes: -0.0% |
| health_live | possible-regression | completed: -8.5%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: +5.1%, p95_ms: +42.7%, p99_ms: +45.2%, requests_per_second: -8.5%, rss_bytes: -0.0% |
| health_live | stable | completed: -2.2%, cpu_percent: +1.1%, duration_seconds: +0.0%, p50_ms: +2.5%, p95_ms: +1.7%, p99_ms: +5.7%, requests_per_second: -2.2%, rss_bytes: -0.0% |
| home | stable | completed: -6.7%, cpu_percent: +1.6%, duration_seconds: +0.1%, p50_ms: +5.7%, p95_ms: +12.5%, p99_ms: +9.5%, requests_per_second: -6.7%, rss_bytes: +0.0% |
| home | confirmed-regression | completed: -8.1%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +13.8%, p95_ms: +11.8%, p99_ms: +26.2%, requests_per_second: -12.4%, rss_bytes: -0.0% |
| home | confirmed-regression | completed: -13.8%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +19.5%, p95_ms: +27.3%, p99_ms: +23.1%, requests_per_second: -13.8%, rss_bytes: -0.0% |
| categories | possible-regression | completed: -5.2%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +2.9%, p95_ms: +16.2%, p99_ms: +16.9%, requests_per_second: -5.2%, rss_bytes: -0.0% |
| categories | possible-regression | completed: -3.7%, cpu_percent: -0.2%, duration_seconds: +4.9%, p50_ms: +4.5%, p95_ms: +15.0%, p99_ms: +23.2%, requests_per_second: -4.4%, rss_bytes: -0.0% |
| categories | stable | completed: -1.1%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +2.7%, p95_ms: -1.4%, p99_ms: -3.0%, requests_per_second: -1.1%, rss_bytes: -0.0% |
| category | stable | completed: +1.3%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -1.3%, p95_ms: +0.2%, p99_ms: +11.6%, requests_per_second: +1.3%, rss_bytes: -0.0% |
| category | stable | completed: -2.6%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +1.3%, p95_ms: +8.5%, p99_ms: +15.5%, requests_per_second: -2.6%, rss_bytes: -0.0% |
| category | stable | completed: -2.9%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +2.8%, p95_ms: +2.6%, p99_ms: -2.4%, requests_per_second: -2.9%, rss_bytes: -0.0% |
| thread | stable | completed: -1.7%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +2.7%, p95_ms: +2.1%, p99_ms: +23.4%, requests_per_second: -1.7%, rss_bytes: -0.0% |
| thread | stable | completed: -5.9%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +1.7%, p95_ms: +1.8%, p99_ms: +1.1%, requests_per_second: -1.3%, rss_bytes: -0.0% |
| thread | stable | completed: -2.7%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +0.7%, p95_ms: +5.9%, p99_ms: +6.3%, requests_per_second: -2.9%, rss_bytes: -0.0% |
| thread | stable | completed: -4.5%, cpu_percent: +1.4%, duration_seconds: -0.0%, p50_ms: +5.0%, p95_ms: +11.0%, p99_ms: +5.9%, requests_per_second: -4.5%, rss_bytes: -0.0% |
| search | confirmed-regression | completed: -12.4%, cpu_percent: +4.5%, duration_seconds: -0.1%, p50_ms: +14.4%, p95_ms: +17.4%, p99_ms: +22.9%, requests_per_second: -12.4%, rss_bytes: -0.0% |
| search | confirmed-regression | completed: -17.3%, cpu_percent: +4.6%, duration_seconds: -4.7%, p50_ms: +18.5%, p95_ms: +25.7%, p99_ms: +19.8%, requests_per_second: -14.1%, rss_bytes: -0.0% |
| search | possible-regression | completed: -16.8%, cpu_percent: +3.7%, duration_seconds: -0.1%, p50_ms: +15.5%, p95_ms: +13.4%, p99_ms: +10.8%, requests_per_second: -16.7%, rss_bytes: -0.0% |
| search | confirmed-regression | completed: +0.0%, cpu_percent: +3.0%, duration_seconds: -0.0%, p50_ms: +20.2%, p95_ms: +20.6%, p99_ms: +22.0%, requests_per_second: +0.0%, rss_bytes: -0.1% |
| cache_hit | stable | completed: +4.5%, cpu_percent: -0.0%, duration_seconds: +4.8%, p50_ms: +1.0%, p95_ms: +0.2%, p99_ms: +1.3%, requests_per_second: -0.5%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -3.0%, cpu_percent: +0.2%, duration_seconds: -4.7%, p50_ms: +1.1%, p95_ms: -6.8%, p99_ms: -16.3%, requests_per_second: +0.8%, rss_bytes: -0.1% |
| cache_hit | improvement | completed: -1.1%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +1.8%, p95_ms: +6.9%, p99_ms: -11.3%, requests_per_second: -1.1%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -4.2%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +4.3%, p95_ms: +7.1%, p99_ms: +3.6%, requests_per_second: -4.1%, rss_bytes: -0.1% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -4.7%, duration_seconds: +10.1%, p50_ms: +6.6%, p95_ms: +10.4%, p99_ms: +9.9%, requests_per_second: -8.9%, rss_bytes: -0.1% |
| thread | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -6.0%, duration_seconds: +7.0%, p50_ms: +10.7%, p95_ms: -4.0%, p99_ms: -13.8%, requests_per_second: -6.2%, rss_bytes: -0.1% |
| thread | stable | completed: -4.1%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -2.3%, p95_ms: -5.8%, p99_ms: -8.3%, requests_per_second: -4.1%, rss_bytes: -0.0% |
| thread | confirmed-regression | completed: -3.9%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +0.4%, p95_ms: +23.9%, p99_ms: +4.8%, requests_per_second: -3.6%, rss_bytes: -0.0% |
| search | stable | completed: -5.0%, cpu_percent: +3.3%, duration_seconds: -0.1%, p50_ms: -0.7%, p95_ms: +6.3%, p99_ms: +7.3%, requests_per_second: -5.0%, rss_bytes: -0.0% |
| search | stable | completed: -9.5%, cpu_percent: +2.7%, duration_seconds: -0.2%, p50_ms: +13.9%, p95_ms: +8.6%, p99_ms: +20.8%, requests_per_second: -9.3%, rss_bytes: +0.0% |
| cache_hit | improvement | completed: +24.7%, cpu_percent: +40.8%, duration_seconds: +0.0%, p50_ms: -39.5%, p95_ms: -1.0%, p99_ms: -27.9%, requests_per_second: +24.6%, rss_bytes: +0.0% |
| cache_hit | possible-regression | completed: -6.7%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +4.4%, p95_ms: +55.7%, p99_ms: +21.6%, requests_per_second: -7.1%, rss_bytes: +0.0% |
| cache_miss | possible-regression | completed: -2.9%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +2.0%, p95_ms: +11.5%, p99_ms: +14.7%, requests_per_second: -2.9%, rss_bytes: +0.0% |
| cache_miss | possible-regression | completed: -0.2%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +2.0%, p95_ms: +25.6%, p99_ms: -18.7%, requests_per_second: -2.5%, rss_bytes: +0.0% |
| cache_miss | stable | completed: -2.1%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +0.9%, p95_ms: +11.7%, p99_ms: +3.8%, requests_per_second: -2.2%, rss_bytes: +0.0% |
| health_live | stable | completed: -0.8%, cpu_percent: -0.0%, duration_seconds: +5.0%, p50_ms: +2.3%, p95_ms: +0.2%, p99_ms: -3.9%, requests_per_second: -1.7%, rss_bytes: +0.0% |
| health_live | stable | completed: -1.7%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +0.9%, p95_ms: +10.1%, p99_ms: +4.9%, requests_per_second: -0.8%, rss_bytes: +0.0% |
| health_live | possible-regression | completed: -3.2%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +1.2%, p95_ms: +15.0%, p99_ms: +21.1%, requests_per_second: -3.3%, rss_bytes: +0.0% |
| health_live | possible-regression | completed: -8.5%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +3.9%, p95_ms: +19.5%, p99_ms: +6.3%, requests_per_second: -8.7%, rss_bytes: +0.0% |
| home | stable | completed: -2.1%, cpu_percent: +1.1%, duration_seconds: +0.1%, p50_ms: +1.5%, p95_ms: +6.5%, p99_ms: -2.5%, requests_per_second: -2.2%, rss_bytes: -0.0% |
| home | stable | completed: -5.1%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +5.8%, p95_ms: +10.5%, p99_ms: +9.4%, requests_per_second: -5.2%, rss_bytes: +0.0% |
| home | possible-regression | completed: -12.0%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: +14.5%, p95_ms: +15.5%, p99_ms: +13.9%, requests_per_second: -12.0%, rss_bytes: +0.0% |
| categories | stable | completed: +0.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +4.1%, p99_ms: +7.0%, requests_per_second: +0.2%, rss_bytes: +0.0% |
| categories | possible-regression | completed: +1.5%, cpu_percent: -0.0%, duration_seconds: +4.8%, p50_ms: +0.6%, p95_ms: +11.0%, p99_ms: -8.2%, requests_per_second: -3.2%, rss_bytes: +0.0% |
| categories | possible-regression | completed: -4.9%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +3.6%, p95_ms: +14.4%, p99_ms: +2.4%, requests_per_second: -5.0%, rss_bytes: +0.0% |
| category | stable | completed: +1.3%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -3.4%, p95_ms: +4.6%, p99_ms: -2.8%, requests_per_second: +1.4%, rss_bytes: +0.0% |
| category | confirmed-regression | completed: -7.5%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +16.0%, p95_ms: +42.5%, p99_ms: +6.6%, requests_per_second: -7.5%, rss_bytes: +0.1% |
| category | possible-regression | completed: -10.7%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +17.3%, p95_ms: +43.2%, p99_ms: +26.5%, requests_per_second: -10.7%, rss_bytes: +0.0% |
| thread | possible-regression | completed: -4.1%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +3.3%, p95_ms: +8.5%, p99_ms: +18.1%, requests_per_second: -4.3%, rss_bytes: +0.0% |
| thread | stable | completed: -4.3%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +3.6%, p95_ms: +11.3%, p99_ms: +11.5%, requests_per_second: -4.3%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: -5.7%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: +6.9%, p95_ms: +19.7%, p99_ms: +19.7%, requests_per_second: -5.5%, rss_bytes: +0.0% |
| thread | stable | completed: -6.1%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +5.3%, p95_ms: +7.7%, p99_ms: +4.7%, requests_per_second: -6.2%, rss_bytes: +0.0% |
| search | possible-regression | completed: -6.0%, cpu_percent: +1.7%, duration_seconds: +0.1%, p50_ms: +11.9%, p95_ms: +11.1%, p99_ms: +30.2%, requests_per_second: -10.4%, rss_bytes: -0.0% |
| search | possible-regression | completed: -8.8%, cpu_percent: +1.9%, duration_seconds: -0.0%, p50_ms: +10.3%, p95_ms: -2.0%, p99_ms: +4.5%, requests_per_second: -8.8%, rss_bytes: +0.0% |
| search | stable | completed: -0.4%, cpu_percent: +1.0%, duration_seconds: -0.0%, p50_ms: +6.8%, p95_ms: +6.0%, p99_ms: +8.2%, requests_per_second: -0.4%, rss_bytes: +0.0% |
| search | confirmed-regression | completed: +0.0%, cpu_percent: +2.2%, duration_seconds: -0.1%, p50_ms: +13.4%, p95_ms: +14.4%, p99_ms: +18.5%, requests_per_second: -0.1%, rss_bytes: +0.0% |
| cache_hit | possible-regression | completed: +0.9%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -2.2%, p95_ms: +11.5%, p99_ms: +6.7%, requests_per_second: -2.0%, rss_bytes: +0.0% |
| cache_hit | stable | completed: -3.6%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +3.0%, p95_ms: +7.2%, p99_ms: +4.4%, requests_per_second: -3.2%, rss_bytes: +0.0% |
| cache_hit | confirmed-regression | completed: -6.3%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: +2.3%, p95_ms: +17.3%, p99_ms: +5.9%, requests_per_second: -6.2%, rss_bytes: +0.0% |
| cache_hit | stable | completed: -2.1%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +4.5%, p95_ms: -5.8%, p99_ms: +7.0%, requests_per_second: -2.2%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: -3.5%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +12.3%, p95_ms: +15.8%, p99_ms: +23.4%, requests_per_second: -3.4%, rss_bytes: +0.1% |
| thread | stable | completed: -4.9%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +3.7%, p95_ms: +16.5%, p99_ms: +3.9%, requests_per_second: -4.8%, rss_bytes: +0.1% |
| search | possible-regression | completed: -0.9%, cpu_percent: +0.7%, duration_seconds: +0.1%, p50_ms: -10.9%, p95_ms: +26.1%, p99_ms: -5.8%, requests_per_second: -0.9%, rss_bytes: +0.1% |
| search | stable | completed: -8.8%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +11.6%, p95_ms: -16.3%, p99_ms: -17.5%, requests_per_second: -8.5%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: +131.4%, cpu_percent: +152.4%, duration_seconds: +0.1%, p50_ms: -54.4%, p95_ms: +6.2%, p99_ms: -36.6%, requests_per_second: +131.2%, rss_bytes: +0.0% |
| cache_hit | confirmed-regression | completed: -2.1%, cpu_percent: +0.8%, duration_seconds: -0.2%, p50_ms: +35.1%, p95_ms: -6.1%, p99_ms: -20.6%, requests_per_second: -2.0%, rss_bytes: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -16.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.3% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.6% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -9.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +9.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +9.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +16.2% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +29.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -8.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.9% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +32.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -15.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +18.6% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +0.3%, messages_per_second: -0.3%, p50_ms: -0.1%, p95_ms: +4.6%, p99_ms: +1.1% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +1.1%, messages_per_second: -1.1%, p50_ms: +0.7%, p95_ms: +7.0%, p99_ms: +6.5% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -3.1%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +0.1%, p95_ms: +9.1%, p99_ms: +10.8%, requests_per_second: -1.1%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +3.4%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: +17.4%, p99_ms: -5.0%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +7.6%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -5.7%, p95_ms: -5.0%, p99_ms: -5.0%, requests_per_second: +7.6%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.5%, cpu_percent: -0.5%, duration_seconds: +5.0%, p50_ms: +0.2%, p95_ms: -5.2%, p99_ms: -9.7%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.1%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: -4.7%, p99_ms: -6.2%, requests_per_second: +5.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +6.1%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -4.5%, p95_ms: -17.9%, p99_ms: -17.0%, requests_per_second: +6.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -5.5%, cpu_percent: -1.1%, duration_seconds: +0.0%, p50_ms: +1.6%, p95_ms: +11.0%, p99_ms: +2.0%, requests_per_second: -5.7%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.5%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -3.7%, p95_ms: -8.3%, p99_ms: -6.9%, requests_per_second: +4.5%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.4%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -7.1%, p95_ms: -5.9%, p99_ms: +9.6%, requests_per_second: +7.4%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +4.3%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -3.0%, p95_ms: -6.4%, p99_ms: -6.8%, requests_per_second: +4.3%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +6.1%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -4.0%, p95_ms: -9.6%, p99_ms: -8.5%, requests_per_second: +6.1%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +7.5%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -2.8%, p95_ms: -5.5%, p99_ms: -17.9%, requests_per_second: +3.2%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -4.7%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: +2.3%, p95_ms: +10.8%, p99_ms: -0.2%, requests_per_second: -4.8%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.8%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: -3.2%, p95_ms: +3.3%, p99_ms: -1.7%, requests_per_second: +1.8%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -4.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +13.7%, p95_ms: +32.7%, p99_ms: +25.0%, requests_per_second: -4.8%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -6.7%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +14.8%, p95_ms: +40.0%, p99_ms: +21.7%, requests_per_second: -6.7%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.8%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +1.4%, p95_ms: +4.7%, p99_ms: -17.6%, requests_per_second: -1.1%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +1.7%, cpu_percent: +0.2%, duration_seconds: +4.9%, p50_ms: +1.6%, p95_ms: +12.0%, p99_ms: +47.4%, requests_per_second: -3.1%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -2.6%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +4.8%, p95_ms: +12.6%, p99_ms: +23.0%, requests_per_second: -2.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -2.8%, cpu_percent: -0.9%, duration_seconds: +0.0%, p50_ms: +2.8%, p95_ms: +0.0%, p99_ms: +3.1%, requests_per_second: -2.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +6.0%, cpu_percent: -1.3%, duration_seconds: +0.1%, p50_ms: -1.7%, p95_ms: +1.1%, p99_ms: +9.7%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +3.8%, cpu_percent: -1.1%, duration_seconds: +0.1%, p50_ms: -3.4%, p95_ms: -8.1%, p99_ms: +6.2%, requests_per_second: +3.7%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +19.7%, cpu_percent: -1.1%, duration_seconds: +0.0%, p50_ms: -11.0%, p95_ms: -2.9%, p99_ms: -2.3%, requests_per_second: +19.6%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: -4.1%, p95_ms: -3.9%, p99_ms: -1.7%, requests_per_second: -0.5%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -3.1%, cpu_percent: +0.1%, duration_seconds: -4.7%, p50_ms: -3.0%, p95_ms: +11.0%, p99_ms: +7.7%, requests_per_second: -1.2%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.8%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +0.7%, p95_ms: +5.2%, p99_ms: +13.6%, requests_per_second: -1.2%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -4.3%, cpu_percent: -0.7%, duration_seconds: -0.1%, p50_ms: +0.4%, p95_ms: +8.8%, p99_ms: +5.4%, requests_per_second: -4.2%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -0.4%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: +2.5%, p95_ms: +14.5%, p99_ms: +8.2%, requests_per_second: -0.5%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.5%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +1.0%, p95_ms: +1.7%, p99_ms: -0.9%, requests_per_second: +0.5%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.5%, cpu_percent: -1.3%, duration_seconds: +0.0%, p50_ms: +1.4%, p95_ms: -4.5%, p99_ms: +4.5%, requests_per_second: -1.5%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.6%, cpu_percent: -1.1%, duration_seconds: +0.0%, p50_ms: -11.5%, p95_ms: +1.6%, p99_ms: -11.2%, requests_per_second: +2.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -2.2%, cpu_percent: -1.1%, duration_seconds: -0.1%, p50_ms: -0.1%, p95_ms: -7.0%, p99_ms: -9.1%, requests_per_second: -2.1%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -2.8%, cpu_percent: -1.4%, duration_seconds: -0.1%, p50_ms: +17.1%, p95_ms: +61.9%, p99_ms: +76.7%, requests_per_second: -2.8%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +3.7%, cpu_percent: +0.6%, duration_seconds: -0.2%, p50_ms: +5.2%, p95_ms: -13.7%, p99_ms: -9.8%, requests_per_second: +4.2%, rss_bytes: +0.5% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +44.0%, cpu_percent: +93.7%, duration_seconds: +0.0%, p50_ms: -26.3%, p95_ms: +10.4%, p99_ms: +13.3%, requests_per_second: +44.0%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | improvement | completed: +50.0%, cpu_percent: +93.7%, duration_seconds: +0.1%, p50_ms: -33.9%, p95_ms: +0.2%, p99_ms: -23.2%, requests_per_second: +49.9%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | possible-regression | completed: +46.6%, cpu_percent: +77.9%, duration_seconds: +0.3%, p50_ms: -42.9%, p95_ms: +5.4%, p99_ms: +16.5%, requests_per_second: +45.8%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +38.0%, cpu_percent: +79.4%, duration_seconds: +0.4%, p50_ms: -40.5%, p95_ms: -22.7%, p99_ms: -15.2%, requests_per_second: +37.5%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: +22.5%, cpu_percent: +51.4%, duration_seconds: +0.1%, p50_ms: -26.0%, p95_ms: +31.4%, p99_ms: +23.3%, requests_per_second: +22.4%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +43.1%, cpu_percent: +94.7%, duration_seconds: +0.1%, p50_ms: -32.2%, p95_ms: +15.7%, p99_ms: -12.1%, requests_per_second: +42.4%, rss_bytes: +64.3% |
| thread | workers=4 | 2 | 50 | improvement | completed: +48.6%, cpu_percent: +92.2%, duration_seconds: +0.1%, p50_ms: -29.0%, p95_ms: -0.3%, p99_ms: -8.7%, requests_per_second: +48.5%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | improvement | completed: +51.9%, cpu_percent: +92.9%, duration_seconds: +0.1%, p50_ms: -34.8%, p95_ms: -4.3%, p99_ms: -22.2%, requests_per_second: +51.8%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | improvement | completed: +25.7%, cpu_percent: +77.9%, duration_seconds: +0.3%, p50_ms: -43.2%, p95_ms: +10.3%, p99_ms: +5.8%, requests_per_second: +25.3%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +35.7%, cpu_percent: +78.9%, duration_seconds: +0.3%, p50_ms: -38.1%, p95_ms: -25.2%, p99_ms: -21.6%, requests_per_second: +35.3%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: +24.4%, cpu_percent: +50.3%, duration_seconds: +0.1%, p50_ms: -13.7%, p95_ms: +95.6%, p99_ms: +106.6%, requests_per_second: +24.2%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.1%, cpu_percent: +94.3%, duration_seconds: -0.1%, p50_ms: -30.4%, p95_ms: -12.8%, p99_ms: -26.7%, requests_per_second: +49.2%, rss_bytes: +64.4% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38164142546)
