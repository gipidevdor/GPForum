# GPForum continuous performance evidence

Commit: `57b2c5eb62f559cf320cc713683352b0dd091018` · mode: **main** · status: **ok**
Run: 38690190012 / attempt 1 · 2026-10-15T06:03:58.134044+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: No baseline available.

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 273.361 | 3.599 | 3.764 | 4.032 | 99.518 / 370.215 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 534.528 | 18.302 | 22.301 | 26.258 | 199.388 / 370.215 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 531.930 | 90.615 | 99.768 | 160.065 | 200.741 / 371.840 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1165.781 | 0.850 | 0.901 | 0.932 | 99.904 / 370.203 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2274.780 | 4.364 | 4.544 | 5.512 | 199.718 / 370.203 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2320.992 | 21.295 | 22.723 | 25.909 | 200.395 / 370.875 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2218.214 | 44.322 | 45.815 | 66.198 | 199.977 / 372.129 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 119.831 | 8.260 | 8.698 | 9.289 | 86.547 / 372.344 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 226.048 | 42.693 | 50.412 | 69.722 | 174.059 / 372.934 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 224.529 | 217.257 | 326.037 | 399.257 | 174.311 / 374.676 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 863.155 | 1.142 | 1.205 | 1.238 | 99.377 / 374.676 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1724.892 | 5.752 | 5.963 | 6.974 | 199.795 / 374.676 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1731.534 | 28.071 | 30.851 | 36.310 | 200.261 / 374.676 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 835.201 | 1.174 | 1.261 | 1.466 | 98.984 / 374.691 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1693.168 | 5.872 | 6.103 | 7.176 | 199.907 / 374.707 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1702.843 | 29.271 | 30.340 | 38.581 | 200.286 / 374.707 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 828.781 | 1.212 | 1.256 | 1.295 | 99.439 / 374.832 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1671.091 | 5.916 | 6.104 | 7.612 | 199.851 / 374.832 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1696.855 | 29.263 | 30.657 | 37.523 | 201.388 / 375.398 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1645.739 | 58.980 | 75.624 | 95.879 | 200.269 / 378.590 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 75.424 | 13.166 | 13.789 | 16.521 | 66.152 / 379.215 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 136.387 | 71.909 | 87.730 | 132.126 | 132.270 / 379.215 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.791 | 361.682 | 612.576 | 691.707 | 131.937 / 379.215 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.790 | 720.335 | 1347.130 | 1400.667 | 131.447 / 379.215 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 869.599 | 1.139 | 1.198 | 1.249 | 99.480 / 379.215 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1711.218 | 5.801 | 6.031 | 6.509 | 199.428 / 379.215 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1728.788 | 28.266 | 32.027 | 38.590 | 200.259 / 379.215 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1721.375 | 56.868 | 60.353 | 91.231 | 201.388 / 379.215 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1382.457 | 6.251 | 10.282 | 14.769 | 24.803 / 379.215 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 968.814 | 9.458 | 13.563 | 17.535 | 38.318 / 379.496 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2471.073 | 17.425 | 36.144 | 38.564 | 387.393 / 615.926 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2462.003 | 39.169 | 71.530 | 87.320 | 389.356 / 620.242 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 159.445 | 234.019 | 785.965 | 943.792 | 234.592 / 622.473 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 143.539 | 554.827 | 1018.808 | 1139.812 | 241.220 / 622.801 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1716.079 | 23.640 | 42.932 | 49.790 | 211.995 / 622.801 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2537.117 | 31.960 | 50.761 | 75.757 | 388.387 / 622.801 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 281.249 | 3.530 | 3.646 | 3.853 | 99.523 / 371.000 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 544.451 | 18.163 | 19.043 | 26.663 | 199.842 / 371.027 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 534.689 | 90.295 | 102.877 | 160.613 | 201.340 / 372.762 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1182.906 | 0.838 | 0.888 | 0.944 | 99.935 / 371.211 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2299.452 | 4.283 | 4.518 | 6.225 | 198.872 / 371.211 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2358.489 | 21.045 | 22.007 | 24.983 | 199.890 / 371.949 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2294.820 | 42.599 | 46.230 | 64.321 | 201.361 / 373.438 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 118.857 | 8.312 | 8.747 | 9.462 | 85.592 / 373.820 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 224.309 | 43.049 | 51.588 | 76.929 | 173.526 / 374.160 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 211.011 | 219.471 | 338.419 | 413.756 | 173.048 / 375.867 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 883.997 | 1.118 | 1.183 | 1.252 | 100.935 / 375.867 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1746.447 | 5.694 | 5.960 | 7.546 | 198.949 / 375.867 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1765.445 | 28.054 | 29.882 | 40.701 | 201.380 / 375.867 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 865.313 | 1.142 | 1.214 | 1.268 | 99.517 / 375.898 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1700.434 | 5.828 | 5.999 | 9.326 | 199.460 / 375.898 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1731.423 | 28.533 | 30.429 | 39.027 | 200.369 / 375.898 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 861.180 | 1.148 | 1.216 | 1.254 | 99.464 / 375.961 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1697.823 | 5.865 | 6.200 | 8.252 | 198.933 / 376.023 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1713.629 | 28.262 | 30.493 | 44.367 | 198.911 / 376.680 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1695.233 | 58.264 | 61.024 | 97.130 | 201.856 / 379.887 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 74.766 | 13.119 | 14.322 | 15.535 | 65.399 / 380.734 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 136.181 | 69.809 | 83.616 | 129.186 | 130.566 / 380.734 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.350 | 359.138 | 611.444 | 693.563 | 130.895 / 380.734 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.263 | 781.322 | 1584.994 | 1679.515 | 133.301 / 380.734 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 889.345 | 1.131 | 1.180 | 1.221 | 99.454 / 380.734 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1739.558 | 5.676 | 7.019 | 7.401 | 198.922 / 380.734 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1743.229 | 28.099 | 31.328 | 41.030 | 200.480 / 380.734 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1720.573 | 56.593 | 59.337 | 93.223 | 199.886 / 380.734 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2129.609 | 24.643 | 38.369 | 42.693 | 333.334 / 618.230 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2450.704 | 36.912 | 68.272 | 81.230 | 385.817 / 622.352 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 147.723 | 191.880 | 768.260 | 932.221 | 231.050 / 624.148 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 153.072 | 469.389 | 1475.159 | 1508.530 | 240.054 / 625.938 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1771.178 | 28.543 | 37.253 | 47.473 | 201.334 / 626.137 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2575.798 | 33.212 | 66.966 | 87.746 | 388.806 / 626.137 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.496 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.033 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.494 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.567 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.096 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.563 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.010 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.105 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.029 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.430 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.516 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.264 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.367 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.094 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.045 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.019 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.501 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.456 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.552 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.486 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.586 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.268 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.370 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.090 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.336 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.191 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.160 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.184 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.113 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.056 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.070 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 681.615 | 144.601 | 159.059 | 163.837 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1148.327 | 171.280 | 198.641 | 200.362 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.9%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -1.9%, p95_ms: -3.1%, p99_ms: -4.4%, requests_per_second: +2.9%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +1.9%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: -14.6%, p99_ms: +1.5%, requests_per_second: +1.9%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.5%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: +3.1%, p99_ms: +0.3%, requests_per_second: +0.5%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +5.5%, cpu_percent: +0.0%, duration_seconds: +5.0%, p50_ms: -1.4%, p95_ms: -1.4%, p99_ms: +1.3%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +3.0%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: -1.9%, p95_ms: -0.6%, p99_ms: +12.9%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.6%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -1.2%, p95_ms: -3.2%, p99_ms: -3.6%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +3.3%, cpu_percent: +0.7%, duration_seconds: -0.1%, p50_ms: -3.9%, p95_ms: +0.9%, p99_ms: -2.8%, requests_per_second: +3.5%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.8%, cpu_percent: -1.1%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: +0.6%, p99_ms: +1.9%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +0.0%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +0.8%, p95_ms: +2.3%, p99_ms: +10.3%, requests_per_second: -0.8%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -6.0%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: +1.0%, p95_ms: +3.8%, p99_ms: +3.6%, requests_per_second: -6.0%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.0%, cpu_percent: +1.6%, duration_seconds: +0.1%, p50_ms: -2.1%, p95_ms: -1.8%, p99_ms: +1.1%, requests_per_second: +2.4%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.2%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -1.0%, p95_ms: -0.1%, p99_ms: +8.2%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.9%, cpu_percent: +0.6%, duration_seconds: -0.0%, p50_ms: -0.1%, p95_ms: -3.1%, p99_ms: +12.1%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +5.7%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -2.7%, p95_ms: -3.7%, p99_ms: -13.5%, requests_per_second: +3.6%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +0.3%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -0.7%, p95_ms: -1.7%, p99_ms: +30.0%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.7%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -2.5%, p95_ms: +0.3%, p99_ms: +1.2%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.9%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -5.3%, p95_ms: -3.2%, p99_ms: -3.2%, requests_per_second: +3.9%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +6.0%, cpu_percent: -0.5%, duration_seconds: +4.7%, p50_ms: -0.9%, p95_ms: +1.6%, p99_ms: +8.4%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.1%, cpu_percent: -1.2%, duration_seconds: +0.1%, p50_ms: -3.4%, p95_ms: -0.5%, p99_ms: +18.2%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +2.9%, cpu_percent: +0.8%, duration_seconds: -0.0%, p50_ms: -1.2%, p95_ms: -19.3%, p99_ms: +1.3%, requests_per_second: +3.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.3%, cpu_percent: -1.1%, duration_seconds: +0.1%, p50_ms: -0.4%, p95_ms: +3.9%, p99_ms: -6.0%, requests_per_second: -0.9%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +4.8%, cpu_percent: -1.3%, duration_seconds: +4.9%, p50_ms: -2.9%, p95_ms: -4.7%, p99_ms: -2.2%, requests_per_second: -0.2%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: -0.7%, p95_ms: -0.2%, p99_ms: +0.3%, requests_per_second: -0.4%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -0.5%, cpu_percent: +1.4%, duration_seconds: +0.1%, p50_ms: +8.5%, p95_ms: +17.7%, p99_ms: +19.9%, requests_per_second: -0.5%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.2%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -0.7%, p95_ms: -1.5%, p99_ms: -2.2%, requests_per_second: +2.3%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -3.0%, cpu_percent: -0.3%, duration_seconds: -4.7%, p50_ms: -2.2%, p95_ms: +16.4%, p99_ms: +13.7%, requests_per_second: +1.7%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.8%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -0.6%, p95_ms: -2.2%, p99_ms: +6.3%, requests_per_second: +0.8%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.0%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: -1.7%, p99_ms: +2.2%, requests_per_second: -0.0%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -13.8%, cpu_percent: -14.0%, duration_seconds: -0.1%, p50_ms: +41.4%, p95_ms: +6.2%, p99_ms: +10.7%, requests_per_second: -13.8%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.3%, cpu_percent: -0.9%, duration_seconds: +0.1%, p50_ms: -5.8%, p95_ms: -4.6%, p99_ms: -7.0%, requests_per_second: -0.5%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -3.1%, cpu_percent: -1.5%, duration_seconds: +0.1%, p50_ms: -18.0%, p95_ms: -2.3%, p99_ms: -1.2%, requests_per_second: -7.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: +6.6%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: -15.4%, p95_ms: +44.8%, p99_ms: +32.3%, requests_per_second: +6.6%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.4%, cpu_percent: -5.0%, duration_seconds: +0.0%, p50_ms: +20.7%, p95_ms: -13.2%, p99_ms: -4.7%, requests_per_second: +3.2%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: +1.5%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +3.9%, p95_ms: +31.9%, p99_ms: +15.8%, requests_per_second: +1.5%, rss_bytes: +0.5% |
| thread | workers=4 | 2 | 50 | improvement | completed: +45.7%, cpu_percent: +92.4%, duration_seconds: +0.2%, p50_ms: -40.5%, p95_ms: +17.9%, p99_ms: +2.8%, requests_per_second: +45.6%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +49.6%, cpu_percent: +94.4%, duration_seconds: +0.0%, p50_ms: -33.6%, p95_ms: -5.4%, p99_ms: -8.9%, requests_per_second: +49.6%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +28.0%, cpu_percent: +77.8%, duration_seconds: +0.2%, p50_ms: -35.3%, p95_ms: +28.3%, p99_ms: +36.4%, requests_per_second: +27.8%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +44.5%, cpu_percent: +83.5%, duration_seconds: +0.5%, p50_ms: -23.0%, p95_ms: -24.4%, p99_ms: -18.6%, requests_per_second: +43.8%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: +4.0%, cpu_percent: +5.9%, duration_seconds: +0.0%, p50_ms: -16.4%, p95_ms: +34.0%, p99_ms: +29.0%, requests_per_second: -0.7%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +47.6%, cpu_percent: +92.9%, duration_seconds: +0.1%, p50_ms: -43.8%, p95_ms: -15.9%, p99_ms: -17.0%, requests_per_second: +47.4%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 50 | improvement | completed: +24.2%, cpu_percent: +67.6%, duration_seconds: +0.0%, p50_ms: -12.8%, p95_ms: +25.8%, p99_ms: -3.8%, requests_per_second: +24.3%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +44.8%, cpu_percent: +91.1%, duration_seconds: +0.1%, p50_ms: -36.6%, p95_ms: +11.9%, p99_ms: -16.4%, requests_per_second: +44.6%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +24.5%, cpu_percent: +76.5%, duration_seconds: +0.3%, p50_ms: -46.6%, p95_ms: +25.6%, p99_ms: +34.4%, requests_per_second: +18.8%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +54.8%, cpu_percent: +80.1%, duration_seconds: +0.3%, p50_ms: -39.9%, p95_ms: -6.9%, p99_ms: -10.2%, requests_per_second: +54.2%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: +1.7%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: +1.6%, p95_ms: +18.9%, p99_ms: +15.7%, requests_per_second: +1.6%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +49.8%, cpu_percent: +94.5%, duration_seconds: +0.1%, p50_ms: -41.3%, p95_ms: +12.9%, p99_ms: -5.9%, requests_per_second: +49.7%, rss_bytes: +64.5% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38690190012)
