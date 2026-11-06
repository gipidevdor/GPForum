# GPForum continuous performance evidence

Commit: `d06ea94d0dc69172f3700476673788e4ecd903a7` · mode: **main** · status: **ok**
Run: 38735392526 / attempt 1 · 2026-10-15T12:32:49.357927+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 47adf843e725cee574caf6c86310a825d9e05df5

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 309.970 | 3.188 | 3.360 | 4.313 | 99.937 / 370.363 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 612.806 | 18.465 | 19.488 | 22.070 | 200.316 / 370.461 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 606.126 | 79.218 | 88.946 | 142.220 | 200.333 / 372.289 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1690.076 | 0.577 | 0.642 | 0.901 | 99.478 / 370.188 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3431.494 | 2.832 | 3.071 | 3.985 | 199.412 / 370.184 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3565.048 | 13.883 | 14.603 | 19.240 | 200.909 / 370.863 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3592.036 | 27.369 | 29.526 | 36.476 | 200.456 / 372.082 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 145.471 | 6.702 | 7.845 | 10.697 | 86.579 / 372.672 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 274.736 | 35.010 | 48.076 | 55.110 | 172.600 / 373.066 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 269.672 | 182.198 | 260.351 | 342.856 | 173.859 / 375.344 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1312.171 | 0.754 | 0.813 | 0.881 | 99.520 / 375.344 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2538.138 | 3.839 | 4.285 | 5.570 | 199.890 / 375.344 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2604.178 | 19.382 | 20.443 | 22.109 | 200.342 / 375.344 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1233.356 | 0.798 | 0.882 | 1.186 | 99.529 / 375.480 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2482.433 | 4.408 | 4.864 | 5.699 | 199.525 / 375.500 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2546.422 | 19.591 | 21.273 | 25.603 | 200.364 / 375.500 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1226.895 | 0.800 | 0.866 | 0.990 | 100.036 / 375.625 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2427.094 | 4.009 | 5.137 | 6.649 | 199.432 / 375.625 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2578.675 | 19.454 | 20.442 | 27.244 | 200.012 / 375.625 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2525.134 | 38.558 | 42.872 | 57.829 | 200.505 / 378.586 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 80.844 | 10.099 | 65.629 | 152.212 | 49.785 / 379.242 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 113.423 | 67.910 | 201.320 | 218.365 | 95.024 / 379.246 | possible-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.800 | 349.007 | 569.396 | 629.744 | 114.314 / 379.246 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.705 | 996.425 | 1782.067 | 1817.316 | 94.466 / 379.246 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1257.754 | 0.797 | 0.826 | 0.952 | 99.920 / 379.246 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2502.989 | 3.916 | 4.714 | 5.632 | 198.847 / 379.246 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2539.431 | 19.343 | 23.415 | 28.660 | 200.413 / 379.246 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2468.611 | 38.931 | 42.582 | 57.995 | 201.367 / 379.246 | improvement |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 2007.593 | 4.221 | 7.800 | 9.013 | 29.729 / 379.246 | improvement |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1383.391 | 6.631 | 10.792 | 11.651 | 37.200 / 379.527 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 3423.294 | 11.604 | 28.749 | 33.180 | 378.887 / 616.598 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 3373.787 | 22.656 | 52.422 | 68.124 | 383.073 / 620.934 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 149.045 | 254.986 | 662.596 | 666.137 | 167.635 / 622.691 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 115.678 | 501.278 | 1536.536 | 1538.990 | 139.893 / 624.137 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2552.759 | 18.764 | 26.340 | 35.036 | 194.766 / 624.176 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 3513.235 | 23.843 | 60.265 | 73.799 | 389.232 / 624.820 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 313.283 | 3.138 | 3.449 | 4.418 | 99.475 / 371.344 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 622.233 | 15.709 | 20.907 | 28.771 | 199.923 / 371.469 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 618.720 | 80.349 | 87.348 | 148.256 | 201.798 / 373.348 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1820.105 | 0.542 | 0.594 | 0.662 | 100.518 / 371.320 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3533.374 | 2.777 | 3.000 | 4.933 | 199.066 / 371.320 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3543.608 | 13.898 | 14.918 | 19.135 | 199.429 / 372.062 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3564.157 | 27.390 | 32.622 | 38.231 | 200.481 / 373.426 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 152.957 | 6.458 | 7.051 | 8.040 | 86.080 / 373.953 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 249.691 | 37.917 | 55.500 | 73.208 | 173.043 / 374.449 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 259.887 | 176.505 | 275.389 | 336.265 | 172.800 / 376.730 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1330.829 | 0.740 | 0.802 | 0.826 | 99.546 / 376.730 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2549.313 | 3.866 | 4.772 | 6.174 | 199.035 / 376.730 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2648.342 | 18.575 | 20.155 | 31.625 | 200.882 / 376.730 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1299.231 | 0.757 | 0.817 | 0.933 | 99.576 / 376.805 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2514.265 | 3.942 | 4.757 | 6.862 | 198.502 / 376.805 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2577.916 | 18.928 | 20.070 | 33.661 | 200.461 / 376.805 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1244.392 | 0.808 | 0.842 | 0.885 | 99.535 / 376.887 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2466.898 | 3.972 | 5.458 | 6.725 | 199.085 / 376.930 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2517.369 | 19.519 | 20.564 | 34.391 | 200.997 / 376.930 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2474.543 | 39.524 | 41.728 | 68.131 | 201.473 / 379.855 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 85.455 | 10.546 | 21.537 | 43.126 | 59.217 / 380.387 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 123.410 | 67.887 | 129.910 | 213.013 | 95.026 / 380.539 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 130.314 | 379.018 | 602.717 | 748.332 | 98.512 / 380.539 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 71.871 | 660.402 | 1242.149 | 1324.017 | 78.308 / 380.539 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1303.252 | 0.757 | 0.818 | 0.884 | 99.525 / 380.539 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2570.621 | 3.807 | 4.526 | 6.579 | 199.028 / 380.539 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2602.380 | 18.859 | 20.497 | 31.819 | 199.390 / 380.539 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2559.893 | 37.596 | 40.109 | 65.546 | 200.441 / 380.539 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3508.467 | 14.827 | 25.679 | 32.942 | 386.538 / 618.363 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3415.456 | 25.286 | 46.916 | 58.684 | 385.882 / 622.543 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 117.805 | 271.442 | 1055.259 | 1229.860 | 124.305 / 624.473 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 184.306 | 343.224 | 1355.214 | 1648.332 | 197.540 / 626.934 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3150.399 | 18.710 | 28.487 | 30.217 | 298.619 / 626.934 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3581.313 | 28.173 | 36.340 | 51.044 | 386.904 / 627.055 | improvement |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.426 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.340 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.405 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.461 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.082 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.230 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.802 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.074 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.021 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.393 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.454 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.228 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.299 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.087 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.051 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.041 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.300 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.373 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.365 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.456 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.356 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.454 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.236 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.289 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.364 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.227 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.153 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.132 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.149 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.045 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.014 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.068 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.073 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.044 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 358.673 | 222.340 | 526.858 | 656.321 | — / — | confirmed-regression |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 901.947 | 198.611 | 374.310 | 375.498 | — / — | confirmed-regression |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +35.0%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -25.9%, p95_ms: -30.6%, p99_ms: -20.8%, requests_per_second: +36.2%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +38.2%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -16.0%, p95_ms: -22.1%, p99_ms: -39.1%, requests_per_second: +38.2%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +47.3%, cpu_percent: -0.9%, duration_seconds: -0.0%, p50_ms: -30.7%, p95_ms: -34.5%, p99_ms: -28.3%, requests_per_second: +47.2%, rss_bytes: +0.5% |
| health_live | improvement | completed: +26.8%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: -21.9%, p95_ms: -20.1%, p99_ms: +3.3%, requests_per_second: +26.7%, rss_bytes: +0.5% |
| health_live | improvement | completed: +30.1%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -24.7%, p95_ms: -21.4%, p99_ms: -9.8%, requests_per_second: +30.1%, rss_bytes: +0.5% |
| health_live | improvement | completed: +32.6%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -24.0%, p95_ms: -27.5%, p99_ms: -32.0%, requests_per_second: +32.6%, rss_bytes: +0.5% |
| health_live | improvement | completed: +38.1%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -27.3%, p95_ms: -28.3%, p99_ms: -35.6%, requests_per_second: +38.0%, rss_bytes: +0.5% |
| home | improvement | completed: +51.3%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -36.4%, p95_ms: -31.5%, p99_ms: -18.9%, requests_per_second: +56.6%, rss_bytes: +0.5% |
| home | improvement | completed: +63.2%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -39.9%, p95_ms: -37.6%, p99_ms: -44.4%, requests_per_second: +63.3%, rss_bytes: +0.4% |
| home | improvement | completed: +66.7%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -34.1%, p95_ms: -44.3%, p99_ms: -36.2%, requests_per_second: +66.8%, rss_bytes: +0.5% |
| categories | improvement | completed: +44.8%, cpu_percent: +0.1%, duration_seconds: +4.8%, p50_ms: -26.4%, p95_ms: -28.2%, p99_ms: -45.1%, requests_per_second: +38.0%, rss_bytes: +0.5% |
| categories | improvement | completed: +33.9%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: -25.8%, p95_ms: -33.4%, p99_ms: -23.0%, requests_per_second: +33.2%, rss_bytes: +0.5% |
| categories | improvement | completed: +39.3%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -26.1%, p95_ms: -30.9%, p99_ms: -43.3%, requests_per_second: +39.3%, rss_bytes: +0.5% |
| category | improvement | completed: +33.6%, cpu_percent: +0.0%, duration_seconds: +4.9%, p50_ms: -23.8%, p95_ms: -20.9%, p99_ms: +1.2%, requests_per_second: +32.1%, rss_bytes: +0.5% |
| category | improvement | completed: +33.2%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -23.4%, p95_ms: -25.6%, p99_ms: -35.4%, requests_per_second: +34.8%, rss_bytes: +0.5% |
| category | improvement | completed: +34.2%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -23.4%, p95_ms: -21.7%, p99_ms: -23.9%, requests_per_second: +34.4%, rss_bytes: +0.5% |
| thread | improvement | completed: +29.2%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -22.6%, p95_ms: -23.1%, p99_ms: -33.3%, requests_per_second: +29.9%, rss_bytes: +0.5% |
| thread | improvement | completed: +37.2%, cpu_percent: +0.1%, duration_seconds: +4.8%, p50_ms: -24.5%, p95_ms: -10.0%, p99_ms: -14.4%, requests_per_second: +30.8%, rss_bytes: +0.5% |
| thread | improvement | completed: +36.5%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -25.7%, p95_ms: -24.9%, p99_ms: -19.3%, requests_per_second: +36.5%, rss_bytes: +0.5% |
| thread | improvement | completed: +39.5%, cpu_percent: -0.6%, duration_seconds: -0.1%, p50_ms: -28.2%, p95_ms: -33.3%, p99_ms: -36.6%, requests_per_second: +39.4%, rss_bytes: +0.5% |
| search | confirmed-regression | completed: +22.7%, cpu_percent: -25.3%, duration_seconds: +0.0%, p50_ms: -33.2%, p95_ms: +314.5%, p99_ms: +818.0%, requests_per_second: +22.7%, rss_bytes: +0.6% |
| search | possible-regression | completed: -5.4%, cpu_percent: -27.9%, duration_seconds: +0.1%, p50_ms: -16.8%, p95_ms: +89.5%, p99_ms: +55.3%, requests_per_second: -5.5%, rss_bytes: +0.5% |
| search | improvement | completed: +12.1%, cpu_percent: -13.3%, duration_seconds: -0.0%, p50_ms: -13.0%, p95_ms: -20.9%, p99_ms: -25.0%, requests_per_second: +12.1%, rss_bytes: +0.5% |
| search | possible-regression | completed: +0.0%, cpu_percent: -28.1%, duration_seconds: +0.0%, p50_ms: +17.8%, p95_ms: +11.7%, p99_ms: +7.8%, requests_per_second: -0.1%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +30.3%, cpu_percent: +0.6%, duration_seconds: +4.9%, p50_ms: -21.8%, p95_ms: -24.2%, p99_ms: -22.5%, requests_per_second: +29.9%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +31.9%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -30.6%, p95_ms: -28.5%, p99_ms: -25.6%, requests_per_second: +32.1%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +41.0%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -26.9%, p95_ms: -37.3%, p99_ms: -39.8%, requests_per_second: +40.9%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +30.3%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -24.8%, p95_ms: -21.6%, p99_ms: -30.0%, requests_per_second: +30.3%, rss_bytes: +0.5% |
| health_live | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +20.1%, duration_seconds: -28.6%, p50_ms: -31.0%, p95_ms: -19.7%, p99_ms: -26.5%, requests_per_second: +40.8%, rss_bytes: +0.5% |
| thread | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -1.4%, duration_seconds: -25.8%, p50_ms: -23.8%, p95_ms: -22.7%, p99_ms: -22.4%, requests_per_second: +34.8%, rss_bytes: +0.5% |
| thread | improvement | completed: +39.0%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -44.6%, p95_ms: -28.7%, p99_ms: -32.2%, requests_per_second: +39.2%, rss_bytes: +0.5% |
| thread | improvement | completed: +34.7%, cpu_percent: -1.4%, duration_seconds: +0.0%, p50_ms: -35.3%, p95_ms: -16.1%, p99_ms: -19.2%, requests_per_second: +34.8%, rss_bytes: +0.6% |
| search | stable | completed: -5.1%, cpu_percent: -28.7%, duration_seconds: -0.2%, p50_ms: +13.3%, p95_ms: +9.6%, p99_ms: -0.6%, requests_per_second: -4.9%, rss_bytes: +0.4% |
| search | possible-regression | completed: -22.9%, cpu_percent: -42.4%, duration_seconds: -0.4%, p50_ms: +14.3%, p95_ms: +30.9%, p99_ms: +16.9%, requests_per_second: -22.6%, rss_bytes: +0.4% |
| cache_hit | improvement | completed: +29.5%, cpu_percent: -11.8%, duration_seconds: -0.0%, p50_ms: -30.1%, p95_ms: -27.3%, p99_ms: -24.8%, requests_per_second: +29.6%, rss_bytes: +0.4% |
| cache_hit | possible-regression | completed: +33.6%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -32.9%, p95_ms: +23.0%, p99_ms: +27.6%, requests_per_second: +34.3%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +40.0%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -28.7%, p95_ms: -28.8%, p99_ms: -27.9%, requests_per_second: +39.9%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +41.1%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -38.2%, p95_ms: -31.2%, p99_ms: -36.6%, requests_per_second: +41.1%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +38.7%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -25.8%, p95_ms: -38.9%, p99_ms: -27.9%, requests_per_second: +38.7%, rss_bytes: +0.5% |
| health_live | improvement | completed: +38.6%, cpu_percent: +1.1%, duration_seconds: +5.0%, p50_ms: -24.0%, p95_ms: -23.6%, p99_ms: -19.4%, requests_per_second: +32.0%, rss_bytes: +0.5% |
| health_live | improvement | completed: +36.1%, cpu_percent: +0.1%, duration_seconds: +4.9%, p50_ms: -23.8%, p95_ms: -38.9%, p99_ms: -24.0%, requests_per_second: +33.2%, rss_bytes: +0.5% |
| health_live | improvement | completed: +31.4%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -23.3%, p95_ms: -25.2%, p99_ms: -33.6%, requests_per_second: +31.3%, rss_bytes: +0.5% |
| health_live | improvement | completed: +34.9%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -26.0%, p95_ms: -26.8%, p99_ms: -35.4%, requests_per_second: +34.8%, rss_bytes: +0.5% |
| home | improvement | completed: +51.5%, cpu_percent: -1.6%, duration_seconds: +0.0%, p50_ms: -34.3%, p95_ms: -32.9%, p99_ms: -26.9%, requests_per_second: +51.5%, rss_bytes: +0.5% |
| home | improvement | completed: +36.2%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: -26.3%, p95_ms: -22.8%, p99_ms: -33.4%, requests_per_second: +36.3%, rss_bytes: +0.5% |
| home | improvement | completed: +61.3%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -37.6%, p95_ms: -43.7%, p99_ms: -39.4%, requests_per_second: +61.2%, rss_bytes: +0.5% |
| categories | improvement | completed: +29.9%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -25.3%, p95_ms: -24.3%, p99_ms: -26.0%, requests_per_second: +33.9%, rss_bytes: +0.5% |
| categories | improvement | completed: +25.3%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: -23.9%, p95_ms: -19.8%, p99_ms: -30.6%, requests_per_second: +31.1%, rss_bytes: +0.5% |
| categories | improvement | completed: +37.3%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -26.4%, p95_ms: -34.5%, p99_ms: -27.4%, requests_per_second: +37.0%, rss_bytes: +0.5% |
| category | improvement | completed: +32.6%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -24.5%, p95_ms: -25.0%, p99_ms: -19.8%, requests_per_second: +32.6%, rss_bytes: +0.4% |
| category | improvement | completed: +39.9%, cpu_percent: -0.2%, duration_seconds: +4.9%, p50_ms: -24.5%, p95_ms: -33.0%, p99_ms: -25.8%, requests_per_second: +34.3%, rss_bytes: +0.4% |
| category | improvement | completed: +38.2%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -27.8%, p95_ms: -33.5%, p99_ms: -29.5%, requests_per_second: +37.0%, rss_bytes: +0.4% |
| thread | improvement | completed: +29.5%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -19.3%, p95_ms: -32.5%, p99_ms: -49.1%, requests_per_second: +29.6%, rss_bytes: +0.4% |
| thread | improvement | completed: +28.8%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -25.4%, p95_ms: -17.3%, p99_ms: -27.3%, requests_per_second: +33.5%, rss_bytes: +0.4% |
| thread | improvement | completed: +36.6%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -26.5%, p95_ms: -27.0%, p99_ms: -29.2%, requests_per_second: +36.8%, rss_bytes: +0.4% |
| thread | improvement | completed: +36.4%, cpu_percent: +1.2%, duration_seconds: -0.2%, p50_ms: -26.4%, p95_ms: -28.2%, p99_ms: -26.0%, requests_per_second: +36.6%, rss_bytes: +0.5% |
| search | confirmed-regression | completed: +36.8%, cpu_percent: -11.8%, duration_seconds: +0.0%, p50_ms: -33.4%, p95_ms: +29.4%, p99_ms: +142.2%, requests_per_second: +36.9%, rss_bytes: +0.4% |
| search | possible-regression | completed: +4.2%, cpu_percent: -27.8%, duration_seconds: -0.1%, p50_ms: -10.1%, p95_ms: +20.0%, p99_ms: +15.6%, requests_per_second: +7.1%, rss_bytes: +0.5% |
| search | improvement | completed: +31.2%, cpu_percent: -25.0%, duration_seconds: -0.1%, p50_ms: -11.3%, p95_ms: -24.6%, p99_ms: -13.5%, requests_per_second: +31.3%, rss_bytes: +0.5% |
| search | stable | completed: -27.6%, cpu_percent: -40.4%, duration_seconds: -0.0%, p50_ms: -21.8%, p95_ms: -21.4%, p99_ms: -20.9%, requests_per_second: -27.6%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +28.9%, cpu_percent: +0.1%, duration_seconds: -4.7%, p50_ms: -22.7%, p95_ms: -24.4%, p99_ms: -23.4%, requests_per_second: +30.5%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +31.5%, cpu_percent: -0.0%, duration_seconds: -4.7%, p50_ms: -27.2%, p95_ms: -34.1%, p99_ms: -28.0%, requests_per_second: +36.1%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +35.3%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: -27.5%, p95_ms: -25.5%, p99_ms: -30.6%, requests_per_second: +35.3%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +37.1%, cpu_percent: -0.6%, duration_seconds: -0.1%, p50_ms: -28.2%, p95_ms: -28.7%, p99_ms: -28.3%, requests_per_second: +37.3%, rss_bytes: +0.5% |
| thread | improvement | completed: +55.4%, cpu_percent: +29.0%, duration_seconds: -0.0%, p50_ms: -30.9%, p95_ms: -19.9%, p99_ms: -19.5%, requests_per_second: +55.4%, rss_bytes: +0.4% |
| thread | improvement | completed: +29.6%, cpu_percent: +0.3%, duration_seconds: -4.5%, p50_ms: -20.0%, p95_ms: -24.9%, p99_ms: -16.1%, requests_per_second: +34.7%, rss_bytes: +0.4% |
| search | confirmed-regression | completed: -27.4%, cpu_percent: -46.3%, duration_seconds: -0.1%, p50_ms: +14.1%, p95_ms: +71.4%, p99_ms: +39.5%, requests_per_second: -27.1%, rss_bytes: +0.5% |
| search | improvement | completed: +28.5%, cpu_percent: -17.5%, duration_seconds: -0.2%, p50_ms: -27.8%, p95_ms: +0.6%, p99_ms: +14.9%, requests_per_second: +28.6%, rss_bytes: +0.7% |
| cache_hit | improvement | completed: +60.9%, cpu_percent: +47.4%, duration_seconds: -0.1%, p50_ms: -27.2%, p95_ms: -23.7%, p99_ms: -31.8%, requests_per_second: +61.1%, rss_bytes: +0.7% |
| cache_hit | improvement | completed: +38.8%, cpu_percent: +0.6%, duration_seconds: -0.0%, p50_ms: -16.6%, p95_ms: -43.6%, p99_ms: -37.5%, requests_per_second: +38.6%, rss_bytes: +0.7% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -25.8% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -24.1% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -21.7% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -23.3% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -18.8% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -22.1% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -21.8% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -23.1% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -28.2% |
| sql-plan-readers | improvement | sql_execution_ms: -14.3% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -22.2% |
| sql-plan-readers | stable | sql_execution_ms: -22.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -20.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -22.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -20.4% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -20.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -13.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -14.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -20.2% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -32.5% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -35.1% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -28.2% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -27.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -29.5% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -25.1% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -24.9% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -24.1% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -21.4% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -23.9% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -27.5% |
| sql-plan-functions | improvement | nested_statements: +0.0%, sql_execution_ms: -25.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -24.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -22.4% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -36.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -24.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -33.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -49.4% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -46.7% |
| postgres-dispatch-noop | confirmed-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +93.8%, messages_per_second: -48.4%, p50_ms: +55.2%, p95_ms: +230.6%, p99_ms: +300.0% |
| postgres-dispatch-noop | confirmed-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +30.8%, messages_per_second: -23.5%, p50_ms: +21.1%, p95_ms: +94.0%, p99_ms: +93.9% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.0%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: -1.6%, p95_ms: +2.6%, p99_ms: +2.4%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +1.5%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -14.9%, p95_ms: +7.3%, p99_ms: +30.4%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.0%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +1.4%, p95_ms: -1.8%, p99_ms: +4.2%, requests_per_second: +2.1%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +7.7%, cpu_percent: +1.0%, duration_seconds: +0.0%, p50_ms: -6.1%, p95_ms: -7.5%, p99_ms: -26.5%, requests_per_second: +7.7%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +8.1%, cpu_percent: -0.2%, duration_seconds: +5.0%, p50_ms: -1.9%, p95_ms: -2.3%, p99_ms: +23.8%, requests_per_second: +3.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.5%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +2.2%, p99_ms: -0.5%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -0.9%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +0.1%, p95_ms: +10.5%, p99_ms: +4.8%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +3.7%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: -3.6%, p95_ms: -10.1%, p99_ms: -24.8%, requests_per_second: +5.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -9.1%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +8.3%, p95_ms: +15.4%, p99_ms: +32.8%, requests_per_second: -9.1%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -3.5%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: -3.1%, p95_ms: +5.8%, p99_ms: -1.9%, requests_per_second: -3.6%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.1%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: -1.9%, p95_ms: -1.4%, p99_ms: -6.2%, requests_per_second: +1.4%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.3%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: +0.7%, p95_ms: +11.4%, p99_ms: +10.8%, requests_per_second: +0.4%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +1.8%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -4.2%, p95_ms: -1.4%, p99_ms: +43.0%, requests_per_second: +1.7%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +9.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -5.1%, p95_ms: -7.4%, p99_ms: -21.3%, requests_per_second: +5.3%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +5.5%, cpu_percent: -0.5%, duration_seconds: +4.9%, p50_ms: -10.6%, p95_ms: -2.2%, p99_ms: +20.4%, requests_per_second: +1.3%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +2.2%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -3.4%, p95_ms: -5.7%, p99_ms: +31.5%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.0%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +1.0%, p95_ms: -2.8%, p99_ms: -10.6%, requests_per_second: +1.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -3.1%, cpu_percent: -0.2%, duration_seconds: -4.6%, p50_ms: -0.9%, p95_ms: +6.2%, p99_ms: +1.1%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -2.5%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: +0.6%, p99_ms: +26.2%, requests_per_second: -2.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | confirmed-regression | completed: -2.2%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +2.5%, p95_ms: -2.7%, p99_ms: +17.8%, requests_per_second: -2.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +5.6%, cpu_percent: +18.9%, duration_seconds: -0.1%, p50_ms: +4.4%, p95_ms: -67.2%, p99_ms: -71.7%, requests_per_second: +5.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +8.8%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -0.0%, p95_ms: -35.5%, p99_ms: -2.5%, requests_per_second: +8.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +4.4%, cpu_percent: -13.8%, duration_seconds: -0.0%, p50_ms: +8.6%, p95_ms: +5.9%, p99_ms: +18.8%, requests_per_second: +4.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -28.0%, cpu_percent: -17.1%, duration_seconds: -0.1%, p50_ms: -33.7%, p95_ms: -30.3%, p99_ms: -27.1%, requests_per_second: -27.9%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +5.4%, cpu_percent: -0.4%, duration_seconds: -4.7%, p50_ms: -5.0%, p95_ms: -1.0%, p99_ms: -7.1%, requests_per_second: +3.6%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +3.4%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -2.8%, p95_ms: -4.0%, p99_ms: +16.8%, requests_per_second: +2.7%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.4%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: -2.5%, p95_ms: -12.5%, p99_ms: +11.0%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +3.5%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -3.4%, p95_ms: -5.8%, p99_ms: +13.0%, requests_per_second: +3.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +2.4%, cpu_percent: +2.0%, duration_seconds: -0.1%, p50_ms: +27.8%, p95_ms: -10.7%, p99_ms: -0.7%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +1.3%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +11.6%, p95_ms: -10.5%, p99_ms: -13.9%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -21.1%, cpu_percent: -25.8%, duration_seconds: -0.0%, p50_ms: +6.5%, p95_ms: +59.3%, p99_ms: +84.6%, requests_per_second: -21.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +59.5%, cpu_percent: +41.2%, duration_seconds: +0.1%, p50_ms: -31.5%, p95_ms: -11.8%, p99_ms: +7.1%, requests_per_second: +59.3%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +23.4%, cpu_percent: +53.3%, duration_seconds: +0.1%, p50_ms: -0.3%, p95_ms: +8.2%, p99_ms: -13.8%, requests_per_second: +23.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: +2.2%, cpu_percent: -0.6%, duration_seconds: +0.2%, p50_ms: +18.2%, p95_ms: -39.7%, p99_ms: -30.8%, requests_per_second: +1.9%, rss_bytes: +0.4% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +32.9%, cpu_percent: +89.4%, duration_seconds: +0.1%, p50_ms: -40.4%, p95_ms: +40.6%, p99_ms: +21.8%, requests_per_second: +32.8%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +33.4%, cpu_percent: +91.1%, duration_seconds: +0.2%, p50_ms: -41.2%, p95_ms: +22.3%, p99_ms: +17.8%, requests_per_second: +33.6%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | improvement | completed: +19.6%, cpu_percent: +46.6%, duration_seconds: +0.2%, p50_ms: -26.9%, p95_ms: +16.4%, p99_ms: +5.8%, requests_per_second: +19.4%, rss_bytes: +64.2% |
| search | workers=4 | 2 | 100 | improvement | completed: +16.0%, cpu_percent: +48.1%, duration_seconds: +0.0%, p50_ms: -49.7%, p95_ms: -13.8%, p99_ms: -15.3%, requests_per_second: +16.0%, rss_bytes: +64.6% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: +0.4%, cpu_percent: -2.8%, duration_seconds: -0.1%, p50_ms: -3.0%, p95_ms: +12.5%, p99_ms: +22.2%, requests_per_second: +0.5%, rss_bytes: +64.6% |
| cache_hit | workers=4 | 2 | 100 | confirmed-regression | completed: +42.2%, cpu_percent: +93.3%, duration_seconds: +0.1%, p50_ms: -38.8%, p95_ms: +41.5%, p99_ms: +27.3%, requests_per_second: +42.3%, rss_bytes: +64.8% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +39.5%, cpu_percent: +92.3%, duration_seconds: +0.0%, p50_ms: -24.0%, p95_ms: +24.9%, p99_ms: -4.2%, requests_per_second: +39.4%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +38.2%, cpu_percent: +91.5%, duration_seconds: +0.1%, p50_ms: -36.0%, p95_ms: +12.4%, p99_ms: -13.9%, requests_per_second: +38.0%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: -9.6%, cpu_percent: +26.2%, duration_seconds: +0.2%, p50_ms: -28.4%, p95_ms: +75.1%, p99_ms: +64.3%, requests_per_second: -9.6%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +156.9%, cpu_percent: +152.3%, duration_seconds: +0.2%, p50_ms: -48.0%, p95_ms: +9.1%, p99_ms: +24.5%, requests_per_second: +156.4%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +21.0%, cpu_percent: +49.8%, duration_seconds: +0.1%, p50_ms: -0.8%, p95_ms: +39.0%, p99_ms: -5.0%, requests_per_second: +21.1%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +40.4%, cpu_percent: +93.0%, duration_seconds: +0.3%, p50_ms: -25.1%, p95_ms: -9.4%, p99_ms: -22.1%, requests_per_second: +39.9%, rss_bytes: +64.8% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38735392526)
