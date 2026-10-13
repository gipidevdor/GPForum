# GPForum continuous performance evidence

Commit: `b37223a7ff134cc711bbc06f1edfa61f95cc435e` · mode: **main** · status: **ok**
Run: 38462264452 / attempt 1 · 2026-10-13T20:22:41.143796+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":25,"categories":8,"feed_items":240,"moderation_actions":25,"notifications":75,"permissions":6,"posts":4800,"posts_per_thread":20,"read_states":75,"reports":50,"role_bindings":25,"roles":3,"sessions":25,"subscriptions":25,"threads":240,"users":25},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"ee7d3093ffc5cd7d0cc2f564417c6ad7f1e113aa0c1316b1b59386e9b

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 229.231 | 4.297 | 4.807 | 5.096 | 100.499 / 369.629 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 443.867 | 21.746 | 28.609 | 29.801 | 200.333 / 369.664 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 396.587 | 115.443 | 170.823 | 205.707 | 201.767 / 371.344 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1197.612 | 0.824 | 0.884 | 0.955 | 99.422 / 369.566 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2302.127 | 4.314 | 4.577 | 5.011 | 198.895 / 369.566 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2282.835 | 21.597 | 22.988 | 25.524 | 200.244 / 370.230 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2194.744 | 44.615 | 47.894 | 65.618 | 201.331 / 371.465 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 105.382 | 9.416 | 9.920 | 10.256 | 85.571 / 371.895 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 179.881 | 53.805 | 64.633 | 86.731 | 172.488 / 372.281 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 174.844 | 281.282 | 402.834 | 486.452 | 172.968 / 374.016 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 900.866 | 1.100 | 1.161 | 1.278 | 99.580 / 374.016 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1697.289 | 5.703 | 8.292 | 9.388 | 199.340 / 374.016 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1686.218 | 29.332 | 31.774 | 42.305 | 200.412 / 374.016 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 861.064 | 1.153 | 1.209 | 1.261 | 99.400 / 374.047 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1646.746 | 5.831 | 6.408 | 8.248 | 199.354 / 374.047 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1621.077 | 30.340 | 34.333 | 40.212 | 200.248 / 374.047 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 848.386 | 1.164 | 1.233 | 1.288 | 99.917 / 374.172 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1599.004 | 5.779 | 7.655 | 9.374 | 198.858 / 374.172 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1632.267 | 30.687 | 33.133 | 42.401 | 201.734 / 374.770 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1597.915 | 61.625 | 66.285 | 98.260 | 201.777 / 377.934 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 66.975 | 14.746 | 15.500 | 16.522 | 67.630 / 378.664 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 117.418 | 73.516 | 107.539 | 152.097 | 136.693 / 378.664 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 111.764 | 390.181 | 732.939 | 814.683 | 135.130 / 378.664 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.770 | 805.095 | 1525.803 | 1635.785 | 135.337 / 378.664 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 901.514 | 1.098 | 1.151 | 1.264 | 99.957 / 378.664 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1660.406 | 6.145 | 6.981 | 7.843 | 199.315 / 378.664 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1652.629 | 29.614 | 31.991 | 42.153 | 200.038 / 378.664 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1669.111 | 58.797 | 61.631 | 94.057 | 200.298 / 378.664 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1226.028 | 6.233 | 12.256 | 14.740 | 28.233 / 378.664 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 832.494 | 10.365 | 17.021 | 21.781 | 43.113 / 378.945 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2045.829 | 22.044 | 45.628 | 51.504 | 387.721 / 615.613 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 1996.039 | 42.711 | 82.692 | 97.883 | 392.656 / 619.633 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 155.939 | 197.891 | 708.143 | 997.708 | 242.887 / 621.887 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 143.845 | 518.459 | 1205.412 | 1324.542 | 244.581 / 622.980 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 1646.001 | 31.580 | 40.802 | 63.153 | 214.548 / 622.980 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 100 | 3 | ok (measured-comparative) | 2194.303 | 43.307 | 73.997 | 89.153 | 393.464 / 622.980 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 226.485 | 4.397 | 4.705 | 4.975 | 99.522 / 370.781 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 432.083 | 21.777 | 30.445 | 40.245 | 199.756 / 370.820 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 408.039 | 116.439 | 154.991 | 211.850 | 201.684 / 372.566 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1208.833 | 0.819 | 0.877 | 0.975 | 99.493 / 370.547 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2255.335 | 4.339 | 4.933 | 7.748 | 199.284 / 370.547 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2232.837 | 22.095 | 23.971 | 29.727 | 200.362 / 371.258 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2147.065 | 45.545 | 47.971 | 66.733 | 201.183 / 372.613 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 108.865 | 9.162 | 9.631 | 10.301 | 85.566 / 373.035 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 175.868 | 42.234 | 98.504 | 144.650 | 172.804 / 373.477 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 174.774 | 273.822 | 453.649 | 538.496 | 173.736 / 375.176 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 891.298 | 1.114 | 1.178 | 1.346 | 101.357 / 375.176 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1646.850 | 5.944 | 6.805 | 9.181 | 199.326 / 375.176 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1623.255 | 31.119 | 33.978 | 49.286 | 200.693 / 375.176 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 845.696 | 1.156 | 1.318 | 1.702 | 99.878 / 375.207 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1636.968 | 6.030 | 6.879 | 10.481 | 199.316 / 375.207 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1625.141 | 30.443 | 40.295 | 50.306 | 200.158 / 375.207 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 795.105 | 1.193 | 1.586 | 1.978 | 99.450 / 375.457 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1589.745 | 6.174 | 6.843 | 10.006 | 198.821 / 375.457 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1528.606 | 31.380 | 37.379 | 50.586 | 200.719 / 376.078 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1545.409 | 63.082 | 70.226 | 103.502 | 201.654 / 379.246 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 66.883 | 14.770 | 15.555 | 16.351 | 68.103 / 379.785 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 118.300 | 83.561 | 111.271 | 170.794 | 137.084 / 379.828 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 109.803 | 422.009 | 750.371 | 827.975 | 136.274 / 379.828 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.794 | 832.724 | 1562.000 | 1636.466 | 135.295 / 379.828 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 883.078 | 1.123 | 1.187 | 1.306 | 99.414 / 379.828 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1623.507 | 5.661 | 7.804 | 11.453 | 198.368 / 379.828 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1590.326 | 30.514 | 37.716 | 50.844 | 201.215 / 379.828 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1582.260 | 61.615 | 70.084 | 101.763 | 200.803 / 379.828 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2364.772 | 16.208 | 42.282 | 46.047 | 386.242 / 617.277 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2013.269 | 42.489 | 86.900 | 132.196 | 384.376 / 621.875 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 146.666 | 222.369 | 579.359 | 730.547 | 242.166 / 623.645 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 144.507 | 544.756 | 1240.007 | 1393.049 | 237.016 / 624.770 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1738.991 | 26.477 | 36.209 | 51.199 | 305.757 / 624.770 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 100 | 3 | ok (measured-comparative) | 2401.092 | 43.291 | 75.823 | 112.356 | 391.780 / 624.770 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.456 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.034 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.448 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.499 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.923 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.668 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.105 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.029 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.004 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.396 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.503 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.282 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.320 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.074 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.048 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.049 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.021 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.388 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.417 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.541 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.395 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.475 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.254 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.325 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.527 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.111 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.208 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.168 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.010 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.189 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.059 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.077 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.123 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.052 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.071 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 675.216 | 146.383 | 169.908 | 172.499 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 1128.305 | 173.424 | 196.493 | 196.802 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.3%, cpu_percent: -1.0%, duration_seconds: -0.1%, p50_ms: +2.3%, p95_ms: -2.1%, p99_ms: -2.4%, requests_per_second: -1.2%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -2.7%, cpu_percent: -0.3%, duration_seconds: -0.0%, p50_ms: +0.1%, p95_ms: +6.4%, p99_ms: +35.0%, requests_per_second: -2.7%, rss_bytes: +0.3% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.9%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +0.9%, p95_ms: -9.3%, p99_ms: +3.0%, requests_per_second: +2.9%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +2.1%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -0.6%, p95_ms: -0.8%, p99_ms: +2.1%, requests_per_second: +0.9%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -2.0%, cpu_percent: +0.2%, duration_seconds: -0.0%, p50_ms: +0.6%, p95_ms: +7.8%, p99_ms: +54.6%, requests_per_second: -2.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -2.3%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: +2.3%, p95_ms: +4.3%, p99_ms: +16.5%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -2.3%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +2.1%, p95_ms: +0.2%, p99_ms: +1.7%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.3%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: -2.7%, p95_ms: -2.9%, p99_ms: +0.4%, requests_per_second: +3.3%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: -2.2%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -21.5%, p95_ms: +52.4%, p99_ms: +66.8%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.0%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -2.7%, p95_ms: +12.6%, p99_ms: +10.7%, requests_per_second: -0.0%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.1%, cpu_percent: +1.8%, duration_seconds: -0.0%, p50_ms: +1.3%, p95_ms: +1.5%, p99_ms: +5.3%, requests_per_second: -1.1%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -3.2%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +4.2%, p95_ms: -17.9%, p99_ms: -2.2%, requests_per_second: -3.0%, rss_bytes: +0.3% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: -3.7%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: +6.1%, p95_ms: +6.9%, p99_ms: +16.5%, requests_per_second: -3.7%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.8%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: +0.3%, p95_ms: +9.0%, p99_ms: +35.0%, requests_per_second: -1.8%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.6%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +3.4%, p95_ms: +7.3%, p99_ms: +27.1%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +0.4%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +0.3%, p95_ms: +17.4%, p99_ms: +25.1%, requests_per_second: +0.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | confirmed-regression | completed: -10.6%, cpu_percent: -0.5%, duration_seconds: -4.7%, p50_ms: +2.5%, p95_ms: +28.6%, p99_ms: +53.6%, requests_per_second: -6.3%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: -0.3%, cpu_percent: -0.0%, duration_seconds: +0.1%, p50_ms: +6.8%, p95_ms: -10.6%, p99_ms: +6.7%, requests_per_second: -0.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -6.4%, cpu_percent: -0.5%, duration_seconds: +0.1%, p50_ms: +2.3%, p95_ms: +12.8%, p99_ms: +19.3%, requests_per_second: -6.4%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -3.2%, cpu_percent: -0.1%, duration_seconds: +0.1%, p50_ms: +2.4%, p95_ms: +5.9%, p99_ms: +5.3%, requests_per_second: -3.3%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -2.9%, cpu_percent: +0.7%, duration_seconds: +0.1%, p50_ms: +0.2%, p95_ms: +0.4%, p99_ms: -1.0%, requests_per_second: -0.1%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.3%, cpu_percent: +0.3%, duration_seconds: +0.1%, p50_ms: +13.7%, p95_ms: +3.5%, p99_ms: +12.3%, requests_per_second: +0.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.8%, cpu_percent: +0.8%, duration_seconds: -0.0%, p50_ms: +8.2%, p95_ms: +2.4%, p99_ms: +1.6%, requests_per_second: -1.8%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.0%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: +3.4%, p95_ms: +2.4%, p99_ms: +0.0%, requests_per_second: +0.0%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.7%, cpu_percent: -0.5%, duration_seconds: +4.9%, p50_ms: +2.3%, p95_ms: +3.1%, p99_ms: +3.3%, requests_per_second: -2.0%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +1.4%, cpu_percent: -0.5%, duration_seconds: +4.8%, p50_ms: -7.9%, p95_ms: +11.8%, p99_ms: +46.0%, requests_per_second: -2.2%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: -3.8%, cpu_percent: +0.6%, duration_seconds: +0.0%, p50_ms: +3.0%, p95_ms: +17.9%, p99_ms: +20.6%, requests_per_second: -3.8%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -5.3%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +4.8%, p95_ms: +13.7%, p99_ms: +8.2%, requests_per_second: -5.2%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +15.7%, cpu_percent: -0.4%, duration_seconds: -0.0%, p50_ms: -26.5%, p95_ms: -7.3%, p99_ms: -10.6%, requests_per_second: +15.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.8%, cpu_percent: -2.1%, duration_seconds: +0.1%, p50_ms: -0.5%, p95_ms: +5.1%, p99_ms: +35.1%, requests_per_second: +0.9%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: -6.1%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: +12.4%, p95_ms: -18.2%, p99_ms: -26.8%, requests_per_second: -5.9%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.7%, cpu_percent: -3.1%, duration_seconds: -0.1%, p50_ms: +5.1%, p95_ms: +2.9%, p99_ms: +5.2%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +5.5%, cpu_percent: +42.5%, duration_seconds: +0.0%, p50_ms: -16.2%, p95_ms: -11.3%, p99_ms: -18.9%, requests_per_second: +5.6%, rss_bytes: +0.3% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +9.8%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: -0.0%, p95_ms: +2.5%, p99_ms: +26.0%, requests_per_second: +9.4%, rss_bytes: +0.3% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +31.4%, cpu_percent: +92.2%, duration_seconds: +4.8%, p50_ms: -28.2%, p95_ms: +37.7%, p99_ms: +21.5%, requests_per_second: +25.3%, rss_bytes: +64.3% |
| thread | workers=4 | 2 | 100 | possible-regression | completed: +25.0%, cpu_percent: +94.6%, duration_seconds: +0.0%, p50_ms: -30.7%, p95_ms: +24.8%, p99_ms: -0.4%, requests_per_second: +24.9%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | confirmed-regression | completed: +39.7%, cpu_percent: +79.7%, duration_seconds: +0.2%, p50_ms: -49.3%, p95_ms: -3.4%, p99_ms: +22.5%, requests_per_second: +39.5%, rss_bytes: +64.2% |
| search | workers=4 | 2 | 100 | improvement | completed: +44.5%, cpu_percent: +80.7%, duration_seconds: +0.2%, p50_ms: -35.6%, p95_ms: -21.0%, p99_ms: -19.0%, requests_per_second: +44.2%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 50 | possible-regression | completed: -0.4%, cpu_percent: +7.3%, duration_seconds: -0.0%, p50_ms: +6.6%, p95_ms: +27.5%, p99_ms: +49.8%, requests_per_second: -0.4%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +31.3%, cpu_percent: +96.4%, duration_seconds: +0.1%, p50_ms: -26.3%, p95_ms: +20.1%, p99_ms: -5.2%, requests_per_second: +31.5%, rss_bytes: +64.5% |
| thread | workers=4 | 2 | 50 | improvement | completed: +62.4%, cpu_percent: +92.4%, duration_seconds: +4.7%, p50_ms: -48.3%, p95_ms: +13.1%, p99_ms: -9.0%, requests_per_second: +54.7%, rss_bytes: +64.1% |
| thread | workers=4 | 2 | 100 | stable | completed: +30.2%, cpu_percent: +90.6%, duration_seconds: +0.1%, p50_ms: -32.6%, p95_ms: +23.7%, p99_ms: +27.7%, requests_per_second: +30.3%, rss_bytes: +64.0% |
| search | workers=4 | 2 | 50 | improvement | completed: +33.6%, cpu_percent: +77.7%, duration_seconds: +0.0%, p50_ms: -47.3%, p95_ms: -22.8%, p99_ms: -11.8%, requests_per_second: +33.6%, rss_bytes: +64.2% |
| search | workers=4 | 2 | 100 | improvement | completed: +45.5%, cpu_percent: +75.2%, duration_seconds: +0.1%, p50_ms: -34.6%, p95_ms: -20.6%, p99_ms: -14.9%, requests_per_second: +44.8%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 50 | stable | completed: +9.3%, cpu_percent: +52.0%, duration_seconds: -0.0%, p50_ms: -13.2%, p95_ms: -4.0%, p99_ms: +0.7%, requests_per_second: +9.3%, rss_bytes: +64.5% |
| cache_hit | workers=4 | 2 | 100 | improvement | completed: +52.2%, cpu_percent: +95.1%, duration_seconds: +0.2%, p50_ms: -29.7%, p95_ms: +8.2%, p99_ms: +10.4%, requests_per_second: +51.8%, rss_bytes: +64.5% |

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
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38462264452)
