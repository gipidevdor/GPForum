# GPForum continuous performance evidence

Commit: `4d616825d05990e1d868eab74f1ae0ae29bb55fd` · mode: **main** · status: **ok**
Run: 38784936557 / attempt 1 · 2026-10-15T18:21:58.588011+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. de3ed5128b1f36a37c605a6417ca716bdca4047a

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 233.738 | 4.245 | 4.386 | 4.922 | 99.827 / 378.453 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 452.101 | 21.402 | 28.729 | 33.827 | 199.924 / 378.512 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 448.128 | 109.685 | 142.916 | 197.237 | 201.394 / 380.324 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1359.516 | 0.724 | 0.794 | 0.995 | 99.465 / 378.508 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2711.781 | 3.666 | 3.843 | 4.370 | 199.284 / 378.508 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2756.754 | 17.765 | 19.656 | 21.891 | 200.711 / 379.152 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2709.946 | 36.837 | 41.245 | 55.790 | 199.891 / 380.492 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 96.635 | 10.127 | 11.996 | 13.154 | 85.499 / 380.805 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 169.257 | 57.953 | 78.459 | 108.768 | 171.894 / 381.629 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 161.494 | 286.922 | 519.636 | 593.769 | 171.359 / 383.938 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 993.643 | 0.993 | 1.058 | 1.130 | 99.552 / 383.938 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1950.586 | 4.872 | 6.425 | 6.960 | 198.939 / 383.938 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1977.332 | 25.033 | 26.940 | 32.601 | 200.105 / 383.938 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 972.187 | 1.015 | 1.096 | 1.139 | 99.567 / 383.973 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1889.565 | 5.274 | 5.653 | 7.568 | 199.417 / 383.973 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1933.440 | 25.254 | 29.566 | 38.394 | 201.024 / 383.973 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 939.291 | 1.046 | 1.128 | 1.304 | 99.448 / 384.098 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1875.695 | 5.244 | 6.568 | 9.944 | 199.659 / 384.098 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1935.491 | 25.902 | 26.734 | 31.479 | 199.889 / 384.098 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1868.735 | 51.477 | 58.095 | 84.896 | 201.326 / 386.891 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 77.970 | 12.670 | 13.764 | 14.471 | 63.683 / 387.449 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 138.336 | 70.554 | 91.253 | 130.315 | 128.747 / 387.664 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 111.826 | 386.894 | 710.806 | 796.118 | 131.849 / 387.664 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.763 | 751.980 | 1411.062 | 1516.779 | 129.457 / 387.664 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 980.077 | 1.006 | 1.077 | 1.425 | 100.014 / 387.664 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1961.490 | 5.063 | 5.303 | 7.035 | 199.455 / 387.664 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1990.868 | 25.186 | 26.778 | 32.590 | 200.823 / 387.664 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1917.189 | 50.449 | 56.101 | 81.816 | 199.720 / 387.664 | stable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1509.367 | 5.860 | 9.571 | 11.075 | 28.494 / 387.664 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1025.116 | 9.041 | 13.580 | 15.827 | 35.419 / 387.945 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2287.091 | 25.420 | 36.140 | 43.588 | 299.233 / 630.418 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2619.891 | 36.720 | 67.385 | 82.946 | 387.581 / 634.992 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 176.500 | 234.653 | 738.481 | 909.505 | 224.522 / 636.316 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 148.396 | 416.700 | 1419.523 | 1421.330 | 236.855 / 637.297 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2029.666 | 24.476 | 49.106 | 52.897 | 213.273 / 637.555 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2728.501 | 38.082 | 55.935 | 61.174 | 382.430 / 637.918 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 235.794 | 4.183 | 4.384 | 5.627 | 100.432 / 379.539 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 468.309 | 21.516 | 27.009 | 37.360 | 199.915 / 379.609 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 455.114 | 106.052 | 127.250 | 196.623 | 200.328 / 381.473 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1338.449 | 0.714 | 0.793 | 0.826 | 98.999 / 379.543 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2665.995 | 4.157 | 4.603 | 5.309 | 198.905 / 379.543 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2712.982 | 18.315 | 19.289 | 25.262 | 199.306 / 380.273 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2653.568 | 36.511 | 39.606 | 57.933 | 199.739 / 381.605 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 94.983 | 10.268 | 11.781 | 12.966 | 85.585 / 382.227 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 171.432 | 55.512 | 77.143 | 117.026 | 170.858 / 382.852 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 160.758 | 283.427 | 480.358 | 559.381 | 171.345 / 385.109 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1000.761 | 0.987 | 1.060 | 1.124 | 98.972 / 385.137 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1950.922 | 5.155 | 6.311 | 8.010 | 199.440 / 385.137 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2014.564 | 24.452 | 26.341 | 42.307 | 200.838 / 385.137 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 978.980 | 0.997 | 1.096 | 1.369 | 99.903 / 385.168 | possible-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1886.352 | 5.190 | 6.801 | 9.087 | 199.285 / 385.168 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1880.906 | 25.347 | 28.429 | 44.905 | 201.187 / 385.168 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 963.023 | 1.017 | 1.106 | 1.326 | 99.436 / 385.293 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1831.222 | 5.788 | 7.333 | 9.820 | 199.292 / 385.293 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1905.800 | 25.299 | 28.290 | 43.374 | 200.222 / 385.391 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1847.960 | 52.337 | 63.042 | 93.145 | 200.130 / 388.035 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 75.398 | 12.928 | 15.013 | 16.523 | 64.668 / 388.570 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 135.376 | 71.403 | 103.969 | 135.150 | 129.232 / 388.684 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 123.697 | 371.333 | 638.217 | 725.685 | 128.466 / 388.684 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.821 | 741.416 | 1388.413 | 1458.668 | 128.958 / 388.684 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 966.902 | 1.032 | 1.090 | 1.432 | 98.946 / 388.684 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1955.950 | 5.173 | 6.874 | 9.965 | 199.765 / 388.684 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1958.431 | 25.133 | 26.550 | 43.298 | 200.892 / 388.684 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1986.094 | 49.418 | 50.910 | 88.282 | 200.405 / 388.684 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2658.756 | 12.972 | 33.149 | 37.795 | 385.412 / 632.035 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2509.977 | 35.465 | 58.384 | 68.058 | 376.158 / 635.969 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 163.341 | 271.270 | 565.747 | 678.188 | 230.720 / 637.707 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 157.954 | 469.558 | 1409.119 | 1478.848 | 234.967 / 638.445 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1933.245 | 30.058 | 35.536 | 51.496 | 210.599 / 638.762 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2705.645 | 34.852 | 66.695 | 78.551 | 386.547 / 638.762 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.542 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.429 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.514 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.599 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.096 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 4.109 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.294 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.120 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.009 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.519 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.583 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.288 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.400 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.117 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.061 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.381 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.488 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.505 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.575 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.458 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.547 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.327 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.390 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.079 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.488 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.196 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.166 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.221 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.057 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.089 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.086 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.056 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.063 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 726.346 | 137.152 | 148.325 | 151.544 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1246.854 | 156.347 | 173.389 | 174.912 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: -0.8%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +1.5%, p95_ms: +0.9%, p99_ms: +5.8%, requests_per_second: -1.4%, rss_bytes: +0.7% |
| cache_miss | stable | completed: -4.5%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +2.0%, p95_ms: +12.2%, p99_ms: +2.6%, requests_per_second: -4.5%, rss_bytes: +0.6% |
| cache_miss | stable | completed: -1.9%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +3.6%, p95_ms: +16.3%, p99_ms: +4.7%, requests_per_second: -1.8%, rss_bytes: +0.7% |
| health_live | stable | completed: -2.1%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: -0.7%, p95_ms: -2.5%, p99_ms: -6.7%, requests_per_second: +2.7%, rss_bytes: +0.7% |
| health_live | stable | completed: -1.5%, cpu_percent: -0.0%, duration_seconds: -4.6%, p50_ms: -1.2%, p95_ms: -1.6%, p99_ms: -5.9%, requests_per_second: +1.4%, rss_bytes: +0.7% |
| health_live | improvement | completed: +0.7%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -2.8%, p95_ms: -2.8%, p99_ms: -21.9%, requests_per_second: +0.8%, rss_bytes: +0.7% |
| health_live | stable | completed: +0.9%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: +2.9%, p95_ms: +4.8%, p99_ms: +6.3%, requests_per_second: +0.6%, rss_bytes: +0.7% |
| home | stable | completed: -8.8%, cpu_percent: -1.7%, duration_seconds: -0.0%, p50_ms: +10.1%, p95_ms: +17.5%, p99_ms: +17.4%, requests_per_second: -10.0%, rss_bytes: +0.6% |
| home | stable | completed: -11.7%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: +17.1%, p95_ms: +31.5%, p99_ms: +13.2%, requests_per_second: -11.8%, rss_bytes: +0.7% |
| home | confirmed-regression | completed: -13.4%, cpu_percent: -2.2%, duration_seconds: +0.2%, p50_ms: +14.8%, p95_ms: +16.0%, p99_ms: +19.1%, requests_per_second: -13.5%, rss_bytes: +0.7% |
| categories | improvement | completed: +8.1%, cpu_percent: +0.2%, duration_seconds: +5.0%, p50_ms: -4.2%, p95_ms: -3.8%, p99_ms: -27.0%, requests_per_second: +3.3%, rss_bytes: +0.7% |
| categories | stable | completed: +0.8%, cpu_percent: -0.3%, duration_seconds: +4.9%, p50_ms: -5.2%, p95_ms: +0.7%, p99_ms: -14.6%, requests_per_second: -0.5%, rss_bytes: +0.7% |
| categories | stable | completed: -0.5%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +1.6%, p95_ms: +2.1%, p99_ms: -0.9%, requests_per_second: -0.5%, rss_bytes: +0.7% |
| category | improvement | completed: -0.2%, cpu_percent: +0.1%, duration_seconds: -4.7%, p50_ms: -5.2%, p95_ms: -2.2%, p99_ms: -37.8%, requests_per_second: +4.7%, rss_bytes: +0.6% |
| category | stable | completed: +1.2%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -0.5%, p95_ms: +1.4%, p99_ms: +1.5%, requests_per_second: +1.2%, rss_bytes: +0.6% |
| category | possible-regression | completed: -1.8%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -1.8%, p95_ms: +9.3%, p99_ms: +23.2%, requests_per_second: -1.8%, rss_bytes: +0.6% |
| thread | stable | completed: +2.8%, cpu_percent: +0.1%, duration_seconds: +4.9%, p50_ms: +2.1%, p95_ms: +1.4%, p99_ms: +12.9%, requests_per_second: -2.0%, rss_bytes: +0.6% |
| thread | stable | completed: -0.2%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: +12.1%, p99_ms: +24.3%, requests_per_second: -0.2%, rss_bytes: +0.6% |
| thread | stable | completed: +2.9%, cpu_percent: -0.7%, duration_seconds: -0.1%, p50_ms: -2.6%, p95_ms: -8.6%, p99_ms: -7.1%, requests_per_second: +3.0%, rss_bytes: +0.6% |
| thread | stable | completed: -2.7%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: +4.3%, p99_ms: -0.9%, requests_per_second: -2.7%, rss_bytes: +0.7% |
| search | stable | completed: +0.0%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +0.3%, p95_ms: -2.1%, p99_ms: -8.0%, requests_per_second: +0.1%, rss_bytes: +0.7% |
| search | stable | completed: -0.7%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -0.4%, p95_ms: +13.8%, p99_ms: +7.7%, requests_per_second: -0.6%, rss_bytes: +0.7% |
| search | stable | completed: -17.9%, cpu_percent: +3.0%, duration_seconds: +0.0%, p50_ms: +14.7%, p95_ms: +18.9%, p99_ms: +13.6%, requests_per_second: -18.0%, rss_bytes: +0.7% |
| search | stable | completed: +0.0%, cpu_percent: +1.5%, duration_seconds: -0.0%, p50_ms: +5.1%, p95_ms: +7.3%, p99_ms: +8.9%, requests_per_second: +0.0%, rss_bytes: +0.7% |
| cache_hit | possible-regression | completed: -0.6%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +1.2%, p95_ms: -0.1%, p99_ms: +26.2%, requests_per_second: -0.9%, rss_bytes: +0.7% |
| cache_hit | stable | completed: +0.6%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.4%, p95_ms: -17.6%, p99_ms: -2.5%, requests_per_second: +1.0%, rss_bytes: +0.7% |
| cache_hit | stable | completed: -0.1%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: +0.9%, p95_ms: +0.3%, p99_ms: -5.8%, requests_per_second: -0.1%, rss_bytes: +0.7% |
| cache_hit | stable | completed: -2.8%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +0.8%, p95_ms: +7.4%, p99_ms: +4.3%, requests_per_second: -2.7%, rss_bytes: +0.7% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +21.4%, duration_seconds: +1.5%, p50_ms: +3.1%, p95_ms: +2.8%, p99_ms: +6.7%, requests_per_second: -2.3%, rss_bytes: +0.7% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +0.3%, duration_seconds: +2.1%, p50_ms: +6.0%, p95_ms: +0.1%, p99_ms: +2.8%, requests_per_second: -1.8%, rss_bytes: +0.7% |
| thread | possible-regression | completed: -15.4%, cpu_percent: -22.4%, duration_seconds: -4.6%, p50_ms: +81.5%, p95_ms: +6.8%, p99_ms: -16.8%, requests_per_second: -11.4%, rss_bytes: +0.7% |
| thread | stable | completed: +1.3%, cpu_percent: +0.6%, duration_seconds: +0.2%, p50_ms: +10.0%, p95_ms: +3.0%, p99_ms: +4.7%, requests_per_second: +1.3%, rss_bytes: +0.8% |
| search | improvement | completed: +15.5%, cpu_percent: -5.7%, duration_seconds: +0.7%, p50_ms: +7.3%, p95_ms: +0.9%, p99_ms: -11.2%, requests_per_second: +14.9%, rss_bytes: +0.7% |
| search | improvement | completed: -7.5%, cpu_percent: -3.2%, duration_seconds: -0.0%, p50_ms: +29.6%, p95_ms: -4.9%, p99_ms: -17.8%, requests_per_second: -7.2%, rss_bytes: +0.7% |
| cache_hit | stable | completed: +6.2%, cpu_percent: -7.3%, duration_seconds: -0.2%, p50_ms: -18.5%, p95_ms: +10.8%, p99_ms: -14.6%, requests_per_second: +6.4%, rss_bytes: +0.7% |
| cache_hit | stable | completed: +1.3%, cpu_percent: -1.1%, duration_seconds: -0.1%, p50_ms: +6.4%, p95_ms: +0.4%, p99_ms: -2.0%, requests_per_second: +1.4%, rss_bytes: +0.6% |
| cache_miss | possible-regression | completed: +0.9%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -0.9%, p95_ms: -2.6%, p99_ms: +16.1%, requests_per_second: +0.8%, rss_bytes: +0.7% |
| cache_miss | stable | completed: +4.5%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: -10.3%, p99_ms: -2.9%, requests_per_second: +4.4%, rss_bytes: +0.7% |
| cache_miss | stable | completed: +2.5%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -1.9%, p95_ms: -3.1%, p99_ms: -6.0%, requests_per_second: +2.5%, rss_bytes: +0.7% |
| health_live | stable | completed: -2.7%, cpu_percent: -1.4%, duration_seconds: -0.0%, p50_ms: -0.4%, p95_ms: +1.5%, p99_ms: +0.9%, requests_per_second: -2.4%, rss_bytes: +0.7% |
| health_live | possible-regression | completed: -1.6%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +14.8%, p95_ms: +19.1%, p99_ms: -11.1%, requests_per_second: -1.7%, rss_bytes: +0.7% |
| health_live | stable | completed: -2.4%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +2.9%, p95_ms: +1.5%, p99_ms: -3.0%, requests_per_second: -2.4%, rss_bytes: +0.7% |
| health_live | stable | completed: -2.2%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -0.6%, p95_ms: -0.8%, p99_ms: +1.6%, requests_per_second: -2.1%, rss_bytes: +0.6% |
| home | stable | completed: -6.4%, cpu_percent: -2.2%, duration_seconds: -0.0%, p50_ms: +5.2%, p95_ms: +6.2%, p99_ms: +11.0%, requests_per_second: -6.4%, rss_bytes: +0.7% |
| home | stable | completed: -11.6%, cpu_percent: -1.6%, duration_seconds: +0.0%, p50_ms: +5.0%, p95_ms: +7.5%, p99_ms: +15.7%, requests_per_second: -11.1%, rss_bytes: +0.7% |
| home | stable | completed: -7.5%, cpu_percent: -1.3%, duration_seconds: -0.0%, p50_ms: +6.5%, p95_ms: +2.6%, p99_ms: +1.1%, requests_per_second: -7.5%, rss_bytes: +0.6% |
| categories | stable | completed: -4.0%, cpu_percent: -0.5%, duration_seconds: -4.7%, p50_ms: -0.2%, p95_ms: +0.6%, p99_ms: +0.9%, requests_per_second: +0.8%, rss_bytes: +0.6% |
| categories | improvement | completed: +0.1%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: -1.7%, p95_ms: -9.0%, p99_ms: -25.8%, requests_per_second: +0.2%, rss_bytes: +0.6% |
| categories | stable | completed: +1.7%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -12.2%, p95_ms: -22.1%, p99_ms: +6.6%, requests_per_second: +1.6%, rss_bytes: +0.6% |
| category | possible-regression | completed: -0.6%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: +3.1%, p99_ms: +23.1%, requests_per_second: -0.8%, rss_bytes: +0.6% |
| category | improvement | completed: +1.8%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -4.7%, p95_ms: -9.8%, p99_ms: -11.9%, requests_per_second: -0.7%, rss_bytes: +0.6% |
| category | stable | completed: -2.3%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -0.3%, p95_ms: +5.2%, p99_ms: -0.6%, requests_per_second: -2.3%, rss_bytes: +0.6% |
| thread | improvement | completed: +1.0%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -1.6%, p95_ms: -0.2%, p99_ms: -31.8%, requests_per_second: +0.2%, rss_bytes: +0.6% |
| thread | possible-regression | completed: -0.9%, cpu_percent: -0.0%, duration_seconds: +4.9%, p50_ms: +10.7%, p95_ms: +12.7%, p99_ms: +8.5%, requests_per_second: -2.9%, rss_bytes: +0.6% |
| thread | stable | completed: +1.3%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -3.1%, p95_ms: -0.3%, p99_ms: -5.9%, requests_per_second: +1.3%, rss_bytes: +0.6% |
| thread | stable | completed: -0.7%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: +0.2%, p95_ms: +2.7%, p99_ms: +3.1%, requests_per_second: -0.8%, rss_bytes: +0.6% |
| search | improvement | completed: +16.2%, cpu_percent: -3.7%, duration_seconds: -0.1%, p50_ms: -15.0%, p95_ms: -11.6%, p99_ms: -4.5%, requests_per_second: +16.2%, rss_bytes: +0.6% |
| search | stable | completed: +5.9%, cpu_percent: -2.8%, duration_seconds: +0.0%, p50_ms: -9.8%, p95_ms: -2.9%, p99_ms: -8.4%, requests_per_second: +11.1%, rss_bytes: +0.6% |
| search | stable | completed: +11.7%, cpu_percent: -2.6%, duration_seconds: -0.0%, p50_ms: -8.7%, p95_ms: -11.7%, p99_ms: -10.9%, requests_per_second: +11.7%, rss_bytes: +0.6% |
| search | stable | completed: +0.0%, cpu_percent: -2.2%, duration_seconds: +0.1%, p50_ms: -7.3%, p95_ms: -6.8%, p99_ms: -8.6%, requests_per_second: -0.0%, rss_bytes: +0.6% |
| cache_hit | confirmed-regression | completed: -9.4%, cpu_percent: -0.9%, duration_seconds: -4.7%, p50_ms: +6.0%, p95_ms: +6.2%, p99_ms: +30.7%, requests_per_second: -4.9%, rss_bytes: +0.6% |
| cache_hit | possible-regression | completed: +0.1%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +2.7%, p95_ms: +1.3%, p99_ms: +14.4%, requests_per_second: +0.0%, rss_bytes: +0.6% |
| cache_hit | stable | completed: -0.2%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +0.5%, p95_ms: -1.5%, p99_ms: -3.5%, requests_per_second: -0.2%, rss_bytes: +0.6% |
| cache_hit | stable | completed: +5.0%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -3.2%, p95_ms: -7.4%, p99_ms: +4.0%, requests_per_second: +5.1%, rss_bytes: +0.6% |
| thread | improvement | completed: +6.2%, cpu_percent: +0.1%, duration_seconds: +4.8%, p50_ms: -33.6%, p95_ms: -3.3%, p99_ms: -13.3%, requests_per_second: +1.3%, rss_bytes: +0.7% |
| thread | stable | completed: -3.5%, cpu_percent: -2.8%, duration_seconds: -0.0%, p50_ms: -4.4%, p95_ms: +20.3%, p99_ms: +9.9%, requests_per_second: -3.6%, rss_bytes: +0.6% |
| search | improvement | completed: +2.2%, cpu_percent: -4.3%, duration_seconds: -0.1%, p50_ms: +21.6%, p95_ms: -19.0%, p99_ms: -20.2%, requests_per_second: +2.3%, rss_bytes: +0.7% |
| search | stable | completed: +2.3%, cpu_percent: -2.8%, duration_seconds: -0.0%, p50_ms: +7.8%, p95_ms: +9.5%, p99_ms: +5.7%, requests_per_second: +2.4%, rss_bytes: +0.6% |
| cache_hit | stable | completed: -17.9%, cpu_percent: -29.2%, duration_seconds: -0.1%, p50_ms: +30.3%, p95_ms: -3.6%, p99_ms: +22.9%, requests_per_second: -13.9%, rss_bytes: +0.7% |
| cache_hit | stable | completed: +2.7%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +17.1%, p95_ms: +0.3%, p99_ms: -2.3%, requests_per_second: +2.7%, rss_bytes: +0.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -6.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -6.2% |
| sql-plan-readers | improvement | sql_execution_ms: -14.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -20.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +20.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -10.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -4.4% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -13.5% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +12.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +20.3% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -17.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -21.2% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -2.0%, messages_per_second: +2.0%, p50_ms: -1.0%, p95_ms: -2.3%, p99_ms: -7.4% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -3.5%, messages_per_second: +3.6%, p50_ms: -4.8%, p95_ms: -8.5%, p99_ms: -8.1% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: +0.4%, cpu_percent: +0.6%, duration_seconds: -0.0%, p50_ms: -1.5%, p95_ms: -0.0%, p99_ms: +14.3%, requests_per_second: +0.9%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +3.6%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +0.5%, p95_ms: -6.0%, p99_ms: +10.4%, requests_per_second: +3.6%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.6%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -3.3%, p95_ms: -11.0%, p99_ms: -0.3%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +3.0%, cpu_percent: -0.5%, duration_seconds: +4.9%, p50_ms: -1.4%, p95_ms: -0.1%, p99_ms: -17.0%, requests_per_second: -1.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -1.5%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +13.4%, p95_ms: +19.8%, p99_ms: +21.5%, requests_per_second: -1.7%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -1.5%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: +3.1%, p95_ms: -1.9%, p99_ms: +15.4%, requests_per_second: -1.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -2.3%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -0.9%, p95_ms: -4.0%, p99_ms: +3.8%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -3.1%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +1.4%, p95_ms: -1.8%, p99_ms: -1.4%, requests_per_second: -1.7%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.2%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: -4.2%, p95_ms: -1.7%, p99_ms: +7.6%, requests_per_second: +1.3%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.6%, cpu_percent: -0.0%, duration_seconds: -0.2%, p50_ms: -1.2%, p95_ms: -7.6%, p99_ms: -5.8%, requests_per_second: -0.5%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -3.8%, cpu_percent: -0.6%, duration_seconds: -4.7%, p50_ms: -0.6%, p95_ms: +0.2%, p99_ms: -0.5%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.4%, cpu_percent: +0.3%, duration_seconds: -4.7%, p50_ms: +5.8%, p95_ms: -1.8%, p99_ms: +15.1%, requests_per_second: +0.0%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +1.9%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -2.3%, p95_ms: -2.2%, p99_ms: +29.8%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | confirmed-regression | completed: +0.9%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: -1.8%, p95_ms: +0.0%, p99_ms: +20.2%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.3%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -1.6%, p95_ms: +20.3%, p99_ms: +20.1%, requests_per_second: -0.2%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -2.6%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +0.4%, p95_ms: -3.8%, p99_ms: +17.0%, requests_per_second: -2.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.5%, cpu_percent: -0.0%, duration_seconds: -4.6%, p50_ms: -2.8%, p95_ms: -1.9%, p99_ms: +1.7%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.1%, cpu_percent: -0.2%, duration_seconds: +4.9%, p50_ms: +10.4%, p95_ms: +11.6%, p99_ms: -1.2%, requests_per_second: -2.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -1.5%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -2.3%, p95_ms: +5.8%, p99_ms: +37.8%, requests_per_second: -1.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.0%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +1.7%, p95_ms: +8.5%, p99_ms: +9.7%, requests_per_second: -1.1%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -3.2%, cpu_percent: +1.5%, duration_seconds: +0.1%, p50_ms: +2.0%, p95_ms: +9.1%, p99_ms: +14.2%, requests_per_second: -3.3%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -2.2%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +1.2%, p95_ms: +13.9%, p99_ms: +3.7%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +10.7%, cpu_percent: -2.6%, duration_seconds: +0.0%, p50_ms: -4.0%, p95_ms: -10.2%, p99_ms: -8.8%, requests_per_second: +10.6%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -1.4%, p95_ms: -1.6%, p99_ms: -3.8%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.7%, cpu_percent: -1.1%, duration_seconds: -0.1%, p50_ms: +2.6%, p95_ms: +1.2%, p99_ms: +0.5%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -0.3%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: +2.2%, p95_ms: +29.6%, p99_ms: +41.6%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -1.7%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.2%, p95_ms: -0.9%, p99_ms: +32.9%, requests_per_second: -1.6%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +3.6%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -2.0%, p95_ms: -9.3%, p99_ms: +7.9%, requests_per_second: +3.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +21.7%, cpu_percent: +28.8%, duration_seconds: +4.7%, p50_ms: -49.0%, p95_ms: -8.3%, p99_ms: -13.3%, requests_per_second: +16.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -4.2%, cpu_percent: -2.9%, duration_seconds: -0.1%, p50_ms: -3.4%, p95_ms: -13.4%, p99_ms: -17.9%, requests_per_second: -4.2%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -8.1%, cpu_percent: +2.8%, duration_seconds: -0.7%, p50_ms: +15.6%, p95_ms: -23.4%, p99_ms: -25.4%, requests_per_second: -7.5%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +6.4%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: +12.7%, p95_ms: -0.7%, p99_ms: +4.0%, requests_per_second: +6.4%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -4.8%, cpu_percent: -1.3%, duration_seconds: +0.0%, p50_ms: +22.8%, p95_ms: -27.6%, p99_ms: -2.6%, requests_per_second: -4.8%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -0.8%, cpu_percent: +1.1%, duration_seconds: +0.1%, p50_ms: -8.5%, p95_ms: +19.2%, p99_ms: +28.4%, requests_per_second: -0.8%, rss_bytes: +0.1% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +18.3%, cpu_percent: +49.7%, duration_seconds: +0.1%, p50_ms: -1.9%, p95_ms: +35.2%, p99_ms: +38.5%, requests_per_second: +18.2%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +40.3%, cpu_percent: +92.5%, duration_seconds: +0.2%, p50_ms: -28.7%, p95_ms: +16.0%, p99_ms: -2.3%, requests_per_second: +40.2%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 50 | improvement | completed: +59.4%, cpu_percent: +70.3%, duration_seconds: +0.9%, p50_ms: -39.4%, p95_ms: +3.9%, p99_ms: +14.2%, requests_per_second: +57.8%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +49.0%, cpu_percent: +83.0%, duration_seconds: +0.2%, p50_ms: -44.6%, p95_ms: +0.6%, p99_ms: -6.3%, requests_per_second: +48.7%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: +1.9%, cpu_percent: +6.2%, duration_seconds: +0.0%, p50_ms: -2.8%, p95_ms: +83.4%, p99_ms: +62.3%, requests_per_second: +1.9%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +42.5%, cpu_percent: +91.5%, duration_seconds: +0.1%, p50_ms: -24.5%, p95_ms: -0.3%, p99_ms: -25.2%, requests_per_second: +42.3%, rss_bytes: +64.6% |
| thread | workers=4 | 2 | 50 | improvement | completed: +46.2%, cpu_percent: +92.5%, duration_seconds: +4.8%, p50_ms: -48.7%, p95_ms: +17.2%, p99_ms: -12.9%, requests_per_second: +39.5%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +35.8%, cpu_percent: +88.0%, duration_seconds: +0.0%, p50_ms: -32.2%, p95_ms: -7.4%, p99_ms: -26.9%, requests_per_second: +35.8%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +32.3%, cpu_percent: +79.6%, duration_seconds: +0.2%, p50_ms: -26.9%, p95_ms: -11.4%, p99_ms: -6.5%, requests_per_second: +32.0%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +58.5%, cpu_percent: +82.2%, duration_seconds: +0.2%, p50_ms: -36.7%, p95_ms: +1.5%, p99_ms: +1.4%, requests_per_second: +58.2%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -1.3%, cpu_percent: +4.8%, duration_seconds: +0.1%, p50_ms: +19.6%, p95_ms: +33.8%, p99_ms: +18.9%, requests_per_second: -1.3%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +36.5%, cpu_percent: +92.9%, duration_seconds: +0.1%, p50_ms: -29.5%, p95_ms: +31.0%, p99_ms: -11.0%, requests_per_second: +36.2%, rss_bytes: +64.3% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38784936557)
