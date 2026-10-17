# GPForum continuous performance evidence

Commit: `2237bb6d6f0f3a784c29924f74535c7bac0bdb01` · mode: **main** · status: **ok**
Run: 38162864461 / attempt 1 · 2026-10-11T18:13:20.089219+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"ee7d3093ffc5cd7d0cc2f564417c6ad7f1e113aa0c1316b1b59386e9b

Baseline: Compatible baseline. d7bc8a523ef7f7c35515c9f1413738910b3e6d15

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 275.972 | 3.607 | 3.713 | 4.027 | 100.446 / 369.605 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 541.674 | 18.092 | 18.726 | 23.187 | 199.421 / 369.605 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 546.407 | 88.564 | 94.042 | 158.985 | 201.746 / 371.324 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1157.324 | 0.851 | 0.921 | 1.154 | 99.499 / 369.648 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2295.003 | 4.879 | 5.288 | 5.548 | 199.419 / 369.648 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2346.933 | 21.090 | 21.788 | 25.447 | 200.404 / 370.371 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2294.482 | 42.630 | 46.395 | 62.762 | 199.414 / 371.602 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 119.465 | 8.299 | 8.974 | 9.416 | 85.594 / 371.875 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 227.213 | 42.469 | 54.185 | 60.238 | 173.538 / 372.418 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 216.532 | 211.338 | 331.555 | 405.742 | 173.825 / 374.148 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 880.818 | 1.124 | 1.180 | 1.241 | 99.491 / 374.148 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1705.441 | 5.650 | 6.100 | 6.691 | 198.940 / 374.148 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1760.383 | 27.676 | 30.602 | 39.533 | 200.374 / 374.148 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 834.526 | 1.195 | 1.243 | 1.305 | 100.052 / 374.180 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1712.417 | 5.805 | 6.036 | 6.639 | 198.940 / 374.180 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1717.335 | 28.542 | 29.759 | 42.987 | 201.300 / 374.180 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 850.900 | 1.153 | 1.226 | 1.445 | 99.539 / 374.305 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1700.199 | 5.842 | 6.046 | 6.552 | 198.950 / 374.305 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1720.471 | 29.068 | 30.578 | 37.932 | 200.138 / 374.934 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1688.069 | 57.261 | 60.005 | 93.219 | 198.888 / 378.145 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 76.420 | 12.985 | 13.519 | 14.374 | 65.180 / 378.906 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 139.031 | 68.962 | 77.055 | 111.756 | 129.282 / 378.906 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.605 | 360.822 | 616.236 | 705.581 | 129.504 / 378.906 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.748 | 702.081 | 1316.209 | 1374.550 | 130.482 / 378.949 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 867.262 | 1.138 | 1.207 | 1.276 | 99.466 / 378.949 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1715.426 | 5.693 | 6.468 | 8.140 | 199.399 / 378.949 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1766.028 | 27.847 | 28.707 | 40.425 | 200.422 / 378.949 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1769.093 | 55.147 | 58.208 | 88.261 | 199.907 / 378.949 | improvement |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1439.057 | 5.983 | 9.908 | 11.772 | 25.986 / 378.949 | improvement |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 996.026 | 8.529 | 18.000 | 23.515 | 36.678 / 379.254 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2509.196 | 22.074 | 37.918 | 49.808 | 387.763 / 615.645 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2508.319 | 39.577 | 53.881 | 72.320 | 388.685 / 619.750 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 159.461 | 239.354 | 692.450 | 849.469 | 231.366 / 621.129 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 151.179 | 440.787 | 1130.025 | 1176.636 | 234.535 / 622.035 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1715.064 | 34.675 | 40.760 | 61.323 | 216.262 / 622.055 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2599.348 | 37.341 | 46.347 | 66.076 | 388.971 / 622.055 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 277.765 | 3.575 | 3.690 | 4.058 | 99.959 / 370.789 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 544.122 | 18.106 | 18.713 | 31.775 | 199.914 / 370.797 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 535.134 | 90.410 | 94.060 | 160.264 | 201.370 / 372.570 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1178.241 | 0.831 | 0.909 | 0.985 | 99.517 / 370.664 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2324.256 | 4.271 | 4.446 | 5.327 | 198.958 / 370.664 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2352.647 | 20.893 | 22.192 | 25.327 | 200.395 / 371.414 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2317.579 | 42.704 | 43.839 | 63.688 | 200.380 / 372.754 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 118.931 | 8.322 | 8.692 | 9.840 | 85.598 / 373.148 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 225.383 | 42.412 | 51.589 | 76.200 | 173.555 / 373.504 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 221.126 | 213.906 | 342.257 | 408.959 | 174.794 / 375.262 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 883.738 | 1.110 | 1.191 | 1.240 | 99.469 / 375.262 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1738.144 | 5.708 | 5.971 | 7.371 | 199.354 / 375.262 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1744.831 | 28.055 | 29.211 | 37.343 | 199.884 / 375.262 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 848.832 | 1.182 | 1.230 | 1.472 | 99.478 / 375.301 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1715.607 | 5.764 | 6.095 | 8.987 | 198.952 / 375.301 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1741.947 | 28.731 | 29.856 | 40.357 | 200.898 / 375.383 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 864.861 | 1.162 | 1.208 | 1.244 | 99.431 / 375.551 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1700.309 | 5.829 | 6.193 | 8.764 | 199.433 / 375.551 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1725.103 | 28.694 | 30.452 | 41.399 | 200.397 / 376.129 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1670.857 | 58.713 | 61.901 | 97.189 | 200.309 / 379.375 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 75.409 | 13.055 | 14.431 | 14.886 | 66.168 / 379.984 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 135.740 | 71.550 | 90.859 | 136.004 | 131.255 / 379.984 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.685 | 347.040 | 639.651 | 706.324 | 131.440 / 379.984 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.331 | 714.060 | 1333.545 | 1391.130 | 130.394 / 379.984 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 870.229 | 1.139 | 1.204 | 1.305 | 99.990 / 379.984 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1763.108 | 5.624 | 5.909 | 7.412 | 199.428 / 379.984 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1783.457 | 27.837 | 28.467 | 35.700 | 200.881 / 379.984 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1724.756 | 56.435 | 75.716 | 92.376 | 200.749 / 379.984 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2503.852 | 19.395 | 31.383 | 36.693 | 384.816 / 617.336 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2501.792 | 38.860 | 54.763 | 76.257 | 386.622 / 621.340 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 157.018 | 236.234 | 592.811 | 858.614 | 234.655 / 622.617 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 146.828 | 449.153 | 1362.892 | 1567.079 | 237.282 / 623.867 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 898.866 | 53.911 | 61.519 | 123.301 | 118.978 / 624.770 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2570.296 | 30.364 | 66.287 | 91.284 | 387.284 / 624.770 | improvement |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.499 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.031 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.509 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.643 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.501 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.065 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.096 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.512 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.520 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.297 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.334 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.076 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.044 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.019 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.412 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.451 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.556 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.451 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.489 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.266 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.322 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.847 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.284 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.206 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.155 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.181 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.051 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.016 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.078 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.086 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.070 | — | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 677.760 | 146.687 | 155.045 | 161.216 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1149.371 | 171.385 | 186.843 | 188.529 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: +0.7%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -0.3%, p95_ms: -1.6%, p99_ms: -12.4%, requests_per_second: +0.7%, rss_bytes: +0.5% |
| cache_miss | stable | completed: +4.0%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -1.5%, p95_ms: -3.3%, p99_ms: -6.8%, requests_per_second: +0.1%, rss_bytes: +0.5% |
| cache_miss | stable | completed: +2.8%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -3.3%, p95_ms: -0.6%, p99_ms: -1.4%, requests_per_second: +2.8%, rss_bytes: +0.5% |
| health_live | possible-regression | completed: -0.2%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +0.4%, p95_ms: +0.8%, p99_ms: +21.2%, requests_per_second: -0.2%, rss_bytes: +0.5% |
| health_live | stable | completed: +1.9%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +11.8%, p95_ms: +13.0%, p99_ms: -4.8%, requests_per_second: +2.4%, rss_bytes: +0.5% |
| health_live | stable | completed: +0.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: -2.6%, p99_ms: -7.5%, requests_per_second: +0.2%, rss_bytes: +0.5% |
| health_live | stable | completed: +0.0%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: +3.7%, p99_ms: -1.4%, requests_per_second: +0.0%, rss_bytes: +0.5% |
| home | stable | completed: +0.8%, cpu_percent: -1.1%, duration_seconds: -0.1%, p50_ms: -0.8%, p95_ms: -1.7%, p99_ms: -11.7%, requests_per_second: +2.0%, rss_bytes: +0.5% |
| home | stable | completed: +2.5%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: -3.1%, p95_ms: +6.3%, p99_ms: -2.1%, requests_per_second: +2.4%, rss_bytes: +0.5% |
| home | stable | completed: +3.1%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -3.6%, p95_ms: -5.4%, p99_ms: -3.4%, requests_per_second: +3.1%, rss_bytes: +0.5% |
| categories | stable | completed: -3.9%, cpu_percent: -0.5%, duration_seconds: -4.7%, p50_ms: -2.5%, p95_ms: -1.7%, p99_ms: -1.8%, requests_per_second: +0.9%, rss_bytes: +0.5% |
| categories | stable | completed: -2.1%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -0.5%, p95_ms: +2.5%, p99_ms: -19.7%, requests_per_second: -2.0%, rss_bytes: +0.5% |
| categories | stable | completed: -0.7%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.5%, p95_ms: +4.8%, p99_ms: +9.4%, requests_per_second: -0.7%, rss_bytes: +0.5% |
| category | stable | completed: -3.2%, cpu_percent: +0.6%, duration_seconds: -0.0%, p50_ms: +4.4%, p95_ms: +2.6%, p99_ms: -1.6%, requests_per_second: -3.3%, rss_bytes: +0.5% |
| category | improvement | completed: +0.7%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -0.9%, p95_ms: -2.0%, p99_ms: -21.8%, requests_per_second: +1.6%, rss_bytes: +0.5% |
| category | possible-regression | completed: -1.0%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -0.6%, p95_ms: +0.7%, p99_ms: +16.1%, requests_per_second: -0.9%, rss_bytes: +0.5% |
| thread | stable | completed: +1.9%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -3.8%, p95_ms: -2.1%, p99_ms: -2.0%, requests_per_second: +2.1%, rss_bytes: +0.5% |
| thread | improvement | completed: +5.8%, cpu_percent: +0.0%, duration_seconds: +4.9%, p50_ms: -0.4%, p95_ms: -0.1%, p99_ms: -14.1%, requests_per_second: +0.8%, rss_bytes: +0.5% |
| thread | stable | completed: +0.5%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: +1.1%, p95_ms: +3.0%, p99_ms: +2.8%, requests_per_second: +0.5%, rss_bytes: +0.5% |
| thread | stable | completed: +1.2%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -1.9%, p95_ms: -22.6%, p99_ms: -14.2%, requests_per_second: +1.2%, rss_bytes: +0.5% |
| search | improvement | completed: +4.8%, cpu_percent: -1.5%, duration_seconds: +0.0%, p50_ms: -3.6%, p95_ms: -11.4%, p99_ms: -18.4%, requests_per_second: +4.7%, rss_bytes: +0.6% |
| search | improvement | completed: +9.9%, cpu_percent: -1.7%, duration_seconds: +4.9%, p50_ms: -7.2%, p95_ms: -9.1%, p99_ms: -14.8%, requests_per_second: +5.8%, rss_bytes: +0.5% |
| search | stable | completed: +0.0%, cpu_percent: -2.1%, duration_seconds: +0.1%, p50_ms: -5.1%, p95_ms: -7.2%, p99_ms: -5.3%, requests_per_second: -0.2%, rss_bytes: +0.5% |
| search | stable | completed: +0.0%, cpu_percent: -1.5%, duration_seconds: +0.0%, p50_ms: -7.9%, p95_ms: -8.5%, p99_ms: -9.9%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| cache_hit | stable | completed: -1.1%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -1.4%, p95_ms: +0.2%, p99_ms: -17.6%, requests_per_second: +0.5%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +4.9%, cpu_percent: +0.3%, duration_seconds: +4.9%, p50_ms: -2.0%, p95_ms: +7.4%, p99_ms: -4.4%, requests_per_second: +0.4%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +1.1%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.9%, p95_ms: -2.9%, p99_ms: +8.4%, requests_per_second: +1.0%, rss_bytes: +0.4% |
| cache_hit | improvement | completed: +1.4%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -1.6%, p95_ms: -26.2%, p99_ms: -5.4%, requests_per_second: +1.3%, rss_bytes: +0.4% |
| health_live | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +10.0%, duration_seconds: -2.8%, p50_ms: -2.0%, p95_ms: -4.4%, p99_ms: -16.0%, requests_per_second: +2.0%, rss_bytes: +0.4% |
| thread | possible-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +6.3%, duration_seconds: -1.0%, p50_ms: -3.4%, p95_ms: +19.8%, p99_ms: +33.5%, requests_per_second: +0.9%, rss_bytes: +0.4% |
| thread | confirmed-regression | completed: -0.6%, cpu_percent: +0.3%, duration_seconds: -0.2%, p50_ms: +17.8%, p95_ms: +26.9%, p99_ms: +28.4%, requests_per_second: +0.6%, rss_bytes: +0.5% |
| thread | stable | completed: +1.2%, cpu_percent: +0.2%, duration_seconds: -0.2%, p50_ms: +7.9%, p95_ms: -9.9%, p99_ms: -3.5%, requests_per_second: +0.9%, rss_bytes: +0.6% |
| search | stable | completed: +7.0%, cpu_percent: +2.2%, duration_seconds: +0.0%, p50_ms: -7.4%, p95_ms: +3.7%, p99_ms: -8.6%, requests_per_second: +7.0%, rss_bytes: +0.5% |
| search | stable | completed: +4.5%, cpu_percent: -2.1%, duration_seconds: +0.4%, p50_ms: -22.0%, p95_ms: +5.1%, p99_ms: -7.0%, requests_per_second: +4.3%, rss_bytes: +0.5% |
| cache_hit | possible-regression | completed: -33.2%, cpu_percent: -44.2%, duration_seconds: -0.1%, p50_ms: +74.5%, p95_ms: +7.1%, p99_ms: +34.3%, requests_per_second: -33.2%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +1.5%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -2.6%, p95_ms: +0.9%, p99_ms: -3.5%, requests_per_second: +1.6%, rss_bytes: +0.4% |
| cache_miss | stable | completed: -0.7%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +0.8%, p95_ms: -0.8%, p99_ms: -1.4%, requests_per_second: -0.7%, rss_bytes: +0.6% |
| cache_miss | stable | completed: -1.3%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: +1.4%, p95_ms: -0.3%, p99_ms: +0.2%, requests_per_second: -0.7%, rss_bytes: +0.6% |
| cache_miss | stable | completed: -0.1%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.3%, p95_ms: -3.6%, p99_ms: +0.2%, requests_per_second: -0.1%, rss_bytes: +0.6% |
| health_live | stable | completed: -6.5%, cpu_percent: +0.1%, duration_seconds: -4.7%, p50_ms: +1.1%, p95_ms: +3.2%, p99_ms: +3.4%, requests_per_second: -1.8%, rss_bytes: +0.5% |
| health_live | stable | completed: +0.8%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +0.1%, p99_ms: -2.6%, requests_per_second: -0.1%, rss_bytes: +0.5% |
| health_live | stable | completed: -1.6%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +1.1%, p95_ms: -0.2%, p99_ms: -1.9%, requests_per_second: -1.5%, rss_bytes: +0.5% |
| health_live | stable | completed: -1.1%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +1.1%, p95_ms: +0.6%, p99_ms: +0.3%, requests_per_second: -1.1%, rss_bytes: +0.5% |
| home | stable | completed: +0.0%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: -0.8%, p99_ms: +6.9%, requests_per_second: -0.0%, rss_bytes: +0.5% |
| home | improvement | completed: +8.7%, cpu_percent: +0.7%, duration_seconds: -0.2%, p50_ms: -6.2%, p95_ms: -20.0%, p99_ms: -6.2%, requests_per_second: +14.0%, rss_bytes: +0.5% |
| home | stable | completed: -0.9%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -1.7%, p95_ms: -0.6%, p99_ms: -3.4%, requests_per_second: -0.8%, rss_bytes: +0.5% |
| categories | stable | completed: -0.7%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -1.3%, p95_ms: +1.4%, p99_ms: -2.7%, requests_per_second: -0.7%, rss_bytes: +0.5% |
| categories | stable | completed: -1.9%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +1.0%, p95_ms: +1.8%, p99_ms: -0.6%, requests_per_second: -0.3%, rss_bytes: +0.5% |
| categories | stable | completed: -1.7%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: +1.5%, p95_ms: +0.9%, p99_ms: -3.8%, requests_per_second: -1.7%, rss_bytes: +0.5% |
| category | stable | completed: -4.6%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: +3.1%, p95_ms: +3.1%, p99_ms: +17.6%, requests_per_second: -2.8%, rss_bytes: +0.5% |
| category | stable | completed: +0.1%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: +1.1%, p99_ms: -5.6%, requests_per_second: +0.1%, rss_bytes: +0.5% |
| category | stable | completed: +1.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +3.1%, p95_ms: -9.2%, p99_ms: +1.5%, requests_per_second: +1.2%, rss_bytes: +0.5% |
| thread | stable | completed: -1.4%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +2.8%, p95_ms: +2.6%, p99_ms: +1.0%, requests_per_second: -1.5%, rss_bytes: +0.5% |
| thread | stable | completed: +5.1%, cpu_percent: +0.1%, duration_seconds: +4.8%, p50_ms: -0.3%, p95_ms: -5.5%, p99_ms: -14.3%, requests_per_second: +0.2%, rss_bytes: +0.5% |
| thread | stable | completed: +0.8%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: +2.2%, p99_ms: -10.8%, requests_per_second: +0.7%, rss_bytes: +0.5% |
| thread | stable | completed: -1.2%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +0.9%, p95_ms: +2.8%, p99_ms: -3.1%, requests_per_second: -1.1%, rss_bytes: +0.5% |
| search | stable | completed: +1.3%, cpu_percent: +1.5%, duration_seconds: +0.1%, p50_ms: -1.2%, p95_ms: +1.8%, p99_ms: -2.8%, requests_per_second: +1.3%, rss_bytes: +0.5% |
| search | stable | completed: +6.7%, cpu_percent: +0.0%, duration_seconds: -0.2%, p50_ms: -4.6%, p95_ms: -9.2%, p99_ms: -2.1%, requests_per_second: +6.6%, rss_bytes: +0.5% |
| search | stable | completed: +0.4%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: -4.0%, p95_ms: -2.8%, p99_ms: -5.4%, requests_per_second: +0.3%, rss_bytes: +0.5% |
| search | stable | completed: -0.5%, cpu_percent: -1.1%, duration_seconds: -0.0%, p50_ms: -4.8%, p95_ms: -6.1%, p99_ms: -5.8%, requests_per_second: -0.4%, rss_bytes: +0.5% |
| cache_hit | stable | completed: -1.5%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +2.1%, p95_ms: +1.3%, p99_ms: +5.2%, requests_per_second: -1.4%, rss_bytes: +0.5% |
| cache_hit | stable | completed: +1.2%, cpu_percent: +0.0%, duration_seconds: +0.2%, p50_ms: -0.5%, p95_ms: -0.0%, p99_ms: +4.2%, requests_per_second: +0.7%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +1.7%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -0.5%, p95_ms: -3.8%, p99_ms: -13.2%, requests_per_second: +1.8%, rss_bytes: +0.5% |
| cache_hit | stable | completed: -1.1%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: +28.6%, p99_ms: +0.6%, requests_per_second: -1.2%, rss_bytes: +0.5% |
| thread | stable | completed: +1.2%, cpu_percent: -1.1%, duration_seconds: -0.0%, p50_ms: +7.2%, p95_ms: -5.6%, p99_ms: -23.4%, requests_per_second: +1.2%, rss_bytes: +0.5% |
| thread | stable | completed: +1.4%, cpu_percent: -0.1%, duration_seconds: -0.2%, p50_ms: -2.2%, p95_ms: -2.7%, p99_ms: +2.4%, requests_per_second: +1.6%, rss_bytes: +0.4% |
| search | stable | completed: +6.4%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -7.3%, p95_ms: -15.2%, p99_ms: -3.3%, requests_per_second: +6.2%, rss_bytes: +0.4% |
| search | improvement | completed: -7.5%, cpu_percent: -1.7%, duration_seconds: -0.0%, p50_ms: -19.9%, p95_ms: +17.5%, p99_ms: +20.0%, requests_per_second: -7.8%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -43.5%, cpu_percent: -49.4%, duration_seconds: -0.0%, p50_ms: +62.5%, p95_ms: -5.4%, p99_ms: +75.5%, requests_per_second: -43.4%, rss_bytes: +0.3% |
| cache_hit | improvement | completed: +1.2%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -24.1%, p95_ms: +17.5%, p99_ms: +28.2%, requests_per_second: +1.4%, rss_bytes: +0.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +19.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.2% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.7% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +10.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -5.5% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +12.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -9.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -4.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -10.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.6% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -38.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.9% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +68.6% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -28.6% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -0.9%, messages_per_second: +0.9%, p50_ms: +0.0%, p95_ms: -3.1%, p99_ms: -4.7% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -2.0%, messages_per_second: +2.0%, p50_ms: -1.9%, p95_ms: -6.6%, p99_ms: -6.0% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.7%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -0.9%, p95_ms: -0.6%, p99_ms: +0.8%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -3.4%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +0.1%, p95_ms: -0.1%, p99_ms: +37.0%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -2.1%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +2.1%, p95_ms: +0.0%, p99_ms: +0.8%, requests_per_second: -2.1%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.8%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -2.4%, p95_ms: -1.3%, p99_ms: -14.6%, requests_per_second: +1.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.8%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -12.5%, p95_ms: -15.9%, p99_ms: -4.0%, requests_per_second: +1.3%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.3%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -0.9%, p95_ms: +1.9%, p99_ms: -0.5%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.9%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +0.2%, p95_ms: -5.5%, p99_ms: +1.5%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: -3.1%, p99_ms: +4.5%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -0.9%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -0.1%, p95_ms: -4.8%, p99_ms: +26.5%, requests_per_second: -0.8%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.1%, cpu_percent: +0.6%, duration_seconds: -0.0%, p50_ms: +1.2%, p95_ms: +3.2%, p99_ms: +0.8%, requests_per_second: +2.1%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.3%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -1.2%, p95_ms: +0.9%, p99_ms: -0.1%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.0%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +1.0%, p95_ms: -2.1%, p99_ms: +10.2%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.8%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +1.4%, p95_ms: -4.5%, p99_ms: -5.5%, requests_per_second: -0.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.7%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: -1.1%, p95_ms: -1.0%, p99_ms: +12.8%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +0.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.7%, p95_ms: +1.0%, p99_ms: +35.4%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.5%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +0.7%, p95_ms: +0.3%, p99_ms: -6.1%, requests_per_second: +1.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.7%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +0.8%, p95_ms: -1.5%, p99_ms: -13.9%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -0.0%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -0.2%, p95_ms: +2.4%, p99_ms: +33.8%, requests_per_second: +0.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.4%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -1.3%, p95_ms: -0.4%, p99_ms: +9.1%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.1%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +2.5%, p95_ms: +3.2%, p99_ms: +4.3%, requests_per_second: -1.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.3%, cpu_percent: +1.5%, duration_seconds: +0.0%, p50_ms: +0.5%, p95_ms: +6.7%, p99_ms: +3.6%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -5.9%, cpu_percent: +1.5%, duration_seconds: -4.6%, p50_ms: +3.8%, p95_ms: +17.9%, p99_ms: +21.7%, requests_per_second: -2.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.0%, cpu_percent: +1.5%, duration_seconds: -0.0%, p50_ms: -3.8%, p95_ms: +3.8%, p99_ms: +0.1%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +1.7%, p95_ms: +1.3%, p99_ms: +1.2%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.3%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +0.1%, p95_ms: -0.2%, p99_ms: +2.3%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.2%, cpu_percent: +0.0%, duration_seconds: -4.5%, p50_ms: -1.2%, p95_ms: -8.6%, p99_ms: -8.9%, requests_per_second: +2.8%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +0.9%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: -0.0%, p95_ms: -0.8%, p99_ms: -11.7%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -2.6%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: +2.3%, p95_ms: +30.1%, p99_ms: +4.7%, requests_per_second: -2.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -0.1%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: -12.1%, p95_ms: -17.2%, p99_ms: -26.3%, requests_per_second: -0.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -1.8%, p95_ms: +1.6%, p99_ms: +5.4%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.6%, cpu_percent: +1.4%, duration_seconds: -0.2%, p50_ms: -1.3%, p95_ms: -14.4%, p99_ms: +1.1%, requests_per_second: -1.5%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -3.0%, cpu_percent: +1.2%, duration_seconds: -0.2%, p50_ms: +1.9%, p95_ms: +20.6%, p99_ms: +33.2%, requests_per_second: -2.9%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -47.6%, cpu_percent: -45.0%, duration_seconds: -0.1%, p50_ms: +55.5%, p95_ms: +50.9%, p99_ms: +101.1%, requests_per_second: -47.6%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -1.1%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -18.7%, p95_ms: +43.0%, p99_ms: +38.1%, requests_per_second: -1.1%, rss_bytes: +0.4% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +46.1%, cpu_percent: +93.7%, duration_seconds: +0.1%, p50_ms: -24.1%, p95_ms: +24.0%, p99_ms: +31.3%, requests_per_second: +45.8%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | improvement | completed: +49.2%, cpu_percent: +95.4%, duration_seconds: +0.2%, p50_ms: -30.9%, p95_ms: -10.2%, p99_ms: -22.4%, requests_per_second: +48.6%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | possible-regression | completed: +28.4%, cpu_percent: +78.7%, duration_seconds: +0.4%, p50_ms: -33.7%, p95_ms: +12.4%, p99_ms: +20.4%, requests_per_second: +28.0%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +52.5%, cpu_percent: +79.7%, duration_seconds: +0.5%, p50_ms: -37.2%, p95_ms: -14.1%, p99_ms: -14.4%, requests_per_second: +51.6%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: -2.9%, cpu_percent: +7.9%, duration_seconds: +0.1%, p50_ms: +24.5%, p95_ms: +42.0%, p99_ms: +51.7%, requests_per_second: -2.9%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +46.9%, cpu_percent: +94.6%, duration_seconds: +0.1%, p50_ms: -32.3%, p95_ms: -20.4%, p99_ms: -25.1%, requests_per_second: +46.9%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 50 | improvement | completed: +45.3%, cpu_percent: +92.0%, duration_seconds: +0.1%, p50_ms: -32.4%, p95_ms: +3.1%, p99_ms: -11.4%, requests_per_second: +45.1%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +50.0%, cpu_percent: +93.0%, duration_seconds: +0.2%, p50_ms: -33.8%, p95_ms: -11.5%, p99_ms: -21.5%, requests_per_second: +49.7%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +26.4%, cpu_percent: +78.5%, duration_seconds: +0.3%, p50_ms: -31.9%, p95_ms: -7.3%, p99_ms: +21.6%, requests_per_second: +25.9%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +48.7%, cpu_percent: +82.0%, duration_seconds: +0.2%, p50_ms: -37.1%, p95_ms: +2.2%, p99_ms: +12.6%, requests_per_second: +47.8%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -49.6%, cpu_percent: -40.8%, duration_seconds: -0.0%, p50_ms: +93.7%, p95_ms: +116.1%, p99_ms: +245.4%, requests_per_second: -49.6%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.1%, cpu_percent: +92.9%, duration_seconds: +0.1%, p50_ms: -46.2%, p95_ms: -12.5%, p99_ms: -1.2%, requests_per_second: +49.0%, rss_bytes: +64.4% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38162864461)
