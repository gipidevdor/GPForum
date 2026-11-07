# Authenticated thread: workers and connection admission

Controlled follow-up to the [complete 5 November campaign](../../http-complete/2026-11-05/report.html).
The application source is frozen at commit `2713b813f2553e16471dcaf93da154341e607e14`;
[the initial patch](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/benchmark-options-initial.patch) adds the benchmark admission
option and records its effective value. After the first two arms, the first
eight-worker attempt exposed a startup race: a worker can answer before the
manager has finished spawning workers and written its PID. That attempt failed
before any cells were measured and is [preserved](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/excluded/http-w8-c32-a/http-complete.json).
[The updated patch](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/benchmark-options.patch) also waits for the PID within the
existing startup deadline; it does not change application or measurement code.
No historical revision was benchmarked again.
Later application changes in the shared working tree are excluded.

Every arm uses production startup/template warmup, 240 threads / 4,800 posts,
103 seeded users, independent authenticated sessions, the same TCP generator,
PostgreSQL durability, and the same machine. Each concurrency has three
repetitions: 100 requests for the single-session cell, or six seconds at
10/50/100 sessions, after ten warmup requests using the first session. Runs are
sequential in table order. At the time of this forward campaign, the reverse
confirmation was queued but not run because another campaign reserved the CPU.
The [6 November confirmation](../2026-11-06/README.md) now completes that check
and records the combined local reference. Production defaults require separate
representative-load validation. The earlier full campaign
independently measured the four-worker baseline at 307.9 req/s / 808.4 ms p95.
The connection limit includes idle keep-alive connections and does not make
synchronous database work parallel within a worker.

## Results

Medians of three repetitions. Parentheses show the observed p95 range.
Percentiles are not pooled across repetitions or arms.

| Arm | Workers | Connections/worker | Sessions | req/s | p95 ms (range) | App p95 ms | DB p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| [http-w4-c2048-a](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w4-c2048-a/report.html) | 4 | 2048 | 1 | 80.6 | 12.6 (12.6–12.6) | 10.12 | 1.13 |
| [http-w4-c2048-a](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w4-c2048-a/report.html) | 4 | 2048 | 10 | 297.4 | 60.6 (59.7–62.4) | 11.44 | 1.38 |
| [http-w4-c2048-a](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w4-c2048-a/report.html) | 4 | 2048 | 50 | 312.6 | 243.1 (231.9–256.4) | 11.47 | 1.42 |
| [http-w4-c2048-a](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w4-c2048-a/report.html) | 4 | 2048 | 100 | 308.4 | 790.4 (723.1–803.7) | 11.65 | 1.47 |
| [http-w4-c32-a](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w4-c32-a/report.html) | 4 | 32 | 1 | 80.7 | 12.5 (12.4–12.7) | 10.05 | 1.11 |
| [http-w4-c32-a](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w4-c32-a/report.html) | 4 | 32 | 10 | 285.9 | 63.8 (63.3–64.4) | 11.28 | 1.36 |
| [http-w4-c32-a](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w4-c32-a/report.html) | 4 | 32 | 50 | 293.2 | 369.6 (367.8–379.9) | 11.57 | 1.45 |
| [http-w4-c32-a](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w4-c32-a/report.html) | 4 | 32 | 100 | 304.8 | 449.9 (422.3–460.3) | 12.00 | 1.52 |
| [http-w8-c16-b](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w8-c16-b/report.html) | 8 | 16 | 1 | 78.8 | 14.2 (13.3–14.6) | 11.32 | 1.42 |
| [http-w8-c16-b](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w8-c16-b/report.html) | 8 | 16 | 10 | 408.1 | 39.5 (39.2–39.9) | 13.50 | 1.77 |
| [http-w8-c16-b](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w8-c16-b/report.html) | 8 | 16 | 50 | 484.5 | 190.6 (143.5–254.4) | 14.81 | 2.00 |
| [http-w8-c16-b](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/thread-tail/2026-11-05/http-w8-c16-b/report.html) | 8 | 16 | 100 | 499.4 | 286.7 (284.2–294.5) | 14.71 | 1.97 |

59,910 measured responses, zero invalid responses, all 36 planned cells
completed. [Raw summary](summary.json), per-arm JSON and commands accompany the
tables. [Source identity](source.json) records the immutable commit and benchmark
files. The frozen checkout's 3,417 tracked files were
verified against the recorded final source manifest; the startup-only harness
change between arms is described above. Application source stayed unchanged.

Two startup failures (missing manager PID; one of eight workers not observed
before startup deadline) and the exploratory 8-worker/32-client run are retained
under `excluded/`. The latter saved 12 cells but its orchestrator stalled and
another benchmark was seen around the run; it does not enter this summary.

At 100 sessions, eight workers / 16 connections per worker yields 61.9% more
requests per second and 63.7% lower p95 than four workers / 2048 connections.
At 50 sessions, four workers / 32 connections worsens p95 from 243.1 to
369.6 ms. Lowering admission alone does not improve every concurrency.
The eight-worker single-session p95 is also slightly higher (14.2 vs 12.6 ms).

## Reproduce

Use an isolated checkout of the recorded commit with `benchmark-options.patch`
applied and dependencies built for the selected Perl. Give every run a new
output directory. For the eight-worker candidate:

```sh
script/gpforum-carton exec script/benchmark-http-complete \
  --output artifacts/thread-8w-16clients --workers 8 --worker-clients 16 \
  --scenario member.thread --concurrency 1,10,50,100 \
  --iterations 100 --warmup 10 --duration 6 --repetitions 3 --deadline 900
```

The harness owns its temporary PostgreSQL cluster. Change only `--workers`
and `--worker-clients` for the other configurations; reverse the order for
confirmation and retain all failed attempts.

## Interpretation limits

The original campaign's 2→4-worker thread p95 improves from 1,096 to 808 ms;
723→808 ms compares two dates at four workers. At four workers / 100 sessions,
application p95 is about 12 ms and database p95 about 1.5 ms. Outside-application
time includes worker waiting, transport and generator overhead. Component
percentiles cannot be added, and these numbers alone cannot identify locks,
CPU contention or a connection-pool bottleneck.

These are closed-loop saturation measurements on a shared laptop, with the
generator, application and database on the same host. They do not establish a
fixed-arrival-rate SLO, representative large-dataset capacity, a causal gain
from a code optimization, or a comparison with Discourse/NodeBB. No production
configuration was changed. Validate the selected arm with mixed writes,
background jobs and long-lived realtime connections before deployment.
