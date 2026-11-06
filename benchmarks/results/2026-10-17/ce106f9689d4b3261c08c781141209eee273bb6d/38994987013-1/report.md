# GPForum continuous performance evidence

Commit: `ce106f9689d4b3261c08c781141209eee273bb6d` · mode: **main** · status: **ok**
Run: 38994987013 / attempt 1 · 2026-10-17T02:27:55.564410+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. cd35e1eaff3859ce8fbf89944e72ee619dc80f7a

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 506.401 | 1.949 | 2.055 | 2.215 | 100.044 / 378.082 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1012.455 | 9.736 | 11.985 | 17.249 | 199.515 / 378.363 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1004.503 | 48.521 | 51.104 | 89.124 | 200.899 / 380.375 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1817.984 | 0.543 | 0.586 | 0.607 | 99.556 / 378.211 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3598.287 | 2.723 | 3.191 | 4.714 | 198.946 / 378.211 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3723.821 | 13.236 | 13.975 | 19.869 | 199.967 / 379.070 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3698.792 | 26.672 | 27.542 | 39.904 | 199.060 / 380.449 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 220.887 | 4.489 | 4.791 | 4.906 | 78.151 / 381.145 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 410.598 | 23.575 | 28.893 | 42.911 | 155.187 / 381.738 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 383.942 | 122.216 | 153.733 | 224.353 | 157.177 / 384.145 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1371.743 | 0.723 | 0.761 | 0.807 | 99.582 / 384.145 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2646.963 | 3.731 | 4.520 | 5.808 | 199.557 / 384.145 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2716.439 | 18.175 | 18.648 | 27.415 | 200.525 / 384.145 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1333.500 | 0.742 | 0.794 | 0.851 | 99.566 / 384.176 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2563.916 | 3.863 | 5.217 | 6.678 | 199.060 / 384.176 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2617.908 | 18.752 | 20.503 | 27.524 | 200.538 / 384.176 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1305.233 | 0.752 | 0.802 | 0.966 | 99.115 / 384.348 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2529.005 | 3.923 | 4.763 | 6.795 | 199.848 / 384.348 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2621.287 | 18.728 | 20.193 | 32.002 | 199.994 / 384.348 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2589.094 | 37.627 | 39.009 | 63.250 | 198.073 / 387.461 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 134.434 | 7.395 | 7.645 | 7.832 | 55.260 / 387.883 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 246.196 | 38.975 | 54.349 | 75.278 | 110.491 / 387.984 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 246.487 | 193.018 | 293.084 | 369.867 | 110.867 / 387.984 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 248.508 | 391.655 | 687.246 | 769.847 | 109.876 / 387.984 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1343.979 | 0.734 | 0.788 | 0.813 | 99.569 / 387.984 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2631.471 | 3.755 | 4.171 | 6.531 | 199.091 / 387.984 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2703.876 | 18.215 | 19.177 | 28.529 | 200.511 / 387.984 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2685.812 | 36.512 | 38.497 | 57.534 | 200.507 / 387.984 | improvement |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1839.083 | 4.890 | 7.400 | 8.218 | 26.447 / 387.984 | improvement |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1220.332 | 7.242 | 11.231 | 12.672 | 37.931 / 388.305 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3572.368 | 14.363 | 25.049 | 33.171 | 385.554 / 630.121 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3541.859 | 20.932 | 50.221 | 54.546 | 387.782 / 634.707 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 316.933 | 118.605 | 342.869 | 472.712 | 204.389 / 636.637 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 317.724 | 233.035 | 444.738 | 604.750 | 216.214 / 636.949 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3696.342 | 13.791 | 24.775 | 28.937 | 384.407 / 636.949 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 3683.503 | 24.363 | 41.626 | 51.401 | 387.202 / 637.879 | improvement |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.432 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.343 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.375 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.440 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.080 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.215 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.785 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.080 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.388 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.458 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.226 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.290 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.049 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.036 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.410 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.527 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.408 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.478 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.380 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.616 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.254 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.405 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.420 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.162 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.148 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.128 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.171 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.046 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.014 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.057 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.116 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 1091.377 | 90.951 | 105.403 | 169.990 | — / — | possible-regression |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1747.978 | 112.435 | 126.219 | 126.317 | — / — | improvement |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +31.0%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: -24.5%, p95_ms: -22.6%, p99_ms: -20.5%, requests_per_second: +31.4%, rss_bytes: +0.0% |
| cache_miss | improvement | completed: +31.1%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -23.7%, p95_ms: -22.8%, p99_ms: -16.3%, requests_per_second: +31.9%, rss_bytes: +0.0% |
| cache_miss | improvement | completed: +31.1%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -23.7%, p95_ms: -22.4%, p99_ms: -24.5%, requests_per_second: +31.1%, rss_bytes: +0.0% |
| health_live | improvement | completed: +32.4%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -24.7%, p95_ms: -24.7%, p99_ms: -32.6%, requests_per_second: +32.4%, rss_bytes: +0.0% |
| health_live | improvement | completed: +36.3%, cpu_percent: -0.3%, duration_seconds: +4.9%, p50_ms: -24.5%, p95_ms: -15.1%, p99_ms: -10.3%, requests_per_second: +30.7%, rss_bytes: +0.0% |
| health_live | improvement | completed: +31.6%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -24.3%, p95_ms: -24.3%, p99_ms: -20.4%, requests_per_second: +31.6%, rss_bytes: +0.0% |
| health_live | improvement | completed: +31.7%, cpu_percent: -0.9%, duration_seconds: -0.0%, p50_ms: -23.5%, p95_ms: -24.4%, p99_ms: -32.4%, requests_per_second: +31.7%, rss_bytes: +0.0% |
| home | improvement | completed: +29.6%, cpu_percent: -1.2%, duration_seconds: -0.0%, p50_ms: -23.1%, p95_ms: -21.4%, p99_ms: -21.7%, requests_per_second: +31.2%, rss_bytes: +0.0% |
| home | improvement | completed: +28.2%, cpu_percent: -1.0%, duration_seconds: -4.7%, p50_ms: -22.1%, p95_ms: -33.1%, p99_ms: -22.9%, requests_per_second: +28.7%, rss_bytes: +0.0% |
| home | improvement | completed: +30.1%, cpu_percent: +0.7%, duration_seconds: +0.0%, p50_ms: -25.2%, p95_ms: -34.7%, p99_ms: -28.8%, requests_per_second: +30.1%, rss_bytes: +0.0% |
| categories | improvement | completed: +42.4%, cpu_percent: -0.4%, duration_seconds: +5.0%, p50_ms: -27.2%, p95_ms: -26.7%, p99_ms: -24.4%, requests_per_second: +35.7%, rss_bytes: +0.0% |
| categories | improvement | completed: +37.6%, cpu_percent: +0.0%, duration_seconds: +4.9%, p50_ms: -23.9%, p95_ms: -14.9%, p99_ms: -32.8%, requests_per_second: +31.2%, rss_bytes: +0.0% |
| categories | improvement | completed: +32.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -23.3%, p95_ms: -31.3%, p99_ms: -38.0%, requests_per_second: +32.2%, rss_bytes: +0.0% |
| category | improvement | completed: +32.5%, cpu_percent: +0.0%, duration_seconds: +5.0%, p50_ms: -24.1%, p95_ms: -23.7%, p99_ms: -22.1%, requests_per_second: +31.8%, rss_bytes: +0.0% |
| category | improvement | completed: +30.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -23.6%, p95_ms: -16.4%, p99_ms: -16.7%, requests_per_second: +33.4%, rss_bytes: +0.0% |
| category | improvement | completed: +29.6%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -23.2%, p95_ms: -19.6%, p99_ms: -30.2%, requests_per_second: +29.8%, rss_bytes: +0.0% |
| thread | improvement | completed: +36.4%, cpu_percent: -0.4%, duration_seconds: +4.9%, p50_ms: -23.7%, p95_ms: -23.4%, p99_ms: -16.5%, requests_per_second: +30.7%, rss_bytes: +0.0% |
| thread | improvement | completed: +24.4%, cpu_percent: +0.4%, duration_seconds: -4.6%, p50_ms: -22.8%, p95_ms: -24.8%, p99_ms: -21.4%, requests_per_second: +30.4%, rss_bytes: +0.0% |
| thread | improvement | completed: +32.1%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -24.2%, p95_ms: -24.8%, p99_ms: -27.3%, requests_per_second: +32.1%, rss_bytes: +0.0% |
| thread | improvement | completed: +31.9%, cpu_percent: -0.9%, duration_seconds: -0.1%, p50_ms: -24.7%, p95_ms: -24.4%, p99_ms: -27.5%, requests_per_second: +31.9%, rss_bytes: +0.0% |
| search | improvement | completed: +28.7%, cpu_percent: -0.9%, duration_seconds: -0.1%, p50_ms: -22.7%, p95_ms: -22.5%, p99_ms: -21.8%, requests_per_second: +29.5%, rss_bytes: -0.0% |
| search | improvement | completed: +30.7%, cpu_percent: -1.3%, duration_seconds: +0.0%, p50_ms: -22.0%, p95_ms: -30.5%, p99_ms: -17.0%, requests_per_second: +28.9%, rss_bytes: -0.0% |
| search | improvement | completed: +33.9%, cpu_percent: -0.8%, duration_seconds: +0.1%, p50_ms: -21.4%, p95_ms: -33.0%, p99_ms: -27.5%, requests_per_second: +33.8%, rss_bytes: -0.0% |
| search | improvement | completed: +43.9%, cpu_percent: -1.3%, duration_seconds: -0.0%, p50_ms: -19.1%, p95_ms: -25.9%, p99_ms: -21.3%, requests_per_second: +44.1%, rss_bytes: -0.0% |
| cache_hit | improvement | completed: +32.0%, cpu_percent: -5.7%, duration_seconds: +0.0%, p50_ms: -27.5%, p95_ms: -25.0%, p99_ms: -25.5%, requests_per_second: +36.2%, rss_bytes: -0.0% |
| cache_hit | improvement | completed: +31.2%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -23.7%, p95_ms: -37.7%, p99_ms: -16.0%, requests_per_second: +31.2%, rss_bytes: -0.0% |
| cache_hit | improvement | completed: +32.1%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -23.8%, p95_ms: -26.5%, p99_ms: -25.2%, requests_per_second: +32.2%, rss_bytes: -0.0% |
| cache_hit | improvement | completed: +33.2%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -24.3%, p95_ms: -23.1%, p99_ms: -29.5%, requests_per_second: +33.2%, rss_bytes: -0.0% |
| health_live | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +33.3%, duration_seconds: -23.9%, p50_ms: -25.7%, p95_ms: -25.6%, p99_ms: -20.8%, requests_per_second: +30.4%, rss_bytes: -0.0% |
| thread | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +14.7%, duration_seconds: -24.1%, p50_ms: -23.2%, p95_ms: -20.5%, p99_ms: -12.6%, requests_per_second: +31.5%, rss_bytes: -0.0% |
| thread | improvement | completed: +33.4%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: -25.4%, p95_ms: -18.0%, p99_ms: -25.5%, requests_per_second: +33.3%, rss_bytes: +0.1% |
| thread | improvement | completed: +31.6%, cpu_percent: +1.3%, duration_seconds: -0.2%, p50_ms: -35.5%, p95_ms: -27.4%, p99_ms: -39.7%, requests_per_second: +31.6%, rss_bytes: +0.1% |
| search | improvement | completed: +25.5%, cpu_percent: -3.9%, duration_seconds: -0.1%, p50_ms: -48.8%, p95_ms: -18.9%, p99_ms: -13.4%, requests_per_second: +25.8%, rss_bytes: +0.2% |
| search | improvement | completed: +31.3%, cpu_percent: -0.8%, duration_seconds: -0.2%, p50_ms: -22.9%, p95_ms: -42.2%, p99_ms: -35.0%, requests_per_second: +31.2%, rss_bytes: -0.0% |
| cache_hit | improvement | completed: +57.9%, cpu_percent: +27.8%, duration_seconds: +0.1%, p50_ms: -28.2%, p95_ms: -29.8%, p99_ms: -19.7%, requests_per_second: +57.5%, rss_bytes: -0.0% |
| cache_hit | improvement | completed: +33.4%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -24.8%, p95_ms: -27.0%, p99_ms: -31.8%, requests_per_second: +33.8%, rss_bytes: +0.1% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -19.1% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -21.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -25.6% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -23.1% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -20.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -21.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -23.9% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -21.7% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -18.4% |
| sql-plan-readers | improvement | sql_execution_ms: -28.6% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -15.4% |
| sql-plan-readers | improvement | sql_execution_ms: -12.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -22.2% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -23.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -21.5% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -23.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -17.3% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -19.7% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -21.7% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -21.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +4.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -17.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -20.1% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -17.2% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +13.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -12.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.1% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -20.5% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -23.3% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -23.7% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -24.7% |
| sql-plan-functions | improvement | nested_statements: +0.0%, sql_execution_ms: -25.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.9% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -19.3% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -33.3% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -24.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +33.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -31.2% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -26.2% |
| postgres-dispatch-noop | possible-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -18.7%, messages_per_second: +22.9%, p50_ms: -18.4%, p95_ms: -13.5%, p99_ms: +36.6% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -20.5%, messages_per_second: +25.8%, p50_ms: -19.7%, p95_ms: -24.1%, p99_ms: -24.1% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +36.4%, cpu_percent: +92.8%, duration_seconds: +0.0%, p50_ms: -23.3%, p95_ms: +24.0%, p99_ms: +3.7%, requests_per_second: +36.3%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | confirmed-regression | completed: +37.1%, cpu_percent: +95.8%, duration_seconds: -0.0%, p50_ms: -44.4%, p95_ms: +28.7%, p99_ms: -13.8%, requests_per_second: +36.8%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +28.3%, cpu_percent: +84.4%, duration_seconds: -0.1%, p50_ms: -38.6%, p95_ms: +17.0%, p99_ms: +27.8%, requests_per_second: +28.6%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 100 | improvement | completed: +27.9%, cpu_percent: +96.8%, duration_seconds: +0.0%, p50_ms: -40.5%, p95_ms: -35.3%, p99_ms: -21.4%, requests_per_second: +27.9%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +36.9%, cpu_percent: +91.7%, duration_seconds: +0.1%, p50_ms: -24.3%, p95_ms: +29.2%, p99_ms: +1.4%, requests_per_second: +36.7%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +37.2%, cpu_percent: +93.1%, duration_seconds: +0.1%, p50_ms: -33.3%, p95_ms: +8.1%, p99_ms: -10.7%, requests_per_second: +37.1%, rss_bytes: +64.4% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38994987013)
