# GPForum continuous performance evidence

Commit: `d475213cdd4a731e2c0d71014ca7937f3ca354ed` · mode: **main** · status: **ok**
Run: 38783394023 / attempt 1 · 2026-10-15T18:10:49.368516+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. cec277e18d8e535ea503696969a4616608dfd0e7

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 205.456 | 4.829 | 5.076 | 6.001 | 99.940 / 377.211 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 398.889 | 24.290 | 30.296 | 36.869 | 199.401 / 377.262 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 395.240 | 121.543 | 166.748 | 225.353 | 201.853 / 379.070 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1159.107 | 0.865 | 0.909 | 0.940 | 99.299 / 377.094 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2286.112 | 4.347 | 4.479 | 5.283 | 199.431 / 377.094 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2350.814 | 20.761 | 23.227 | 28.363 | 197.957 / 377.676 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2293.764 | 42.476 | 47.992 | 64.792 | 200.750 / 378.930 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 81.764 | 11.959 | 13.824 | 15.808 | 87.500 / 379.332 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 154.229 | 62.457 | 76.503 | 99.582 | 174.000 / 380.000 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.647 | 333.689 | 588.588 | 665.718 | 174.544 / 382.414 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 868.202 | 1.133 | 1.210 | 1.276 | 99.492 / 382.414 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1732.472 | 5.719 | 5.963 | 7.429 | 199.402 / 382.414 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1757.266 | 28.724 | 30.340 | 36.622 | 200.726 / 382.414 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 845.538 | 1.182 | 1.243 | 1.428 | 99.496 / 382.430 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1670.686 | 6.695 | 7.010 | 7.961 | 199.228 / 382.445 | possible-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1674.895 | 29.440 | 30.492 | 38.078 | 200.247 / 382.445 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 841.746 | 1.170 | 1.247 | 1.466 | 99.418 / 382.570 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1667.568 | 5.964 | 7.473 | 7.984 | 199.384 / 382.570 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1696.509 | 29.141 | 30.993 | 36.965 | 200.351 / 382.570 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1620.882 | 60.749 | 64.621 | 98.968 | 201.774 / 385.336 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 68.955 | 14.076 | 16.659 | 17.596 | 66.106 / 385.867 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 134.337 | 71.054 | 93.480 | 125.641 | 132.224 / 385.867 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 99.758 | 443.846 | 778.150 | 854.129 | 133.765 / 385.867 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.716 | 925.454 | 1725.134 | 1792.263 | 136.239 / 385.867 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 856.167 | 1.157 | 1.222 | 1.296 | 99.897 / 385.867 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1710.958 | 5.760 | 6.230 | 7.995 | 198.755 / 385.867 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1716.673 | 28.291 | 32.727 | 38.742 | 201.197 / 385.867 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1646.255 | 59.041 | 63.792 | 91.929 | 199.271 / 385.867 | stable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1339.122 | 6.788 | 11.143 | 12.709 | 27.280 / 385.867 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 868.048 | 10.163 | 17.062 | 18.265 | 36.603 / 386.172 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2449.144 | 18.692 | 29.256 | 42.116 | 388.741 / 627.805 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2371.076 | 42.621 | 54.453 | 69.672 | 386.447 / 631.230 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 141.083 | 270.980 | 614.004 | 759.809 | 194.145 / 632.395 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 140.823 | 520.798 | 1139.181 | 1312.016 | 237.644 / 633.461 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1493.437 | 32.076 | 40.848 | 54.495 | 201.047 / 633.496 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2413.737 | 42.747 | 60.079 | 70.658 | 387.217 / 633.625 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 196.789 | 4.947 | 5.983 | 6.555 | 99.899 / 378.312 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 395.149 | 25.159 | 31.644 | 43.430 | 200.270 / 378.379 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 372.651 | 125.847 | 158.948 | 234.529 | 201.153 / 380.273 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1163.193 | 0.847 | 0.913 | 1.257 | 99.424 / 378.031 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2253.969 | 4.407 | 4.768 | 5.594 | 199.313 / 378.031 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2304.267 | 21.270 | 22.633 | 28.736 | 200.225 / 378.762 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2212.080 | 44.411 | 47.437 | 68.397 | 199.206 / 380.113 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 71.976 | 13.648 | 15.041 | 18.023 | 86.955 / 380.742 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 142.809 | 68.580 | 107.744 | 158.830 | 175.389 / 381.270 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.236 | 357.676 | 644.700 | 697.601 | 174.660 / 383.660 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 846.650 | 1.161 | 1.226 | 1.665 | 99.445 / 383.660 | possible-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1705.010 | 5.767 | 6.323 | 9.898 | 199.299 / 383.660 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1731.810 | 28.485 | 32.498 | 44.195 | 199.914 / 383.660 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 840.467 | 1.186 | 1.240 | 1.607 | 99.433 / 383.781 | possible-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1691.011 | 5.816 | 6.312 | 9.731 | 199.392 / 383.781 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1679.698 | 29.308 | 31.068 | 42.661 | 200.280 / 383.781 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 855.156 | 1.166 | 1.217 | 2.233 | 99.400 / 383.906 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1646.303 | 5.910 | 7.637 | 9.813 | 198.719 / 383.906 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1677.504 | 29.321 | 31.143 | 47.090 | 200.708 / 383.906 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1661.537 | 58.419 | 68.939 | 97.953 | 200.720 / 386.637 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 59.397 | 16.657 | 18.074 | 19.885 | 69.595 / 387.250 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 119.359 | 86.706 | 108.487 | 164.449 | 136.157 / 387.340 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 99.773 | 405.705 | 764.488 | 836.205 | 135.220 / 387.340 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.269 | 860.143 | 1616.601 | 1716.799 | 135.755 / 387.340 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 867.747 | 1.127 | 1.213 | 1.608 | 99.905 / 387.340 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1699.967 | 5.785 | 6.780 | 9.089 | 198.917 / 387.340 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1704.009 | 28.684 | 31.033 | 41.125 | 200.732 / 387.340 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1693.955 | 57.016 | 60.768 | 94.832 | 199.888 / 387.340 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2362.991 | 23.206 | 36.620 | 48.143 | 384.556 / 629.840 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2330.114 | 40.435 | 81.373 | 97.768 | 385.215 / 633.914 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 141.761 | 243.428 | 829.668 | 976.447 | 242.696 / 635.336 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 131.605 | 360.847 | 1288.413 | 1432.659 | 249.610 / 637.316 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1567.529 | 34.116 | 49.635 | 62.076 | 215.436 / 637.652 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2395.542 | 41.554 | 54.753 | 77.374 | 388.417 / 637.973 | possible-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.556 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.478 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.545 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.706 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.589 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.048 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.108 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.084 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.026 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.598 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.598 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.332 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.384 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.058 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.400 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.576 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.493 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.737 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.514 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.597 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.321 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.573 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.912 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.343 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.195 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.164 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.208 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.056 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.136 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.055 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.101 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 636.605 | 156.425 | 171.014 | 173.686 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1091.355 | 180.370 | 194.897 | 198.643 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: +3.3%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -3.2%, p95_ms: -4.0%, p99_ms: -3.8%, requests_per_second: +4.0%, rss_bytes: +0.9% |
| cache_miss | stable | completed: -1.1%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -0.3%, p95_ms: +9.9%, p99_ms: +14.6%, requests_per_second: -1.2%, rss_bytes: +0.9% |
| cache_miss | stable | completed: +2.6%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -2.8%, p95_ms: +6.4%, p99_ms: -0.1%, requests_per_second: +2.6%, rss_bytes: +0.9% |
| health_live | stable | completed: +0.8%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: -2.1%, p95_ms: -2.8%, p99_ms: -4.5%, requests_per_second: +3.0%, rss_bytes: +0.8% |
| health_live | stable | completed: -0.1%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -0.8%, p95_ms: -16.0%, p99_ms: -19.2%, requests_per_second: +3.2%, rss_bytes: +0.8% |
| health_live | stable | completed: +1.4%, cpu_percent: -1.2%, duration_seconds: +0.1%, p50_ms: -3.1%, p95_ms: +3.8%, p99_ms: +11.7%, requests_per_second: +1.3%, rss_bytes: +0.8% |
| health_live | stable | completed: +2.8%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -3.5%, p95_ms: -6.9%, p99_ms: -1.1%, requests_per_second: +2.7%, rss_bytes: +0.8% |
| home | confirmed-regression | completed: -16.3%, cpu_percent: -0.6%, duration_seconds: +0.2%, p50_ms: +20.3%, p95_ms: +16.9%, p99_ms: +27.1%, requests_per_second: -16.5%, rss_bytes: +0.8% |
| home | confirmed-regression | completed: -15.3%, cpu_percent: -2.5%, duration_seconds: +0.0%, p50_ms: +17.5%, p95_ms: +18.4%, p99_ms: +14.3%, requests_per_second: -15.4%, rss_bytes: +0.8% |
| home | confirmed-regression | completed: -28.6%, cpu_percent: -2.0%, duration_seconds: +0.1%, p50_ms: +26.7%, p95_ms: +33.2%, p99_ms: +31.8%, requests_per_second: -28.6%, rss_bytes: +0.8% |
| categories | stable | completed: +1.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: -1.5%, p99_ms: -9.0%, requests_per_second: +1.3%, rss_bytes: +0.8% |
| categories | stable | completed: +1.2%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -1.5%, p95_ms: -3.8%, p99_ms: -3.5%, requests_per_second: +1.2%, rss_bytes: +0.8% |
| categories | stable | completed: +1.3%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +4.4%, p95_ms: +1.3%, p99_ms: -4.5%, requests_per_second: +1.3%, rss_bytes: +0.8% |
| category | stable | completed: +1.4%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -0.9%, p95_ms: -0.6%, p99_ms: +0.9%, requests_per_second: +1.4%, rss_bytes: +0.8% |
| category | possible-regression | completed: -0.8%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +13.8%, p95_ms: +12.5%, p99_ms: +4.3%, requests_per_second: -0.8%, rss_bytes: +0.8% |
| category | stable | completed: -0.8%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: +1.2%, p95_ms: -1.6%, p99_ms: -4.6%, requests_per_second: -0.7%, rss_bytes: +0.8% |
| thread | stable | completed: +0.7%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -0.8%, p95_ms: +0.1%, p99_ms: -1.9%, requests_per_second: +0.8%, rss_bytes: +0.8% |
| thread | possible-regression | completed: +0.7%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: +19.3%, p99_ms: +5.9%, requests_per_second: +0.7%, rss_bytes: +0.8% |
| thread | improvement | completed: +0.7%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +0.7%, p95_ms: -4.8%, p99_ms: -16.3%, requests_per_second: +0.7%, rss_bytes: +0.8% |
| thread | stable | completed: -3.0%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +3.2%, p95_ms: +4.0%, p99_ms: +5.1%, requests_per_second: -3.0%, rss_bytes: +0.8% |
| search | stable | completed: -5.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +4.7%, p95_ms: +9.9%, p99_ms: -8.7%, requests_per_second: -5.5%, rss_bytes: +0.8% |
| search | stable | completed: +3.9%, cpu_percent: -1.1%, duration_seconds: -0.1%, p50_ms: -9.2%, p95_ms: +2.1%, p99_ms: -3.2%, requests_per_second: +3.8%, rss_bytes: +0.8% |
| search | confirmed-regression | completed: -18.0%, cpu_percent: +1.1%, duration_seconds: +0.0%, p50_ms: +17.0%, p95_ms: +13.1%, p99_ms: +14.6%, requests_per_second: -18.0%, rss_bytes: +0.8% |
| search | possible-regression | completed: +100.0%, cpu_percent: +92.1%, duration_seconds: +0.0%, p50_ms: +21.9%, p95_ms: +25.8%, p99_ms: +25.8%, requests_per_second: +99.9%, rss_bytes: +0.3% |
| cache_hit | improvement | completed: +1.1%, cpu_percent: -15.6%, duration_seconds: -0.0%, p50_ms: +1.2%, p95_ms: -9.5%, p99_ms: -22.7%, requests_per_second: +1.2%, rss_bytes: +0.1% |
| cache_hit | confirmed-regression | completed: -1.0%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +3.6%, p99_ms: +22.4%, requests_per_second: -0.6%, rss_bytes: +0.1% |
| cache_hit | possible-regression | completed: -1.7%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: +10.6%, p99_ms: +8.1%, requests_per_second: -1.8%, rss_bytes: +0.1% |
| cache_hit | stable | completed: -2.9%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +2.8%, p95_ms: +4.0%, p99_ms: -1.0%, requests_per_second: -2.8%, rss_bytes: +0.1% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +0.0%, duration_seconds: +7.1%, p50_ms: +6.9%, p95_ms: -3.1%, p99_ms: -0.5%, requests_per_second: -5.9%, rss_bytes: +0.1% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -8.9%, duration_seconds: +10.6%, p50_ms: +11.6%, p95_ms: +8.2%, p99_ms: -0.4%, requests_per_second: -9.6%, rss_bytes: +0.1% |
| thread | stable | completed: -0.9%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: -7.5%, p95_ms: -0.6%, p99_ms: +9.3%, requests_per_second: +0.7%, rss_bytes: +0.9% |
| thread | stable | completed: -1.2%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +8.0%, p95_ms: -9.8%, p99_ms: -4.5%, requests_per_second: -1.3%, rss_bytes: +0.8% |
| search | stable | completed: -9.9%, cpu_percent: -18.4%, duration_seconds: +0.0%, p50_ms: +27.4%, p95_ms: -6.5%, p99_ms: -4.9%, requests_per_second: -9.9%, rss_bytes: +0.8% |
| search | improvement | completed: -6.0%, cpu_percent: -2.3%, duration_seconds: +0.3%, p50_ms: -8.1%, p95_ms: -17.7%, p99_ms: -20.8%, requests_per_second: -5.9%, rss_bytes: +0.8% |
| cache_hit | improvement | completed: +76.6%, cpu_percent: +53.3%, duration_seconds: +0.2%, p50_ms: -43.1%, p95_ms: -42.8%, p99_ms: -55.6%, requests_per_second: +76.1%, rss_bytes: +0.8% |
| cache_hit | stable | completed: +2.8%, cpu_percent: +7.2%, duration_seconds: -0.1%, p50_ms: +2.1%, p95_ms: -16.0%, p99_ms: -31.2%, requests_per_second: +2.9%, rss_bytes: +0.8% |
| cache_miss | stable | completed: -1.7%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: +15.4%, p99_ms: +14.6%, requests_per_second: -1.8%, rss_bytes: +0.9% |
| cache_miss | stable | completed: -0.4%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: -0.4%, p95_ms: -0.5%, p99_ms: +2.7%, requests_per_second: -0.3%, rss_bytes: +0.9% |
| cache_miss | stable | completed: -3.2%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -0.0%, p95_ms: -0.5%, p99_ms: +2.5%, requests_per_second: -3.3%, rss_bytes: +0.9% |
| health_live | possible-regression | completed: -5.3%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +1.1%, p95_ms: +0.9%, p99_ms: +30.8%, requests_per_second: -0.9%, rss_bytes: +0.9% |
| health_live | stable | completed: -1.1%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +3.2%, p95_ms: +1.9%, p99_ms: -4.7%, requests_per_second: -3.0%, rss_bytes: +0.9% |
| health_live | stable | completed: -0.6%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +0.2%, p95_ms: +2.5%, p99_ms: +8.0%, requests_per_second: -0.7%, rss_bytes: +0.9% |
| health_live | stable | completed: -1.4%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +2.3%, p95_ms: -6.4%, p99_ms: +4.3%, requests_per_second: -1.4%, rss_bytes: +0.9% |
| home | confirmed-regression | completed: -26.2%, cpu_percent: -1.8%, duration_seconds: +0.1%, p50_ms: +36.6%, p95_ms: +34.5%, p99_ms: +29.7%, requests_per_second: -26.0%, rss_bytes: +0.9% |
| home | confirmed-regression | completed: -21.9%, cpu_percent: -1.2%, duration_seconds: +0.0%, p50_ms: +29.2%, p95_ms: +63.1%, p99_ms: +69.5%, requests_per_second: -21.9%, rss_bytes: +0.9% |
| home | confirmed-regression | completed: -28.7%, cpu_percent: -2.2%, duration_seconds: -0.0%, p50_ms: +36.4%, p95_ms: +51.6%, p99_ms: +39.1%, requests_per_second: -28.6%, rss_bytes: +0.9% |
| categories | possible-regression | completed: -3.6%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +3.8%, p95_ms: +2.2%, p99_ms: +32.9%, requests_per_second: -3.6%, rss_bytes: +0.9% |
| categories | stable | completed: +4.1%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.4%, p95_ms: +3.7%, p99_ms: +21.8%, requests_per_second: -0.7%, rss_bytes: +0.9% |
| categories | stable | completed: +4.1%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -3.7%, p95_ms: -11.3%, p99_ms: -6.7%, requests_per_second: +4.5%, rss_bytes: +0.9% |
| category | possible-regression | completed: -1.9%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +3.3%, p95_ms: +1.5%, p99_ms: +25.6%, requests_per_second: -1.9%, rss_bytes: +0.9% |
| category | stable | completed: -0.6%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: -0.9%, p95_ms: +2.6%, p99_ms: +19.6%, requests_per_second: +0.3%, rss_bytes: +0.9% |
| category | stable | completed: -0.9%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +0.8%, p95_ms: +0.5%, p99_ms: +4.0%, requests_per_second: -0.9%, rss_bytes: +0.9% |
| thread | stable | completed: +1.2%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +0.0%, p95_ms: -2.0%, p99_ms: +64.1%, requests_per_second: +1.2%, rss_bytes: +0.9% |
| thread | possible-regression | completed: -1.6%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: -0.1%, p95_ms: +17.7%, p99_ms: +5.1%, requests_per_second: -1.5%, rss_bytes: +0.9% |
| thread | stable | completed: +0.0%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +0.1%, p95_ms: +1.6%, p99_ms: +6.4%, requests_per_second: -0.1%, rss_bytes: +0.9% |
| thread | possible-regression | completed: -0.1%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: +11.8%, p99_ms: -1.3%, requests_per_second: -0.0%, rss_bytes: +0.9% |
| search | possible-regression | completed: -15.6%, cpu_percent: +4.4%, duration_seconds: +0.0%, p50_ms: +19.9%, p95_ms: +8.7%, p99_ms: +8.6%, requests_per_second: -15.7%, rss_bytes: +0.8% |
| search | possible-regression | completed: -3.2%, cpu_percent: +2.6%, duration_seconds: +0.1%, p50_ms: +12.9%, p95_ms: -4.1%, p99_ms: +13.7%, requests_per_second: -3.3%, rss_bytes: +0.9% |
| search | confirmed-regression | completed: -19.7%, cpu_percent: +2.5%, duration_seconds: +0.0%, p50_ms: +1.3%, p95_ms: +15.1%, p99_ms: +11.6%, requests_per_second: -19.6%, rss_bytes: +0.9% |
| search | stable | completed: -0.5%, cpu_percent: +1.8%, duration_seconds: -0.0%, p50_ms: +13.0%, p95_ms: +14.1%, p99_ms: +16.2%, requests_per_second: -0.4%, rss_bytes: +0.9% |
| cache_hit | stable | completed: +0.2%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -1.2%, p95_ms: -0.8%, p99_ms: +19.3%, requests_per_second: +0.6%, rss_bytes: +0.9% |
| cache_hit | possible-regression | completed: +0.3%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +0.2%, p95_ms: +11.5%, p99_ms: +13.6%, requests_per_second: -1.3%, rss_bytes: +0.9% |
| cache_hit | stable | completed: -1.4%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +0.8%, p95_ms: -2.1%, p99_ms: -4.2%, requests_per_second: -1.4%, rss_bytes: +0.9% |
| cache_hit | stable | completed: +0.1%, cpu_percent: -1.0%, duration_seconds: +0.0%, p50_ms: -1.2%, p95_ms: -1.7%, p99_ms: +1.2%, requests_per_second: +0.2%, rss_bytes: +0.9% |
| thread | confirmed-regression | completed: -4.5%, cpu_percent: -0.3%, duration_seconds: +0.3%, p50_ms: +39.5%, p95_ms: +16.1%, p99_ms: +16.2%, requests_per_second: -4.5%, rss_bytes: +0.9% |
| thread | stable | completed: -3.0%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +5.2%, p95_ms: +29.4%, p99_ms: +4.5%, requests_per_second: -3.3%, rss_bytes: +0.9% |
| search | possible-regression | completed: -5.9%, cpu_percent: +0.9%, duration_seconds: +0.2%, p50_ms: +8.7%, p95_ms: +11.3%, p99_ms: -2.9%, requests_per_second: -6.1%, rss_bytes: +0.9% |
| search | stable | completed: -8.0%, cpu_percent: +2.3%, duration_seconds: +0.1%, p50_ms: -41.6%, p95_ms: +0.9%, p99_ms: -4.9%, requests_per_second: -8.1%, rss_bytes: +1.1% |
| cache_hit | stable | completed: -21.7%, cpu_percent: -28.5%, duration_seconds: +0.1%, p50_ms: +46.2%, p95_ms: +18.7%, p99_ms: +15.7%, requests_per_second: -25.3%, rss_bytes: +1.2% |
| cache_hit | possible-regression | completed: -4.2%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +10.3%, p95_ms: +19.0%, p99_ms: +17.4%, requests_per_second: -4.4%, rss_bytes: +1.2% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +11.0% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +12.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +13.1% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +35.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -15.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -19.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.7% |
| sql-plan-readers | possible-regression | sql_execution_ms: +16.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -7.1% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +16.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.5% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +21.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.9% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +17.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +36.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.2% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +15.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +15.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +9.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.4% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -18.7% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.1% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +12.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +43.2% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -9.8% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +4.5%, messages_per_second: -4.3%, p50_ms: +4.6%, p95_ms: +5.0%, p99_ms: +2.1% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -1.4%, messages_per_second: +1.4%, p50_ms: -2.7%, p95_ms: -5.0%, p99_ms: -3.6% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -4.1%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +2.4%, p95_ms: +17.9%, p99_ms: +9.2%, requests_per_second: -4.2%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.9%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: +3.6%, p95_ms: +4.4%, p99_ms: +17.8%, requests_per_second: -0.9%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -5.7%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +3.5%, p95_ms: -4.7%, p99_ms: +4.1%, requests_per_second: -5.7%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -2.3%, cpu_percent: +0.1%, duration_seconds: -4.7%, p50_ms: -2.1%, p95_ms: +0.4%, p99_ms: +33.7%, requests_per_second: +0.4%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.5%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +1.4%, p95_ms: +6.5%, p99_ms: +5.9%, requests_per_second: -1.4%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -2.0%, cpu_percent: +1.1%, duration_seconds: -0.0%, p50_ms: +2.5%, p95_ms: -2.6%, p99_ms: +1.3%, requests_per_second: -2.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -3.6%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: +4.6%, p95_ms: -1.2%, p99_ms: +5.6%, requests_per_second: -3.6%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -12.2%, cpu_percent: -0.6%, duration_seconds: -0.1%, p50_ms: +14.1%, p95_ms: +8.8%, p99_ms: +14.0%, requests_per_second: -12.0%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -7.4%, cpu_percent: +0.8%, duration_seconds: -0.0%, p50_ms: +9.8%, p95_ms: +40.8%, p99_ms: +59.5%, requests_per_second: -7.4%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: +7.2%, p95_ms: +9.5%, p99_ms: +4.8%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -2.4%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +2.5%, p95_ms: +1.3%, p99_ms: +30.5%, requests_per_second: -2.5%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +3.1%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +0.8%, p95_ms: +6.0%, p99_ms: +33.2%, requests_per_second: -1.6%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.5%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: -0.8%, p95_ms: +7.1%, p99_ms: +20.7%, requests_per_second: -1.4%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.6%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +0.3%, p95_ms: -0.2%, p99_ms: +12.5%, requests_per_second: -0.6%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +1.2%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -13.1%, p95_ms: -10.0%, p99_ms: +22.2%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: +1.9%, p99_ms: +12.0%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.7%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -0.3%, p95_ms: -2.4%, p99_ms: +52.3%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -1.3%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -0.9%, p95_ms: +2.2%, p99_ms: +22.9%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -1.0%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: +0.5%, p99_ms: +27.4%, requests_per_second: -1.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.5%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -3.8%, p95_ms: +6.7%, p99_ms: -1.0%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -13.8%, cpu_percent: +5.3%, duration_seconds: +0.0%, p50_ms: +18.3%, p95_ms: +8.5%, p99_ms: +13.0%, requests_per_second: -13.9%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -11.2%, cpu_percent: +3.0%, duration_seconds: +0.1%, p50_ms: +22.0%, p95_ms: +16.1%, p99_ms: +30.9%, requests_per_second: -11.1%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.0%, cpu_percent: +1.1%, duration_seconds: -0.0%, p50_ms: -8.6%, p95_ms: -1.8%, p99_ms: -2.1%, requests_per_second: +0.0%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: -7.1%, p95_ms: -6.3%, p99_ms: -4.2%, requests_per_second: -0.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: +1.5%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -2.6%, p95_ms: -0.7%, p99_ms: +24.1%, requests_per_second: +1.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.5%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +0.4%, p95_ms: +8.8%, p99_ms: +13.7%, requests_per_second: -0.6%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.8%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +1.4%, p95_ms: -5.2%, p99_ms: +6.2%, requests_per_second: -0.7%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.9%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -3.4%, p95_ms: -4.7%, p99_ms: +3.2%, requests_per_second: +2.9%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -3.8%, cpu_percent: -1.1%, duration_seconds: +0.1%, p50_ms: +24.1%, p95_ms: +25.2%, p99_ms: +14.3%, requests_per_second: -3.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -1.5%, cpu_percent: -0.3%, duration_seconds: +0.2%, p50_ms: -5.1%, p95_ms: +49.4%, p99_ms: +40.3%, requests_per_second: -1.7%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.7%, cpu_percent: +25.0%, duration_seconds: +0.2%, p50_ms: -10.2%, p95_ms: +35.1%, p99_ms: +28.5%, requests_per_second: +0.5%, rss_bytes: +0.5% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -6.4%, cpu_percent: +5.0%, duration_seconds: -0.0%, p50_ms: -30.7%, p95_ms: +13.1%, p99_ms: +9.2%, requests_per_second: -6.5%, rss_bytes: +0.6% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +9.8%, cpu_percent: +7.2%, duration_seconds: -0.0%, p50_ms: +6.4%, p95_ms: +21.5%, p99_ms: +13.9%, requests_per_second: +5.0%, rss_bytes: +0.7% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.7%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -2.8%, p95_ms: -8.9%, p99_ms: +9.5%, requests_per_second: -0.8%, rss_bytes: +0.7% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +44.6%, cpu_percent: +94.0%, duration_seconds: +0.2%, p50_ms: -35.9%, p95_ms: -5.6%, p99_ms: +13.9%, requests_per_second: +44.4%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +46.5%, cpu_percent: +91.5%, duration_seconds: +0.1%, p50_ms: -29.8%, p95_ms: -15.7%, p99_ms: -29.6%, requests_per_second: +46.3%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | improvement | completed: +41.5%, cpu_percent: +45.1%, duration_seconds: +0.1%, p50_ms: -38.9%, p95_ms: -21.1%, p99_ms: -11.0%, requests_per_second: +41.4%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +41.5%, cpu_percent: +74.4%, duration_seconds: +0.4%, p50_ms: -43.7%, p95_ms: -34.0%, p99_ms: -26.8%, requests_per_second: +41.2%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: -12.8%, cpu_percent: -0.1%, duration_seconds: +0.2%, p50_ms: +13.4%, p95_ms: +24.8%, p99_ms: +40.7%, requests_per_second: -13.0%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +46.8%, cpu_percent: +94.3%, duration_seconds: +0.1%, p50_ms: -27.6%, p95_ms: -5.8%, p99_ms: -23.1%, requests_per_second: +46.6%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 50 | improvement | completed: +40.6%, cpu_percent: +91.6%, duration_seconds: +0.3%, p50_ms: -20.9%, p95_ms: +17.6%, p99_ms: +2.2%, requests_per_second: +40.9%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +40.8%, cpu_percent: +91.9%, duration_seconds: +0.3%, p50_ms: -30.8%, p95_ms: +18.0%, p99_ms: -0.2%, requests_per_second: +40.2%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | possible-regression | completed: +42.5%, cpu_percent: +79.5%, duration_seconds: +0.3%, p50_ms: -40.0%, p95_ms: +8.5%, p99_ms: +16.8%, requests_per_second: +42.1%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +33.2%, cpu_percent: +83.9%, duration_seconds: +0.4%, p50_ms: -58.0%, p95_ms: -20.3%, p99_ms: -16.6%, requests_per_second: +32.6%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -3.5%, cpu_percent: +7.3%, duration_seconds: +0.2%, p50_ms: +18.9%, p95_ms: +59.9%, p99_ms: +50.9%, requests_per_second: -8.0%, rss_bytes: +64.6% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +41.7%, cpu_percent: +94.3%, duration_seconds: +0.1%, p50_ms: -27.1%, p95_ms: -9.9%, p99_ms: -18.4%, requests_per_second: +41.4%, rss_bytes: +64.7% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38783394023)
