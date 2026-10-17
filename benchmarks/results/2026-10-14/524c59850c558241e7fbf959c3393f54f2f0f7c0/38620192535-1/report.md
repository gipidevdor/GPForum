# GPForum continuous performance evidence

Commit: `524c59850c558241e7fbf959c3393f54f2f0f7c0` · mode: **main** · status: **ok**
Run: 38620192535 / attempt 1 · 2026-10-14T19:02:14.514599+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"ee7d3093ffc5cd7d0cc2f564417c6ad7f1e113aa0c1316b1b59386e9b

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 390.359 | 2.545 | 2.645 | 2.758 | 99.952 / 369.789 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 780.723 | 12.624 | 13.372 | 17.562 | 199.382 / 369.816 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 767.305 | 63.370 | 73.398 | 107.809 | 201.347 / 371.473 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1721.482 | 0.573 | 0.624 | 0.719 | 99.555 / 370.074 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3442.345 | 2.856 | 3.083 | 4.002 | 198.606 / 370.074 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3597.412 | 13.776 | 14.193 | 16.614 | 200.503 / 370.793 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3540.441 | 27.722 | 30.743 | 40.726 | 200.821 / 372.031 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 172.876 | 5.737 | 6.037 | 7.412 | 85.568 / 372.414 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 323.649 | 28.836 | 44.093 | 53.943 | 169.070 / 372.781 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 306.838 | 156.098 | 227.365 | 292.495 | 169.599 / 374.539 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1282.190 | 0.770 | 0.832 | 0.866 | 99.031 / 374.539 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2503.404 | 3.924 | 4.227 | 5.842 | 199.037 / 374.539 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2616.434 | 18.864 | 20.131 | 26.555 | 199.014 / 374.539 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1232.873 | 0.800 | 0.863 | 0.889 | 99.505 / 374.570 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2481.038 | 4.029 | 4.314 | 5.242 | 199.557 / 374.570 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2530.939 | 19.857 | 20.877 | 25.374 | 199.958 / 374.570 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1223.954 | 0.804 | 0.867 | 0.968 | 99.522 / 374.695 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2426.513 | 4.034 | 4.525 | 6.564 | 199.982 / 374.695 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2495.703 | 20.031 | 20.962 | 24.202 | 200.394 / 375.305 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2426.692 | 41.459 | 46.957 | 61.579 | 201.465 / 378.469 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 72.851 | 11.065 | 83.487 | 138.391 | 47.403 / 378.855 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 101.945 | 64.770 | 220.322 | 319.940 | 78.594 / 379.105 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 74.867 | 647.675 | 1118.228 | 1170.693 | 67.477 / 379.105 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 49.913 | 908.501 | 1285.007 | 1305.894 | 59.572 / 379.105 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1288.142 | 0.766 | 0.824 | 0.897 | 99.544 / 379.105 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2541.769 | 4.113 | 4.777 | 5.484 | 199.428 / 379.105 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2581.894 | 19.185 | 20.246 | 26.949 | 200.401 / 379.105 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2545.834 | 38.366 | 40.006 | 55.996 | 201.326 / 379.105 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1985.620 | 4.456 | 7.094 | 9.022 | 23.329 / 379.105 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1257.813 | 7.083 | 12.820 | 14.146 | 31.296 / 379.387 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 3451.029 | 11.626 | 27.554 | 30.881 | 382.719 / 616.316 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 3443.749 | 24.872 | 50.549 | 62.586 | 386.256 / 620.652 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 126.648 | 220.716 | 844.946 | 1177.865 | 129.037 / 622.297 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 144.396 | 594.408 | 1256.384 | 1342.292 | 164.905 / 623.562 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2506.624 | 19.625 | 24.382 | 33.991 | 209.800 / 623.578 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 3486.216 | 25.599 | 54.564 | 60.934 | 389.395 / 623.578 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 392.899 | 2.503 | 2.654 | 3.163 | 99.482 / 370.887 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 772.998 | 12.554 | 15.880 | 20.511 | 199.437 / 370.902 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 756.707 | 62.841 | 83.751 | 120.790 | 200.912 / 372.680 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1801.355 | 0.545 | 0.598 | 0.747 | 99.980 / 370.781 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3533.847 | 2.848 | 3.457 | 4.769 | 199.051 / 370.781 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3596.774 | 13.701 | 14.316 | 19.363 | 199.899 / 371.539 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3587.280 | 28.473 | 30.088 | 39.244 | 201.515 / 372.945 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 168.447 | 5.789 | 6.448 | 7.855 | 84.609 / 373.316 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 312.815 | 30.582 | 43.444 | 70.606 | 169.068 / 373.727 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 309.961 | 157.361 | 233.246 | 294.208 | 169.397 / 375.434 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1316.608 | 0.749 | 0.807 | 0.842 | 99.530 / 375.434 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2571.617 | 3.711 | 4.807 | 6.927 | 198.123 / 375.434 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2619.500 | 18.840 | 20.605 | 27.851 | 200.523 / 375.434 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1276.674 | 0.772 | 0.835 | 0.875 | 99.536 / 375.590 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2468.011 | 3.997 | 4.958 | 6.829 | 199.397 / 375.590 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2541.084 | 19.378 | 21.178 | 32.565 | 200.281 / 375.590 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1258.801 | 0.786 | 0.843 | 0.862 | 99.516 / 375.715 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2468.021 | 4.025 | 5.171 | 7.745 | 199.550 / 375.715 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2501.050 | 19.577 | 22.046 | 34.903 | 199.989 / 376.328 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2487.043 | 39.356 | 43.146 | 66.611 | 201.310 / 379.535 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 73.444 | 10.380 | 116.020 | 197.710 | 46.282 / 380.180 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 105.409 | 73.941 | 239.247 | 387.138 | 75.636 / 380.355 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 123.370 | 308.434 | 679.251 | 759.759 | 99.012 / 380.355 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.368 | 757.769 | 1657.725 | 1788.239 | 83.746 / 380.355 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1298.661 | 0.762 | 0.816 | 0.843 | 99.507 / 380.355 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2559.146 | 3.859 | 4.439 | 6.378 | 199.434 / 380.355 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2526.819 | 19.808 | 27.761 | 37.659 | 199.782 / 380.355 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2515.748 | 38.550 | 41.216 | 64.333 | 200.794 / 380.355 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3495.088 | 10.707 | 25.764 | 32.546 | 385.365 / 617.625 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3477.659 | 22.598 | 53.438 | 61.054 | 387.611 / 621.824 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 74.448 | 440.077 | 1514.544 | 1772.702 | 91.670 / 623.465 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 126.041 | 435.545 | 1554.874 | 1610.228 | 155.417 / 624.637 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2547.383 | 19.807 | 25.875 | 30.849 | 211.916 / 625.371 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3523.010 | 17.964 | 50.339 | 60.022 | 389.190 / 625.371 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.444 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.410 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.477 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.085 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.262 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.861 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.086 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.029 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.400 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.459 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.225 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.283 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.068 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.036 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.036 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.016 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.376 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.382 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.460 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.373 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.431 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.243 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.299 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.513 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.173 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.149 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.151 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.146 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.044 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.014 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.071 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.075 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.057 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.089 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 490.552 | 158.979 | 387.730 | 625.922 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 546.259 | 354.635 | 599.928 | 670.721 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.6%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -1.6%, p95_ms: +0.3%, p99_ms: +14.7%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -5.1%, cpu_percent: +0.0%, duration_seconds: -4.6%, p50_ms: -0.6%, p95_ms: +18.8%, p99_ms: +16.8%, requests_per_second: -1.0%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -1.4%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -0.8%, p95_ms: +14.1%, p99_ms: +12.0%, requests_per_second: -1.4%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.3%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -4.9%, p95_ms: -4.2%, p99_ms: +3.9%, requests_per_second: +4.6%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -1.0%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -0.3%, p95_ms: +12.1%, p99_ms: +19.2%, requests_per_second: +2.7%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.3%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: +0.9%, p99_ms: +16.5%, requests_per_second: -0.0%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.3%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +2.7%, p95_ms: -2.1%, p99_ms: -3.6%, requests_per_second: +1.3%, rss_bytes: +0.2% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.6%, cpu_percent: -1.1%, duration_seconds: -0.0%, p50_ms: +0.9%, p95_ms: +6.8%, p99_ms: +6.0%, requests_per_second: -2.6%, rss_bytes: +0.2% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -3.4%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +6.1%, p95_ms: -1.5%, p99_ms: +30.9%, requests_per_second: -3.3%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.1%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +0.8%, p95_ms: +2.6%, p99_ms: +0.6%, requests_per_second: +1.0%, rss_bytes: +0.2% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.2%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -2.7%, p95_ms: -3.0%, p99_ms: -2.8%, requests_per_second: +2.7%, rss_bytes: +0.2% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +6.4%, cpu_percent: -0.5%, duration_seconds: +4.9%, p50_ms: -5.4%, p95_ms: +13.7%, p99_ms: +18.6%, requests_per_second: +2.7%, rss_bytes: +0.2% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.1%, cpu_percent: +0.8%, duration_seconds: -0.0%, p50_ms: -0.1%, p95_ms: +2.4%, p99_ms: +4.9%, requests_per_second: +0.1%, rss_bytes: +0.2% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.9%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -3.5%, p95_ms: -3.2%, p99_ms: -1.6%, requests_per_second: +3.6%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +1.1%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: +14.9%, p99_ms: +30.3%, requests_per_second: -0.5%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +0.9%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -2.4%, p95_ms: +1.4%, p99_ms: +28.3%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.7%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -2.2%, p95_ms: -2.8%, p99_ms: -10.9%, requests_per_second: +2.8%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.2%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -0.2%, p95_ms: +14.3%, p99_ms: +18.0%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.3%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -2.3%, p95_ms: +5.2%, p99_ms: +44.2%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -5.1%, p95_ms: -8.1%, p99_ms: +8.2%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -3.9%, cpu_percent: -2.4%, duration_seconds: -0.1%, p50_ms: -6.2%, p95_ms: +39.0%, p99_ms: +42.9%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +3.4%, cpu_percent: -3.8%, duration_seconds: +0.0%, p50_ms: +14.2%, p95_ms: +8.6%, p99_ms: +21.0%, requests_per_second: +3.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +64.7%, cpu_percent: +46.7%, duration_seconds: -0.1%, p50_ms: -52.4%, p95_ms: -39.3%, p99_ms: -35.1%, requests_per_second: +64.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: +99.0%, cpu_percent: +40.6%, duration_seconds: -0.0%, p50_ms: -16.6%, p95_ms: +29.0%, p99_ms: +36.9%, requests_per_second: +99.1%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.8%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -0.5%, p95_ms: -1.0%, p99_ms: -6.0%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +2.4%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -6.2%, p95_ms: -7.1%, p99_ms: +16.3%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -2.1%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +3.2%, p95_ms: +37.1%, p99_ms: +39.7%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.2%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +0.5%, p95_ms: +3.0%, p99_ms: +14.9%, requests_per_second: -1.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.9%, cpu_percent: +0.7%, duration_seconds: +0.0%, p50_ms: -7.9%, p95_ms: -6.5%, p99_ms: +5.4%, requests_per_second: +1.3%, rss_bytes: +0.2% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.1%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: -9.1%, p95_ms: +5.7%, p99_ms: -2.4%, requests_per_second: +1.0%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -41.3%, cpu_percent: -29.0%, duration_seconds: -0.1%, p50_ms: +99.4%, p95_ms: +79.2%, p99_ms: +50.5%, requests_per_second: -41.2%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -12.8%, cpu_percent: -5.8%, duration_seconds: -0.1%, p50_ms: -26.7%, p95_ms: +23.8%, p99_ms: +20.0%, requests_per_second: -12.7%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.8%, cpu_percent: +1.0%, duration_seconds: +0.1%, p50_ms: +0.9%, p95_ms: +6.1%, p99_ms: -9.2%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.1%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -29.8%, p95_ms: -7.7%, p99_ms: -1.5%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +39.5%, cpu_percent: +91.0%, duration_seconds: +4.9%, p50_ms: -42.0%, p95_ms: +31.4%, p99_ms: +27.6%, requests_per_second: +38.3%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | improvement | completed: +42.0%, cpu_percent: +91.7%, duration_seconds: +0.0%, p50_ms: -40.0%, p95_ms: +7.7%, p99_ms: +1.6%, requests_per_second: +41.9%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | improvement | completed: +69.3%, cpu_percent: +91.2%, duration_seconds: +0.1%, p50_ms: -65.9%, p95_ms: -24.4%, p99_ms: +0.6%, requests_per_second: +69.2%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +190.0%, cpu_percent: +176.8%, duration_seconds: +0.2%, p50_ms: -34.6%, p95_ms: -2.2%, p99_ms: +2.8%, requests_per_second: +189.3%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: -2.9%, cpu_percent: +4.7%, duration_seconds: -0.0%, p50_ms: +2.3%, p95_ms: +20.4%, p99_ms: +26.1%, requests_per_second: -2.9%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 100 | confirmed-regression | completed: +37.0%, cpu_percent: +93.4%, duration_seconds: -0.1%, p50_ms: -33.3%, p95_ms: +36.4%, p99_ms: +8.8%, requests_per_second: +36.9%, rss_bytes: +64.5% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +41.7%, cpu_percent: +92.7%, duration_seconds: +4.9%, p50_ms: -45.3%, p95_ms: +16.9%, p99_ms: -6.8%, requests_per_second: +39.7%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | confirmed-regression | completed: +40.0%, cpu_percent: +92.5%, duration_seconds: +0.1%, p50_ms: -42.6%, p95_ms: +23.9%, p99_ms: -8.3%, requests_per_second: +39.8%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | possible-regression | completed: -39.7%, cpu_percent: -7.4%, duration_seconds: +0.1%, p50_ms: +42.7%, p95_ms: +123.0%, p99_ms: +133.3%, requests_per_second: -39.7%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +27.1%, cpu_percent: +85.6%, duration_seconds: +0.2%, p50_ms: -42.5%, p95_ms: -6.2%, p99_ms: -10.0%, requests_per_second: +26.8%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: +0.9%, cpu_percent: +6.1%, duration_seconds: +0.0%, p50_ms: -0.0%, p95_ms: -6.8%, p99_ms: -18.1%, requests_per_second: +0.8%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | confirmed-regression | completed: +40.2%, cpu_percent: +93.8%, duration_seconds: +0.0%, p50_ms: -53.4%, p95_ms: +22.1%, p99_ms: -6.7%, requests_per_second: +40.0%, rss_bytes: +64.4% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38620192535)
