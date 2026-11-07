# Authenticated-thread baseline: reverse-order confirmation

This continues the [forward admission sweep](../2026-11-05/README.md) on the
same immutable application source, commit `2713b813f2553e16471dcaf93da154341e607e14`,
using its [recorded benchmark patch](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/benchmark-options.patch). The order is reversed: 8 workers / 16
connections, 4 / 32, then 4 / 2048. Each arm retains three repetitions at
1/10/50/100 authenticated sessions, the same 240-thread / 4,800-post fixture,
100 serial requests or six-second concurrent windows, ten workload warmup
requests, and production startup/template precompilation. The older November 2
baseline is not re-executed. The normal production configuration is unchanged.

The runner first waits for the previous reserved benchmark campaign to finish
and for ten seconds without known benchmark or test processes. It samples
those processes every second during each arm and excludes attempts with
detected overlaps or failures. The frozen source hashes are checked before
and after each attempt. Raw reports, worker telemetry and the campaign record
are retained alongside the summary.

## Both orders

Values are medians of three repetitions. Parentheses show the observed p95
range. Tables retain each order separately rather than pooling percentiles.

| Order | Workers | Connections/worker | Sessions | req/s | p95 ms (range) | App p95 ms | DB p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| forward | 4 | 2048 | 1 | 80.6 | 12.6 (12.6–12.6) | 10.12 | 1.13 |
| forward | 4 | 2048 | 10 | 297.4 | 60.6 (59.7–62.4) | 11.44 | 1.38 |
| forward | 4 | 2048 | 50 | 312.6 | 243.1 (231.9–256.4) | 11.47 | 1.42 |
| forward | 4 | 2048 | 100 | 308.4 | 790.4 (723.1–803.7) | 11.65 | 1.47 |
| forward | 4 | 32 | 1 | 80.7 | 12.5 (12.4–12.7) | 10.05 | 1.11 |
| forward | 4 | 32 | 10 | 285.9 | 63.8 (63.3–64.4) | 11.28 | 1.36 |
| forward | 4 | 32 | 50 | 293.2 | 369.6 (367.8–379.9) | 11.57 | 1.45 |
| forward | 4 | 32 | 100 | 304.8 | 449.9 (422.3–460.3) | 12.00 | 1.52 |
| forward | 8 | 16 | 1 | 78.8 | 14.2 (13.3–14.6) | 11.32 | 1.42 |
| forward | 8 | 16 | 10 | 408.1 | 39.5 (39.2–39.9) | 13.50 | 1.77 |
| forward | 8 | 16 | 50 | 484.5 | 190.6 (143.5–254.4) | 14.81 | 2.00 |
| forward | 8 | 16 | 100 | 499.4 | 286.7 (284.2–294.5) | 14.71 | 1.97 |
| reverse | 8 | 16 | 1 | 76.4 | 13.7 (13.6–14.0) | 10.94 | 1.32 |
| reverse | 8 | 16 | 10 | 346.5 | 44.0 (40.3–46.2) | 16.08 | 2.29 |
| reverse | 8 | 16 | 50 | 444.8 | 263.5 (242.3–284.6) | 16.94 | 2.81 |
| reverse | 8 | 16 | 100 | 459.6 | 315.3 (310.5–324.5) | 16.85 | 2.32 |
| reverse | 4 | 32 | 1 | 80.8 | 13.3 (13.1–13.7) | 10.58 | 1.24 |
| reverse | 4 | 32 | 10 | 295.1 | 58.5 (58.0–58.9) | 11.58 | 1.43 |
| reverse | 4 | 32 | 50 | 309.6 | 250.3 (236.0–322.5) | 11.54 | 1.45 |
| reverse | 4 | 32 | 100 | 307.8 | 461.5 (440.3–510.3) | 11.47 | 1.43 |
| reverse | 4 | 2048 | 1 | 79.9 | 13.2 (12.8–14.7) | 10.64 | 1.21 |
| reverse | 4 | 2048 | 10 | 301.7 | 51.5 (49.1–52.0) | 11.96 | 1.50 |
| reverse | 4 | 2048 | 50 | 314.7 | 247.4 (218.9–306.6) | 11.75 | 1.48 |
| reverse | 4 | 2048 | 100 | 300.9 | 837.7 (785.1–856.4) | 11.63 | 1.46 |

## Confirmation result

The throughput and p95 improvement at 100 sessions persists in both orders.

- forward: throughput +61.9%; p95 -63.7% (8/16 versus 4/2048).
- reverse: throughput +52.7%; p95 -62.4% (8/16 versus 4/2048).

118,259 valid measured responses across both orders; zero invalid responses; all 72 planned cells complete.

The combined reference below uses the median of six repetition statistics
across both orders; it is not a p95 computed from pooled request samples.

| Workers | Connections/worker | Sessions | req/s | p95 ms (range) |
| ---: | ---: | ---: | ---: | ---: |
| 4 | 32 | 100 | 305.2 | 455.1 (422.3–510.3) |
| 4 | 2048 | 100 | 304.6 | 797.0 (723.1–856.4) |
| 8 | 16 | 100 | 491.8 | 302.5 (284.2–324.5) |

The documented local reference is **8 workers / 16 connections per worker**,
**491.8 req/s / 302.5 ms p95** at 100 authenticated sessions.
[BASELINE.json](../BASELINE.json) stores the source checkpoint, fixture, runtime,
aggregation and observed ranges. Across the six repetition statistics this is
61.4% higher throughput and 62.0% lower p95 than 4/2048.
The reverse-order 8/16 median was lower than the initial result: 459.6 versus
499.4 req/s, with p95 315.3 versus 286.7 ms. Absolute values therefore remain
sensitive to host/run variation even though the configuration advantage persists.

At 50 sessions the combined p95 is 345.1 ms for 4/32 and 245.2 ms for 4/2048;
8/16 reaches 248.3 ms there. A lower connection limit does not improve every
concurrency. The 200 ms p95 target at 100 sessions is not yet met.

## Scope

These are closed-loop saturation measurements on one shared Apple M4 laptop
with the generator, PostgreSQL and application on the same host. Connection
limits include idle keep-alive connections; they do not directly measure
queue length or make synchronous work parallel within a worker. The 8/16
versus 4/2048 comparison changes both worker count and connection admission.
It cannot by itself establish which factor dominates or identify PostgreSQL
locks. Admission effects also vary with concurrency; inspect the 50-session
rows before generalizing the 100-session result.

These results are a local reference for this authenticated-thread
fixture, not a production capacity guarantee, a large-dataset or mixed-write
benchmark, or a comparison with Discourse/NodeBB. Existing 8/16-core PostgreSQL
profiles are not validated by this application-only sweep. A fixed-arrival-rate
test and representative mixed load remain separate work.
