# GPForum continuous performance evidence

Commit: `c826fd0d6b11020f63653933251fd9eb8458cbcf` · mode: **main** · status: **failed**
Run: 38986436746 / attempt 1 · 2026-10-17T00:27:48.152955+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 55ff9335e5050b33511e6271a67d0101a616cc81

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 336.982 | 2.926 | 3.170 | 3.920 | 99.402 / 377.992 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 657.488 | 14.951 | 18.848 | 25.746 | 199.755 / 378.266 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 641.869 | 76.666 | 81.555 | 132.163 | 201.699 / 380.242 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1185.087 | 0.830 | 0.894 | 0.967 | 99.458 / 378.102 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2297.800 | 4.295 | 4.585 | 5.437 | 198.763 / 378.102 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2267.303 | 21.700 | 24.603 | 28.509 | 200.268 / 379.000 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2172.025 | 45.940 | 50.686 | 66.740 | 200.209 / 380.352 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 128.825 | 7.472 | 8.995 | 9.533 | 82.000 / 381.020 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 246.964 | 39.502 | 47.347 | 67.945 | 163.445 / 381.637 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 242.941 | 194.768 | 302.307 | 379.285 | 164.315 / 383.977 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 883.481 | 1.116 | 1.192 | 1.418 | 99.369 / 383.977 | confirmed-regression |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1725.395 | 5.674 | 6.138 | 9.016 | 198.782 / 383.977 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1716.072 | 28.504 | 31.003 | 44.696 | 200.723 / 383.977 | possible-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 871.606 | 1.122 | 1.195 | 1.874 | 98.944 / 384.008 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1673.213 | 5.895 | 6.460 | 8.200 | 199.250 / 384.008 | improvement |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1653.416 | 30.182 | 33.466 | 41.793 | 200.202 / 384.008 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 860.461 | 1.145 | 1.221 | 1.507 | 99.430 / 384.133 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1649.919 | 5.970 | 7.040 | 9.932 | 199.264 / 384.133 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1656.952 | 29.801 | 31.277 | 45.183 | 201.189 / 384.133 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1594.896 | 60.852 | 63.091 | 100.649 | 200.688 / 387.324 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 85.732 | 11.418 | 13.346 | 15.556 | 62.633 / 387.855 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 155.736 | 61.842 | 78.908 | 114.001 | 125.712 / 387.855 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 149.266 | 307.251 | 515.596 | 587.407 | 124.858 / 387.855 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 149.157 | 624.152 | 1110.505 | 1188.093 | 123.296 / 387.855 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 887.829 | 1.112 | 1.181 | 1.585 | 99.368 / 387.855 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1693.236 | 5.883 | 7.895 | 8.988 | 198.750 / 387.855 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1671.087 | 29.238 | 34.661 | 42.049 | 200.719 / 387.855 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1669.565 | 58.324 | 62.646 | 96.572 | 200.688 / 387.855 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1183.575 | 7.917 | 10.978 | 12.306 | 25.971 / 387.855 | stable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 813.278 | 12.121 | 15.764 | 18.459 | 33.057 / 388.199 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2415.168 | 17.231 | 35.865 | 42.939 | 384.991 / 629.648 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2371.231 | 40.101 | 55.734 | 76.488 | 386.551 / 633.719 | possible-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 207.099 | 192.733 | 519.585 | 765.357 | 229.834 / 635.031 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 201.276 | 458.217 | 1124.758 | 1216.705 | 231.188 / 636.715 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2074.324 | 24.448 | 38.673 | 41.947 | 300.215 / 636.715 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2412.850 | 40.955 | 54.278 | 67.367 | 386.699 / 636.715 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.512 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.426 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.499 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.573 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.111 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.578 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.065 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.114 | — | — / — | possible-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.116 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.507 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.560 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.286 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.353 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.070 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.403 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.464 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.461 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.564 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.463 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.512 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.328 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.548 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.935 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.322 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.189 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.167 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.192 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.055 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.072 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.106 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.108 | — | — / — | confirmed-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 773.345 | 128.912 | 139.989 | 143.622 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1241.802 | 159.728 | 191.876 | 193.459 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +80.7%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -43.3%, p95_ms: -49.0%, p99_ms: -45.8%, requests_per_second: +78.0%, rss_bytes: +0.3% |
| cache_miss | improvement | completed: +70.8%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -40.8%, p95_ms: -43.6%, p99_ms: -40.0%, requests_per_second: +70.8%, rss_bytes: +0.3% |
| cache_miss | improvement | completed: +77.6%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -40.9%, p95_ms: -51.5%, p99_ms: -43.5%, requests_per_second: +77.7%, rss_bytes: +0.3% |
| health_live | stable | completed: -5.5%, cpu_percent: +0.0%, duration_seconds: -4.7%, p50_ms: +2.6%, p95_ms: +3.5%, p99_ms: +7.1%, requests_per_second: -3.3%, rss_bytes: +0.3% |
| health_live | stable | completed: +3.9%, cpu_percent: +0.0%, duration_seconds: +4.8%, p50_ms: +0.6%, p95_ms: +2.1%, p99_ms: -0.3%, requests_per_second: -0.8%, rss_bytes: +0.3% |
| health_live | possible-regression | completed: -3.3%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +2.7%, p95_ms: +11.9%, p99_ms: +11.1%, requests_per_second: -3.3%, rss_bytes: +0.3% |
| health_live | stable | completed: -2.2%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +4.6%, p95_ms: +2.1%, p99_ms: +2.3%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| home | improvement | completed: +82.8%, cpu_percent: -7.4%, duration_seconds: -0.0%, p50_ms: -47.4%, p95_ms: -42.1%, p99_ms: -41.4%, requests_per_second: +85.6%, rss_bytes: +0.3% |
| home | improvement | completed: +76.2%, cpu_percent: -7.8%, duration_seconds: +0.1%, p50_ms: -43.0%, p95_ms: -39.0%, p99_ms: -45.2%, requests_per_second: +76.1%, rss_bytes: +0.4% |
| home | improvement | completed: +95.6%, cpu_percent: -7.8%, duration_seconds: +0.1%, p50_ms: -44.2%, p95_ms: -50.4%, p99_ms: -44.4%, requests_per_second: +95.4%, rss_bytes: +0.3% |
| categories | confirmed-regression | completed: -1.4%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +2.7%, p95_ms: +4.9%, p99_ms: +17.9%, requests_per_second: -3.1%, rss_bytes: +0.3% |
| categories | stable | completed: +4.2%, cpu_percent: -0.0%, duration_seconds: +4.9%, p50_ms: -2.3%, p95_ms: +1.1%, p99_ms: -2.2%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| categories | possible-regression | completed: +0.5%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: -0.9%, p95_ms: +3.9%, p99_ms: +11.2%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| category | stable | completed: +2.0%, cpu_percent: +0.1%, duration_seconds: +0.1%, p50_ms: -3.1%, p95_ms: -2.3%, p99_ms: +40.7%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| category | improvement | completed: -3.6%, cpu_percent: -0.0%, duration_seconds: -4.7%, p50_ms: -0.9%, p95_ms: -10.7%, p99_ms: -18.1%, requests_per_second: +0.4%, rss_bytes: +0.3% |
| category | stable | completed: -0.2%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +1.2%, p95_ms: -3.0%, p99_ms: -9.8%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| thread | possible-regression | completed: -0.2%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +0.1%, p95_ms: -0.2%, p99_ms: +15.6%, requests_per_second: -0.3%, rss_bytes: +0.3% |
| thread | stable | completed: -1.3%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +0.6%, p95_ms: +7.2%, p99_ms: -1.4%, requests_per_second: -1.4%, rss_bytes: +0.3% |
| thread | stable | completed: -0.4%, cpu_percent: -0.2%, duration_seconds: +0.1%, p50_ms: -0.3%, p95_ms: -1.6%, p99_ms: +1.5%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| thread | stable | completed: -1.3%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +0.7%, p95_ms: +0.1%, p99_ms: -0.5%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| search | improvement | completed: +33.1%, cpu_percent: -10.0%, duration_seconds: +0.2%, p50_ms: -24.7%, p95_ms: -21.0%, p99_ms: -22.9%, requests_per_second: +31.9%, rss_bytes: +0.3% |
| search | improvement | completed: +28.9%, cpu_percent: -10.7%, duration_seconds: +0.0%, p50_ms: -24.5%, p95_ms: -17.8%, p99_ms: -19.3%, requests_per_second: +29.0%, rss_bytes: +0.3% |
| search | improvement | completed: +50.3%, cpu_percent: -9.7%, duration_seconds: -0.0%, p50_ms: -24.4%, p95_ms: -28.6%, p99_ms: -27.1%, requests_per_second: +50.2%, rss_bytes: +0.3% |
| search | improvement | completed: +50.3%, cpu_percent: -12.4%, duration_seconds: +0.0%, p50_ms: -22.3%, p95_ms: -26.9%, p99_ms: -26.4%, requests_per_second: +50.2%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +0.9%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +0.3%, p95_ms: -2.2%, p99_ms: -5.6%, requests_per_second: +0.9%, rss_bytes: +0.3% |
| cache_hit | possible-regression | completed: -3.7%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: +1.4%, p95_ms: +23.3%, p99_ms: -3.3%, requests_per_second: -1.1%, rss_bytes: +0.3% |
| cache_hit | stable | completed: -0.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -0.4%, p95_ms: +13.1%, p99_ms: +2.0%, requests_per_second: -0.5%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +1.5%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -1.4%, p95_ms: -1.5%, p99_ms: +1.9%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +10.0%, duration_seconds: -2.3%, p50_ms: -0.9%, p95_ms: -4.1%, p99_ms: -4.0%, requests_per_second: +1.3%, rss_bytes: +0.3% |
| thread | possible-regression | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -4.1%, duration_seconds: +3.4%, p50_ms: +17.1%, p95_ms: -7.4%, p99_ms: -0.7%, requests_per_second: -3.0%, rss_bytes: +0.3% |
| thread | stable | completed: -1.1%, cpu_percent: -0.8%, duration_seconds: -0.1%, p50_ms: -22.0%, p95_ms: +8.3%, p99_ms: -2.7%, requests_per_second: -1.3%, rss_bytes: +0.3% |
| thread | possible-regression | completed: -0.2%, cpu_percent: -0.3%, duration_seconds: -0.3%, p50_ms: +11.5%, p95_ms: -21.9%, p99_ms: -23.3%, requests_per_second: +0.1%, rss_bytes: +0.3% |
| search | improvement | completed: +23.4%, cpu_percent: -9.2%, duration_seconds: -0.2%, p50_ms: +0.3%, p95_ms: -28.2%, p99_ms: -12.9%, requests_per_second: +23.7%, rss_bytes: +0.2% |
| search | improvement | completed: +36.5%, cpu_percent: -13.8%, duration_seconds: -0.1%, p50_ms: -8.7%, p95_ms: -15.7%, p99_ms: -14.3%, requests_per_second: +38.3%, rss_bytes: +0.2% |
| cache_hit | stable | completed: -12.1%, cpu_percent: -19.6%, duration_seconds: -0.1%, p50_ms: +12.7%, p95_ms: +10.7%, p99_ms: -27.5%, requests_per_second: -12.2%, rss_bytes: +0.2% |
| cache_hit | stable | completed: -1.1%, cpu_percent: +1.3%, duration_seconds: -0.1%, p50_ms: +0.7%, p95_ms: -14.5%, p99_ms: -26.5%, requests_per_second: -1.0%, rss_bytes: +0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +8.3% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +18.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.1% |
| sql-plan-readers | possible-regression | actual_rows: +0.0%, sql_execution_ms: +10.7% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +34.9% |
| sql-plan-readers | stable | sql_execution_ms: +16.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -10.0% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +66.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -4.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +3.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +20.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -7.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -19.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +7.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +22.8% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +49.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.8% |
| sql-plan-functions | possible-regression | nested_statements: +0.0%, sql_execution_ms: +14.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.7% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -15.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -22.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.9% |
| sql-plan-functions | confirmed-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +54.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.3% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +1.7%, messages_per_second: -1.7%, p50_ms: +1.2%, p95_ms: +3.0%, p99_ms: +4.9% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +3.7%, messages_per_second: -3.6%, p50_ms: +4.7%, p95_ms: +9.8%, p99_ms: +10.7% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | improvement | completed: +46.2%, cpu_percent: +91.4%, duration_seconds: +0.0%, p50_ms: -42.2%, p95_ms: +14.7%, p99_ms: -5.0%, requests_per_second: +45.8%, rss_bytes: +63.9% |
| thread | workers=4 | 2 | 100 | improvement | completed: +49.0%, cpu_percent: +92.6%, duration_seconds: +0.2%, p50_ms: -34.1%, p95_ms: -11.7%, p99_ms: -24.0%, requests_per_second: +48.7%, rss_bytes: +63.6% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +39.1%, cpu_percent: +84.1%, duration_seconds: +0.3%, p50_ms: -37.3%, p95_ms: +0.8%, p99_ms: +30.3%, requests_per_second: +38.7%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 100 | improvement | completed: +35.1%, cpu_percent: +87.5%, duration_seconds: +0.4%, p50_ms: -26.6%, p95_ms: +1.3%, p99_ms: +2.4%, requests_per_second: +34.9%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +24.1%, cpu_percent: +49.6%, duration_seconds: +0.0%, p50_ms: -16.4%, p95_ms: +11.6%, p99_ms: -0.2%, requests_per_second: +24.1%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +44.7%, cpu_percent: +92.7%, duration_seconds: +0.1%, p50_ms: -29.8%, p95_ms: -13.4%, p99_ms: -30.2%, requests_per_second: +44.5%, rss_bytes: +64.2% |

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

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38986436746)
