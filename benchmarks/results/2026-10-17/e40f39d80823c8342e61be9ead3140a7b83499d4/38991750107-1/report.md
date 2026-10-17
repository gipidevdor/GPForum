# GPForum continuous performance evidence

Commit: `e40f39d80823c8342e61be9ead3140a7b83499d4` · mode: **main** · status: **failed**
Run: 38991750107 / attempt 1 · 2026-10-17T01:39:21.971793+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 7a8e1edd20dc51e0a52f9cf6d50012b6c8275bdf

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 338.336 | 2.898 | 3.058 | 3.441 | 99.478 / 378.059 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 665.490 | 14.720 | 16.285 | 26.001 | 199.360 / 378.340 | possible-regression |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 661.040 | 74.454 | 77.972 | 129.500 | 201.731 / 380.320 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1203.425 | 0.824 | 0.886 | 0.936 | 99.478 / 378.207 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2284.305 | 4.321 | 4.520 | 5.341 | 199.321 / 378.207 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2322.149 | 21.302 | 22.039 | 25.934 | 200.798 / 379.082 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2267.758 | 42.910 | 48.386 | 64.050 | 199.395 / 380.461 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 147.845 | 6.705 | 7.201 | 8.207 | 80.062 / 381.000 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 270.765 | 35.559 | 49.529 | 64.855 | 161.369 / 381.613 | possible-regression |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 249.906 | 186.553 | 272.608 | 338.474 | 161.432 / 383.988 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 884.349 | 1.116 | 1.187 | 1.250 | 99.508 / 383.988 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1740.312 | 5.717 | 5.953 | 8.240 | 198.913 / 383.988 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1752.727 | 28.041 | 30.309 | 39.964 | 199.829 / 383.988 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 874.374 | 1.135 | 1.180 | 1.524 | 100.003 / 384.004 | possible-regression |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1693.301 | 5.848 | 6.147 | 7.754 | 199.407 / 384.020 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1707.800 | 29.021 | 30.371 | 39.006 | 199.338 / 384.020 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 837.430 | 1.181 | 1.247 | 7.301 | 99.446 / 384.203 | possible-regression |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1674.103 | 5.901 | 6.545 | 10.019 | 198.892 / 384.266 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1675.527 | 29.237 | 31.858 | 45.960 | 200.296 / 384.266 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1668.863 | 58.714 | 60.797 | 98.696 | 199.805 / 387.379 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 97.447 | 10.018 | 11.574 | 13.016 | 59.196 / 387.781 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 164.381 | 58.288 | 83.008 | 104.959 | 119.314 / 388.086 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 154.350 | 275.624 | 504.511 | 591.585 | 120.891 / 388.086 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 152.426 | 458.702 | 1018.501 | 1166.342 | 119.122 / 388.152 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 864.500 | 1.141 | 1.209 | 1.626 | 102.906 / 388.152 | confirmed-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1698.425 | 5.800 | 6.074 | 7.751 | 199.421 / 388.152 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1699.246 | 28.795 | 31.752 | 43.218 | 201.776 / 388.152 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1669.406 | 58.055 | 61.832 | 96.036 | 200.208 / 388.152 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1159.448 | 8.218 | 11.348 | 13.232 | 23.623 / 388.152 | stable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 863.580 | 9.984 | 16.833 | 17.057 | 34.509 / 388.480 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2457.799 | 19.910 | 33.927 | 42.777 | 385.656 / 630.004 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2456.755 | 30.646 | 65.583 | 89.454 | 387.086 / 634.520 | confirmed-regression |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 212.154 | 153.263 | 504.702 | 728.531 | 223.954 / 635.949 | stable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 210.761 | 428.624 | 915.851 | 962.740 | 226.481 / 637.145 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2135.638 | 22.938 | 28.086 | 32.094 | 303.187 / 637.180 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2451.684 | 38.504 | 68.806 | 99.552 | 385.208 / 637.180 | confirmed-regression |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.514 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.425 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.455 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.649 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.520 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.004 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.100 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.026 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | improvement |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.514 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.556 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.270 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.375 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.063 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.049 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.394 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.454 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.495 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.558 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.485 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.479 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.413 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.412 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.224 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.319 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.194 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.164 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.187 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.072 | — | — / — | improvement |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.084 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.063 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.060 | — | — / — | improvement |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 786.669 | 126.025 | 140.709 | 142.260 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1276.914 | 156.959 | 175.547 | 180.438 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | possible-regression | completed: -4.9%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +3.7%, p95_ms: +6.4%, p99_ms: +14.2%, requests_per_second: -4.9%, rss_bytes: -0.0% |
| cache_miss | possible-regression | completed: -1.3%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -0.9%, p95_ms: -6.7%, p99_ms: +23.6%, requests_per_second: -1.2%, rss_bytes: -0.0% |
| cache_miss | stable | completed: -1.4%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +1.1%, p95_ms: -4.8%, p99_ms: +0.1%, requests_per_second: -1.3%, rss_bytes: -0.0% |
| health_live | stable | completed: +2.6%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -1.7%, p95_ms: -2.1%, p99_ms: -2.3%, requests_per_second: +2.5%, rss_bytes: +0.1% |
| health_live | improvement | completed: -1.2%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +1.3%, p95_ms: -13.1%, p99_ms: -3.9%, requests_per_second: -2.0%, rss_bytes: +0.1% |
| health_live | stable | completed: -1.5%, cpu_percent: +0.5%, duration_seconds: -0.1%, p50_ms: +1.7%, p95_ms: +0.7%, p99_ms: +0.4%, requests_per_second: -1.4%, rss_bytes: +0.1% |
| health_live | stable | completed: +0.0%, cpu_percent: -0.7%, duration_seconds: +0.0%, p50_ms: -1.1%, p95_ms: +3.4%, p99_ms: -7.2%, requests_per_second: -0.1%, rss_bytes: +0.1% |
| home | improvement | completed: -1.0%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +2.0%, p95_ms: -0.4%, p99_ms: -20.6%, requests_per_second: -1.0%, rss_bytes: +0.0% |
| home | possible-regression | completed: -2.0%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +2.0%, p95_ms: +18.5%, p99_ms: +6.7%, requests_per_second: -1.9%, rss_bytes: +0.0% |
| home | stable | completed: +0.8%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: +3.8%, p95_ms: -7.9%, p99_ms: -6.6%, requests_per_second: +0.8%, rss_bytes: +0.0% |
| categories | stable | completed: +0.2%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -0.6%, p95_ms: +0.8%, p99_ms: +2.4%, requests_per_second: +0.3%, rss_bytes: +0.0% |
| categories | stable | completed: +0.7%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: -0.1%, p95_ms: -1.3%, p99_ms: -5.0%, requests_per_second: +0.8%, rss_bytes: +0.0% |
| categories | stable | completed: +0.3%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: -1.4%, p95_ms: +3.1%, p99_ms: +1.6%, requests_per_second: +0.3%, rss_bytes: +0.0% |
| category | possible-regression | completed: +0.7%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -0.7%, p95_ms: -1.7%, p99_ms: +23.5%, requests_per_second: +0.8%, rss_bytes: +0.0% |
| category | stable | completed: -1.4%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +1.2%, p95_ms: +2.0%, p99_ms: -14.5%, requests_per_second: -1.4%, rss_bytes: +0.0% |
| category | stable | completed: -2.1%, cpu_percent: -1.0%, duration_seconds: +0.0%, p50_ms: +2.0%, p95_ms: +0.1%, p99_ms: -4.8%, requests_per_second: -1.9%, rss_bytes: +0.0% |
| thread | possible-regression | completed: -2.8%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -0.1%, p95_ms: +0.3%, p99_ms: +404.2%, requests_per_second: -0.8%, rss_bytes: +0.0% |
| thread | stable | completed: +0.4%, cpu_percent: -0.5%, duration_seconds: +0.0%, p50_ms: -1.3%, p95_ms: -9.1%, p99_ms: +12.6%, requests_per_second: -0.1%, rss_bytes: +0.0% |
| thread | stable | completed: -0.1%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +0.7%, p95_ms: +1.4%, p99_ms: +9.7%, requests_per_second: -0.1%, rss_bytes: +0.0% |
| thread | stable | completed: -0.1%, cpu_percent: +0.2%, duration_seconds: +0.0%, p50_ms: +0.1%, p95_ms: -4.5%, p99_ms: +3.5%, requests_per_second: -0.0%, rss_bytes: +0.0% |
| search | stable | completed: -2.0%, cpu_percent: +0.8%, duration_seconds: -0.1%, p50_ms: +0.2%, p95_ms: -0.6%, p99_ms: +1.1%, requests_per_second: -0.7%, rss_bytes: -0.0% |
| search | stable | completed: -4.4%, cpu_percent: -1.6%, duration_seconds: +0.1%, p50_ms: +3.2%, p95_ms: +16.1%, p99_ms: +1.4%, requests_per_second: -4.4%, rss_bytes: +0.0% |
| search | stable | completed: -1.0%, cpu_percent: +1.9%, duration_seconds: +0.0%, p50_ms: -2.9%, p95_ms: +9.7%, p99_ms: +10.8%, requests_per_second: -0.8%, rss_bytes: +0.0% |
| search | stable | completed: +2.3%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: -16.4%, p95_ms: +4.1%, p99_ms: +9.8%, requests_per_second: +2.1%, rss_bytes: +0.0% |
| cache_hit | confirmed-regression | completed: -0.7%, cpu_percent: +2.4%, duration_seconds: +0.0%, p50_ms: -0.9%, p95_ms: +1.1%, p99_ms: +30.5%, requests_per_second: -0.8%, rss_bytes: +0.0% |
| cache_hit | stable | completed: -1.1%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: +1.4%, p95_ms: +1.7%, p99_ms: -3.7%, requests_per_second: -1.1%, rss_bytes: +0.0% |
| cache_hit | stable | completed: -3.3%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +2.5%, p95_ms: +8.6%, p99_ms: +6.6%, requests_per_second: -3.2%, rss_bytes: +0.0% |
| cache_hit | stable | completed: -1.5%, cpu_percent: +0.4%, duration_seconds: +0.1%, p50_ms: +1.5%, p95_ms: +4.2%, p99_ms: +3.2%, requests_per_second: -1.5%, rss_bytes: +0.0% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -0.0%, duration_seconds: +7.5%, p50_ms: +13.8%, p95_ms: +6.5%, p99_ms: +14.4%, requests_per_second: -7.7%, rss_bytes: +0.0% |
| thread | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: -5.9%, duration_seconds: -4.9%, p50_ms: -15.4%, p95_ms: +6.3%, p99_ms: -0.6%, requests_per_second: +5.3%, rss_bytes: +0.0% |
| thread | improvement | completed: +1.5%, cpu_percent: +1.0%, duration_seconds: -0.2%, p50_ms: -18.9%, p95_ms: +2.8%, p99_ms: -23.2%, requests_per_second: +1.7%, rss_bytes: +0.1% |
| thread | confirmed-regression | completed: +0.2%, cpu_percent: +0.5%, duration_seconds: +0.1%, p50_ms: -25.8%, p95_ms: +16.0%, p99_ms: +19.6%, requests_per_second: +0.2%, rss_bytes: +0.1% |
| search | stable | completed: +1.4%, cpu_percent: +1.4%, duration_seconds: +0.1%, p50_ms: -2.5%, p95_ms: -0.4%, p99_ms: -1.4%, requests_per_second: +1.4%, rss_bytes: +0.1% |
| search | stable | completed: -1.2%, cpu_percent: -0.2%, duration_seconds: -0.2%, p50_ms: +6.8%, p95_ms: +9.4%, p99_ms: +14.8%, requests_per_second: -1.0%, rss_bytes: +0.1% |
| cache_hit | improvement | completed: -1.9%, cpu_percent: +0.9%, duration_seconds: -0.4%, p50_ms: +18.0%, p95_ms: -16.7%, p99_ms: -10.0%, requests_per_second: +0.9%, rss_bytes: +0.1% |
| cache_hit | confirmed-regression | completed: -3.1%, cpu_percent: -0.5%, duration_seconds: -0.1%, p50_ms: +1.2%, p95_ms: +35.0%, p99_ms: +53.7%, requests_per_second: -3.0%, rss_bytes: +0.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +15.9% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.5% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -7.4% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.6% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -3.7% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | improvement | actual_rows: +0.0%, sql_execution_ms: -25.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +7.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +6.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -10.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.3% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -25.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -47.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +12.5% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.6% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +11.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -5.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -7.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -15.0% |
| sql-plan-functions | stable | nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -3.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.9% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -19.0% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -42.4% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -22.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -25.9% |
| sql-plan-functions | improvement | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -37.5% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +4.9%, messages_per_second: -4.7%, p50_ms: +5.2%, p95_ms: +8.8%, p99_ms: +7.9% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: +4.6%, messages_per_second: -4.4%, p50_ms: +3.9%, p95_ms: +6.9%, p99_ms: +9.5% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | improvement | completed: +46.8%, cpu_percent: +92.5%, duration_seconds: +0.0%, p50_ms: -31.9%, p95_ms: +6.5%, p99_ms: -6.9%, requests_per_second: +46.7%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +47.5%, cpu_percent: +93.7%, duration_seconds: +0.1%, p50_ms: -47.8%, p95_ms: +7.9%, p99_ms: -9.4%, requests_per_second: +47.2%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 50 | improvement | completed: +37.9%, cpu_percent: +85.3%, duration_seconds: +0.2%, p50_ms: -44.4%, p95_ms: +0.0%, p99_ms: +23.1%, requests_per_second: +37.5%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | improvement | completed: +38.2%, cpu_percent: +90.1%, duration_seconds: +0.1%, p50_ms: -6.6%, p95_ms: -10.1%, p99_ms: -17.5%, requests_per_second: +38.3%, rss_bytes: +64.1% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +25.6%, cpu_percent: +50.3%, duration_seconds: -0.0%, p50_ms: -20.3%, p95_ms: -11.5%, p99_ms: -25.7%, requests_per_second: +25.7%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | possible-regression | completed: +46.8%, cpu_percent: +92.4%, duration_seconds: -0.0%, p50_ms: -33.7%, p95_ms: +11.3%, p99_ms: +3.7%, requests_per_second: +46.9%, rss_bytes: +64.2% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38991750107)
