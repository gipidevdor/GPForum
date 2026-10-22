# GPForum continuous performance evidence

Commit: `08cd14566e2aff42c1315b4deea5e5c16c8ca14b` · mode: **main** · status: **ok**
Run: 38737369760 / attempt 1 · 2026-10-15T12:48:10.158332+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V45 96-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 720b09c2f07af15fb756e164d8101bb08d426dc1

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 344.470 | 2.820 | 3.120 | 5.187 | 94.501 / 371.758 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 660.608 | 15.394 | 20.603 | 24.633 | 188.095 / 371.867 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 628.390 | 75.383 | 100.879 | 138.306 | 188.519 / 373.672 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 2377.976 | 0.408 | 0.462 | 0.524 | 99.082 / 371.367 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 4647.310 | 2.093 | 2.312 | 3.162 | 199.069 / 371.367 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 4865.983 | 10.218 | 10.848 | 11.628 | 200.043 / 371.996 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 4678.651 | 21.190 | 22.739 | 30.483 | 199.876 / 373.246 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 182.409 | 5.225 | 7.166 | 10.486 | 82.982 / 373.840 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 330.642 | 32.611 | 41.408 | 49.541 | 167.143 / 374.273 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 322.117 | 153.128 | 204.536 | 297.613 | 167.526 / 376.516 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1730.520 | 0.570 | 0.620 | 0.667 | 99.617 / 376.516 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3367.082 | 3.270 | 3.995 | 5.103 | 198.943 / 376.516 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3573.494 | 14.063 | 14.931 | 19.127 | 200.036 / 376.516 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1740.540 | 0.566 | 0.619 | 0.689 | 99.504 / 376.672 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3317.643 | 2.943 | 3.244 | 5.591 | 199.113 / 376.672 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3411.263 | 14.135 | 16.391 | 24.176 | 199.890 / 376.672 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1684.188 | 0.582 | 0.637 | 0.779 | 99.592 / 376.797 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3276.732 | 2.915 | 4.412 | 5.043 | 199.084 / 376.797 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3302.166 | 15.195 | 20.969 | 26.239 | 199.898 / 376.914 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3392.367 | 28.873 | 31.122 | 41.227 | 200.487 / 380.453 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 122.381 | 7.769 | 11.603 | 12.892 | 61.723 / 381.094 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 219.216 | 45.057 | 66.645 | 85.451 | 125.370 / 381.094 | possible-regression |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 211.563 | 207.279 | 354.572 | 428.986 | 124.161 / 381.094 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 199.693 | 453.366 | 844.391 | 919.714 | 124.567 / 381.094 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1692.279 | 0.564 | 0.667 | 1.238 | 100.005 / 381.094 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3370.990 | 3.219 | 3.717 | 4.917 | 199.095 / 381.094 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3484.715 | 14.360 | 17.969 | 23.106 | 200.048 / 381.094 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3462.372 | 28.308 | 32.064 | 40.309 | 201.029 / 381.094 | possible-regression |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 2654.774 | 3.395 | 5.213 | 5.895 | 24.786 / 381.094 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1679.125 | 5.364 | 9.430 | 10.432 | 38.113 / 381.383 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 4123.497 | 13.818 | 20.784 | 26.060 | 298.903 / 619.004 | possible-regression |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 4136.439 | 35.320 | 40.491 | 50.575 | 298.984 / 624.188 | possible-regression |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 263.502 | 218.805 | 444.329 | 558.325 | 187.850 / 626.273 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 245.958 | 236.514 | 908.756 | 972.560 | 220.326 / 627.664 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 4243.410 | 8.907 | 19.260 | 20.498 | 298.969 / 627.664 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 5011.029 | 21.181 | 39.727 | 53.235 | 389.206 / 628.062 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 351.565 | 2.810 | 3.166 | 3.956 | 94.404 / 372.590 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 656.387 | 14.825 | 22.342 | 27.213 | 187.018 / 372.684 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 640.677 | 75.072 | 96.262 | 142.336 | 189.590 / 374.621 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 2395.617 | 0.410 | 0.452 | 0.504 | 99.560 / 372.488 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 4678.856 | 2.105 | 2.581 | 3.601 | 199.401 / 372.488 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 4833.550 | 10.405 | 11.236 | 15.592 | 199.618 / 373.211 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 4711.378 | 20.973 | 22.937 | 30.815 | 198.539 / 374.574 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 180.446 | 5.401 | 7.505 | 11.328 | 83.630 / 375.094 | possible-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 323.146 | 29.081 | 45.056 | 52.136 | 167.124 / 375.555 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 300.836 | 143.344 | 239.800 | 314.059 | 167.479 / 377.801 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1814.979 | 0.535 | 0.589 | 0.782 | 99.608 / 377.801 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3393.899 | 2.858 | 3.744 | 5.031 | 198.950 / 377.801 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3539.581 | 13.788 | 15.676 | 25.393 | 199.515 / 377.801 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1702.688 | 0.569 | 0.635 | 1.224 | 99.568 / 377.957 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3412.991 | 2.949 | 3.911 | 5.106 | 199.397 / 377.957 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3443.959 | 14.208 | 15.608 | 26.090 | 199.871 / 377.957 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1732.218 | 0.566 | 0.622 | 0.650 | 99.431 / 378.082 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3283.141 | 3.038 | 4.527 | 6.607 | 199.144 / 378.082 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3308.938 | 14.648 | 16.358 | 26.649 | 199.857 / 378.293 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3264.750 | 29.050 | 41.717 | 52.553 | 200.930 / 381.480 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 119.486 | 7.768 | 10.094 | 11.209 | 61.724 / 382.160 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 215.266 | 47.219 | 63.442 | 90.194 | 122.931 / 382.160 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 197.736 | 221.751 | 397.197 | 458.914 | 125.821 / 382.160 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 199.013 | 417.397 | 740.974 | 806.296 | 125.610 / 382.477 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1788.408 | 0.549 | 0.604 | 0.645 | 100.041 / 382.477 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3392.148 | 2.920 | 3.974 | 5.478 | 199.617 / 382.477 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3534.210 | 13.945 | 15.163 | 23.715 | 200.518 / 382.477 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3500.145 | 27.469 | 32.005 | 50.479 | 199.994 / 382.477 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4741.432 | 10.759 | 19.642 | 24.383 | 385.575 / 620.551 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 4669.183 | 19.572 | 39.367 | 45.887 | 385.472 / 626.102 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 251.147 | 156.199 | 411.904 | 530.317 | 211.814 / 627.461 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 256.571 | 246.656 | 994.384 | 1197.841 | 217.960 / 628.750 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3416.740 | 16.482 | 23.540 | 31.315 | 210.375 / 629.785 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 4249.887 | 26.095 | 34.414 | 38.818 | 300.107 / 630.047 | possible-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.311 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.252 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.278 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.300 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.069 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.200 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.256 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.076 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.067 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.019 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.269 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.314 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.152 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.212 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.070 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.037 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.032 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.200 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.313 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.261 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.326 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.274 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.464 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.166 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.212 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.751 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.857 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.118 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.100 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.117 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.039 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.013 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.063 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.046 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.045 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 1018.826 | 100.456 | 108.408 | 110.870 | — / — | possible-regression |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1639.555 | 120.407 | 134.007 | 134.136 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | confirmed-regression | completed: -20.0%, cpu_percent: -5.6%, duration_seconds: -0.0%, p50_ms: +27.8%, p95_ms: +5.5%, p99_ms: +24.6%, requests_per_second: -19.9%, rss_bytes: +0.7% |
| cache_miss | confirmed-regression | completed: -23.7%, cpu_percent: -5.5%, duration_seconds: -0.1%, p50_ms: +18.1%, p95_ms: +44.6%, p99_ms: +45.8%, requests_per_second: -23.7%, rss_bytes: +0.7% |
| cache_miss | confirmed-regression | completed: -27.5%, cpu_percent: -6.3%, duration_seconds: -0.0%, p50_ms: +31.0%, p95_ms: +54.8%, p99_ms: +47.2%, requests_per_second: -27.6%, rss_bytes: +0.7% |
| health_live | stable | completed: -3.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +1.0%, p95_ms: +1.8%, p99_ms: -2.6%, requests_per_second: -1.8%, rss_bytes: +0.6% |
| health_live | stable | completed: -0.6%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +1.5%, p95_ms: +0.3%, p99_ms: +1.7%, requests_per_second: -1.6%, rss_bytes: +0.6% |
| health_live | stable | completed: -2.2%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +2.4%, p95_ms: -2.9%, p99_ms: -21.9%, requests_per_second: -2.0%, rss_bytes: +0.6% |
| health_live | stable | completed: -2.8%, cpu_percent: -0.0%, duration_seconds: +0.3%, p50_ms: +7.8%, p95_ms: -5.8%, p99_ms: +4.4%, requests_per_second: -4.8%, rss_bytes: +0.5% |
| home | confirmed-regression | completed: -13.5%, cpu_percent: -2.0%, duration_seconds: +0.1%, p50_ms: +11.9%, p95_ms: +43.5%, p99_ms: +84.9%, requests_per_second: -13.5%, rss_bytes: +0.6% |
| home | confirmed-regression | completed: -17.5%, cpu_percent: -2.0%, duration_seconds: +0.0%, p50_ms: +16.7%, p95_ms: +24.4%, p99_ms: +25.6%, requests_per_second: -17.5%, rss_bytes: +0.5% |
| home | confirmed-regression | completed: -16.6%, cpu_percent: -2.7%, duration_seconds: -0.0%, p50_ms: +25.0%, p95_ms: +25.8%, p99_ms: +31.7%, requests_per_second: -16.6%, rss_bytes: +0.5% |
| categories | improvement | completed: -5.8%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +8.6%, p95_ms: +8.2%, p99_ms: -19.3%, requests_per_second: -7.2%, rss_bytes: +0.5% |
| categories | confirmed-regression | completed: -1.7%, cpu_percent: -0.3%, duration_seconds: +4.9%, p50_ms: +18.3%, p95_ms: +16.3%, p99_ms: +15.8%, requests_per_second: -6.4%, rss_bytes: +0.5% |
| categories | stable | completed: -1.5%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: +3.3%, p95_ms: +3.6%, p99_ms: +8.1%, requests_per_second: -1.5%, rss_bytes: +0.5% |
| category | stable | completed: -7.9%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +3.5%, p95_ms: +4.6%, p99_ms: +3.0%, requests_per_second: -3.3%, rss_bytes: +0.5% |
| category | confirmed-regression | completed: -5.4%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +8.0%, p95_ms: +4.8%, p99_ms: +31.5%, requests_per_second: -5.4%, rss_bytes: +0.5% |
| category | possible-regression | completed: -6.6%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +4.1%, p95_ms: +9.9%, p99_ms: +16.0%, requests_per_second: -6.7%, rss_bytes: +0.5% |
| thread | stable | completed: -4.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +2.1%, p95_ms: +2.4%, p99_ms: +19.3%, requests_per_second: -3.1%, rss_bytes: +0.5% |
| thread | stable | completed: +0.4%, cpu_percent: -0.0%, duration_seconds: +4.9%, p50_ms: -12.3%, p95_ms: +6.6%, p99_ms: +8.6%, requests_per_second: -4.3%, rss_bytes: +0.5% |
| thread | possible-regression | completed: -7.9%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +10.5%, p95_ms: +41.9%, p99_ms: +68.6%, requests_per_second: -8.0%, rss_bytes: +0.5% |
| thread | stable | completed: -4.2%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: +3.9%, p95_ms: +3.5%, p99_ms: +5.4%, requests_per_second: -4.3%, rss_bytes: +0.7% |
| search | stable | completed: -6.3%, cpu_percent: -2.8%, duration_seconds: +0.0%, p50_ms: +7.3%, p95_ms: +19.5%, p99_ms: +13.0%, requests_per_second: -5.2%, rss_bytes: +0.7% |
| search | possible-regression | completed: -16.1%, cpu_percent: +1.5%, duration_seconds: +4.9%, p50_ms: +7.9%, p95_ms: +28.8%, p99_ms: +22.4%, requests_per_second: -16.1%, rss_bytes: +0.7% |
| search | stable | completed: -15.2%, cpu_percent: -1.2%, duration_seconds: +0.0%, p50_ms: +7.3%, p95_ms: +12.2%, p99_ms: +14.6%, requests_per_second: -15.3%, rss_bytes: +0.7% |
| search | possible-regression | completed: -20.0%, cpu_percent: -0.8%, duration_seconds: -0.0%, p50_ms: +14.8%, p95_ms: +29.8%, p99_ms: +24.0%, requests_per_second: -19.9%, rss_bytes: +0.7% |
| cache_hit | possible-regression | completed: -7.3%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +5.4%, p95_ms: +11.4%, p99_ms: +87.0%, requests_per_second: -7.3%, rss_bytes: +0.7% |
| cache_hit | stable | completed: -0.6%, cpu_percent: +0.0%, duration_seconds: +4.9%, p50_ms: +1.9%, p95_ms: +4.3%, p99_ms: -5.8%, requests_per_second: -4.2%, rss_bytes: +0.7% |
| cache_hit | confirmed-regression | completed: -5.1%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: +7.2%, p95_ms: +23.4%, p99_ms: +49.4%, requests_per_second: -5.1%, rss_bytes: +0.7% |
| cache_hit | possible-regression | completed: -4.9%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +4.6%, p95_ms: +8.2%, p99_ms: +16.2%, requests_per_second: -4.9%, rss_bytes: +0.7% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +0.2%, duration_seconds: +2.7%, p50_ms: +6.0%, p95_ms: -7.4%, p99_ms: -2.9%, requests_per_second: -1.2%, rss_bytes: +0.7% |
| thread | possible-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +11.2%, duration_seconds: +13.2%, p50_ms: +7.8%, p95_ms: +27.0%, p99_ms: +14.3%, requests_per_second: -11.7%, rss_bytes: +0.7% |
| thread | possible-regression | completed: -11.7%, cpu_percent: -22.4%, duration_seconds: +4.9%, p50_ms: +30.1%, p95_ms: +4.1%, p99_ms: -3.6%, requests_per_second: -13.4%, rss_bytes: +0.6% |
| thread | possible-regression | completed: -9.8%, cpu_percent: -22.9%, duration_seconds: -0.0%, p50_ms: +65.4%, p95_ms: +13.1%, p99_ms: +10.6%, requests_per_second: -9.6%, rss_bytes: +0.7% |
| search | stable | completed: +6.9%, cpu_percent: -19.4%, duration_seconds: -0.3%, p50_ms: +53.4%, p95_ms: -4.6%, p99_ms: -17.0%, requests_per_second: +7.2%, rss_bytes: +0.7% |
| search | stable | completed: +4.9%, cpu_percent: -7.5%, duration_seconds: +0.2%, p50_ms: -2.9%, p95_ms: +15.5%, p99_ms: +8.2%, requests_per_second: +4.7%, rss_bytes: +0.6% |
| cache_hit | improvement | completed: +22.7%, cpu_percent: +44.3%, duration_seconds: -4.5%, p50_ms: -26.4%, p95_ms: -12.3%, p99_ms: -29.3%, requests_per_second: +28.2%, rss_bytes: +0.6% |
| cache_hit | improvement | completed: +13.4%, cpu_percent: +1.0%, duration_seconds: +0.2%, p50_ms: -8.3%, p95_ms: -0.6%, p99_ms: +26.8%, requests_per_second: +12.6%, rss_bytes: +0.7% |
| cache_miss | confirmed-regression | completed: -14.7%, cpu_percent: -5.1%, duration_seconds: +0.1%, p50_ms: +18.2%, p95_ms: +15.6%, p99_ms: +23.8%, requests_per_second: -14.7%, rss_bytes: +0.6% |
| cache_miss | confirmed-regression | completed: -19.9%, cpu_percent: -6.1%, duration_seconds: -4.7%, p50_ms: +18.4%, p95_ms: +45.2%, p99_ms: +28.9%, requests_per_second: -15.9%, rss_bytes: +0.6% |
| cache_miss | confirmed-regression | completed: -16.0%, cpu_percent: -6.0%, duration_seconds: -0.1%, p50_ms: +21.9%, p95_ms: +34.1%, p99_ms: +14.6%, requests_per_second: -15.9%, rss_bytes: +0.6% |
| health_live | stable | completed: -1.8%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: +1.7%, p95_ms: +1.1%, p99_ms: +7.5%, requests_per_second: -1.8%, rss_bytes: +0.6% |
| health_live | stable | completed: -2.4%, cpu_percent: -0.0%, duration_seconds: +4.9%, p50_ms: +2.5%, p95_ms: +0.2%, p99_ms: +6.2%, requests_per_second: -2.0%, rss_bytes: +0.6% |
| health_live | stable | completed: +1.4%, cpu_percent: +0.3%, duration_seconds: +4.9%, p50_ms: +4.1%, p95_ms: +0.4%, p99_ms: -1.5%, requests_per_second: -0.9%, rss_bytes: +0.6% |
| health_live | stable | completed: +0.0%, cpu_percent: -0.7%, duration_seconds: +0.1%, p50_ms: +1.4%, p95_ms: -11.2%, p99_ms: -1.0%, requests_per_second: -0.0%, rss_bytes: +0.6% |
| home | possible-regression | completed: -10.6%, cpu_percent: -3.4%, duration_seconds: -0.1%, p50_ms: +12.8%, p95_ms: +29.6%, p99_ms: +53.8%, requests_per_second: -10.6%, rss_bytes: +0.6% |
| home | stable | completed: +5.9%, cpu_percent: -2.0%, duration_seconds: -0.0%, p50_ms: -11.5%, p95_ms: -5.3%, p99_ms: -18.0%, requests_per_second: +5.9%, rss_bytes: +0.6% |
| home | stable | completed: -6.5%, cpu_percent: -2.4%, duration_seconds: -0.1%, p50_ms: -5.9%, p95_ms: +6.9%, p99_ms: +6.9%, requests_per_second: -6.4%, rss_bytes: +0.5% |
| categories | stable | completed: -4.5%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: +3.5%, p95_ms: +2.6%, p99_ms: +21.2%, requests_per_second: -4.5%, rss_bytes: +0.5% |
| categories | stable | completed: +0.7%, cpu_percent: -0.2%, duration_seconds: +4.8%, p50_ms: -1.2%, p95_ms: -12.2%, p99_ms: -9.6%, requests_per_second: -2.9%, rss_bytes: +0.5% |
| categories | confirmed-regression | completed: -0.0%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -0.7%, p95_ms: +3.1%, p99_ms: +15.4%, requests_per_second: -0.0%, rss_bytes: +0.5% |
| category | confirmed-regression | completed: -4.5%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +2.7%, p95_ms: +6.4%, p99_ms: +71.7%, requests_per_second: -4.5%, rss_bytes: +0.6% |
| category | stable | completed: -0.1%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +2.4%, p95_ms: +9.9%, p99_ms: +2.2%, requests_per_second: -0.1%, rss_bytes: +0.6% |
| category | possible-regression | completed: -3.1%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: -1.2%, p95_ms: -3.1%, p99_ms: +16.1%, requests_per_second: +1.4%, rss_bytes: +0.6% |
| thread | stable | completed: -4.7%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +3.1%, p95_ms: +4.4%, p99_ms: +1.2%, requests_per_second: -4.0%, rss_bytes: +0.6% |
| thread | stable | completed: -6.5%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: +6.4%, p95_ms: +19.5%, p99_ms: +40.0%, requests_per_second: -4.0%, rss_bytes: +0.6% |
| thread | stable | completed: -0.9%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: +1.7%, p95_ms: +0.6%, p99_ms: +1.2%, requests_per_second: -2.3%, rss_bytes: +0.6% |
| thread | possible-regression | completed: -3.1%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -1.0%, p95_ms: +25.6%, p99_ms: +8.0%, requests_per_second: -3.1%, rss_bytes: +0.6% |
| search | stable | completed: +0.4%, cpu_percent: -6.1%, duration_seconds: +0.1%, p50_ms: -6.2%, p95_ms: +5.2%, p99_ms: -0.5%, requests_per_second: +0.5%, rss_bytes: +0.7% |
| search | improvement | completed: +7.2%, cpu_percent: -6.7%, duration_seconds: -0.1%, p50_ms: -15.0%, p95_ms: -24.3%, p99_ms: -24.4%, requests_per_second: +7.4%, rss_bytes: +0.6% |
| search | stable | completed: +0.0%, cpu_percent: -5.6%, duration_seconds: +0.1%, p50_ms: -6.8%, p95_ms: -3.7%, p99_ms: -4.7%, requests_per_second: +0.0%, rss_bytes: +0.6% |
| search | stable | completed: +0.0%, cpu_percent: -5.8%, duration_seconds: -0.0%, p50_ms: -6.9%, p95_ms: -15.5%, p99_ms: -15.0%, requests_per_second: -0.1%, rss_bytes: +0.7% |
| cache_hit | stable | completed: -6.6%, cpu_percent: -1.0%, duration_seconds: -0.0%, p50_ms: +2.2%, p95_ms: +3.8%, p99_ms: -3.2%, requests_per_second: -3.0%, rss_bytes: +0.7% |
| cache_hit | stable | completed: -7.5%, cpu_percent: +0.3%, duration_seconds: -4.6%, p50_ms: -0.7%, p95_ms: +15.0%, p99_ms: +22.7%, requests_per_second: -5.7%, rss_bytes: +0.7% |
| cache_hit | improvement | completed: -3.7%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: -24.9%, p99_ms: -6.7%, requests_per_second: +0.7%, rss_bytes: +0.7% |
| cache_hit | stable | completed: +3.3%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +4.6%, p95_ms: -6.5%, p99_ms: +9.2%, requests_per_second: +3.3%, rss_bytes: +0.7% |
| thread | improvement | completed: +17.4%, cpu_percent: +29.4%, duration_seconds: -0.0%, p50_ms: -26.9%, p95_ms: -0.8%, p99_ms: -10.1%, requests_per_second: +17.5%, rss_bytes: +0.6% |
| thread | stable | completed: -0.7%, cpu_percent: +2.0%, duration_seconds: +0.1%, p50_ms: -17.9%, p95_ms: +7.1%, p99_ms: +2.3%, requests_per_second: -0.6%, rss_bytes: +0.8% |
| search | stable | completed: +3.1%, cpu_percent: -5.1%, duration_seconds: +0.1%, p50_ms: -16.3%, p95_ms: -2.9%, p99_ms: +4.3%, requests_per_second: +3.1%, rss_bytes: +0.7% |
| search | improvement | completed: +14.7%, cpu_percent: +10.6%, duration_seconds: +0.1%, p50_ms: -7.7%, p95_ms: -6.3%, p99_ms: -3.6%, requests_per_second: +14.6%, rss_bytes: +0.5% |
| cache_hit | confirmed-regression | completed: -17.3%, cpu_percent: -31.7%, duration_seconds: -0.2%, p50_ms: +76.9%, p95_ms: +0.8%, p99_ms: +12.1%, requests_per_second: -17.2%, rss_bytes: +0.6% |
| cache_hit | possible-regression | completed: -12.0%, cpu_percent: -21.1%, duration_seconds: -0.0%, p50_ms: +4.9%, p95_ms: -1.6%, p99_ms: -8.9%, requests_per_second: -12.1%, rss_bytes: +0.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -7.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.1% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +11.8% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.0% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +15.8% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +25.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +23.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +10.3% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +11.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +8.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +63.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +10.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.3% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +11.1% |
| sql-plan-functions | possible-regression | nested_statements: +0.0%, sql_execution_ms: +20.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +8.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.1% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +31.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.1% |
| postgres-dispatch-noop | possible-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +7.6%, messages_per_second: -7.1%, p50_ms: +10.1%, p95_ms: +3.0%, p99_ms: +3.9% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +7.6%, messages_per_second: -7.1%, p50_ms: +7.6%, p95_ms: +8.2%, p99_ms: +7.7% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.2%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: -0.4%, p95_ms: +1.5%, p99_ms: -23.7%, requests_per_second: +2.1%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.7%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: -3.7%, p95_ms: +8.4%, p99_ms: +10.5%, requests_per_second: -0.6%, rss_bytes: +0.2% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.8%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: -0.4%, p95_ms: -4.6%, p99_ms: +2.9%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.8%, cpu_percent: +0.5%, duration_seconds: +0.0%, p50_ms: +0.5%, p95_ms: -2.2%, p99_ms: -3.8%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.9%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: +11.6%, p99_ms: +13.9%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +1.6%, cpu_percent: -0.2%, duration_seconds: +4.9%, p50_ms: +1.8%, p95_ms: +3.6%, p99_ms: +34.1%, requests_per_second: -0.7%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -1.3%, cpu_percent: -0.7%, duration_seconds: -0.2%, p50_ms: -1.0%, p95_ms: +0.9%, p99_ms: +1.1%, requests_per_second: +0.7%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.1%, cpu_percent: +0.8%, duration_seconds: -0.0%, p50_ms: +3.4%, p95_ms: +4.7%, p99_ms: +8.0%, requests_per_second: -1.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -2.3%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -10.8%, p95_ms: +8.8%, p99_ms: +5.2%, requests_per_second: -2.3%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -6.7%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -6.4%, p95_ms: +17.2%, p99_ms: +5.5%, requests_per_second: -6.6%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.9%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -6.1%, p95_ms: -5.0%, p99_ms: +17.2%, requests_per_second: +4.9%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: -0.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -12.6%, p95_ms: -6.3%, p99_ms: -1.4%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.0%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: -2.0%, p95_ms: +5.0%, p99_ms: +32.8%, requests_per_second: -0.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | confirmed-regression | completed: +2.7%, cpu_percent: +0.1%, duration_seconds: +5.0%, p50_ms: +0.5%, p95_ms: +2.6%, p99_ms: +77.6%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -1.9%, cpu_percent: +0.1%, duration_seconds: -4.7%, p50_ms: +0.2%, p95_ms: +20.6%, p99_ms: -8.7%, requests_per_second: +2.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.0%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +0.5%, p95_ms: -4.8%, p99_ms: +7.9%, requests_per_second: +1.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.1%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -2.7%, p95_ms: -2.4%, p99_ms: -16.6%, requests_per_second: +2.9%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -4.5%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: +4.2%, p95_ms: +2.6%, p99_ms: +31.0%, requests_per_second: +0.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +1.5%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -3.6%, p95_ms: -22.0%, p99_ms: +1.6%, requests_per_second: +0.2%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -3.8%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +0.6%, p95_ms: +34.0%, p99_ms: +27.5%, requests_per_second: -3.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: -5.9%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.0%, p95_ms: -13.0%, p99_ms: -13.1%, requests_per_second: -2.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -1.8%, cpu_percent: -1.9%, duration_seconds: -4.7%, p50_ms: +4.8%, p95_ms: -4.8%, p99_ms: +5.6%, requests_per_second: -1.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -6.6%, cpu_percent: +1.3%, duration_seconds: +0.0%, p50_ms: +7.0%, p95_ms: +12.0%, p99_ms: +7.0%, requests_per_second: -6.5%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.2%, cpu_percent: +0.8%, duration_seconds: +0.1%, p50_ms: -7.9%, p95_ms: -12.2%, p99_ms: -12.3%, requests_per_second: -0.3%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +1.7%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -2.7%, p95_ms: -9.4%, p99_ms: -47.9%, requests_per_second: +5.7%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.1%, cpu_percent: +0.3%, duration_seconds: -4.6%, p50_ms: -9.3%, p95_ms: +6.9%, p99_ms: +11.4%, requests_per_second: +0.6%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.4%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -2.9%, p95_ms: -15.6%, p99_ms: +2.6%, requests_per_second: +1.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.0%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: -3.0%, p95_ms: -0.2%, p99_ms: +25.2%, requests_per_second: +1.1%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +9.6%, cpu_percent: +29.0%, duration_seconds: -4.7%, p50_ms: -22.1%, p95_ms: -5.5%, p99_ms: -6.4%, requests_per_second: +15.0%, rss_bytes: +0.2% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +13.0%, cpu_percent: +28.9%, duration_seconds: +0.1%, p50_ms: -44.6%, p95_ms: -2.8%, p99_ms: -9.3%, requests_per_second: +12.9%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -4.4%, cpu_percent: +12.8%, duration_seconds: +0.2%, p50_ms: -28.6%, p95_ms: -7.3%, p99_ms: -5.0%, requests_per_second: -4.7%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | confirmed-regression | completed: +4.0%, cpu_percent: -1.1%, duration_seconds: -0.3%, p50_ms: +4.3%, p95_ms: +9.4%, p99_ms: +23.2%, requests_per_second: +4.3%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -19.7%, cpu_percent: -29.6%, duration_seconds: -0.1%, p50_ms: +85.0%, p95_ms: +22.2%, p99_ms: +52.8%, requests_per_second: -19.5%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | confirmed-regression | completed: -15.8%, cpu_percent: -22.9%, duration_seconds: -0.2%, p50_ms: +23.2%, p95_ms: -13.4%, p99_ms: -27.1%, requests_per_second: -15.2%, rss_bytes: +0.3% |
| thread | workers=4 | 2 | 50 | improvement | completed: +30.9%, cpu_percent: +49.5%, duration_seconds: +4.9%, p50_ms: -9.1%, p95_ms: -0.9%, p99_ms: -0.7%, requests_per_second: +24.9%, rss_bytes: +64.2% |
| thread | workers=4 | 2 | 100 | confirmed-regression | completed: +21.9%, cpu_percent: +49.1%, duration_seconds: -0.0%, p50_ms: +22.3%, p95_ms: +30.1%, p99_ms: +22.7%, requests_per_second: +21.9%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 50 | improvement | completed: +24.5%, cpu_percent: +51.3%, duration_seconds: -0.0%, p50_ms: +5.6%, p95_ms: +25.3%, p99_ms: +30.1%, requests_per_second: +24.6%, rss_bytes: +64.3% |
| search | workers=4 | 2 | 100 | improvement | completed: +23.8%, cpu_percent: +76.9%, duration_seconds: +0.5%, p50_ms: -47.8%, p95_ms: +7.6%, p99_ms: +5.7%, requests_per_second: +23.2%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +22.1%, cpu_percent: +49.4%, duration_seconds: +0.1%, p50_ms: -38.0%, p95_ms: +7.2%, p99_ms: -11.3%, requests_per_second: +21.8%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +45.6%, cpu_percent: +93.6%, duration_seconds: +0.2%, p50_ms: -25.2%, p95_ms: +23.9%, p99_ms: +32.1%, requests_per_second: +44.7%, rss_bytes: +64.8% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +41.3%, cpu_percent: +92.9%, duration_seconds: -0.1%, p50_ms: -26.6%, p95_ms: +20.1%, p99_ms: -8.5%, requests_per_second: +43.3%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +43.1%, cpu_percent: +91.8%, duration_seconds: +0.0%, p50_ms: -32.6%, p95_ms: -5.6%, p99_ms: -12.7%, requests_per_second: +43.0%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 50 | stable | completed: +27.5%, cpu_percent: +68.3%, duration_seconds: +0.2%, p50_ms: -29.6%, p95_ms: +3.7%, p99_ms: +15.6%, requests_per_second: +27.0%, rss_bytes: +64.2% |
| search | workers=4 | 2 | 100 | confirmed-regression | completed: +29.1%, cpu_percent: +73.5%, duration_seconds: +0.1%, p50_ms: -40.9%, p95_ms: +34.2%, p99_ms: +48.6%, requests_per_second: +28.9%, rss_bytes: +64.4% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -3.3%, cpu_percent: +4.9%, duration_seconds: +0.0%, p50_ms: +18.2%, p95_ms: +55.2%, p99_ms: +32.0%, requests_per_second: -3.3%, rss_bytes: +64.7% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +21.4%, cpu_percent: +50.1%, duration_seconds: -0.1%, p50_ms: -5.0%, p95_ms: +7.5%, p99_ms: -23.1%, requests_per_second: +21.4%, rss_bytes: +64.7% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38737369760)
