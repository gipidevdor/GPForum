# GPForum continuous performance evidence

Commit: `12ab8f01fa67bb9fd7f4a584c1fabe5020ec0b01` · mode: **main** · status: **failed**
Run: 39018912017 / attempt 1 · 2026-10-17T08:51:32.472157+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V45 96-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. ae4d51139cb8acb619e86575f1a5ec1372ecb60a

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 761.875 | 1.296 | 1.366 | 1.421 | 100.087 / 387.672 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1492.591 | 6.603 | 8.478 | 10.715 | 199.645 / 388.008 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1511.081 | 32.696 | 33.781 | 60.580 | 199.644 / 389.934 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 2663.187 | 0.370 | 0.406 | 0.429 | 99.602 / 387.488 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 5046.558 | 1.935 | 2.455 | 4.138 | 198.703 / 387.504 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 5254.747 | 9.376 | 9.807 | 13.499 | 199.655 / 388.473 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 5299.679 | 18.661 | 19.360 | 24.943 | 198.677 / 389.855 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 304.711 | 3.090 | 3.497 | 3.582 | 77.154 / 390.426 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 556.835 | 17.699 | 27.343 | 35.257 | 152.243 / 391.098 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 545.449 | 86.856 | 99.350 | 168.287 | 151.349 / 393.539 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1960.554 | 0.501 | 0.547 | 0.590 | 99.603 / 393.539 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3773.529 | 2.614 | 3.252 | 4.486 | 199.184 / 393.539 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3921.733 | 12.577 | 13.031 | 20.898 | 199.657 / 393.539 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1872.706 | 0.524 | 0.568 | 0.599 | 99.615 / 393.617 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3673.084 | 2.675 | 3.370 | 4.633 | 199.178 / 393.695 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3811.248 | 12.942 | 13.900 | 20.734 | 199.629 / 393.695 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1901.654 | 0.522 | 0.560 | 0.589 | 99.644 / 393.820 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3618.535 | 2.701 | 3.911 | 4.730 | 199.194 / 393.820 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3718.157 | 13.112 | 13.992 | 22.469 | 200.140 / 393.820 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3733.521 | 26.204 | 28.380 | 45.661 | 199.628 / 396.891 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 192.410 | 5.103 | 5.435 | 5.584 | 52.646 / 397.422 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 348.343 | 27.648 | 37.589 | 53.027 | 107.633 / 397.246 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 335.119 | 142.628 | 207.223 | 279.990 | 107.498 / 397.246 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 301.491 | 318.226 | 524.660 | 592.825 | 104.988 / 397.422 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1906.456 | 0.510 | 0.591 | 0.627 | 99.623 / 397.422 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3712.829 | 2.729 | 3.400 | 5.660 | 199.659 / 397.422 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3788.675 | 14.229 | 17.486 | 29.651 | 200.154 / 397.422 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3816.668 | 26.571 | 28.632 | 40.425 | 200.595 / 397.422 | improvement |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 2586.251 | 3.675 | 5.577 | 5.931 | 22.544 / 397.422 | improvement |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1844.510 | 5.229 | 8.423 | 8.847 | 28.943 / 397.742 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4471.027 | 10.483 | 22.156 | 27.347 | 297.965 / 645.492 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 5332.440 | 20.220 | 32.783 | 42.428 | 385.680 / 649.957 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 462.436 | 106.308 | 255.675 | 338.137 | 199.186 / 651.137 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 461.620 | 158.273 | 506.655 | 643.392 | 212.028 / 653.328 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4617.628 | 7.169 | 16.707 | 23.336 | 301.928 / 653.379 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 4631.441 | 22.634 | 36.296 | 37.376 | 301.235 / 653.379 | confirmed-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.289 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.260 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.246 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.278 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.065 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.102 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.161 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.069 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.064 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.002 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.250 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.293 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.146 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.198 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.061 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.037 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.026 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.199 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.247 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.369 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.300 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.239 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.270 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.148 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.189 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.590 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.808 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.124 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.092 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.120 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.037 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.011 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.043 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.058 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.039 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.043 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 1460.701 | 62.536 | 79.901 | 84.277 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 2336.067 | 83.694 | 94.432 | 94.613 | — / — | improvement |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +11.5%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: -10.5%, p95_ms: -12.2%, p99_ms: -30.9%, requests_per_second: +11.7%, rss_bytes: +1.5% |
| cache_miss | improvement | completed: +15.1%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -15.0%, p95_ms: -20.7%, p99_ms: -28.0%, requests_per_second: +15.1%, rss_bytes: +1.5% |
| cache_miss | improvement | completed: +17.4%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: -11.1%, p95_ms: -19.6%, p99_ms: -11.7%, requests_per_second: +17.3%, rss_bytes: +1.4% |
| health_live | improvement | completed: +15.8%, cpu_percent: +0.1%, duration_seconds: +5.0%, p50_ms: -8.0%, p95_ms: -27.2%, p99_ms: -55.2%, requests_per_second: +12.9%, rss_bytes: +1.4% |
| health_live | stable | completed: +5.5%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: -6.3%, p95_ms: -2.0%, p99_ms: +15.9%, requests_per_second: +7.7%, rss_bytes: +1.4% |
| health_live | improvement | completed: +8.6%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -7.8%, p95_ms: -9.9%, p99_ms: -16.8%, requests_per_second: +8.6%, rss_bytes: +1.3% |
| health_live | improvement | completed: +11.8%, cpu_percent: -0.9%, duration_seconds: +0.1%, p50_ms: -10.0%, p95_ms: -16.3%, p99_ms: -31.6%, requests_per_second: +11.7%, rss_bytes: +1.4% |
| home | improvement | completed: +9.9%, cpu_percent: -1.8%, duration_seconds: +0.0%, p50_ms: -13.1%, p95_ms: -29.9%, p99_ms: -45.5%, requests_per_second: +9.8%, rss_bytes: +1.3% |
| home | improvement | completed: +18.5%, cpu_percent: -2.1%, duration_seconds: -0.0%, p50_ms: -20.7%, p95_ms: -23.1%, p99_ms: -33.7%, requests_per_second: +18.8%, rss_bytes: +1.3% |
| home | improvement | completed: +19.2%, cpu_percent: -4.2%, duration_seconds: +0.1%, p50_ms: -15.3%, p95_ms: -25.6%, p99_ms: -6.3%, requests_per_second: +19.3%, rss_bytes: +1.3% |
| categories | stable | completed: +8.0%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -7.2%, p95_ms: -6.5%, p99_ms: -10.5%, requests_per_second: +7.0%, rss_bytes: +1.3% |
| categories | improvement | completed: +10.9%, cpu_percent: +0.1%, duration_seconds: +4.9%, p50_ms: -8.0%, p95_ms: -14.4%, p99_ms: -18.7%, requests_per_second: +8.5%, rss_bytes: +1.3% |
| categories | improvement | completed: +9.7%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -8.4%, p95_ms: -12.2%, p99_ms: -13.5%, requests_per_second: +9.8%, rss_bytes: +1.3% |
| category | improvement | completed: +3.0%, cpu_percent: +0.2%, duration_seconds: -4.7%, p50_ms: -5.4%, p95_ms: -8.7%, p99_ms: -44.7%, requests_per_second: +8.1%, rss_bytes: +1.3% |
| category | improvement | completed: +14.8%, cpu_percent: +0.1%, duration_seconds: +4.9%, p50_ms: -12.0%, p95_ms: -15.3%, p99_ms: -22.4%, requests_per_second: +9.5%, rss_bytes: +1.4% |
| category | improvement | completed: +12.7%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -11.0%, p95_ms: -15.3%, p99_ms: -15.9%, requests_per_second: +12.7%, rss_bytes: +1.4% |
| thread | improvement | completed: +10.7%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -5.9%, p95_ms: -9.4%, p99_ms: -55.1%, requests_per_second: +9.3%, rss_bytes: +1.4% |
| thread | stable | completed: +6.9%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -9.2%, p95_ms: -1.3%, p99_ms: -7.7%, requests_per_second: +7.0%, rss_bytes: +1.4% |
| thread | stable | completed: +10.8%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -8.6%, p95_ms: -8.7%, p99_ms: -7.7%, requests_per_second: +8.7%, rss_bytes: +1.4% |
| thread | improvement | completed: +8.2%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: -7.7%, p95_ms: -21.5%, p99_ms: -4.2%, requests_per_second: +8.1%, rss_bytes: +1.3% |
| search | improvement | completed: +22.7%, cpu_percent: -5.5%, duration_seconds: +0.0%, p50_ms: -13.8%, p95_ms: -36.3%, p99_ms: -47.5%, requests_per_second: +21.5%, rss_bytes: +1.3% |
| search | improvement | completed: +26.2%, cpu_percent: -8.3%, duration_seconds: +0.1%, p50_ms: -25.1%, p95_ms: -25.1%, p99_ms: -22.1%, requests_per_second: +32.3%, rss_bytes: +1.3% |
| search | improvement | completed: +29.5%, cpu_percent: -7.9%, duration_seconds: -0.0%, p50_ms: -22.6%, p95_ms: -31.2%, p99_ms: -29.1%, requests_per_second: +29.6%, rss_bytes: +1.3% |
| search | stable | completed: +23.3%, cpu_percent: -5.2%, duration_seconds: -0.0%, p50_ms: -16.7%, p95_ms: -29.2%, p99_ms: -32.0%, requests_per_second: +23.4%, rss_bytes: +1.2% |
| cache_hit | stable | completed: +10.0%, cpu_percent: -0.4%, duration_seconds: +4.9%, p50_ms: -3.6%, p95_ms: -2.3%, p99_ms: -20.5%, requests_per_second: +6.1%, rss_bytes: +1.2% |
| cache_hit | improvement | completed: +4.9%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -6.4%, p95_ms: -15.6%, p99_ms: -1.7%, requests_per_second: +6.4%, rss_bytes: +1.2% |
| cache_hit | stable | completed: +5.9%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +3.6%, p95_ms: +15.9%, p99_ms: +18.7%, requests_per_second: +5.8%, rss_bytes: +1.2% |
| cache_hit | improvement | completed: +14.2%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: -9.5%, p95_ms: -26.8%, p99_ms: -23.9%, requests_per_second: +14.4%, rss_bytes: +1.2% |
| health_live | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -15.4%, duration_seconds: -11.4%, p50_ms: -2.1%, p95_ms: -6.3%, p99_ms: -12.7%, requests_per_second: +13.2%, rss_bytes: +1.2% |
| thread | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +8.4%, duration_seconds: -12.9%, p50_ms: -9.7%, p95_ms: -6.2%, p99_ms: -11.3%, requests_per_second: +13.6%, rss_bytes: +1.2% |
| thread | possible-regression | completed: -5.5%, cpu_percent: -21.9%, duration_seconds: -0.1%, p50_ms: -6.8%, p95_ms: +22.7%, p99_ms: +7.0%, requests_per_second: -5.4%, rss_bytes: +1.4% |
| thread | stable | completed: +6.9%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: +1.8%, p95_ms: +0.2%, p99_ms: +5.6%, requests_per_second: +7.2%, rss_bytes: +1.3% |
| search | improvement | completed: +30.2%, cpu_percent: +21.3%, duration_seconds: -0.2%, p50_ms: -36.3%, p95_ms: -3.8%, p99_ms: +0.6%, requests_per_second: +30.3%, rss_bytes: +1.3% |
| search | improvement | completed: +16.9%, cpu_percent: -5.7%, duration_seconds: -0.2%, p50_ms: -16.6%, p95_ms: -11.1%, p99_ms: +2.3%, requests_per_second: +17.1%, rss_bytes: +1.3% |
| cache_hit | stable | completed: +13.3%, cpu_percent: +1.0%, duration_seconds: +4.8%, p50_ms: -27.3%, p95_ms: -9.6%, p99_ms: +16.6%, requests_per_second: +8.0%, rss_bytes: +1.3% |
| cache_hit | confirmed-regression | completed: -14.7%, cpu_percent: -22.3%, duration_seconds: -4.7%, p50_ms: +58.7%, p95_ms: -2.1%, p99_ms: -13.1%, requests_per_second: -10.5%, rss_bytes: +1.2% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -11.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -8.2% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -10.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -16.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -9.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -18.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -15.0% |
| sql-plan-readers | improvement | sql_execution_ms: -20.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -60.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -9.7% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -10.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -7.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.3% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -10.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -9.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -35.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.1% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +35.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -8.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.9% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -19.1% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -15.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.2% |
| sql-plan-functions | improvement | nested_statements: +0.0%, sql_execution_ms: -16.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -28.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +9.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -4.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +30.3% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -5.4%, messages_per_second: +5.7%, p50_ms: -9.7%, p95_ms: -15.7%, p99_ms: -27.7% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -10.0%, messages_per_second: +11.1%, p50_ms: -10.7%, p95_ms: -10.1%, p99_ms: -10.7% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +18.0%, cpu_percent: +48.9%, duration_seconds: -0.1%, p50_ms: -20.1%, p95_ms: +58.3%, p99_ms: +21.7%, requests_per_second: +20.2%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +42.9%, cpu_percent: +93.2%, duration_seconds: +0.1%, p50_ms: -22.8%, p95_ms: +15.5%, p99_ms: -7.1%, requests_per_second: +42.8%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +38.2%, cpu_percent: +85.3%, duration_seconds: +0.1%, p50_ms: -25.5%, p95_ms: +23.4%, p99_ms: +20.8%, requests_per_second: +38.0%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +53.1%, cpu_percent: +102.0%, duration_seconds: -0.1%, p50_ms: -50.3%, p95_ms: -3.4%, p99_ms: +8.5%, requests_per_second: +53.1%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +27.7%, cpu_percent: +50.8%, duration_seconds: +4.9%, p50_ms: -49.6%, p95_ms: -4.5%, p99_ms: -21.3%, requests_per_second: +21.9%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +21.4%, cpu_percent: +50.2%, duration_seconds: +0.0%, p50_ms: -14.8%, p95_ms: +26.8%, p99_ms: -7.5%, requests_per_second: +21.3%, rss_bytes: +64.4% |

## Suite status and skipped tests

- connections_workflow: **failed** — GitHub Actions step outcome: failure
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
- Configured wrk latency budget: 3 seconds.
- Shared runner and load generator share the host; values are comparative evidence, not production capacity.
- wrk uses closed-loop fixed connections and corrected latency histograms; in-flight concurrency is not measured.
- RSS is end-of-sample manager+workers residency, not peak; PostgreSQL and generator resources are separate.
- Cache hits/misses verified by probes; warmed worker-local SSR cache; cache miss uses harness-only expiry policy.
- Only anonymous GETs; migrations, seed and rate-limit accounting write only the dedicated disposable database.

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/performance-data/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/39018912017)
