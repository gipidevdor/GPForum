# GPForum continuous performance evidence

Commit: `cec277e18d8e535ea503696969a4616608dfd0e7` · mode: **main** · status: **ok**
Run: 38774605102 / attempt 1 · 2026-10-15T17:07:20.463856+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. b7b72daa5b7a06af6c82ab36945f966e8b98e6ff

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 197.611 | 4.990 | 5.286 | 6.237 | 99.500 / 373.824 | stable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 403.537 | 24.369 | 27.565 | 32.180 | 200.342 / 373.898 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 385.086 | 125.054 | 156.708 | 225.471 | 201.324 / 375.676 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1124.801 | 0.884 | 0.935 | 0.984 | 99.995 / 373.953 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2215.321 | 4.382 | 5.334 | 6.542 | 198.880 / 373.953 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2320.237 | 21.432 | 22.377 | 25.390 | 200.355 / 374.590 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2233.238 | 43.999 | 51.546 | 65.537 | 200.806 / 375.812 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 97.874 | 9.940 | 11.821 | 12.438 | 88.063 / 376.359 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 182.294 | 53.139 | 64.598 | 87.087 | 178.449 / 376.922 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 174.659 | 263.448 | 441.758 | 505.127 | 178.103 / 379.254 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 856.809 | 1.140 | 1.228 | 1.402 | 99.446 / 379.254 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1712.127 | 5.804 | 6.200 | 7.702 | 199.380 / 379.254 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1735.051 | 27.526 | 29.963 | 38.348 | 200.355 / 379.254 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 833.913 | 1.193 | 1.251 | 1.415 | 99.472 / 379.285 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1684.254 | 5.881 | 6.230 | 7.633 | 199.928 / 379.285 | improvement |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1686.525 | 29.092 | 30.977 | 39.902 | 200.820 / 379.285 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 835.182 | 1.180 | 1.246 | 1.495 | 99.916 / 379.410 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1655.768 | 6.015 | 6.266 | 7.536 | 199.341 / 379.410 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1684.090 | 28.946 | 32.541 | 44.151 | 201.264 / 379.410 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1671.333 | 58.877 | 62.153 | 94.145 | 201.363 / 382.160 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 72.945 | 13.443 | 15.153 | 19.277 | 66.121 / 382.641 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 129.374 | 78.272 | 91.551 | 129.755 | 133.696 / 382.746 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 121.654 | 379.509 | 688.198 | 745.337 | 132.318 / 382.746 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 49.874 | 758.878 | 1371.001 | 1424.573 | 70.908 / 384.523 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 846.332 | 1.143 | 1.351 | 1.676 | 118.416 / 385.559 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1721.080 | 5.755 | 6.016 | 6.531 | 198.919 / 385.559 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1747.517 | 28.344 | 29.593 | 35.830 | 201.902 / 385.559 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1693.887 | 57.458 | 61.355 | 92.844 | 200.327 / 385.559 | stable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1423.511 | 6.351 | 11.505 | 12.767 | 27.275 / 385.559 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 960.034 | 9.103 | 15.768 | 18.344 | 40.170 / 385.840 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2432.433 | 20.201 | 29.441 | 38.547 | 386.937 / 622.453 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2402.589 | 39.479 | 60.337 | 72.934 | 385.869 / 626.105 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 156.590 | 212.636 | 656.449 | 799.021 | 238.026 / 627.422 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 149.692 | 566.711 | 1383.508 | 1657.264 | 243.221 / 628.457 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 848.131 | 56.408 | 71.389 | 122.734 | 131.131 / 628.590 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2346.520 | 41.879 | 71.517 | 102.736 | 361.070 / 628.590 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 200.309 | 4.926 | 5.184 | 5.718 | 99.893 / 375.059 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 396.509 | 25.249 | 31.793 | 42.286 | 199.193 / 375.145 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 385.186 | 125.851 | 159.786 | 228.742 | 202.169 / 377.020 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1174.205 | 0.838 | 0.905 | 0.961 | 99.492 / 374.766 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2323.941 | 4.272 | 4.677 | 5.869 | 198.938 / 374.766 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2319.499 | 21.219 | 22.086 | 26.599 | 200.350 / 375.562 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2243.327 | 43.420 | 50.675 | 65.566 | 199.892 / 376.895 | possible-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 97.262 | 9.994 | 11.180 | 13.899 | 88.543 / 377.480 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 182.771 | 53.097 | 66.064 | 93.691 | 177.494 / 378.051 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 173.956 | 262.290 | 425.386 | 501.489 | 178.660 / 380.422 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 878.172 | 1.118 | 1.200 | 1.253 | 99.429 / 380.422 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1716.372 | 5.789 | 6.096 | 8.127 | 199.287 / 380.422 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1656.711 | 29.586 | 36.648 | 47.383 | 199.194 / 380.422 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 856.928 | 1.148 | 1.222 | 1.279 | 99.453 / 380.453 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1686.642 | 5.869 | 6.153 | 8.138 | 198.885 / 380.453 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1695.294 | 29.087 | 30.926 | 41.035 | 199.795 / 380.453 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 845.276 | 1.166 | 1.242 | 1.361 | 99.505 / 380.535 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1671.514 | 5.914 | 6.486 | 9.337 | 199.346 / 380.578 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1679.649 | 29.288 | 30.646 | 44.269 | 201.772 / 380.578 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1661.851 | 59.045 | 61.683 | 99.283 | 201.152 / 383.273 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 70.425 | 13.896 | 16.634 | 18.309 | 66.658 / 384.047 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 123.452 | 76.804 | 113.180 | 144.627 | 132.645 / 384.047 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 124.042 | 400.423 | 664.305 | 749.426 | 131.928 / 384.047 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.673 | 761.443 | 1417.032 | 1477.698 | 133.370 / 384.047 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 862.999 | 1.141 | 1.223 | 1.348 | 99.436 / 384.047 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1722.692 | 5.772 | 6.083 | 8.002 | 198.876 / 384.047 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1728.744 | 28.453 | 31.687 | 42.929 | 199.864 / 384.047 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1690.463 | 57.681 | 61.798 | 93.743 | 201.822 / 384.047 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2473.677 | 16.636 | 31.529 | 41.416 | 385.616 / 624.141 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2408.580 | 38.441 | 62.909 | 93.586 | 383.886 / 628.223 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 151.039 | 224.041 | 745.423 | 1005.907 | 240.458 / 629.441 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 143.233 | 618.351 | 1276.690 | 1506.643 | 243.911 / 630.199 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2098.225 | 23.331 | 41.823 | 53.670 | 301.495 / 630.199 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2504.938 | 37.676 | 46.017 | 65.931 | 389.179 / 630.199 | improvement |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.501 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.426 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.482 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.523 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.113 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.523 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.018 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.134 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.081 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.513 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.572 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.274 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.356 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.057 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.051 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.341 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.421 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.531 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.637 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.454 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.515 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.294 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.567 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.924 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.652 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.221 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.159 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.185 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.054 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.055 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.112 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 665.100 | 149.532 | 162.847 | 170.037 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1076.058 | 185.383 | 205.134 | 206.025 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: +9.3%, cpu_percent: +4.7%, duration_seconds: -0.0%, p50_ms: -8.1%, p95_ms: -8.3%, p99_ms: -5.0%, requests_per_second: +8.6%, rss_bytes: +0.1% |
| cache_miss | improvement | completed: +21.7%, cpu_percent: +4.7%, duration_seconds: -0.0%, p50_ms: -17.7%, p95_ms: -20.5%, p99_ms: -28.8%, requests_per_second: +21.7%, rss_bytes: +0.1% |
| cache_miss | improvement | completed: +19.3%, cpu_percent: +5.2%, duration_seconds: +0.0%, p50_ms: -13.6%, p95_ms: -26.6%, p99_ms: -18.5%, requests_per_second: +19.3%, rss_bytes: +0.1% |
| health_live | stable | completed: +1.6%, cpu_percent: +0.0%, duration_seconds: +5.0%, p50_ms: +2.2%, p95_ms: +3.7%, p99_ms: +4.2%, requests_per_second: -3.1%, rss_bytes: +0.1% |
| health_live | stable | completed: -5.0%, cpu_percent: -0.2%, duration_seconds: -4.6%, p50_ms: +1.9%, p95_ms: +16.0%, p99_ms: +19.0%, requests_per_second: -3.7%, rss_bytes: +0.1% |
| health_live | stable | completed: -2.2%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: +2.9%, p95_ms: +4.0%, p99_ms: +3.2%, requests_per_second: -2.1%, rss_bytes: +0.1% |
| health_live | stable | completed: -3.1%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +4.6%, p95_ms: +1.2%, p99_ms: +2.8%, requests_per_second: -3.0%, rss_bytes: +0.1% |
| home | stable | completed: +6.5%, cpu_percent: +1.7%, duration_seconds: +0.1%, p50_ms: -6.8%, p95_ms: +0.3%, p99_ms: -0.4%, requests_per_second: +6.4%, rss_bytes: +0.1% |
| home | improvement | completed: +12.3%, cpu_percent: +3.5%, duration_seconds: -0.2%, p50_ms: -15.2%, p95_ms: -21.8%, p99_ms: -15.3%, requests_per_second: +12.3%, rss_bytes: +0.1% |
| home | stable | completed: +8.0%, cpu_percent: +2.1%, duration_seconds: -0.0%, p50_ms: -9.9%, p95_ms: -6.4%, p99_ms: -7.6%, requests_per_second: +8.1%, rss_bytes: +0.0% |
| categories | stable | completed: -2.1%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: +1.5%, p95_ms: +3.0%, p99_ms: +8.7%, requests_per_second: -2.1%, rss_bytes: +0.0% |
| categories | stable | completed: -2.2%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +2.2%, p95_ms: +2.8%, p99_ms: +14.2%, requests_per_second: -1.1%, rss_bytes: +0.0% |
| categories | stable | completed: -2.1%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -1.4%, p95_ms: +3.6%, p99_ms: +9.3%, requests_per_second: -2.0%, rss_bytes: +0.0% |
| category | stable | completed: -3.7%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +3.0%, p95_ms: +1.1%, p99_ms: -5.4%, requests_per_second: -1.8%, rss_bytes: +0.0% |
| category | improvement | completed: -0.3%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -10.3%, p95_ms: -11.5%, p99_ms: -2.8%, requests_per_second: -0.3%, rss_bytes: +0.0% |
| category | stable | completed: -1.7%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +1.0%, p95_ms: -3.8%, p99_ms: -6.5%, requests_per_second: -1.7%, rss_bytes: +0.0% |
| thread | stable | completed: -2.2%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +2.3%, p95_ms: +1.9%, p99_ms: +16.2%, requests_per_second: -2.2%, rss_bytes: +0.0% |
| thread | stable | completed: -0.5%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: +1.7%, p95_ms: +2.0%, p99_ms: -0.8%, requests_per_second: -0.5%, rss_bytes: +0.0% |
| thread | possible-regression | completed: -0.0%, cpu_percent: +0.8%, duration_seconds: -0.0%, p50_ms: -1.0%, p95_ms: +7.5%, p99_ms: +17.9%, requests_per_second: +0.1%, rss_bytes: +0.0% |
| thread | stable | completed: +0.0%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +0.8%, p95_ms: +2.8%, p99_ms: -1.8%, requests_per_second: +0.0%, rss_bytes: +0.0% |
| search | stable | completed: +2.8%, cpu_percent: +1.5%, duration_seconds: +0.0%, p50_ms: -2.5%, p95_ms: +1.0%, p99_ms: +5.9%, requests_per_second: +2.8%, rss_bytes: +0.0% |
| search | improvement | completed: +8.4%, cpu_percent: +2.1%, duration_seconds: +0.1%, p50_ms: +1.0%, p95_ms: -5.1%, p99_ms: -18.7%, requests_per_second: +8.4%, rss_bytes: +0.0% |
| search | stable | completed: +9.4%, cpu_percent: +1.4%, duration_seconds: +0.1%, p50_ms: -6.7%, p95_ms: -2.5%, p99_ms: -1.7%, requests_per_second: +9.3%, rss_bytes: +0.0% |
| search | possible-regression | completed: -50.0%, cpu_percent: -45.9%, duration_seconds: +0.0%, p50_ms: -1.7%, p95_ms: -4.2%, p99_ms: -4.4%, requests_per_second: -50.0%, rss_bytes: +0.5% |
| cache_hit | stable | completed: -2.2%, cpu_percent: +19.1%, duration_seconds: -0.0%, p50_ms: +0.9%, p95_ms: +9.4%, p99_ms: +0.5%, requests_per_second: -1.0%, rss_bytes: +0.8% |
| cache_hit | stable | completed: -1.7%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +0.9%, p95_ms: +2.3%, p99_ms: +1.2%, requests_per_second: -0.7%, rss_bytes: +0.8% |
| cache_hit | stable | completed: +0.5%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: -2.0%, p99_ms: -6.9%, requests_per_second: +0.4%, rss_bytes: +0.8% |
| cache_hit | stable | completed: -1.5%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +0.7%, p95_ms: +2.2%, p99_ms: +2.5%, requests_per_second: -1.5%, rss_bytes: +0.8% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +10.0%, duration_seconds: -9.1%, p50_ms: -7.5%, p95_ms: -1.6%, p99_ms: -9.2%, requests_per_second: +9.0%, rss_bytes: +0.8% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -1.0%, duration_seconds: +4.0%, p50_ms: +1.4%, p95_ms: +11.6%, p99_ms: +5.7%, requests_per_second: -4.2%, rss_bytes: +0.8% |
| thread | improvement | completed: +0.1%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -3.2%, p95_ms: -11.9%, p99_ms: -19.4%, requests_per_second: -1.5%, rss_bytes: +0.1% |
| thread | stable | completed: -1.6%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -0.0%, p95_ms: +10.0%, p99_ms: +4.3%, requests_per_second: -1.6%, rss_bytes: +0.0% |
| search | stable | completed: +10.2%, cpu_percent: +1.1%, duration_seconds: -0.3%, p50_ms: +5.9%, p95_ms: -17.7%, p99_ms: -8.4%, requests_per_second: +10.6%, rss_bytes: -0.0% |
| search | possible-regression | completed: +18.0%, cpu_percent: +2.2%, duration_seconds: -0.2%, p50_ms: -7.5%, p95_ms: +27.3%, p99_ms: +27.7%, requests_per_second: +18.2%, rss_bytes: +0.0% |
| cache_hit | possible-regression | completed: -59.9%, cpu_percent: -56.8%, duration_seconds: +0.1%, p50_ms: +189.3%, p95_ms: +71.6%, p99_ms: +150.0%, requests_per_second: -59.9%, rss_bytes: +0.0% |
| cache_hit | possible-regression | completed: -4.4%, cpu_percent: -6.5%, duration_seconds: +0.1%, p50_ms: +5.2%, p95_ms: +34.0%, p99_ms: +40.5%, requests_per_second: -4.6%, rss_bytes: +0.0% |
| cache_miss | stable | completed: +8.4%, cpu_percent: +5.1%, duration_seconds: +0.0%, p50_ms: -7.5%, p95_ms: -7.0%, p99_ms: -14.3%, requests_per_second: +8.3%, rss_bytes: +0.0% |
| cache_miss | improvement | completed: +15.4%, cpu_percent: +4.6%, duration_seconds: -0.1%, p50_ms: -11.2%, p95_ms: -8.6%, p99_ms: -19.0%, requests_per_second: +16.6%, rss_bytes: +0.0% |
| cache_miss | improvement | completed: +15.1%, cpu_percent: +5.1%, duration_seconds: +0.1%, p50_ms: -11.7%, p95_ms: -17.7%, p99_ms: -14.8%, requests_per_second: +15.1%, rss_bytes: +0.0% |
| health_live | stable | completed: -0.2%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +0.7%, p95_ms: +1.3%, p99_ms: -9.9%, requests_per_second: -0.3%, rss_bytes: +0.0% |
| health_live | possible-regression | completed: +0.8%, cpu_percent: -0.5%, duration_seconds: +0.2%, p50_ms: -0.2%, p95_ms: +5.1%, p99_ms: +15.0%, requests_per_second: +0.7%, rss_bytes: +0.0% |
| health_live | improvement | completed: -0.6%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -0.8%, p95_ms: -13.6%, p99_ms: -12.1%, requests_per_second: -0.6%, rss_bytes: +0.0% |
| health_live | possible-regression | completed: -2.8%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -0.5%, p95_ms: +12.7%, p99_ms: +2.0%, requests_per_second: -2.8%, rss_bytes: +0.0% |
| home | stable | completed: +2.6%, cpu_percent: +2.3%, duration_seconds: -0.0%, p50_ms: -3.8%, p95_ms: +1.7%, p99_ms: +5.1%, requests_per_second: +2.4%, rss_bytes: +0.0% |
| home | stable | completed: +2.2%, cpu_percent: +2.0%, duration_seconds: -0.0%, p50_ms: -2.4%, p95_ms: +2.0%, p99_ms: -4.6%, requests_per_second: +3.2%, rss_bytes: +0.0% |
| home | improvement | completed: +8.1%, cpu_percent: +2.5%, duration_seconds: +0.0%, p50_ms: -6.3%, p95_ms: -14.9%, p99_ms: -12.3%, requests_per_second: +9.4%, rss_bytes: +0.0% |
| categories | stable | completed: +0.3%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -2.1%, p95_ms: +2.0%, p99_ms: +2.8%, requests_per_second: +0.3%, rss_bytes: +0.0% |
| categories | stable | completed: -0.5%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: +1.2%, p95_ms: +0.4%, p99_ms: -6.9%, requests_per_second: -0.4%, rss_bytes: +0.0% |
| categories | confirmed-regression | completed: -4.3%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +5.2%, p95_ms: +23.4%, p99_ms: +15.9%, requests_per_second: -4.6%, rss_bytes: +0.0% |
| category | stable | completed: -1.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +2.0%, p95_ms: +1.3%, p99_ms: -19.4%, requests_per_second: -0.9%, rss_bytes: -0.0% |
| category | stable | completed: -1.3%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -0.1%, p95_ms: -3.5%, p99_ms: -2.2%, requests_per_second: -1.6%, rss_bytes: -0.0% |
| category | stable | completed: -1.3%, cpu_percent: -0.3%, duration_seconds: -0.2%, p50_ms: +1.0%, p95_ms: +0.8%, p99_ms: -6.6%, requests_per_second: -1.2%, rss_bytes: -0.0% |
| thread | stable | completed: -3.1%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +1.1%, p95_ms: +2.2%, p99_ms: +8.7%, requests_per_second: -1.4%, rss_bytes: -0.0% |
| thread | stable | completed: -1.3%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: -4.0%, p95_ms: -10.3%, p99_ms: -9.1%, requests_per_second: -1.3%, rss_bytes: -0.0% |
| thread | stable | completed: -0.5%, cpu_percent: +0.7%, duration_seconds: +0.1%, p50_ms: -4.5%, p95_ms: -4.8%, p99_ms: -7.7%, requests_per_second: -0.6%, rss_bytes: -0.0% |
| thread | stable | completed: -0.3%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +0.4%, p95_ms: +0.8%, p99_ms: +0.3%, requests_per_second: -0.4%, rss_bytes: +0.0% |
| search | stable | completed: +2.2%, cpu_percent: +1.5%, duration_seconds: +0.0%, p50_ms: -2.6%, p95_ms: +8.5%, p99_ms: +15.7%, requests_per_second: +2.1%, rss_bytes: +0.0% |
| search | stable | completed: +0.4%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -3.1%, p95_ms: +15.5%, p99_ms: -3.5%, requests_per_second: +0.5%, rss_bytes: +0.0% |
| search | stable | completed: +11.2%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +3.0%, p95_ms: -6.9%, p99_ms: -5.9%, requests_per_second: +10.9%, rss_bytes: +0.0% |
| search | stable | completed: +0.5%, cpu_percent: +1.3%, duration_seconds: -0.0%, p50_ms: -4.8%, p95_ms: -5.8%, p99_ms: -5.4%, requests_per_second: +0.4%, rss_bytes: +0.0% |
| cache_hit | stable | completed: +1.7%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: -1.1%, p95_ms: +0.9%, p99_ms: -5.1%, requests_per_second: +1.2%, rss_bytes: +0.0% |
| cache_hit | stable | completed: +0.9%, cpu_percent: -0.1%, duration_seconds: +0.2%, p50_ms: -0.4%, p95_ms: +1.4%, p99_ms: +4.1%, requests_per_second: +0.4%, rss_bytes: +0.0% |
| cache_hit | stable | completed: +0.1%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -0.2%, p95_ms: +5.4%, p99_ms: +8.8%, requests_per_second: +0.2%, rss_bytes: +0.0% |
| cache_hit | stable | completed: -1.6%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +1.5%, p95_ms: +0.4%, p99_ms: +0.2%, requests_per_second: -1.7%, rss_bytes: +0.0% |
| thread | stable | completed: +0.5%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -6.9%, p95_ms: -5.3%, p99_ms: +3.4%, requests_per_second: +0.7%, rss_bytes: +0.0% |
| thread | stable | completed: +0.1%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -1.9%, p95_ms: +10.3%, p99_ms: +27.4%, requests_per_second: -0.1%, rss_bytes: +0.1% |
| search | stable | completed: -1.9%, cpu_percent: +5.8%, duration_seconds: +0.0%, p50_ms: -21.1%, p95_ms: -0.4%, p99_ms: +15.6%, requests_per_second: -2.0%, rss_bytes: +0.0% |
| search | stable | completed: +6.7%, cpu_percent: +4.2%, duration_seconds: -0.1%, p50_ms: +12.1%, p95_ms: +9.3%, p99_ms: +11.8%, requests_per_second: +6.8%, rss_bytes: +0.0% |
| cache_hit | possible-regression | completed: +20.3%, cpu_percent: +44.4%, duration_seconds: -0.1%, p50_ms: +18.2%, p95_ms: +21.8%, p99_ms: -1.4%, requests_per_second: +20.3%, rss_bytes: +0.0% |
| cache_hit | improvement | completed: +0.3%, cpu_percent: +1.6%, duration_seconds: +0.0%, p50_ms: +2.4%, p95_ms: -24.0%, p99_ms: -14.3%, requests_per_second: +0.3%, rss_bytes: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +18.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.1% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +26.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.7% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +33.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.3% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -21.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +14.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -8.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -8.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -24.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -27.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.1% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +2.5%, messages_per_second: -2.4%, p50_ms: +2.7%, p95_ms: +2.7%, p99_ms: +3.3% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +7.0%, messages_per_second: -6.5%, p50_ms: +8.4%, p95_ms: +2.8%, p99_ms: +3.2% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.8%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -1.3%, p95_ms: -1.9%, p99_ms: -8.3%, requests_per_second: +1.4%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -1.6%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +3.6%, p95_ms: +15.3%, p99_ms: +31.4%, requests_per_second: -1.7%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.0%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: +2.0%, p99_ms: +1.5%, requests_per_second: +0.0%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.1%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -5.2%, p95_ms: -3.2%, p99_ms: -2.3%, requests_per_second: +4.4%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.5%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -2.5%, p95_ms: -12.3%, p99_ms: -10.3%, requests_per_second: +4.9%, rss_bytes: +0.2% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.0%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -1.0%, p95_ms: -1.3%, p99_ms: +4.8%, requests_per_second: -0.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.6%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -1.3%, p95_ms: -1.7%, p99_ms: +0.0%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -0.5%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +0.5%, p95_ms: -5.4%, p99_ms: +11.7%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.3%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -0.1%, p95_ms: +2.3%, p99_ms: +7.6%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.3%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: -0.4%, p95_ms: -3.7%, p99_ms: -0.7%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.6%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -1.9%, p95_ms: -2.3%, p99_ms: -10.6%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.2%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -0.3%, p95_ms: -1.7%, p99_ms: +5.5%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -4.1%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: +7.5%, p95_ms: +22.3%, p99_ms: +23.6%, requests_per_second: -4.5%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.8%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -3.8%, p95_ms: -2.3%, p99_ms: -9.6%, requests_per_second: +2.8%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.0%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -0.2%, p95_ms: -1.2%, p99_ms: +6.6%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.4%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -0.0%, p95_ms: -0.2%, p99_ms: +2.8%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.1%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -1.2%, p95_ms: -0.3%, p99_ms: -9.0%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +0.9%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -1.7%, p95_ms: +3.5%, p99_ms: +23.9%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.3%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +1.2%, p95_ms: -5.8%, p99_ms: +0.3%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +0.3%, p95_ms: -0.8%, p99_ms: +5.5%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -3.4%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: +3.4%, p95_ms: +9.8%, p99_ms: -5.0%, requests_per_second: -3.5%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -4.6%, cpu_percent: -0.8%, duration_seconds: -0.1%, p50_ms: -1.9%, p95_ms: +23.6%, p99_ms: +11.5%, requests_per_second: -4.6%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.0%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +5.5%, p95_ms: -3.5%, p99_ms: +0.5%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +100.0%, cpu_percent: +88.1%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: +3.4%, p99_ms: +3.7%, requests_per_second: +99.9%, rss_bytes: -0.1% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.4%, cpu_percent: -16.0%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: -9.5%, p99_ms: -19.6%, requests_per_second: +2.0%, rss_bytes: -0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +0.2%, cpu_percent: -0.0%, duration_seconds: +0.2%, p50_ms: +0.3%, p95_ms: +1.1%, p99_ms: +22.5%, requests_per_second: +0.1%, rss_bytes: -0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -1.1%, cpu_percent: -1.0%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: +7.1%, p99_ms: +19.8%, requests_per_second: -1.1%, rss_bytes: -0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.1%, cpu_percent: +0.7%, duration_seconds: -0.1%, p50_ms: +0.4%, p95_ms: +0.7%, p99_ms: +1.0%, requests_per_second: -0.2%, rss_bytes: -0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.1%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: -17.6%, p95_ms: +7.1%, p99_ms: +7.4%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.4%, cpu_percent: -0.5%, duration_seconds: +0.3%, p50_ms: -2.6%, p95_ms: +4.3%, p99_ms: +28.3%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -3.5%, cpu_percent: +1.0%, duration_seconds: +0.0%, p50_ms: +5.4%, p95_ms: +13.6%, p99_ms: +25.9%, requests_per_second: -3.5%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -4.3%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: +9.1%, p95_ms: -7.7%, p99_ms: -9.1%, requests_per_second: -4.3%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +147.7%, cpu_percent: +129.9%, duration_seconds: +0.0%, p50_ms: -58.6%, p95_ms: -41.4%, p99_ms: -56.3%, requests_per_second: +147.4%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +6.6%, cpu_percent: +7.8%, duration_seconds: -0.1%, p50_ms: -10.0%, p95_ms: -35.7%, p99_ms: -35.8%, requests_per_second: +6.8%, rss_bytes: +0.3% |
| thread | workers=4 | 2 | 50 | improvement | completed: +47.0%, cpu_percent: +92.3%, duration_seconds: +0.1%, p50_ms: -30.2%, p95_ms: -9.5%, p99_ms: -12.7%, requests_per_second: +44.4%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +43.8%, cpu_percent: +91.6%, duration_seconds: +0.0%, p50_ms: -32.9%, p95_ms: -2.9%, p99_ms: -22.5%, requests_per_second: +43.8%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | improvement | completed: +28.7%, cpu_percent: +79.9%, duration_seconds: +0.0%, p50_ms: -44.0%, p95_ms: -4.6%, p99_ms: +7.2%, requests_per_second: +28.7%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +201.0%, cpu_percent: +243.0%, duration_seconds: +0.2%, p50_ms: -25.3%, p95_ms: +0.9%, p99_ms: +16.3%, requests_per_second: +200.1%, rss_bytes: +63.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -51.5%, cpu_percent: -35.1%, duration_seconds: +0.0%, p50_ms: +99.0%, p95_ms: +141.2%, p99_ms: +242.5%, requests_per_second: -51.5%, rss_bytes: +63.0% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +38.7%, cpu_percent: +80.2%, duration_seconds: +0.2%, p50_ms: -27.1%, p95_ms: +16.6%, p99_ms: +10.7%, requests_per_second: +38.5%, rss_bytes: +63.0% |
| thread | workers=4 | 2 | 50 | improvement | completed: +47.2%, cpu_percent: +91.1%, duration_seconds: -0.0%, p50_ms: -43.2%, p95_ms: +2.9%, p99_ms: -6.4%, requests_per_second: +47.3%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +45.1%, cpu_percent: +90.8%, duration_seconds: +0.3%, p50_ms: -34.9%, p95_ms: +2.0%, p99_ms: -5.7%, requests_per_second: +44.9%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +21.7%, cpu_percent: +82.3%, duration_seconds: +0.1%, p50_ms: -44.0%, p95_ms: +12.2%, p99_ms: +34.2%, requests_per_second: +21.8%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +44.0%, cpu_percent: +82.9%, duration_seconds: +0.3%, p50_ms: -18.8%, p95_ms: -9.9%, p99_ms: +2.0%, requests_per_second: +43.7%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: +21.5%, cpu_percent: +50.9%, duration_seconds: +0.1%, p50_ms: -18.0%, p95_ms: +32.0%, p99_ms: +25.0%, requests_per_second: +21.4%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +48.0%, cpu_percent: +92.8%, duration_seconds: +0.2%, p50_ms: -34.7%, p95_ms: -25.5%, p99_ms: -29.7%, requests_per_second: +48.2%, rss_bytes: +64.1% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38774605102)
