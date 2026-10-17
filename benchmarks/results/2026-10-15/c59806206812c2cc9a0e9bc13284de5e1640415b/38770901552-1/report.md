# GPForum continuous performance evidence

Commit: `c59806206812c2cc9a0e9bc13284de5e1640415b` · mode: **main** · status: **ok**
Run: 38770901552 / attempt 1 · 2026-10-15T16:40:35.531430+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V45 96-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 08cd14566e2aff42c1315b4deea5e5c16c8ca14b

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 421.329 | 2.359 | 2.472 | 2.688 | 99.124 / 373.621 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 793.758 | 13.528 | 16.679 | 21.638 | 199.803 / 373.707 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 758.780 | 62.770 | 75.150 | 117.222 | 201.935 / 375.500 | improvement |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 2334.795 | 0.414 | 0.462 | 0.852 | 99.929 / 373.641 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 4623.836 | 2.064 | 2.716 | 3.930 | 199.434 / 373.641 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 4954.106 | 10.055 | 11.281 | 12.227 | 199.968 / 374.254 | stable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 4771.279 | 20.472 | 28.257 | 32.672 | 200.088 / 375.539 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 201.858 | 4.806 | 6.384 | 9.312 | 85.568 / 375.836 | improvement |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 375.764 | 28.564 | 48.781 | 55.558 | 170.851 / 376.625 | stable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 345.776 | 136.032 | 207.886 | 300.411 | 172.357 / 379.160 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1835.563 | 0.537 | 0.590 | 0.673 | 99.518 / 379.160 | stable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3560.764 | 2.864 | 3.497 | 3.767 | 199.138 / 379.160 | improvement |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3557.260 | 13.857 | 14.830 | 16.812 | 199.874 / 379.160 | stable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1700.372 | 0.552 | 0.682 | 1.394 | 99.523 / 379.211 | possible-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3406.279 | 3.032 | 3.644 | 4.820 | 198.989 / 379.211 | possible-regression |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3495.655 | 14.028 | 15.579 | 23.912 | 199.406 / 379.211 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1741.599 | 0.565 | 0.613 | 0.640 | 99.532 / 379.395 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3412.011 | 3.410 | 4.281 | 5.508 | 198.935 / 379.395 | stable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3521.816 | 14.057 | 15.576 | 21.510 | 200.095 / 379.461 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3472.040 | 28.281 | 31.148 | 36.560 | 200.339 / 381.988 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 133.888 | 7.132 | 9.378 | 13.010 | 62.240 / 382.707 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 228.743 | 45.185 | 61.046 | 69.552 | 128.731 / 382.707 | improvement |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 223.982 | 203.514 | 291.612 | 383.545 | 123.696 / 382.707 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 190.559 | 433.213 | 835.351 | 997.787 | 130.468 / 382.754 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1835.829 | 0.540 | 0.577 | 0.620 | 99.632 / 382.754 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3540.732 | 2.788 | 3.543 | 4.515 | 199.452 / 382.754 | stable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3503.674 | 13.936 | 16.474 | 26.301 | 200.358 / 382.754 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3543.029 | 27.900 | 29.635 | 36.413 | 197.992 / 382.754 | stable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 2706.352 | 3.069 | 5.351 | 6.112 | 20.633 / 382.754 | stable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1793.495 | 5.055 | 8.029 | 9.057 | 34.316 / 383.035 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 4919.831 | 11.355 | 20.666 | 27.147 | 380.893 / 622.164 | improvement |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 4624.604 | 21.076 | 38.409 | 43.410 | 384.440 / 626.938 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 278.401 | 150.548 | 423.537 | 600.926 | 216.440 / 629.441 | stable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 242.242 | 221.046 | 852.480 | 1104.046 | 238.704 / 631.438 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 3615.600 | 14.993 | 22.016 | 23.736 | 210.992 / 631.438 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 5065.150 | 20.751 | 34.947 | 48.120 | 387.031 / 631.438 | stable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 412.336 | 2.401 | 2.667 | 4.058 | 99.606 / 374.973 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 817.386 | 12.112 | 15.890 | 20.823 | 199.860 / 375.047 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 815.294 | 59.406 | 73.777 | 116.143 | 201.178 / 376.949 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 2443.092 | 0.400 | 0.440 | 0.473 | 99.949 / 374.824 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 4813.154 | 2.102 | 2.645 | 3.900 | 199.142 / 374.824 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 4921.733 | 10.116 | 11.096 | 13.671 | 199.605 / 375.590 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 4836.022 | 20.711 | 22.198 | 33.690 | 198.875 / 377.000 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 201.680 | 4.907 | 5.500 | 7.553 | 86.171 / 377.309 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 368.057 | 26.180 | 39.357 | 45.956 | 170.078 / 378.070 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 347.373 | 134.464 | 212.334 | 265.869 | 172.070 / 380.512 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1836.695 | 0.528 | 0.610 | 0.821 | 99.498 / 380.512 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3534.286 | 2.786 | 3.531 | 5.136 | 198.939 / 380.512 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3499.041 | 14.037 | 15.325 | 22.876 | 199.888 / 380.512 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1774.489 | 0.551 | 0.609 | 0.657 | 99.608 / 380.652 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3394.644 | 2.847 | 3.973 | 4.829 | 199.467 / 380.652 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3547.272 | 14.593 | 18.077 | 25.306 | 200.330 / 380.652 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1726.367 | 0.568 | 0.619 | 1.139 | 99.516 / 380.730 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3361.102 | 3.078 | 4.438 | 6.050 | 199.078 / 380.777 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3486.237 | 14.099 | 15.366 | 25.410 | 200.012 / 380.777 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3300.126 | 29.970 | 31.951 | 47.975 | 200.304 / 383.422 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 118.975 | 7.603 | 11.097 | 14.992 | 63.240 / 384.113 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 200.260 | 47.517 | 68.220 | 98.198 | 133.783 / 384.113 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 210.681 | 238.500 | 362.756 | 443.746 | 130.486 / 384.113 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 198.533 | 393.386 | 760.920 | 839.796 | 128.520 / 384.113 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1727.297 | 0.570 | 0.611 | 1.163 | 102.550 / 384.113 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3500.115 | 2.888 | 3.868 | 4.680 | 199.465 / 384.113 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3437.776 | 14.258 | 15.920 | 26.635 | 199.876 / 384.113 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3312.263 | 27.627 | 35.911 | 42.356 | 200.852 / 384.113 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4693.838 | 12.055 | 20.950 | 26.195 | 384.033 / 624.465 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 4555.816 | 19.716 | 40.709 | 47.702 | 380.109 / 628.398 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 239.480 | 200.955 | 461.448 | 546.482 | 193.325 / 631.031 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 231.016 | 328.800 | 807.192 | 987.715 | 224.381 / 633.035 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 3475.766 | 15.077 | 23.766 | 26.132 | 220.439 / 633.035 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 4829.462 | 20.121 | 37.172 | 44.678 | 388.828 / 633.422 | improvement |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.309 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.269 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.281 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.327 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.070 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.189 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.240 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.080 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.064 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.290 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.330 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.154 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.217 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.078 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.037 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.032 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.202 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.241 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.259 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.295 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.247 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.320 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.153 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.206 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.686 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.796 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.119 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.097 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.115 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.038 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.013 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.064 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.057 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.034 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.055 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 992.586 | 100.495 | 131.155 | 158.411 | — / — | possible-regression |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1717.171 | 115.360 | 127.542 | 127.586 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +24.4%, cpu_percent: +4.9%, duration_seconds: +0.3%, p50_ms: -16.3%, p95_ms: -20.8%, p99_ms: -48.2%, requests_per_second: +22.3%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +20.3%, cpu_percent: +6.2%, duration_seconds: -0.1%, p50_ms: -12.1%, p95_ms: -19.0%, p99_ms: -12.2%, requests_per_second: +20.2%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +20.7%, cpu_percent: +7.1%, duration_seconds: -0.1%, p50_ms: -16.7%, p95_ms: -25.5%, p99_ms: -15.2%, requests_per_second: +20.8%, rss_bytes: +0.5% |
| health_live | possible-regression | completed: -3.7%, cpu_percent: +0.9%, duration_seconds: -4.7%, p50_ms: +1.5%, p95_ms: +0.0%, p99_ms: +62.6%, requests_per_second: -1.8%, rss_bytes: +0.6% |
| health_live | stable | completed: -5.2%, cpu_percent: +0.2%, duration_seconds: -4.7%, p50_ms: -1.4%, p95_ms: +17.5%, p99_ms: +24.3%, requests_per_second: -0.5%, rss_bytes: +0.6% |
| health_live | stable | completed: +1.9%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -1.6%, p95_ms: +4.0%, p99_ms: +5.2%, requests_per_second: +1.8%, rss_bytes: +0.6% |
| health_live | stable | completed: -0.2%, cpu_percent: +0.1%, duration_seconds: -0.3%, p50_ms: -3.4%, p95_ms: +24.3%, p99_ms: +7.2%, requests_per_second: +2.0%, rss_bytes: +0.6% |
| home | improvement | completed: +10.7%, cpu_percent: +3.1%, duration_seconds: -0.0%, p50_ms: -8.0%, p95_ms: -10.9%, p99_ms: -11.2%, requests_per_second: +10.7%, rss_bytes: +0.5% |
| home | stable | completed: +19.2%, cpu_percent: +2.2%, duration_seconds: +4.9%, p50_ms: -12.4%, p95_ms: +17.8%, p99_ms: +12.1%, requests_per_second: +13.6%, rss_bytes: +0.6% |
| home | stable | completed: +7.4%, cpu_percent: +2.9%, duration_seconds: +0.1%, p50_ms: -11.2%, p95_ms: +1.6%, p99_ms: +0.9%, requests_per_second: +7.3%, rss_bytes: +0.7% |
| categories | stable | completed: +6.1%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -5.8%, p95_ms: -4.8%, p99_ms: +0.9%, requests_per_second: +6.1%, rss_bytes: +0.7% |
| categories | improvement | completed: +0.8%, cpu_percent: +0.1%, duration_seconds: -4.7%, p50_ms: -12.4%, p95_ms: -12.5%, p99_ms: -26.2%, requests_per_second: +5.8%, rss_bytes: +0.7% |
| categories | stable | completed: -0.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -1.5%, p95_ms: -0.7%, p99_ms: -12.1%, requests_per_second: -0.5%, rss_bytes: +0.7% |
| category | possible-regression | completed: +0.3%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -2.5%, p95_ms: +10.2%, p99_ms: +102.3%, requests_per_second: -2.3%, rss_bytes: +0.7% |
| category | possible-regression | completed: +0.2%, cpu_percent: -0.1%, duration_seconds: -4.6%, p50_ms: +3.0%, p95_ms: +12.3%, p99_ms: -13.8%, requests_per_second: +2.7%, rss_bytes: +0.7% |
| category | stable | completed: +2.4%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -0.8%, p95_ms: -5.0%, p99_ms: -1.1%, requests_per_second: +2.5%, rss_bytes: +0.7% |
| thread | stable | completed: +5.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -2.9%, p95_ms: -3.8%, p99_ms: -17.8%, requests_per_second: +3.4%, rss_bytes: +0.7% |
| thread | stable | completed: +1.9%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +17.0%, p95_ms: -3.0%, p99_ms: +9.2%, requests_per_second: +4.1%, rss_bytes: +0.7% |
| thread | improvement | completed: +6.6%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -7.5%, p95_ms: -25.7%, p99_ms: -18.0%, requests_per_second: +6.7%, rss_bytes: +0.7% |
| thread | improvement | completed: +2.2%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -2.0%, p95_ms: +0.1%, p99_ms: -11.3%, requests_per_second: +2.3%, rss_bytes: +0.4% |
| search | stable | completed: +5.5%, cpu_percent: +0.8%, duration_seconds: -0.0%, p50_ms: -8.2%, p95_ms: -19.2%, p99_ms: +0.9%, requests_per_second: +9.4%, rss_bytes: +0.4% |
| search | improvement | completed: +4.3%, cpu_percent: +2.7%, duration_seconds: -4.7%, p50_ms: +0.3%, p95_ms: -8.4%, p99_ms: -18.6%, requests_per_second: +4.3%, rss_bytes: +0.4% |
| search | stable | completed: +5.9%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -1.8%, p95_ms: -17.8%, p99_ms: -10.6%, requests_per_second: +5.9%, rss_bytes: +0.4% |
| search | stable | completed: -4.5%, cpu_percent: +4.7%, duration_seconds: +0.1%, p50_ms: -4.4%, p95_ms: -1.1%, p99_ms: +8.5%, requests_per_second: -4.6%, rss_bytes: +0.4% |
| cache_hit | improvement | completed: +3.3%, cpu_percent: -0.4%, duration_seconds: -4.7%, p50_ms: -4.3%, p95_ms: -13.5%, p99_ms: -49.9%, requests_per_second: +8.5%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +3.2%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -13.4%, p95_ms: -4.7%, p99_ms: -8.2%, requests_per_second: +5.0%, rss_bytes: +0.4% |
| cache_hit | possible-regression | completed: +0.5%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -3.0%, p95_ms: -8.3%, p99_ms: +13.8%, requests_per_second: +0.5%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +2.2%, cpu_percent: -1.5%, duration_seconds: +0.0%, p50_ms: -1.4%, p95_ms: -7.6%, p99_ms: -9.7%, requests_per_second: +2.3%, rss_bytes: +0.4% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -16.8%, duration_seconds: -2.6%, p50_ms: -9.6%, p95_ms: +2.6%, p99_ms: +3.7%, requests_per_second: +1.9%, rss_bytes: +0.4% |
| thread | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -10.0%, duration_seconds: -6.7%, p50_ms: -5.8%, p95_ms: -14.9%, p99_ms: -13.2%, requests_per_second: +6.8%, rss_bytes: +0.4% |
| thread | improvement | completed: +13.8%, cpu_percent: +27.4%, duration_seconds: -4.6%, p50_ms: -17.8%, p95_ms: -0.6%, p99_ms: +4.2%, requests_per_second: +19.3%, rss_bytes: +0.5% |
| thread | stable | completed: +12.1%, cpu_percent: +28.6%, duration_seconds: +0.1%, p50_ms: -40.3%, p95_ms: -5.1%, p99_ms: -14.2%, requests_per_second: +11.8%, rss_bytes: +0.4% |
| search | stable | completed: +6.2%, cpu_percent: +15.2%, duration_seconds: +0.5%, p50_ms: -31.2%, p95_ms: -4.7%, p99_ms: +7.6%, requests_per_second: +5.7%, rss_bytes: +0.5% |
| search | possible-regression | completed: -1.8%, cpu_percent: +8.3%, duration_seconds: -0.2%, p50_ms: -6.5%, p95_ms: -6.2%, p99_ms: +13.5%, requests_per_second: -1.5%, rss_bytes: +0.6% |
| cache_hit | possible-regression | completed: -15.1%, cpu_percent: -29.4%, duration_seconds: -0.1%, p50_ms: +68.3%, p95_ms: +14.3%, p99_ms: +15.8%, requests_per_second: -14.8%, rss_bytes: +0.6% |
| cache_hit | stable | completed: +0.4%, cpu_percent: -0.6%, duration_seconds: -0.2%, p50_ms: -2.0%, p95_ms: -12.0%, p99_ms: -9.6%, requests_per_second: +1.1%, rss_bytes: +0.5% |
| cache_miss | improvement | completed: +17.2%, cpu_percent: +5.5%, duration_seconds: -0.1%, p50_ms: -14.6%, p95_ms: -15.8%, p99_ms: +2.6%, requests_per_second: +17.3%, rss_bytes: +0.6% |
| cache_miss | improvement | completed: +24.6%, cpu_percent: +6.9%, duration_seconds: -0.0%, p50_ms: -18.3%, p95_ms: -28.9%, p99_ms: -23.5%, requests_per_second: +24.5%, rss_bytes: +0.6% |
| cache_miss | improvement | completed: +27.5%, cpu_percent: +6.1%, duration_seconds: +0.1%, p50_ms: -20.9%, p95_ms: -23.4%, p99_ms: -18.4%, requests_per_second: +27.3%, rss_bytes: +0.6% |
| health_live | stable | completed: -2.9%, cpu_percent: +0.4%, duration_seconds: -4.7%, p50_ms: -2.4%, p95_ms: -2.7%, p99_ms: -6.2%, requests_per_second: +2.0%, rss_bytes: +0.6% |
| health_live | stable | completed: +0.6%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: -0.1%, p95_ms: +2.5%, p99_ms: +8.3%, requests_per_second: +2.9%, rss_bytes: +0.6% |
| health_live | stable | completed: -0.4%, cpu_percent: -0.0%, duration_seconds: -4.6%, p50_ms: -2.8%, p95_ms: -1.2%, p99_ms: -12.3%, requests_per_second: +1.8%, rss_bytes: +0.6% |
| health_live | stable | completed: +2.7%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -1.2%, p95_ms: -3.2%, p99_ms: +9.3%, requests_per_second: +2.6%, rss_bytes: +0.6% |
| home | improvement | completed: +11.9%, cpu_percent: +3.0%, duration_seconds: -0.0%, p50_ms: -9.1%, p95_ms: -26.7%, p99_ms: -33.3%, requests_per_second: +11.8%, rss_bytes: +0.6% |
| home | improvement | completed: +17.9%, cpu_percent: +1.8%, duration_seconds: +0.1%, p50_ms: -10.0%, p95_ms: -12.6%, p99_ms: -11.9%, requests_per_second: +13.9%, rss_bytes: +0.7% |
| home | stable | completed: +15.4%, cpu_percent: +2.7%, duration_seconds: -0.1%, p50_ms: -6.2%, p95_ms: -11.5%, p99_ms: -15.3%, requests_per_second: +15.5%, rss_bytes: +0.7% |
| categories | stable | completed: +1.2%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -1.3%, p95_ms: +3.6%, p99_ms: +5.0%, requests_per_second: +1.2%, rss_bytes: +0.7% |
| categories | stable | completed: +5.3%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -2.5%, p95_ms: -5.7%, p99_ms: +2.1%, requests_per_second: +4.1%, rss_bytes: +0.7% |
| categories | stable | completed: -1.2%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +1.8%, p95_ms: -2.2%, p99_ms: -9.9%, requests_per_second: -1.1%, rss_bytes: +0.7% |
| category | improvement | completed: +4.2%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -3.2%, p95_ms: -4.1%, p99_ms: -46.3%, requests_per_second: +4.2%, rss_bytes: +0.7% |
| category | stable | completed: -0.5%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -3.5%, p95_ms: +1.6%, p99_ms: -5.4%, requests_per_second: -0.5%, rss_bytes: +0.7% |
| category | stable | completed: +2.9%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +2.7%, p95_ms: +15.8%, p99_ms: -3.0%, requests_per_second: +3.0%, rss_bytes: +0.7% |
| thread | possible-regression | completed: -1.9%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +0.4%, p95_ms: -0.5%, p99_ms: +75.2%, requests_per_second: -0.3%, rss_bytes: +0.7% |
| thread | stable | completed: +3.7%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +1.3%, p95_ms: -2.0%, p99_ms: -8.4%, requests_per_second: +2.4%, rss_bytes: +0.7% |
| thread | stable | completed: +4.0%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -3.7%, p95_ms: -6.1%, p99_ms: -4.6%, requests_per_second: +5.4%, rss_bytes: +0.7% |
| thread | improvement | completed: +1.1%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: +3.2%, p95_ms: -23.4%, p99_ms: -8.7%, requests_per_second: +1.1%, rss_bytes: +0.5% |
| search | stable | completed: -0.4%, cpu_percent: +2.5%, duration_seconds: -0.1%, p50_ms: -2.1%, p95_ms: +9.9%, p99_ms: +33.8%, requests_per_second: -0.4%, rss_bytes: +0.5% |
| search | stable | completed: -7.0%, cpu_percent: +8.8%, duration_seconds: +0.0%, p50_ms: +0.6%, p95_ms: +7.5%, p99_ms: +8.9%, requests_per_second: -7.0%, rss_bytes: +0.5% |
| search | stable | completed: +6.6%, cpu_percent: +3.7%, duration_seconds: +0.0%, p50_ms: +7.6%, p95_ms: -8.7%, p99_ms: -3.3%, requests_per_second: +6.5%, rss_bytes: +0.5% |
| search | stable | completed: -0.3%, cpu_percent: +2.3%, duration_seconds: +0.0%, p50_ms: -5.8%, p95_ms: +2.7%, p99_ms: +4.2%, requests_per_second: -0.2%, rss_bytes: +0.4% |
| cache_hit | confirmed-regression | completed: -4.4%, cpu_percent: +2.5%, duration_seconds: -4.7%, p50_ms: +3.8%, p95_ms: +1.2%, p99_ms: +80.3%, requests_per_second: -3.4%, rss_bytes: +0.4% |
| cache_hit | stable | completed: +2.8%, cpu_percent: -0.1%, duration_seconds: +4.9%, p50_ms: -1.1%, p95_ms: -2.7%, p99_ms: -14.6%, requests_per_second: +3.2%, rss_bytes: +0.4% |
| cache_hit | possible-regression | completed: -2.7%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +2.2%, p95_ms: +5.0%, p99_ms: +12.3%, requests_per_second: -2.7%, rss_bytes: +0.4% |
| cache_hit | stable | completed: -5.4%, cpu_percent: +0.4%, duration_seconds: -0.1%, p50_ms: +0.6%, p95_ms: +12.2%, p99_ms: -16.1%, requests_per_second: -5.4%, rss_bytes: +0.4% |
| thread | possible-regression | completed: -1.0%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +12.0%, p95_ms: +6.7%, p99_ms: +7.4%, requests_per_second: -1.0%, rss_bytes: +0.6% |
| thread | stable | completed: +2.0%, cpu_percent: -1.4%, duration_seconds: -0.0%, p50_ms: +0.7%, p95_ms: +3.4%, p99_ms: +4.0%, requests_per_second: -2.4%, rss_bytes: +0.4% |
| search | stable | completed: -4.8%, cpu_percent: -8.7%, duration_seconds: -0.1%, p50_ms: +28.7%, p95_ms: +12.0%, p99_ms: +3.0%, requests_per_second: -4.6%, rss_bytes: +0.6% |
| search | stable | completed: -9.9%, cpu_percent: +2.9%, duration_seconds: +0.1%, p50_ms: +33.3%, p95_ms: -18.8%, p99_ms: -17.5%, requests_per_second: -10.0%, rss_bytes: +0.7% |
| cache_hit | improvement | completed: +1.8%, cpu_percent: +4.8%, duration_seconds: +0.0%, p50_ms: -8.5%, p95_ms: +1.0%, p99_ms: -16.6%, requests_per_second: +1.7%, rss_bytes: +0.5% |
| cache_hit | improvement | completed: +13.8%, cpu_percent: +29.6%, duration_seconds: +0.1%, p50_ms: -22.9%, p95_ms: +8.0%, p99_ms: +15.1%, requests_per_second: +13.6%, rss_bytes: +0.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +9.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -1.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.5% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -5.3% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +11.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -23.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -0.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -9.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -9.9% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -31.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.0% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +33.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -9.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -26.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +22.2% |
| postgres-dispatch-noop | possible-regression | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +2.6%, messages_per_second: -2.6%, p50_ms: +0.0%, p95_ms: +21.0%, p99_ms: +42.9% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -4.5%, messages_per_second: +4.7%, p50_ms: -4.2%, p95_ms: -4.8%, p99_ms: -4.9% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -3.7%, cpu_percent: +0.5%, duration_seconds: -0.2%, p50_ms: +1.8%, p95_ms: +7.9%, p99_ms: +51.0%, requests_per_second: -2.1%, rss_bytes: +0.4% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.9%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -10.5%, p95_ms: -4.7%, p99_ms: -3.8%, requests_per_second: +3.0%, rss_bytes: +0.4% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +7.6%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -5.4%, p95_ms: -1.8%, p99_ms: -0.9%, requests_per_second: +7.4%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +4.6%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -3.4%, p95_ms: -4.8%, p99_ms: -44.5%, requests_per_second: +4.6%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +4.1%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +1.8%, p95_ms: -2.6%, p99_ms: -0.8%, requests_per_second: +4.1%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -0.7%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +0.6%, p95_ms: -1.6%, p99_ms: +11.8%, requests_per_second: -0.7%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +1.5%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +1.2%, p95_ms: -21.4%, p99_ms: +3.1%, requests_per_second: +1.4%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.0%, cpu_percent: +0.7%, duration_seconds: -0.0%, p50_ms: +2.1%, p95_ms: -13.8%, p99_ms: -18.9%, requests_per_second: -0.1%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: -3.3%, cpu_percent: -0.5%, duration_seconds: -4.5%, p50_ms: -8.3%, p95_ms: -19.3%, p99_ms: -17.3%, requests_per_second: -2.1%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.3%, cpu_percent: -0.2%, duration_seconds: -0.2%, p50_ms: -1.2%, p95_ms: +2.1%, p99_ms: -11.5%, requests_per_second: +0.5%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.1%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -1.7%, p95_ms: +3.4%, p99_ms: +22.0%, requests_per_second: +0.1%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +4.1%, cpu_percent: -0.1%, duration_seconds: +4.9%, p50_ms: -2.7%, p95_ms: +1.0%, p99_ms: +36.3%, requests_per_second: -0.7%, rss_bytes: +0.4% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -1.7%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +1.3%, p95_ms: +3.3%, p99_ms: +36.1%, requests_per_second: -1.6%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +6.6%, cpu_percent: +0.1%, duration_seconds: +5.0%, p50_ms: -0.2%, p95_ms: -10.7%, p99_ms: -52.9%, requests_per_second: +4.4%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -2.6%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: -6.1%, p95_ms: +9.0%, p99_ms: +0.2%, requests_per_second: -0.3%, rss_bytes: +0.4% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.5%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: +4.0%, p95_ms: +16.0%, p99_ms: +5.8%, requests_per_second: +1.5%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | confirmed-regression | completed: -3.2%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +0.5%, p95_ms: +1.0%, p99_ms: +78.0%, requests_per_second: -0.9%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -2.8%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -9.7%, p95_ms: +3.7%, p99_ms: +9.8%, requests_per_second: -1.5%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.0%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: -1.3%, p99_ms: +18.1%, requests_per_second: -1.0%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | confirmed-regression | completed: -4.9%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +6.0%, p95_ms: +2.6%, p99_ms: +31.2%, requests_per_second: -5.0%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -11.2%, cpu_percent: +1.6%, duration_seconds: -0.1%, p50_ms: +6.6%, p95_ms: +18.3%, p99_ms: +15.2%, requests_per_second: -11.1%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -12.4%, cpu_percent: +3.9%, duration_seconds: +0.0%, p50_ms: +5.2%, p95_ms: +11.8%, p99_ms: +41.2%, requests_per_second: -12.5%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -6.0%, cpu_percent: +5.5%, duration_seconds: +0.0%, p50_ms: +17.2%, p95_ms: +24.4%, p99_ms: +15.7%, requests_per_second: -5.9%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +4.2%, cpu_percent: -1.5%, duration_seconds: -0.0%, p50_ms: -9.2%, p95_ms: -8.9%, p99_ms: -15.8%, requests_per_second: +4.2%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | confirmed-regression | completed: -5.9%, cpu_percent: +2.9%, duration_seconds: +0.0%, p50_ms: +5.6%, p95_ms: +5.9%, p99_ms: +87.6%, requests_per_second: -5.9%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +3.6%, p95_ms: +9.2%, p99_ms: +3.7%, requests_per_second: -1.1%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.9%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +2.3%, p95_ms: -3.4%, p99_ms: +1.3%, requests_per_second: -1.9%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | possible-regression | completed: -6.6%, cpu_percent: +1.4%, duration_seconds: -0.1%, p50_ms: -1.0%, p95_ms: +21.2%, p99_ms: +16.3%, requests_per_second: -6.5%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -4.7%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: +6.2%, p95_ms: +1.4%, p99_ms: -3.5%, requests_per_second: -4.6%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.8%, cpu_percent: -1.1%, duration_seconds: -0.1%, p50_ms: -6.5%, p95_ms: +6.0%, p99_ms: +9.9%, requests_per_second: -1.5%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -14.3%, cpu_percent: -10.7%, duration_seconds: -0.4%, p50_ms: +33.5%, p95_ms: +9.0%, p99_ms: -9.1%, requests_per_second: -14.0%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -4.5%, cpu_percent: -6.0%, duration_seconds: +0.0%, p50_ms: +48.7%, p95_ms: -5.3%, p99_ms: -10.5%, requests_per_second: -4.6%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -3.7%, cpu_percent: +4.5%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: +7.9%, p99_ms: +10.1%, requests_per_second: -3.9%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -4.6%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: -3.0%, p95_ms: +6.4%, p99_ms: -7.2%, requests_per_second: -4.7%, rss_bytes: +0.3% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +39.7%, cpu_percent: +90.4%, duration_seconds: +0.0%, p50_ms: -19.2%, p95_ms: +32.7%, p99_ms: +26.2%, requests_per_second: +39.7%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +33.6%, cpu_percent: +91.9%, duration_seconds: +0.1%, p50_ms: -25.5%, p95_ms: +23.3%, p99_ms: +18.7%, requests_per_second: +33.2%, rss_bytes: +64.1% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +24.9%, cpu_percent: +75.0%, duration_seconds: +0.5%, p50_ms: -26.0%, p95_ms: +45.2%, p99_ms: +56.7%, requests_per_second: +24.3%, rss_bytes: +64.5% |
| search | workers=4 | 2 | 100 | improvement | completed: +27.2%, cpu_percent: +83.0%, duration_seconds: +0.2%, p50_ms: -49.0%, p95_ms: +2.1%, p99_ms: +10.6%, requests_per_second: +27.1%, rss_bytes: +65.0% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: +3.1%, cpu_percent: +5.3%, duration_seconds: +0.0%, p50_ms: +7.6%, p95_ms: +33.6%, p99_ms: -9.8%, requests_per_second: +3.2%, rss_bytes: +65.0% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +43.0%, cpu_percent: +95.5%, duration_seconds: -0.0%, p50_ms: -25.6%, p95_ms: +17.9%, p99_ms: +32.2%, requests_per_second: +43.0%, rss_bytes: +65.0% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +34.5%, cpu_percent: +92.0%, duration_seconds: +0.0%, p50_ms: -14.5%, p95_ms: +36.3%, p99_ms: +3.1%, requests_per_second: +34.6%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | confirmed-regression | completed: +44.4%, cpu_percent: +89.8%, duration_seconds: +0.1%, p50_ms: -34.2%, p95_ms: +27.4%, p99_ms: -0.6%, requests_per_second: +38.0%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | stable | completed: +14.0%, cpu_percent: +48.2%, duration_seconds: +0.1%, p50_ms: -15.7%, p95_ms: +27.2%, p99_ms: +23.2%, requests_per_second: +13.7%, rss_bytes: +64.3% |
| search | workers=4 | 2 | 100 | stable | completed: +16.6%, cpu_percent: +74.6%, duration_seconds: +0.2%, p50_ms: -16.4%, p95_ms: +6.1%, p99_ms: +17.6%, requests_per_second: +16.4%, rss_bytes: +64.8% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +1.2%, cpu_percent: +10.3%, duration_seconds: +0.0%, p50_ms: +5.7%, p95_ms: +49.3%, p99_ms: -1.9%, requests_per_second: +1.1%, rss_bytes: +64.8% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +46.0%, cpu_percent: +93.6%, duration_seconds: +0.1%, p50_ms: -27.2%, p95_ms: +3.5%, p99_ms: +5.5%, requests_per_second: +45.8%, rss_bytes: +64.9% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38770901552)
