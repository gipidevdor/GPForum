# GPForum continuous performance evidence

Commit: `0876e8f620d4cd96bc1cd68c1cf8d8de893c7fff` · mode: **main** · status: **ok**
Run: 38980538205 / attempt 1 · 2026-10-16T23:17:01.208729+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V45 96-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 1ef4ac244ade35a6ebc1a78d2744214066f1b7fd

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 709.317 | 1.402 | 1.489 | 1.589 | 99.641 / 377.848 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1382.484 | 6.997 | 8.969 | 13.851 | 199.612 / 378.125 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1376.558 | 35.479 | 39.313 | 65.459 | 200.116 / 380.129 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 2624.007 | 0.375 | 0.414 | 0.438 | 99.604 / 377.945 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 4992.769 | 1.943 | 2.523 | 3.441 | 199.177 / 377.945 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 5249.137 | 9.626 | 10.278 | 13.771 | 200.135 / 378.832 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 5142.515 | 19.122 | 20.470 | 28.307 | 200.565 / 380.207 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 298.995 | 3.180 | 3.532 | 4.042 | 77.295 / 380.543 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 542.014 | 18.714 | 23.092 | 34.826 | 152.838 / 381.449 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 503.329 | 94.920 | 123.315 | 168.831 | 155.264 / 383.836 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1877.821 | 0.524 | 0.575 | 0.609 | 99.590 / 383.836 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3567.128 | 2.839 | 3.904 | 4.664 | 199.168 / 383.836 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3717.966 | 14.521 | 15.539 | 23.649 | 199.607 / 383.836 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1844.420 | 0.539 | 0.570 | 0.703 | 99.624 / 383.914 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3519.992 | 2.961 | 3.541 | 5.131 | 200.089 / 383.934 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3531.993 | 14.135 | 15.844 | 22.662 | 199.365 / 383.934 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1887.129 | 0.518 | 0.570 | 0.592 | 99.613 / 384.055 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3605.540 | 3.035 | 3.436 | 4.572 | 199.155 / 384.059 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3608.049 | 13.409 | 18.324 | 26.367 | 199.934 / 384.117 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3664.171 | 26.694 | 29.720 | 43.584 | 200.002 / 387.234 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 194.406 | 5.024 | 5.542 | 6.905 | 54.774 / 387.754 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 331.637 | 28.798 | 43.552 | 53.723 | 112.440 / 387.832 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 335.113 | 143.885 | 206.795 | 295.804 | 110.905 / 387.832 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 296.862 | 298.364 | 497.157 | 566.385 | 109.401 / 387.832 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1920.292 | 0.511 | 0.563 | 0.612 | 99.607 / 387.832 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3680.980 | 2.838 | 3.423 | 4.654 | 199.183 / 387.832 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3781.545 | 13.534 | 15.541 | 22.468 | 199.612 / 387.832 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3732.757 | 26.079 | 29.444 | 41.166 | 199.605 / 387.832 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 2428.594 | 3.713 | 5.450 | 5.960 | 20.666 / 387.832 | stable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1526.417 | 6.158 | 8.635 | 10.700 | 34.321 / 388.172 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4522.371 | 11.434 | 17.598 | 20.770 | 295.766 / 630.008 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 5408.170 | 14.310 | 29.812 | 36.697 | 387.155 / 635.008 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 440.053 | 129.419 | 255.870 | 350.654 | 196.884 / 636.281 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 448.046 | 156.376 | 431.474 | 507.068 | 213.582 / 637.891 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4548.744 | 14.753 | 18.150 | 21.476 | 293.806 / 637.891 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 5584.914 | 17.906 | 29.275 | 34.450 | 389.234 / 638.031 | improvement |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.327 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.260 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.254 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.279 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.067 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.106 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.232 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.078 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.064 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.267 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.296 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.145 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.200 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.073 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.037 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.264 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.258 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.229 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.309 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.264 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.311 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.149 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.275 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.614 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.031 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.121 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.099 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.119 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.038 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.010 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.068 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.041 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 1274.160 | 77.113 | 90.456 | 119.547 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 2103.383 | 92.413 | 160.738 | 161.539 | — / — | possible-regression |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | stable | completed: +1.0%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +0.3%, p95_ms: +0.4%, p99_ms: -19.5%, requests_per_second: +1.0%, rss_bytes: -0.0% |
| cache_miss | improvement | completed: +3.2%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -14.8%, p95_ms: -6.6%, p99_ms: +6.5%, requests_per_second: +0.1%, rss_bytes: -0.1% |
| cache_miss | stable | completed: +0.1%, cpu_percent: -0.6%, duration_seconds: +0.1%, p50_ms: -0.5%, p95_ms: -22.5%, p99_ms: -7.0%, requests_per_second: +0.1%, rss_bytes: -0.1% |
| health_live | stable | completed: +2.5%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -0.8%, p95_ms: -0.5%, p99_ms: -0.5%, requests_per_second: +2.5%, rss_bytes: +0.1% |
| health_live | stable | completed: +0.1%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -3.6%, p95_ms: +1.7%, p99_ms: -1.3%, requests_per_second: +0.2%, rss_bytes: +0.1% |
| health_live | stable | completed: +3.3%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: +0.2%, p95_ms: -13.9%, p99_ms: -2.2%, requests_per_second: +3.3%, rss_bytes: +0.1% |
| health_live | improvement | completed: +9.3%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -8.8%, p95_ms: -15.0%, p99_ms: +5.9%, requests_per_second: +9.4%, rss_bytes: +0.1% |
| home | stable | completed: +21.9%, cpu_percent: -5.7%, duration_seconds: +0.0%, p50_ms: -14.1%, p95_ms: -37.8%, p99_ms: -34.6%, requests_per_second: +21.9%, rss_bytes: +0.1% |
| home | improvement | completed: +70.6%, cpu_percent: -5.7%, duration_seconds: -0.0%, p50_ms: -37.5%, p95_ms: -46.3%, p99_ms: -36.6%, requests_per_second: +70.5%, rss_bytes: +0.1% |
| home | improvement | completed: +46.8%, cpu_percent: -4.2%, duration_seconds: +0.0%, p50_ms: -30.1%, p95_ms: -27.2%, p99_ms: -26.6%, requests_per_second: +40.0%, rss_bytes: +0.1% |
| categories | stable | completed: +3.6%, cpu_percent: +0.1%, duration_seconds: +5.0%, p50_ms: +2.1%, p95_ms: +2.3%, p99_ms: +2.7%, requests_per_second: -1.3%, rss_bytes: +0.1% |
| categories | stable | completed: -2.2%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +0.5%, p95_ms: -5.9%, p99_ms: -0.8%, requests_per_second: +2.0%, rss_bytes: +0.1% |
| categories | stable | completed: +8.9%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -0.2%, p95_ms: -0.9%, p99_ms: +6.3%, requests_per_second: +8.9%, rss_bytes: +0.1% |
| category | stable | completed: +1.4%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -0.7%, p95_ms: -5.2%, p99_ms: -8.1%, requests_per_second: +1.4%, rss_bytes: +0.1% |
| category | stable | completed: +4.6%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +1.6%, p95_ms: -8.0%, p99_ms: -4.1%, requests_per_second: +4.6%, rss_bytes: +0.1% |
| category | improvement | completed: +13.9%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -8.3%, p95_ms: -6.5%, p99_ms: -11.6%, requests_per_second: +10.7%, rss_bytes: +0.1% |
| thread | improvement | completed: +5.0%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -5.0%, p95_ms: -3.9%, p99_ms: -39.3%, requests_per_second: +5.0%, rss_bytes: +0.1% |
| thread | stable | completed: +9.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +2.8%, p95_ms: -8.2%, p99_ms: -11.3%, requests_per_second: +8.3%, rss_bytes: +0.1% |
| thread | improvement | completed: +17.4%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: +1.7%, p95_ms: -17.5%, p99_ms: -10.1%, requests_per_second: +15.0%, rss_bytes: -0.1% |
| thread | improvement | completed: +18.2%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -5.8%, p95_ms: -17.2%, p99_ms: -11.2%, requests_per_second: +18.3%, rss_bytes: +0.1% |
| search | improvement | completed: +82.6%, cpu_percent: -13.4%, duration_seconds: +0.0%, p50_ms: -45.7%, p95_ms: -47.7%, p99_ms: -43.7%, requests_per_second: +82.7%, rss_bytes: +0.1% |
| search | improvement | completed: +65.3%, cpu_percent: -12.4%, duration_seconds: +0.0%, p50_ms: -43.9%, p95_ms: -44.9%, p99_ms: -54.9%, requests_per_second: +62.3%, rss_bytes: +0.1% |
| search | improvement | completed: +71.2%, cpu_percent: -12.3%, duration_seconds: -0.2%, p50_ms: -27.3%, p95_ms: -49.6%, p99_ms: -41.3%, requests_per_second: +71.4%, rss_bytes: +0.1% |
| search | improvement | completed: +71.0%, cpu_percent: -12.8%, duration_seconds: +0.0%, p50_ms: -40.6%, p95_ms: -43.1%, p99_ms: -40.6%, requests_per_second: +70.9%, rss_bytes: -0.0% |
| cache_hit | stable | completed: +1.9%, cpu_percent: -4.1%, duration_seconds: +0.0%, p50_ms: -5.4%, p95_ms: -5.1%, p99_ms: -18.5%, requests_per_second: +5.0%, rss_bytes: -0.0% |
| cache_hit | stable | completed: +7.7%, cpu_percent: -0.0%, duration_seconds: +4.9%, p50_ms: -0.7%, p95_ms: -6.0%, p99_ms: -11.0%, requests_per_second: +7.7%, rss_bytes: -0.0% |
| cache_hit | improvement | completed: +12.5%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -9.5%, p95_ms: -5.7%, p99_ms: -10.5%, requests_per_second: +12.6%, rss_bytes: -0.0% |
| cache_hit | stable | completed: +1.9%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: -3.3%, p95_ms: -3.5%, p99_ms: -3.1%, requests_per_second: +1.8%, rss_bytes: -0.0% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -16.5%, duration_seconds: +2.5%, p50_ms: +1.3%, p95_ms: -2.7%, p99_ms: +0.4%, requests_per_second: -3.1%, rss_bytes: -0.0% |
| thread | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +12.5%, duration_seconds: +0.0%, p50_ms: -8.0%, p95_ms: -4.8%, p99_ms: -5.3%, requests_per_second: +1.0%, rss_bytes: -0.0% |
| thread | possible-regression | completed: -9.9%, cpu_percent: -23.0%, duration_seconds: -4.6%, p50_ms: +71.8%, p95_ms: -10.2%, p99_ms: -23.6%, requests_per_second: -8.0%, rss_bytes: +0.1% |
| thread | improvement | completed: +16.2%, cpu_percent: +1.6%, duration_seconds: +0.1%, p50_ms: -30.0%, p95_ms: -19.7%, p99_ms: -19.7%, requests_per_second: +16.1%, rss_bytes: +0.0% |
| search | improvement | completed: +60.4%, cpu_percent: +8.4%, duration_seconds: -0.1%, p50_ms: -41.4%, p95_ms: -29.3%, p99_ms: -22.6%, requests_per_second: +61.0%, rss_bytes: +0.1% |
| search | stable | completed: +39.2%, cpu_percent: -7.6%, duration_seconds: -0.2%, p50_ms: -20.3%, p95_ms: -30.4%, p99_ms: -29.0%, requests_per_second: +39.5%, rss_bytes: +0.3% |
| cache_hit | improvement | completed: +32.7%, cpu_percent: +38.6%, duration_seconds: -0.1%, p50_ms: +22.8%, p95_ms: -22.5%, p99_ms: -15.5%, requests_per_second: +29.3%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: +13.9%, cpu_percent: +1.2%, duration_seconds: -0.0%, p50_ms: -13.8%, p95_ms: -13.9%, p99_ms: -24.5%, requests_per_second: +14.0%, rss_bytes: -0.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.7% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | improvement | sql_execution_ms: -20.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -5.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -10.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +39.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -12.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -10.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +18.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.9% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +51.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.9% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +33.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.6% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +28.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -14.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.8% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +2.6%, messages_per_second: -2.5%, p50_ms: +5.8%, p95_ms: +0.3%, p99_ms: -16.7% |
| postgres-dispatch-noop | possible-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +1.6%, messages_per_second: -1.6%, p50_ms: -0.5%, p95_ms: +53.0%, p99_ms: +53.7% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | improvement | completed: +22.9%, cpu_percent: +47.9%, duration_seconds: -0.0%, p50_ms: -14.7%, p95_ms: -4.0%, p99_ms: -21.2%, requests_per_second: +25.3%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +48.2%, cpu_percent: +93.6%, duration_seconds: +0.1%, p50_ms: -46.4%, p95_ms: +0.3%, p99_ms: -15.8%, requests_per_second: +47.6%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | improvement | completed: +31.4%, cpu_percent: +77.5%, duration_seconds: +0.1%, p50_ms: -10.1%, p95_ms: +23.7%, p99_ms: +18.5%, requests_per_second: +31.3%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +51.1%, cpu_percent: +95.2%, duration_seconds: +0.1%, p50_ms: -47.6%, p95_ms: -13.2%, p99_ms: -10.5%, requests_per_second: +50.9%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +23.5%, cpu_percent: +47.2%, duration_seconds: +0.0%, p50_ms: +9.0%, p95_ms: +16.8%, p99_ms: -4.4%, requests_per_second: +20.3%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +49.7%, cpu_percent: +95.0%, duration_seconds: +0.0%, p50_ms: -31.3%, p95_ms: -0.6%, p99_ms: -16.3%, requests_per_second: +49.6%, rss_bytes: +64.5% |

## Suite status and skipped tests

- connections_workflow: **ok** — GitHub Actions step outcome: success
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

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38980538205)
