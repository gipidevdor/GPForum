# GPForum continuous performance evidence

Commit: `b34fc8088ffb20011009d79cddbcd4b99c9df437` · mode: **main** · status: **failed**
Run: 38983398514 / attempt 1 · 2026-10-16T23:49:41.769614+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 7763 64-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: Compatible baseline. 55ff9335e5050b33511e6271a67d0101a616cc81

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 343.935 | 2.877 | 2.990 | 3.492 | 100.000 / 377.785 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 665.699 | 14.797 | 15.941 | 25.384 | 199.753 / 378.055 | improvement |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 647.501 | 74.818 | 92.915 | 133.243 | 200.779 / 380.055 | improvement |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1190.381 | 0.835 | 0.878 | 1.007 | 99.978 / 377.730 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2300.889 | 4.374 | 4.656 | 6.075 | 199.343 / 377.730 | stable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2305.806 | 21.142 | 24.221 | 28.568 | 200.920 / 378.598 | possible-regression |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2270.682 | 43.183 | 44.994 | 64.048 | 201.393 / 379.969 | stable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 147.933 | 6.717 | 7.783 | 9.908 | 79.036 / 380.648 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 266.500 | 36.862 | 43.936 | 64.900 | 160.069 / 381.254 | improvement |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 261.159 | 188.460 | 262.181 | 335.783 | 159.596 / 383.707 | improvement |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 901.357 | 1.098 | 1.155 | 1.219 | 99.507 / 383.707 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1740.177 | 5.625 | 5.937 | 8.226 | 199.284 / 383.707 | stable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1755.093 | 27.990 | 29.862 | 39.548 | 200.278 / 383.707 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 887.031 | 1.114 | 1.197 | 1.264 | 99.501 / 383.785 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1711.507 | 5.899 | 7.126 | 8.114 | 199.321 / 383.863 | stable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1727.321 | 30.038 | 32.550 | 42.068 | 200.802 / 383.863 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 873.218 | 1.134 | 1.199 | 1.257 | 99.512 / 383.988 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1691.280 | 5.848 | 6.148 | 10.027 | 199.862 / 383.988 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1695.103 | 28.999 | 30.084 | 40.182 | 199.927 / 383.988 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1692.966 | 57.777 | 59.413 | 98.665 | 199.895 / 387.109 | stable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 100.428 | 9.847 | 10.547 | 12.951 | 58.701 / 387.766 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 178.731 | 53.014 | 72.660 | 93.633 | 117.158 / 387.766 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 166.670 | 261.944 | 448.712 | 535.111 | 118.615 / 387.766 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 149.194 | 547.542 | 1023.615 | 1088.507 | 118.136 / 387.766 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 894.116 | 1.106 | 1.168 | 1.221 | 99.931 / 387.766 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1738.375 | 5.698 | 5.952 | 8.139 | 198.875 / 387.766 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1757.126 | 28.059 | 29.725 | 39.269 | 200.403 / 387.766 | stable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1721.677 | 56.593 | 60.085 | 93.676 | 198.878 / 387.766 | stable |
| http:health_live | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 1182.747 | 8.080 | 10.794 | 12.763 | 25.984 / 387.766 | stable |
| http:thread | mojo / Mojo::Reactor::EV / 2 / 10 | 3 | ok (indicative) | 885.983 | 11.081 | 15.210 | 16.492 | 36.657 / 388.109 | improvement |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2461.924 | 21.093 | 34.753 | 49.863 | 388.166 / 629.832 | stable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2452.742 | 38.284 | 53.984 | 72.196 | 388.818 / 633.723 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 220.975 | 171.521 | 516.614 | 624.401 | 213.863 / 635.004 | improvement |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 218.465 | 335.396 | 1007.903 | 1257.574 | 222.273 / 636.559 | improvement |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1710.391 | 33.066 | 35.609 | 56.071 | 208.012 / 636.559 | possible-regression |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2539.709 | 39.552 | 62.499 | 75.979 | 388.495 / 636.559 | stable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.564 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.492 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.540 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.787 | — | — / — | confirmed-regression |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.551 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.967 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.088 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.028 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.611 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.597 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.289 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.386 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.061 | — | — / — | stable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.442 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.462 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.457 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.587 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.602 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.565 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.314 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.360 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.859 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.293 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.189 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.201 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.211 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.053 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.049 | — | — / — | possible-regression |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.093 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.105 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.072 | — | — / — | stable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.095 | — | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 792.521 | 125.651 | 133.170 | 134.274 | — / — | stable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1293.021 | 152.536 | 179.411 | 181.099 | — / — | stable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |
| cache_miss | improvement | completed: +82.1%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -44.3%, p95_ms: -51.9%, p99_ms: -51.8%, requests_per_second: +81.6%, rss_bytes: +0.2% |
| cache_miss | improvement | completed: +73.0%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -41.4%, p95_ms: -52.3%, p99_ms: -40.9%, requests_per_second: +73.0%, rss_bytes: +0.3% |
| cache_miss | improvement | completed: +79.1%, cpu_percent: -0.4%, duration_seconds: +0.0%, p50_ms: -42.3%, p95_ms: -44.7%, p99_ms: -43.0%, requests_per_second: +79.3%, rss_bytes: +0.3% |
| health_live | stable | completed: -6.7%, cpu_percent: +0.5%, duration_seconds: -4.7%, p50_ms: +3.2%, p95_ms: +1.6%, p99_ms: +11.5%, requests_per_second: -2.8%, rss_bytes: +0.2% |
| health_live | stable | completed: -0.8%, cpu_percent: +0.3%, duration_seconds: -0.1%, p50_ms: +2.5%, p95_ms: +3.7%, p99_ms: +11.4%, requests_per_second: -0.7%, rss_bytes: +0.2% |
| health_live | possible-regression | completed: -1.7%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +0.1%, p95_ms: +10.1%, p99_ms: +11.4%, requests_per_second: -1.7%, rss_bytes: +0.2% |
| health_live | stable | completed: +2.3%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: -1.6%, p95_ms: -9.4%, p99_ms: -1.8%, requests_per_second: +2.2%, rss_bytes: +0.2% |
| home | improvement | completed: +104.1%, cpu_percent: -10.8%, duration_seconds: -0.1%, p50_ms: -52.7%, p95_ms: -49.9%, p99_ms: -39.1%, requests_per_second: +113.1%, rss_bytes: +0.2% |
| home | improvement | completed: +90.0%, cpu_percent: -9.8%, duration_seconds: -0.0%, p50_ms: -46.9%, p95_ms: -43.4%, p99_ms: -47.7%, requests_per_second: +90.0%, rss_bytes: +0.3% |
| home | improvement | completed: +110.0%, cpu_percent: -10.4%, duration_seconds: -0.0%, p50_ms: -46.0%, p95_ms: -56.9%, p99_ms: -50.8%, requests_per_second: +110.0%, rss_bytes: +0.3% |
| categories | stable | completed: -0.7%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +1.0%, p95_ms: +1.7%, p99_ms: +1.3%, requests_per_second: -1.1%, rss_bytes: +0.3% |
| categories | stable | completed: +3.5%, cpu_percent: +0.2%, duration_seconds: +0.1%, p50_ms: -3.1%, p95_ms: -2.2%, p99_ms: -10.8%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| categories | stable | completed: +2.8%, cpu_percent: +0.1%, duration_seconds: -0.0%, p50_ms: -2.7%, p95_ms: +0.1%, p99_ms: -1.6%, requests_per_second: +2.8%, rss_bytes: +0.3% |
| category | stable | completed: +3.5%, cpu_percent: +0.6%, duration_seconds: +0.1%, p50_ms: -3.8%, p95_ms: -2.1%, p99_ms: -5.1%, requests_per_second: +3.4%, rss_bytes: +0.3% |
| category | stable | completed: -1.3%, cpu_percent: +0.0%, duration_seconds: -4.6%, p50_ms: -0.9%, p95_ms: -1.5%, p99_ms: -19.0%, requests_per_second: +2.7%, rss_bytes: +0.3% |
| category | stable | completed: +4.1%, cpu_percent: +0.6%, duration_seconds: -0.1%, p50_ms: +0.8%, p95_ms: -5.6%, p99_ms: -9.2%, requests_per_second: +4.2%, rss_bytes: +0.3% |
| thread | stable | completed: +1.3%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -0.9%, p95_ms: -2.0%, p99_ms: -3.6%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| thread | stable | completed: +1.1%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -1.4%, p95_ms: -6.4%, p99_ms: -0.4%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| thread | stable | completed: +1.9%, cpu_percent: -0.8%, duration_seconds: +0.1%, p50_ms: -2.9%, p95_ms: -5.3%, p99_ms: -9.7%, requests_per_second: +1.9%, rss_bytes: +0.3% |
| thread | stable | completed: +4.8%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: -4.4%, p95_ms: -5.7%, p99_ms: -2.4%, requests_per_second: +4.8%, rss_bytes: +0.3% |
| search | improvement | completed: +54.6%, cpu_percent: -15.7%, duration_seconds: -0.0%, p50_ms: -35.1%, p95_ms: -37.6%, p99_ms: -35.8%, requests_per_second: +54.5%, rss_bytes: +0.3% |
| search | improvement | completed: +47.9%, cpu_percent: -16.8%, duration_seconds: +0.0%, p50_ms: -35.3%, p95_ms: -24.3%, p99_ms: -33.7%, requests_per_second: +48.1%, rss_bytes: +0.3% |
| search | improvement | completed: +67.8%, cpu_percent: -14.2%, duration_seconds: +0.0%, p50_ms: -35.5%, p95_ms: -37.8%, p99_ms: -33.6%, requests_per_second: +67.7%, rss_bytes: +0.3% |
| search | improvement | completed: +50.3%, cpu_percent: -16.0%, duration_seconds: +0.0%, p50_ms: -31.8%, p95_ms: -32.6%, p99_ms: -32.6%, requests_per_second: +50.2%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +5.2%, cpu_percent: -0.0%, duration_seconds: +4.9%, p50_ms: -0.3%, p95_ms: -3.3%, p99_ms: -27.3%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +2.3%, cpu_percent: +0.1%, duration_seconds: +4.8%, p50_ms: -1.8%, p95_ms: -7.0%, p99_ms: -12.5%, requests_per_second: +1.5%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +4.7%, cpu_percent: -0.1%, duration_seconds: +0.0%, p50_ms: -4.4%, p95_ms: -3.0%, p99_ms: -4.7%, requests_per_second: +4.6%, rss_bytes: +0.3% |
| cache_hit | stable | completed: +4.6%, cpu_percent: -1.4%, duration_seconds: +0.0%, p50_ms: -4.4%, p95_ms: -5.5%, p99_ms: -1.2%, requests_per_second: +4.6%, rss_bytes: +0.3% |
| health_live | stable | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +10.1%, duration_seconds: -1.2%, p50_ms: +1.1%, p95_ms: -5.7%, p99_ms: -0.4%, requests_per_second: +1.2%, rss_bytes: +0.3% |
| thread | improvement | completed: +0.0%, concurrency_effective: +0.0%, cpu_percent: +6.4%, duration_seconds: -5.0%, p50_ms: +7.1%, p95_ms: -10.6%, p99_ms: -11.2%, requests_per_second: +5.7%, rss_bytes: +0.3% |
| thread | stable | completed: +0.5%, cpu_percent: -0.0%, duration_seconds: -0.1%, p50_ms: -4.5%, p95_ms: +5.0%, p99_ms: +13.0%, requests_per_second: +0.6%, rss_bytes: +0.4% |
| thread | improvement | completed: +3.2%, cpu_percent: +0.3%, duration_seconds: -0.3%, p50_ms: +6.5%, p95_ms: -24.4%, p99_ms: -27.6%, requests_per_second: +3.6%, rss_bytes: +0.3% |
| search | improvement | completed: +32.0%, cpu_percent: -15.5%, duration_seconds: -0.1%, p50_ms: -10.8%, p95_ms: -28.6%, p99_ms: -29.0%, requests_per_second: +32.0%, rss_bytes: +0.2% |
| search | improvement | completed: +48.3%, cpu_percent: -17.2%, duration_seconds: -0.3%, p50_ms: -33.2%, p95_ms: -24.5%, p99_ms: -11.4%, requests_per_second: +50.1%, rss_bytes: +0.2% |
| cache_hit | possible-regression | completed: -27.5%, cpu_percent: -44.3%, duration_seconds: +0.0%, p50_ms: +52.4%, p95_ms: +2.0%, p99_ms: -3.0%, requests_per_second: -27.6%, rss_bytes: +0.2% |
| cache_hit | stable | completed: +4.0%, cpu_percent: +1.8%, duration_seconds: -0.1%, p50_ms: -2.8%, p95_ms: -1.6%, p99_ms: -17.1%, requests_per_second: +4.2%, rss_bytes: +0.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +17.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +10.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +8.2% |
| sql-plan-readers | confirmed-regression | actual_rows: +0.0%, sql_execution_ms: +48.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +1.3% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +2.3% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -6.7% |
| sql-plan-readers | stable | sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +22.7% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +11.8% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.1% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +4.6% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: -2.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +5.2% |
| sql-plan-readers | stable | actual_rows: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -11.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +6.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +5.8% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +31.2% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +11.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +17.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -1.6% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.1% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -6.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +1.1% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +22.6% |
| sql-plan-functions | possible-regression | nested_statements: +0.0%, sql_execution_ms: +14.3% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +12.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | possible-regression | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +145.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +0.0% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: -2.8% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +2.9% |
| sql-plan-functions | stable | actual_rows: +0.0%, nested_statements: +0.0%, sql_execution_ms: +3.3% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -0.8%, messages_per_second: +0.8%, p50_ms: -1.3%, p95_ms: -2.1%, p99_ms: -1.9% |
| postgres-dispatch-noop | stable | acknowledged: +0.0%, completed: +0.0%, duration_seconds: -0.4%, messages_per_second: +0.4%, p50_ms: -0.0%, p95_ms: +2.6%, p99_ms: +3.6% |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +45.2%, cpu_percent: +94.2%, duration_seconds: -0.0%, p50_ms: -27.3%, p95_ms: +15.5%, p99_ms: +24.1%, requests_per_second: +45.2%, rss_bytes: +64.0% |
| thread | workers=4 | 2 | 100 | improvement | completed: +45.1%, cpu_percent: +94.5%, duration_seconds: +0.1%, p50_ms: -33.7%, p95_ms: -9.1%, p99_ms: -26.8%, requests_per_second: +44.9%, rss_bytes: +63.7% |
| search | workers=4 | 2 | 50 | possible-regression | completed: +33.2%, cpu_percent: +80.3%, duration_seconds: +0.3%, p50_ms: -34.5%, p95_ms: +15.1%, p99_ms: +16.7%, requests_per_second: +32.6%, rss_bytes: +63.8% |
| search | workers=4 | 2 | 100 | possible-regression | completed: +46.8%, cpu_percent: +88.2%, duration_seconds: +0.2%, p50_ms: -38.7%, p95_ms: -1.5%, p99_ms: +15.5%, requests_per_second: +46.4%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -2.6%, cpu_percent: +3.8%, duration_seconds: +0.1%, p50_ms: +17.8%, p95_ms: +19.8%, p99_ms: +42.8%, requests_per_second: -2.7%, rss_bytes: +64.2% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +47.7%, cpu_percent: +95.3%, duration_seconds: +0.1%, p50_ms: -30.1%, p95_ms: +4.0%, p99_ms: -18.9%, requests_per_second: +47.5%, rss_bytes: +64.2% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38983398514)
