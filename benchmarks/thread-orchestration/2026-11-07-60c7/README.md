# Clean local confirmation of `60c7b9f`

Apple M4, 10 cores, 16 GiB; **8 workers × 16 connections per worker**,
100 authenticated sessions. PostgreSQL 18.6, Perl 5.44.0, Mojolicious 9.51,
EV/kqueue. Private local durable PostgreSQL; 103 users, 240 threads,
4,800 posts. No application or harness overlay; clean detached application
source `60c7b9f2f4825073331c3b7f244da8722a3f31a0`.

| Thread sessions | req/s median | p95 median ms |
| --- | ---: | ---: |
| 1 | 69.0 | 15.9 |
| 100 | **452.3** | **282.0** |

Three concurrent repetitions: **456.1 / 449.8 / 452.3 req/s**,
p95 **266.5 / 299.5 / 282.0 ms**. These are medians of repetition
statistics, not pooled percentiles. All 6/6 planned cells completed;
**8,736 measured responses, zero errors**. All eight serving workers
reported the actual 16-connection limit; no competing tests/benchmarks
were detected by the half-second process monitor.

The median meets **450 req/s and p95 ≤ 300 ms**. One throughput repetition
is 449.8 req/s; this is a median target, not a guarantee for every future run.
Against the earlier local `05f238b` reference, throughput improves by
**22.3%** and p95 falls by **20.1%**. The intermediate `756374d` clean
confirmation was 413.4 req/s / 307.0 ms.

The same seed, warmup10, iterations100, duration6s, repetitions3 and
generator are used. This selects100sessions plus the mandatory1-client
cells; the original baseline also includes10/50-session cells, a workload
order limitation. This is a version comparison: the new commit includes
combined HTTP-context reads, rendering/memoization and other async/UI
changes. It does not isolate the performance of Mojo::Pg against DBIx.

Authentication and mixed results in the previous report belong to
`756374d`; they must not be relabelled as `60c7b9f` results.
The earlier SQL/phase diagnosis likewise describes `05f238b`.

```sh
script/gpforum-carton exec script/benchmark-http-complete \
  --output artifacts/thread-60c7 --workers 8 --worker-clients 16 \
  --scenario member.thread --concurrency 100 \
  --iterations 100 --warmup 10 --duration 6 --repetitions 3 --deadline 900
```

Raw JSON, exact command, process monitor and SHA-256 checksums accompany
this report. The generator, application and database share the laptop;
these measurements do not establish a fixed-arrival production SLO.
This evidence-only branch keeps the running main CI uninterrupted.
