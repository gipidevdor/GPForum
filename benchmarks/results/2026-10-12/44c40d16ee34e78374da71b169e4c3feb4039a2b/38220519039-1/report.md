# GPForum continuous performance evidence

Commit: `44c40d16ee34e78374da71b169e4c3feb4039a2b` · mode: **deep** · status: **failed**
Run: 38220519039 / attempt 1 · 2026-10-12T07:56:18.245488+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, INTEL(R) XEON(R) PLATINUM 8573C.

Versions: {"ev":"4.37","mojolicious":"9.49","perl":"v5.40.1","postgres":"16.15 (Debian 16.15-1.pgdg13+2)","wrk":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)"}

Dataset: {"counts":{"bookmarks":40,"categories":4,"feed_items":600,"moderation_actions":40,"notifications":120,"permissions":6,"posts":72000,"posts_per_thread":120,"read_states":120,"reports":80,"role_bindings":40,"roles":3,"sessions":40,"subscriptions":40,"threads":600,"users":40},"implementation_sha256":{"lib/GPForum/Benchmark/SeedDataset.pm":"8c3d32ab10783f871b4e5c4122a16a01cea73b686dde249c1af050a2559ed0cb","lib/GPForum/Command/PerformanceSeed.pm":"ee7d3093ffc5cd7d0cc2f564417c6ad7f1e113aa0c1316b1b5938

Baseline: No baseline available. 

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 293.779 | 3.368 | 3.535 | 3.834 | 99.675 / 370.090 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 570.564 | 19.547 | 21.296 | 23.320 | 199.835 / 370.094 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 556.255 | 88.453 | 93.005 | 141.239 | 200.450 / 371.363 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 1241.465 | 0.796 | 0.876 | 0.982 | 99.517 / 370.332 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 2297.168 | 4.596 | 6.263 | 6.413 | 198.884 / 370.332 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 2439.686 | 20.874 | 22.199 | 28.324 | 199.818 / 370.707 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 2297.513 | 42.612 | 55.375 | 61.529 | 200.502 / 371.980 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 250 | 3 | ok (measured-comparative) | 2324.253 | 104.627 | 108.887 | 172.864 | 200.421 / 375.828 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::Poll / 2 / 500 | 3 | ok (measured-comparative) | 2186.925 | 214.811 | 277.386 | 383.431 | 201.066 / 382.070 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 127.625 | 7.761 | 8.335 | 9.816 | 86.572 / 382.277 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 225.706 | 38.967 | 67.497 | 80.618 | 173.044 / 382.504 | not-comparable |
| http:home | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 227.986 | 207.660 | 307.835 | 435.601 | 174.304 / 384.004 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 838.269 | 1.172 | 1.267 | 1.640 | 99.722 / 384.004 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1663.802 | 6.089 | 8.446 | 8.858 | 199.213 / 384.004 | not-comparable |
| http:categories | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1649.608 | 30.048 | 31.691 | 36.570 | 200.094 / 384.004 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 798.504 | 1.233 | 1.294 | 1.434 | 99.888 / 384.152 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1608.109 | 6.111 | 8.695 | 9.298 | 199.133 / 384.152 | not-comparable |
| http:category | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1588.134 | 31.034 | 40.525 | 47.264 | 199.760 / 384.500 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 799.424 | 1.255 | 1.297 | 1.369 | 99.538 / 384.625 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1568.158 | 6.307 | 7.751 | 8.696 | 199.529 / 384.625 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1569.937 | 31.236 | 33.744 | 42.095 | 200.090 / 385.734 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1542.593 | 64.732 | 73.000 | 95.652 | 201.079 / 388.691 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 250 | 3 | ok (measured-comparative) | 1513.190 | 163.098 | 185.070 | 254.766 | 200.918 / 398.398 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 2 / 500 | 3 | ok (measured-comparative) | 1492.516 | 319.943 | 484.864 | 593.303 | 201.367 / 411.562 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 60.297 | 16.602 | 17.577 | 18.086 | 58.407 / 400.137 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 106.573 | 75.331 | 134.429 | 175.958 | 115.336 / 400.297 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 99.874 | 447.542 | 777.990 | 884.308 | 114.553 / 400.297 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 99.768 | 910.909 | 1715.060 | 1929.184 | 114.581 / 400.297 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 1 | 3 | ok (measured-comparative) | 816.545 | 1.216 | 1.308 | 1.619 | 102.151 / 400.297 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (measured-comparative) | 1653.762 | 6.911 | 7.525 | 7.850 | 199.566 / 400.297 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 50 | 3 | ok (measured-comparative) | 1640.914 | 29.851 | 33.207 | 34.893 | 199.802 / 400.297 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 100 | 3 | ok (measured-comparative) | 1603.884 | 62.007 | 74.793 | 90.317 | 200.402 / 400.297 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 250 | 3 | ok (measured-comparative) | 1577.937 | 151.840 | 160.149 | 264.282 | 201.089 / 400.297 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 2 / 500 | 3 | ok (measured-comparative) | 1571.598 | 300.182 | 452.911 | 566.857 | 201.106 / 400.297 | not-comparable |
| http:health_live | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 1329.912 | 6.678 | 10.748 | 12.296 | 32.225 / 400.297 | not-comparable |
| http:thread | mojo / Mojo::Reactor::Poll / 2 / 10 | 3 | ok (indicative) | 861.988 | 9.955 | 17.148 | 22.896 | 42.805 / 400.578 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 2290.281 | 26.063 | 36.352 | 43.822 | 390.470 / 616.770 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 4 / 250 | 3 | ok (measured-comparative) | 2213.455 | 97.115 | 171.867 | 218.916 | 393.868 / 634.590 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 145.081 | 223.616 | 703.831 | 932.415 | 204.340 / 635.965 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 4 / 250 | 3 | ok (measured-comparative) | 102.966 | 994.559 | 2662.958 | 2812.181 | 208.424 / 637.488 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 50 | 3 | ok (measured-comparative) | 831.088 | 57.733 | 66.391 | 122.713 | 144.001 / 637.559 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 4 / 250 | 3 | ok (measured-comparative) | 2271.892 | 94.522 | 155.886 | 206.950 | 391.758 / 637.559 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 8 / 50 | 3 | ok (measured-comparative) | 2140.174 | 26.391 | 39.250 | 53.321 | 376.600 / 1102.637 | not-comparable |
| http:thread | wrk / Mojo::Reactor::Poll / 8 / 250 | 3 | ok (measured-comparative) | 2131.598 | 115.448 | 248.505 | 316.862 | 393.127 / 1119.680 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 8 / 50 | 3 | ok (measured-comparative) | 146.840 | 297.240 | 526.168 | 667.685 | 218.152 / 1122.023 | not-comparable |
| http:search | wrk / Mojo::Reactor::Poll / 8 / 250 | 3 | ok (measured-comparative) | 109.859 | 1043.363 | 2240.920 | 2567.304 | 227.755 / 1124.090 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 8 / 50 | 3 | ok (measured-comparative) | 2020.714 | 24.817 | 54.568 | 75.307 | 370.353 / 1124.320 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::Poll / 8 / 250 | 3 | ok (measured-comparative) | 2218.514 | 106.482 | 221.420 | 252.970 | 394.290 / 1124.320 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 296.130 | 3.351 | 3.470 | 4.109 | 99.742 / 371.449 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 576.097 | 17.042 | 20.990 | 27.208 | 199.486 / 371.449 | not-comparable |
| http:cache_miss | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 569.290 | 84.430 | 90.115 | 147.316 | 201.087 / 372.770 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 1265.915 | 0.772 | 0.875 | 0.924 | 99.742 / 371.402 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 2364.565 | 4.136 | 5.302 | 6.121 | 198.906 / 371.398 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 2451.486 | 20.032 | 21.222 | 30.401 | 199.461 / 371.934 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 2380.450 | 41.409 | 45.996 | 58.852 | 200.736 / 373.309 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 250 | 3 | ok (measured-comparative) | 2283.674 | 105.899 | 121.356 | 151.121 | 200.739 / 377.406 | not-comparable |
| http:health_live | wrk / Mojo::Reactor::EV / 2 / 500 | 3 | ok (measured-comparative) | 2241.876 | 212.968 | 267.800 | 305.534 | 201.087 / 384.258 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 125.597 | 7.913 | 8.498 | 8.939 | 86.870 / 384.492 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 218.590 | 43.758 | 65.089 | 93.205 | 173.709 / 384.516 | not-comparable |
| http:home | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 222.923 | 215.087 | 334.861 | 451.404 | 174.030 / 386.039 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 849.959 | 1.156 | 1.244 | 1.336 | 99.731 / 386.039 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1660.729 | 6.026 | 7.351 | 8.988 | 198.883 / 386.039 | not-comparable |
| http:categories | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1675.722 | 29.353 | 31.532 | 42.951 | 200.157 / 386.039 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 837.669 | 1.186 | 1.254 | 1.333 | 99.587 / 386.117 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1620.122 | 6.276 | 7.675 | 10.858 | 199.202 / 386.117 | not-comparable |
| http:category | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1611.413 | 30.832 | 32.662 | 45.501 | 199.451 / 386.176 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 827.544 | 1.189 | 1.279 | 1.344 | 99.517 / 386.402 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1593.847 | 6.211 | 8.001 | 10.888 | 198.871 / 386.402 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1569.862 | 31.303 | 33.745 | 52.650 | 199.833 / 387.836 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1545.309 | 63.797 | 66.343 | 103.875 | 200.469 / 388.121 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 250 | 3 | ok (measured-comparative) | 1492.698 | 162.539 | 190.735 | 289.209 | 201.048 / 398.664 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 2 / 500 | 3 | ok (measured-comparative) | 1493.420 | 320.083 | 485.103 | 595.273 | 201.107 / 413.402 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 62.644 | 15.937 | 16.846 | 18.964 | 57.425 / 402.598 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 109.585 | 90.007 | 117.066 | 185.096 | 114.667 / 402.598 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 99.843 | 440.542 | 765.307 | 871.283 | 115.022 / 402.598 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 99.129 | 915.033 | 1687.036 | 1828.359 | 114.570 / 402.598 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 2 / 250 | 3 | ok (measured-comparative) | 83.030 | 1127.738 | 2137.035 | 2236.147 | 114.592 / 402.598 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 1 | 3 | ok (measured-comparative) | 865.059 | 1.138 | 1.227 | 1.310 | 100.121 / 402.598 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 10 | 3 | ok (measured-comparative) | 1678.736 | 5.996 | 7.308 | 10.665 | 199.180 / 402.598 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 50 | 3 | ok (measured-comparative) | 1643.202 | 29.774 | 32.049 | 43.541 | 200.132 / 402.598 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 100 | 3 | ok (measured-comparative) | 1627.798 | 60.274 | 64.902 | 95.016 | 200.180 / 402.598 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 250 | 3 | ok (measured-comparative) | 1590.509 | 150.852 | 163.910 | 271.492 | 200.789 / 402.598 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 2 / 500 | 3 | ok (measured-comparative) | 1572.542 | 301.808 | 447.743 | 557.100 | 200.425 / 402.598 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 2327.751 | 16.568 | 44.057 | 46.919 | 389.434 / 618.598 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 4 / 250 | 3 | ok (measured-comparative) | 2219.786 | 99.109 | 187.771 | 233.153 | 392.322 / 637.340 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 152.104 | 266.421 | 645.233 | 874.480 | 200.452 / 638.449 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 4 / 250 | 3 | ok (measured-comparative) | 123.187 | 1095.450 | 2553.164 | 2917.406 | 206.042 / 638.895 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 50 | 3 | ok (measured-comparative) | 1600.798 | 37.560 | 43.009 | 60.335 | 216.451 / 638.980 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 4 / 250 | 3 | ok (measured-comparative) | 2276.377 | 106.495 | 155.624 | 198.299 | 391.878 / 638.980 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 8 / 50 | 3 | ok (measured-comparative) | 1961.763 | 21.460 | 38.463 | 46.271 | 297.855 / 1104.691 | not-comparable |
| http:thread | wrk / Mojo::Reactor::EV / 8 / 250 | 3 | ok (measured-comparative) | 2123.623 | 112.929 | 232.004 | 283.992 | 391.026 / 1123.172 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 8 / 50 | 3 | ok (measured-comparative) | 144.309 | 346.558 | 585.634 | 732.459 | 221.395 / 1125.766 | not-comparable |
| http:search | wrk / Mojo::Reactor::EV / 8 / 250 | 1 | failed (indicative) | 118.510 | 507.968 | 1539.923 | 1977.498 | 224.263 / 1127.859 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 8 / 50 | 3 | ok (measured-comparative) | 1696.499 | 35.768 | 75.035 | 106.821 | 306.518 / 1129.602 | not-comparable |
| http:cache_hit | wrk / Mojo::Reactor::EV / 8 / 250 | 3 | ok (measured-comparative) | 2240.039 | 102.125 | 230.573 | 320.682 | 396.139 / 1129.602 | not-comparable |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.165 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.109 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.379 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.107 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 5.527 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 3.021 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.137 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.098 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.016 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.005 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.128 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.124 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.290 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.314 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.117 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.090 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.115 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.111 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.115 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.124 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.071 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.196 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.288 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.252 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 4.935 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.583 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.378 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.008 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.063 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.056 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.136 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.124 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.144 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.160 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 1.753 | 1.861 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 2.958 | 3.069 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 0.433 | 0.535 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 1.598 | 1.635 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 4.337 | 4.519 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 6.328 | 47.317 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 1.148 | 1.175 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 2.379 | 2.525 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 5.824 | 6.502 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 8.223 | 9.165 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 1.768 | 1.815 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 4.198 | 4.420 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 3.660 | 3.732 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 5.460 | 47.090 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 1.048 | 1.103 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 2.274 | 2.315 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 3.111 | 3.352 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 11.836 | 12.195 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 0.710 | 0.755 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 4.705 | 4.783 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 19.173 | 20.434 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 88.525 | 90.543 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 3.439 | 3.617 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 7.076 | 7.183 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 8.446 | 9.881 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 9.904 | 11.013 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 2.177 | 2.235 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 3.625 | 3.778 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 9.295 | 10.546 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 10.993 | 11.992 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 3.102 | 3.313 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 4.445 | 4.507 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 1.381 | 2.194 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 3.707 | 3.858 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 0.522 | 0.589 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 1.706 | 1.756 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 1.891 | 2.355 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 3.052 | 3.326 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 0.460 | 0.633 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 1.821 | 1.861 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 14.952 | 15.849 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 66.814 | 69.103 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 3.551 | 3.679 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 6.610 | 6.749 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 0.667 | 0.730 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 2.940 | 3.031 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 0.460 | 0.513 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 1.927 | 2.021 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 15.960 | 17.061 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 71.020 | 71.990 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 3.443 | 3.534 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 6.681 | 7.045 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 11.692 | 12.119 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 13.000 | 13.406 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 4.043 | 4.211 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 5.388 | 5.465 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 22.225 | 22.732 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 63.854 | 64.150 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 8.135 | 8.266 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 9.634 | 12.023 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 0.310 | 0.368 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 1.763 | 1.831 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 0.411 | 0.459 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 1.655 | 1.698 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 1.195 | 1.248 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 4.039 | 4.225 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 1.304 | 1.481 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 4.311 | 45.061 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 1.231 | 1.332 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 3.850 | 4.189 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 1.115 | 1.955 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 3.939 | 44.294 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 1.324 | 1.506 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 3.743 | 3.829 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 1.114 | 1.363 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 3.937 | 44.488 | — | — / — | not-comparable |
| database:sql-function-service-dbic-direct | — / — / — / — | 1 | ok (indicative) | — | 0.514 | 0.551 | — | — / — | not-comparable |
| database:sql-function-service-dbic-proxy | — / — / — / — | 1 | ok (indicative) | — | 1.702 | 1.732 | — | — / — | not-comparable |
| database:sql-function-service-function-direct | — / — / — / — | 1 | ok (indicative) | — | 0.560 | 0.590 | — | — / — | not-comparable |
| database:sql-function-service-function-proxy | — / — / — / — | 1 | ok (indicative) | — | 1.945 | 1.987 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 557.459 | 179.174 | 202.821 | 212.415 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 884.973 | 222.857 | 237.451 | 253.284 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 4 / — | 3 | ok (measured-comparative) | 1144.570 | 345.210 | 393.231 | 400.000 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +0.8%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -0.5%, p95_ms: -1.8%, p99_ms: +7.2%, requests_per_second: +0.8%, rss_bytes: +0.4% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | confirmed-regression | completed: +0.9%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -12.8%, p95_ms: -1.4%, p99_ms: +16.7%, requests_per_second: +1.0%, rss_bytes: +0.4% |
| cache_miss | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +2.2%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: -4.5%, p95_ms: -3.1%, p99_ms: +4.3%, requests_per_second: +2.3%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.3%, cpu_percent: +0.2%, duration_seconds: +3.3%, p50_ms: -3.0%, p95_ms: -0.1%, p99_ms: -5.9%, requests_per_second: +2.0%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.9%, cpu_percent: +0.0%, duration_seconds: +0.1%, p50_ms: -10.0%, p95_ms: -15.3%, p99_ms: -4.6%, requests_per_second: +2.9%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.3%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -4.0%, p95_ms: -4.4%, p99_ms: +7.3%, requests_per_second: +0.5%, rss_bytes: +0.3% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +3.6%, cpu_percent: +0.1%, duration_seconds: +0.0%, p50_ms: -2.8%, p95_ms: -16.9%, p99_ms: -4.4%, requests_per_second: +3.6%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 250 | possible-regression | completed: -1.8%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: +1.2%, p95_ms: +11.5%, p99_ms: -12.6%, requests_per_second: -1.7%, rss_bytes: +0.4% |
| health_live | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 500 | improvement | completed: +2.5%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -0.9%, p95_ms: -3.5%, p99_ms: -20.3%, requests_per_second: +2.5%, rss_bytes: +0.6% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: -1.8%, cpu_percent: +0.3%, duration_seconds: -0.0%, p50_ms: +2.0%, p95_ms: +2.0%, p99_ms: -8.9%, requests_per_second: -1.6%, rss_bytes: +0.6% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: -3.1%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: +12.3%, p95_ms: -3.6%, p99_ms: +15.6%, requests_per_second: -3.2%, rss_bytes: +0.5% |
| home | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -2.2%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: +3.6%, p95_ms: +8.8%, p99_ms: +3.6%, requests_per_second: -2.2%, rss_bytes: +0.5% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | improvement | completed: +1.4%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -1.4%, p95_ms: -1.8%, p99_ms: -18.5%, requests_per_second: +1.4%, rss_bytes: +0.5% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | improvement | completed: +0.3%, cpu_percent: -0.2%, duration_seconds: -0.0%, p50_ms: -1.0%, p95_ms: -13.0%, p99_ms: +1.5%, requests_per_second: -0.2%, rss_bytes: +0.5% |
| categories | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +1.5%, cpu_percent: +0.0%, duration_seconds: -0.0%, p50_ms: -2.3%, p95_ms: -0.5%, p99_ms: +17.4%, requests_per_second: +1.6%, rss_bytes: +0.5% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +5.0%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -3.8%, p95_ms: -3.1%, p99_ms: -7.0%, requests_per_second: +4.9%, rss_bytes: +0.5% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +0.8%, cpu_percent: +0.0%, duration_seconds: +0.0%, p50_ms: +2.7%, p95_ms: -11.7%, p99_ms: +16.8%, requests_per_second: +0.7%, rss_bytes: +0.5% |
| category | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +1.4%, cpu_percent: -0.2%, duration_seconds: +0.0%, p50_ms: -0.7%, p95_ms: -19.4%, p99_ms: -3.7%, requests_per_second: +1.5%, rss_bytes: +0.4% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.5%, cpu_percent: -0.0%, duration_seconds: -0.0%, p50_ms: -5.3%, p95_ms: -1.4%, p99_ms: -1.8%, requests_per_second: +3.5%, rss_bytes: +0.5% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | possible-regression | completed: +1.6%, cpu_percent: -0.3%, duration_seconds: -0.1%, p50_ms: -1.5%, p95_ms: +3.2%, p99_ms: +25.2%, requests_per_second: +1.6%, rss_bytes: +0.5% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.0%, cpu_percent: -0.1%, duration_seconds: -0.0%, p50_ms: +0.2%, p95_ms: +0.0%, p99_ms: +25.1%, requests_per_second: -0.0%, rss_bytes: +0.5% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: +0.2%, cpu_percent: -0.3%, duration_seconds: +0.0%, p50_ms: -1.4%, p95_ms: -9.1%, p99_ms: +8.6%, requests_per_second: +0.2%, rss_bytes: -0.1% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 250 | stable | completed: -1.5%, cpu_percent: +0.1%, duration_seconds: -0.1%, p50_ms: -0.3%, p95_ms: +3.1%, p99_ms: +13.5%, requests_per_second: -1.4%, rss_bytes: +0.1% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 500 | stable | completed: +0.0%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: +0.0%, p95_ms: +0.0%, p99_ms: +0.3%, requests_per_second: +0.1%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +3.9%, cpu_percent: -1.7%, duration_seconds: -0.0%, p50_ms: -4.0%, p95_ms: -4.2%, p99_ms: +4.9%, requests_per_second: +3.9%, rss_bytes: +0.6% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +2.8%, cpu_percent: -0.6%, duration_seconds: +0.0%, p50_ms: +19.5%, p95_ms: -12.9%, p99_ms: +5.2%, requests_per_second: +2.8%, rss_bytes: +0.6% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +0.0%, cpu_percent: +0.4%, duration_seconds: -0.0%, p50_ms: -1.6%, p95_ms: -1.6%, p99_ms: -1.5%, requests_per_second: -0.0%, rss_bytes: +0.6% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | stable | completed: -0.7%, cpu_percent: -0.0%, duration_seconds: +0.0%, p50_ms: +0.5%, p95_ms: -1.6%, p99_ms: -5.2%, requests_per_second: -0.6%, rss_bytes: +0.6% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 1 | stable | completed: +5.9%, cpu_percent: -2.0%, duration_seconds: -0.0%, p50_ms: -6.4%, p95_ms: -6.2%, p99_ms: -19.1%, requests_per_second: +5.9%, rss_bytes: +0.6% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 10 | stable | completed: +1.4%, cpu_percent: -0.2%, duration_seconds: -0.1%, p50_ms: -13.2%, p95_ms: -2.9%, p99_ms: +35.9%, requests_per_second: +1.5%, rss_bytes: +0.6% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | confirmed-regression | completed: +0.2%, cpu_percent: +0.2%, duration_seconds: -0.1%, p50_ms: -0.3%, p95_ms: -3.5%, p99_ms: +24.8%, requests_per_second: +0.1%, rss_bytes: +0.6% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 100 | improvement | completed: +1.6%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -2.8%, p95_ms: -13.2%, p99_ms: +5.2%, requests_per_second: +1.5%, rss_bytes: +0.6% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 250 | stable | completed: +0.7%, cpu_percent: -0.1%, duration_seconds: -0.1%, p50_ms: -0.7%, p95_ms: +2.3%, p99_ms: +2.7%, requests_per_second: +0.8%, rss_bytes: +0.6% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 500 | stable | completed: +0.1%, cpu_percent: -0.3%, duration_seconds: +0.1%, p50_ms: +0.5%, p95_ms: -1.1%, p99_ms: -1.7%, requests_per_second: +0.1%, rss_bytes: +0.6% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | possible-regression | completed: +4.9%, cpu_percent: -0.3%, duration_seconds: +3.1%, p50_ms: -36.4%, p95_ms: +21.2%, p99_ms: +7.1%, requests_per_second: +1.6%, rss_bytes: +0.3% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 250 | stable | completed: +0.4%, cpu_percent: -0.4%, duration_seconds: +0.1%, p50_ms: +2.1%, p95_ms: +9.3%, p99_ms: +6.5%, requests_per_second: +0.3%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: +4.3%, cpu_percent: -1.9%, duration_seconds: -0.1%, p50_ms: +19.1%, p95_ms: -8.3%, p99_ms: -6.2%, requests_per_second: +4.8%, rss_bytes: +0.4% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 250 | stable | completed: +19.3%, cpu_percent: -1.1%, duration_seconds: -0.0%, p50_ms: +10.1%, p95_ms: -4.1%, p99_ms: +3.7%, requests_per_second: +19.6%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | improvement | completed: +92.7%, cpu_percent: +50.3%, duration_seconds: +0.1%, p50_ms: -34.9%, p95_ms: -35.2%, p99_ms: -50.8%, requests_per_second: +92.6%, rss_bytes: +0.2% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 250 | stable | completed: +0.5%, cpu_percent: +0.0%, duration_seconds: +0.2%, p50_ms: +12.7%, p95_ms: -0.2%, p99_ms: -4.2%, requests_per_second: +0.2%, rss_bytes: +0.2% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -11.2%, cpu_percent: -20.9%, duration_seconds: -0.1%, p50_ms: -18.7%, p95_ms: -2.0%, p99_ms: -13.2%, requests_per_second: -8.3%, rss_bytes: +0.2% |
| thread | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 250 | stable | completed: +0.2%, cpu_percent: -0.5%, duration_seconds: +0.3%, p50_ms: -2.2%, p95_ms: -6.6%, p99_ms: -10.4%, requests_per_second: -0.4%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -1.8%, cpu_percent: +1.5%, duration_seconds: +0.1%, p50_ms: +16.6%, p95_ms: +11.3%, p99_ms: +9.7%, requests_per_second: -1.7%, rss_bytes: +0.3% |
| search | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 250 | not-comparable |  |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 50 | stable | completed: -16.1%, cpu_percent: -17.2%, duration_seconds: -0.1%, p50_ms: +44.1%, p95_ms: +37.5%, p99_ms: +41.8%, requests_per_second: -16.0%, rss_bytes: +0.5% |
| cache_hit | reactor=Mojo::Reactor::EV | Mojo::Reactor::Poll | 250 | possible-regression | completed: +0.7%, cpu_percent: +0.5%, duration_seconds: -0.0%, p50_ms: -4.1%, p95_ms: +4.1%, p99_ms: +26.8%, requests_per_second: +1.0%, rss_bytes: +0.5% |
| thread | workers=4 | 2 | 50 | improvement | completed: +46.0%, cpu_percent: +95.1%, duration_seconds: +0.1%, p50_ms: -16.6%, p95_ms: +7.7%, p99_ms: +4.1%, requests_per_second: +45.9%, rss_bytes: +59.9% |
| thread | workers=4 | 2 | 250 | improvement | completed: +46.3%, cpu_percent: +96.0%, duration_seconds: +0.1%, p50_ms: -40.5%, p95_ms: -7.1%, p99_ms: -14.1%, requests_per_second: +46.3%, rss_bytes: +59.3% |
| search | workers=4 | 2 | 50 | improvement | completed: +46.3%, cpu_percent: +78.4%, duration_seconds: +0.3%, p50_ms: -50.0%, p95_ms: -9.5%, p99_ms: +5.4%, requests_per_second: +45.3%, rss_bytes: +58.9% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -49.3%, cpu_percent: -27.9%, duration_seconds: -0.1%, p50_ms: +93.4%, p95_ms: +99.9%, p99_ms: +251.7%, requests_per_second: -49.4%, rss_bytes: +59.3% |
| cache_hit | workers=4 | 2 | 250 | improvement | completed: +44.2%, cpu_percent: +94.8%, duration_seconds: +0.1%, p50_ms: -37.7%, p95_ms: -2.7%, p99_ms: -21.7%, requests_per_second: +44.0%, rss_bytes: +59.3% |
| thread | workers=8 | 2 | 50 | possible-regression | completed: +40.7%, cpu_percent: +88.2%, duration_seconds: +0.1%, p50_ms: -15.5%, p95_ms: +16.3%, p99_ms: +26.7%, requests_per_second: +36.3%, rss_bytes: +185.9% |
| thread | workers=8 | 2 | 250 | confirmed-regression | completed: +40.9%, cpu_percent: +95.7%, duration_seconds: +0.1%, p50_ms: -29.2%, p95_ms: +34.3%, p99_ms: +24.4%, requests_per_second: +40.9%, rss_bytes: +181.0% |
| search | workers=8 | 2 | 50 | improvement | completed: +48.3%, cpu_percent: +90.4%, duration_seconds: +0.9%, p50_ms: -33.6%, p95_ms: -32.4%, p99_ms: -24.5%, requests_per_second: +47.0%, rss_bytes: +180.3% |
| search | workers=8 | 4 | 250 | stable | completed: +8.4%, cpu_percent: +9.3%, duration_seconds: +0.7%, p50_ms: +4.9%, p95_ms: -15.8%, p99_ms: -8.7%, requests_per_second: +6.7%, rss_bytes: +76.3% |
| cache_hit | workers=8 | 2 | 50 | confirmed-regression | completed: +23.7%, cpu_percent: +85.4%, duration_seconds: +0.3%, p50_ms: -16.9%, p95_ms: +64.3%, p99_ms: +115.8%, requests_per_second: +23.1%, rss_bytes: +180.9% |
| cache_hit | workers=8 | 2 | 250 | confirmed-regression | completed: +41.2%, cpu_percent: +96.1%, duration_seconds: +0.2%, p50_ms: -29.9%, p95_ms: +38.3%, p99_ms: -4.3%, requests_per_second: +40.6%, rss_bytes: +180.9% |
| thread | workers=4 | 2 | 50 | possible-regression | completed: +53.0%, cpu_percent: +94.9%, duration_seconds: +3.2%, p50_ms: -47.1%, p95_ms: +30.6%, p99_ms: -10.9%, requests_per_second: +48.3%, rss_bytes: +59.5% |
| thread | workers=4 | 2 | 250 | improvement | completed: +49.1%, cpu_percent: +95.1%, duration_seconds: +0.2%, p50_ms: -39.0%, p95_ms: -1.6%, p99_ms: -19.4%, requests_per_second: +48.7%, rss_bytes: +59.9% |
| search | workers=4 | 2 | 50 | improvement | completed: +52.7%, cpu_percent: +74.3%, duration_seconds: +0.2%, p50_ms: -39.5%, p95_ms: -15.7%, p99_ms: +0.4%, requests_per_second: +52.3%, rss_bytes: +58.6% |
| search | workers=4 | 2 | 250 | confirmed-regression | completed: +48.4%, cpu_percent: +79.8%, duration_seconds: +0.3%, p50_ms: -2.9%, p95_ms: +19.5%, p99_ms: +30.5%, requests_per_second: +48.4%, rss_bytes: +58.7% |
| cache_hit | workers=4 | 2 | 50 | confirmed-regression | completed: -2.5%, cpu_percent: +8.2%, duration_seconds: +0.1%, p50_ms: +26.1%, p95_ms: +34.2%, p99_ms: +38.6%, requests_per_second: -2.6%, rss_bytes: +58.7% |
| cache_hit | workers=4 | 2 | 250 | improvement | completed: +43.9%, cpu_percent: +95.2%, duration_seconds: +0.4%, p50_ms: -29.4%, p95_ms: -5.1%, p99_ms: -27.0%, requests_per_second: +43.1%, rss_bytes: +58.7% |
| thread | workers=8 | 2 | 50 | possible-regression | completed: +24.9%, cpu_percent: +49.1%, duration_seconds: +0.0%, p50_ms: -31.4%, p95_ms: +14.0%, p99_ms: -12.1%, requests_per_second: +25.0%, rss_bytes: +184.8% |
| thread | workers=8 | 2 | 250 | improvement | completed: +43.4%, cpu_percent: +94.5%, duration_seconds: +0.5%, p50_ms: -30.5%, p95_ms: +21.6%, p99_ms: -1.8%, requests_per_second: +42.3%, rss_bytes: +181.7% |
| search | workers=8 | 2 | 50 | improvement | completed: +45.7%, cpu_percent: +92.5%, duration_seconds: +1.0%, p50_ms: -21.3%, p95_ms: -23.5%, p99_ms: -15.9%, requests_per_second: +44.5%, rss_bytes: +179.6% |
| search | workers=8 | 2 | 250 | not-comparable |  |
| cache_hit | workers=8 | 2 | 50 | confirmed-regression | completed: +3.5%, cpu_percent: +53.2%, duration_seconds: +0.3%, p50_ms: +20.1%, p95_ms: +134.1%, p99_ms: +145.3%, requests_per_second: +3.2%, rss_bytes: +180.6% |
| cache_hit | workers=8 | 2 | 250 | confirmed-regression | completed: +41.2%, cpu_percent: +97.3%, duration_seconds: +0.3%, p50_ms: -32.3%, p95_ms: +40.7%, p99_ms: +18.1%, requests_per_second: +40.8%, rss_bytes: +180.6% |

## Suite status and skipped tests

- contracts: **ok** — GitHub Actions step outcome: success
- database: **ok** — See individual gates and artifacts; skipped suites never imply execution
- database-plans-functions: **ok** — Nested function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- database-plans-readers: **ok** — Nested function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- databases: **ok** — GitHub Actions step outcome: success
- hotpaths_workflow: **ok** — GitHub Actions step outcome: success
- http: **partial** — search EV/8/250 returned errors; search EV/8/250 returned errors
  - {"reason":"read-only anonymous suite; safe durable auth fixture unavailable","scenario":"authenticated"}
  - {"reason":"bounded targeted plan: every endpoint at low load; high concurrency on health/thread/search/cache_hit; extra workers only thread/search/cache_hit","scenario":"full_cartesian_matrix"}
  - {"reason":"requires explicit --allow-1000 and capable runner","scenario":"concurrency_1000"}
  - {"reason":"wrk (distribution package 4.1.0-4build3; CLI upstream unspecified)","scenario":"wrk_upstream_version"}
  - {"cache_mode":"normal","concurrency":250,"endpoint":"/search?q=performance","reactor":"Mojo::Reactor::Poll","reason":"stopped after errors/saturation or suite deadline","repetition":1,"scenario":"search","workers":2}
  - {"cache_mode":"normal","concurrency":500,"endpoint":"/search?q=performance","reactor":"Mojo::Reactor::Poll","reason":"stopped after errors/saturation or suite deadline","repetition":1,"scenario":"search","workers":2}
  - {"cache_mode":"normal","concurrency":500,"endpoint":"/search?q=performance","reactor":"Mojo::Reactor::EV","reason":"stopped after errors/saturation or suite deadline","repetition":1,"scenario":"search","workers":2}
  - {"cache_mode":"normal","concurrency":500,"endpoint":"/search?q=performance","reactor":"Mojo::Reactor::EV","reason":"stopped after errors/saturation or suite deadline","repetition":2,"scenario":"search","workers":2}
  - {"cache_mode":"normal","concurrency":250,"endpoint":"/search?q=performance","reactor":"Mojo::Reactor::Poll","reason":"stopped after errors/saturation or suite deadline","repetition":2,"scenario":"search","workers":2}
  - {"cache_mode":"normal","concurrency":500,"endpoint":"/search?q=performance","reactor":"Mojo::Reactor::Poll","reason":"stopped after errors/saturation or suite deadline","repetition":2,"scenario":"search","workers":2}
  - {"cache_mode":"normal","concurrency":250,"endpoint":"/search?q=performance","reactor":"Mojo::Reactor::Poll","reason":"stopped after errors/saturation or suite deadline","repetition":3,"scenario":"search","workers":2}
  - {"cache_mode":"normal","concurrency":500,"endpoint":"/search?q=performance","reactor":"Mojo::Reactor::Poll","reason":"stopped after errors/saturation or suite deadline","repetition":3,"scenario":"search","workers":2}
  - {"cache_mode":"normal","concurrency":500,"endpoint":"/search?q=performance","reactor":"Mojo::Reactor::EV","reason":"stopped after errors/saturation or suite deadline","repetition":3,"scenario":"search","workers":2}
- http_workflow: **failed** — GitHub Actions step outcome: failure
- migrations: **ok** — GitHub Actions step outcome: success
- outbox: **ok** — See individual gates and artifacts; skipped suites never imply execution
- outbox-postgres: **ok** — Owned database is dropped on completion or caught signals; delivery IDs verify losses and duplicates
- pr_comment: **skipped** — Job Summary and artifacts provide PR results with a read-only token; no privileged fork artifact/comment workflow is enabled.
- profiling: **ok** — Configured request profile; binaries only in diagnostic artifact
- query-budget: **ok** — Catalog drift is deterministic; N+1 request counts remain blocking in the integration tier
- query-plan-static: **ok** — Required index and forbidden OFFSET checks
- setup: **ok** — GitHub Actions step outcome: success
- sql-functions: **ok** — Existing helper owns its 3000-post / 1500-thread database
- tools: **ok** — GitHub Actions step outcome: success

## Limits

- Shared runners and a colocated load generator give comparative CI evidence, not production capacity.
- Shared runner and load generator share the host; values are comparative evidence, not production capacity.
- wrk uses closed-loop fixed connections and corrected latency histograms; in-flight concurrency is not measured.
- RSS is end-of-sample manager+workers residency, not peak; PostgreSQL and generator resources are separate.
- Cache hits/misses verified by probes; warmed worker-local SSR cache; cache miss uses harness-only expiry policy.
- Only anonymous GETs; migrations, seed and rate-limit accounting write only the dedicated disposable database.

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38220519039)
