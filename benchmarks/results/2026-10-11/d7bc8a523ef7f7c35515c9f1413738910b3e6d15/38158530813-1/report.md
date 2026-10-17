# GPForum continuous performance evidence

Commit: `d7bc8a523ef7f7c35515c9f1413738910b3e6d15` · mode: **main** · status: **ok**
Run: 38158530813 / attempt 1 · 2026-10-11T17:10:56.288446+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"ee7d3093ffc5cd7d0cc2f564417c6ad7f1e113aa0c1316b1b59386e9b

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 273.960 | 3.617 | 3.775 | 4.597 | 100.376 / 367.684 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 541.213 | 18.366 | 19.367 | 24.880 | 200.262 / 367.684 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 531.458 | 91.549 | 94.595 | 161.213 | 201.292 / 369.387 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1159.178 | 0.848 | 0.914 | 0.952 | 99.493 / 367.805 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2242.066 | 4.365 | 4.679 | 5.829 | 199.356 / 367.805 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2341.716 | 21.227 | 22.365 | 27.519 | 200.386 / 368.527 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2293.822 | 42.823 | 44.737 | 63.628 | 200.634 / 369.777 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 117.140 | 8.365 | 9.125 | 10.663 | 86.503 / 370.148 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 221.786 | 43.834 | 50.968 | 61.525 | 174.014 / 370.555 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 210.019 | 219.193 | 350.310 | 420.067 | 174.255 / 372.258 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 872.867 | 1.153 | 1.200 | 1.264 | 99.973 / 372.258 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1740.731 | 5.676 | 5.953 | 8.332 | 199.391 / 372.258 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1772.030 | 27.811 | 29.194 | 36.145 | 200.372 / 372.258 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 862.781 | 1.145 | 1.212 | 1.326 | 99.501 / 372.414 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1684.623 | 5.857 | 6.159 | 8.489 | 199.289 / 372.414 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1733.547 | 28.703 | 29.548 | 37.023 | 201.864 / 372.414 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 833.539 | 1.199 | 1.252 | 1.474 | 99.470 / 372.539 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1686.462 | 5.864 | 6.054 | 7.624 | 198.924 / 372.539 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1711.864 | 28.751 | 29.681 | 36.906 | 200.780 / 373.145 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1667.628 | 58.357 | 77.546 | 108.670 | 199.159 / 376.426 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 72.959 | 13.474 | 15.252 | 17.616 | 66.175 / 376.738 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 131.376 | 74.283 | 84.747 | 131.118 | 131.580 / 376.957 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.808 | 380.182 | 663.738 | 745.399 | 132.312 / 376.957 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.799 | 762.175 | 1438.658 | 1525.063 | 132.407 / 377.527 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 862.533 | 1.154 | 1.205 | 1.548 | 99.954 / 377.527 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1709.148 | 5.812 | 6.024 | 8.518 | 198.867 / 377.527 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1747.995 | 28.093 | 29.567 | 37.289 | 200.364 / 377.527 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1745.637 | 56.061 | 78.851 | 93.336 | 200.330 / 377.527 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1411.131 | 6.107 | 10.361 | 14.015 | 23.632 / 377.527 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 987.206 | 8.830 | 15.022 | 17.616 | 34.502 / 377.832 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2493.403 | 18.738 | 29.871 | 38.793 | 386.683 / 612.328 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2484.801 | 36.687 | 59.829 | 74.974 | 387.724 / 616.324 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 149.026 | 258.386 | 667.824 | 928.967 | 226.284 / 617.879 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 144.937 | 565.312 | 1074.827 | 1265.034 | 239.658 / 619.051 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2568.869 | 19.871 | 38.042 | 45.668 | 387.667 / 619.379 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2559.157 | 38.335 | 45.932 | 68.495 | 388.034 / 619.379 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 279.661 | 3.545 | 3.721 | 4.117 | 99.473 / 368.711 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 547.942 | 17.851 | 18.764 | 31.704 | 199.352 / 368.711 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 535.715 | 90.724 | 97.532 | 159.959 | 201.318 / 370.473 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1200.152 | 0.822 | 0.881 | 0.953 | 99.439 / 368.836 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2326.399 | 4.266 | 4.440 | 5.468 | 198.925 / 368.836 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2389.416 | 20.657 | 22.232 | 25.807 | 199.345 / 369.574 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2343.114 | 42.239 | 43.582 | 63.483 | 200.255 / 371.043 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 118.976 | 8.269 | 8.759 | 9.207 | 86.087 / 371.414 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 197.635 | 45.207 | 64.497 | 81.252 | 172.344 / 371.801 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 223.005 | 217.673 | 344.441 | 423.540 | 174.233 / 373.531 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 889.574 | 1.125 | 1.175 | 1.274 | 99.932 / 373.531 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1742.934 | 5.654 | 5.863 | 7.414 | 199.874 / 373.531 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1774.210 | 27.630 | 28.945 | 38.818 | 200.885 / 373.531 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 873.671 | 1.147 | 1.193 | 1.252 | 99.958 / 373.590 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1714.243 | 5.775 | 6.031 | 9.517 | 199.354 / 373.590 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1720.667 | 27.873 | 32.871 | 39.759 | 200.803 / 373.590 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 877.890 | 1.130 | 1.177 | 1.232 | 99.457 / 373.715 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1696.978 | 5.849 | 6.550 | 10.229 | 199.311 / 373.715 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1712.736 | 28.653 | 29.798 | 46.418 | 200.864 / 374.262 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1689.259 | 58.215 | 60.243 | 100.287 | 201.287 / 377.430 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 74.462 | 13.217 | 14.179 | 15.319 | 65.174 / 377.984 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 127.336 | 74.985 | 100.043 | 138.944 | 131.255 / 377.984 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.363 | 361.621 | 658.411 | 746.952 | 130.905 / 377.984 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.681 | 750.221 | 1419.693 | 1477.307 | 131.853 / 377.984 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 882.184 | 1.116 | 1.188 | 1.241 | 99.936 / 377.984 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1751.116 | 5.655 | 5.910 | 7.111 | 199.418 / 377.984 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1752.038 | 27.990 | 29.605 | 41.110 | 199.885 / 377.984 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1745.227 | 56.636 | 58.863 | 91.835 | 201.362 / 377.984 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2473.773 | 18.091 | 33.230 | 47.877 | 389.127 / 614.492 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2461.706 | 39.722 | 56.305 | 74.471 | 387.168 / 618.672 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 147.851 | 254.832 | 699.372 | 887.749 | 234.148 / 619.852 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 159.319 | 560.703 | 1160.331 | 1305.806 | 241.305 / 622.188 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1589.135 | 33.173 | 65.017 | 70.240 | 235.093 / 622.695 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2535.907 | 39.980 | 56.421 | 71.223 | 386.836 / 622.695 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.499 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.032 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.507 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.540 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.532 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.013 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.104 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.464 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.550 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.265 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.369 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.077 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.046 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.019 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.413 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.427 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.520 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.418 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.510 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.268 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.361 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.892 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.264 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.182 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.154 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.178 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.016 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.126 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.102 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.051 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 671.659 | 146.673 | 159.986 | 169.151 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1126.466 | 174.676 | 200.077 | 200.605 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.2%, cpu_percent: -0.9%, duration_seconds: +0.0%, p50_ms: -2.0%, p95_ms: -1.4%, p99_ms: -10.4%, requests_per_second: +2.1%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +1.8%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -2.8%, p95_ms: -3.1%, p99_ms: +27.4%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.8%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.9%, p95_ms: +3.1%, p99_ms: -0.8%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +8.7%, cpu_percent: -0.1%, duration_seconds: +5.0%, p50_ms: -3.1%, p95_ms: -3.6%, p99_ms: +0.1%, requests_per_second: +3.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.8%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -2.3%, p95_ms: -5.1%, p99_ms: -6.2%, requests_per_second: +3.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.1%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -2.7%, p95_ms: -0.6%, p99_ms: -6.2%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.1%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -1.4%, p95_ms: -2.6%, p99_ms: -0.2%, requests_per_second: +2.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.4%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: -4.0%, p99_ms: -13.7%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -6.5%, cpu_percent: -1.0%, duration_seconds: +0.2%, p50_ms: +3.1%, p95_ms: +26.5%, p99_ms: +32.1%, requests_per_second: -10.9%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +6.2%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -0.7%, p95_ms: -1.7%, p99_ms: +0.8%, requests_per_second: +6.2%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.8%, cpu_percent: -0.0%, duration_seconds: -4.7%, p50_ms: -2.4%, p95_ms: -2.1%, p99_ms: +0.8%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.9%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: -1.5%, p99_ms: -11.0%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.1%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -0.7%, p95_ms: -0.9%, p99_ms: +7.4%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.2%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +0.2%, p95_ms: -1.6%, p99_ms: -5.6%, requests_per_second: +1.3%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +0.8%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -1.4%, p95_ms: -2.1%, p99_ms: +12.1%, requests_per_second: +1.8%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.8%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -2.9%, p95_ms: +11.2%, p99_ms: +7.4%, requests_per_second: -0.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +5.2%, cpu_percent: -0.0%, duration_seconds: -0.2%, p50_ms: -5.8%, p95_ms: -6.0%, p99_ms: -16.4%, requests_per_second: +5.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +0.6%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -0.3%, p95_ms: +8.2%, p99_ms: +34.2%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.1%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.3%, p95_ms: +0.4%, p99_ms: +25.8%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.3%, cpu_percent: +1.1%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: -22.3%, p99_ms: -7.7%, requests_per_second: +1.3%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.1%, cpu_percent: -1.5%, duration_seconds: -0.0%, p50_ms: -1.9%, p95_ms: -7.0%, p99_ms: -13.0%, requests_per_second: +2.1%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -3.0%, cpu_percent: -0.2%, duration_seconds: +0.3%, p50_ms: +0.9%, p95_ms: +18.0%, p99_ms: +6.0%, requests_per_second: -3.1%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: -1.1%, duration_seconds: +0.0%, p50_ms: -4.9%, p95_ms: -0.8%, p99_ms: +0.2%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -1.6%, p95_ms: -1.3%, p99_ms: -3.1%, requests_per_second: -0.1%, rss_bytes: +0.1% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.7%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -3.3%, p95_ms: -1.4%, p99_ms: -19.8%, requests_per_second: +2.3%, rss_bytes: +0.1% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.5%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -2.7%, p95_ms: -1.9%, p99_ms: -16.5%, requests_per_second: +2.5%, rss_bytes: +0.1% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.4%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -0.4%, p95_ms: +0.1%, p99_ms: +10.2%, requests_per_second: +0.2%, rss_bytes: +0.1% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: -0.1%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +1.0%, p95_ms: -25.3%, p99_ms: -1.6%, requests_per_second: -0.0%, rss_bytes: +0.1% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.9%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -3.5%, p95_ms: +11.2%, p99_ms: +23.4%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.8%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +8.3%, p95_ms: -5.9%, p99_ms: -0.7%, requests_per_second: -0.9%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.0%, cpu_percent: +3.5%, duration_seconds: -0.3%, p50_ms: -1.4%, p95_ms: +4.7%, p99_ms: -4.4%, requests_per_second: -0.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +9.6%, cpu_percent: +0.7%, duration_seconds: +0.2%, p50_ms: -0.8%, p95_ms: +8.0%, p99_ms: +3.2%, requests_per_second: +9.9%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -38.1%, cpu_percent: -39.4%, duration_seconds: -0.1%, p50_ms: +66.9%, p95_ms: +70.9%, p99_ms: +53.8%, requests_per_second: -38.1%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.8%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +4.3%, p95_ms: +22.8%, p99_ms: +4.0%, requests_per_second: -0.9%, rss_bytes: +0.5% |
| thread | workers=4 | 2 | 50 | improvement | completed: +47.6%, cpu_percent: +92.6%, duration_seconds: +0.2%, p50_ms: -34.8%, p95_ms: +0.6%, p99_ms: +5.1%, requests_per_second: +45.7%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +49.2%, cpu_percent: +94.7%, duration_seconds: +0.3%, p50_ms: -37.1%, p95_ms: -22.8%, p99_ms: -31.0%, requests_per_second: +49.0%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 50 | improvement | completed: +20.0%, cpu_percent: +71.0%, duration_seconds: +0.5%, p50_ms: -32.0%, p95_ms: +0.6%, p99_ms: +24.6%, requests_per_second: +19.4%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +46.0%, cpu_percent: +81.0%, duration_seconds: +0.2%, p50_ms: -25.8%, p95_ms: -25.3%, p99_ms: -17.1%, requests_per_second: +45.2%, rss_bytes: +64.0% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +47.0%, cpu_percent: +93.5%, duration_seconds: +0.2%, p50_ms: -29.3%, p95_ms: +28.7%, p99_ms: +22.5%, requests_per_second: +47.0%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +46.8%, cpu_percent: +93.7%, duration_seconds: +0.2%, p50_ms: -31.6%, p95_ms: -41.7%, p99_ms: -26.6%, requests_per_second: +46.6%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 50 | improvement | completed: +44.7%, cpu_percent: +93.7%, duration_seconds: +0.1%, p50_ms: -36.9%, p95_ms: +11.5%, p99_ms: +3.1%, requests_per_second: +44.4%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | improvement | completed: +46.2%, cpu_percent: +92.3%, duration_seconds: +0.3%, p50_ms: -31.8%, p95_ms: -6.5%, p99_ms: -25.7%, requests_per_second: +45.7%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +19.3%, cpu_percent: +78.9%, duration_seconds: +0.2%, p50_ms: -29.5%, p95_ms: +6.2%, p99_ms: +18.9%, requests_per_second: +18.9%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +60.0%, cpu_percent: +83.0%, duration_seconds: +0.2%, p50_ms: -25.3%, p95_ms: -18.3%, p99_ms: -11.6%, requests_per_second: +59.8%, rss_bytes: +64.6% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: -9.4%, cpu_percent: +17.6%, duration_seconds: +0.1%, p50_ms: +18.5%, p95_ms: +119.6%, p99_ms: +70.9%, requests_per_second: -9.3%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +45.8%, cpu_percent: +92.1%, duration_seconds: +0.2%, p50_ms: -29.4%, p95_ms: -4.1%, p99_ms: -22.4%, requests_per_second: +45.3%, rss_bytes: +64.7% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38158530813)
