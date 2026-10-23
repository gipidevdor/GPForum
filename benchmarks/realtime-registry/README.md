# Realtime registry measurements

Local comparison on 2026-10-23, using the same Perl runtime and workload for
both versions. This measures the process-local connection registry, not a
WebSocket server, network delivery, PostgreSQL throughput, or deployment capacity.

Each of three repetitions registers and subscribes 100, 1,000 or 5,000 distinct
users, looks up one notification channel 5,000 times, then disconnects everyone.
Every lookup must return exactly one recipient. The baseline registry is from
commit `2036a63`; the raw files also record SHA-256 fingerprints of both source
versions. `comparison.json` records the median of the three runs.

| Connections | Register + subscribe, before / after | 5,000 recipient lookups, before / after |
| --- | --- | --- |
| 100 | 2.57 / 1.01 ms | 39.10 / 4.43 ms |
| 1,000 | 192.03 / 10.37 ms | 521.64 / 4.57 ms |
| 5,000 | 4,586.15 / 49.34 ms | 2,744.32 / 4.50 ms |

At 5,000 connections, registration/subscription is 92.9 times faster and
recipient lookup is 610.1 times faster in this workload. Lookup time stays
roughly constant because it now reads the target channel's index, rather than
scanning every socket. User quota checks use a counter rather than a full scan.
Channels with many recipients still require work proportional to those recipients.

There is a tradeoff: index cleanup makes disconnecting 5,000 sockets take
13.42 ms rather than 4.19 ms. The indexes also require memory proportional to
live users and subscriptions. They contain ids and counters, and prune empty
entries on disconnect; they do not retain extra socket references or historical
channels. The existing per-user and per-socket quotas remain unchanged.

Reproduce from the repository root on either registry revision, using the same
harness in both runs:

```sh
script/gpforum-carton exec perl benchmarks/realtime-registry/benchmark.pl
```

Evidence: [baseline](2026-10-23/baseline.json),
[optimized](2026-10-23/optimized.json),
[comparison](2026-10-23/comparison.json).

Regression coverage: `t/729-realtime-registry-indexes.t` checks quota and
replacement behavior, idempotent subscriptions, seeded registries, disconnect
cleanup and churn. An instrumented hash verifies that a recipient lookup among
2,000 connections fetches one row without enumerating unrelated connections;
quota checks fetch none. These are operation-count assertions, not timing gates.
Existing hub, listener, real-WebSocket snapshot and session-end tests cover the
integration boundaries.
