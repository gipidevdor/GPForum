# GPForum continuous performance evidence

Commit: `47adf843e725cee574caf6c86310a825d9e05df5` · mode: **main** · status: **ok**
Run: 38695193520 / attempt 1 · 2026-10-15T06:54:08.858457+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: No baseline available.

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 227.650 | 4.300 | 4.845 | 5.443 | 99.452 / 368.418 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 443.521 | 21.979 | 25.010 | 36.264 | 199.709 / 368.539 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 411.767 | 114.303 | 135.819 | 198.249 | 202.144 / 370.363 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1333.538 | 0.739 | 0.804 | 0.872 | 100.279 / 368.387 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2636.842 | 3.763 | 3.905 | 4.417 | 198.812 / 368.387 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2689.299 | 18.271 | 20.136 | 28.277 | 200.222 / 369.008 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2602.155 | 37.644 | 41.170 | 56.662 | 200.745 / 370.289 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 92.881 | 10.543 | 11.452 | 13.197 | 86.488 / 370.754 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 168.246 | 58.277 | 77.068 | 99.116 | 172.452 / 371.406 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 161.684 | 276.294 | 467.193 | 537.725 | 173.202 / 373.633 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 950.755 | 1.024 | 1.132 | 1.606 | 99.379 / 373.633 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1905.035 | 5.172 | 6.433 | 7.238 | 198.815 / 373.633 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1869.195 | 26.243 | 29.594 | 38.959 | 200.024 / 373.633 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 933.658 | 1.047 | 1.115 | 1.172 | 99.480 / 373.664 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1841.545 | 5.755 | 6.540 | 8.820 | 198.804 / 373.664 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1895.075 | 25.563 | 27.169 | 33.640 | 200.225 / 373.664 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 944.183 | 1.034 | 1.126 | 1.484 | 99.902 / 373.789 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1856.059 | 5.310 | 5.707 | 7.765 | 199.312 / 373.789 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1888.870 | 26.189 | 27.225 | 33.744 | 200.784 / 373.789 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1812.054 | 53.706 | 64.301 | 91.262 | 201.659 / 376.723 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 65.888 | 15.110 | 15.833 | 16.580 | 66.614 / 377.043 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 119.987 | 81.642 | 106.238 | 140.640 | 131.704 / 377.422 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 111.303 | 400.940 | 719.525 | 839.957 | 131.839 / 377.422 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.755 | 845.691 | 1594.742 | 1686.236 | 131.385 / 377.422 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 968.299 | 1.019 | 1.089 | 1.228 | 99.363 / 377.422 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1894.374 | 5.644 | 6.589 | 7.567 | 199.301 / 377.422 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1802.770 | 26.470 | 37.360 | 47.640 | 200.710 / 377.422 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1894.675 | 51.804 | 54.316 | 82.800 | 201.170 / 377.422 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1425.393 | 6.121 | 9.719 | 12.260 | 24.757 / 377.422 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1026.325 | 8.701 | 13.967 | 15.011 | 37.726 / 377.727 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2459.619 | 20.946 | 40.336 | 48.907 | 379.138 / 613.785 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2502.424 | 35.004 | 62.505 | 84.317 | 388.541 / 617.539 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 156.670 | 224.973 | 604.797 | 669.936 | 235.128 / 619.992 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 149.485 | 438.740 | 1173.546 | 1316.241 | 242.871 / 621.516 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1970.342 | 26.862 | 36.214 | 46.608 | 220.786 / 621.516 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2615.588 | 35.531 | 49.003 | 57.829 | 387.595 / 621.535 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 223.887 | 4.401 | 4.841 | 6.128 | 99.479 / 369.480 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 440.955 | 25.410 | 30.397 | 45.387 | 200.127 / 369.617 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 446.008 | 108.337 | 143.033 | 205.579 | 201.650 / 371.484 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1378.897 | 0.713 | 0.778 | 0.821 | 99.408 / 369.480 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2653.330 | 3.645 | 4.909 | 6.487 | 198.848 / 369.480 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2699.426 | 18.123 | 19.934 | 28.809 | 200.206 / 370.277 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2643.363 | 37.022 | 44.594 | 59.136 | 199.225 / 371.652 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 100.967 | 9.827 | 10.504 | 10.996 | 87.503 / 371.934 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 183.180 | 51.477 | 71.870 | 109.916 | 173.954 / 372.707 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 161.185 | 282.958 | 489.343 | 555.303 | 173.640 / 374.992 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 993.945 | 0.991 | 1.059 | 1.116 | 99.856 / 374.992 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1944.417 | 5.083 | 5.948 | 8.890 | 199.297 / 374.992 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1932.407 | 25.239 | 30.762 | 43.537 | 200.541 / 374.992 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 980.144 | 1.002 | 1.090 | 1.163 | 99.044 / 375.156 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1872.404 | 5.218 | 7.098 | 9.253 | 198.848 / 375.156 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1882.077 | 26.221 | 30.159 | 47.733 | 199.723 / 375.156 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 960.423 | 1.001 | 1.247 | 1.738 | 99.834 / 375.281 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1848.517 | 5.328 | 6.601 | 9.249 | 199.355 / 375.281 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1840.537 | 26.566 | 28.152 | 48.565 | 200.216 / 375.281 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1812.107 | 53.699 | 58.077 | 92.023 | 199.138 / 378.145 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 62.404 | 15.828 | 16.638 | 17.805 | 67.135 / 378.809 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 115.238 | 75.542 | 108.275 | 184.252 | 131.565 / 378.809 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 99.245 | 427.243 | 799.695 | 864.697 | 131.390 / 378.809 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.298 | 844.845 | 1580.121 | 1673.802 | 131.384 / 378.809 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 998.762 | 0.979 | 1.082 | 1.154 | 99.402 / 378.809 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1889.267 | 5.226 | 6.872 | 9.138 | 199.096 / 378.809 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1923.017 | 26.015 | 27.514 | 45.846 | 200.158 / 378.809 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1864.942 | 52.389 | 56.252 | 91.432 | 201.647 / 378.809 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2257.485 | 21.463 | 32.056 | 40.911 | 299.535 / 615.832 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2535.416 | 31.601 | 62.504 | 69.938 | 384.826 / 619.809 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 161.612 | 237.959 | 615.653 | 881.739 | 231.481 / 621.340 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 143.298 | 475.209 | 1346.872 | 1434.694 | 239.450 / 622.738 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1955.298 | 25.709 | 37.358 | 44.278 | 202.642 / 622.742 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2584.492 | 33.795 | 64.481 | 81.667 | 384.502 / 622.742 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.574 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.448 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.517 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.601 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.101 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 4.147 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.304 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.121 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.009 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.507 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.570 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.285 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.347 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.085 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.376 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.553 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.562 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.635 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.492 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.644 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.315 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.385 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.115 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.562 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.201 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.182 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.196 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.058 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.109 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.087 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 694.992 | 143.271 | 159.355 | 164.069 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1179.403 | 163.992 | 192.913 | 193.657 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.6%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +2.3%, p95_ms: -0.1%, p99_ms: +12.6%, requests_per_second: -1.7%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -0.6%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +15.6%, p95_ms: +21.5%, p99_ms: +25.2%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +8.2%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -5.2%, p95_ms: +5.3%, p99_ms: +3.7%, requests_per_second: +8.3%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.5%, cpu_percent: -0.9%, duration_seconds: -4.8%, p50_ms: -3.5%, p95_ms: -3.2%, p99_ms: -5.8%, requests_per_second: +3.4%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +3.4%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -3.1%, p95_ms: +25.7%, p99_ms: +46.9%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.4%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -0.8%, p95_ms: -1.0%, p99_ms: +1.9%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.4%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: -1.7%, p95_ms: +8.3%, p99_ms: +4.4%, requests_per_second: +1.6%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.6%, cpu_percent: +1.2%, duration_seconds: -0.1%, p50_ms: -6.8%, p95_ms: -8.3%, p99_ms: -16.7%, requests_per_second: +8.7%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +8.9%, cpu_percent: +0.9%, duration_seconds: +0.0%, p50_ms: -11.7%, p95_ms: -6.7%, p99_ms: +10.9%, requests_per_second: +8.9%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.3%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +2.4%, p95_ms: +4.7%, p99_ms: +3.3%, requests_per_second: -0.3%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +9.1%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: -3.2%, p95_ms: -6.4%, p99_ms: -30.5%, requests_per_second: +4.5%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +5.5%, cpu_percent: +0.2%, duration_seconds: +4.8%, p50_ms: -1.7%, p95_ms: -7.5%, p99_ms: +22.8%, requests_per_second: +2.1%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +3.3%, cpu_percent: +0.3%, duration_seconds: -0.2%, p50_ms: -3.8%, p95_ms: +3.9%, p99_ms: +11.8%, requests_per_second: +3.4%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +10.2%, cpu_percent: -0.4%, duration_seconds: +4.9%, p50_ms: -4.3%, p95_ms: -2.2%, p99_ms: -0.8%, requests_per_second: +5.0%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.5%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -9.3%, p95_ms: +8.5%, p99_ms: +4.9%, requests_per_second: +1.7%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -0.7%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +2.6%, p95_ms: +11.0%, p99_ms: +41.9%, requests_per_second: -0.7%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.2%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -3.2%, p95_ms: +10.7%, p99_ms: +17.1%, requests_per_second: +1.7%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +3.2%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +0.3%, p95_ms: +15.7%, p99_ms: +19.1%, requests_per_second: -0.4%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -2.5%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +1.4%, p95_ms: +3.4%, p99_ms: +43.9%, requests_per_second: -2.6%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: -1.2%, duration_seconds: +0.2%, p50_ms: -0.0%, p95_ms: -9.7%, p99_ms: +0.8%, requests_per_second: +0.0%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -5.3%, cpu_percent: +0.8%, duration_seconds: -0.1%, p50_ms: +4.8%, p95_ms: +5.1%, p99_ms: +7.4%, requests_per_second: -5.3%, rss_bytes: +0.5% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.2%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -7.5%, p95_ms: +1.9%, p99_ms: +31.0%, requests_per_second: -4.0%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -10.8%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +6.6%, p95_ms: +11.1%, p99_ms: +2.9%, requests_per_second: -10.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -0.1%, p95_ms: -0.9%, p99_ms: -0.7%, requests_per_second: -0.5%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +6.6%, cpu_percent: +0.0%, duration_seconds: +4.9%, p50_ms: -3.9%, p95_ms: -0.6%, p99_ms: -6.0%, requests_per_second: +3.1%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +3.7%, cpu_percent: -0.1%, duration_seconds: +4.9%, p50_ms: -7.4%, p95_ms: +4.3%, p99_ms: +20.8%, requests_per_second: -0.3%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +6.7%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -1.7%, p95_ms: -26.4%, p99_ms: -3.8%, requests_per_second: +6.7%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -1.6%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +1.1%, p95_ms: +3.6%, p99_ms: +10.4%, requests_per_second: -1.6%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -8.4%, cpu_percent: -21.0%, duration_seconds: -0.2%, p50_ms: +2.5%, p95_ms: -20.5%, p99_ms: -16.3%, requests_per_second: -8.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +5.3%, cpu_percent: -1.0%, duration_seconds: +4.7%, p50_ms: -9.7%, p95_ms: -0.0%, p99_ms: -17.1%, requests_per_second: +1.3%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +3.2%, cpu_percent: -1.6%, duration_seconds: -0.1%, p50_ms: +5.8%, p95_ms: +1.8%, p99_ms: +31.6%, requests_per_second: +3.2%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -4.3%, cpu_percent: -1.4%, duration_seconds: -0.1%, p50_ms: +8.3%, p95_ms: +14.8%, p99_ms: +9.0%, requests_per_second: -4.1%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.7%, cpu_percent: -8.2%, duration_seconds: +0.1%, p50_ms: -4.3%, p95_ms: +3.2%, p99_ms: -5.0%, requests_per_second: -0.8%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -1.6%, cpu_percent: -0.8%, duration_seconds: +0.1%, p50_ms: -4.9%, p95_ms: +31.6%, p99_ms: +41.2%, requests_per_second: -1.2%, rss_bytes: +0.2% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +30.4%, cpu_percent: +88.8%, duration_seconds: +0.2%, p50_ms: -20.0%, p95_ms: +48.2%, p99_ms: +44.9%, requests_per_second: +30.2%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | improvement | completed: +38.2%, cpu_percent: +92.7%, duration_seconds: +0.1%, p50_ms: -34.8%, p95_ms: -2.8%, p99_ms: -7.6%, requests_per_second: +38.1%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +41.3%, cpu_percent: +78.3%, duration_seconds: +0.3%, p50_ms: -43.9%, p95_ms: -15.9%, p99_ms: -20.2%, requests_per_second: +40.8%, rss_bytes: +64.3% |
| search | workers=4 | 2 | 100 | improvement | completed: +50.5%, cpu_percent: +84.9%, duration_seconds: +0.4%, p50_ms: -48.1%, p95_ms: -26.4%, p99_ms: -21.9%, requests_per_second: +49.9%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: +9.2%, cpu_percent: +10.0%, duration_seconds: -0.0%, p50_ms: +1.5%, p95_ms: -3.1%, p99_ms: -2.2%, requests_per_second: +9.3%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +38.7%, cpu_percent: +92.7%, duration_seconds: +0.0%, p50_ms: -31.4%, p95_ms: -9.8%, p99_ms: -30.2%, requests_per_second: +38.0%, rss_bytes: +64.7% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +22.6%, cpu_percent: +49.6%, duration_seconds: -0.1%, p50_ms: -19.2%, p95_ms: +13.9%, p99_ms: -15.8%, requests_per_second: +22.7%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +45.5%, cpu_percent: +93.2%, duration_seconds: +4.6%, p50_ms: -41.2%, p95_ms: +7.6%, p99_ms: -24.0%, requests_per_second: +39.9%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +63.3%, cpu_percent: +76.2%, duration_seconds: +0.2%, p50_ms: -44.3%, p95_ms: -23.0%, p99_ms: +2.0%, requests_per_second: +62.8%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 100 | improvement | completed: +44.7%, cpu_percent: +82.3%, duration_seconds: +0.4%, p50_ms: -43.8%, p95_ms: -14.8%, p99_ms: -14.3%, requests_per_second: +44.3%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: +1.7%, cpu_percent: +1.2%, duration_seconds: +0.1%, p50_ms: -1.2%, p95_ms: +35.8%, p99_ms: -3.4%, requests_per_second: +1.7%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +38.7%, cpu_percent: +90.7%, duration_seconds: +0.2%, p50_ms: -35.5%, p95_ms: +14.6%, p99_ms: -10.7%, requests_per_second: +38.6%, rss_bytes: +64.4% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38695193520)
