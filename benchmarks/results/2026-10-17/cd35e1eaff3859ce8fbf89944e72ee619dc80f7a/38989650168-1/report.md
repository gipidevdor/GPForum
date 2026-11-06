# GPForum continuous performance evidence

Commit: `cd35e1eaff3859ce8fbf89944e72ee619dc80f7a` · mode: **main** · status: **ok**
Run: 38989650168 / attempt 1 · 2026-10-17T01:10:08.672853+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 078d740f5c63bbe7ed13faace2636fd0ddf088c3

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 385.431 | 2.583 | 2.656 | 2.787 | 99.508 / 377.973 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 767.577 | 12.766 | 15.533 | 20.618 | 199.899 / 378.266 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 766.215 | 63.554 | 65.859 | 118.016 | 200.409 / 380.250 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1372.612 | 0.721 | 0.778 | 0.901 | 99.060 / 378.156 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2753.567 | 3.607 | 3.758 | 5.256 | 199.474 / 378.156 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2828.714 | 17.479 | 18.453 | 24.955 | 200.438 / 379.023 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2808.843 | 34.883 | 36.452 | 59.045 | 200.922 / 380.426 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 168.353 | 5.838 | 6.098 | 6.265 | 79.105 / 381.070 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 319.057 | 30.252 | 43.210 | 55.688 | 156.679 / 381.633 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 295.176 | 163.414 | 235.382 | 314.961 | 156.109 / 384.035 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1010.851 | 0.993 | 1.038 | 1.067 | 99.984 / 384.062 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2017.186 | 4.904 | 5.309 | 8.643 | 199.470 / 384.062 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2055.544 | 23.701 | 27.159 | 44.236 | 200.439 / 384.062 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1011.833 | 0.978 | 1.040 | 1.092 | 99.560 / 384.102 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1922.292 | 5.056 | 6.239 | 8.013 | 198.977 / 384.102 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2017.052 | 24.410 | 25.492 | 39.434 | 200.400 / 384.102 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 998.472 | 0.986 | 1.047 | 1.157 | 99.562 / 384.184 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1939.435 | 5.082 | 6.337 | 8.648 | 198.987 / 384.227 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1983.900 | 24.723 | 26.845 | 44.037 | 199.930 / 384.227 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1963.399 | 49.955 | 51.605 | 87.191 | 199.943 / 387.359 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 103.849 | 9.567 | 9.864 | 10.018 | 55.743 / 387.961 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 190.989 | 49.973 | 78.189 | 90.663 | 111.919 / 388.047 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 184.200 | 245.653 | 437.729 | 510.147 | 111.798 / 388.047 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 172.496 | 484.143 | 927.811 | 978.068 | 111.306 / 388.047 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 986.890 | 1.012 | 1.051 | 1.092 | 105.628 / 388.047 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2005.297 | 4.919 | 6.699 | 7.777 | 198.923 / 388.047 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2045.625 | 23.911 | 26.098 | 38.163 | 199.935 / 388.047 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2017.070 | 48.219 | 50.070 | 81.576 | 199.937 / 388.047 | confirmed-regression |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1410.500 | 6.578 | 9.949 | 10.375 | 19.834 / 388.047 | confirmed-regression |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 927.989 | 9.425 | 14.130 | 14.498 | 33.065 / 388.391 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2680.480 | 19.241 | 30.553 | 44.537 | 384.522 / 629.430 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2691.610 | 32.471 | 69.215 | 90.386 | 382.759 / 634.039 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 251.930 | 231.676 | 422.931 | 545.573 | 212.637 / 635.285 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 242.222 | 302.381 | 768.969 | 930.635 | 217.974 / 637.016 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2346.653 | 19.197 | 35.302 | 36.039 | 300.852 / 637.039 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2753.810 | 32.378 | 57.056 | 75.327 | 387.268 / 637.039 | confirmed-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.534 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.434 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.504 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.572 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.100 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 4.096 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.347 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.115 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.026 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.499 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.599 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.288 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.378 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.110 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.061 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.046 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.523 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.503 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.492 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.598 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.459 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.543 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.289 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.368 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.044 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.515 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.194 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.170 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.194 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.057 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.021 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.075 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.087 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.077 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.065 | — | — / — | confirmed-regression |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 887.754 | 111.522 | 121.792 | 124.430 | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1389.839 | 139.995 | 166.310 | 166.491 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +25.3%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -19.7%, p95_ms: -22.2%, p99_ms: -33.7%, requests_per_second: +25.0%, rss_bytes: +0.7% |
| cache_miss | improvement | completed: +25.6%, cpu_percent: -0.5%, duration_seconds: -0.0%, p50_ms: -19.5%, p95_ms: -29.8%, p99_ms: -28.2%, requests_per_second: +24.3%, rss_bytes: +0.7% |
| cache_miss | improvement | completed: +31.4%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: -21.6%, p95_ms: -40.0%, p99_ms: -20.0%, requests_per_second: +31.3%, rss_bytes: +0.7% |
| health_live | confirmed-regression | completed: -26.5%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: +36.8%, p95_ms: +34.8%, p99_ms: +51.2%, requests_per_second: -26.5%, rss_bytes: +0.8% |
| health_live | confirmed-regression | completed: -28.9%, cpu_percent: +0.2%, duration_seconds: -4.7%, p50_ms: +35.3%, p95_ms: +20.2%, p99_ms: +11.7%, requests_per_second: -25.8%, rss_bytes: +0.8% |
| health_live | confirmed-regression | completed: -23.5%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +30.0%, p95_ms: +17.4%, p99_ms: +18.5%, requests_per_second: -23.6%, rss_bytes: +0.8% |
| health_live | confirmed-regression | completed: -23.8%, cpu_percent: +1.2%, duration_seconds: -0.1%, p50_ms: +31.6%, p95_ms: +23.6%, p99_ms: +44.0%, requests_per_second: -23.8%, rss_bytes: +0.8% |
| home | improvement | completed: +31.2%, cpu_percent: -8.6%, duration_seconds: +0.0%, p50_ms: -24.5%, p95_ms: -30.5%, p99_ms: -36.4%, requests_per_second: +32.0%, rss_bytes: +0.8% |
| home | improvement | completed: +26.9%, cpu_percent: -9.2%, duration_seconds: -0.0%, p50_ms: -24.5%, p95_ms: -20.3%, p99_ms: -24.7%, requests_per_second: +31.4%, rss_bytes: +0.8% |
| home | improvement | completed: +32.2%, cpu_percent: -10.3%, duration_seconds: +0.0%, p50_ms: -18.7%, p95_ms: -26.8%, p99_ms: -20.0%, requests_per_second: +32.2%, rss_bytes: +0.8% |
| categories | confirmed-regression | completed: -27.3%, cpu_percent: +0.5%, duration_seconds: -4.7%, p50_ms: +32.0%, p95_ms: +31.9%, p99_ms: +26.4%, requests_per_second: -23.7%, rss_bytes: +0.8% |
| categories | confirmed-regression | completed: -28.3%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: +32.9%, p95_ms: +14.2%, p99_ms: +19.5%, requests_per_second: -24.8%, rss_bytes: +0.8% |
| categories | confirmed-regression | completed: -24.9%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +29.8%, p95_ms: +38.9%, p99_ms: +40.0%, requests_per_second: -24.8%, rss_bytes: +0.8% |
| category | confirmed-regression | completed: -26.7%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: +32.3%, p95_ms: +34.9%, p99_ms: +33.0%, requests_per_second: -24.7%, rss_bytes: +0.8% |
| category | confirmed-regression | completed: -27.9%, cpu_percent: -0.0%, duration_seconds: -4.6%, p50_ms: +32.4%, p95_ms: +33.1%, p99_ms: +19.4%, requests_per_second: -26.2%, rss_bytes: +0.8% |
| category | confirmed-regression | completed: -23.6%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: +30.9%, p95_ms: +28.1%, p99_ms: +29.5%, requests_per_second: -23.3%, rss_bytes: +0.8% |
| thread | confirmed-regression | completed: -24.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +31.5%, p95_ms: +30.1%, p99_ms: +37.6%, requests_per_second: -23.9%, rss_bytes: +0.8% |
| thread | confirmed-regression | completed: -22.1%, cpu_percent: -0.3%, duration_seconds: +4.9%, p50_ms: +17.7%, p95_ms: +22.1%, p99_ms: +37.4%, requests_per_second: -24.6%, rss_bytes: +0.8% |
| thread | confirmed-regression | completed: -24.6%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +32.2%, p95_ms: +39.0%, p99_ms: +41.2%, requests_per_second: -24.7%, rss_bytes: +0.8% |
| thread | confirmed-regression | completed: -23.4%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: +32.1%, p95_ms: +18.3%, p99_ms: +36.8%, requests_per_second: -23.5%, rss_bytes: +0.7% |
| search | improvement | completed: +56.0%, cpu_percent: +35.0%, duration_seconds: -0.0%, p50_ms: -1.7%, p95_ms: -92.8%, p99_ms: -94.9%, requests_per_second: +55.1%, rss_bytes: +0.8% |
| search | improvement | completed: +83.7%, cpu_percent: +41.5%, duration_seconds: +0.0%, p50_ms: -21.0%, p95_ms: -76.8%, p99_ms: -74.7%, requests_per_second: +82.9%, rss_bytes: +0.7% |
| search | improvement | completed: +122.3%, cpu_percent: +56.6%, duration_seconds: -0.0%, p50_ms: -48.9%, p95_ms: -49.3%, p99_ms: -50.6%, requests_per_second: +122.3%, rss_bytes: +0.7% |
| search | stable | completed: +73.0%, cpu_percent: +51.7%, duration_seconds: +0.0%, p50_ms: -36.3%, p95_ms: -23.9%, p99_ms: -23.9%, requests_per_second: +72.8%, rss_bytes: +0.7% |
| cache_hit | confirmed-regression | completed: -26.6%, cpu_percent: +5.7%, duration_seconds: -0.0%, p50_ms: +38.4%, p95_ms: +32.5%, p99_ms: +9.6%, requests_per_second: -26.6%, rss_bytes: +0.7% |
| cache_hit | confirmed-regression | completed: -24.3%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +29.4%, p95_ms: +43.9%, p99_ms: +18.3%, requests_per_second: -24.4%, rss_bytes: +0.7% |
| cache_hit | confirmed-regression | completed: -24.0%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +30.8%, p95_ms: +36.7%, p99_ms: +26.2%, requests_per_second: -24.0%, rss_bytes: +0.7% |
| cache_hit | confirmed-regression | completed: -25.6%, cpu_percent: -1.0%, duration_seconds: -0.0%, p50_ms: +32.7%, p95_ms: +29.5%, p99_ms: +40.2%, requests_per_second: -25.6%, rss_bytes: +0.7% |
| health_live | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -8.5%, duration_seconds: +24.6%, p50_ms: +17.8%, p95_ms: +29.2%, p99_ms: +29.2%, requests_per_second: -19.5%, rss_bytes: +0.7% |
| thread | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -5.5%, duration_seconds: +25.6%, p50_ms: +19.3%, p95_ms: +9.8%, p99_ms: +2.0%, requests_per_second: -20.1%, rss_bytes: +0.7% |
| thread | confirmed-regression | completed: -24.9%, cpu_percent: -0.5%, duration_seconds: -0.2%, p50_ms: +77.7%, p95_ms: +28.8%, p99_ms: +44.7%, requests_per_second: -24.8%, rss_bytes: +0.6% |
| thread | confirmed-regression | completed: -23.0%, cpu_percent: -1.4%, duration_seconds: -0.0%, p50_ms: +24.7%, p95_ms: +29.2%, p99_ms: +22.9%, requests_per_second: -23.1%, rss_bytes: +0.6% |
| search | improvement | completed: +139.3%, cpu_percent: +69.9%, duration_seconds: -0.0%, p50_ms: -22.8%, p95_ms: -49.6%, p99_ms: -45.2%, requests_per_second: +139.4%, rss_bytes: +0.5% |
| search | improvement | completed: +70.8%, cpu_percent: +35.7%, duration_seconds: +0.1%, p50_ms: -12.9%, p95_ms: -21.1%, p99_ms: -9.7%, requests_per_second: +71.2%, rss_bytes: +0.5% |
| cache_hit | stable | completed: -4.8%, cpu_percent: +35.1%, duration_seconds: -0.0%, p50_ms: +1.6%, p95_ms: +25.6%, p99_ms: +11.0%, requests_per_second: -4.8%, rss_bytes: +0.4% |
| cache_hit | confirmed-regression | completed: -24.1%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +42.1%, p95_ms: +30.4%, p99_ms: +26.1%, requests_per_second: -24.2%, rss_bytes: +0.4% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +23.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +23.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +28.9% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +26.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +25.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +27.1% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +32.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +22.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +32.4% |
| sql-plan-readers | confirmed-regression | sql_execution_ms: +16.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +23.8% |
| sql-plan-readers | possible-regression | sql_execution_ms: +14.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +29.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +28.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +30.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +30.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +35.8% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +22.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +73.8% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +39.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +29.5% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +22.8% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +20.2% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +28.7% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +28.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +21.9% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +28.5% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +23.9% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +30.2% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +27.8% |
| sql-plan-functions | possible-regression | nested_statements: +0.0%, sql_execution_ms: +14.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +29.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +23.9% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +31.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.3% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +14.5% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +48.1% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +16.1% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -28.1%, messages_per_second: +39.0%, p50_ms: -15.9%, p95_ms: -59.7%, p99_ms: -73.9% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -14.6%, messages_per_second: +17.1%, p50_ms: -14.9%, p95_ms: -39.9%, p99_ms: -39.9% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +35.1%, cpu_percent: +92.3%, duration_seconds: -0.0%, p50_ms: -22.2%, p95_ms: +13.8%, p99_ms: +1.1%, requests_per_second: +35.1%, rss_bytes: +63.8% |
| thread | workers=4 | 2 | 100 | improvement | completed: +37.4%, cpu_percent: +91.4%, duration_seconds: +0.2%, p50_ms: -35.0%, p95_ms: +34.1%, p99_ms: +3.7%, requests_per_second: +37.1%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 50 | improvement | completed: +36.9%, cpu_percent: +90.2%, duration_seconds: +0.1%, p50_ms: -5.7%, p95_ms: -3.4%, p99_ms: +6.9%, requests_per_second: +36.8%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 100 | improvement | completed: +40.2%, cpu_percent: +95.8%, duration_seconds: +0.2%, p50_ms: -37.5%, p95_ms: -17.1%, p99_ms: -4.8%, requests_per_second: +40.4%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +14.6%, cpu_percent: +50.5%, duration_seconds: -0.0%, p50_ms: -19.7%, p95_ms: +35.3%, p99_ms: -5.6%, requests_per_second: +14.7%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +37.0%, cpu_percent: +93.7%, duration_seconds: +0.1%, p50_ms: -32.9%, p95_ms: +14.0%, p99_ms: -7.7%, requests_per_second: +36.5%, rss_bytes: +64.2% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38989650168)
