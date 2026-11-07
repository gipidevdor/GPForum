# Mojo::Pg regression investigation — 7 November 2026

The native transport regression had two distinct costs: excessive promise/event-loop
relays on reads, and repeated process creation plus PostgreSQL connection/session
initialization on writes and their security/visibility preflight. The previous
runtime already called typed stored functions directly on hot paths; removing the
ORM did not automatically remove their cost.

## Measured recovery

The table compares the same two-worker budget, fixture, locked dependencies and
TCP-only private PostgreSQL harness. Values are medians of two repetition
statistics; p95 columns are medians of cell p95 values, not pooled percentiles.

| Scenario | Regressed req/s | Fixed req/s | Change | Regressed p95, ms | Fixed p95, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Thread, 100 sessions | 128.9 | 151.5 | +17.5% | 796.6 | 704.0 |
| Publishing/community, 10 clients | 31.4 | 170.7 | +442.8% | 485.5 | 156.1 |
| Mixed, 10 clients | 94.4 | 170.3 | +80.4% | 278.6 | 83.7 |

Publishing/community is a complete HTTP journey, including its forms, publishing,
edits, likes/reactions, bookmarks, subscriptions and read markers. Its throughput
is HTTP requests/s, not posts/s. Mixed uses the harness's read/reply/read-marker
weights. All 8,704 responses in these selected comparison/confirmation cells
were valid, with complete planned-cell coverage and verified persistent effects.

The independent full-candidate pass measured publishing at **156.5
req/s / 189.1 ms p95** and mixed at **165.3 req/s /
91.6 ms p95**. It ran thread reads before the write scenarios;
the primary write comparison uses the matching write-only scenario list. Both
accepted passes are retained, rather than selecting the highest repetition.

Primary arms:

- [Native baseline, writes](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/attempts/verified-control-final/http-complete.json)
  and [native baseline, thread](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/attempts/verified-control-read/http-complete.json).
- [Complete fixed candidate, writes](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/attempts/verified-complete-c/http-complete.json)
  and [complete candidate, thread plus writes](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/attempts/verified-complete-a/http-complete.json).
- [Summary CSV](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/summary.csv), [summary JSON](summary.json), and
  [all attempts and exclusions](attempts.json).

## Comparison with the pre-migration runtime

The older runtime is commit `702e78821eb5644a8a6577f56cbb5b6f958a937d`.
Its migrations match the native control's migrations; the complete candidate adds
migration 2044. The same harness and dependency tree were used. The historical
arms each contain one launch with two repetitions, and used the original monitor.

| Scenario | Pre-migration req/s | Fixed req/s | Change | Pre-migration p95, ms | Fixed p95, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Thread, 100 sessions | 174.5 | 151.5 | -13.2% | 2390.5 | 704.0 |
| Publishing/community, 10 clients | 229.8 | 170.7 | -25.7% | 82.6 | 156.1 |
| Mixed, 10 clients | 199.1 | 170.3 | -14.5% | 81.8 | 83.7 |

The major regression is repaired, but throughput is still below the pre-migration
runtime in these cells. Thread tail latency is substantially better than that
older runtime at 100 sessions. Do not describe every performance dimension as
fully recovered. The remaining cost includes asynchronous orchestration and
isolated body preparation; this campaign does not attribute the entire remaining
difference to either component.

## Changes and preserved contracts

- Release admission slots and native leases before publishing completion. Ready
  results stay ready; admitted work and idle leases need no artificial tick.
- Use async/await in the hot adapters/services instead of repeated
  resolve/then/finally relays. Keep six SQL calls on the warm authenticated thread
  path, typed/binary bindings, stale-plan protections and request context.
- Move IP-ban, live participation, single-post and thread visibility lookups to
  their native promise methods. No security-result cache was introduced.
- Execute existing atomic community/read/posting commands on retained native
  connections. Small metadata-only posting preparation is pure parent work.
  Body composition and signing stay in the bounded child executor, where an
  unanswered synchronous SQL read fails the HTTP-access guard.
- Migration 2044 combines bookmark removal and subscription mute/revocation with
  command-log open/close in one call. It reuses the existing locked target stores,
  fixes the operation/column choices, binds the target owner to the command actor,
  pins search_path/plan mode and revokes PUBLIC execution. Only its typed v2
  boundary acquires owner rights.
- Keep extended moderation and mention transactions in the complete isolated
  executor. Preserve authorization, CSRF, live sessions, quotas, signatures,
  idempotency, audit/outbox atomicity and failure/replay semantics.

The query executor still retains two native leases per worker. Listener and
isolated workflow accounting keep the existing four-connection worker budget.
No concurrency limits, WAL durability settings or production worker defaults were
increased to obtain these results. The baseline already includes the separately
landed admission-queue capacity fix; its increase is not credited to this patch.

## Validation

- [General suite](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/verification/unit-complete.log): 535 files, 20,352 tests pass.
- [PostgreSQL suites](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/verification/pg-complete.log): 23 files, 6,636 tests pass.
  Coverage includes native HTTP transport, real SQL rollback after command-log
  close failure, replay/conflict, restricted API roles, IP bans, suspensions,
  visibility, moderation/first-post review, query budgets, async transactions,
  cancellation, live catalogue and canonical schema snapshot.
- [Critic](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/verification/critic-complete.log),
  [targeted formatting](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/verification/checks.json),
  [architecture](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/verification/architecture-complete.log), and
  [policy ratchet](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/verification/policies-complete.log) pass.
- Native command HTTP tests assert that primitive commands and their preflight
  perform zero subprocess calls, and that atomic SQL executes in the parent.
- [Source match](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/verification/source-match.json) checks that runtime, SQL and test
  files match the frozen measured source. Operational documentation was completed
  after the freeze.

The initial review-queue run used a private 40-connection fixture and exhausted it
because the test creates many application instances. It passed with the standard
100-connection test setting. This did not change runtime pool limits or benchmark
PostgreSQL settings. An initial targeted unit invocation named a nonexistent POD
test; the corrected invocation and the complete suite passed.

## Evidence and measurement limits

Apple M4 (10 cores), 16 GiB, macOS/arm64, Perl 5.44.0, Mojolicious 9.51,
PostgreSQL 18.6, EV/kqueue; generator and server share the host. Two web workers,
2048 admitted connections per worker; fixture: 103 users, 8 categories,
240 threads, 4,800 posts. Fsync, full_page_writes and synchronous_commit are on.
The private cluster uses TCP loopback, max_connections=80, the same JIT/memory
settings in each arm. Background delivery/realtime listeners are disabled in all
arms; outbox writes and application authorization remain exercised. This is
short, closed-loop local comparative evidence, not production capacity or a
mixed/realtime deployment SLO.

The original campaign monitor missed `perl -S prove`. A later full integration
suite overlapped `complete-a` and `complete-b`; both are excluded despite their
original false contamination flag. [Post-hoc evidence](posthoc-exclusions.json)
records that correction. The v2 monitor detects those processes, direct Perl
integration workers, other benchmarks and Node test runs. Its selected arms
have no detected competing verification. Unrelated OS activity and thermal
variation remain possible on this shared host. The disturbed
`verified-complete-b` is excluded as well.

Early candidates and failed/interrupted attempts are retained under `attempts/`.
`writes-a` was aborted during setup after a failed harness copy and is excluded.
Only the accepted arms use the common TCP harness for conclusions.
`diagnostics/` holds instrumented probes of intermediate candidates; timing
wrappers add overhead and these probes do not establish capacity. Their warm
read counter probe reduced 304 promise allocations to 105 with the same six SQL
calls. Write probes identified three avoidable child calls before a like; the
native HTTP tests verify their removal in the final candidate.

## Reproduce and deploy

The native control is frozen at
`79f3d0e8810f03b67a25563e12682e260b1d3303`. Create separate checkouts of that
commit, select the same Perl and locked dependency tree, and apply
[source/harness.patch](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/source/harness.patch) to both. Apply
[source/native-complete.patch](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/mojo-pg-regression/2026-11-07/source/native-complete.patch) only to the fixed
checkout. Frozen manifests in `source/` identify all overlays, including new files;
the harness dirty/diff metadata alone does not identify every overlay. The
archived campaign runners retain the original session-specific paths.

Run each arm sequentially into a new output directory, avoiding concurrent tests:

```sh
script/gpforum-carton exec script/benchmark-http-complete \
  --output /tmp/gpforum-write-measurement --workers 2 \
  --iterations 40 --warmup 10 --duration 4 --repetitions 2 \
  --concurrency 1,10,32,100 --deadline 600 \
  --scenario journey.publishing_community --scenario mixed
```

Use `--scenario member.thread` for the read comparison, with the same options.
Preserve complete outputs and process-monitor evidence for every attempt. The
accepted sequence was `verified-complete-a`, `verified-control-final`,
`verified-control-read`, then `verified-complete-c`. The disturbed
`verified-complete-b` was excluded. This was not a randomized statistical
experiment.

For a real deployment, apply `2044_native_community_targets.sql` and re-provision
the runtime API role before starting new workers. The migration is additive and
keeps previous entry points, so the previous application can be restored without
removing data. No production deployment was performed in this investigation.
