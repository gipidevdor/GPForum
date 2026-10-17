# GPForum continuous performance evidence

Commit: `d59dee6fefe60dec682246e54e913ca14bdf0ff6` · mode: **main** · status: **failed**
Run: 38950181866 / attempt 1 · 2026-10-16T18:49:09.969989+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. e8c48ca88901aabffc011eafce5c6ed13ca861d8

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 221.786 | 4.421 | 4.932 | 5.777 | 99.437 / 375.832 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 433.543 | 23.293 | 30.264 | 46.261 | 200.692 / 375.906 | confirmed-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 420.525 | 113.323 | 147.921 | 215.333 | 202.105 / 377.781 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1383.371 | 0.710 | 0.778 | 0.889 | 99.495 / 375.910 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2667.133 | 3.754 | 4.099 | 5.662 | 198.792 / 375.910 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2683.504 | 18.075 | 20.862 | 32.450 | 200.247 / 376.570 | confirmed-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2604.635 | 37.637 | 39.727 | 58.273 | 200.720 / 377.930 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 81.387 | 12.081 | 13.755 | 14.409 | 87.960 / 378.445 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 166.773 | 60.906 | 78.717 | 129.396 | 174.888 / 379.035 | confirmed-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 149.256 | 306.484 | 523.190 | 599.205 | 175.064 / 381.418 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 986.336 | 0.999 | 1.088 | 1.371 | 99.920 / 381.418 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1885.385 | 5.655 | 6.727 | 8.913 | 199.269 / 381.418 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1870.340 | 26.174 | 29.088 | 43.181 | 200.183 / 381.418 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 954.904 | 1.014 | 1.112 | 2.563 | 98.956 / 381.574 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1839.400 | 5.831 | 7.348 | 10.224 | 199.251 / 381.574 | confirmed-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1883.132 | 26.107 | 27.971 | 45.336 | 200.702 / 381.574 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 937.847 | 1.029 | 1.152 | 1.213 | 99.500 / 381.637 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1805.601 | 6.208 | 7.419 | 9.859 | 199.255 / 381.699 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1834.463 | 26.760 | 29.399 | 45.916 | 200.690 / 381.699 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1790.763 | 53.759 | 64.941 | 97.959 | 200.688 / 384.504 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 65.891 | 14.970 | 17.555 | 20.346 | 69.080 / 385.152 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 123.429 | 75.997 | 117.868 | 177.955 | 136.638 / 385.152 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 123.761 | 376.265 | 685.356 | 750.910 | 136.767 / 385.152 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.149 | 769.443 | 1433.310 | 1498.402 | 136.591 / 385.355 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 991.272 | 0.990 | 1.130 | 1.181 | 99.484 / 385.395 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1864.818 | 5.301 | 7.655 | 9.599 | 198.700 / 385.395 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1867.060 | 26.201 | 28.708 | 44.227 | 200.238 / 385.395 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1853.771 | 52.751 | 57.980 | 93.919 | 201.167 / 385.395 | confirmed-regression |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1281.772 | 7.661 | 9.871 | 10.795 | 21.223 / 385.395 | confirmed-regression |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 852.565 | 10.505 | 16.095 | 17.470 | 40.509 / 385.676 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2392.266 | 22.746 | 33.083 | 44.250 | 380.282 / 625.320 | confirmed-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2483.989 | 41.474 | 54.879 | 72.668 | 384.426 / 629.363 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 153.022 | 342.311 | 707.964 | 843.659 | 198.999 / 630.562 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 149.568 | 378.032 | 1158.331 | 1159.624 | 265.560 / 631.738 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2194.150 | 19.095 | 37.063 | 50.469 | 303.103 / 631.977 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2607.175 | 36.519 | 57.708 | 72.836 | 388.934 / 631.977 | confirmed-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.559 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.437 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.507 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.589 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.101 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 4.210 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.353 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.127 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.029 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.009 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.519 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.628 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.296 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.389 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.104 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.072 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.055 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.407 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.507 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.531 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.597 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.498 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.801 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.326 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.348 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.160 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.618 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.198 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.167 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.194 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.059 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.114 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.117 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.069 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.087 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 866.007 | 112.570 | 126.821 | 135.170 | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1367.040 | 144.043 | 160.938 | 161.523 | — / — | improvement |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | confirmed-regression | completed: -26.4%, cpu_percent: -0.1%, duration_seconds: +4.8%, p50_ms: +27.5%, p95_ms: +32.1%, p99_ms: +46.1%, requests_per_second: -22.7%, rss_bytes: -0.0% |
| cache_miss | confirmed-regression | completed: -24.8%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +36.1%, p95_ms: +33.2%, p99_ms: +79.6%, requests_per_second: -24.8%, rss_bytes: -0.0% |
| cache_miss | confirmed-regression | completed: -26.3%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +36.8%, p95_ms: +52.6%, p99_ms: +32.0%, requests_per_second: -26.2%, rss_bytes: -0.0% |
| health_live | confirmed-regression | completed: -23.1%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +30.3%, p95_ms: +29.9%, p99_ms: +24.7%, requests_per_second: -23.1%, rss_bytes: +0.0% |
| health_live | confirmed-regression | completed: -28.2%, cpu_percent: -0.3%, duration_seconds: -4.7%, p50_ms: +34.4%, p95_ms: +15.2%, p99_ms: +14.9%, requests_per_second: -24.7%, rss_bytes: +0.0% |
| health_live | confirmed-regression | completed: -25.6%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +33.1%, p95_ms: +42.0%, p99_ms: +53.2%, requests_per_second: -25.6%, rss_bytes: +0.0% |
| health_live | confirmed-regression | completed: -27.7%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +33.9%, p95_ms: +34.9%, p99_ms: +44.1%, requests_per_second: -27.8%, rss_bytes: +0.0% |
| home | confirmed-regression | completed: -34.5%, cpu_percent: +1.0%, duration_seconds: -0.0%, p50_ms: +51.4%, p95_ms: +54.5%, p99_ms: +47.6%, requests_per_second: -34.6%, rss_bytes: +0.0% |
| home | confirmed-regression | completed: -31.6%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: +55.3%, p95_ms: +42.2%, p99_ms: +67.8%, requests_per_second: -31.6%, rss_bytes: -0.0% |
| home | confirmed-regression | completed: -36.7%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: +52.2%, p95_ms: +71.1%, p99_ms: +57.4%, requests_per_second: -36.6%, rss_bytes: +0.0% |
| categories | confirmed-regression | completed: -25.4%, cpu_percent: +0.8%, duration_seconds: +0.0%, p50_ms: +35.0%, p95_ms: +34.0%, p99_ms: +60.9%, requests_per_second: -26.0%, rss_bytes: +0.0% |
| categories | confirmed-regression | completed: -28.5%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +46.5%, p95_ms: +40.1%, p99_ms: +44.0%, requests_per_second: -26.6%, rss_bytes: +0.0% |
| categories | confirmed-regression | completed: -29.4%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +41.5%, p95_ms: +49.8%, p99_ms: +30.0%, requests_per_second: -29.5%, rss_bytes: +0.0% |
| category | confirmed-regression | completed: -29.3%, cpu_percent: -0.6%, duration_seconds: -4.7%, p50_ms: +33.2%, p95_ms: +38.7%, p99_ms: +171.5%, requests_per_second: -26.5%, rss_bytes: +0.0% |
| category | confirmed-regression | completed: -28.6%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: +47.6%, p95_ms: +47.1%, p99_ms: +56.1%, requests_per_second: -26.6%, rss_bytes: +0.0% |
| category | confirmed-regression | completed: -26.0%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +35.8%, p95_ms: +27.6%, p99_ms: +49.5%, requests_per_second: -26.1%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: -25.3%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +33.6%, p95_ms: +37.6%, p99_ms: -10.1%, requests_per_second: -25.3%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: -27.8%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: +57.3%, p95_ms: +36.1%, p99_ms: +54.0%, requests_per_second: -27.8%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: -27.6%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +30.3%, p95_ms: +8.5%, p99_ms: +36.7%, requests_per_second: -27.6%, rss_bytes: -0.0% |
| thread | confirmed-regression | completed: -27.6%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +37.1%, p95_ms: +47.7%, p99_ms: +48.2%, requests_per_second: -27.6%, rss_bytes: +0.0% |
| search | confirmed-regression | completed: -6.4%, cpu_percent: +32.3%, duration_seconds: +0.0%, p50_ms: +41.3%, p95_ms: -84.8%, p99_ms: -87.9%, requests_per_second: -6.5%, rss_bytes: +0.0% |
| search | confirmed-regression | completed: -13.0%, cpu_percent: +25.6%, duration_seconds: -0.1%, p50_ms: +26.1%, p95_ms: -33.1%, p99_ms: -12.0%, requests_per_second: -12.9%, rss_bytes: +0.0% |
| search | possible-regression | completed: -23.2%, cpu_percent: +8.0%, duration_seconds: +0.0%, p50_ms: +42.2%, p95_ms: +40.1%, p99_ms: +32.3%, requests_per_second: -23.3%, rss_bytes: +0.0% |
| search | confirmed-regression | completed: -31.1%, cpu_percent: +16.0%, duration_seconds: -0.0%, p50_ms: +16.2%, p95_ms: +37.9%, p99_ms: +34.5%, requests_per_second: -31.1%, rss_bytes: +0.0% |
| cache_hit | confirmed-regression | completed: -27.1%, cpu_percent: -0.4%, duration_seconds: -4.7%, p50_ms: +31.5%, p95_ms: +39.9%, p99_ms: +22.8%, requests_per_second: -24.6%, rss_bytes: +0.0% |
| cache_hit | confirmed-regression | completed: -29.4%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +36.9%, p95_ms: +53.6%, p99_ms: +30.1%, requests_per_second: -26.7%, rss_bytes: +0.0% |
| cache_hit | confirmed-regression | completed: -26.6%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +35.7%, p95_ms: +39.7%, p99_ms: +27.5%, requests_per_second: -26.7%, rss_bytes: +0.0% |
| cache_hit | confirmed-regression | completed: -24.7%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +31.9%, p95_ms: +37.6%, p99_ms: +45.8%, requests_per_second: -24.7%, rss_bytes: +0.0% |
| health_live | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -14.3%, duration_seconds: +34.5%, p50_ms: +46.7%, p95_ms: +27.9%, p99_ms: +32.2%, requests_per_second: -25.1%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +26.4%, duration_seconds: +33.0%, p50_ms: +28.2%, p95_ms: +27.6%, p99_ms: +16.0%, requests_per_second: -24.8%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: -31.5%, cpu_percent: -1.7%, duration_seconds: +0.1%, p50_ms: +95.9%, p95_ms: +22.5%, p99_ms: +29.8%, requests_per_second: -29.9%, rss_bytes: +0.0% |
| thread | confirmed-regression | completed: -26.5%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +52.0%, p95_ms: +34.9%, p99_ms: +38.4%, requests_per_second: -26.5%, rss_bytes: +0.0% |
| search | possible-regression | completed: +15.8%, cpu_percent: +23.8%, duration_seconds: -0.1%, p50_ms: +47.2%, p95_ms: -28.2%, p99_ms: -30.6%, requests_per_second: +15.9%, rss_bytes: -0.0% |
| search | stable | completed: -10.7%, cpu_percent: +57.1%, duration_seconds: +0.1%, p50_ms: -11.8%, p95_ms: +8.3%, p99_ms: -1.9%, requests_per_second: -10.8%, rss_bytes: +0.1% |
| cache_hit | confirmed-regression | completed: -27.5%, cpu_percent: +0.3%, duration_seconds: +0.2%, p50_ms: +21.0%, p95_ms: +54.3%, p99_ms: +48.9%, requests_per_second: -27.5%, rss_bytes: +0.1% |
| cache_hit | confirmed-regression | completed: -25.7%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +49.3%, p95_ms: +33.3%, p99_ms: +51.2%, requests_per_second: -25.6%, rss_bytes: +0.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +33.1% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +26.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +30.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +29.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +29.9% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +30.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +35.1% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +28.8% |
| sql-plan-readers | confirmed-regression | sql_execution_ms: +33.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +31.8% |
| sql-plan-readers | confirmed-regression | sql_execution_ms: +28.6% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +50.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +34.1% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +33.6% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +32.1% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +33.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +35.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +41.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +27.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +44.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +42.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +30.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +39.5% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +26.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.5% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +27.5% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +31.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +32.5% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +30.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +25.6% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +14.3% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +26.0% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +34.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +29.4% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +96.6% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +77.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +32.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +27.9% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -55.7%, messages_per_second: +125.9%, p50_ms: -50.2%, p95_ms: -80.5%, p99_ms: -80.3% |
| postgres-dispatch-noop | improvement | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -59.1%, messages_per_second: +144.2%, p50_ms: -52.5%, p95_ms: -82.5%, p99_ms: -82.9% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | improvement | completed: +30.3%, cpu_percent: +89.5%, duration_seconds: +0.1%, p50_ms: -15.0%, p95_ms: +12.5%, p99_ms: -3.6%, requests_per_second: +30.4%, rss_bytes: +63.8% |
| thread | workers=4 | 2 | 100 | improvement | completed: +38.8%, cpu_percent: +91.6%, duration_seconds: +0.3%, p50_ms: -22.9%, p95_ms: -15.5%, p99_ms: -25.8%, requests_per_second: +38.7%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 50 | possible-regression | completed: +23.8%, cpu_percent: +45.5%, duration_seconds: +0.2%, p50_ms: -9.0%, p95_ms: +3.3%, p99_ms: +12.4%, requests_per_second: +23.6%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 100 | improvement | completed: +51.3%, cpu_percent: +94.4%, duration_seconds: +0.4%, p50_ms: -50.9%, p95_ms: -19.2%, p99_ms: -22.6%, requests_per_second: +50.9%, rss_bytes: +63.9% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: +17.2%, cpu_percent: +51.4%, duration_seconds: +0.2%, p50_ms: -27.1%, p95_ms: +29.1%, p99_ms: +14.1%, requests_per_second: +17.5%, rss_bytes: +64.0% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +40.8%, cpu_percent: +93.3%, duration_seconds: +0.2%, p50_ms: -30.8%, p95_ms: -0.5%, p99_ms: -22.4%, requests_per_second: +40.6%, rss_bytes: +64.0% |

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
- Shared runner and load generator share the host; values are comparative evidence, not production capacity.
- wrk uses closed-loop fixed connections and corrected latency histograms; in-flight concurrency is not measured.
- RSS is end-of-sample manager+workers residency, not peak; PostgreSQL and generator resources are separate.
- Cache hits/misses verified by probes; warmed worker-local SSR cache; cache miss uses harness-only expiry policy.
- Only anonymous GETs; migrations, seed and rate-limit accounting write only the dedicated disposable database.

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38950181866)
