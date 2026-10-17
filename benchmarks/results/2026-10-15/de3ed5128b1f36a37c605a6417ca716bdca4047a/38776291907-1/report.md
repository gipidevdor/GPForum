# GPForum continuous performance evidence

Commit: `de3ed5128b1f36a37c605a6417ca716bdca4047a` · mode: **main** · status: **ok**
Run: 38776291907 / attempt 1 · 2026-10-15T17:19:24.067043+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. d06ea94d0dc69172f3700476673788e4ecd903a7

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 236.969 | 4.182 | 4.345 | 4.653 | 99.488 / 375.988 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 473.581 | 20.976 | 25.616 | 32.956 | 199.714 / 376.074 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 456.546 | 105.913 | 122.895 | 188.465 | 201.215 / 377.863 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1323.194 | 0.729 | 0.814 | 1.066 | 99.421 / 375.996 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2675.043 | 3.712 | 3.907 | 4.645 | 199.297 / 375.996 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2735.190 | 18.285 | 20.226 | 28.032 | 200.202 / 376.645 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2693.017 | 35.810 | 39.371 | 52.497 | 198.745 / 377.871 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 107.410 | 9.196 | 10.211 | 11.203 | 86.973 / 378.480 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 191.912 | 49.491 | 59.648 | 96.109 | 173.338 / 379.008 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 186.668 | 249.878 | 448.075 | 498.367 | 175.198 / 381.414 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 961.709 | 1.036 | 1.100 | 1.547 | 99.396 / 381.414 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1961.311 | 5.138 | 6.380 | 8.153 | 199.465 / 381.414 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1988.247 | 24.648 | 26.375 | 32.905 | 199.827 / 381.414 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 928.147 | 1.071 | 1.121 | 1.831 | 99.443 / 381.535 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1867.706 | 5.301 | 5.573 | 7.457 | 198.662 / 381.535 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1968.299 | 25.709 | 27.050 | 31.154 | 201.317 / 381.535 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 958.674 | 1.024 | 1.112 | 1.155 | 99.386 / 381.660 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1880.090 | 5.263 | 5.860 | 7.997 | 198.899 / 381.660 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1879.204 | 26.593 | 29.244 | 33.871 | 201.297 / 381.660 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1920.456 | 51.333 | 55.693 | 85.641 | 200.801 / 384.336 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 77.924 | 12.626 | 14.057 | 15.733 | 63.674 / 384.922 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 139.191 | 70.818 | 80.206 | 120.985 | 128.271 / 384.922 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 136.357 | 337.296 | 597.877 | 700.909 | 128.002 / 384.922 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.728 | 715.234 | 1315.036 | 1392.361 | 127.496 / 384.922 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 989.044 | 0.994 | 1.078 | 1.129 | 99.516 / 384.922 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1941.996 | 5.082 | 6.438 | 7.214 | 199.400 / 384.922 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1993.662 | 24.960 | 26.686 | 34.598 | 200.287 / 384.922 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1971.182 | 50.063 | 52.254 | 78.444 | 200.219 / 384.922 | confirmed-regression |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1545.000 | 5.683 | 9.306 | 10.376 | 23.480 / 384.922 | confirmed-regression |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1043.873 | 8.528 | 13.564 | 15.389 | 35.320 / 385.215 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2580.255 | 14.007 | 33.847 | 52.388 | 385.400 / 626.137 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2586.811 | 33.389 | 65.402 | 79.218 | 385.269 / 630.160 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 153.571 | 218.622 | 732.133 | 1024.574 | 238.003 / 631.859 | possible-regression |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 159.953 | 321.546 | 1492.561 | 1728.631 | 244.629 / 633.168 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1906.702 | 30.039 | 44.338 | 61.923 | 229.961 / 633.289 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2691.148 | 35.783 | 55.711 | 62.433 | 386.848 / 633.840 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 233.960 | 4.221 | 4.500 | 4.846 | 99.912 / 376.930 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 448.713 | 21.616 | 30.110 | 38.457 | 199.754 / 377.004 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 443.885 | 108.137 | 131.357 | 209.170 | 200.715 / 378.879 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1371.155 | 0.717 | 0.781 | 0.819 | 100.419 / 377.059 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2711.814 | 3.622 | 3.866 | 5.972 | 199.735 / 377.059 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2778.348 | 17.803 | 19.001 | 26.040 | 199.681 / 377.785 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2710.668 | 36.749 | 39.923 | 57.021 | 199.285 / 379.180 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 101.454 | 9.756 | 11.091 | 11.678 | 87.482 / 379.648 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 192.824 | 52.884 | 71.784 | 101.109 | 173.656 / 380.258 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 173.709 | 266.071 | 468.157 | 553.463 | 173.678 / 382.676 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 992.927 | 0.989 | 1.054 | 1.114 | 99.464 / 382.676 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1947.380 | 5.243 | 6.935 | 10.801 | 198.905 / 382.676 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1983.298 | 27.849 | 33.822 | 39.671 | 201.237 / 382.676 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 986.844 | 1.003 | 1.063 | 1.112 | 99.469 / 382.793 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1899.426 | 5.445 | 7.538 | 10.316 | 199.093 / 382.809 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1926.056 | 25.411 | 27.011 | 45.173 | 200.230 / 382.809 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 961.034 | 1.034 | 1.108 | 1.943 | 99.034 / 382.895 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1885.530 | 5.227 | 6.506 | 9.053 | 199.320 / 382.957 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1881.746 | 26.111 | 28.384 | 46.110 | 199.820 / 382.957 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1862.203 | 52.250 | 61.401 | 90.346 | 199.213 / 385.672 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 64.878 | 15.206 | 16.977 | 17.293 | 67.123 / 386.168 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 121.867 | 79.188 | 107.079 | 147.528 | 133.013 / 386.441 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 110.693 | 406.857 | 723.012 | 814.452 | 131.887 / 386.441 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.837 | 800.043 | 1489.760 | 1595.184 | 131.872 / 386.469 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1016.825 | 0.974 | 1.026 | 1.096 | 99.874 / 386.469 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1955.468 | 5.038 | 6.789 | 8.711 | 199.274 / 386.469 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1961.475 | 25.006 | 26.944 | 44.871 | 200.284 / 386.469 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1889.296 | 51.059 | 54.971 | 84.880 | 200.233 / 386.469 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2624.775 | 19.548 | 34.267 | 43.570 | 384.998 / 627.875 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2602.844 | 37.111 | 48.529 | 61.939 | 387.125 / 631.965 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 159.698 | 223.091 | 698.545 | 849.905 | 241.056 / 633.090 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 154.225 | 435.724 | 1286.622 | 1398.505 | 241.665 / 634.383 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2245.493 | 23.064 | 36.863 | 41.915 | 297.620 / 634.480 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2635.527 | 29.773 | 66.515 | 80.390 | 387.065 / 634.551 | confirmed-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.550 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.457 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.498 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.606 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 4.157 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.338 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.121 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.097 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.009 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.517 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.595 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.316 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.380 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.097 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.062 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.406 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.543 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.487 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.610 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.493 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.546 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.338 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.363 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.074 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.591 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.205 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.192 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.196 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.057 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.074 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.104 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.055 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.080 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 712.118 | 138.584 | 151.857 | 163.725 | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1203.494 | 164.192 | 189.501 | 190.346 | — / — | improvement |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | confirmed-regression | completed: -23.7%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: +31.2%, p95_ms: +29.3%, p99_ms: +7.9%, requests_per_second: -23.6%, rss_bytes: +1.5% |
| cache_miss | confirmed-regression | completed: -22.7%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +13.6%, p95_ms: +31.4%, p99_ms: +49.3%, requests_per_second: -22.7%, rss_bytes: +1.5% |
| cache_miss | confirmed-regression | completed: -24.7%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +33.7%, p95_ms: +38.2%, p99_ms: +32.5%, requests_per_second: -24.7%, rss_bytes: +1.5% |
| health_live | confirmed-regression | completed: -21.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +26.3%, p95_ms: +26.8%, p99_ms: +18.3%, requests_per_second: -21.7%, rss_bytes: +1.6% |
| health_live | confirmed-regression | completed: -19.7%, cpu_percent: -0.1%, duration_seconds: +5.0%, p50_ms: +31.1%, p95_ms: +27.2%, p99_ms: +16.6%, requests_per_second: -22.0%, rss_bytes: +1.6% |
| health_live | confirmed-regression | completed: -23.2%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +31.7%, p95_ms: +38.5%, p99_ms: +45.7%, requests_per_second: -23.3%, rss_bytes: +1.6% |
| health_live | confirmed-regression | completed: -25.1%, cpu_percent: -0.9%, duration_seconds: +0.0%, p50_ms: +30.8%, p95_ms: +33.3%, p99_ms: +43.9%, requests_per_second: -25.0%, rss_bytes: +1.6% |
| home | confirmed-regression | completed: -27.1%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: +37.2%, p95_ms: +30.2%, p99_ms: +4.7%, requests_per_second: -26.2%, rss_bytes: +1.6% |
| home | confirmed-regression | completed: -30.2%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +41.4%, p95_ms: +24.1%, p99_ms: +74.4%, requests_per_second: -30.1%, rss_bytes: +1.6% |
| home | confirmed-regression | completed: -30.7%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: +37.1%, p95_ms: +72.1%, p99_ms: +45.4%, requests_per_second: -30.8%, rss_bytes: +1.6% |
| categories | confirmed-regression | completed: -30.2%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +37.4%, p95_ms: +35.3%, p99_ms: +75.6%, requests_per_second: -26.7%, rss_bytes: +1.6% |
| categories | confirmed-regression | completed: -24.0%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +33.8%, p95_ms: +48.9%, p99_ms: +46.4%, requests_per_second: -22.7%, rss_bytes: +1.6% |
| categories | confirmed-regression | completed: -23.7%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +27.2%, p95_ms: +29.0%, p99_ms: +48.8%, requests_per_second: -23.7%, rss_bytes: +1.6% |
| category | confirmed-regression | completed: -21.9%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +34.2%, p95_ms: +27.1%, p99_ms: +54.4%, requests_per_second: -24.7%, rss_bytes: +1.6% |
| category | confirmed-regression | completed: -24.8%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: +20.3%, p95_ms: +14.6%, p99_ms: +30.8%, requests_per_second: -24.8%, rss_bytes: +1.6% |
| category | confirmed-regression | completed: -22.7%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +31.2%, p95_ms: +27.2%, p99_ms: +21.7%, requests_per_second: -22.7%, rss_bytes: +1.6% |
| thread | confirmed-regression | completed: -22.9%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: +28.0%, p95_ms: +28.4%, p99_ms: +16.7%, requests_per_second: -21.9%, rss_bytes: +1.6% |
| thread | confirmed-regression | completed: -26.1%, cpu_percent: -0.3%, duration_seconds: -4.7%, p50_ms: +31.3%, p95_ms: +14.1%, p99_ms: +20.3%, requests_per_second: -22.5%, rss_bytes: +1.6% |
| thread | confirmed-regression | completed: -27.1%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: +36.7%, p95_ms: +43.1%, p99_ms: +24.3%, requests_per_second: -27.1%, rss_bytes: +1.6% |
| thread | confirmed-regression | completed: -24.0%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +33.1%, p95_ms: +29.9%, p99_ms: +48.1%, requests_per_second: -23.9%, rss_bytes: +1.5% |
| search | confirmed-regression | completed: -3.7%, cpu_percent: +27.9%, duration_seconds: -0.1%, p50_ms: +25.0%, p95_ms: -78.6%, p99_ms: -89.7%, requests_per_second: -3.6%, rss_bytes: +1.5% |
| search | improvement | completed: +22.9%, cpu_percent: +35.0%, duration_seconds: -0.0%, p50_ms: +4.3%, p95_ms: -60.2%, p99_ms: -44.6%, requests_per_second: +22.7%, rss_bytes: +1.5% |
| search | stable | completed: +9.2%, cpu_percent: +12.0%, duration_seconds: +0.0%, p50_ms: -3.4%, p95_ms: +5.0%, p99_ms: +11.3%, requests_per_second: +9.3%, rss_bytes: +1.5% |
| search | improvement | completed: +0.0%, cpu_percent: +35.0%, duration_seconds: +0.0%, p50_ms: -28.2%, p95_ms: -26.2%, p99_ms: -23.4%, requests_per_second: +0.0%, rss_bytes: +1.5% |
| cache_hit | confirmed-regression | completed: -21.6%, cpu_percent: -0.4%, duration_seconds: -4.7%, p50_ms: +24.7%, p95_ms: +30.5%, p99_ms: +18.6%, requests_per_second: -21.4%, rss_bytes: +1.5% |
| cache_hit | confirmed-regression | completed: -22.0%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +29.8%, p95_ms: +36.6%, p99_ms: +28.1%, requests_per_second: -22.4%, rss_bytes: +1.5% |
| cache_hit | confirmed-regression | completed: -21.5%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +29.0%, p95_ms: +14.0%, p99_ms: +20.7%, requests_per_second: -21.5%, rss_bytes: +1.5% |
| cache_hit | confirmed-regression | completed: -20.2%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +28.6%, p95_ms: +22.7%, p99_ms: +35.3%, requests_per_second: -20.1%, rss_bytes: +1.5% |
| health_live | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -21.0%, duration_seconds: +30.0%, p50_ms: +34.6%, p95_ms: +19.3%, p99_ms: +15.1%, requests_per_second: -23.0%, rss_bytes: +1.5% |
| thread | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -5.1%, duration_seconds: +33.3%, p50_ms: +28.6%, p95_ms: +25.7%, p99_ms: +32.1%, requests_per_second: -24.5%, rss_bytes: +1.5% |
| thread | confirmed-regression | completed: -21.0%, cpu_percent: +1.7%, duration_seconds: +4.8%, p50_ms: +20.7%, p95_ms: +17.7%, p99_ms: +57.9%, requests_per_second: -24.6%, rss_bytes: +1.5% |
| thread | confirmed-regression | completed: -23.3%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: +47.4%, p95_ms: +24.8%, p99_ms: +16.3%, requests_per_second: -23.3%, rss_bytes: +1.5% |
| search | possible-regression | completed: +3.3%, cpu_percent: +42.0%, duration_seconds: +0.1%, p50_ms: -14.3%, p95_ms: +10.5%, p99_ms: +53.8%, requests_per_second: +3.0%, rss_bytes: +1.5% |
| search | possible-regression | completed: +38.8%, cpu_percent: +74.9%, duration_seconds: +0.1%, p50_ms: -35.9%, p95_ms: -2.9%, p99_ms: +12.3%, requests_per_second: +38.3%, rss_bytes: +1.4% |
| cache_hit | possible-regression | completed: -25.0%, cpu_percent: +18.1%, duration_seconds: +0.2%, p50_ms: +60.1%, p95_ms: +68.3%, p99_ms: +76.7%, requests_per_second: -25.3%, rss_bytes: +1.5% |
| cache_hit | confirmed-regression | completed: -23.3%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: +50.1%, p95_ms: -7.6%, p99_ms: -15.4%, requests_per_second: -23.4%, rss_bytes: +1.4% |
| cache_miss | confirmed-regression | completed: -25.4%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +34.5%, p95_ms: +30.5%, p99_ms: +9.7%, requests_per_second: -25.3%, rss_bytes: +1.5% |
| cache_miss | confirmed-regression | completed: -27.9%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +37.6%, p95_ms: +44.0%, p99_ms: +33.7%, requests_per_second: -27.9%, rss_bytes: +1.5% |
| cache_miss | confirmed-regression | completed: -28.2%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +34.6%, p95_ms: +50.4%, p99_ms: +41.1%, requests_per_second: -28.3%, rss_bytes: +1.5% |
| health_live | confirmed-regression | completed: -24.7%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +32.3%, p95_ms: +31.5%, p99_ms: +23.7%, requests_per_second: -24.7%, rss_bytes: +1.5% |
| health_live | confirmed-regression | completed: -26.8%, cpu_percent: +0.3%, duration_seconds: -4.7%, p50_ms: +30.4%, p95_ms: +28.9%, p99_ms: +21.1%, requests_per_second: -23.3%, rss_bytes: +1.5% |
| health_live | confirmed-regression | completed: -21.7%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +28.1%, p95_ms: +27.4%, p99_ms: +36.1%, requests_per_second: -21.6%, rss_bytes: +1.5% |
| health_live | confirmed-regression | completed: -23.9%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: +34.2%, p95_ms: +22.4%, p99_ms: +49.1%, requests_per_second: -23.9%, rss_bytes: +1.5% |
| home | confirmed-regression | completed: -33.7%, cpu_percent: +1.6%, duration_seconds: +0.0%, p50_ms: +51.1%, p95_ms: +57.3%, p99_ms: +45.2%, requests_per_second: -33.7%, rss_bytes: +1.5% |
| home | confirmed-regression | completed: -22.4%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +39.5%, p95_ms: +29.3%, p99_ms: +38.1%, requests_per_second: -22.8%, rss_bytes: +1.6% |
| home | confirmed-regression | completed: -33.2%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +50.7%, p95_ms: +70.0%, p99_ms: +64.6%, requests_per_second: -33.2%, rss_bytes: +1.6% |
| categories | confirmed-regression | completed: -22.7%, cpu_percent: -0.1%, duration_seconds: +5.0%, p50_ms: +33.6%, p95_ms: +31.4%, p99_ms: +34.9%, requests_per_second: -25.4%, rss_bytes: +1.6% |
| categories | confirmed-regression | completed: -23.6%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +35.6%, p95_ms: +45.3%, p99_ms: +74.9%, requests_per_second: -23.6%, rss_bytes: +1.6% |
| categories | confirmed-regression | completed: -25.3%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +49.9%, p95_ms: +67.8%, p99_ms: +25.4%, requests_per_second: -25.1%, rss_bytes: +1.6% |
| category | confirmed-regression | completed: -27.6%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +32.5%, p95_ms: +30.1%, p99_ms: +19.2%, requests_per_second: -24.0%, rss_bytes: +1.6% |
| category | confirmed-regression | completed: -27.5%, cpu_percent: +0.3%, duration_seconds: -4.7%, p50_ms: +38.1%, p95_ms: +58.5%, p99_ms: +50.3%, requests_per_second: -24.5%, rss_bytes: +1.6% |
| category | confirmed-regression | completed: -26.0%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +34.3%, p95_ms: +34.6%, p99_ms: +34.2%, requests_per_second: -25.3%, rss_bytes: +1.6% |
| thread | confirmed-regression | completed: -22.7%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +28.0%, p95_ms: +31.6%, p99_ms: +119.5%, requests_per_second: -22.8%, rss_bytes: +1.6% |
| thread | confirmed-regression | completed: -22.4%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +31.6%, p95_ms: +19.2%, p99_ms: +34.6%, requests_per_second: -23.6%, rss_bytes: +1.6% |
| thread | confirmed-regression | completed: -25.2%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +33.8%, p95_ms: +38.0%, p99_ms: +34.1%, requests_per_second: -25.2%, rss_bytes: +1.6% |
| thread | confirmed-regression | completed: -24.6%, cpu_percent: -1.1%, duration_seconds: +0.1%, p50_ms: +32.2%, p95_ms: +47.1%, p99_ms: +32.6%, requests_per_second: -24.7%, rss_bytes: +1.5% |
| search | confirmed-regression | completed: -24.0%, cpu_percent: +13.4%, duration_seconds: +0.1%, p50_ms: +44.2%, p95_ms: -21.2%, p99_ms: -59.9%, requests_per_second: -24.1%, rss_bytes: +1.5% |
| search | improvement | completed: +3.6%, cpu_percent: +40.0%, duration_seconds: -0.0%, p50_ms: +16.6%, p95_ms: -17.6%, p99_ms: -30.7%, requests_per_second: -1.2%, rss_bytes: +1.6% |
| search | stable | completed: -14.9%, cpu_percent: +33.9%, duration_seconds: +0.1%, p50_ms: +7.3%, p95_ms: +20.0%, p99_ms: +8.8%, requests_per_second: -15.1%, rss_bytes: +1.6% |
| search | stable | completed: +38.9%, cpu_percent: +68.4%, duration_seconds: -0.0%, p50_ms: +21.1%, p95_ms: +19.9%, p99_ms: +20.5%, requests_per_second: +38.9%, rss_bytes: +1.6% |
| cache_hit | confirmed-regression | completed: -19.8%, cpu_percent: +0.4%, duration_seconds: +5.0%, p50_ms: +28.7%, p95_ms: +25.4%, p99_ms: +24.0%, requests_per_second: -22.0%, rss_bytes: +1.6% |
| cache_hit | confirmed-regression | completed: -24.4%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +32.3%, p95_ms: +50.0%, p99_ms: +32.4%, requests_per_second: -23.9%, rss_bytes: +1.6% |
| cache_hit | confirmed-regression | completed: -24.6%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: +32.6%, p95_ms: +31.5%, p99_ms: +41.0%, requests_per_second: -24.6%, rss_bytes: +1.6% |
| cache_hit | confirmed-regression | completed: -26.1%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +35.8%, p95_ms: +37.1%, p99_ms: +29.5%, requests_per_second: -26.2%, rss_bytes: +1.6% |
| thread | confirmed-regression | completed: -25.2%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: +31.8%, p95_ms: +33.4%, p99_ms: +32.3%, requests_per_second: -25.2%, rss_bytes: +1.5% |
| thread | confirmed-regression | completed: -23.8%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +46.8%, p95_ms: +3.4%, p99_ms: +5.5%, requests_per_second: -23.8%, rss_bytes: +1.5% |
| search | stable | completed: +36.0%, cpu_percent: +93.9%, duration_seconds: +0.2%, p50_ms: -17.8%, p95_ms: -33.8%, p99_ms: -30.9%, requests_per_second: +35.6%, rss_bytes: +1.4% |
| search | stable | completed: -16.2%, cpu_percent: +22.3%, duration_seconds: +0.1%, p50_ms: +26.9%, p95_ms: -5.1%, p99_ms: -15.2%, requests_per_second: -16.3%, rss_bytes: +1.2% |
| cache_hit | possible-regression | completed: -25.2%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +23.3%, p95_ms: +29.4%, p99_ms: +38.7%, requests_per_second: -28.7%, rss_bytes: +1.2% |
| cache_hit | confirmed-regression | completed: -26.5%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +5.7%, p95_ms: +83.0%, p99_ms: +57.5%, requests_per_second: -26.4%, rss_bytes: +1.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +29.1% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +34.4% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +23.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +31.5% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +19.5% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +28.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +29.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +30.1% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +31.1% |
| sql-plan-readers | confirmed-regression | sql_execution_ms: +16.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +33.3% |
| sql-plan-readers | confirmed-regression | sql_execution_ms: +28.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +25.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +31.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +31.1% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +38.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +27.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +11.5% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +21.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +29.3% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +35.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +45.6% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +33.4% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +33.8% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +38.5% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +20.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +43.2% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +25.6% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +30.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +29.7% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +34.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +45.5% |
| sql-plan-functions | confirmed-regression | nested_statements: +0.0%, sql_execution_ms: +33.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +31.5% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +26.7% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +21.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +8.8% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +42.5% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +25.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +66.7% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -49.6%, messages_per_second: +98.5%, p50_ms: -37.7%, p95_ms: -71.2%, p99_ms: -75.1% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -25.1%, messages_per_second: +33.4%, p50_ms: -17.3%, p95_ms: -49.4%, p99_ms: -49.3% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.3%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +0.9%, p95_ms: +3.6%, p99_ms: +4.1%, requests_per_second: -1.3%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -5.3%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +3.1%, p95_ms: +17.5%, p99_ms: +16.7%, requests_per_second: -5.3%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -2.7%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +2.1%, p95_ms: +6.9%, p99_ms: +11.0%, requests_per_second: -2.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +3.7%, cpu_percent: +1.0%, duration_seconds: -0.0%, p50_ms: -1.6%, p95_ms: -4.1%, p99_ms: -23.2%, requests_per_second: +3.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -1.5%, cpu_percent: +0.2%, duration_seconds: -4.7%, p50_ms: -2.4%, p95_ms: -1.0%, p99_ms: +28.6%, requests_per_second: +1.4%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.5%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -2.6%, p95_ms: -6.1%, p99_ms: -7.1%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.8%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +2.6%, p95_ms: +1.4%, p99_ms: +8.6%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -5.6%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: +6.1%, p95_ms: +8.6%, p99_ms: +4.2%, requests_per_second: -5.5%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.0%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +6.9%, p95_ms: +20.3%, p99_ms: +5.2%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -7.0%, cpu_percent: -0.9%, duration_seconds: +0.0%, p50_ms: +6.5%, p95_ms: +4.5%, p99_ms: +11.1%, requests_per_second: -6.9%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +8.4%, cpu_percent: +0.1%, duration_seconds: +4.9%, p50_ms: -4.5%, p95_ms: -4.2%, p99_ms: -28.0%, requests_per_second: +3.2%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.7%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +2.0%, p95_ms: +8.7%, p99_ms: +32.5%, requests_per_second: -0.7%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -0.3%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +13.0%, p95_ms: +28.2%, p99_ms: +20.6%, requests_per_second: -0.2%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +1.3%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: -6.3%, p95_ms: -5.2%, p99_ms: -39.3%, requests_per_second: +6.3%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +1.7%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +2.7%, p95_ms: +35.3%, p99_ms: +38.3%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -2.1%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -1.2%, p95_ms: -0.1%, p99_ms: +45.0%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | confirmed-regression | completed: +0.2%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: +1.0%, p95_ms: -0.4%, p99_ms: +68.2%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +1.8%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -0.7%, p95_ms: +11.0%, p99_ms: +13.2%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.1%, cpu_percent: -0.7%, duration_seconds: -0.1%, p50_ms: -1.8%, p95_ms: -2.9%, p99_ms: +36.1%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -3.0%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: +1.8%, p95_ms: +10.2%, p99_ms: +5.5%, requests_per_second: -3.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -16.7%, cpu_percent: +5.4%, duration_seconds: +0.1%, p50_ms: +20.4%, p95_ms: +20.8%, p99_ms: +9.9%, requests_per_second: -16.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -8.2%, cpu_percent: +3.7%, duration_seconds: -0.1%, p50_ms: +11.8%, p95_ms: +33.5%, p99_ms: +21.9%, requests_per_second: -12.4%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -18.7%, cpu_percent: +3.0%, duration_seconds: +0.1%, p50_ms: +20.6%, p95_ms: +20.9%, p99_ms: +16.2%, requests_per_second: -18.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: +0.0%, cpu_percent: +3.4%, duration_seconds: -0.1%, p50_ms: +11.9%, p95_ms: +13.3%, p99_ms: +14.6%, requests_per_second: +0.1%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +7.9%, cpu_percent: +0.4%, duration_seconds: +4.9%, p50_ms: -2.0%, p95_ms: -4.8%, p99_ms: -2.9%, requests_per_second: +2.8%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.3%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -0.9%, p95_ms: +5.5%, p99_ms: +20.8%, requests_per_second: +0.7%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -1.6%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +0.2%, p95_ms: +1.0%, p99_ms: +29.7%, requests_per_second: -1.6%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -4.1%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +2.0%, p95_ms: +5.2%, p99_ms: +8.2%, requests_per_second: -4.2%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -3.0%, cpu_percent: -0.1%, duration_seconds: -4.6%, p50_ms: +39.6%, p95_ms: +1.2%, p99_ms: -16.8%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +0.6%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: +11.1%, p95_ms: -25.8%, p99_ms: -21.8%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +3.9%, cpu_percent: +1.3%, duration_seconds: +0.1%, p50_ms: +2.0%, p95_ms: -4.6%, p99_ms: -17.0%, requests_per_second: +4.0%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -3.7%, cpu_percent: -1.2%, duration_seconds: -0.0%, p50_ms: +35.5%, p95_ms: -13.8%, p99_ms: -19.1%, requests_per_second: -3.6%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +23.1%, cpu_percent: +29.4%, duration_seconds: -0.1%, p50_ms: -23.2%, p95_ms: -16.9%, p99_ms: -32.3%, requests_per_second: +17.8%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | confirmed-regression | completed: -2.1%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -16.8%, p95_ms: +19.4%, p99_ms: +28.8%, requests_per_second: -2.1%, rss_bytes: +0.1% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +43.9%, cpu_percent: +91.5%, duration_seconds: +4.8%, p50_ms: -47.3%, p95_ms: +15.7%, p99_ms: +54.7%, requests_per_second: +37.3%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +34.8%, cpu_percent: +91.9%, duration_seconds: +0.0%, p50_ms: -35.0%, p95_ms: +17.4%, p99_ms: -7.5%, requests_per_second: +34.7%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +13.2%, cpu_percent: +85.9%, duration_seconds: +0.2%, p50_ms: -35.2%, p95_ms: +22.5%, p99_ms: +46.2%, requests_per_second: +12.6%, rss_bytes: +64.2% |
| search | workers=4 | 2 | 100 | possible-regression | completed: +61.0%, cpu_percent: +91.9%, duration_seconds: +0.2%, p50_ms: -55.0%, p95_ms: +13.5%, p99_ms: +24.2%, requests_per_second: +60.4%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -4.1%, cpu_percent: +14.8%, duration_seconds: +0.2%, p50_ms: +20.3%, p95_ms: +66.1%, p99_ms: +79.0%, requests_per_second: -4.4%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +36.7%, cpu_percent: +93.2%, duration_seconds: +0.1%, p50_ms: -28.5%, p95_ms: +6.6%, p99_ms: -20.4%, requests_per_second: +36.5%, rss_bytes: +64.7% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +39.5%, cpu_percent: +92.7%, duration_seconds: +0.1%, p50_ms: -25.1%, p95_ms: +20.7%, p99_ms: -5.5%, requests_per_second: +39.5%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +39.8%, cpu_percent: +94.3%, duration_seconds: +0.1%, p50_ms: -29.0%, p95_ms: -21.0%, p99_ms: -31.4%, requests_per_second: +39.8%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +44.6%, cpu_percent: +82.8%, duration_seconds: +0.2%, p50_ms: -45.2%, p95_ms: -3.4%, p99_ms: +4.4%, requests_per_second: +44.3%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 100 | improvement | completed: +55.0%, cpu_percent: +83.3%, duration_seconds: +0.3%, p50_ms: -45.5%, p95_ms: -13.6%, p99_ms: -12.3%, requests_per_second: +54.5%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: +20.0%, cpu_percent: +48.6%, duration_seconds: +0.1%, p50_ms: -7.8%, p95_ms: +36.8%, p99_ms: -6.6%, requests_per_second: +14.5%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +39.5%, cpu_percent: +93.3%, duration_seconds: +0.1%, p50_ms: -41.7%, p95_ms: +21.0%, p99_ms: -5.3%, requests_per_second: +39.5%, rss_bytes: +64.2% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38776291907)
