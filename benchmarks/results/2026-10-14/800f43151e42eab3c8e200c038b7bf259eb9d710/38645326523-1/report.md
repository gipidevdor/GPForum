# GPForum continuous performance evidence

Commit: `800f43151e42eab3c8e200c038b7bf259eb9d710` · mode: **main** · status: **ok**
Run: 38645326523 / attempt 1 · 2026-10-14T22:07:20.550554+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"26f1e2022f330a9d556751cff40314eccd166da8aea629f96e6992e8e

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 276.192 | 3.604 | 3.692 | 3.900 | 100.489 / 369.934 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 549.481 | 18.079 | 18.496 | 22.238 | 199.965 / 369.934 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 536.318 | 90.145 | 96.980 | 159.386 | 201.406 / 371.617 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1159.051 | 0.855 | 0.913 | 0.970 | 99.966 / 370.008 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2279.179 | 4.328 | 4.584 | 6.277 | 198.856 / 370.008 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2333.820 | 21.240 | 22.089 | 26.153 | 200.415 / 370.637 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2294.918 | 43.004 | 47.730 | 64.377 | 201.845 / 371.918 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 120.428 | 8.242 | 8.537 | 8.951 | 86.111 / 372.242 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 229.125 | 42.430 | 48.359 | 59.756 | 173.581 / 372.645 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 219.535 | 217.494 | 336.076 | 402.189 | 174.160 / 374.387 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 846.472 | 1.183 | 1.230 | 1.291 | 99.987 / 374.387 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1733.457 | 5.741 | 5.957 | 6.865 | 198.955 / 374.387 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1760.887 | 28.450 | 28.941 | 37.684 | 201.410 / 374.387 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 851.517 | 1.160 | 1.229 | 1.439 | 99.471 / 374.418 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1664.456 | 6.263 | 7.111 | 8.237 | 199.443 / 374.418 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1707.222 | 29.493 | 30.792 | 39.179 | 199.914 / 374.418 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 839.951 | 1.163 | 1.244 | 1.593 | 99.453 / 374.648 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1674.784 | 5.919 | 6.081 | 6.773 | 198.961 / 374.648 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1680.544 | 29.053 | 31.944 | 42.886 | 200.366 / 375.203 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1672.116 | 58.081 | 61.293 | 94.475 | 199.895 / 378.406 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 76.454 | 12.984 | 13.512 | 14.022 | 65.411 / 378.941 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 138.789 | 66.781 | 92.041 | 118.923 | 130.820 / 379.125 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.711 | 348.932 | 594.229 | 660.426 | 130.417 / 379.125 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.765 | 709.787 | 1331.665 | 1385.842 | 130.951 / 379.125 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 869.212 | 1.142 | 1.191 | 1.274 | 99.529 / 379.125 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1716.260 | 5.802 | 5.997 | 6.701 | 198.965 / 379.125 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1760.408 | 28.189 | 29.122 | 35.680 | 200.941 / 379.125 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1722.287 | 56.603 | 65.308 | 90.749 | 200.889 / 379.125 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1487.922 | 6.090 | 10.501 | 12.530 | 27.268 / 379.125 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 989.218 | 9.547 | 14.301 | 16.863 | 38.332 / 379.406 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2443.197 | 19.458 | 34.905 | 55.796 | 381.740 / 616.094 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2471.437 | 33.518 | 71.282 | 87.999 | 386.576 / 620.215 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 156.514 | 139.599 | 703.447 | 957.198 | 224.728 / 622.090 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 152.208 | 567.171 | 971.784 | 998.360 | 235.142 / 623.215 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2150.383 | 21.486 | 34.114 | 46.006 | 307.027 / 623.215 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2542.015 | 38.633 | 53.715 | 77.573 | 387.516 / 623.215 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 276.342 | 3.596 | 3.688 | 4.204 | 99.477 / 371.148 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 551.205 | 18.000 | 18.491 | 25.340 | 200.424 / 371.148 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 546.027 | 90.138 | 96.544 | 158.706 | 201.892 / 372.945 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1186.006 | 0.830 | 0.878 | 0.931 | 99.958 / 371.035 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2272.731 | 4.544 | 5.271 | 6.765 | 198.954 / 371.035 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2318.729 | 21.325 | 22.098 | 24.101 | 199.425 / 371.848 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2284.663 | 43.170 | 45.712 | 64.314 | 200.914 / 373.211 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 120.368 | 8.248 | 8.516 | 8.807 | 86.078 / 373.574 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 229.207 | 42.126 | 50.406 | 68.581 | 173.571 / 373.926 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 224.188 | 212.947 | 341.781 | 420.438 | 173.778 / 375.660 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 887.402 | 1.117 | 1.171 | 1.235 | 99.973 / 375.660 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1740.908 | 5.701 | 5.846 | 6.991 | 198.969 / 375.660 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1759.867 | 28.062 | 28.912 | 38.613 | 200.912 / 375.660 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 864.342 | 1.139 | 1.217 | 1.386 | 99.927 / 375.816 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1700.495 | 5.882 | 6.108 | 8.711 | 199.446 / 375.816 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1703.763 | 28.978 | 29.874 | 41.715 | 198.946 / 375.816 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 856.814 | 1.156 | 1.217 | 1.269 | 99.965 / 375.887 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1669.780 | 5.944 | 6.437 | 9.636 | 199.411 / 375.941 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1691.140 | 29.277 | 32.081 | 42.323 | 200.869 / 376.590 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1669.458 | 58.445 | 60.567 | 98.556 | 200.393 / 379.777 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 75.705 | 13.023 | 13.704 | 15.710 | 65.186 / 380.441 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 138.827 | 68.737 | 81.327 | 126.499 | 130.296 / 380.441 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.288 | 344.640 | 606.762 | 678.657 | 130.972 / 380.441 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.745 | 681.994 | 1340.247 | 1393.826 | 130.494 / 380.441 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 871.310 | 1.145 | 1.190 | 1.255 | 99.452 / 380.441 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1733.046 | 5.741 | 5.944 | 6.627 | 199.438 / 380.441 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1771.160 | 27.899 | 28.985 | 37.091 | 200.410 / 380.441 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1719.840 | 56.760 | 58.260 | 92.433 | 199.297 / 380.441 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2486.657 | 20.106 | 34.235 | 49.740 | 386.754 / 618.074 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2490.524 | 37.907 | 58.625 | 70.551 | 388.267 / 621.953 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 164.173 | 163.736 | 660.214 | 760.795 | 229.696 / 623.652 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 145.148 | 484.766 | 1550.463 | 1792.433 | 230.544 / 625.301 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2114.164 | 23.904 | 37.495 | 43.032 | 303.613 / 625.312 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2571.076 | 37.777 | 49.181 | 71.200 | 389.723 / 625.312 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.506 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.031 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.509 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.663 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.525 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.975 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.105 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.088 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.463 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.546 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.299 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.360 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.078 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.045 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.019 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.470 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.532 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.561 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.484 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.515 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.273 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.371 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.890 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.359 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.188 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.162 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.183 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.088 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.128 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.074 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.070 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 688.553 | 144.520 | 152.964 | 161.013 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1174.218 | 166.645 | 191.472 | 192.503 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.0%, cpu_percent: -1.0%, duration_seconds: +0.1%, p50_ms: -0.2%, p95_ms: -0.1%, p99_ms: +7.8%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.4%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -0.4%, p95_ms: -0.0%, p99_ms: +13.9%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.9%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -0.0%, p95_ms: -0.5%, p99_ms: -0.4%, requests_per_second: +1.8%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.0%, cpu_percent: -0.0%, duration_seconds: -4.8%, p50_ms: -2.9%, p95_ms: -3.8%, p99_ms: -4.0%, requests_per_second: +2.3%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.9%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +5.0%, p95_ms: +15.0%, p99_ms: +7.8%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.6%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: +0.0%, p99_ms: -7.8%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +0.4%, p95_ms: -4.2%, p99_ms: -0.1%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.8%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +0.1%, p95_ms: -0.2%, p99_ms: -1.6%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +0.0%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: -0.7%, p95_ms: +4.2%, p99_ms: +14.8%, requests_per_second: +0.0%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.0%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -2.1%, p95_ms: +1.7%, p99_ms: +4.5%, requests_per_second: +2.1%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -5.6%, p95_ms: -4.8%, p99_ms: -4.3%, requests_per_second: +4.8%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.4%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.7%, p95_ms: -1.9%, p99_ms: +1.8%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.1%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -1.4%, p95_ms: -0.1%, p99_ms: +2.5%, requests_per_second: -0.1%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.5%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -1.8%, p95_ms: -1.0%, p99_ms: -3.7%, requests_per_second: +1.5%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.3%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -6.1%, p95_ms: -14.1%, p99_ms: +5.8%, requests_per_second: +2.2%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.1%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -1.7%, p95_ms: -3.0%, p99_ms: +6.5%, requests_per_second: -0.2%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.0%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -0.6%, p95_ms: -2.2%, p99_ms: -20.3%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -4.4%, cpu_percent: +0.2%, duration_seconds: -4.6%, p50_ms: +0.4%, p95_ms: +5.9%, p99_ms: +42.3%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.7%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +0.8%, p95_ms: +0.4%, p99_ms: -1.3%, requests_per_second: +0.6%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.1%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +0.6%, p95_ms: -1.2%, p99_ms: +4.3%, requests_per_second: -0.2%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.7%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: +1.4%, p99_ms: +12.0%, requests_per_second: -1.0%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.0%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: +2.9%, p95_ms: -11.6%, p99_ms: +6.4%, requests_per_second: +0.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -1.2%, p95_ms: +2.1%, p99_ms: +2.8%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -3.9%, p95_ms: +0.6%, p99_ms: +0.6%, requests_per_second: -0.0%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.4%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +0.3%, p95_ms: -0.1%, p99_ms: -1.5%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.0%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -1.1%, p95_ms: -0.9%, p99_ms: -1.1%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.6%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -1.0%, p95_ms: -0.5%, p99_ms: +4.0%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: -0.1%, cpu_percent: -0.8%, duration_seconds: +0.1%, p50_ms: +0.3%, p95_ms: -10.8%, p99_ms: +1.9%, requests_per_second: -0.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.8%, cpu_percent: +1.3%, duration_seconds: +0.0%, p50_ms: +3.3%, p95_ms: -1.9%, p99_ms: -10.9%, requests_per_second: +1.8%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.6%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +13.1%, p95_ms: -17.8%, p99_ms: -19.8%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +4.4%, cpu_percent: +2.2%, duration_seconds: +0.1%, p50_ms: +17.3%, p95_ms: -6.1%, p99_ms: -20.5%, requests_per_second: +4.9%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | confirmed-regression | completed: -4.6%, cpu_percent: -2.0%, duration_seconds: +0.0%, p50_ms: -14.5%, p95_ms: +59.5%, p99_ms: +79.5%, requests_per_second: -4.6%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -5.0%, cpu_percent: -1.1%, duration_seconds: -0.2%, p50_ms: +11.3%, p95_ms: +9.9%, p99_ms: -6.5%, requests_per_second: -1.7%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.1%, cpu_percent: +0.6%, duration_seconds: -0.0%, p50_ms: -2.2%, p95_ms: -8.4%, p99_ms: -8.2%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +45.6%, cpu_percent: +90.5%, duration_seconds: +0.1%, p50_ms: -33.0%, p95_ms: +9.3%, p99_ms: +30.1%, requests_per_second: +45.4%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | improvement | completed: +48.2%, cpu_percent: +93.4%, duration_seconds: +0.2%, p50_ms: -42.3%, p95_ms: +16.3%, p99_ms: -6.9%, requests_per_second: +47.8%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +26.0%, cpu_percent: +72.3%, duration_seconds: +0.1%, p50_ms: -60.0%, p95_ms: +18.4%, p99_ms: +44.9%, requests_per_second: +25.5%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +53.0%, cpu_percent: +79.6%, duration_seconds: +0.3%, p50_ms: -20.1%, p95_ms: -27.0%, p99_ms: -28.0%, requests_per_second: +52.6%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +26.5%, cpu_percent: +52.8%, duration_seconds: +0.2%, p50_ms: -23.8%, p95_ms: +17.1%, p99_ms: +28.9%, requests_per_second: +22.2%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +47.9%, cpu_percent: +92.9%, duration_seconds: +0.2%, p50_ms: -31.7%, p95_ms: -17.8%, p99_ms: -14.5%, requests_per_second: +47.6%, rss_bytes: +64.4% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +47.2%, cpu_percent: +92.5%, duration_seconds: +0.2%, p50_ms: -31.3%, p95_ms: +6.7%, p99_ms: +17.5%, requests_per_second: +47.0%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +49.3%, cpu_percent: +93.8%, duration_seconds: +0.1%, p50_ms: -35.1%, p95_ms: -3.2%, p99_ms: -28.4%, requests_per_second: +49.2%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | possible-regression | completed: +32.1%, cpu_percent: +75.4%, duration_seconds: +0.2%, p50_ms: -52.5%, p95_ms: +8.8%, p99_ms: +12.1%, requests_per_second: +32.1%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | possible-regression | completed: +46.0%, cpu_percent: +76.7%, duration_seconds: +0.3%, p50_ms: -28.9%, p95_ms: +15.7%, p99_ms: +28.6%, requests_per_second: +45.5%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +19.5%, cpu_percent: +51.5%, duration_seconds: +0.0%, p50_ms: -14.3%, p95_ms: +29.4%, p99_ms: +16.0%, requests_per_second: +19.4%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.7%, cpu_percent: +95.5%, duration_seconds: +0.1%, p50_ms: -33.4%, p95_ms: -15.6%, p99_ms: -23.0%, requests_per_second: +49.5%, rss_bytes: +64.4% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38645326523)
