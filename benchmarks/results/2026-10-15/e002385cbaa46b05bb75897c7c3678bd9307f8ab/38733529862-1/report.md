# GPForum continuous performance evidence

Commit: `e002385cbaa46b05bb75897c7c3678bd9307f8ab` · mode: **main** · status: **ok**
Run: 38733529862 / attempt 1 · 2026-10-15T12:18:06.242710+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 27ca9e53bce99b7fa8691ff4fcdbf3e341fb291e

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 206.410 | 4.806 | 5.023 | 5.309 | 99.934 / 369.395 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 412.900 | 23.813 | 24.783 | 33.008 | 199.416 / 369.480 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 398.549 | 122.131 | 149.569 | 219.720 | 200.737 / 371.301 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1181.082 | 0.838 | 0.905 | 0.960 | 99.444 / 369.855 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2262.898 | 4.348 | 4.574 | 6.390 | 198.901 / 369.855 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2331.601 | 21.159 | 22.132 | 27.066 | 199.366 / 370.441 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2320.269 | 42.383 | 43.974 | 62.693 | 199.344 / 371.754 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 98.895 | 9.972 | 11.351 | 11.644 | 88.040 / 372.246 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 186.673 | 51.386 | 61.708 | 83.327 | 177.458 / 372.734 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 174.593 | 261.990 | 468.516 | 562.007 | 178.075 / 375.031 | possible-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 865.707 | 1.140 | 1.215 | 1.288 | 99.469 / 375.031 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1721.411 | 5.782 | 6.008 | 6.714 | 199.289 / 375.031 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1771.009 | 27.971 | 29.351 | 36.110 | 202.256 / 375.031 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 857.187 | 1.150 | 1.221 | 1.504 | 99.529 / 375.047 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1677.777 | 5.855 | 6.222 | 7.674 | 199.346 / 375.062 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1717.524 | 28.626 | 29.605 | 36.977 | 200.314 / 375.062 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 836.138 | 1.164 | 1.249 | 1.737 | 99.880 / 375.188 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1658.061 | 5.971 | 6.243 | 6.872 | 199.244 / 375.188 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1671.050 | 29.118 | 34.558 | 40.552 | 199.776 / 375.188 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1668.972 | 58.808 | 61.824 | 95.870 | 199.307 / 378.074 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 72.395 | 13.608 | 15.535 | 16.137 | 66.663 / 378.543 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 129.926 | 74.207 | 92.413 | 128.491 | 133.709 / 378.938 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.675 | 363.207 | 604.843 | 677.309 | 132.710 / 378.938 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.659 | 726.545 | 1352.014 | 1419.867 | 133.388 / 378.938 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 853.776 | 1.171 | 1.212 | 1.260 | 99.423 / 378.938 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1717.720 | 5.708 | 5.971 | 8.457 | 199.346 / 378.938 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1684.613 | 29.303 | 34.382 | 39.122 | 200.845 / 378.938 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1694.081 | 57.065 | 69.137 | 91.971 | 201.160 / 378.938 | stable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1390.740 | 6.663 | 10.148 | 13.047 | 28.301 / 378.938 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 964.283 | 9.196 | 13.906 | 15.957 | 40.160 / 379.219 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2483.402 | 17.139 | 39.406 | 49.179 | 385.186 / 615.641 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2469.618 | 39.888 | 51.040 | 62.344 | 386.977 / 619.379 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 144.801 | 197.567 | 811.608 | 1039.322 | 237.872 / 620.637 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 122.956 | 487.636 | 1390.561 | 1394.146 | 239.893 / 622.035 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1680.420 | 33.280 | 39.125 | 58.150 | 216.715 / 622.035 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2516.660 | 35.067 | 65.042 | 79.277 | 388.813 / 622.035 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 211.351 | 4.687 | 4.852 | 5.463 | 99.424 / 370.543 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 416.129 | 23.480 | 28.704 | 42.934 | 200.310 / 370.668 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 406.623 | 118.619 | 159.753 | 214.998 | 201.791 / 372.559 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1170.226 | 0.831 | 0.896 | 0.976 | 99.460 / 370.508 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2324.223 | 4.280 | 4.436 | 4.977 | 199.303 / 370.508 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2332.655 | 21.189 | 22.100 | 25.992 | 200.252 / 371.398 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2271.124 | 43.399 | 52.122 | 64.799 | 201.347 / 372.738 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 97.417 | 10.178 | 11.046 | 11.787 | 88.485 / 373.090 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 179.052 | 58.636 | 72.855 | 101.337 | 177.436 / 373.781 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 156.630 | 274.709 | 532.987 | 606.916 | 177.419 / 376.035 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 895.416 | 1.105 | 1.158 | 1.275 | 99.403 / 376.035 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1709.385 | 5.796 | 6.095 | 8.323 | 199.443 / 376.035 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1731.634 | 28.547 | 30.121 | 39.294 | 200.680 / 376.035 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 867.512 | 1.138 | 1.203 | 1.420 | 99.439 / 376.051 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1669.633 | 5.881 | 6.270 | 9.082 | 199.302 / 376.105 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1693.924 | 29.101 | 29.991 | 40.329 | 201.234 / 376.105 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 851.645 | 1.163 | 1.212 | 1.308 | 99.528 / 376.230 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1656.387 | 5.950 | 7.885 | 8.830 | 199.360 / 376.230 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1647.952 | 29.417 | 32.155 | 49.162 | 200.799 / 376.230 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1632.638 | 59.850 | 64.351 | 100.188 | 200.213 / 379.246 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 70.460 | 13.934 | 15.403 | 16.595 | 67.105 / 379.863 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 125.828 | 74.479 | 97.503 | 136.904 | 134.170 / 379.922 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 98.858 | 377.108 | 732.057 | 802.164 | 134.272 / 379.922 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.756 | 844.980 | 1663.746 | 1730.696 | 134.750 / 379.922 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 864.147 | 1.137 | 1.230 | 1.549 | 99.344 / 379.922 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1706.498 | 5.793 | 6.039 | 8.950 | 198.800 / 379.922 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1690.719 | 29.264 | 30.924 | 42.190 | 201.545 / 379.922 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1643.146 | 58.852 | 65.324 | 98.903 | 199.252 / 379.922 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2350.742 | 19.371 | 32.752 | 44.164 | 383.120 / 616.918 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2325.675 | 36.844 | 64.515 | 75.236 | 386.207 / 621.324 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 145.051 | 237.901 | 704.769 | 930.893 | 232.351 / 622.414 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 139.987 | 494.218 | 946.665 | 1109.789 | 243.153 / 623.219 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1695.139 | 33.471 | 43.997 | 65.425 | 220.492 / 623.219 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2499.340 | 37.967 | 59.064 | 69.973 | 388.700 / 623.531 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.507 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.458 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.497 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.570 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.099 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.618 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.109 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.123 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.029 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.583 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.531 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.278 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.339 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.089 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.054 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.054 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.367 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.445 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.512 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.663 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.417 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.700 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.328 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.318 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.937 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.435 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.203 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.170 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.193 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.072 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.125 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.100 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.085 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 678.607 | 146.344 | 151.070 | 161.414 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1149.439 | 172.179 | 189.371 | 191.497 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: -0.5%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +2.1%, p95_ms: -3.8%, p99_ms: -6.7%, requests_per_second: -0.4%, rss_bytes: +0.0% |
| cache_miss | stable | completed: +2.0%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.1%, p95_ms: -11.8%, p99_ms: -12.0%, requests_per_second: +2.0%, rss_bytes: +0.0% |
| cache_miss | stable | completed: +0.9%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +2.1%, p95_ms: -2.9%, p99_ms: +2.5%, requests_per_second: +0.7%, rss_bytes: +0.0% |
| health_live | stable | completed: +0.4%, cpu_percent: -0.0%, duration_seconds: -4.7%, p50_ms: -5.5%, p95_ms: -2.5%, p99_ms: -2.9%, requests_per_second: +4.8%, rss_bytes: +0.1% |
| health_live | possible-regression | completed: -0.3%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: +1.5%, p99_ms: +14.3%, requests_per_second: -0.4%, rss_bytes: +0.1% |
| health_live | stable | completed: -0.7%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -0.2%, p95_ms: +0.7%, p99_ms: +9.6%, requests_per_second: -0.7%, rss_bytes: +0.1% |
| health_live | stable | completed: +2.2%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: -1.6%, p95_ms: -5.3%, p99_ms: -2.0%, requests_per_second: +2.4%, rss_bytes: +0.1% |
| home | stable | completed: -1.0%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +0.9%, p95_ms: +8.8%, p99_ms: -10.3%, requests_per_second: -1.0%, rss_bytes: +0.2% |
| home | stable | completed: -1.3%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +1.6%, p95_ms: -4.0%, p99_ms: -1.1%, requests_per_second: -1.3%, rss_bytes: +0.1% |
| home | possible-regression | completed: +0.0%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +1.5%, p95_ms: +9.2%, p99_ms: +14.6%, requests_per_second: -0.1%, rss_bytes: +0.1% |
| categories | stable | completed: +0.3%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -0.2%, p95_ms: -0.5%, p99_ms: +1.1%, requests_per_second: +0.3%, rss_bytes: +0.1% |
| categories | improvement | completed: +2.0%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -0.4%, p95_ms: -16.8%, p99_ms: -20.6%, requests_per_second: +2.0%, rss_bytes: +0.1% |
| categories | stable | completed: +0.7%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: +0.9%, p95_ms: +0.2%, p99_ms: +0.9%, requests_per_second: +0.7%, rss_bytes: +0.1% |
| category | stable | completed: +3.1%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -1.9%, p95_ms: -0.7%, p99_ms: +16.5%, requests_per_second: +1.4%, rss_bytes: +0.1% |
| category | improvement | completed: +4.7%, cpu_percent: -0.3%, duration_seconds: +4.8%, p50_ms: -2.7%, p95_ms: -15.5%, p99_ms: -5.7%, requests_per_second: +0.8%, rss_bytes: +0.1% |
| category | stable | completed: +0.5%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -2.5%, p95_ms: -10.3%, p99_ms: -2.4%, requests_per_second: +0.2%, rss_bytes: +0.1% |
| thread | stable | completed: +0.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +0.1%, p99_ms: +28.0%, requests_per_second: -1.7%, rss_bytes: +0.1% |
| thread | stable | completed: +0.6%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.3%, p95_ms: -2.7%, p99_ms: -6.0%, requests_per_second: +0.7%, rss_bytes: +0.1% |
| thread | stable | completed: +4.7%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -4.8%, p95_ms: +4.3%, p99_ms: -14.8%, requests_per_second: +4.5%, rss_bytes: +0.1% |
| thread | stable | completed: +3.0%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: -1.1%, p95_ms: -8.5%, p99_ms: -1.5%, requests_per_second: +2.9%, rss_bytes: +0.1% |
| search | stable | completed: +4.3%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: -4.5%, p95_ms: -3.9%, p99_ms: -12.3%, requests_per_second: +4.2%, rss_bytes: +0.0% |
| search | stable | completed: +2.8%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -2.1%, p95_ms: +6.2%, p99_ms: -2.1%, requests_per_second: +2.8%, rss_bytes: +0.2% |
| search | improvement | completed: +0.4%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -4.5%, p95_ms: -13.0%, p99_ms: -12.6%, requests_per_second: +0.4%, rss_bytes: +0.2% |
| search | stable | completed: +0.0%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: -6.3%, p95_ms: -6.4%, p99_ms: -7.2%, requests_per_second: -0.1%, rss_bytes: +0.2% |
| cache_hit | stable | completed: +5.6%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +1.0%, p95_ms: -1.8%, p99_ms: -1.4%, requests_per_second: +1.4%, rss_bytes: +0.2% |
| cache_hit | stable | completed: +1.2%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: -5.0%, p95_ms: -9.3%, p99_ms: -4.4%, requests_per_second: +1.3%, rss_bytes: +0.2% |
| cache_hit | stable | completed: -4.3%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: +0.0%, p95_ms: +8.4%, p99_ms: +4.2%, requests_per_second: -0.6%, rss_bytes: +0.2% |
| cache_hit | stable | completed: -0.2%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: -0.9%, p95_ms: +13.5%, p99_ms: -1.3%, requests_per_second: -0.1%, rss_bytes: +0.2% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +3.8%, duration_seconds: -4.0%, p50_ms: -5.5%, p95_ms: -1.6%, p99_ms: +3.2%, requests_per_second: +4.6%, rss_bytes: +0.2% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +4.9%, duration_seconds: +2.0%, p50_ms: -2.0%, p95_ms: -1.6%, p99_ms: -7.2%, requests_per_second: -1.9%, rss_bytes: +0.1% |
| thread | possible-regression | completed: +3.1%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: -4.5%, p95_ms: +14.7%, p99_ms: +27.7%, requests_per_second: +3.0%, rss_bytes: +0.1% |
| thread | stable | completed: +5.9%, cpu_percent: +5.5%, duration_seconds: +0.1%, p50_ms: +4.8%, p95_ms: -33.1%, p99_ms: -44.4%, requests_per_second: +5.9%, rss_bytes: +0.0% |
| search | stable | completed: -2.7%, cpu_percent: +1.3%, duration_seconds: -0.1%, p50_ms: -24.2%, p95_ms: +15.8%, p99_ms: +21.5%, requests_per_second: -2.8%, rss_bytes: +0.0% |
| search | possible-regression | completed: -20.8%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -9.0%, p95_ms: -4.2%, p99_ms: -19.8%, requests_per_second: -20.7%, rss_bytes: -0.0% |
| cache_hit | improvement | completed: +7.5%, cpu_percent: +2.4%, duration_seconds: -0.0%, p50_ms: -5.8%, p95_ms: -42.2%, p99_ms: -39.3%, requests_per_second: +7.5%, rss_bytes: -0.0% |
| cache_hit | possible-regression | completed: -0.4%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -13.5%, p95_ms: +22.2%, p99_ms: +15.7%, requests_per_second: -0.9%, rss_bytes: -0.0% |
| cache_miss | stable | completed: +1.0%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -1.4%, p95_ms: -0.5%, p99_ms: +6.8%, requests_per_second: +1.0%, rss_bytes: +0.0% |
| cache_miss | confirmed-regression | completed: +3.9%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -12.7%, p95_ms: -1.1%, p99_ms: +25.2%, requests_per_second: +2.6%, rss_bytes: +0.0% |
| cache_miss | stable | completed: +4.4%, cpu_percent: +0.7%, duration_seconds: +0.0%, p50_ms: -2.5%, p95_ms: +4.3%, p99_ms: -2.5%, requests_per_second: +4.3%, rss_bytes: +0.0% |
| health_live | stable | completed: -3.9%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: -1.0%, p99_ms: -6.2%, requests_per_second: -0.8%, rss_bytes: +0.0% |
| health_live | stable | completed: +0.8%, cpu_percent: +0.1%, duration_seconds: -4.6%, p50_ms: -0.4%, p95_ms: -1.3%, p99_ms: -10.0%, requests_per_second: +0.8%, rss_bytes: +0.0% |
| health_live | stable | completed: +0.5%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -1.6%, p95_ms: -4.3%, p99_ms: +0.9%, requests_per_second: +0.2%, rss_bytes: +0.1% |
| health_live | stable | completed: +2.3%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: -0.3%, p95_ms: +7.4%, p99_ms: -7.5%, requests_per_second: +2.4%, rss_bytes: +0.1% |
| home | stable | completed: +7.7%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: -5.1%, p95_ms: -10.8%, p99_ms: -23.3%, requests_per_second: +7.9%, rss_bytes: -0.0% |
| home | stable | completed: +8.7%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +3.1%, p95_ms: +5.6%, p99_ms: +2.1%, requests_per_second: +3.6%, rss_bytes: +0.0% |
| home | stable | completed: +5.0%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -9.4%, p95_ms: +0.7%, p99_ms: +3.6%, requests_per_second: +5.0%, rss_bytes: +0.0% |
| categories | stable | completed: +2.0%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -2.0%, p95_ms: -2.3%, p99_ms: +0.4%, requests_per_second: +1.8%, rss_bytes: +0.0% |
| categories | stable | completed: +2.6%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -0.0%, p95_ms: -3.5%, p99_ms: +1.6%, requests_per_second: -0.2%, rss_bytes: +0.0% |
| categories | stable | completed: +1.8%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -1.3%, p95_ms: -5.2%, p99_ms: -3.5%, requests_per_second: +1.9%, rss_bytes: +0.0% |
| category | stable | completed: -2.0%, cpu_percent: -0.5%, duration_seconds: -4.6%, p50_ms: -0.3%, p95_ms: -1.8%, p99_ms: +11.5%, requests_per_second: +0.7%, rss_bytes: +0.0% |
| category | stable | completed: -2.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -0.5%, p95_ms: -0.6%, p99_ms: +3.4%, requests_per_second: -0.5%, rss_bytes: +0.0% |
| category | improvement | completed: +0.7%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -1.5%, p95_ms: -10.4%, p99_ms: -15.8%, requests_per_second: +0.8%, rss_bytes: +0.0% |
| thread | stable | completed: +0.9%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -0.2%, p95_ms: -2.3%, p99_ms: -3.7%, requests_per_second: +0.9%, rss_bytes: +0.0% |
| thread | possible-regression | completed: -1.5%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -0.4%, p95_ms: +24.3%, p99_ms: -16.3%, requests_per_second: +0.1%, rss_bytes: +0.0% |
| thread | stable | completed: +0.7%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -1.9%, p95_ms: +0.1%, p99_ms: +6.8%, requests_per_second: +0.5%, rss_bytes: +0.0% |
| thread | stable | completed: +2.5%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: -3.2%, p95_ms: +0.6%, p99_ms: -0.5%, requests_per_second: +2.5%, rss_bytes: +0.0% |
| search | stable | completed: +3.7%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: -3.9%, p95_ms: -8.0%, p99_ms: -8.5%, requests_per_second: +3.7%, rss_bytes: +0.1% |
| search | stable | completed: -5.6%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: +1.0%, p95_ms: -2.5%, p99_ms: -5.9%, requests_per_second: -2.1%, rss_bytes: +0.1% |
| search | possible-regression | completed: -16.5%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +11.2%, p95_ms: -1.8%, p99_ms: -9.6%, requests_per_second: -16.4%, rss_bytes: +0.1% |
| search | possible-regression | completed: +181.7%, cpu_percent: +87.5%, duration_seconds: -0.0%, p50_ms: +55.0%, p95_ms: +20.1%, p99_ms: +19.1%, requests_per_second: +181.7%, rss_bytes: -0.2% |
| cache_hit | stable | completed: +1.7%, cpu_percent: -11.2%, duration_seconds: +0.0%, p50_ms: +0.6%, p95_ms: -0.5%, p99_ms: +2.9%, requests_per_second: -1.1%, rss_bytes: -0.4% |
| cache_hit | improvement | completed: +2.3%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -1.2%, p95_ms: -13.0%, p99_ms: -3.2%, requests_per_second: +1.1%, rss_bytes: -0.4% |
| cache_hit | stable | completed: -0.1%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: +0.2%, p95_ms: +0.5%, p99_ms: -3.2%, requests_per_second: -0.1%, rss_bytes: -0.4% |
| cache_hit | stable | completed: -1.6%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +0.6%, p95_ms: +6.9%, p99_ms: +0.9%, requests_per_second: -1.6%, rss_bytes: -0.4% |
| thread | improvement | completed: -2.4%, cpu_percent: +1.2%, duration_seconds: +0.1%, p50_ms: -6.6%, p95_ms: -14.6%, p99_ms: -27.5%, requests_per_second: -2.6%, rss_bytes: +0.1% |
| thread | improvement | completed: -3.8%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +2.0%, p95_ms: -7.0%, p99_ms: -21.7%, requests_per_second: -3.9%, rss_bytes: +0.0% |
| search | stable | completed: -1.7%, cpu_percent: -1.5%, duration_seconds: -0.3%, p50_ms: +6.0%, p95_ms: -8.0%, p99_ms: -12.1%, requests_per_second: -2.0%, rss_bytes: -0.1% |
| search | improvement | completed: -3.8%, cpu_percent: +0.5%, duration_seconds: +0.2%, p50_ms: +12.9%, p95_ms: -38.9%, p99_ms: -40.6%, requests_per_second: -3.9%, rss_bytes: -0.0% |
| cache_hit | stable | completed: +5.4%, cpu_percent: -3.9%, duration_seconds: -0.1%, p50_ms: +0.6%, p95_ms: -8.8%, p99_ms: +4.8%, requests_per_second: +5.5%, rss_bytes: -0.0% |
| cache_hit | stable | completed: -0.3%, cpu_percent: +0.6%, duration_seconds: +0.2%, p50_ms: -2.7%, p95_ms: -1.4%, p99_ms: -21.8%, requests_per_second: -0.5%, rss_bytes: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +8.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +9.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.8% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.6% |
| sql-plan-readers | possible-regression | sql_execution_ms: +14.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +8.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +11.2% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +12.5% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +12.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -16.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +14.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +20.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -4.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +32.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +21.5% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -21.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.6% |
| sql-plan-functions | improvement | nested_statements: +0.0%, sql_execution_ms: -12.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +35.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -18.2% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +34.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -19.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.1% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -0.8%, messages_per_second: +0.8%, p50_ms: -0.6%, p95_ms: -5.5%, p99_ms: -0.9% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -0.6%, messages_per_second: +0.6%, p50_ms: +0.4%, p95_ms: +0.2%, p99_ms: +0.7% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.4%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -2.5%, p95_ms: -3.4%, p99_ms: +2.9%, requests_per_second: +2.4%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +2.2%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: -1.4%, p95_ms: +15.8%, p99_ms: +30.1%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.9%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: -2.9%, p95_ms: +6.8%, p99_ms: -2.1%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.9%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.8%, p95_ms: -1.0%, p99_ms: +1.7%, requests_per_second: -0.9%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +2.7%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -1.6%, p95_ms: -3.0%, p99_ms: -22.1%, requests_per_second: +2.7%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.4%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +0.1%, p95_ms: -0.1%, p99_ms: -4.0%, requests_per_second: +0.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -2.2%, cpu_percent: +1.0%, duration_seconds: +0.0%, p50_ms: +2.4%, p95_ms: +18.5%, p99_ms: +3.4%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.5%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +2.1%, p95_ms: -2.7%, p99_ms: +1.2%, requests_per_second: -1.5%, rss_bytes: +0.2% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +0.5%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +14.1%, p95_ms: +18.1%, p99_ms: +21.6%, requests_per_second: -4.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -10.3%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: +4.9%, p95_ms: +13.8%, p99_ms: +8.0%, requests_per_second: -10.3%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.6%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -3.1%, p95_ms: -4.7%, p99_ms: -1.0%, requests_per_second: +3.4%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +2.2%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +0.2%, p95_ms: +1.4%, p99_ms: +24.0%, requests_per_second: -0.7%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -2.2%, cpu_percent: -0.8%, duration_seconds: -0.1%, p50_ms: +2.1%, p95_ms: +2.6%, p99_ms: +8.8%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.3%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -1.0%, p95_ms: -1.5%, p99_ms: -5.6%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -4.2%, cpu_percent: -0.0%, duration_seconds: -4.6%, p50_ms: +0.4%, p95_ms: +0.8%, p99_ms: +18.3%, requests_per_second: -0.5%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.7%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +1.7%, p95_ms: +1.3%, p99_ms: +9.1%, requests_per_second: -1.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.8%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: -0.1%, p95_ms: -3.0%, p99_ms: -24.7%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +0.5%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: +26.3%, p99_ms: +28.5%, requests_per_second: -0.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -1.3%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +1.0%, p95_ms: -7.0%, p99_ms: +21.2%, requests_per_second: -1.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -2.2%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +1.8%, p95_ms: +4.1%, p99_ms: +4.5%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.8%, cpu_percent: +0.7%, duration_seconds: -0.1%, p50_ms: +2.4%, p95_ms: -0.8%, p99_ms: +2.8%, requests_per_second: -2.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -3.1%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: +5.5%, p99_ms: +6.5%, requests_per_second: -3.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -20.8%, cpu_percent: +1.2%, duration_seconds: +0.1%, p50_ms: +3.8%, p95_ms: +21.0%, p99_ms: +18.4%, requests_per_second: -20.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | confirmed-regression | completed: +0.0%, cpu_percent: +1.0%, duration_seconds: -0.1%, p50_ms: +16.3%, p95_ms: +23.1%, p99_ms: +21.9%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -0.1%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -2.9%, p95_ms: +1.5%, p99_ms: +22.9%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.4%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +1.5%, p95_ms: +1.1%, p99_ms: +5.8%, requests_per_second: -0.7%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +0.4%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: -0.1%, p95_ms: -10.1%, p99_ms: +7.8%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -2.9%, cpu_percent: -0.9%, duration_seconds: +0.0%, p50_ms: +3.1%, p95_ms: -5.5%, p99_ms: +7.5%, requests_per_second: -3.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -5.2%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +13.0%, p95_ms: -16.9%, p99_ms: -10.2%, requests_per_second: -5.3%, rss_bytes: +0.2% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -5.8%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -7.6%, p95_ms: +26.4%, p99_ms: +20.7%, requests_per_second: -5.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.7%, cpu_percent: -2.3%, duration_seconds: +0.1%, p50_ms: +20.4%, p95_ms: -13.2%, p99_ms: -10.4%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +14.2%, cpu_percent: +1.4%, duration_seconds: +0.2%, p50_ms: +1.4%, p95_ms: -31.9%, p99_ms: -20.4%, requests_per_second: +13.9%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.8%, cpu_percent: +1.7%, duration_seconds: -0.1%, p50_ms: +0.6%, p95_ms: +12.5%, p99_ms: +12.5%, requests_per_second: +0.9%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.0%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +8.3%, p95_ms: -9.2%, p99_ms: -11.7%, requests_per_second: -0.7%, rss_bytes: +0.2% |
| thread | workers=4 | 2 | 50 | improvement | completed: +48.7%, cpu_percent: +92.8%, duration_seconds: +0.1%, p50_ms: -41.1%, p95_ms: +14.0%, p99_ms: +21.3%, requests_per_second: +48.6%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +48.1%, cpu_percent: +94.2%, duration_seconds: +0.2%, p50_ms: -32.2%, p95_ms: -17.4%, p99_ms: -35.0%, requests_per_second: +48.0%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +16.4%, cpu_percent: +79.2%, duration_seconds: +0.1%, p50_ms: -45.6%, p95_ms: +34.2%, p99_ms: +53.4%, requests_per_second: +16.1%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 100 | improvement | completed: +23.5%, cpu_percent: +79.8%, duration_seconds: +0.2%, p50_ms: -32.9%, p95_ms: +2.9%, p99_ms: -1.8%, requests_per_second: +23.4%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: -0.2%, cpu_percent: +7.9%, duration_seconds: +0.1%, p50_ms: +13.6%, p95_ms: +13.8%, p99_ms: +48.6%, requests_per_second: -0.2%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.5%, cpu_percent: +93.3%, duration_seconds: +0.2%, p50_ms: -38.5%, p95_ms: -5.9%, p99_ms: -13.8%, requests_per_second: +48.6%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 50 | improvement | completed: +42.8%, cpu_percent: +90.8%, duration_seconds: +0.3%, p50_ms: -34.1%, p95_ms: +1.9%, p99_ms: -10.2%, requests_per_second: +42.6%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +42.6%, cpu_percent: +92.9%, duration_seconds: +0.2%, p50_ms: -38.4%, p95_ms: +0.3%, p99_ms: -24.9%, requests_per_second: +42.4%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | improvement | completed: +48.0%, cpu_percent: +73.0%, duration_seconds: +0.1%, p50_ms: -36.9%, p95_ms: -3.7%, p99_ms: +16.0%, requests_per_second: +46.7%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 100 | improvement | completed: +41.0%, cpu_percent: +80.4%, duration_seconds: +0.5%, p50_ms: -41.5%, p95_ms: -43.1%, p99_ms: -35.9%, requests_per_second: +40.3%, rss_bytes: +64.0% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: +0.3%, cpu_percent: +9.4%, duration_seconds: -0.0%, p50_ms: +14.4%, p95_ms: +42.3%, p99_ms: +55.1%, requests_per_second: +0.3%, rss_bytes: +64.0% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +52.4%, cpu_percent: +95.1%, duration_seconds: +0.2%, p50_ms: -35.5%, p95_ms: -9.6%, p99_ms: -29.3%, requests_per_second: +52.1%, rss_bytes: +64.1% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38733529862)
