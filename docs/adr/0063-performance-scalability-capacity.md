# ADR 0063: Performance, Scalability and Capacity Engineering

## Status

Accepted.

## Date

2026-09-19

## Context

GPForum must serve large communities with heavy read concurrency, realtime
traffic and long-term data growth while staying operable by a small team.
Performance requirements must be defined early and measured through
tests, benchmarks, and operational metrics.

This ADR is foundational and mandatory. It defines the performance
principles, scalability architecture, latency discipline, throughput
strategy, resource management model, cache hierarchy, backpressure behavior,
load-shedding principles and long-term capacity engineering standards. It
governs web and worker processes, PostgreSQL query and partition design,
caches, realtime connections, queues, search, asset delivery, frontend
rendering and benchmarking across all bounded contexts.

## Decision

### Measurability

- Per ADR 0093, every performance claim MUST be measurable.
- Hot paths MUST have bounded query-cost expectations, profiling capability,
  and tests or benchmarks where feasible.
- OFFSET pagination on hot forum paths is prohibited.
- Performance regressions that break documented budgets are release-blocking
  engineering failures.

### OS Awareness

- Per ADR 0097, performance MUST also be OS-aware.
- macOS, FreeBSD and Linux behavior MUST be detected through `GPForum::OS`,
  not scattered `$^O` checks.
- Hot paths MUST avoid fork-per-request, blocking I/O, unbounded caches, long
  transactions, repeated parsing and unnecessary synchronous filesystem work.
- OS-specific optimizations require fallback, feature flags, documentation
  and profiling evidence.

### Scalability Invariants

- Per ADR 0099, performance work MUST preserve hot-path query topology,
  projection stability, hot-row avoidance, outbox separation, cache
  disposability, search derivation, migration online safety and graceful
  degradation under worker or projection failure.

### Performance Principles

- Performance is an architectural property, an operational discipline and a
  scalability constraint system.
- Performance MUST prioritize predictability, bounded latency, graceful
  degradation, operational sustainability and distributed scalability.
- The platform MUST avoid uncontrolled resource amplification, latency
  spikes, unbounded memory growth and hidden scalability cliffs.

### Scalability Principles

- GPForum MUST scale horizontally, incrementally, through multi-process Perl
  capacity and operationally predictably.
- The architecture MUST assume millions of users, massive read concurrency,
  distributed websocket traffic, asynchronous event propagation and
  long-term data growth.
- The platform MUST prioritize stateless application nodes, multiple Perl
  processes per node, dynamic worker and web process counts, asynchronous
  processing, partition-aware persistence and cache efficiency.

### Capacity Engineering Principles

- Capacity planning MUST remain measurable, observable, proactive and
  continuously validated.
- The platform MUST support node replacement, rolling scaling, workload
  isolation and capacity forecasting.

### Latency Principles

- Latency MUST remain bounded, measurable and operationally observable.
- Critical user-facing workflows SHOULD prioritize low p95 latency, low p99
  latency and graceful degradation under load.
- Latency spikes MUST remain diagnosable, attributable and operationally
  visible.

### Throughput Principles

- The architecture MUST optimize for high concurrent reads, bounded write
  amplification, asynchronous fanout and distributed workload handling.
- The platform MUST avoid synchronous bottlenecks, centralized coordination
  hotspots and global serialization points.

### Resource Management

- All workloads MUST maintain bounded memory usage, bounded concurrency,
  bounded process counts, bounded thread counts where threads are used,
  bounded queue growth and bounded connection usage.
- The system MUST avoid uncontrolled buffering, unbounded websocket fanout
  and unbounded worker accumulation.

### Stateless Scaling

- Application nodes MUST remain stateless, disposable, horizontally scalable
  and vertically scalable through process multiplicity.
- The architecture MUST support rolling deployment, autoscaling, node
  replacement and workload redistribution.
- No application node may become irreplaceable.

### Database Scaling Principles

- PostgreSQL scaling MUST prioritize partitioning, replica reads, bounded
  transactions, index efficiency and append-oriented persistence.
- The platform MUST avoid giant mutable tables, unbounded scans and
  destructive cleanup workloads.

### Query Discipline

- Queries MUST remain bounded, indexed, partition-aware and
  pagination-aware.
- Forbidden: unbounded ORM loads; `SELECT *` on large datasets; unrestricted
  joins; unbounded aggregation scans.
- All high-volume queries MUST support deterministic execution plans,
  selective indexes and explicit ordering.

### Partitioning Principles

- Partitioning is mandatory.
- Partitioning MUST reduce vacuum pressure, reduce index bloat, support
  retention and improve operational predictability.
- The architecture MUST support partition pruning, partition rotation and
  partition archival.

### Cache Principles

- Caching MUST remain explicit, observable, disposable and
  authorization-aware.
- Caches MUST NOT become canonical persistence or hidden business authority.
- Preferred cache targets: rendered fragments, expensive aggregates,
  anonymous content, search projections.

### Cache Hierarchy

- Recommended cache layers: CDN cache, edge cache, application cache,
  fragment cache, search cache.
- Each layer MUST remain independently invalidatable and operationally
  observable.

### Cache Invalidation

- Cache invalidation MUST remain explicit, event-driven where possible and
  bounded.
- The architecture MUST avoid uncontrolled cache staleness and hidden
  invalidation coupling.

### Realtime Scaling

- Realtime infrastructure MUST support distributed websocket nodes,
  incremental propagation, asynchronous fanout and connection recovery.
- Realtime systems MUST avoid centralized websocket ownership and
  synchronous broadcast bottlenecks.

### Connection Management

- The platform MUST support high websocket concurrency, connection lifecycle
  management, idle timeout policies and reconnect workflows.
- Connection handling MUST remain memory-aware, resource-bounded and
  operationally observable.

### Backpressure Principles

- The platform MUST support graceful degradation under load, queue
  backpressure, rate limiting and overload protection.
- The system MUST prefer controlled degradation over catastrophic collapse.

### Load Shedding

- The architecture SHOULD support selective workload shedding, degraded
  realtime behavior, delayed non-critical workflows and queue prioritization.
- Critical persistence workflows MUST remain prioritized.

### Queue Scalability

- Worker systems MUST support workload isolation, queue prioritization,
  distributed execution and autoscaling.
- Queue growth MUST remain observable, bounded and recoverable.

### Search Scalability

- Search infrastructure MUST support worker-distributed indexing,
  partition-aware PostgreSQL scaling, asynchronous ingestion and rebuild
  workflows.
- Search failures MUST NOT block persistence workflows or posting workflows.

### Asset Delivery

- Static assets MUST support CDN delivery, immutable caching, compression and
  fingerprinting.
- Asset delivery MUST remain horizontally scalable and cache-efficient.

### Frontend Performance

- Frontend rendering MUST prioritize server-side rendering, incremental
  updates, minimal JavaScript and cache-friendly delivery.
- The platform MUST avoid hydration-heavy architectures and giant frontend
  runtime costs.

### Observability of Performance

- Performance metrics MUST include request latency, websocket latency, queue
  latency, cache hit ratio, database latency, replication lag and event
  propagation delay.
- Performance visibility is mandatory.

### Capacity Limits

- The architecture MUST support configurable operational limits, queue
  limits, connection limits, upload limits, search limits and API rate
  limits.
- The system MUST remain bounded, controllable and abuse-resistant.

### Failure Principles

- The platform MUST assume traffic spikes, node crashes, queue backlog,
  replica lag, websocket storms and abusive clients.
- The architecture MUST degrade gracefully.

### Benchmarking Principles

- Performance testing SHOULD include concurrency testing, websocket testing,
  queue stress testing, indexing stress testing, partition scaling tests,
  profiling runs, memory growth checks and slow query analysis.
- Profiling MUST be part of performance engineering.
- The system SHOULD retain comparable profiling artifacts between releases.
- Performance assumptions MUST remain measurable and reproducible.

### The 5,000-connection gate (2026-10-17)

Every performance run holds 1,000 and 5,000 keep-alive connections against
`/health/live` on four workers, three 10-second samples each, and requires
zero errors within a three-second response timeout. That is the bar, and
the gate does not lower it to pass:

- It is all or nothing. The sweep's saturation stop (a p95 over two seconds
  at 1,000 skipped 5,000) does not apply to it, and a planned cell or
  repetition that was not measured fails the suite instead of leaving it
  `partial` with exit status 0. The final CI step checks the gate's own
  summary (`performance-workflow-status --check --gate DIR`), which must be
  `ok`; the main suite keeps its tolerance for `partial` timing data.
- It measures what it claims. It refuses a kernel listen queue
  (`net.core.somaxconn`) shorter than the burst, records `ListenOverflows`
  and `ListenDrops` across each sample, warms the workers with a
  three-second pass at the same concurrency (recorded in the row, not
  counted in the sample, which still opens every connection at once) and,
  on Linux, records each worker's connections halfway through the sample.
  The workers stay four, the runner's CPUs, and each may hold all 5,000
  connections: the workload is not capped per worker.
- It records why a sample passed or failed. A closed loop of N connections
  served at R requests/s waits N/R on average. A Mojolicious worker serves
  the requests ready in one event-loop turn and writes their responses in
  the next, so the loop runs in turns about N/R long and a request that
  just missed one waits two: 2N/R. Each sample records its p99 margin to the
  budget, N/R, 2N/R and the R at which two turns fit, 3,334 requests/s at
  5,000 connections. Timeouts on a sample below that are classified
  `runner_below_bar`, and the report says the runner cannot hold 5,000
  connections within three seconds.
- The runners do not all reach it, and the evidence says so. In 60 samples
  from 20 runs on 2026-10-16/17, the hosted four-CPU runner served
  5,970-6,560 requests/s on AMD EPYC 9V45 hosts and 3,240-4,470 on EPYC 9V74,
  with no timeouts, but 2,790-3,190 on EPYC 7763 and Xeon 8370C/8573C hosts,
  where the p99 reached 2.9 s and 23 of 42 samples timed out; none above
  3,110 requests/s did. The p99 (of the requests that completed) reached
  1.06-2.09 times N/R. Capping each worker at 5% over its even share
  (66f859f) still timed out on a Xeon 8370C, and taking one connection at a
  time from the TCP listener (26c849b) timed out at 1,000 as well. On the slower hosts the gate fails; what moves the
  line is what a worker serves per second.

### Operational Sustainability

- The platform MUST remain operable by small teams, understandable under load
  and recoverable during incidents.
- Operational simplicity is a scalability feature.

### Long-Term Performance Goal

- GPForum performance architecture MUST remain horizontally scalable,
  latency-aware, operationally predictable, resilient under high
  concurrency and sustainable under long-term growth.
- Performance work requires measurable distributed systems behavior.
- All future scalability and performance decisions MUST comply with this
  ADR.

## Consequences

- `t/09-architecture-documentation.t` checks ADR structure, index navigation,
  and references to repository artifacts.
- Performance becomes a gated property: hot paths carry query budgets,
  profiling evidence and benchmarks and never use OFFSET pagination, and a
  broken budget blocks a release.
- Every workload has explicit limits (memory, processes, queues, connections,
  uploads, search, API rate), which operators must size and observe; the
  platform sheds or delays non-critical work before persistence suffers.
- Stateless multi-process nodes, disposable caches and derived projections
  keep scaling horizontal and node replacement routine, at the cost of
  maintaining invalidation, rebuild and partition-rotation machinery.
- Open conflicts:
  - "Partitioning is mandatory" names no tables. Today only `event_log`,
    `audit_log` and `notifications` are range-partitioned (ADR 0012);
    `posts`, `threads` and `search_documents` are not, so the required
    partitioning scope is undefined.

## Related Decisions and Implementation

- ADR 0093 (verifiable invariants), ADR 0097 (OS-level performance), ADR 0099
  (operational scalability and projection stability).
- ADR 0088 (multi-process runtime scalability), ADR 0089 (profiling and
  coverage), ADR 0067 (cache and coordination decision), ADR 0051
  (database), ADR 0050 (infrastructure), ADR 0056 (workers and queues), ADR
  0055 (realtime), ADR 0062 (search), ADR 0054 (frontend rendering).
- ADR 0006 (LISTEN/NOTIFY realtime transport), ADR 0012 (operational
  profiles and partition lifecycle), ADR 0019 (public HTTP cache), ADR 0048
  (GlifiStore L2 cache).
- `lib/GPForum/OS.pm`, `lib/GPForum/OS/`, `gpforum benchmark`,
  `gpforum budgets`, `gpforum query-plan-evidence`.
- `bin/gpforum budgets`, `script/query-plan-check`,
  `bin/gpforum query-plan-evidence`, `script/benchmark-http`,
  `bin/gpforum hypnotoad-benchmark`, `bin/gpforum hypnotoad-scaling`,
  `script/profile-nytprof`, `bin/gpforum performance-seed`.
- The 5,000-connection gate: `script/lib/GPForum/Performance/HTTP.pm`,
  `script/lib/GPForum/Performance/WorkflowStatus.pm`,
  `.github/workflows/performance.yml`, `benchmarks/README.md`,
  `t/705-performance-stress-gate.t`.
- `docs/PERFORMANCE.md`, `docs/PERFORMANCE.md#evidence-and-how-to-reproduce-it`,
  `docs/PERFORMANCE.md#database`, `docs/PERFORMANCE.md#query-budgets`,
  `docs/PERFORMANCE.md#profiling`, `docs/PERFORMANCE.md#os-tuning`,
  `docs/architecture/partition-lifecycle.md`.
- `t/21-forum-pagination.t`, `t/36-os-performance.t`,
  `t/38-query-budget-command.t`, `t/47-query-plan-check.t`,
  `t/49-performance-harness.t`, `t/89-tiered-cache.t`,
  `t/99-partition-lifecycle.t`, `t/09-architecture-documentation.t`.
