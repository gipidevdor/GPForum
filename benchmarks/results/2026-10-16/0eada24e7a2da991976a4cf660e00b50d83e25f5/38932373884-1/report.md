# GPForum continuous performance evidence

Commit: `0eada24e7a2da991976a4cf660e00b50d83e25f5` · mode: **main** · status: **ok**
Run: 38932373884 / attempt 1 · 2026-10-16T16:30:12.435482+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 4d616825d05990e1d868eab74f1ae0ae29bb55fd

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 298.087 | 3.274 | 3.835 | 5.253 | 99.571 / 378.746 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 596.823 | 16.288 | 18.533 | 27.950 | 199.672 / 378.809 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 596.800 | 82.331 | 89.737 | 141.653 | 201.337 / 380.590 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1702.879 | 0.576 | 0.628 | 0.673 | 99.529 / 378.773 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3436.236 | 2.954 | 3.774 | 4.134 | 199.461 / 378.773 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3619.934 | 13.692 | 14.544 | 17.415 | 199.922 / 379.402 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3610.779 | 27.533 | 28.642 | 35.229 | 200.411 / 380.680 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 122.870 | 7.876 | 9.640 | 10.111 | 84.855 / 381.273 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 183.335 | 52.957 | 73.871 | 91.538 | 170.603 / 381.859 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 197.962 | 224.836 | 377.935 | 433.834 | 170.381 / 384.242 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1269.921 | 0.769 | 0.841 | 1.096 | 99.029 / 384.242 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2524.311 | 3.920 | 4.171 | 5.641 | 198.959 / 384.242 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2564.600 | 19.123 | 20.279 | 26.126 | 199.888 / 384.242 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1248.460 | 0.790 | 0.847 | 0.941 | 100.466 / 384.320 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2468.140 | 4.071 | 4.454 | 5.467 | 198.493 / 384.352 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2558.874 | 19.198 | 20.525 | 25.396 | 200.407 / 384.352 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1240.430 | 0.802 | 0.858 | 0.892 | 99.933 / 384.461 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2444.741 | 4.064 | 4.345 | 6.407 | 198.912 / 384.477 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2528.639 | 19.481 | 20.799 | 23.356 | 200.393 / 384.477 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2520.402 | 38.678 | 41.550 | 58.620 | 200.843 / 387.141 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 64.471 | 10.775 | 110.767 | 153.532 | 47.762 / 387.527 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 139.272 | 65.494 | 142.751 | 159.206 | 108.421 / 387.855 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 111.332 | 329.793 | 723.232 | 788.032 | 93.556 / 387.855 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.819 | 759.409 | 1358.060 | 1414.959 | 91.154 / 387.855 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1278.716 | 0.770 | 0.830 | 0.875 | 99.555 / 387.855 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2527.821 | 3.924 | 4.061 | 5.748 | 199.159 / 387.855 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2583.255 | 19.154 | 20.213 | 23.070 | 200.386 / 387.855 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2613.082 | 37.698 | 38.630 | 56.612 | 201.430 / 387.855 | improvement |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 2032.154 | 4.425 | 6.800 | 9.152 | 29.742 / 387.855 | improvement |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1285.248 | 6.813 | 11.105 | 12.648 | 34.937 / 388.137 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2952.218 | 16.191 | 27.170 | 32.853 | 298.210 / 631.027 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 3385.875 | 24.337 | 45.771 | 52.696 | 386.974 / 634.684 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 125.155 | 237.422 | 934.085 | 1138.245 | 152.196 / 636.562 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 149.474 | 372.206 | 1519.266 | 1784.027 | 186.243 / 638.023 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2842.250 | 14.276 | 35.821 | 37.185 | 301.081 / 638.098 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 3504.443 | 26.230 | 47.477 | 53.768 | 386.620 / 638.098 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 302.926 | 3.256 | 3.474 | 4.012 | 99.993 / 380.051 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 604.806 | 16.345 | 22.821 | 32.490 | 200.426 / 380.113 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 591.830 | 82.629 | 94.094 | 153.363 | 201.881 / 382.000 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1779.719 | 0.552 | 0.607 | 0.641 | 99.479 / 380.031 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3472.278 | 2.851 | 3.051 | 4.104 | 199.544 / 380.031 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3507.076 | 13.954 | 14.898 | 20.746 | 199.965 / 380.742 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3532.183 | 27.924 | 29.611 | 40.031 | 200.932 / 382.082 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 119.787 | 7.994 | 9.400 | 9.967 | 85.625 / 382.422 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 228.319 | 42.124 | 62.172 | 95.703 | 171.077 / 383.227 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 210.012 | 217.605 | 371.217 | 440.832 | 171.177 / 385.629 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1306.701 | 0.754 | 0.814 | 0.856 | 99.498 / 385.629 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2504.957 | 4.123 | 5.337 | 7.215 | 199.460 / 385.629 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2587.919 | 19.002 | 19.978 | 30.461 | 198.979 / 385.629 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1252.579 | 0.778 | 0.844 | 1.047 | 99.497 / 385.668 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2458.768 | 4.004 | 4.432 | 6.812 | 198.918 / 385.668 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2534.973 | 19.696 | 21.298 | 33.303 | 200.235 / 385.668 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1252.345 | 0.787 | 0.846 | 0.888 | 99.554 / 385.793 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2393.972 | 4.097 | 5.323 | 7.177 | 198.918 / 385.793 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2463.604 | 20.234 | 22.104 | 34.094 | 199.489 / 385.793 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2463.651 | 39.770 | 45.070 | 68.502 | 200.281 / 388.543 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 79.393 | 10.158 | 25.299 | 51.316 | 59.250 / 389.129 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 130.476 | 60.317 | 152.984 | 229.587 | 101.392 / 389.242 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 98.822 | 456.726 | 614.512 | 752.308 | 93.543 / 389.242 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.802 | 784.552 | 1405.244 | 1576.060 | 97.034 / 389.242 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1294.952 | 0.757 | 0.826 | 1.023 | 102.388 / 389.242 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2525.885 | 3.970 | 4.878 | 7.002 | 198.950 / 389.242 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2545.801 | 19.199 | 21.410 | 30.851 | 199.756 / 389.242 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2485.584 | 39.368 | 43.114 | 63.112 | 201.451 / 389.242 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3451.171 | 13.813 | 24.897 | 37.749 | 382.859 / 632.461 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3454.722 | 28.331 | 43.633 | 50.985 | 387.875 / 636.660 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 172.353 | 191.080 | 709.910 | 915.508 | 185.677 / 638.543 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 160.339 | 360.475 | 967.295 | 1092.135 | 204.940 / 639.703 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2903.155 | 21.120 | 26.968 | 35.993 | 305.224 / 639.703 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3366.684 | 26.525 | 52.564 | 71.606 | 387.931 / 639.703 | improvement |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.420 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.344 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.379 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.470 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.080 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.263 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.871 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.102 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.079 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.023 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.413 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.474 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.225 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.304 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.077 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.049 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.041 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.287 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.374 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.384 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.536 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.390 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.486 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.226 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.279 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.373 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.339 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.183 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.139 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.176 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.045 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.014 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.079 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.099 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.055 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.069 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 456.656 | 184.479 | 491.994 | 751.566 | — / — | confirmed-regression |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 605.690 | 254.094 | 759.316 | 761.156 | — / — | confirmed-regression |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +27.0%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: -22.9%, p95_ms: -12.6%, p99_ms: +6.7%, requests_per_second: +27.5%, rss_bytes: +0.1% |
| cache_miss | improvement | completed: +32.0%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -23.9%, p95_ms: -35.5%, p99_ms: -17.4%, requests_per_second: +32.0%, rss_bytes: +0.1% |
| cache_miss | improvement | completed: +33.1%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: -24.9%, p95_ms: -37.2%, p99_ms: -28.2%, requests_per_second: +33.2%, rss_bytes: +0.1% |
| health_live | improvement | completed: +25.4%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -20.4%, p95_ms: -20.9%, p99_ms: -32.4%, requests_per_second: +25.3%, rss_bytes: +0.1% |
| health_live | improvement | completed: +32.8%, cpu_percent: +0.1%, duration_seconds: +4.8%, p50_ms: -19.4%, p95_ms: -1.8%, p99_ms: -5.4%, requests_per_second: +26.7%, rss_bytes: +0.1% |
| health_live | improvement | completed: +31.4%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -22.9%, p95_ms: -26.0%, p99_ms: -20.4%, requests_per_second: +31.3%, rss_bytes: +0.1% |
| health_live | improvement | completed: +33.0%, cpu_percent: +0.3%, duration_seconds: -0.2%, p50_ms: -25.3%, p95_ms: -30.6%, p99_ms: -36.9%, requests_per_second: +33.2%, rss_bytes: +0.0% |
| home | improvement | completed: +27.6%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: -22.2%, p95_ms: -19.6%, p99_ms: -23.1%, requests_per_second: +27.1%, rss_bytes: +0.1% |
| home | stable | completed: +13.6%, cpu_percent: -0.8%, duration_seconds: +4.8%, p50_ms: -8.6%, p95_ms: -5.8%, p99_ms: -15.8%, requests_per_second: +8.3%, rss_bytes: +0.1% |
| home | improvement | completed: +22.5%, cpu_percent: -0.6%, duration_seconds: -0.1%, p50_ms: -21.6%, p95_ms: -27.3%, p99_ms: -26.9%, requests_per_second: +22.6%, rss_bytes: +0.1% |
| categories | improvement | completed: +23.9%, cpu_percent: -0.5%, duration_seconds: -4.7%, p50_ms: -22.6%, p95_ms: -20.5%, p99_ms: -3.0%, requests_per_second: +27.8%, rss_bytes: +0.1% |
| categories | improvement | completed: +33.8%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -19.5%, p95_ms: -35.1%, p99_ms: -19.0%, requests_per_second: +29.4%, rss_bytes: +0.1% |
| categories | improvement | completed: +29.6%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -23.6%, p95_ms: -24.7%, p99_ms: -19.9%, requests_per_second: +29.7%, rss_bytes: +0.1% |
| category | improvement | completed: +34.8%, cpu_percent: +0.9%, duration_seconds: +4.9%, p50_ms: -22.2%, p95_ms: -22.7%, p99_ms: -17.4%, requests_per_second: +28.4%, rss_bytes: +0.1% |
| category | improvement | completed: +33.7%, cpu_percent: -0.5%, duration_seconds: +4.8%, p50_ms: -22.8%, p95_ms: -21.2%, p99_ms: -27.8%, requests_per_second: +30.6%, rss_bytes: +0.1% |
| category | improvement | completed: +32.3%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -24.0%, p95_ms: -30.6%, p99_ms: -33.9%, requests_per_second: +32.3%, rss_bytes: +0.1% |
| thread | improvement | completed: +32.1%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -23.3%, p95_ms: -23.9%, p99_ms: -31.6%, requests_per_second: +32.1%, rss_bytes: +0.1% |
| thread | improvement | completed: +30.1%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -22.5%, p95_ms: -33.8%, p99_ms: -35.6%, requests_per_second: +30.3%, rss_bytes: +0.1% |
| thread | improvement | completed: +30.8%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: -24.8%, p95_ms: -22.2%, p99_ms: -25.8%, requests_per_second: +30.6%, rss_bytes: +0.1% |
| thread | improvement | completed: +34.8%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -24.9%, p95_ms: -28.5%, p99_ms: -31.0%, requests_per_second: +34.9%, rss_bytes: +0.1% |
| search | confirmed-regression | completed: -17.3%, cpu_percent: -25.0%, duration_seconds: +0.0%, p50_ms: -15.0%, p95_ms: +704.8%, p99_ms: +961.0%, requests_per_second: -17.3%, rss_bytes: +0.0% |
| search | confirmed-regression | completed: +0.7%, cpu_percent: -15.8%, duration_seconds: +0.0%, p50_ms: -7.2%, p95_ms: +56.4%, p99_ms: +22.2%, requests_per_second: +0.7%, rss_bytes: +0.0% |
| search | stable | completed: -0.4%, cpu_percent: -29.0%, duration_seconds: -0.1%, p50_ms: -14.8%, p95_ms: +1.7%, p99_ms: -1.0%, requests_per_second: -0.4%, rss_bytes: +0.0% |
| search | stable | completed: +0.0%, cpu_percent: -29.6%, duration_seconds: -0.1%, p50_ms: +1.0%, p95_ms: -3.8%, p99_ms: -6.7%, requests_per_second: +0.1%, rss_bytes: +0.0% |
| cache_hit | improvement | completed: +36.6%, cpu_percent: -0.5%, duration_seconds: +4.9%, p50_ms: -23.5%, p95_ms: -22.9%, p99_ms: -38.6%, requests_per_second: +30.5%, rss_bytes: +0.0% |
| cache_hit | improvement | completed: +29.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -22.5%, p95_ms: -23.4%, p99_ms: -18.3%, requests_per_second: +28.9%, rss_bytes: +0.0% |
| cache_hit | improvement | completed: +29.5%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -23.9%, p95_ms: -24.5%, p99_ms: -29.2%, requests_per_second: +29.8%, rss_bytes: +0.0% |
| cache_hit | improvement | completed: +36.3%, cpu_percent: +0.9%, duration_seconds: -0.0%, p50_ms: -25.3%, p95_ms: -31.1%, p99_ms: -30.8%, requests_per_second: +36.3%, rss_bytes: +0.0% |
| health_live | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +4.4%, duration_seconds: -25.8%, p50_ms: -24.5%, p95_ms: -29.0%, p99_ms: -17.4%, requests_per_second: +34.6%, rss_bytes: +0.0% |
| thread | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -1.4%, duration_seconds: -20.4%, p50_ms: -24.6%, p95_ms: -18.2%, p99_ms: -20.1%, requests_per_second: +25.4%, rss_bytes: +0.0% |
| thread | improvement | completed: +34.0%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: -36.3%, p95_ms: -24.8%, p99_ms: -24.6%, requests_per_second: +29.1%, rss_bytes: +0.1% |
| thread | improvement | completed: +29.4%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -33.7%, p95_ms: -32.1%, p99_ms: -36.5%, requests_per_second: +29.2%, rss_bytes: -0.0% |
| search | confirmed-regression | completed: -29.7%, cpu_percent: -32.2%, duration_seconds: -0.8%, p50_ms: +1.2%, p95_ms: +26.5%, p99_ms: +25.1%, requests_per_second: -29.1%, rss_bytes: +0.0% |
| search | confirmed-regression | completed: +5.4%, cpu_percent: -21.4%, duration_seconds: +0.1%, p50_ms: -10.7%, p95_ms: +7.0%, p99_ms: +25.5%, requests_per_second: +0.7%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: +40.1%, cpu_percent: +41.2%, duration_seconds: -0.0%, p50_ms: -41.7%, p95_ms: -27.1%, p99_ms: -29.7%, requests_per_second: +40.0%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: +28.3%, cpu_percent: +1.1%, duration_seconds: +0.0%, p50_ms: -31.1%, p95_ms: -15.1%, p99_ms: -12.1%, requests_per_second: +28.4%, rss_bytes: +0.0% |
| cache_miss | improvement | completed: +28.6%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -22.2%, p95_ms: -20.8%, p99_ms: -28.7%, requests_per_second: +28.5%, rss_bytes: +0.1% |
| cache_miss | improvement | completed: +30.0%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -24.0%, p95_ms: -15.5%, p99_ms: -13.0%, requests_per_second: +29.1%, rss_bytes: +0.1% |
| cache_miss | improvement | completed: +29.9%, cpu_percent: +0.8%, duration_seconds: -0.1%, p50_ms: -22.1%, p95_ms: -26.1%, p99_ms: -22.0%, requests_per_second: +30.0%, rss_bytes: +0.1% |
| health_live | improvement | completed: +33.3%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -22.7%, p95_ms: -23.5%, p99_ms: -22.4%, requests_per_second: +33.0%, rss_bytes: +0.1% |
| health_live | improvement | completed: +36.3%, cpu_percent: +0.3%, duration_seconds: +4.8%, p50_ms: -31.4%, p95_ms: -33.7%, p99_ms: -22.7%, requests_per_second: +30.2%, rss_bytes: +0.1% |
| health_live | improvement | completed: +31.5%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -23.8%, p95_ms: -22.8%, p99_ms: -17.9%, requests_per_second: +29.3%, rss_bytes: +0.1% |
| health_live | improvement | completed: +33.2%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -23.5%, p95_ms: -25.2%, p99_ms: -30.9%, requests_per_second: +33.1%, rss_bytes: +0.1% |
| home | improvement | completed: +30.5%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -22.1%, p95_ms: -20.2%, p99_ms: -23.1%, requests_per_second: +26.1%, rss_bytes: +0.1% |
| home | improvement | completed: +33.2%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -24.1%, p95_ms: -19.4%, p99_ms: -18.2%, requests_per_second: +33.2%, rss_bytes: +0.1% |
| home | improvement | completed: +30.7%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -23.2%, p95_ms: -22.7%, p99_ms: -21.2%, requests_per_second: +30.6%, rss_bytes: +0.1% |
| categories | improvement | completed: +30.6%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -23.6%, p95_ms: -23.2%, p99_ms: -23.8%, requests_per_second: +30.6%, rss_bytes: +0.1% |
| categories | improvement | completed: +28.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -20.0%, p95_ms: -15.4%, p99_ms: -9.9%, requests_per_second: +28.4%, rss_bytes: +0.1% |
| categories | improvement | completed: +28.5%, cpu_percent: -0.9%, duration_seconds: +0.1%, p50_ms: -22.3%, p95_ms: -24.2%, p99_ms: -28.0%, requests_per_second: +28.5%, rss_bytes: +0.1% |
| category | improvement | completed: +27.7%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -22.0%, p95_ms: -23.0%, p99_ms: -23.5%, requests_per_second: +27.9%, rss_bytes: +0.1% |
| category | improvement | completed: +33.4%, cpu_percent: -0.2%, duration_seconds: +4.9%, p50_ms: -22.9%, p95_ms: -34.8%, p99_ms: -25.0%, requests_per_second: +30.3%, rss_bytes: +0.1% |
| category | improvement | completed: +34.7%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: -22.3%, p95_ms: -25.1%, p99_ms: -25.8%, requests_per_second: +34.8%, rss_bytes: +0.1% |
| thread | improvement | completed: +35.3%, cpu_percent: +0.1%, duration_seconds: +4.9%, p50_ms: -22.6%, p95_ms: -23.5%, p99_ms: -33.0%, requests_per_second: +30.0%, rss_bytes: +0.1% |
| thread | improvement | completed: +32.0%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -29.2%, p95_ms: -27.4%, p99_ms: -26.9%, requests_per_second: +30.7%, rss_bytes: +0.1% |
| thread | improvement | completed: +29.2%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -20.0%, p95_ms: -21.9%, p99_ms: -21.4%, requests_per_second: +29.3%, rss_bytes: +0.1% |
| thread | improvement | completed: +33.0%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -24.0%, p95_ms: -28.5%, p99_ms: -26.5%, requests_per_second: +33.3%, rss_bytes: +0.1% |
| search | confirmed-regression | completed: +5.3%, cpu_percent: -8.4%, duration_seconds: +0.0%, p50_ms: -21.4%, p95_ms: +68.5%, p99_ms: +210.6%, requests_per_second: +5.3%, rss_bytes: +0.1% |
| search | possible-regression | completed: -3.7%, cpu_percent: -21.5%, duration_seconds: -0.0%, p50_ms: -15.5%, p95_ms: +47.1%, p99_ms: +69.9%, requests_per_second: -3.6%, rss_bytes: +0.1% |
| search | stable | completed: -20.2%, cpu_percent: -27.2%, duration_seconds: -0.1%, p50_ms: +23.0%, p95_ms: -3.7%, p99_ms: +3.7%, requests_per_second: -20.1%, rss_bytes: +0.1% |
| search | stable | completed: +0.0%, cpu_percent: -24.8%, duration_seconds: -0.1%, p50_ms: +5.8%, p95_ms: +1.2%, p99_ms: +8.0%, requests_per_second: -0.0%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: +34.4%, cpu_percent: +3.5%, duration_seconds: +0.0%, p50_ms: -26.6%, p95_ms: -24.2%, p99_ms: -28.6%, requests_per_second: +33.9%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: +32.3%, cpu_percent: -0.4%, duration_seconds: +4.8%, p50_ms: -23.3%, p95_ms: -29.0%, p99_ms: -29.7%, requests_per_second: +29.1%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: +30.0%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: -23.6%, p95_ms: -19.4%, p99_ms: -28.7%, requests_per_second: +30.0%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: +25.2%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: -20.3%, p95_ms: -15.3%, p99_ms: -28.5%, requests_per_second: +25.1%, rss_bytes: +0.1% |
| thread | improvement | completed: +25.5%, cpu_percent: -0.7%, duration_seconds: -4.5%, p50_ms: +6.5%, p95_ms: -24.9%, p99_ms: -0.1%, requests_per_second: +29.8%, rss_bytes: +0.1% |
| thread | improvement | completed: +37.5%, cpu_percent: +3.1%, duration_seconds: +0.0%, p50_ms: -20.1%, p95_ms: -25.3%, p99_ms: -25.1%, requests_per_second: +37.6%, rss_bytes: +0.1% |
| search | stable | completed: +5.5%, cpu_percent: -19.5%, duration_seconds: -0.1%, p50_ms: -29.6%, p95_ms: +25.5%, p99_ms: +35.0%, requests_per_second: +5.5%, rss_bytes: +0.1% |
| search | improvement | completed: +1.6%, cpu_percent: -12.8%, duration_seconds: -0.0%, p50_ms: -23.2%, p95_ms: -31.4%, p99_ms: -26.1%, requests_per_second: +1.5%, rss_bytes: +0.2% |
| cache_hit | stable | completed: +50.1%, cpu_percent: +44.9%, duration_seconds: -0.1%, p50_ms: -29.7%, p95_ms: -24.1%, p99_ms: -30.1%, requests_per_second: +50.2%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: +24.2%, cpu_percent: +0.4%, duration_seconds: -0.2%, p50_ms: -23.9%, p95_ms: -21.2%, p99_ms: -8.8%, requests_per_second: +24.4%, rss_bytes: +0.1% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -22.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -19.8% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -26.3% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -21.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -16.7% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -20.6% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -18.4% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -15.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -13.2% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -17.9% |
| sql-plan-readers | improvement | sql_execution_ms: -22.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -20.4% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -18.7% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -21.9% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -24.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -34.2% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -19.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -21.2% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -24.7% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -23.4% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -24.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.8% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -14.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.2% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -30.9% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -28.5% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -22.9% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -10.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.6% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -16.3% |
| sql-plan-functions | improvement | nested_statements: +0.0%, sql_execution_ms: -12.5% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -20.4% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -21.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -17.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +15.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +9.5% |
| postgres-dispatch-noop | confirmed-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +59.1%, messages_per_second: -37.1%, p50_ms: +34.5%, p95_ms: +231.7%, p99_ms: +395.9% |
| postgres-dispatch-noop | confirmed-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +105.9%, messages_per_second: -51.4%, p50_ms: +62.5%, p95_ms: +337.9%, p99_ms: +335.2% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.7%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -0.6%, p95_ms: -9.4%, p99_ms: -23.6%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +2.0%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: +23.1%, p99_ms: +16.2%, requests_per_second: +1.3%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.8%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +0.4%, p95_ms: +4.9%, p99_ms: +8.3%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +9.5%, cpu_percent: -0.1%, duration_seconds: +4.9%, p50_ms: -4.2%, p95_ms: -3.3%, p99_ms: -4.8%, requests_per_second: +4.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.0%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -3.5%, p95_ms: -19.2%, p99_ms: -0.7%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +1.9%, p95_ms: +2.4%, p99_ms: +19.1%, requests_per_second: -3.1%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -2.1%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +1.4%, p95_ms: +3.4%, p99_ms: +13.6%, requests_per_second: -2.2%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.8%, cpu_percent: +0.9%, duration_seconds: +0.1%, p50_ms: +1.5%, p95_ms: -2.5%, p99_ms: -1.4%, requests_per_second: -2.5%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +18.7%, cpu_percent: +0.3%, duration_seconds: -4.7%, p50_ms: -20.5%, p95_ms: -15.8%, p99_ms: +4.5%, requests_per_second: +24.5%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +6.0%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: -3.2%, p95_ms: -1.8%, p99_ms: +1.6%, requests_per_second: +6.1%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +1.4%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -2.0%, p95_ms: -3.2%, p99_ms: -21.9%, requests_per_second: +2.9%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -5.4%, cpu_percent: +0.3%, duration_seconds: -4.7%, p50_ms: +5.2%, p95_ms: +28.0%, p99_ms: +27.9%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.0%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -0.6%, p95_ms: -1.5%, p99_ms: +16.6%, requests_per_second: +0.9%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -4.4%, cpu_percent: -1.0%, duration_seconds: -4.8%, p50_ms: -1.5%, p95_ms: -0.4%, p99_ms: +11.3%, requests_per_second: +0.3%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.1%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -1.6%, p95_ms: -0.5%, p99_ms: +24.6%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.8%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +2.6%, p95_ms: +3.8%, p99_ms: +31.1%, requests_per_second: -0.9%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.9%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -1.9%, p95_ms: -1.4%, p99_ms: -0.4%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +2.5%, cpu_percent: +0.0%, duration_seconds: +4.8%, p50_ms: +0.8%, p95_ms: +22.5%, p99_ms: +12.0%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -2.6%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: +3.9%, p95_ms: +6.3%, p99_ms: +46.0%, requests_per_second: -2.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | confirmed-regression | completed: -2.3%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +2.8%, p95_ms: +8.5%, p99_ms: +16.9%, requests_per_second: -2.3%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +23.3%, cpu_percent: +24.1%, duration_seconds: +0.1%, p50_ms: -5.7%, p95_ms: -77.2%, p99_ms: -66.6%, requests_per_second: +23.1%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -6.5%, cpu_percent: -6.5%, duration_seconds: -0.1%, p50_ms: -7.9%, p95_ms: +7.2%, p99_ms: +44.2%, requests_per_second: -6.3%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -11.2%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +38.5%, p95_ms: -15.0%, p99_ms: -4.5%, requests_per_second: -11.2%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: +6.5%, duration_seconds: -0.0%, p50_ms: +3.3%, p95_ms: +3.5%, p99_ms: +11.4%, requests_per_second: -0.0%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -3.2%, cpu_percent: +2.8%, duration_seconds: -4.7%, p50_ms: -1.7%, p95_ms: -0.5%, p99_ms: +16.9%, requests_per_second: +1.3%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +1.6%, cpu_percent: -0.1%, duration_seconds: +4.9%, p50_ms: +1.2%, p95_ms: +20.1%, p99_ms: +21.8%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -1.3%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +0.2%, p95_ms: +5.9%, p99_ms: +33.7%, requests_per_second: -1.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -4.9%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +4.4%, p95_ms: +11.6%, p99_ms: +11.5%, requests_per_second: -4.9%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +14.0%, cpu_percent: +28.4%, duration_seconds: +0.1%, p50_ms: -14.7%, p95_ms: -8.4%, p99_ms: +14.9%, requests_per_second: +16.9%, rss_bytes: +0.2% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.8%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +16.4%, p95_ms: -4.7%, p99_ms: -3.2%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +37.8%, cpu_percent: +22.0%, duration_seconds: +0.0%, p50_ms: -19.5%, p95_ms: -24.0%, p99_ms: -19.6%, requests_per_second: +37.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +2.5%, cpu_percent: +10.0%, duration_seconds: -0.1%, p50_ms: -3.2%, p95_ms: -36.3%, p99_ms: -38.8%, requests_per_second: +7.3%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +2.0%, cpu_percent: +1.4%, duration_seconds: -0.0%, p50_ms: +47.9%, p95_ms: -24.7%, p99_ms: -3.2%, requests_per_second: +2.1%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -3.9%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +1.1%, p95_ms: +10.7%, p99_ms: +33.2%, requests_per_second: -3.9%, rss_bytes: +0.3% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +21.3%, cpu_percent: +48.8%, duration_seconds: -0.0%, p50_ms: -16.9%, p95_ms: +30.6%, p99_ms: +40.7%, requests_per_second: +16.8%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +34.7%, cpu_percent: +92.7%, duration_seconds: +0.2%, p50_ms: -37.1%, p95_ms: +10.2%, p99_ms: -10.1%, requests_per_second: +34.3%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +12.6%, cpu_percent: +62.7%, duration_seconds: +0.1%, p50_ms: -28.0%, p95_ms: +29.2%, p99_ms: +44.4%, requests_per_second: +12.4%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +57.0%, cpu_percent: +104.3%, duration_seconds: +0.3%, p50_ms: -51.0%, p95_ms: +11.9%, p99_ms: +26.1%, requests_per_second: +49.7%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +10.2%, cpu_percent: +50.3%, duration_seconds: +0.0%, p50_ms: -25.5%, p95_ms: +77.2%, p99_ms: +61.2%, requests_per_second: +10.0%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +34.1%, cpu_percent: +91.9%, duration_seconds: +0.1%, p50_ms: -30.4%, p95_ms: +22.9%, p99_ms: -5.0%, requests_per_second: +34.1%, rss_bytes: +64.5% |
| thread | workers=4 | 2 | 50 | improvement | completed: +41.9%, cpu_percent: +91.9%, duration_seconds: +0.1%, p50_ms: -31.7%, p95_ms: +12.6%, p99_ms: +10.7%, requests_per_second: +40.1%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | improvement | completed: +40.4%, cpu_percent: +93.7%, duration_seconds: +0.2%, p50_ms: -28.8%, p95_ms: -3.2%, p99_ms: -25.6%, requests_per_second: +40.2%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +74.7%, cpu_percent: +98.5%, duration_seconds: +0.1%, p50_ms: -58.2%, p95_ms: +15.5%, p99_ms: +21.7%, requests_per_second: +74.4%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +61.0%, cpu_percent: +111.2%, duration_seconds: +0.2%, p50_ms: -54.1%, p95_ms: -31.2%, p99_ms: -30.7%, requests_per_second: +60.7%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +14.0%, cpu_percent: +52.8%, duration_seconds: -0.0%, p50_ms: +10.0%, p95_ms: +26.0%, p99_ms: +16.7%, requests_per_second: +14.0%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +35.4%, cpu_percent: +92.6%, duration_seconds: +0.0%, p50_ms: -32.6%, p95_ms: +21.9%, p99_ms: +13.5%, requests_per_second: +35.4%, rss_bytes: +64.3% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38932373884)
