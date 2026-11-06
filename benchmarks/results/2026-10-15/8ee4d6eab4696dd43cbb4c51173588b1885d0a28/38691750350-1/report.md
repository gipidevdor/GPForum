# GPForum continuous performance evidence

Commit: `8ee4d6eab4696dd43cbb4c51173588b1885d0a28` · mode: **main** · status: **ok**
Run: 38691750350 / attempt 1 · 2026-10-15T06:20:10.030404+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 57b2c5eb62f559cf320cc713683352b0dd091018

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 210.922 | 4.673 | 4.852 | 5.864 | 99.516 / 369.859 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 407.801 | 24.079 | 26.278 | 36.194 | 199.713 / 369.957 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 389.870 | 121.310 | 145.083 | 219.951 | 200.880 / 371.785 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1159.649 | 0.855 | 0.918 | 0.987 | 99.458 / 370.180 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2261.101 | 4.391 | 4.628 | 5.566 | 198.467 / 370.180 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2321.416 | 21.346 | 22.567 | 27.215 | 200.207 / 370.836 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2245.612 | 43.826 | 48.073 | 64.886 | 201.684 / 372.070 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 97.955 | 10.108 | 10.972 | 12.384 | 88.018 / 372.445 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 173.159 | 55.333 | 65.317 | 85.953 | 176.865 / 373.145 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 161.625 | 279.735 | 509.207 | 583.180 | 177.005 / 375.457 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 859.766 | 1.146 | 1.218 | 1.310 | 99.413 / 375.457 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1685.840 | 5.771 | 7.012 | 8.675 | 199.223 / 375.457 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1733.187 | 28.545 | 29.902 | 36.021 | 200.236 / 375.457 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 839.456 | 1.169 | 1.238 | 1.490 | 99.453 / 375.488 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1663.640 | 5.965 | 6.227 | 7.798 | 199.234 / 375.488 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1705.744 | 29.657 | 32.354 | 42.064 | 200.701 / 375.488 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 838.419 | 1.159 | 1.251 | 1.836 | 99.444 / 375.613 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1686.426 | 5.874 | 6.153 | 7.715 | 199.428 / 375.613 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1674.313 | 29.229 | 30.575 | 42.269 | 200.027 / 375.613 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1670.946 | 58.965 | 61.641 | 95.621 | 202.219 / 378.426 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 72.490 | 13.522 | 14.775 | 16.699 | 66.185 / 379.266 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 130.320 | 73.327 | 89.482 | 135.627 | 130.970 / 379.266 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 106.110 | 414.090 | 691.168 | 746.517 | 131.940 / 379.266 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.806 | 763.319 | 1433.518 | 1491.775 | 131.415 / 379.266 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 858.930 | 1.144 | 1.229 | 1.356 | 98.941 / 379.266 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1696.874 | 5.830 | 6.061 | 7.341 | 198.659 / 379.266 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1732.966 | 28.889 | 30.256 | 37.509 | 199.652 / 379.266 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1598.251 | 60.487 | 73.905 | 96.225 | 200.964 / 379.266 | possible-regression |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1416.430 | 6.125 | 11.107 | 13.700 | 24.789 / 379.266 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 978.177 | 9.232 | 16.749 | 18.299 | 38.320 / 379.547 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2379.345 | 20.803 | 36.324 | 44.887 | 377.681 / 616.078 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2421.361 | 35.850 | 71.813 | 86.042 | 383.925 / 620.148 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 146.151 | 264.714 | 727.993 | 955.269 | 233.257 / 621.668 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 136.717 | 468.893 | 1239.519 | 1378.097 | 238.631 / 623.078 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2074.447 | 21.327 | 43.382 | 48.427 | 300.361 / 623.359 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2506.092 | 33.674 | 65.358 | 80.528 | 389.795 / 623.359 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 212.803 | 4.666 | 4.956 | 5.820 | 99.534 / 371.113 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 405.697 | 23.982 | 26.874 | 41.910 | 201.163 / 371.254 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 384.680 | 122.257 | 153.615 | 226.640 | 200.700 / 373.188 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1169.160 | 0.840 | 0.915 | 0.947 | 99.433 / 370.688 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2310.133 | 4.300 | 4.486 | 5.400 | 198.947 / 370.688 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2339.540 | 21.230 | 22.106 | 26.778 | 199.409 / 371.555 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2266.759 | 43.733 | 46.560 | 68.811 | 200.248 / 372.926 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 99.434 | 9.963 | 10.517 | 12.403 | 88.543 / 373.344 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 195.249 | 50.103 | 56.131 | 90.164 | 177.037 / 374.059 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 173.571 | 251.011 | 426.564 | 495.363 | 176.758 / 376.352 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 875.360 | 1.135 | 1.195 | 1.377 | 99.944 / 376.352 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1710.740 | 5.742 | 6.190 | 8.681 | 198.715 / 376.352 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1730.511 | 28.101 | 34.776 | 47.607 | 199.190 / 376.352 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 871.907 | 1.133 | 1.200 | 1.283 | 99.824 / 376.430 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1673.829 | 5.907 | 6.154 | 8.463 | 198.958 / 376.445 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1693.904 | 28.918 | 31.815 | 43.457 | 200.903 / 376.445 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 850.686 | 1.153 | 1.242 | 1.563 | 99.465 / 376.570 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1615.795 | 5.960 | 7.255 | 10.388 | 198.940 / 376.570 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1638.423 | 30.227 | 34.582 | 48.838 | 200.348 / 376.570 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1644.390 | 59.487 | 62.117 | 101.281 | 200.237 / 379.488 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 67.435 | 14.661 | 16.772 | 17.823 | 67.636 / 380.164 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 121.284 | 74.097 | 110.444 | 137.795 | 133.813 / 380.164 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.237 | 377.983 | 753.176 | 812.195 | 130.482 / 380.164 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.776 | 759.134 | 1430.169 | 1572.468 | 132.865 / 380.164 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 872.023 | 1.123 | 1.214 | 1.390 | 100.418 / 380.164 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1710.447 | 5.792 | 6.530 | 8.915 | 199.390 / 380.164 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1733.965 | 28.288 | 32.836 | 37.305 | 199.595 / 380.164 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1701.761 | 57.003 | 63.936 | 97.532 | 201.768 / 380.164 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2507.934 | 22.346 | 31.876 | 40.920 | 388.826 / 618.023 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2484.066 | 34.540 | 59.681 | 72.965 | 386.126 / 622.074 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 153.455 | 144.989 | 677.790 | 805.464 | 230.764 / 623.270 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 138.876 | 490.132 | 1122.960 | 1195.258 | 239.277 / 624.461 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1673.036 | 38.465 | 57.125 | 80.160 | 211.836 / 624.562 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2552.190 | 36.058 | 53.439 | 62.598 | 388.295 / 624.562 | improvement |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.524 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.471 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.547 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.677 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.099 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.574 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.053 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.131 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.036 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.670 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.606 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.308 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.363 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.132 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.050 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.056 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.396 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.449 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.430 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.572 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.429 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.518 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.290 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.385 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.961 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.374 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.201 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.182 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.192 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.016 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.097 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.057 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.081 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 654.707 | 150.531 | 165.317 | 167.356 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1105.988 | 177.844 | 196.148 | 202.267 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | confirmed-regression | completed: -19.0%, cpu_percent: -0.0%, duration_seconds: +5.0%, p50_ms: +29.8%, p95_ms: +28.9%, p99_ms: +45.4%, requests_per_second: -22.8%, rss_bytes: -0.1% |
| cache_miss | confirmed-regression | completed: -23.6%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +31.6%, p95_ms: +17.8%, p99_ms: +37.8%, requests_per_second: -23.7%, rss_bytes: -0.1% |
| cache_miss | confirmed-regression | completed: -26.6%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +33.9%, p95_ms: +45.4%, p99_ms: +37.4%, requests_per_second: -26.7%, rss_bytes: -0.0% |
| health_live | stable | completed: -1.5%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: +0.6%, p95_ms: +1.9%, p99_ms: +5.9%, requests_per_second: -0.5%, rss_bytes: -0.0% |
| health_live | stable | completed: +0.1%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: +1.8%, p99_ms: +1.0%, requests_per_second: -0.6%, rss_bytes: -0.0% |
| health_live | stable | completed: +0.0%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +0.2%, p95_ms: -0.7%, p99_ms: +5.0%, requests_per_second: +0.0%, rss_bytes: -0.0% |
| health_live | stable | completed: +1.1%, cpu_percent: +0.9%, duration_seconds: -0.1%, p50_ms: -1.1%, p95_ms: +4.9%, p99_ms: -2.0%, requests_per_second: +1.2%, rss_bytes: -0.0% |
| home | confirmed-regression | completed: -18.3%, cpu_percent: +1.7%, duration_seconds: +0.0%, p50_ms: +22.4%, p95_ms: +26.1%, p99_ms: +33.3%, requests_per_second: -18.3%, rss_bytes: +0.0% |
| home | confirmed-regression | completed: -19.6%, cpu_percent: +1.6%, duration_seconds: -0.0%, p50_ms: +29.6%, p95_ms: +29.6%, p99_ms: +23.3%, requests_per_second: -23.4%, rss_bytes: +0.1% |
| home | confirmed-regression | completed: -28.0%, cpu_percent: +1.5%, duration_seconds: +0.0%, p50_ms: +28.8%, p95_ms: +56.2%, p99_ms: +46.1%, requests_per_second: -28.0%, rss_bytes: +0.2% |
| categories | stable | completed: +4.5%, cpu_percent: +0.0%, duration_seconds: +4.9%, p50_ms: +0.3%, p95_ms: +1.1%, p99_ms: +5.8%, requests_per_second: -0.4%, rss_bytes: +0.2% |
| categories | stable | completed: +2.5%, cpu_percent: -0.3%, duration_seconds: +4.9%, p50_ms: +0.3%, p95_ms: +17.6%, p99_ms: +24.4%, requests_per_second: -2.3%, rss_bytes: +0.2% |
| categories | stable | completed: +0.0%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: +1.7%, p95_ms: -3.1%, p99_ms: -0.8%, requests_per_second: +0.1%, rss_bytes: +0.2% |
| category | stable | completed: +0.5%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: -1.8%, p99_ms: +1.6%, requests_per_second: +0.5%, rss_bytes: +0.2% |
| category | stable | completed: -1.7%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: +1.6%, p95_ms: +2.0%, p99_ms: +8.7%, requests_per_second: -1.7%, rss_bytes: +0.2% |
| category | stable | completed: +0.2%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +1.3%, p95_ms: +6.6%, p99_ms: +9.0%, requests_per_second: +0.2%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: +1.1%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -4.4%, p95_ms: -0.4%, p99_ms: +41.8%, requests_per_second: +1.2%, rss_bytes: +0.2% |
| thread | stable | completed: +0.7%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -0.7%, p95_ms: +0.8%, p99_ms: +1.4%, requests_per_second: +0.9%, rss_bytes: +0.2% |
| thread | stable | completed: -1.4%, cpu_percent: -0.7%, duration_seconds: -0.1%, p50_ms: -0.1%, p95_ms: -0.3%, p99_ms: +12.6%, requests_per_second: -1.3%, rss_bytes: +0.1% |
| thread | improvement | completed: +1.5%, cpu_percent: +1.0%, duration_seconds: -0.1%, p50_ms: -0.0%, p95_ms: -18.5%, p99_ms: -0.3%, requests_per_second: +1.5%, rss_bytes: -0.0% |
| search | stable | completed: -4.0%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +2.7%, p95_ms: +7.2%, p99_ms: +1.1%, requests_per_second: -3.9%, rss_bytes: +0.0% |
| search | stable | completed: -4.4%, cpu_percent: -1.0%, duration_seconds: +0.0%, p50_ms: +2.0%, p95_ms: +2.0%, p99_ms: +2.6%, requests_per_second: -4.4%, rss_bytes: +0.0% |
| search | stable | completed: -14.8%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +14.5%, p95_ms: +12.8%, p99_ms: +7.9%, requests_per_second: -15.0%, rss_bytes: +0.0% |
| search | stable | completed: +0.0%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +6.0%, p95_ms: +6.4%, p99_ms: +6.5%, requests_per_second: +0.0%, rss_bytes: +0.0% |
| cache_hit | stable | completed: -1.3%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +0.4%, p95_ms: +2.6%, p99_ms: +8.6%, requests_per_second: -1.2%, rss_bytes: +0.0% |
| cache_hit | stable | completed: -5.4%, cpu_percent: -0.4%, duration_seconds: -4.6%, p50_ms: +0.5%, p95_ms: +0.5%, p99_ms: +12.8%, requests_per_second: -0.8%, rss_bytes: +0.0% |
| cache_hit | stable | completed: +0.3%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +2.2%, p95_ms: -5.5%, p99_ms: -2.8%, requests_per_second: +0.2%, rss_bytes: +0.0% |
| cache_hit | possible-regression | completed: -7.1%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +6.4%, p95_ms: +22.5%, p99_ms: +5.5%, requests_per_second: -7.2%, rss_bytes: +0.0% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -0.1%, duration_seconds: -1.4%, p50_ms: -2.0%, p95_ms: +8.0%, p99_ms: -7.2%, requests_per_second: +2.5%, rss_bytes: +0.0% |
| thread | possible-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +0.0%, duration_seconds: -1.0%, p50_ms: -2.4%, p95_ms: +23.5%, p99_ms: +4.4%, requests_per_second: +1.0%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: -3.7%, cpu_percent: -2.5%, duration_seconds: -0.1%, p50_ms: +19.4%, p95_ms: +0.5%, p99_ms: +16.4%, requests_per_second: -3.7%, rss_bytes: +0.0% |
| thread | stable | completed: -1.5%, cpu_percent: -1.4%, duration_seconds: +0.2%, p50_ms: -8.5%, p95_ms: +0.4%, p99_ms: -1.5%, requests_per_second: -1.7%, rss_bytes: -0.0% |
| search | stable | completed: -8.4%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +13.1%, p95_ms: -7.4%, p99_ms: +1.2%, requests_per_second: -8.3%, rss_bytes: -0.1% |
| search | possible-regression | completed: -4.8%, cpu_percent: -1.1%, duration_seconds: -0.1%, p50_ms: -15.5%, p95_ms: +21.7%, p99_ms: +20.9%, requests_per_second: -4.8%, rss_bytes: +0.0% |
| cache_hit | stable | completed: +15.7%, cpu_percent: +41.7%, duration_seconds: -0.1%, p50_ms: -9.8%, p95_ms: +1.0%, p99_ms: -2.7%, requests_per_second: +20.9%, rss_bytes: +0.1% |
| cache_hit | possible-regression | completed: -1.3%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +5.4%, p95_ms: +28.8%, p99_ms: +6.3%, requests_per_second: -1.2%, rss_bytes: +0.1% |
| cache_miss | confirmed-regression | completed: -24.3%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +32.2%, p95_ms: +35.9%, p99_ms: +51.1%, requests_per_second: -24.3%, rss_bytes: +0.0% |
| cache_miss | confirmed-regression | completed: -25.4%, cpu_percent: +0.7%, duration_seconds: +0.0%, p50_ms: +32.0%, p95_ms: +41.1%, p99_ms: +57.2%, requests_per_second: -25.5%, rss_bytes: +0.1% |
| cache_miss | confirmed-regression | completed: -28.0%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +35.4%, p95_ms: +49.3%, p99_ms: +41.1%, requests_per_second: -28.1%, rss_bytes: +0.1% |
| health_live | stable | completed: -2.9%, cpu_percent: -0.5%, duration_seconds: -4.7%, p50_ms: +0.2%, p95_ms: +3.0%, p99_ms: +0.3%, requests_per_second: -1.2%, rss_bytes: -0.1% |
| health_live | stable | completed: -1.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: -0.7%, p99_ms: -13.3%, requests_per_second: +0.5%, rss_bytes: -0.1% |
| health_live | stable | completed: -0.7%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +0.9%, p95_ms: +0.5%, p99_ms: +7.2%, requests_per_second: -0.8%, rss_bytes: -0.1% |
| health_live | stable | completed: -1.2%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +2.7%, p95_ms: +0.7%, p99_ms: +7.0%, requests_per_second: -1.2%, rss_bytes: -0.1% |
| home | confirmed-regression | completed: -16.4%, cpu_percent: +3.4%, duration_seconds: +0.0%, p50_ms: +19.9%, p95_ms: +20.2%, p99_ms: +31.1%, requests_per_second: -16.3%, rss_bytes: -0.1% |
| home | confirmed-regression | completed: -13.7%, cpu_percent: +2.0%, duration_seconds: -0.1%, p50_ms: +16.4%, p95_ms: +8.8%, p99_ms: +17.2%, requests_per_second: -13.0%, rss_bytes: -0.0% |
| home | confirmed-regression | completed: -17.7%, cpu_percent: +2.1%, duration_seconds: +0.0%, p50_ms: +14.4%, p95_ms: +26.0%, p99_ms: +19.7%, requests_per_second: -17.7%, rss_bytes: +0.1% |
| categories | stable | completed: -1.5%, cpu_percent: -1.0%, duration_seconds: -0.0%, p50_ms: +1.5%, p95_ms: +1.0%, p99_ms: +10.0%, requests_per_second: -1.0%, rss_bytes: +0.1% |
| categories | stable | completed: +2.3%, cpu_percent: -0.1%, duration_seconds: +4.9%, p50_ms: +0.8%, p95_ms: +3.9%, p99_ms: +15.0%, requests_per_second: -2.0%, rss_bytes: +0.1% |
| categories | stable | completed: -2.1%, cpu_percent: -1.1%, duration_seconds: +0.1%, p50_ms: +0.2%, p95_ms: +16.4%, p99_ms: +17.0%, requests_per_second: -2.0%, rss_bytes: +0.1% |
| category | stable | completed: -1.0%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: -1.2%, p99_ms: +1.2%, requests_per_second: +0.8%, rss_bytes: +0.1% |
| category | stable | completed: +0.1%, cpu_percent: -0.3%, duration_seconds: +4.9%, p50_ms: +1.4%, p95_ms: +2.6%, p99_ms: -9.3%, requests_per_second: -1.6%, rss_bytes: +0.1% |
| category | stable | completed: -2.1%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: +1.3%, p95_ms: +4.6%, p99_ms: +11.4%, requests_per_second: -2.2%, rss_bytes: +0.1% |
| thread | possible-regression | completed: -1.3%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +0.4%, p95_ms: +2.1%, p99_ms: +24.6%, requests_per_second: -1.2%, rss_bytes: +0.2% |
| thread | confirmed-regression | completed: -8.9%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: +1.6%, p95_ms: +17.0%, p99_ms: +25.9%, requests_per_second: -4.8%, rss_bytes: +0.1% |
| thread | stable | completed: -4.4%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +7.0%, p95_ms: +13.4%, p99_ms: +10.1%, requests_per_second: -4.4%, rss_bytes: -0.0% |
| thread | stable | completed: -2.9%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: +2.1%, p95_ms: +1.8%, p99_ms: +4.3%, requests_per_second: -3.0%, rss_bytes: -0.1% |
| search | possible-regression | completed: -11.8%, cpu_percent: +3.4%, duration_seconds: -0.1%, p50_ms: +11.8%, p95_ms: +17.1%, p99_ms: +14.7%, requests_per_second: -9.8%, rss_bytes: -0.1% |
| search | confirmed-regression | completed: -14.3%, cpu_percent: +2.5%, duration_seconds: -0.0%, p50_ms: +6.1%, p95_ms: +32.1%, p99_ms: +6.7%, requests_per_second: -10.9%, rss_bytes: -0.1% |
| search | possible-regression | completed: +0.0%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +5.2%, p95_ms: +23.2%, p99_ms: +17.1%, requests_per_second: -0.1%, rss_bytes: -0.1% |
| search | stable | completed: +0.5%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: -2.8%, p95_ms: -9.8%, p99_ms: -6.4%, requests_per_second: +0.5%, rss_bytes: -0.1% |
| cache_hit | possible-regression | completed: -2.0%, cpu_percent: +1.0%, duration_seconds: +0.1%, p50_ms: -0.7%, p95_ms: +2.9%, p99_ms: +13.8%, requests_per_second: -1.9%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -0.7%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +2.0%, p95_ms: -7.0%, p99_ms: +20.5%, requests_per_second: -1.7%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -0.5%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +0.7%, p95_ms: +4.8%, p99_ms: -9.1%, requests_per_second: -0.5%, rss_bytes: -0.1% |
| cache_hit | stable | completed: -1.0%, cpu_percent: +0.9%, duration_seconds: -0.0%, p50_ms: +0.7%, p95_ms: +7.8%, p99_ms: +4.6%, requests_per_second: -1.1%, rss_bytes: -0.1% |
| thread | improvement | completed: +19.8%, cpu_percent: +16.6%, duration_seconds: +0.1%, p50_ms: -9.3%, p95_ms: -16.9%, p99_ms: -4.2%, requests_per_second: +17.8%, rss_bytes: -0.0% |
| thread | improvement | completed: +1.4%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -6.4%, p95_ms: -12.6%, p99_ms: -10.2%, requests_per_second: +1.4%, rss_bytes: -0.0% |
| search | stable | completed: -0.6%, cpu_percent: -0.1%, duration_seconds: +0.5%, p50_ms: -24.4%, p95_ms: -11.8%, p99_ms: -13.6%, requests_per_second: +3.9%, rss_bytes: -0.1% |
| search | stable | completed: -9.4%, cpu_percent: -0.3%, duration_seconds: -0.2%, p50_ms: +4.4%, p95_ms: -23.9%, p99_ms: -20.8%, requests_per_second: -9.3%, rss_bytes: -0.2% |
| cache_hit | possible-regression | completed: -5.5%, cpu_percent: +5.2%, duration_seconds: +0.0%, p50_ms: +34.8%, p95_ms: +53.3%, p99_ms: +68.9%, requests_per_second: -5.5%, rss_bytes: -0.3% |
| cache_hit | improvement | completed: -1.0%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +8.6%, p95_ms: -20.2%, p99_ms: -28.7%, requests_per_second: -0.9%, rss_bytes: -0.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +1327.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +10.7% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +19.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +24.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +13.2% |
| sql-plan-readers | confirmed-regression | sql_execution_ms: +16.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +24.1% |
| sql-plan-readers | possible-regression | sql_execution_ms: +14.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +66.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +55.8% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +17.4% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +16.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.1% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +40.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +11.1% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +19.1% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1984.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -10.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +8.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -4.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.8% |
| sql-plan-functions | possible-regression | nested_statements: +0.0%, sql_execution_ms: +14.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -15.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +15.7% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +4.1%, messages_per_second: -3.9%, p50_ms: +4.1%, p95_ms: +3.9%, p99_ms: +2.1% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +3.8%, messages_per_second: -3.7%, p50_ms: +3.8%, p95_ms: -1.3%, p99_ms: +1.0% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -3.8%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: -0.1%, p95_ms: +2.1%, p99_ms: -0.8%, requests_per_second: +0.9%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.5%, cpu_percent: +0.7%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: +2.3%, p99_ms: +15.8%, requests_per_second: -0.5%, rss_bytes: +0.4% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.4%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +0.8%, p95_ms: +5.9%, p99_ms: +3.0%, requests_per_second: -1.3%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.0%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -1.8%, p95_ms: -0.3%, p99_ms: -4.1%, requests_per_second: +0.8%, rss_bytes: +0.1% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.5%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -2.1%, p95_ms: -3.1%, p99_ms: -3.0%, requests_per_second: +2.2%, rss_bytes: +0.1% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.9%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: -2.0%, p99_ms: -1.6%, requests_per_second: +0.8%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.0%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: -3.1%, p99_ms: +6.0%, requests_per_second: +0.9%, rss_bytes: +0.2% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.5%, cpu_percent: +0.6%, duration_seconds: -0.0%, p50_ms: -1.4%, p95_ms: -4.1%, p99_ms: +0.2%, requests_per_second: +1.5%, rss_bytes: +0.2% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +7.4%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -9.5%, p95_ms: -14.1%, p99_ms: +4.9%, requests_per_second: +12.8%, rss_bytes: +0.2% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +7.4%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -10.3%, p95_ms: -16.2%, p99_ms: -15.1%, requests_per_second: +7.4%, rss_bytes: +0.2% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.9%, cpu_percent: +0.5%, duration_seconds: -4.7%, p50_ms: -1.0%, p95_ms: -1.9%, p99_ms: +5.1%, requests_per_second: +1.8%, rss_bytes: +0.2% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.0%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -0.5%, p95_ms: -11.7%, p99_ms: +0.1%, requests_per_second: +1.5%, rss_bytes: +0.2% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -0.3%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -1.6%, p95_ms: +16.3%, p99_ms: +32.2%, requests_per_second: -0.2%, rss_bytes: +0.2% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.1%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -3.1%, p95_ms: -3.1%, p99_ms: -13.9%, requests_per_second: +3.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.2%, cpu_percent: -0.1%, duration_seconds: +4.8%, p50_ms: -1.0%, p95_ms: -1.2%, p99_ms: +8.5%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.6%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -2.5%, p95_ms: -1.7%, p99_ms: +3.3%, requests_per_second: -0.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +1.4%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -0.5%, p95_ms: -0.7%, p99_ms: -14.9%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -4.1%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: +1.5%, p95_ms: +17.9%, p99_ms: +34.6%, requests_per_second: -4.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -2.0%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: +3.4%, p95_ms: +13.1%, p99_ms: +15.5%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.6%, cpu_percent: -1.0%, duration_seconds: +0.0%, p50_ms: +0.9%, p95_ms: +0.8%, p99_ms: +5.9%, requests_per_second: -1.6%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -6.9%, cpu_percent: +2.2%, duration_seconds: -0.0%, p50_ms: +8.4%, p95_ms: +13.5%, p99_ms: +6.7%, requests_per_second: -7.0%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -6.1%, cpu_percent: +2.2%, duration_seconds: +4.8%, p50_ms: +1.1%, p95_ms: +23.4%, p99_ms: +1.6%, requests_per_second: -6.9%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +16.9%, cpu_percent: -1.1%, duration_seconds: +0.0%, p50_ms: -8.7%, p95_ms: +9.0%, p99_ms: +8.8%, requests_per_second: +17.1%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: +1.1%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: -0.2%, p99_ms: +5.4%, requests_per_second: -0.0%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.6%, cpu_percent: +1.5%, duration_seconds: +0.1%, p50_ms: -1.8%, p95_ms: -1.2%, p99_ms: +2.5%, requests_per_second: +1.5%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.8%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -0.7%, p95_ms: +7.7%, p99_ms: +21.4%, requests_per_second: +0.8%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.1%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -2.1%, p95_ms: +8.5%, p99_ms: -0.5%, requests_per_second: +0.1%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +6.5%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -5.8%, p95_ms: -13.5%, p99_ms: +1.4%, requests_per_second: +6.5%, rss_bytes: +0.2% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +7.2%, cpu_percent: +3.0%, duration_seconds: +0.1%, p50_ms: +7.4%, p95_ms: -12.2%, p99_ms: -8.8%, requests_per_second: +5.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +2.5%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -3.7%, p95_ms: -16.9%, p99_ms: -15.2%, requests_per_second: +2.6%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +5.1%, cpu_percent: -1.1%, duration_seconds: +0.5%, p50_ms: -45.2%, p95_ms: -6.9%, p99_ms: -15.7%, requests_per_second: +5.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.5%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +4.5%, p95_ms: -9.4%, p99_ms: -13.3%, requests_per_second: +1.6%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -19.5%, cpu_percent: -29.5%, duration_seconds: +0.1%, p50_ms: +80.4%, p95_ms: +31.7%, p99_ms: +65.5%, requests_per_second: -19.4%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +1.8%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: +7.1%, p95_ms: -18.2%, p99_ms: -22.3%, requests_per_second: +1.8%, rss_bytes: +0.2% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +42.3%, cpu_percent: +88.8%, duration_seconds: +0.1%, p50_ms: -28.8%, p95_ms: +18.8%, p99_ms: +6.2%, requests_per_second: +42.1%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +45.2%, cpu_percent: +89.9%, duration_seconds: +0.3%, p50_ms: -39.2%, p95_ms: +16.5%, p99_ms: -10.0%, requests_per_second: +44.9%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +37.6%, cpu_percent: +76.8%, duration_seconds: +0.2%, p50_ms: -36.1%, p95_ms: +5.3%, p99_ms: +28.0%, requests_per_second: +37.7%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +37.5%, cpu_percent: +81.6%, duration_seconds: +0.4%, p50_ms: -38.6%, p95_ms: -13.5%, p99_ms: -7.6%, requests_per_second: +37.0%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +20.0%, cpu_percent: +50.4%, duration_seconds: -0.1%, p50_ms: -26.2%, p95_ms: +43.4%, p99_ms: +29.1%, requests_per_second: +19.7%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +56.8%, cpu_percent: +94.0%, duration_seconds: +0.0%, p50_ms: -44.3%, p95_ms: -11.6%, p99_ms: -16.3%, requests_per_second: +56.8%, rss_bytes: +64.4% |
| thread | workers=4 | 2 | 50 | improvement | completed: +55.7%, cpu_percent: +94.1%, duration_seconds: +0.1%, p50_ms: -26.1%, p95_ms: -7.8%, p99_ms: -16.2%, requests_per_second: +53.1%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +51.2%, cpu_percent: +92.8%, duration_seconds: +0.2%, p50_ms: -41.9%, p95_ms: -3.9%, p99_ms: -28.0%, requests_per_second: +51.1%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +23.7%, cpu_percent: +76.9%, duration_seconds: +0.7%, p50_ms: -61.6%, p95_ms: -10.0%, p99_ms: -0.8%, requests_per_second: +23.5%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +39.5%, cpu_percent: +80.1%, duration_seconds: +0.2%, p50_ms: -35.4%, p95_ms: -21.5%, p99_ms: -24.0%, requests_per_second: +39.2%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -3.4%, cpu_percent: +6.1%, duration_seconds: +0.0%, p50_ms: +36.0%, p95_ms: +74.0%, p99_ms: +114.9%, requests_per_second: -3.5%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.9%, cpu_percent: +92.4%, duration_seconds: +0.0%, p50_ms: -36.7%, p95_ms: -16.4%, p99_ms: -35.8%, requests_per_second: +50.0%, rss_bytes: +64.3% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38691750350)
