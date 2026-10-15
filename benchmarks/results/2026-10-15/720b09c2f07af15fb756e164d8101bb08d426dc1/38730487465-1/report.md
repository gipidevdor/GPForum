# GPForum continuous performance evidence

Commit: `720b09c2f07af15fb756e164d8101bb08d426dc1` · mode: **main** · status: **ok**
Run: 38730487465 / attempt 1 · 2026-10-15T11:53:18.881437+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V45 96-Core Processor.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"106fdee0ce1639d8b80ec244444ef79168a4bb8b72bc428503b5e8233

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 430.243 | 2.207 | 2.958 | 4.163 | 100.060 / 369.160 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 866.242 | 13.038 | 14.252 | 16.898 | 199.014 / 369.293 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 868.233 | 57.548 | 65.184 | 93.951 | 201.123 / 371.113 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 2422.687 | 0.404 | 0.454 | 0.538 | 99.161 / 369.285 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 4722.126 | 2.062 | 2.306 | 3.108 | 199.108 / 369.285 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 4966.173 | 9.978 | 11.176 | 14.895 | 199.458 / 369.930 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 4916.101 | 19.665 | 24.142 | 29.192 | 199.923 / 371.250 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 210.958 | 4.670 | 4.994 | 5.671 | 84.695 / 371.508 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 400.562 | 27.956 | 33.293 | 39.434 | 170.579 / 372.352 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 386.080 | 122.513 | 162.573 | 225.903 | 172.149 / 374.672 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1865.641 | 0.525 | 0.573 | 0.827 | 99.602 / 374.672 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3595.758 | 2.765 | 3.436 | 4.406 | 199.600 / 374.672 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3628.484 | 13.619 | 14.408 | 17.697 | 199.050 / 374.672 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1799.670 | 0.547 | 0.592 | 0.669 | 99.585 / 374.828 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3508.772 | 2.726 | 3.096 | 4.252 | 199.179 / 374.828 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3656.290 | 13.578 | 14.910 | 20.835 | 200.097 / 374.828 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1737.542 | 0.570 | 0.622 | 0.653 | 99.614 / 374.953 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3424.223 | 3.323 | 4.138 | 4.643 | 199.143 / 374.953 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3587.774 | 13.748 | 14.780 | 15.566 | 199.888 / 374.953 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3544.141 | 27.790 | 30.064 | 39.112 | 201.228 / 377.758 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 129.035 | 7.238 | 9.711 | 11.410 | 63.519 / 378.289 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 261.203 | 41.741 | 51.736 | 69.798 | 123.478 / 378.289 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 249.710 | 193.206 | 315.938 | 374.320 | 125.638 / 378.289 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 249.192 | 394.750 | 650.725 | 741.694 | 125.632 / 378.289 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1824.902 | 0.535 | 0.599 | 0.662 | 100.033 / 378.289 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 3518.193 | 3.159 | 3.563 | 5.222 | 199.094 / 378.289 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 3671.168 | 13.396 | 14.564 | 15.471 | 200.029 / 378.289 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 3639.552 | 27.070 | 29.631 | 34.688 | 200.792 / 378.289 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 2687.657 | 3.203 | 5.629 | 6.073 | 24.730 / 378.289 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1900.558 | 4.974 | 7.426 | 9.127 | 34.275 / 378.586 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 4762.644 | 10.617 | 19.962 | 27.040 | 385.355 / 615.129 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 4574.982 | 21.358 | 35.790 | 45.709 | 387.965 / 619.559 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 245.736 | 142.634 | 465.711 | 672.883 | 233.042 / 621.707 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 234.898 | 243.495 | 786.495 | 898.586 | 238.262 / 623.887 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 3309.179 | 12.094 | 21.961 | 28.985 | 207.197 / 623.891 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 4448.814 | 23.086 | 39.967 | 41.977 | 385.499 / 623.891 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 412.320 | 2.378 | 2.739 | 3.195 | 99.475 / 370.211 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 780.912 | 12.518 | 15.392 | 21.107 | 199.133 / 370.312 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 761.491 | 61.584 | 71.801 | 124.211 | 201.740 / 372.207 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 2438.663 | 0.403 | 0.447 | 0.469 | 100.008 / 370.355 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 4774.361 | 2.053 | 2.576 | 3.390 | 199.449 / 370.355 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 4876.441 | 9.999 | 11.190 | 15.837 | 198.959 / 371.098 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 4712.962 | 20.688 | 25.830 | 31.139 | 199.927 / 372.441 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 201.729 | 4.787 | 5.792 | 7.365 | 86.596 / 372.965 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 305.127 | 32.874 | 47.556 | 63.614 | 170.546 / 373.445 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 321.343 | 152.374 | 224.408 | 293.705 | 171.578 / 375.742 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1899.752 | 0.517 | 0.574 | 0.645 | 100.018 / 375.742 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3495.136 | 2.894 | 4.263 | 5.566 | 199.368 / 375.742 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3540.568 | 13.888 | 15.210 | 21.996 | 199.906 / 375.742 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1782.608 | 0.554 | 0.597 | 0.713 | 99.572 / 375.883 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3416.447 | 2.880 | 3.560 | 4.994 | 199.080 / 375.883 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3397.917 | 14.380 | 16.109 | 22.480 | 198.901 / 375.883 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1804.659 | 0.549 | 0.596 | 0.642 | 99.503 / 376.008 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3419.408 | 2.856 | 3.788 | 4.718 | 199.132 / 376.008 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3385.621 | 14.397 | 16.263 | 26.330 | 199.549 / 376.008 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3370.716 | 29.357 | 33.212 | 48.642 | 200.816 / 379.027 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 118.927 | 8.283 | 9.599 | 11.270 | 65.735 / 379.570 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 200.502 | 55.543 | 83.833 | 119.365 | 131.766 / 379.891 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 197.716 | 237.823 | 412.631 | 481.446 | 133.251 / 379.891 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 199.180 | 448.174 | 876.975 | 948.711 | 133.413 / 379.891 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1843.396 | 0.537 | 0.582 | 0.666 | 101.015 / 379.891 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 3597.487 | 2.942 | 3.457 | 4.463 | 198.935 / 379.891 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 3508.821 | 13.971 | 20.193 | 25.409 | 199.867 / 379.891 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 3389.025 | 26.269 | 34.212 | 46.246 | 200.793 / 379.891 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4035.565 | 14.709 | 19.806 | 27.127 | 298.054 / 616.910 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 4697.823 | 23.835 | 36.771 | 44.866 | 378.029 / 621.332 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 243.555 | 186.622 | 424.163 | 508.305 | 223.083 / 622.828 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 223.900 | 267.116 | 1060.874 | 1242.800 | 197.160 / 625.883 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 4126.148 | 9.319 | 23.362 | 27.934 | 307.861 / 626.250 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 4833.503 | 24.877 | 34.991 | 42.615 | 380.336 / 626.426 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.294 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.257 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.274 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.325 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.070 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.088 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.233 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.076 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.065 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.017 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.250 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.291 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.149 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.183 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.056 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.030 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.029 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.180 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.303 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.241 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.303 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.249 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.284 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.161 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.197 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.627 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.773 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.110 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.109 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.036 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.013 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.065 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.035 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.042 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 1096.113 | 91.237 | 105.292 | 106.669 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1764.593 | 111.937 | 123.903 | 124.595 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -4.2%, cpu_percent: -0.6%, duration_seconds: -0.0%, p50_ms: +7.7%, p95_ms: -7.4%, p99_ms: -23.3%, requests_per_second: -4.2%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -5.4%, cpu_percent: +0.1%, duration_seconds: +4.7%, p50_ms: -4.0%, p95_ms: +8.0%, p99_ms: +24.9%, requests_per_second: -9.9%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -12.1%, cpu_percent: +0.3%, duration_seconds: +0.0%, p50_ms: +7.0%, p95_ms: +10.2%, p99_ms: +32.2%, requests_per_second: -12.3%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.6%, cpu_percent: +0.9%, duration_seconds: +0.0%, p50_ms: -0.2%, p95_ms: -1.5%, p99_ms: -12.8%, requests_per_second: +0.7%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.2%, cpu_percent: +0.2%, duration_seconds: -4.6%, p50_ms: -0.4%, p95_ms: +11.7%, p99_ms: +9.1%, requests_per_second: +1.1%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.9%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: +0.2%, p95_ms: +0.1%, p99_ms: +6.3%, requests_per_second: -1.8%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -4.1%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +5.2%, p95_ms: +7.0%, p99_ms: +6.7%, requests_per_second: -4.1%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | possible-regression | completed: -4.3%, cpu_percent: +2.2%, duration_seconds: +0.1%, p50_ms: +2.5%, p95_ms: +16.0%, p99_ms: +29.9%, requests_per_second: -4.4%, rss_bytes: +0.4% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -23.8%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +17.6%, p95_ms: +42.8%, p99_ms: +61.3%, requests_per_second: -23.8%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -16.7%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +24.4%, p95_ms: +38.0%, p99_ms: +30.0%, requests_per_second: -16.8%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.4%, cpu_percent: +0.4%, duration_seconds: +0.0%, p50_ms: -1.5%, p95_ms: +0.2%, p99_ms: -22.0%, requests_per_second: +1.8%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -2.8%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +4.7%, p95_ms: +24.1%, p99_ms: +26.3%, requests_per_second: -2.8%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -2.5%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +2.0%, p95_ms: +5.6%, p99_ms: +24.3%, requests_per_second: -2.4%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.0%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +1.3%, p95_ms: +0.8%, p99_ms: +6.6%, requests_per_second: -0.9%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -7.2%, cpu_percent: -0.1%, duration_seconds: -4.7%, p50_ms: +5.6%, p95_ms: +15.0%, p99_ms: +17.5%, requests_per_second: -2.6%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -2.6%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +5.9%, p95_ms: +8.0%, p99_ms: +7.9%, requests_per_second: -7.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.9%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: -3.7%, p95_ms: -4.2%, p99_ms: -1.7%, requests_per_second: +3.9%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.6%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -14.1%, p95_ms: -8.5%, p99_ms: +1.6%, requests_per_second: -0.1%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -5.7%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: +4.7%, p95_ms: +10.0%, p99_ms: +69.2%, requests_per_second: -5.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | confirmed-regression | completed: -4.9%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: +5.6%, p95_ms: +10.5%, p99_ms: +24.4%, requests_per_second: -4.9%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -12.2%, cpu_percent: +3.5%, duration_seconds: -0.0%, p50_ms: +14.4%, p95_ms: -1.2%, p99_ms: -1.2%, requests_per_second: -7.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -23.1%, cpu_percent: +6.7%, duration_seconds: +0.1%, p50_ms: +33.1%, p95_ms: +62.0%, p99_ms: +71.0%, requests_per_second: -23.2%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -20.8%, cpu_percent: +6.1%, duration_seconds: -0.0%, p50_ms: +23.1%, p95_ms: +30.6%, p99_ms: +28.6%, requests_per_second: -20.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -20.2%, cpu_percent: +6.2%, duration_seconds: +0.1%, p50_ms: +13.5%, p95_ms: +34.8%, p99_ms: +27.9%, requests_per_second: -20.1%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +1.0%, cpu_percent: +1.0%, duration_seconds: -0.0%, p50_ms: +0.4%, p95_ms: -2.8%, p99_ms: +0.6%, requests_per_second: +1.0%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +7.3%, cpu_percent: -0.1%, duration_seconds: +4.9%, p50_ms: -6.9%, p95_ms: -3.0%, p99_ms: -14.5%, requests_per_second: +2.3%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -0.1%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +4.3%, p95_ms: +38.6%, p99_ms: +64.2%, requests_per_second: -4.4%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -7.0%, cpu_percent: +0.0%, duration_seconds: -0.1%, p50_ms: -3.0%, p95_ms: +15.5%, p99_ms: +33.3%, requests_per_second: -6.9%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -17.6%, cpu_percent: -22.7%, duration_seconds: -0.0%, p50_ms: +38.5%, p95_ms: -0.8%, p99_ms: +0.3%, requests_per_second: -15.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +2.7%, cpu_percent: -2.6%, duration_seconds: -0.0%, p50_ms: +11.6%, p95_ms: +2.7%, p99_ms: -1.8%, requests_per_second: +2.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -0.8%, cpu_percent: -4.3%, duration_seconds: -0.2%, p50_ms: +30.8%, p95_ms: -8.9%, p99_ms: -24.5%, requests_per_second: -0.9%, rss_bytes: +0.2% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -4.9%, cpu_percent: -17.3%, duration_seconds: -0.1%, p50_ms: +9.7%, p95_ms: +34.9%, p99_ms: +38.3%, requests_per_second: -4.7%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +19.1%, cpu_percent: +48.6%, duration_seconds: -4.4%, p50_ms: -22.9%, p95_ms: +6.4%, p99_ms: -3.6%, requests_per_second: +24.7%, rss_bytes: +0.4% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +8.6%, cpu_percent: -1.3%, duration_seconds: -0.0%, p50_ms: +7.8%, p95_ms: -12.4%, p99_ms: +1.5%, requests_per_second: +8.6%, rss_bytes: +0.4% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +36.5%, cpu_percent: +92.8%, duration_seconds: -0.0%, p50_ms: -22.8%, p95_ms: +35.1%, p99_ms: +73.7%, requests_per_second: +32.7%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +29.3%, cpu_percent: +92.8%, duration_seconds: -0.0%, p50_ms: -23.1%, p95_ms: +19.0%, p99_ms: +16.9%, requests_per_second: +29.1%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: -1.2%, cpu_percent: +85.5%, duration_seconds: +0.3%, p50_ms: -26.2%, p95_ms: +47.4%, p99_ms: +79.8%, requests_per_second: -1.6%, rss_bytes: +64.3% |
| search | workers=4 | 2 | 100 | stable | completed: -5.6%, cpu_percent: +89.7%, duration_seconds: +0.2%, p50_ms: -38.3%, p95_ms: +20.9%, p99_ms: +21.2%, requests_per_second: -5.7%, rss_bytes: +64.9% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -5.5%, cpu_percent: +3.6%, duration_seconds: +4.8%, p50_ms: -9.7%, p95_ms: +50.8%, p99_ms: +87.4%, requests_per_second: -9.9%, rss_bytes: +64.9% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +22.1%, cpu_percent: +92.0%, duration_seconds: -0.0%, p50_ms: -14.7%, p95_ms: +34.9%, p99_ms: +21.0%, requests_per_second: +22.2%, rss_bytes: +64.9% |
| thread | workers=4 | 2 | 50 | confirmed-regression | completed: +19.3%, cpu_percent: +49.4%, duration_seconds: +0.0%, p50_ms: +2.2%, p95_ms: +21.8%, p99_ms: +3.0%, requests_per_second: +19.2%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | improvement | completed: +39.7%, cpu_percent: +88.2%, duration_seconds: +0.0%, p50_ms: -18.8%, p95_ms: +10.7%, p99_ms: -7.8%, requests_per_second: +39.4%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 50 | stable | completed: +23.7%, cpu_percent: +67.4%, duration_seconds: +0.1%, p50_ms: -21.5%, p95_ms: +2.8%, p99_ms: +5.6%, requests_per_second: +23.2%, rss_bytes: +63.9% |
| search | workers=4 | 2 | 100 | stable | completed: +12.5%, cpu_percent: +47.8%, duration_seconds: +0.1%, p50_ms: -40.4%, p95_ms: +21.0%, p99_ms: +31.0%, requests_per_second: +12.4%, rss_bytes: +64.8% |
| cache_hit | workers=4 | 2 | 50 | improvement | completed: +12.7%, cpu_percent: +54.0%, duration_seconds: +0.2%, p50_ms: -33.3%, p95_ms: +15.7%, p99_ms: +9.9%, requests_per_second: +17.6%, rss_bytes: +64.8% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +42.6%, cpu_percent: +89.4%, duration_seconds: +0.0%, p50_ms: -5.3%, p95_ms: +2.3%, p99_ms: -7.9%, requests_per_second: +42.6%, rss_bytes: +64.9% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38730487465)
