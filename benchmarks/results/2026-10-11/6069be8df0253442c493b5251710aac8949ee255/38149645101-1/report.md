# GPForum continuous performance evidence

Commit: `6069be8df0253442c493b5251710aac8949ee255` · mode: **main** · status: **ok**
Run: 38149645101 / attempt 1 · 2026-10-11T15:03:18.006032+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev": "4.37", "mojolicious": "9.49", "perl": "v5.40.1", "postgres": "16.15 (Debian 16.15-1.pgdg13+2)", "wrk": "wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts": {"bookmarks": 25, "categories": 8, "feed_items": 240, "moderation_actions": 25, "notifications": 75, "permissions": 6, "posts": 4800, "posts_per_thread": 20, "read_states": 75, "reports": 50, "role_bindings": 25, "roles": 3, "sessions": 25, "subscriptions": 25, "threads": 240, "users": 25}, "implementation_sha256": {"lib/GPForum/Benchmark/SeedDataset.pm": "8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb", "lib/GPForum/Command/PerformanceSeed.pm": "ee7d3093ffc5cd7d0cc2

Baseline: No baseline available.

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 277.337 | 3.560 | 3.726 | 4.214 | 100.304 / 367.758 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 551.077 | 18.002 | 18.540 | 21.559 | 200.974 / 367.773 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 536.892 | 90.149 | 95.497 | 157.789 | 200.546 / 369.461 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1154.055 | 0.853 | 0.915 | 0.951 | 100.327 / 367.957 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2271.026 | 4.326 | 4.523 | 4.989 | 200.048 / 367.957 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2356.689 | 21.033 | 21.837 | 24.830 | 200.640 / 368.629 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2272.089 | 43.149 | 44.400 | 64.752 | 200.842 / 369.875 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 118.829 | 8.301 | 8.693 | 9.953 | 86.523 / 370.270 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 228.288 | 42.578 | 48.577 | 60.334 | 172.982 / 370.664 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 223.136 | 215.209 | 337.149 | 406.942 | 173.382 / 372.406 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 884.777 | 1.122 | 1.167 | 1.223 | 100.256 / 372.406 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1702.347 | 5.791 | 6.208 | 7.438 | 200.059 / 372.406 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1743.305 | 28.717 | 33.409 | 44.125 | 200.333 / 372.406 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 849.501 | 1.161 | 1.236 | 1.259 | 99.785 / 372.449 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1676.637 | 5.860 | 6.125 | 7.474 | 199.547 / 372.449 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1721.225 | 28.670 | 29.673 | 36.737 | 201.103 / 372.449 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 837.518 | 1.168 | 1.244 | 1.749 | 99.777 / 372.574 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1660.705 | 5.946 | 6.382 | 8.524 | 199.780 / 372.574 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1694.379 | 29.168 | 30.239 | 38.084 | 201.231 / 373.125 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1681.674 | 58.248 | 60.789 | 93.912 | 201.619 / 376.355 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 75.989 | 13.020 | 13.507 | 14.563 | 65.332 / 376.949 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 134.399 | 70.443 | 85.708 | 126.342 | 129.719 / 376.949 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 124.832 | 355.845 | 623.442 | 703.996 | 130.595 / 376.949 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.773 | 715.429 | 1338.123 | 1431.662 | 129.207 / 376.949 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 845.198 | 1.185 | 1.233 | 1.298 | 100.253 / 376.949 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1703.675 | 5.812 | 6.127 | 6.761 | 199.795 / 376.949 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1741.687 | 28.353 | 31.642 | 39.646 | 201.259 / 376.949 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1746.119 | 56.529 | 57.846 | 90.112 | 200.366 / 376.949 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1362.269 | 6.176 | 13.273 | 14.659 | 25.784 / 376.949 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 988.444 | 9.424 | 14.627 | 18.913 | 37.516 / 377.246 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2490.107 | 19.832 | 34.668 | 43.349 | 389.279 / 612.871 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2468.864 | 39.500 | 56.030 | 77.637 | 384.756 / 616.840 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 158.053 | 194.169 | 770.336 | 933.538 | 228.635 / 618.504 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 152.391 | 538.038 | 1136.976 | 1173.940 | 230.977 / 619.902 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1647.888 | 33.891 | 53.205 | 67.309 | 222.369 / 619.902 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2578.125 | 38.729 | 46.398 | 61.736 | 391.103 / 619.902 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 278.619 | 3.559 | 3.676 | 3.882 | 100.211 / 368.863 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 545.933 | 17.900 | 18.860 | 27.045 | 200.776 / 368.891 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 543.194 | 89.887 | 97.335 | 159.138 | 200.962 / 370.684 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1176.859 | 0.834 | 0.903 | 0.968 | 99.826 / 369.133 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2319.233 | 4.287 | 4.420 | 5.030 | 200.081 / 369.133 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2369.987 | 21.049 | 21.906 | 24.602 | 200.638 / 369.883 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2295.934 | 42.877 | 44.788 | 63.920 | 200.648 / 371.230 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 119.413 | 8.250 | 8.756 | 9.537 | 86.273 / 371.676 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 227.687 | 42.457 | 48.891 | 76.633 | 173.040 / 372.066 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 223.789 | 213.546 | 334.243 | 408.627 | 173.102 / 373.805 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 891.433 | 1.109 | 1.178 | 1.209 | 99.835 / 373.805 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1753.844 | 5.723 | 5.891 | 7.160 | 199.946 / 373.805 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1745.769 | 28.222 | 32.554 | 41.732 | 200.149 / 373.805 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 876.943 | 1.144 | 1.183 | 1.221 | 99.826 / 373.836 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1711.402 | 5.811 | 6.192 | 8.809 | 200.008 / 373.836 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1733.461 | 28.670 | 29.685 | 38.782 | 200.556 / 373.836 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 876.920 | 1.132 | 1.179 | 1.230 | 100.276 / 373.941 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1686.930 | 5.810 | 7.475 | 9.913 | 200.464 / 373.961 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1725.731 | 28.574 | 29.914 | 47.702 | 200.838 / 374.484 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1692.982 | 57.364 | 62.330 | 98.474 | 200.881 / 377.676 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 76.427 | 13.032 | 13.609 | 15.344 | 65.331 / 378.422 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 134.909 | 68.830 | 102.717 | 150.079 | 130.093 / 378.449 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 122.257 | 347.258 | 632.167 | 717.924 | 128.497 / 378.449 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.735 | 709.016 | 1335.092 | 1388.137 | 129.898 / 378.449 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 900.482 | 1.100 | 1.162 | 1.205 | 100.175 / 378.449 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1749.620 | 5.609 | 6.056 | 7.326 | 200.133 / 378.449 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1735.126 | 27.644 | 34.963 | 50.474 | 200.787 / 378.449 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1744.582 | 55.923 | 57.551 | 91.634 | 200.918 / 378.449 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2479.458 | 20.492 | 28.985 | 37.604 | 388.600 / 614.520 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2513.202 | 35.691 | 60.677 | 67.974 | 389.709 / 618.371 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 157.433 | 249.945 | 666.016 | 868.547 | 224.154 / 620.285 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 150.128 | 566.049 | 1308.072 | 1514.961 | 230.624 / 621.234 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 845.700 | 54.440 | 80.565 | 127.344 | 134.194 / 621.512 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2543.849 | 38.618 | 46.018 | 65.726 | 392.210 / 621.512 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.504 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.032 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.503 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.528 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.094 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.540 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.980 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.112 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.500 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.531 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.296 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.328 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.075 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.044 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.046 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.019 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.409 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.417 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.520 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.418 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.510 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.267 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.320 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.826 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.278 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.181 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.154 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.175 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.016 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.101 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.079 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.087 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.059 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 674.378 | 147.427 | 158.475 | 167.597 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1139.985 | 171.631 | 192.376 | 192.753 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.1%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -0.0%, p95_ms: -1.3%, p99_ms: -7.9%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.9%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: +1.7%, p99_ms: +25.4%, requests_per_second: -0.9%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.2%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -0.3%, p95_ms: +1.9%, p99_ms: +0.9%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.8%, cpu_percent: -0.5%, duration_seconds: -4.7%, p50_ms: -2.2%, p95_ms: -1.3%, p99_ms: +1.8%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.0%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -0.9%, p95_ms: -2.3%, p99_ms: +0.8%, requests_per_second: +2.1%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +0.1%, p95_ms: +0.3%, p99_ms: -0.9%, requests_per_second: +0.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.1%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: +0.9%, p99_ms: -1.3%, requests_per_second: +1.0%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.4%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: -0.6%, p95_ms: +0.7%, p99_ms: -4.2%, requests_per_second: +0.5%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +3.9%, cpu_percent: +0.0%, duration_seconds: +4.9%, p50_ms: -0.3%, p95_ms: +0.6%, p99_ms: +27.0%, requests_per_second: -0.3%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.2%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -0.8%, p95_ms: -0.9%, p99_ms: +0.4%, requests_per_second: +0.3%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.5%, cpu_percent: -0.4%, duration_seconds: -0.1%, p50_ms: -1.2%, p95_ms: +0.9%, p99_ms: -1.1%, requests_per_second: +0.8%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.7%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -1.2%, p95_ms: -5.1%, p99_ms: -3.7%, requests_per_second: +3.0%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.2%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -1.7%, p95_ms: -2.6%, p99_ms: -5.4%, requests_per_second: +0.1%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.7%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -1.5%, p95_ms: -4.3%, p99_ms: -3.0%, requests_per_second: +3.2%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.9%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -0.8%, p95_ms: +1.1%, p99_ms: +17.9%, requests_per_second: +2.1%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.6%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +0.0%, p95_ms: +0.0%, p99_ms: +5.6%, requests_per_second: +0.7%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +3.5%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -3.1%, p95_ms: -5.2%, p99_ms: -29.7%, requests_per_second: +4.7%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +0.6%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: -2.3%, p95_ms: +17.1%, p99_ms: +16.3%, requests_per_second: +1.6%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +1.8%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -2.0%, p95_ms: -1.1%, p99_ms: +25.3%, requests_per_second: +1.9%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.4%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -1.5%, p95_ms: +2.5%, p99_ms: +4.9%, requests_per_second: +0.7%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.7%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +0.1%, p95_ms: +0.8%, p99_ms: +5.4%, requests_per_second: +0.6%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +0.4%, cpu_percent: +0.3%, duration_seconds: -0.2%, p50_ms: -2.3%, p95_ms: +19.8%, p99_ms: +18.8%, requests_per_second: +0.4%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -2.0%, cpu_percent: -1.6%, duration_seconds: +0.0%, p50_ms: -2.4%, p95_ms: +1.4%, p99_ms: +2.0%, requests_per_second: -2.1%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -0.9%, p95_ms: -0.2%, p99_ms: -3.0%, requests_per_second: -0.0%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +6.6%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -7.2%, p95_ms: -5.8%, p99_ms: -7.2%, requests_per_second: +6.5%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +4.1%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -3.5%, p95_ms: -1.2%, p99_ms: +8.4%, requests_per_second: +2.7%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +1.9%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -2.5%, p95_ms: +10.5%, p99_ms: +27.3%, requests_per_second: -0.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.2%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -1.1%, p95_ms: -0.5%, p99_ms: +1.7%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -0.3%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: +3.3%, p95_ms: -16.4%, p99_ms: -13.3%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.8%, cpu_percent: +1.3%, duration_seconds: -0.0%, p50_ms: -9.6%, p95_ms: +8.3%, p99_ms: -12.4%, requests_per_second: +1.8%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.3%, cpu_percent: -2.0%, duration_seconds: -0.0%, p50_ms: +28.7%, p95_ms: -13.5%, p99_ms: -7.0%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.3%, cpu_percent: -0.2%, duration_seconds: +0.2%, p50_ms: +5.2%, p95_ms: +15.0%, p99_ms: +29.0%, requests_per_second: -1.5%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -48.6%, cpu_percent: -39.7%, duration_seconds: +0.0%, p50_ms: +60.6%, p95_ms: +51.4%, p99_ms: +89.2%, requests_per_second: -48.7%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.1%, cpu_percent: +0.3%, duration_seconds: +0.2%, p50_ms: -0.3%, p95_ms: -0.8%, p99_ms: +6.5%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +47.0%, cpu_percent: +93.4%, duration_seconds: +0.0%, p50_ms: -32.0%, p95_ms: +14.6%, p99_ms: +13.8%, requests_per_second: +47.0%, rss_bytes: +64.3% |
| thread | workers=4 | 2 | 100 | improvement | completed: +46.5%, cpu_percent: +90.8%, duration_seconds: +0.2%, p50_ms: -32.2%, p95_ms: -7.8%, p99_ms: -17.3%, requests_per_second: +46.8%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +26.8%, cpu_percent: +75.1%, duration_seconds: +0.2%, p50_ms: -45.4%, p95_ms: +23.6%, p99_ms: +32.6%, requests_per_second: +26.6%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +53.0%, cpu_percent: +78.8%, duration_seconds: +0.1%, p50_ms: -24.8%, p95_ms: -15.0%, p99_ms: -18.0%, requests_per_second: +52.7%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: -5.4%, cpu_percent: +10.5%, duration_seconds: +0.1%, p50_ms: +19.5%, p95_ms: +68.1%, p99_ms: +69.8%, requests_per_second: -5.4%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +47.6%, cpu_percent: +95.2%, duration_seconds: +0.0%, p50_ms: -31.5%, p95_ms: -19.8%, p99_ms: -31.5%, requests_per_second: +47.6%, rss_bytes: +64.5% |
| thread | workers=4 | 2 | 50 | improvement | completed: +44.0%, cpu_percent: +93.5%, duration_seconds: +0.2%, p50_ms: -28.3%, p95_ms: -3.1%, p99_ms: -21.2%, requests_per_second: +43.7%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +48.6%, cpu_percent: +94.0%, duration_seconds: +0.1%, p50_ms: -37.8%, p95_ms: -2.7%, p99_ms: -31.0%, requests_per_second: +48.4%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +29.0%, cpu_percent: +74.4%, duration_seconds: +0.1%, p50_ms: -28.0%, p95_ms: +5.4%, p99_ms: +21.0%, requests_per_second: +28.8%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +51.0%, cpu_percent: +77.5%, duration_seconds: +0.3%, p50_ms: -20.2%, p95_ms: -2.0%, p99_ms: +9.1%, requests_per_second: +50.5%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -52.3%, cpu_percent: -33.2%, duration_seconds: +0.2%, p50_ms: +96.9%, p95_ms: +130.4%, p99_ms: +152.3%, requests_per_second: -51.3%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +46.3%, cpu_percent: +95.2%, duration_seconds: +0.2%, p50_ms: -30.9%, p95_ms: -20.0%, p99_ms: -28.3%, requests_per_second: +45.8%, rss_bytes: +64.2% |

## Suite status and skipped tests

- contracts: **ok** — GitHub Actions step outcome: success
- database: **ok** — See individual gates and diagnostic artifacts; skipped suites never imply execution
- database-plans-functions: **ok** — Nested stored-function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- database-plans-readers: **ok** — Nested stored-function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- databases: **ok** — GitHub Actions step outcome: success
- hotpaths_workflow: **ok** — GitHub Actions step outcome: success
- http: **ok** — completed planned HTTP measurements
  - {"reason": "read-only anonymous suite; safe durable auth fixture unavailable", "scenario": "authenticated"}
  - {"reason": "bounded targeted plan: every endpoint at low load; high concurrency on health/thread/search/cache_hit; extra workers only thread/search/cache_hit", "scenario": "full_cartesian_matrix"}
  - {"reason": "bounded PR/main modes; use deep sweep", "scenario": "concurrency_250_500"}
  - {"reason": "eight-worker sweep reserved for capable deep runners", "scenario": "workers_8"}
  - {"reason": "requires explicit --allow-1000 and capable runner", "scenario": "concurrency_1000"}
  - {"reason": "wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)", "scenario": "wrk_upstream_version"}
- http_workflow: **ok** — GitHub Actions step outcome: success
- migrations: **ok** — GitHub Actions step outcome: success
- outbox: **ok** — See individual gates and diagnostic artifacts; skipped suites never imply execution
- outbox-postgres: **ok** — Fresh owned database is dropped on completion or caught signals; synthetic delivery IDs verify losses and duplicates
- pr_comment: **skipped** — Job Summary and artifacts provide PR results with a read-only token; no privileged fork artifact/comment workflow is enabled.
- profiling: **skipped** — Reserved for bounded weekly/manual deep mode
- query-budget: **ok** — Catalog drift is deterministic; N+1 request counts remain blocking in ci.yml integration tier
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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38149645101)
