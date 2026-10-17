# GPForum continuous performance evidence

Commit: `762f14c44bc08e6698218ac19a8bbba03e252d91` · mode: **main** · status: **ok**
Run: 38689092090 / attempt 1 · 2026-10-15T05:52:16.191951+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V45 96-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"26f1e2022f330a9d556751cff40314eccd166da8aea629f96e6992e8e

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 535.822 | 1.839 | 1.938 | 2.154 | 99.567 / 369.961 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1067.933 | 9.053 | 11.482 | 13.953 | 199.043 / 369.961 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1051.755 | 46.851 | 51.889 | 73.739 | 200.467 / 371.645 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 2384.935 | 0.413 | 0.449 | 0.478 | 99.593 / 369.898 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 4589.122 | 2.109 | 2.719 | 3.441 | 199.163 / 369.898 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 4878.409 | 10.231 | 10.887 | 16.740 | 200.122 / 370.570 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 4854.886 | 20.477 | 21.364 | 26.150 | 200.614 / 371.855 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 235.975 | 4.230 | 4.377 | 5.741 | 82.829 / 372.305 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 441.392 | 21.581 | 29.518 | 40.729 | 165.396 / 372.688 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 431.948 | 113.470 | 139.389 | 199.623 | 167.261 / 374.512 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1791.708 | 0.555 | 0.586 | 0.621 | 99.582 / 374.512 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3527.808 | 3.215 | 3.636 | 4.593 | 199.555 / 374.512 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3617.736 | 14.084 | 15.691 | 23.203 | 200.130 / 374.512 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1784.181 | 0.555 | 0.596 | 0.667 | 99.636 / 374.668 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3454.509 | 2.856 | 3.609 | 4.421 | 199.152 / 374.668 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3576.718 | 14.509 | 15.745 | 16.334 | 200.118 / 374.668 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1731.753 | 0.565 | 0.624 | 0.824 | 99.585 / 374.793 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3229.960 | 3.439 | 4.184 | 6.307 | 199.142 / 374.793 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3394.914 | 14.510 | 15.627 | 20.120 | 199.556 / 375.383 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3492.799 | 28.242 | 29.067 | 35.914 | 200.103 / 378.590 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 140.929 | 7.138 | 7.319 | 9.669 | 61.268 / 379.016 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 245.788 | 43.013 | 60.181 | 75.076 | 121.959 / 379.016 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 222.690 | 202.964 | 323.265 | 413.709 | 125.111 / 379.016 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 222.518 | 389.606 | 749.301 | 845.233 | 124.163 / 379.016 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1724.125 | 0.553 | 0.639 | 1.120 | 102.884 / 379.016 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3404.406 | 2.887 | 3.113 | 4.192 | 199.450 / 379.016 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3567.178 | 14.160 | 15.507 | 19.182 | 200.021 / 379.016 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3520.125 | 27.661 | 30.302 | 43.590 | 199.909 / 379.016 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 2801.582 | 3.050 | 4.962 | 5.867 | 22.529 / 379.016 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1731.659 | 5.026 | 8.425 | 10.330 | 34.278 / 379.297 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 4873.522 | 10.494 | 19.864 | 22.434 | 383.817 / 616.145 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 4869.769 | 23.834 | 34.522 | 46.674 | 382.050 / 620.887 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 284.874 | 180.057 | 420.534 | 509.700 | 187.908 / 623.387 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 288.721 | 182.046 | 772.419 | 841.076 | 225.237 / 624.293 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 3594.656 | 14.640 | 20.180 | 23.853 | 208.831 / 624.293 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 4316.921 | 33.359 | 35.063 | 43.716 | 300.584 / 624.293 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 537.757 | 1.835 | 1.948 | 2.724 | 100.013 / 371.020 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1053.751 | 9.318 | 12.948 | 18.396 | 199.014 / 371.047 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1042.776 | 46.683 | 53.515 | 81.453 | 201.007 / 372.859 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 2387.551 | 0.407 | 0.453 | 0.751 | 99.562 / 371.055 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 4705.907 | 2.104 | 2.898 | 3.950 | 199.164 / 371.055 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 4915.099 | 10.111 | 10.511 | 11.368 | 200.047 / 371.734 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 4775.405 | 20.747 | 21.718 | 32.434 | 198.958 / 373.125 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 236.102 | 4.143 | 4.569 | 4.900 | 84.139 / 373.562 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 435.593 | 22.024 | 32.655 | 43.335 | 166.166 / 373.961 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 419.855 | 111.492 | 153.664 | 233.282 | 167.197 / 375.660 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1795.462 | 0.542 | 0.596 | 0.700 | 99.587 / 375.664 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3532.658 | 2.831 | 3.686 | 4.681 | 199.140 / 375.664 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3585.263 | 13.480 | 17.794 | 25.187 | 199.435 / 375.664 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1780.373 | 0.553 | 0.602 | 0.630 | 99.530 / 375.742 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3396.973 | 2.987 | 4.260 | 5.442 | 199.177 / 375.742 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3537.506 | 14.093 | 15.824 | 22.978 | 200.077 / 375.855 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1775.919 | 0.555 | 0.601 | 0.622 | 99.595 / 375.918 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3400.053 | 2.888 | 3.830 | 5.755 | 199.121 / 375.980 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3472.536 | 14.653 | 17.754 | 24.858 | 200.452 / 376.535 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3304.308 | 28.972 | 35.867 | 48.057 | 198.811 / 379.637 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 133.855 | 7.335 | 7.933 | 11.522 | 60.754 / 380.168 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 239.252 | 42.421 | 63.821 | 100.204 | 124.382 / 380.289 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 233.356 | 201.784 | 334.925 | 403.787 | 125.551 / 380.289 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 221.086 | 356.856 | 753.755 | 835.412 | 123.208 / 380.344 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1778.522 | 0.550 | 0.603 | 1.085 | 99.575 / 380.344 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3500.445 | 2.785 | 4.069 | 6.045 | 199.169 / 380.344 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3558.660 | 13.805 | 14.638 | 22.636 | 200.090 / 380.344 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3540.446 | 28.708 | 31.117 | 46.396 | 199.999 / 380.344 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 5036.192 | 8.202 | 19.336 | 24.650 | 383.193 / 618.043 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 4917.017 | 17.215 | 35.830 | 44.528 | 385.279 / 623.441 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 284.262 | 193.825 | 362.618 | 481.316 | 188.058 / 624.770 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 288.896 | 280.359 | 793.095 | 1076.776 | 210.115 / 627.625 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4353.025 | 10.850 | 20.904 | 23.708 | 300.846 / 627.625 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 5156.782 | 21.132 | 34.784 | 39.526 | 385.739 / 627.824 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.319 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.023 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.305 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.357 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.072 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.221 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.271 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.077 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.071 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.278 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.318 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.159 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.215 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.058 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.031 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.030 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.014 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.265 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.330 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.335 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.317 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.309 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.157 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.214 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.754 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.840 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.121 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.116 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.038 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.012 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.072 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.044 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.045 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 969.412 | 102.122 | 114.133 | 179.126 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1644.986 | 118.939 | 131.891 | 132.180 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: +0.4%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -0.2%, p95_ms: +0.5%, p99_ms: +26.5%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -1.9%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +2.9%, p95_ms: +12.8%, p99_ms: +31.8%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -1.3%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -0.4%, p95_ms: +3.1%, p99_ms: +10.5%, requests_per_second: -0.9%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.7%, cpu_percent: -0.0%, duration_seconds: +5.0%, p50_ms: -1.5%, p95_ms: +0.9%, p99_ms: +57.1%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -2.3%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: -0.2%, p95_ms: +6.6%, p99_ms: +14.8%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +0.7%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -1.2%, p95_ms: -3.5%, p99_ms: -32.1%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.6%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: +1.3%, p95_ms: +1.7%, p99_ms: +24.0%, requests_per_second: -1.6%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.0%, cpu_percent: +1.6%, duration_seconds: -0.1%, p50_ms: -2.1%, p95_ms: +4.4%, p99_ms: -14.6%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -3.5%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +2.1%, p95_ms: +10.6%, p99_ms: +6.4%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -2.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -1.7%, p95_ms: +10.2%, p99_ms: +16.9%, requests_per_second: -2.8%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +5.2%, cpu_percent: +0.0%, duration_seconds: +5.0%, p50_ms: -2.3%, p95_ms: +1.7%, p99_ms: +12.7%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +0.2%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -11.9%, p95_ms: +1.4%, p99_ms: +1.9%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.7%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: -4.3%, p95_ms: +13.4%, p99_ms: +8.6%, requests_per_second: -0.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.6%, cpu_percent: -0.1%, duration_seconds: +5.0%, p50_ms: -0.4%, p95_ms: +1.0%, p99_ms: -5.5%, requests_per_second: -0.2%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -6.3%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: +4.6%, p95_ms: +18.0%, p99_ms: +23.1%, requests_per_second: -1.7%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -1.1%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -2.9%, p95_ms: +0.5%, p99_ms: +40.7%, requests_per_second: -1.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.3%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -1.8%, p95_ms: -3.7%, p99_ms: -24.5%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +8.5%, cpu_percent: -0.0%, duration_seconds: +4.8%, p50_ms: -16.0%, p95_ms: -8.5%, p99_ms: -8.8%, requests_per_second: +5.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +2.2%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +1.0%, p95_ms: +13.6%, p99_ms: +23.5%, requests_per_second: +2.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -5.4%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +2.6%, p95_ms: +23.4%, p99_ms: +33.8%, requests_per_second: -5.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -5.0%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: +2.8%, p95_ms: +8.4%, p99_ms: +19.2%, requests_per_second: -5.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -2.6%, cpu_percent: +2.0%, duration_seconds: -0.0%, p50_ms: -1.4%, p95_ms: +6.0%, p99_ms: +33.5%, requests_per_second: -2.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +4.9%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: +3.6%, p99_ms: -2.4%, requests_per_second: +4.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.9%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: -8.4%, p95_ms: +0.6%, p99_ms: -1.2%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.6%, cpu_percent: -3.2%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: -5.6%, p99_ms: -3.1%, requests_per_second: +3.2%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +7.9%, cpu_percent: -0.1%, duration_seconds: +4.9%, p50_ms: -3.5%, p95_ms: +30.7%, p99_ms: +44.2%, requests_per_second: +2.8%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.4%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -2.5%, p95_ms: -5.6%, p99_ms: +18.0%, requests_per_second: -0.2%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.7%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +3.8%, p95_ms: +2.7%, p99_ms: +6.4%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +3.5%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -21.8%, p95_ms: -2.7%, p99_ms: +9.9%, requests_per_second: +3.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +1.0%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: -27.8%, p95_ms: +3.8%, p99_ms: -4.6%, requests_per_second: +1.0%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -0.2%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +7.6%, p95_ms: -13.8%, p99_ms: -5.6%, requests_per_second: -0.2%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: +0.0%, cpu_percent: -6.7%, duration_seconds: -0.1%, p50_ms: +54.0%, p95_ms: +2.7%, p99_ms: +28.0%, requests_per_second: +0.1%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +27.0%, cpu_percent: +44.1%, duration_seconds: +4.9%, p50_ms: -25.9%, p95_ms: +3.6%, p99_ms: -0.6%, requests_per_second: +21.1%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +19.4%, cpu_percent: +28.3%, duration_seconds: +0.3%, p50_ms: -36.7%, p95_ms: -0.8%, p99_ms: -9.6%, requests_per_second: +19.5%, rss_bytes: +0.6% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +43.2%, cpu_percent: +92.3%, duration_seconds: -0.2%, p50_ms: -27.7%, p95_ms: +27.1%, p99_ms: +11.5%, requests_per_second: +43.6%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +39.5%, cpu_percent: +90.9%, duration_seconds: +0.0%, p50_ms: -15.6%, p95_ms: +18.8%, p99_ms: +30.0%, requests_per_second: +39.4%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +28.3%, cpu_percent: +50.2%, duration_seconds: +0.1%, p50_ms: -11.3%, p95_ms: +30.1%, p99_ms: +23.2%, requests_per_second: +27.9%, rss_bytes: +64.5% |
| search | workers=4 | 2 | 100 | improvement | completed: +30.0%, cpu_percent: +81.4%, duration_seconds: +0.3%, p50_ms: -53.3%, p95_ms: +3.1%, p99_ms: -0.5%, requests_per_second: +29.8%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +0.6%, cpu_percent: +4.4%, duration_seconds: -0.1%, p50_ms: +3.4%, p95_ms: +30.1%, p99_ms: +24.4%, requests_per_second: +0.8%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +22.7%, cpu_percent: +50.4%, duration_seconds: +0.0%, p50_ms: +20.6%, p95_ms: +15.7%, p99_ms: +0.3%, requests_per_second: +22.6%, rss_bytes: +64.7% |
| thread | workers=4 | 2 | 50 | improvement | completed: +45.0%, cpu_percent: +91.2%, duration_seconds: +0.0%, p50_ms: -44.0%, p95_ms: +8.9%, p99_ms: -0.8%, requests_per_second: +45.0%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +48.8%, cpu_percent: +93.8%, duration_seconds: -0.0%, p50_ms: -40.6%, p95_ms: -0.1%, p99_ms: -7.3%, requests_per_second: +48.8%, rss_bytes: +64.2% |
| search | workers=4 | 2 | 50 | improvement | completed: +22.0%, cpu_percent: +49.8%, duration_seconds: +0.1%, p50_ms: -3.9%, p95_ms: +8.3%, p99_ms: +19.2%, requests_per_second: +21.8%, rss_bytes: +64.3% |
| search | workers=4 | 2 | 100 | possible-regression | completed: +31.2%, cpu_percent: +70.5%, duration_seconds: +0.2%, p50_ms: -21.4%, p95_ms: +5.2%, p99_ms: +28.9%, requests_per_second: +30.7%, rss_bytes: +65.0% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +28.3%, cpu_percent: +50.4%, duration_seconds: +4.9%, p50_ms: -21.4%, p95_ms: +42.8%, p99_ms: +4.7%, requests_per_second: +22.3%, rss_bytes: +65.0% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +45.6%, cpu_percent: +92.9%, duration_seconds: +0.3%, p50_ms: -26.4%, p95_ms: +11.8%, p99_ms: -14.8%, requests_per_second: +45.7%, rss_bytes: +65.1% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38689092090)
