# GPForum continuous performance evidence

Commit: `824de58c83d022e37243407d71aa38e9390a47b9` · mode: **main** · status: **ok**
Run: 38940661243 / attempt 1 · 2026-10-16T17:34:29.297607+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 0eada24e7a2da991976a4cf660e00b50d83e25f5

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 233.439 | 4.256 | 4.379 | 4.784 | 99.939 / 379.805 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 462.079 | 21.261 | 22.063 | 29.495 | 200.916 / 379.906 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 451.933 | 108.322 | 124.913 | 193.506 | 201.371 / 381.699 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1319.493 | 0.754 | 0.810 | 0.855 | 99.488 / 379.684 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2664.092 | 3.696 | 3.881 | 5.226 | 199.345 / 379.684 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2781.166 | 17.856 | 18.411 | 21.580 | 199.922 / 380.293 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2740.362 | 35.758 | 39.121 | 53.205 | 199.431 / 381.523 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 98.932 | 9.971 | 10.660 | 12.543 | 85.559 / 381.906 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 175.656 | 53.712 | 69.761 | 96.163 | 171.578 / 382.730 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 169.348 | 277.253 | 450.181 | 532.299 | 171.283 / 385.027 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 961.199 | 1.046 | 1.087 | 1.138 | 99.514 / 385.027 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1934.373 | 5.107 | 5.500 | 7.686 | 199.452 / 385.027 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2034.671 | 24.677 | 26.116 | 31.272 | 199.930 / 385.027 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 963.813 | 1.016 | 1.108 | 1.454 | 99.510 / 385.184 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1916.248 | 5.180 | 5.527 | 7.110 | 198.960 / 385.184 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1971.924 | 24.918 | 26.428 | 32.894 | 199.639 / 385.184 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 975.295 | 1.016 | 1.099 | 1.134 | 99.572 / 385.309 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1918.559 | 5.146 | 5.446 | 6.098 | 199.417 / 385.309 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1957.692 | 25.115 | 25.932 | 31.967 | 199.917 / 385.309 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1919.866 | 50.826 | 52.656 | 81.224 | 198.936 / 388.059 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 77.630 | 12.746 | 13.921 | 15.447 | 63.985 / 388.543 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 143.387 | 66.674 | 86.488 | 118.987 | 126.325 / 388.766 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.847 | 345.604 | 590.054 | 666.100 | 126.999 / 388.766 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.786 | 698.113 | 1308.884 | 1378.209 | 127.045 / 388.766 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 968.373 | 1.037 | 1.085 | 1.159 | 99.469 / 388.766 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1966.143 | 5.051 | 5.227 | 6.349 | 199.445 / 388.766 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2034.026 | 24.279 | 24.938 | 30.652 | 200.437 / 388.766 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1995.540 | 49.130 | 50.861 | 76.367 | 199.398 / 388.766 | confirmed-regression |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1505.953 | 5.757 | 10.257 | 11.243 | 26.079 / 388.766 | confirmed-regression |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1096.049 | 8.605 | 12.041 | 14.289 | 37.191 / 389.070 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2647.463 | 18.441 | 30.824 | 44.462 | 380.510 / 632.340 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2645.468 | 38.868 | 69.097 | 77.699 | 385.571 / 636.820 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 171.874 | 221.983 | 700.531 | 871.216 | 230.248 / 639.008 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 163.519 | 392.898 | 1349.425 | 1465.179 | 233.527 / 639.406 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1855.017 | 28.298 | 45.119 | 50.439 | 222.365 / 640.406 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2740.163 | 28.147 | 65.269 | 79.844 | 385.865 / 640.406 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 233.144 | 4.260 | 4.388 | 4.664 | 99.462 / 380.750 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 463.954 | 21.102 | 28.883 | 33.822 | 199.424 / 380.824 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 458.843 | 105.805 | 134.784 | 196.307 | 201.353 / 382.703 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1400.166 | 0.704 | 0.770 | 0.817 | 99.525 / 380.773 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2732.519 | 3.608 | 3.839 | 6.385 | 198.968 / 380.773 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2803.370 | 17.649 | 18.624 | 22.670 | 200.417 / 381.406 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2787.601 | 35.402 | 37.035 | 56.500 | 200.325 / 382.820 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 100.853 | 9.844 | 10.283 | 11.907 | 85.556 / 383.445 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 177.190 | 52.877 | 88.240 | 102.265 | 171.570 / 383.984 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 173.660 | 269.235 | 451.296 | 529.845 | 171.327 / 386.293 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1013.465 | 0.970 | 1.046 | 1.123 | 101.384 / 386.293 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1994.536 | 4.946 | 6.587 | 8.823 | 199.470 / 386.293 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2044.022 | 24.028 | 24.919 | 37.173 | 200.906 / 386.293 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 979.128 | 0.991 | 1.147 | 1.483 | 99.507 / 386.375 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1928.106 | 5.119 | 6.179 | 8.976 | 198.968 / 386.375 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1980.813 | 24.885 | 26.439 | 43.422 | 200.861 / 386.375 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 994.216 | 0.992 | 1.066 | 1.120 | 99.533 / 386.500 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1907.566 | 5.121 | 6.734 | 9.055 | 198.977 / 386.500 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1971.817 | 25.072 | 26.007 | 45.180 | 199.847 / 386.500 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1938.117 | 50.318 | 53.359 | 87.580 | 200.395 / 389.309 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 78.068 | 12.523 | 13.710 | 14.807 | 63.190 / 389.930 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 139.745 | 68.325 | 101.755 | 129.064 | 126.825 / 389.930 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 123.259 | 349.186 | 606.657 | 673.360 | 128.017 / 389.930 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.811 | 699.110 | 1320.937 | 1397.873 | 127.020 / 389.930 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 993.018 | 1.017 | 1.061 | 1.175 | 99.497 / 389.930 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1962.893 | 4.967 | 6.065 | 8.596 | 199.456 / 389.930 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2026.841 | 24.343 | 25.158 | 42.359 | 200.420 / 389.930 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1989.782 | 48.703 | 50.929 | 81.701 | 199.895 / 389.930 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2667.107 | 17.324 | 34.411 | 43.213 | 385.892 / 634.547 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2642.893 | 39.332 | 64.279 | 84.122 | 387.193 / 639.188 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 174.461 | 210.442 | 665.741 | 842.730 | 233.586 / 641.152 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 167.898 | 513.245 | 1059.006 | 1232.054 | 234.895 / 642.691 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2001.793 | 24.013 | 33.298 | 47.606 | 210.938 / 642.727 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2733.752 | 25.464 | 56.586 | 66.367 | 387.733 / 642.871 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.535 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.434 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.520 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.598 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 4.177 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.304 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.120 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.100 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.509 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.582 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.287 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.376 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.105 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.062 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.058 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.396 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.458 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.518 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.606 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.490 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.574 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.326 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.399 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.069 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.590 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.192 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.173 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.194 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.059 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.021 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.106 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.056 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.065 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 702.998 | 141.392 | 152.903 | 153.832 | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1189.582 | 161.618 | 189.795 | 194.487 | — / — | improvement |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | confirmed-regression | completed: -21.8%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +30.0%, p95_ms: +14.2%, p99_ms: -8.9%, requests_per_second: -21.7%, rss_bytes: +0.3% |
| cache_miss | confirmed-regression | completed: -21.6%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: +30.5%, p95_ms: +19.0%, p99_ms: +5.5%, requests_per_second: -22.6%, rss_bytes: +0.3% |
| cache_miss | confirmed-regression | completed: -24.3%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +31.6%, p95_ms: +39.2%, p99_ms: +36.6%, requests_per_second: -24.3%, rss_bytes: +0.3% |
| health_live | confirmed-regression | completed: -20.0%, cpu_percent: -0.0%, duration_seconds: +4.9%, p50_ms: +30.9%, p95_ms: +29.0%, p99_ms: +27.0%, requests_per_second: -22.5%, rss_bytes: +0.2% |
| health_live | confirmed-regression | completed: -25.0%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +25.1%, p95_ms: +2.8%, p99_ms: +26.4%, requests_per_second: -22.5%, rss_bytes: +0.2% |
| health_live | confirmed-regression | completed: -23.2%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +30.4%, p95_ms: +26.6%, p99_ms: +23.9%, requests_per_second: -23.2%, rss_bytes: +0.2% |
| health_live | confirmed-regression | completed: -24.0%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +29.9%, p95_ms: +36.6%, p99_ms: +51.0%, requests_per_second: -24.1%, rss_bytes: +0.2% |
| home | confirmed-regression | completed: -20.8%, cpu_percent: +0.8%, duration_seconds: -0.0%, p50_ms: +26.6%, p95_ms: +10.6%, p99_ms: +24.1%, requests_per_second: -19.5%, rss_bytes: +0.2% |
| home | stable | completed: -8.6%, cpu_percent: +0.6%, duration_seconds: -4.7%, p50_ms: +1.4%, p95_ms: -5.6%, p99_ms: +5.1%, requests_per_second: -4.2%, rss_bytes: +0.2% |
| home | confirmed-regression | completed: -14.6%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +23.3%, p95_ms: +19.1%, p99_ms: +22.7%, requests_per_second: -14.5%, rss_bytes: +0.2% |
| categories | confirmed-regression | completed: -25.4%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +36.0%, p95_ms: +29.3%, p99_ms: +3.8%, requests_per_second: -24.3%, rss_bytes: +0.2% |
| categories | confirmed-regression | completed: -23.8%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +30.3%, p95_ms: +31.9%, p99_ms: +36.3%, requests_per_second: -23.4%, rss_bytes: +0.2% |
| categories | confirmed-regression | completed: -20.6%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +29.0%, p95_ms: +28.8%, p99_ms: +19.7%, requests_per_second: -20.7%, rss_bytes: +0.2% |
| category | confirmed-regression | completed: -26.2%, cpu_percent: -1.0%, duration_seconds: -4.7%, p50_ms: +28.6%, p95_ms: +30.8%, p99_ms: +54.5%, requests_per_second: -22.8%, rss_bytes: +0.2% |
| category | confirmed-regression | completed: -23.9%, cpu_percent: +0.2%, duration_seconds: -4.7%, p50_ms: +27.2%, p95_ms: +24.1%, p99_ms: +30.1%, requests_per_second: -22.4%, rss_bytes: +0.2% |
| category | confirmed-regression | completed: -22.9%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +29.8%, p95_ms: +28.8%, p99_ms: +29.5%, requests_per_second: -22.9%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -25.1%, cpu_percent: -0.4%, duration_seconds: -4.7%, p50_ms: +26.7%, p95_ms: +28.1%, p99_ms: +27.1%, requests_per_second: -21.4%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -21.5%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +26.6%, p95_ms: +25.3%, p99_ms: -4.8%, requests_per_second: -21.5%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -22.5%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +28.9%, p95_ms: +24.7%, p99_ms: +36.9%, requests_per_second: -22.6%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -23.7%, cpu_percent: -0.9%, duration_seconds: +0.1%, p50_ms: +31.4%, p95_ms: +26.7%, p99_ms: +38.6%, requests_per_second: -23.8%, rss_bytes: +0.2% |
| search | confirmed-regression | completed: +21.7%, cpu_percent: +34.0%, duration_seconds: -0.0%, p50_ms: +18.3%, p95_ms: -87.4%, p99_ms: -89.9%, requests_per_second: +20.4%, rss_bytes: +0.3% |
| search | improvement | completed: +2.9%, cpu_percent: +16.5%, duration_seconds: -0.1%, p50_ms: +1.8%, p95_ms: -39.4%, p99_ms: -25.3%, requests_per_second: +3.0%, rss_bytes: +0.2% |
| search | improvement | completed: +12.1%, cpu_percent: +35.7%, duration_seconds: +0.0%, p50_ms: +4.8%, p95_ms: -18.4%, p99_ms: -15.5%, requests_per_second: +12.1%, rss_bytes: +0.2% |
| search | stable | completed: +0.0%, cpu_percent: +39.4%, duration_seconds: +0.0%, p50_ms: -8.1%, p95_ms: -3.6%, p99_ms: -2.6%, requests_per_second: -0.0%, rss_bytes: +0.2% |
| cache_hit | confirmed-regression | completed: -27.8%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +34.7%, p95_ms: +30.7%, p99_ms: +32.5%, requests_per_second: -24.3%, rss_bytes: +0.2% |
| cache_hit | confirmed-regression | completed: -22.8%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +28.7%, p95_ms: +28.7%, p99_ms: +10.5%, requests_per_second: -22.2%, rss_bytes: +0.2% |
| cache_hit | confirmed-regression | completed: -21.2%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +26.8%, p95_ms: +23.4%, p99_ms: +32.9%, requests_per_second: -21.3%, rss_bytes: +0.2% |
| cache_hit | confirmed-regression | completed: -23.6%, cpu_percent: -1.0%, duration_seconds: +0.1%, p50_ms: +30.3%, p95_ms: +31.7%, p99_ms: +34.9%, requests_per_second: -23.6%, rss_bytes: +0.2% |
| health_live | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -12.3%, duration_seconds: +34.7%, p50_ms: +30.1%, p95_ms: +50.8%, p99_ms: +22.8%, requests_per_second: -25.9%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +6.5%, duration_seconds: +16.7%, p50_ms: +26.3%, p95_ms: +8.4%, p99_ms: +13.0%, requests_per_second: -14.7%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -9.5%, cpu_percent: +27.6%, duration_seconds: +4.9%, p50_ms: +13.9%, p95_ms: +13.4%, p99_ms: +35.3%, requests_per_second: -10.3%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -22.1%, cpu_percent: -0.4%, duration_seconds: -0.3%, p50_ms: +59.7%, p95_ms: +51.0%, p99_ms: +47.4%, requests_per_second: -21.9%, rss_bytes: +0.3% |
| search | stable | completed: +37.8%, cpu_percent: +51.3%, duration_seconds: +0.2%, p50_ms: -6.5%, p95_ms: -25.0%, p99_ms: -23.5%, requests_per_second: +37.3%, rss_bytes: +0.4% |
| search | stable | completed: +4.8%, cpu_percent: +25.4%, duration_seconds: +0.1%, p50_ms: +5.6%, p95_ms: -11.2%, p99_ms: -17.9%, requests_per_second: +9.4%, rss_bytes: +0.2% |
| cache_hit | confirmed-regression | completed: -34.7%, cpu_percent: -26.1%, duration_seconds: +0.1%, p50_ms: +98.2%, p95_ms: +26.0%, p99_ms: +35.6%, requests_per_second: -34.7%, rss_bytes: +0.4% |
| cache_hit | confirmed-regression | completed: -21.6%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +7.3%, p95_ms: +37.5%, p99_ms: +48.5%, requests_per_second: -21.8%, rss_bytes: +0.4% |
| cache_miss | confirmed-regression | completed: -23.1%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +30.8%, p95_ms: +26.3%, p99_ms: +16.3%, requests_per_second: -23.0%, rss_bytes: +0.2% |
| cache_miss | confirmed-regression | completed: -23.8%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +29.1%, p95_ms: +26.6%, p99_ms: +4.1%, requests_per_second: -23.3%, rss_bytes: +0.2% |
| cache_miss | confirmed-regression | completed: -22.4%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +28.0%, p95_ms: +43.2%, p99_ms: +28.0%, requests_per_second: -22.5%, rss_bytes: +0.2% |
| health_live | confirmed-regression | completed: -24.5%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: +27.5%, p95_ms: +26.9%, p99_ms: +27.5%, requests_per_second: -21.3%, rss_bytes: +0.2% |
| health_live | confirmed-regression | completed: -24.9%, cpu_percent: -0.3%, duration_seconds: -4.7%, p50_ms: +26.6%, p95_ms: +25.8%, p99_ms: +55.6%, requests_per_second: -21.3%, rss_bytes: +0.2% |
| health_live | confirmed-regression | completed: -21.5%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +26.5%, p95_ms: +25.0%, p99_ms: +9.3%, requests_per_second: -20.1%, rss_bytes: +0.2% |
| health_live | confirmed-regression | completed: -21.1%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +26.8%, p95_ms: +25.1%, p99_ms: +41.1%, requests_per_second: -21.1%, rss_bytes: +0.2% |
| home | confirmed-regression | completed: -18.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +23.1%, p95_ms: +9.4%, p99_ms: +19.5%, requests_per_second: -15.8%, rss_bytes: +0.3% |
| home | confirmed-regression | completed: -22.3%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: +25.5%, p95_ms: +41.9%, p99_ms: +6.9%, requests_per_second: -22.4%, rss_bytes: +0.2% |
| home | confirmed-regression | completed: -17.3%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +23.7%, p95_ms: +21.6%, p99_ms: +20.2%, requests_per_second: -17.3%, rss_bytes: +0.2% |
| categories | confirmed-regression | completed: -18.6%, cpu_percent: +1.9%, duration_seconds: +4.9%, p50_ms: +28.6%, p95_ms: +28.5%, p99_ms: +31.2%, requests_per_second: -22.4%, rss_bytes: +0.2% |
| categories | confirmed-regression | completed: -20.4%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +20.0%, p95_ms: +23.4%, p99_ms: +22.3%, requests_per_second: -20.4%, rss_bytes: +0.2% |
| categories | confirmed-regression | completed: -21.0%, cpu_percent: +1.0%, duration_seconds: -0.0%, p50_ms: +26.4%, p95_ms: +24.7%, p99_ms: +22.0%, requests_per_second: -21.0%, rss_bytes: +0.2% |
| category | confirmed-regression | completed: -21.8%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +27.4%, p95_ms: +35.9%, p99_ms: +41.6%, requests_per_second: -21.8%, rss_bytes: +0.2% |
| category | confirmed-regression | completed: -21.6%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +27.8%, p95_ms: +39.4%, p99_ms: +31.8%, requests_per_second: -21.6%, rss_bytes: +0.2% |
| category | confirmed-regression | completed: -21.9%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: +26.3%, p95_ms: +24.1%, p99_ms: +30.4%, requests_per_second: -21.9%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -24.3%, cpu_percent: -0.0%, duration_seconds: -4.7%, p50_ms: +26.0%, p95_ms: +26.0%, p99_ms: +26.1%, requests_per_second: -20.6%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -22.9%, cpu_percent: +0.0%, duration_seconds: -4.6%, p50_ms: +25.0%, p95_ms: +26.5%, p99_ms: +26.2%, requests_per_second: -20.3%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -20.0%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +23.9%, p95_ms: +17.7%, p99_ms: +32.5%, requests_per_second: -20.0%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -21.3%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +26.5%, p95_ms: +18.4%, p99_ms: +27.9%, requests_per_second: -21.3%, rss_bytes: +0.2% |
| search | confirmed-regression | completed: -1.3%, cpu_percent: +6.7%, duration_seconds: +0.0%, p50_ms: +23.3%, p95_ms: -45.8%, p99_ms: -71.1%, requests_per_second: -1.7%, rss_bytes: +0.2% |
| search | possible-regression | completed: +7.3%, cpu_percent: +25.1%, duration_seconds: +0.1%, p50_ms: +13.3%, p95_ms: -33.5%, p99_ms: -43.8%, requests_per_second: +7.1%, rss_bytes: +0.2% |
| search | stable | completed: +24.7%, cpu_percent: +36.9%, duration_seconds: +0.1%, p50_ms: -23.5%, p95_ms: -1.3%, p99_ms: -10.5%, requests_per_second: +24.7%, rss_bytes: +0.2% |
| search | stable | completed: +0.0%, cpu_percent: +30.9%, duration_seconds: +0.1%, p50_ms: -10.9%, p95_ms: -6.0%, p99_ms: -11.3%, requests_per_second: +0.0%, rss_bytes: +0.2% |
| cache_hit | confirmed-regression | completed: -19.7%, cpu_percent: -2.8%, duration_seconds: +5.0%, p50_ms: +34.3%, p95_ms: +28.4%, p99_ms: +14.9%, requests_per_second: -23.3%, rss_bytes: +0.2% |
| cache_hit | confirmed-regression | completed: -20.5%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +25.1%, p95_ms: +24.3%, p99_ms: +22.8%, requests_per_second: -22.3%, rss_bytes: +0.2% |
| cache_hit | confirmed-regression | completed: -20.4%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +26.8%, p95_ms: +17.5%, p99_ms: +37.3%, requests_per_second: -20.4%, rss_bytes: +0.2% |
| cache_hit | confirmed-regression | completed: -19.9%, cpu_percent: -0.8%, duration_seconds: +0.1%, p50_ms: +23.7%, p95_ms: +18.1%, p99_ms: +29.5%, requests_per_second: -19.9%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -22.7%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: +25.4%, p95_ms: +38.2%, p99_ms: +14.5%, requests_per_second: -22.7%, rss_bytes: +0.3% |
| thread | confirmed-regression | completed: -23.4%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +38.8%, p95_ms: +47.3%, p99_ms: +65.0%, requests_per_second: -23.5%, rss_bytes: +0.4% |
| search | stable | completed: +1.4%, cpu_percent: +25.8%, duration_seconds: +0.2%, p50_ms: +10.1%, p95_ms: -6.2%, p99_ms: -7.9%, requests_per_second: +1.2%, rss_bytes: +0.4% |
| search | confirmed-regression | completed: +5.0%, cpu_percent: +14.6%, duration_seconds: -0.0%, p50_ms: +42.4%, p95_ms: +9.5%, p99_ms: +12.8%, requests_per_second: +4.7%, rss_bytes: +0.5% |
| cache_hit | possible-regression | completed: -31.0%, cpu_percent: -30.9%, duration_seconds: +0.1%, p50_ms: +13.7%, p95_ms: +23.5%, p99_ms: +32.3%, requests_per_second: -31.0%, rss_bytes: +0.5% |
| cache_hit | stable | completed: -18.0%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -4.0%, p95_ms: +7.7%, p99_ms: -7.3%, requests_per_second: -18.8%, rss_bytes: +0.5% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +27.4% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +26.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +37.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +27.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +28.8% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +28.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +23.1% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +17.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +26.6% |
| sql-plan-readers | possible-regression | sql_execution_ms: +16.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +17.4% |
| sql-plan-readers | possible-regression | sql_execution_ms: +14.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +23.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +22.8% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +27.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +23.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +36.4% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +26.5% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +41.5% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +38.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +22.5% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +34.9% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.1% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +25.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +18.1% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +44.2% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +43.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +29.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +18.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.9% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +24.5% |
| sql-plan-functions | possible-regression | nested_statements: +0.0%, sql_execution_ms: +14.3% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.2% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +31.1% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +50.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +20.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.8% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -35.0%, messages_per_second: +53.9%, p50_ms: -23.4%, p95_ms: -68.9%, p99_ms: -79.5% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -49.1%, messages_per_second: +96.4%, p50_ms: -36.4%, p95_ms: -75.0%, p99_ms: -74.4% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.0%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +0.1%, p95_ms: +0.2%, p99_ms: -2.5%, requests_per_second: -0.1%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -0.9%, cpu_percent: -0.7%, duration_seconds: -0.1%, p50_ms: -0.7%, p95_ms: +30.9%, p99_ms: +14.7%, requests_per_second: +0.4%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -2.3%, p95_ms: +7.9%, p99_ms: +1.4%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.3%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: -6.6%, p95_ms: -4.9%, p99_ms: -4.4%, requests_per_second: +6.1%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.0%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -2.4%, p95_ms: -1.1%, p99_ms: +22.2%, requests_per_second: +2.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.8%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -1.2%, p95_ms: +1.2%, p99_ms: +5.1%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.6%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -1.0%, p95_ms: -5.3%, p99_ms: +6.2%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.0%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -1.3%, p95_ms: -3.5%, p99_ms: -5.1%, requests_per_second: +1.9%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +0.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -1.6%, p95_ms: +26.5%, p99_ms: +6.3%, requests_per_second: +0.9%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.7%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -2.9%, p95_ms: +0.2%, p99_ms: -0.5%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +10.7%, cpu_percent: +1.9%, duration_seconds: +4.9%, p50_ms: -7.3%, p95_ms: -3.8%, p99_ms: -1.3%, requests_per_second: +5.4%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -1.3%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: -3.2%, p95_ms: +19.8%, p99_ms: +14.8%, requests_per_second: +3.1%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.5%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -2.6%, p95_ms: -4.6%, p99_ms: +18.9%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.2%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -2.5%, p95_ms: +3.5%, p99_ms: +2.0%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +5.1%, cpu_percent: +0.0%, duration_seconds: +4.9%, p50_ms: -1.2%, p95_ms: +11.8%, p99_ms: +26.2%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.5%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: -0.1%, p95_ms: +0.0%, p99_ms: +32.0%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -2.4%, p95_ms: -3.0%, p99_ms: -1.2%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +0.8%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -0.5%, p95_ms: +23.6%, p99_ms: +48.5%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.6%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: -0.2%, p95_ms: +0.3%, p99_ms: +41.3%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.9%, cpu_percent: +0.7%, duration_seconds: -0.1%, p50_ms: -1.0%, p95_ms: +1.3%, p99_ms: +7.8%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.0%, cpu_percent: -1.2%, duration_seconds: +0.1%, p50_ms: -1.8%, p95_ms: -1.5%, p99_ms: -4.1%, requests_per_second: +0.6%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -2.4%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: +2.5%, p95_ms: +17.7%, p99_ms: +8.5%, requests_per_second: -2.5%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.2%, cpu_percent: +0.8%, duration_seconds: +0.1%, p50_ms: +1.0%, p95_ms: +2.8%, p99_ms: +1.1%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +0.9%, p99_ms: +1.4%, requests_per_second: +0.0%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +7.6%, cpu_percent: +0.0%, duration_seconds: +5.0%, p50_ms: -1.9%, p95_ms: -2.2%, p99_ms: +1.4%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +4.7%, cpu_percent: +0.0%, duration_seconds: +4.8%, p50_ms: -1.7%, p95_ms: +16.0%, p99_ms: +35.4%, requests_per_second: -0.2%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -0.3%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +0.3%, p95_ms: +0.9%, p99_ms: +38.2%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.3%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -0.9%, p95_ms: +0.1%, p99_ms: +7.0%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -2.7%, cpu_percent: +1.4%, duration_seconds: -4.5%, p50_ms: -6.1%, p95_ms: +11.6%, p99_ms: -2.8%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.1%, cpu_percent: +0.4%, duration_seconds: +0.2%, p50_ms: +1.2%, p95_ms: -7.0%, p99_ms: +8.3%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.4%, cpu_percent: +1.4%, duration_seconds: -0.0%, p50_ms: -5.2%, p95_ms: -5.0%, p99_ms: -3.3%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.7%, cpu_percent: +0.6%, duration_seconds: -0.2%, p50_ms: +30.6%, p95_ms: -21.5%, p99_ms: -15.9%, requests_per_second: +2.7%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +7.9%, cpu_percent: -5.1%, duration_seconds: -0.0%, p50_ms: -15.1%, p95_ms: -26.2%, p99_ms: -5.6%, requests_per_second: +7.9%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.5%, cpu_percent: +0.5%, duration_seconds: -0.2%, p50_ms: -9.5%, p95_ms: -13.3%, p99_ms: -16.9%, requests_per_second: -0.2%, rss_bytes: +0.4% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +41.7%, cpu_percent: +90.3%, duration_seconds: +4.9%, p50_ms: -26.6%, p95_ms: +18.9%, p99_ms: +39.1%, requests_per_second: +35.2%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +37.6%, cpu_percent: +93.8%, duration_seconds: -0.2%, p50_ms: -23.5%, p95_ms: +31.2%, p99_ms: -4.3%, requests_per_second: +37.8%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +38.4%, cpu_percent: +81.3%, duration_seconds: +0.3%, p50_ms: -35.8%, p95_ms: +18.7%, p99_ms: +30.8%, requests_per_second: +37.7%, rss_bytes: +64.4% |
| search | workers=4 | 2 | 100 | improvement | completed: +64.5%, cpu_percent: +83.8%, duration_seconds: +0.4%, p50_ms: -43.7%, p95_ms: +3.1%, p99_ms: +6.3%, requests_per_second: +63.9%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -8.7%, cpu_percent: +10.9%, duration_seconds: +0.1%, p50_ms: +16.6%, p95_ms: +80.9%, p99_ms: +64.6%, requests_per_second: -8.8%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +37.5%, cpu_percent: +93.5%, duration_seconds: +0.2%, p50_ms: -42.7%, p95_ms: +28.3%, p99_ms: +4.6%, requests_per_second: +37.3%, rss_bytes: +64.7% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +37.1%, cpu_percent: +93.1%, duration_seconds: +0.2%, p50_ms: -30.9%, p95_ms: +32.3%, p99_ms: -4.4%, requests_per_second: +35.3%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | confirmed-regression | completed: +36.5%, cpu_percent: +93.2%, duration_seconds: +0.1%, p50_ms: -21.8%, p95_ms: +20.5%, p99_ms: -3.9%, requests_per_second: +36.4%, rss_bytes: +64.2% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +42.1%, cpu_percent: +82.5%, duration_seconds: +0.2%, p50_ms: -39.7%, p95_ms: +9.7%, p99_ms: +25.2%, requests_per_second: +41.5%, rss_bytes: +64.4% |
| search | workers=4 | 2 | 100 | improvement | completed: +69.0%, cpu_percent: +84.9%, duration_seconds: +0.1%, p50_ms: -26.6%, p95_ms: -19.8%, p99_ms: -11.9%, requests_per_second: +68.2%, rss_bytes: +64.8% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: -1.2%, cpu_percent: +5.2%, duration_seconds: +0.1%, p50_ms: -1.4%, p95_ms: +32.4%, p99_ms: +12.4%, requests_per_second: -1.2%, rss_bytes: +64.8% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +38.6%, cpu_percent: +94.0%, duration_seconds: +0.0%, p50_ms: -47.7%, p95_ms: +11.1%, p99_ms: -18.8%, requests_per_second: +37.4%, rss_bytes: +64.9% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38940661243)
