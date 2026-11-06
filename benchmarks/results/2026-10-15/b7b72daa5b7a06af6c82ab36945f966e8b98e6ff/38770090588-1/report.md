# GPForum continuous performance evidence

Commit: `b7b72daa5b7a06af6c82ab36945f966e8b98e6ff` · mode: **main** · status: **ok**
Run: 38770090588 / attempt 1 · 2026-10-15T16:34:35.634432+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. d68bc52cae27c058c769d4a95a02b7df6232abc9

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 181.961 | 5.430 | 5.767 | 6.567 | 95.003 / 373.594 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 331.596 | 29.602 | 34.669 | 45.215 | 191.312 / 373.676 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 322.800 | 144.814 | 213.427 | 276.642 | 191.405 / 375.465 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1161.100 | 0.865 | 0.902 | 0.944 | 99.966 / 373.668 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2299.729 | 4.299 | 4.599 | 5.496 | 199.265 / 373.668 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2370.817 | 20.836 | 21.515 | 24.593 | 200.415 / 374.289 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2303.079 | 42.067 | 50.941 | 63.773 | 199.910 / 375.598 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 91.951 | 10.662 | 11.781 | 12.486 | 86.590 / 376.090 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 162.330 | 62.627 | 82.574 | 102.769 | 172.352 / 376.719 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 161.620 | 292.297 | 471.955 | 546.873 | 174.510 / 379.188 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 875.377 | 1.123 | 1.192 | 1.290 | 99.915 / 379.188 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1731.993 | 5.681 | 6.029 | 6.743 | 199.296 / 379.188 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1770.846 | 27.931 | 28.914 | 35.074 | 200.780 / 379.188 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 848.926 | 1.158 | 1.238 | 1.495 | 99.483 / 379.219 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1689.234 | 6.556 | 7.038 | 7.850 | 199.795 / 379.219 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1715.997 | 28.805 | 32.206 | 42.675 | 201.228 / 379.219 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 854.374 | 1.153 | 1.223 | 1.287 | 99.450 / 379.344 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1664.600 | 5.914 | 6.144 | 7.599 | 199.346 / 379.344 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1683.172 | 29.245 | 30.260 | 37.462 | 199.766 / 379.383 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1670.580 | 58.409 | 60.485 | 95.854 | 200.845 / 381.992 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 70.950 | 13.787 | 14.997 | 18.200 | 65.174 / 382.570 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 119.382 | 77.486 | 96.441 | 159.567 | 130.958 / 382.570 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 111.329 | 406.837 | 705.646 | 758.189 | 130.462 / 382.570 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.760 | 772.213 | 1430.494 | 1490.520 | 130.954 / 382.570 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 855.216 | 1.133 | 1.235 | 1.668 | 99.462 / 382.570 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1733.747 | 5.703 | 5.882 | 6.455 | 198.929 / 382.570 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1739.747 | 28.410 | 30.210 | 38.487 | 200.267 / 382.570 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1720.252 | 57.074 | 60.018 | 90.621 | 199.752 / 382.570 | stable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1305.722 | 6.869 | 11.694 | 14.067 | 24.797 / 382.570 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1001.922 | 8.976 | 14.123 | 17.351 | 40.570 / 382.852 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2469.263 | 20.861 | 33.428 | 47.810 | 387.892 / 622.039 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2441.501 | 39.498 | 54.853 | 69.903 | 386.635 / 625.898 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 141.524 | 200.775 | 797.588 | 872.742 | 235.489 / 627.707 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 126.680 | 612.391 | 1086.976 | 1297.727 | 238.030 / 628.391 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2114.245 | 19.499 | 41.598 | 49.100 | 303.585 / 628.418 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2460.481 | 39.792 | 53.356 | 73.100 | 386.210 / 628.469 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 184.933 | 5.328 | 5.575 | 6.669 | 95.022 / 374.887 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 339.974 | 28.434 | 34.789 | 52.217 | 190.404 / 374.984 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 334.674 | 142.504 | 194.216 | 268.543 | 192.417 / 376.852 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1177.948 | 0.832 | 0.893 | 1.067 | 99.020 / 374.633 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2308.912 | 4.279 | 4.452 | 5.103 | 199.894 / 374.633 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2334.170 | 21.380 | 25.571 | 30.268 | 199.798 / 375.387 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2307.166 | 43.640 | 44.965 | 64.300 | 199.372 / 376.758 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 94.983 | 10.393 | 10.995 | 13.225 | 86.555 / 377.367 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 177.145 | 54.423 | 64.773 | 98.241 | 174.003 / 377.969 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 158.975 | 280.007 | 500.067 | 571.832 | 174.273 / 380.332 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 875.575 | 1.142 | 1.176 | 1.219 | 99.439 / 380.332 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1722.478 | 5.720 | 6.069 | 8.731 | 199.333 / 380.332 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1737.126 | 28.135 | 29.696 | 40.868 | 199.860 / 380.332 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 864.935 | 1.126 | 1.206 | 1.586 | 99.471 / 380.484 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1713.556 | 5.877 | 6.373 | 8.324 | 198.896 / 380.484 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1716.633 | 28.792 | 30.688 | 43.922 | 200.343 / 380.484 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 856.863 | 1.153 | 1.215 | 1.252 | 99.454 / 380.609 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1692.888 | 6.163 | 7.230 | 10.272 | 198.352 / 380.609 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1689.327 | 30.653 | 32.201 | 47.956 | 200.330 / 380.609 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1668.877 | 58.805 | 61.182 | 98.966 | 200.305 / 383.207 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 68.961 | 14.268 | 15.335 | 15.831 | 65.678 / 384.016 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 122.885 | 79.258 | 98.022 | 149.850 | 133.200 / 384.016 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 111.877 | 388.937 | 713.828 | 796.128 | 131.415 / 384.016 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.306 | 799.628 | 1504.466 | 1561.405 | 131.702 / 384.016 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 852.590 | 1.154 | 1.212 | 1.421 | 99.017 / 384.016 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1716.039 | 5.798 | 5.999 | 7.688 | 199.091 / 384.016 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1726.036 | 28.522 | 30.051 | 39.439 | 200.283 / 384.016 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1719.461 | 56.817 | 61.551 | 93.581 | 201.249 / 384.016 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2456.585 | 17.868 | 33.283 | 40.042 | 386.389 / 623.926 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2410.716 | 39.195 | 57.022 | 73.458 | 384.299 / 627.879 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 154.134 | 283.892 | 748.674 | 870.265 | 227.259 / 629.363 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 134.147 | 551.599 | 1168.408 | 1347.019 | 234.190 / 629.969 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1744.124 | 19.739 | 34.346 | 54.432 | 208.846 / 630.090 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2497.010 | 36.808 | 60.526 | 76.948 | 383.218 / 630.188 | improvement |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.487 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.438 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.454 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.516 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.522 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.977 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.106 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.081 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.026 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.501 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.537 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.272 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.355 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.114 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.056 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.050 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.343 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.475 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.467 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.555 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.428 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.565 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.320 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.583 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.995 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.677 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.211 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.159 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.189 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.125 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.106 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.076 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.099 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 681.396 | 145.554 | 158.549 | 164.531 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1150.988 | 171.021 | 199.588 | 199.715 | — / — | improvement |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +18.6%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: -16.7%, p95_ms: -19.3%, p99_ms: -12.5%, requests_per_second: +18.6%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +17.7%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: -10.3%, p95_ms: -25.4%, p99_ms: -13.5%, requests_per_second: +17.7%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +29.4%, cpu_percent: +0.9%, duration_seconds: +0.1%, p50_ms: -22.8%, p95_ms: -23.5%, p99_ms: -20.7%, requests_per_second: +29.2%, rss_bytes: +0.5% |
| health_live | stable | completed: +1.4%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: -4.2%, p99_ms: -6.8%, requests_per_second: +2.5%, rss_bytes: +0.5% |
| health_live | stable | completed: +9.7%, cpu_percent: +0.3%, duration_seconds: +4.9%, p50_ms: -4.8%, p95_ms: -2.5%, p99_ms: +3.8%, requests_per_second: +4.7%, rss_bytes: +0.5% |
| health_live | improvement | completed: +9.2%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -7.5%, p95_ms: -8.9%, p99_ms: -17.8%, requests_per_second: +9.1%, rss_bytes: +0.6% |
| health_live | stable | completed: +6.1%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: -6.6%, p95_ms: +2.1%, p99_ms: -6.2%, requests_per_second: +6.2%, rss_bytes: +0.6% |
| home | improvement | completed: +17.2%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -17.2%, p95_ms: -17.7%, p99_ms: -20.0%, requests_per_second: +17.3%, rss_bytes: +0.6% |
| home | improvement | completed: +27.5%, cpu_percent: -0.6%, duration_seconds: +0.2%, p50_ms: -20.5%, p95_ms: -6.8%, p99_ms: -24.7%, requests_per_second: +27.5%, rss_bytes: +0.6% |
| home | improvement | completed: +29.6%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: -23.0%, p95_ms: -26.1%, p99_ms: -22.7%, requests_per_second: +29.6%, rss_bytes: +0.6% |
| categories | stable | completed: +1.7%, cpu_percent: +0.5%, duration_seconds: -4.7%, p50_ms: -3.6%, p95_ms: -8.0%, p99_ms: -14.0%, requests_per_second: +3.0%, rss_bytes: +0.6% |
| categories | improvement | completed: +4.6%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: -3.5%, p95_ms: -13.5%, p99_ms: -26.1%, requests_per_second: +4.0%, rss_bytes: +0.6% |
| categories | stable | completed: +6.0%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -5.8%, p95_ms: -7.6%, p99_ms: -9.7%, requests_per_second: +5.9%, rss_bytes: +0.6% |
| category | stable | completed: +6.1%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -4.5%, p95_ms: -4.9%, p99_ms: -16.6%, requests_per_second: +3.9%, rss_bytes: +0.6% |
| category | stable | completed: +5.8%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +5.8%, p95_ms: +6.3%, p99_ms: +9.1%, requests_per_second: +5.8%, rss_bytes: +0.6% |
| category | stable | completed: +6.9%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -5.4%, p95_ms: -7.0%, p99_ms: -1.0%, requests_per_second: +6.9%, rss_bytes: +0.6% |
| thread | stable | completed: +4.5%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -4.1%, p95_ms: -6.3%, p99_ms: -24.7%, requests_per_second: +4.5%, rss_bytes: +0.6% |
| thread | stable | completed: +1.9%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -2.6%, p95_ms: -5.0%, p99_ms: -3.1%, requests_per_second: +1.8%, rss_bytes: +0.6% |
| thread | improvement | completed: +6.3%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: -5.7%, p95_ms: -13.1%, p99_ms: -8.8%, requests_per_second: +6.1%, rss_bytes: +0.6% |
| thread | improvement | completed: +8.1%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -7.2%, p95_ms: -11.0%, p99_ms: -5.3%, requests_per_second: +8.1%, rss_bytes: +0.5% |
| search | improvement | completed: +23.5%, cpu_percent: -5.0%, duration_seconds: -0.0%, p50_ms: -18.8%, p95_ms: -26.8%, p99_ms: -21.2%, requests_per_second: +23.5%, rss_bytes: +0.5% |
| search | improvement | completed: +16.0%, cpu_percent: -3.7%, duration_seconds: +0.1%, p50_ms: -11.7%, p95_ms: -25.6%, p99_ms: -2.1%, requests_per_second: +16.0%, rss_bytes: +0.5% |
| search | improvement | completed: +28.2%, cpu_percent: -3.6%, duration_seconds: -0.0%, p50_ms: -13.6%, p95_ms: -21.1%, p99_ms: -22.5%, requests_per_second: +28.2%, rss_bytes: +0.5% |
| search | stable | completed: +0.0%, cpu_percent: -3.5%, duration_seconds: +0.1%, p50_ms: -13.4%, p95_ms: -14.2%, p99_ms: -14.7%, requests_per_second: -0.1%, rss_bytes: +0.5% |
| cache_hit | stable | completed: +3.5%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -3.9%, p95_ms: -2.5%, p99_ms: +1.6%, requests_per_second: +2.3%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +6.7%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -6.0%, p95_ms: -9.5%, p99_ms: -17.4%, requests_per_second: +6.5%, rss_bytes: +0.5% |
| cache_hit | stable | completed: +7.2%, cpu_percent: -0.7%, duration_seconds: -0.0%, p50_ms: -6.8%, p95_ms: -9.0%, p99_ms: -2.8%, requests_per_second: +7.3%, rss_bytes: +0.5% |
| cache_hit | stable | completed: +7.9%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: -7.5%, p95_ms: -7.0%, p99_ms: -6.9%, requests_per_second: +7.8%, rss_bytes: +0.5% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -12.4%, duration_seconds: +4.1%, p50_ms: +2.5%, p95_ms: +18.0%, p99_ms: +11.4%, requests_per_second: -3.0%, rss_bytes: +0.5% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +4.7%, duration_seconds: -7.4%, p50_ms: -7.7%, p95_ms: -4.5%, p99_ms: -0.6%, requests_per_second: +7.8%, rss_bytes: +0.5% |
| thread | improvement | completed: +11.3%, cpu_percent: +1.8%, duration_seconds: +0.0%, p50_ms: +4.4%, p95_ms: -17.6%, p99_ms: -28.5%, requests_per_second: +11.1%, rss_bytes: +0.5% |
| thread | stable | completed: +8.0%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -8.8%, p95_ms: -1.0%, p99_ms: -2.0%, requests_per_second: +8.1%, rss_bytes: +0.5% |
| search | improvement | completed: +8.8%, cpu_percent: -1.1%, duration_seconds: +0.0%, p50_ms: -27.2%, p95_ms: +4.5%, p99_ms: -19.2%, requests_per_second: +8.7%, rss_bytes: +0.5% |
| search | confirmed-regression | completed: +8.1%, cpu_percent: -1.7%, duration_seconds: +0.2%, p50_ms: +26.0%, p95_ms: -21.5%, p99_ms: -20.4%, requests_per_second: +7.9%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +8.2%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +3.3%, p95_ms: -0.8%, p99_ms: -5.7%, requests_per_second: +8.2%, rss_bytes: +0.4% |
| cache_hit | improvement | completed: +29.6%, cpu_percent: +15.7%, duration_seconds: -0.1%, p50_ms: -13.5%, p95_ms: -49.4%, p99_ms: -48.7%, requests_per_second: +30.0%, rss_bytes: +0.4% |
| cache_miss | improvement | completed: +8.8%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: -7.5%, p95_ms: -18.3%, p99_ms: -10.8%, requests_per_second: +8.8%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +8.7%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: -10.6%, p95_ms: -21.8%, p99_ms: -4.9%, requests_per_second: +7.3%, rss_bytes: +0.6% |
| cache_miss | improvement | completed: +16.9%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: -15.2%, p95_ms: -17.9%, p99_ms: -12.9%, requests_per_second: +16.8%, rss_bytes: +0.5% |
| health_live | stable | completed: +2.2%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: -1.1%, p99_ms: +10.8%, requests_per_second: +0.1%, rss_bytes: +0.5% |
| health_live | stable | completed: -2.2%, cpu_percent: +0.6%, duration_seconds: -4.7%, p50_ms: -2.8%, p95_ms: -3.8%, p99_ms: -1.4%, requests_per_second: +2.5%, rss_bytes: +0.5% |
| health_live | stable | completed: +5.0%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -3.4%, p95_ms: +2.1%, p99_ms: +4.6%, requests_per_second: +4.9%, rss_bytes: +0.5% |
| health_live | stable | completed: +7.7%, cpu_percent: -1.1%, duration_seconds: +0.0%, p50_ms: -5.4%, p95_ms: -9.9%, p99_ms: -7.1%, requests_per_second: +7.6%, rss_bytes: +0.4% |
| home | improvement | completed: +24.2%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -20.4%, p95_ms: -22.4%, p99_ms: -9.7%, requests_per_second: +24.2%, rss_bytes: +0.5% |
| home | improvement | completed: +26.1%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: -19.3%, p95_ms: -18.5%, p99_ms: -21.9%, requests_per_second: +24.9%, rss_bytes: +0.5% |
| home | improvement | completed: +29.2%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -17.6%, p95_ms: -18.8%, p99_ms: -16.4%, requests_per_second: +27.5%, rss_bytes: +0.4% |
| categories | improvement | completed: +3.8%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -2.1%, p95_ms: -7.5%, p99_ms: -19.0%, requests_per_second: +3.8%, rss_bytes: +0.4% |
| categories | stable | completed: +3.4%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -4.3%, p95_ms: -8.4%, p99_ms: -14.8%, requests_per_second: +4.9%, rss_bytes: +0.4% |
| categories | stable | completed: +5.9%, cpu_percent: -0.6%, duration_seconds: -0.1%, p50_ms: -7.1%, p95_ms: -13.3%, p99_ms: -6.5%, requests_per_second: +7.8%, rss_bytes: +0.4% |
| category | stable | completed: +2.2%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -2.3%, p95_ms: -1.7%, p99_ms: +12.4%, requests_per_second: +1.1%, rss_bytes: +0.5% |
| category | improvement | completed: +8.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -3.5%, p95_ms: -20.8%, p99_ms: -21.9%, requests_per_second: +7.8%, rss_bytes: +0.5% |
| category | stable | completed: +6.9%, cpu_percent: +0.4%, duration_seconds: +0.3%, p50_ms: -5.4%, p95_ms: -7.8%, p99_ms: +5.3%, requests_per_second: +6.9%, rss_bytes: +0.5% |
| thread | stable | completed: +2.3%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -0.3%, p95_ms: -1.4%, p99_ms: -1.4%, requests_per_second: +0.6%, rss_bytes: +0.5% |
| thread | stable | completed: +3.9%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: +1.4%, p95_ms: -0.7%, p99_ms: -4.7%, requests_per_second: +3.8%, rss_bytes: +0.5% |
| thread | stable | completed: +3.9%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -1.3%, p95_ms: -11.0%, p99_ms: +0.4%, requests_per_second: +3.9%, rss_bytes: +0.5% |
| thread | improvement | completed: +8.2%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -5.8%, p95_ms: -17.6%, p99_ms: -4.9%, requests_per_second: +8.3%, rss_bytes: +0.5% |
| search | improvement | completed: +23.2%, cpu_percent: -5.0%, duration_seconds: -0.1%, p50_ms: -19.3%, p95_ms: -21.9%, p99_ms: -27.3%, requests_per_second: +23.3%, rss_bytes: +0.5% |
| search | improvement | completed: +24.9%, cpu_percent: -1.4%, duration_seconds: +0.0%, p50_ms: -16.8%, p95_ms: -11.9%, p99_ms: -15.2%, requests_per_second: +24.8%, rss_bytes: +0.5% |
| search | improvement | completed: +12.6%, cpu_percent: -3.5%, duration_seconds: +0.1%, p50_ms: -19.2%, p95_ms: -18.3%, p99_ms: -15.6%, requests_per_second: +12.7%, rss_bytes: +0.5% |
| search | improvement | completed: +30.9%, cpu_percent: -3.0%, duration_seconds: +0.1%, p50_ms: +10.2%, p95_ms: -15.0%, p99_ms: -16.6%, requests_per_second: +31.0%, rss_bytes: +0.5% |
| cache_hit | stable | completed: +2.3%, cpu_percent: -18.9%, duration_seconds: -0.0%, p50_ms: -3.2%, p95_ms: -8.0%, p99_ms: -9.1%, requests_per_second: +2.3%, rss_bytes: +0.5% |
| cache_hit | stable | completed: +3.4%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -8.9%, p95_ms: -17.5%, p99_ms: -25.9%, requests_per_second: +3.4%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +6.7%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -4.7%, p95_ms: -10.7%, p99_ms: -16.4%, requests_per_second: +6.7%, rss_bytes: +0.5% |
| cache_hit | stable | completed: +9.5%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -9.0%, p95_ms: -14.3%, p99_ms: -4.6%, requests_per_second: +9.5%, rss_bytes: +0.5% |
| thread | improvement | completed: +13.4%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -27.1%, p95_ms: -18.2%, p99_ms: -22.8%, requests_per_second: +13.1%, rss_bytes: +0.5% |
| thread | stable | completed: +8.9%, cpu_percent: -1.3%, duration_seconds: +0.1%, p50_ms: -12.1%, p95_ms: -19.5%, p99_ms: -15.7%, requests_per_second: +9.3%, rss_bytes: +0.4% |
| search | improvement | completed: +17.0%, cpu_percent: -5.0%, duration_seconds: -0.2%, p50_ms: +2.3%, p95_ms: -3.1%, p99_ms: -17.7%, requests_per_second: +17.6%, rss_bytes: +0.4% |
| search | stable | completed: +10.7%, cpu_percent: -2.8%, duration_seconds: +0.1%, p50_ms: -15.5%, p95_ms: -8.9%, p99_ms: -5.3%, requests_per_second: +11.0%, rss_bytes: +0.4% |
| cache_hit | improvement | completed: +11.8%, cpu_percent: -2.3%, duration_seconds: +0.1%, p50_ms: -37.9%, p95_ms: -14.3%, p99_ms: -7.9%, requests_per_second: +11.9%, rss_bytes: +0.4% |
| cache_hit | improvement | completed: +11.4%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -11.0%, p95_ms: -16.4%, p99_ms: -12.8%, requests_per_second: +11.5%, rss_bytes: +0.4% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -12.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -12.7% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -17.9% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -33.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -7.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -12.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -25.0% |
| sql-plan-readers | improvement | sql_execution_ms: -14.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -7.1% |
| sql-plan-readers | improvement | sql_execution_ms: -12.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -50.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -22.4% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -11.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -5.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -5.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -12.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -16.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -16.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.8% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -13.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.6% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +58.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +22.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.6% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -8.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +37.4% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +19.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -12.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.0% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -8.8%, messages_per_second: +9.6%, p50_ms: -8.2%, p95_ms: -8.1%, p99_ms: -7.5% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -9.9%, messages_per_second: +11.0%, p50_ms: -9.9%, p95_ms: -4.8%, p99_ms: -7.1% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.6%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -1.9%, p95_ms: -3.3%, p99_ms: +1.6%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +3.8%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -3.9%, p95_ms: +0.3%, p99_ms: +15.5%, requests_per_second: +2.5%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +3.7%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: -1.6%, p95_ms: -9.0%, p99_ms: -2.9%, requests_per_second: +3.7%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +5.9%, cpu_percent: -0.9%, duration_seconds: +5.0%, p50_ms: -3.8%, p95_ms: -1.0%, p99_ms: +13.0%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -4.3%, cpu_percent: +0.3%, duration_seconds: -4.7%, p50_ms: -0.5%, p95_ms: -3.2%, p99_ms: -7.2%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -1.5%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +2.6%, p95_ms: +18.9%, p99_ms: +23.1%, requests_per_second: -1.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +0.2%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +3.7%, p95_ms: -11.7%, p99_ms: +0.8%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.3%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -2.5%, p95_ms: -6.7%, p99_ms: +5.9%, requests_per_second: +3.3%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +10.2%, cpu_percent: +1.0%, duration_seconds: -0.2%, p50_ms: -13.1%, p95_ms: -21.6%, p99_ms: -4.4%, requests_per_second: +9.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.3%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -4.2%, p95_ms: +6.0%, p99_ms: +4.6%, requests_per_second: -1.6%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.1%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +1.7%, p95_ms: -1.3%, p99_ms: -5.5%, requests_per_second: +0.0%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -1.5%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +0.7%, p95_ms: +0.7%, p99_ms: +29.5%, requests_per_second: -0.5%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -2.0%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: +0.7%, p95_ms: +2.7%, p99_ms: +16.5%, requests_per_second: -1.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -2.8%, p95_ms: -2.6%, p99_ms: +6.1%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +2.0%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -10.4%, p95_ms: -9.4%, p99_ms: +6.0%, requests_per_second: +1.4%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.0%, cpu_percent: -0.4%, duration_seconds: +0.2%, p50_ms: -0.0%, p95_ms: -4.7%, p99_ms: +2.9%, requests_per_second: +0.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.1%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +0.0%, p95_ms: -0.7%, p99_ms: -2.7%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +1.7%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: +4.2%, p95_ms: +17.7%, p99_ms: +35.2%, requests_per_second: +1.7%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.2%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +4.8%, p95_ms: +6.4%, p99_ms: +28.0%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.2%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +0.7%, p95_ms: +1.2%, p99_ms: +3.2%, requests_per_second: -0.1%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.8%, cpu_percent: +0.8%, duration_seconds: -0.0%, p50_ms: +3.5%, p95_ms: +2.3%, p99_ms: -13.0%, requests_per_second: -2.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.9%, cpu_percent: +1.7%, duration_seconds: -0.0%, p50_ms: +2.3%, p95_ms: +1.6%, p99_ms: -6.1%, requests_per_second: +2.9%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.4%, cpu_percent: +0.7%, duration_seconds: +0.1%, p50_ms: -4.4%, p95_ms: +1.2%, p99_ms: +5.0%, requests_per_second: +0.5%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.5%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: +3.5%, p95_ms: +5.2%, p99_ms: +4.8%, requests_per_second: -0.5%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.5%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: +1.9%, p95_ms: -1.9%, p99_ms: -14.8%, requests_per_second: -0.3%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -2.4%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +1.7%, p95_ms: +2.0%, p99_ms: +19.1%, requests_per_second: -1.0%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.8%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: -0.5%, p99_ms: +2.5%, requests_per_second: -0.8%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.1%, cpu_percent: +0.7%, duration_seconds: -0.1%, p50_ms: -0.5%, p95_ms: +2.6%, p99_ms: +3.3%, requests_per_second: -0.0%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.5%, cpu_percent: -0.4%, duration_seconds: -0.2%, p50_ms: -14.3%, p95_ms: -0.4%, p99_ms: -16.2%, requests_per_second: -0.5%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.3%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: -0.8%, p95_ms: +4.0%, p99_ms: +5.1%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +8.4%, cpu_percent: -3.5%, duration_seconds: -0.3%, p50_ms: +41.4%, p95_ms: -6.1%, p99_ms: -0.3%, requests_per_second: +8.9%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +5.9%, cpu_percent: -1.6%, duration_seconds: -0.0%, p50_ms: -9.9%, p95_ms: +7.5%, p99_ms: +3.8%, requests_per_second: +5.9%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -17.5%, cpu_percent: -31.2%, duration_seconds: +0.2%, p50_ms: +1.2%, p95_ms: -17.4%, p99_ms: +10.9%, requests_per_second: -17.5%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.6%, cpu_percent: -0.8%, duration_seconds: +0.0%, p50_ms: -7.5%, p95_ms: +13.4%, p99_ms: +5.3%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +46.7%, cpu_percent: +94.2%, duration_seconds: +0.1%, p50_ms: -28.7%, p95_ms: +10.5%, p99_ms: +27.6%, requests_per_second: +46.7%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +46.1%, cpu_percent: +92.5%, duration_seconds: +0.1%, p50_ms: -32.4%, p95_ms: -9.3%, p99_ms: -27.1%, requests_per_second: +46.1%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | possible-regression | completed: +27.8%, cpu_percent: +80.5%, duration_seconds: +0.4%, p50_ms: -50.6%, p95_ms: +13.0%, p99_ms: +15.1%, requests_per_second: +27.1%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +27.5%, cpu_percent: +81.8%, duration_seconds: +0.4%, p50_ms: -20.7%, p95_ms: -24.0%, p99_ms: -12.9%, requests_per_second: +27.0%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: +21.5%, cpu_percent: +51.6%, duration_seconds: +0.0%, p50_ms: -31.4%, p95_ms: +37.7%, p99_ms: +27.6%, requests_per_second: +21.5%, rss_bytes: +64.3% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +42.9%, cpu_percent: +93.3%, duration_seconds: +0.0%, p50_ms: -30.3%, p95_ms: -11.1%, p99_ms: -19.3%, requests_per_second: +43.0%, rss_bytes: +64.3% |
| thread | workers=4 | 2 | 50 | improvement | completed: +45.7%, cpu_percent: +92.9%, duration_seconds: +0.0%, p50_ms: -41.7%, p95_ms: +3.4%, p99_ms: -16.5%, requests_per_second: +45.4%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | improvement | completed: +44.6%, cpu_percent: +91.9%, duration_seconds: +0.1%, p50_ms: -33.3%, p95_ms: -6.8%, p99_ms: -25.8%, requests_per_second: +44.5%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | improvement | completed: +37.9%, cpu_percent: +72.9%, duration_seconds: +0.0%, p50_ms: -27.0%, p95_ms: +4.9%, p99_ms: +9.3%, requests_per_second: +37.8%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +35.7%, cpu_percent: +77.8%, duration_seconds: +0.3%, p50_ms: -31.0%, p95_ms: -22.3%, p99_ms: -13.7%, requests_per_second: +35.1%, rss_bytes: +64.0% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: +1.1%, cpu_percent: +4.3%, duration_seconds: +0.2%, p50_ms: -30.8%, p95_ms: +14.3%, p99_ms: +38.0%, requests_per_second: +1.0%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +45.3%, cpu_percent: +90.4%, duration_seconds: +0.1%, p50_ms: -35.2%, p95_ms: -1.7%, p99_ms: -17.8%, requests_per_second: +45.2%, rss_bytes: +64.1% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38770090588)
