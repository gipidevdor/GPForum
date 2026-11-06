# PostgreSQL configuration A/B — 2026-10-17

Both requested corpora completed: 100,000 and 1,000,000 search documents. The sized shared-host profile was applied, verified strict after an operator restart, and restored through its journal. **These runs do not establish a general latency or throughput improvement.** Several measured paths regressed.

Apple M4 (10 cores), 16 GiB RAM, internal SSD/APFS, macOS/Darwin 27, PostgreSQL 18.6 (Homebrew), Perl 5.44.0; local Unix socket. Other idle PostgreSQL clusters and ordinary desktop activity were left alone. This is one serial service run per arm/corpus, fixed A-before-B order, with warmups. It is not an HTTP, concurrency or production-capacity benchmark.

## Configuration and comparability

| Setting | Original A | Sized shared-host B |
| --- | --- | --- |
| shared_buffers | 16384 8kB | 262144 8kB |
| effective_cache_size | 524288 8kB | 786432 8kB |
| work_mem | 4096 kB | 4096 kB |
| maintenance_work_mem | 65536 kB | 131072 kB |
| random_page_cost | 4.0 | 1.1 |
| effective_io_concurrency | 16 | 100 |
| jit | on | off |
| max_connections | 100 | 100 |
| track_io_timing | off | on |

B reserves 8 GiB for the OS, application and other services: shared_buffers 2 GiB, effective_cache_size 6 GiB, work_mem 4 MiB and maintenance_work_mem 128 MiB. The dedicated 16 GiB starting profile (4/12 GiB, 8/512 MiB) is implemented and unit-tested; it was not the full profile activated for this colocated benchmark.

fsync, full_page_writes, synchronous_commit and autovacuum remained on in both arms. No durability setting was changed. The [reviewed plan](optimized-plan.json), [apply journal](apply.jsonl), [strict active verification](verify-optimized.json), and [restore journal](restore.jsonl) preserve the operational steps. The CLI itself never restarted PostgreSQL; restarts of this disposable cluster were separate operator commands.

The service harness reuses the existing SQL-function benchmark fixture and operations. One prepared template was cloned for A and B at each scale. Initial document counts and ID digests match:

| Corpus | Documents | Matching document-ID digest |
| --- | ---: | --- |
| 100k | 100,000 | `aee4cd3790f725f0dec7c1f9bb62ce50` |
| 1m | 1,000,000 | `64650f295615fbab430a5080648e7d06` |

Each operation has 5 warmups; reads have 100 samples at 100k and 30 at 1m, writes 30 at both sizes. Writes commit, so each clone grows through the same operation sequence. Search and autocomplete in this reused service benchmark use the 15-second session timeout. The web application normally sets a 2-second search budget: the approximately 3-second trigram result at 1m would exceed that budget.

## Observed service latency

Every cell is **A → B**, milliseconds. p50/p95/p99 and throughput for all 23 operations, raw samples, client CPU, backend CPU and RSS are retained in [comparison.json](comparison.json) and the four raw service reports.

| Corpus | Operation | p50 ms | p95 ms | p99 ms |
| --- | --- | ---: | ---: | ---: |
| 100k | search_full_text_common | 276.028 → 303.922 | 290.107 → 352.514 | 309.509 → 378.953 |
| 100k | search_full_text_rare | 1.908 → 2.491 | 2.361 → 2.972 | 4.215 → 3.764 |
| 100k | search_trigram | 305.721 → 329.464 | 312.700 → 371.709 | 316.530 → 400.630 |
| 100k | search_autocomplete | 5.304 → 6.176 | 5.715 → 7.177 | 6.390 → 7.232 |
| 100k | thread_page_member | 0.423 → 0.533 | 0.436 → 0.912 | 0.463 → 1.067 |
| 100k | home_page_member | 1.679 → 1.597 | 1.792 → 2.275 | 1.910 → 2.410 |
| 100k | category_index_member | 0.837 → 0.680 | 0.920 → 0.838 | 1.024 → 0.878 |
| 100k | new_thread | 1.490 → 2.212 | 1.700 → 2.652 | 2.169 → 3.703 |
| 100k | reply | 1.520 → 2.238 | 10.315 → 2.740 | 26.019 → 3.316 |
| 1m | search_full_text_common | 10.660 → 11.202 | 11.450 → 17.562 | 11.676 → 19.054 |
| 1m | search_full_text_rare | 2.616 → 2.733 | 2.814 → 2.962 | 3.255 → 3.529 |
| 1m | search_trigram | 3118.324 → 3098.978 | 3249.263 → 3155.201 | 3555.346 → 3297.889 |
| 1m | search_autocomplete | 5.222 → 6.678 | 5.450 → 8.376 | 5.761 → 9.391 |
| 1m | thread_page_member | 0.425 → 0.428 | 0.454 → 0.588 | 0.807 → 0.750 |
| 1m | home_page_member | 1.687 → 2.731 | 1.898 → 4.065 | 2.183 → 4.378 |
| 1m | category_index_member | 0.845 → 0.781 | 0.937 → 1.001 | 1.317 → 1.316 |
| 1m | new_thread | 1.511 → 2.275 | 2.559 → 3.978 | 2.655 → 4.103 |
| 1m | reply | 1.495 → 2.715 | 2.214 → 3.241 | 2.551 → 3.661 |

Small-sample p99 estimates and isolated before/after deltas are descriptive. The observations do not justify promoting this profile as a measured universal speedup.

## Resources and outbox

| Corpus/arm | Shared-buffer hit ratio | Blocks read into shared buffers | Timed client CPU s | Timed backend CPU s | Max observed backend RSS KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100k/baseline | 99.99% | 7,587 | 0.76 | 60.03 | 123,056 |
| 100k/profile | 100.00% | 2,696 | 1.03 | 64.48 | 113,968 |
| 1m/baseline | 42.95% | 1,694,353 | 0.27 | 94.42 | 196,384 |
| 1m/profile | 98.33% | 49,596 | 0.43 | 94.02 | 425,984 |

At 1m, the larger shared buffer pool reduced shared-buffer misses, while the trigram latency and backend CPU stayed similar. A PostgreSQL block read can be satisfied by the OS cache; this is not a physical-device read count. Baseline track_io_timing was off, so its I/O duration is unavailable. Raw pg_stat_io, database and WAL snapshots remain in each report. WAL/FPI totals vary with checkpoint timing and page layout and do not establish a WAL reduction attributable to tuning. Database counter deltas include setup and warmups and can reflect asynchronous statistics flushes; plan capture happens afterward.

CPU covers the calling Perl process and its PostgreSQL backend, excluding server background workers. ps has centisecond CPU precision. RSS contains shared mappings and must not be summed as private server memory.

Outbox uses the existing real PostgreSQL dispatcher benchmark, 1,000 fixed-ID messages, batch size 100, 1/2 worker processes and three repetitions per worker count. The transport records delivery without executing external handlers. Each table value is the median of the three runs, **A → B**; latency percentiles refer to batches, not individual messages.

| Workers | Messages/s | Batch p50 ms | Batch p95 ms | Batch p99 ms | Client CPU s | Backend CPU s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1419.17 → 1447.17 | 67.72 → 65.87 | 77.08 → 75.25 | 77.08 → 75.25 | 0.37 → 0.36 | 0.28 → 0.27 |
| 2 | 2794.40 → 2918.92 | 66.43 → 59.58 | 71.74 → 70.01 | 71.74 → 70.01 | 0.38 → 0.37 | 0.24 → 0.22 |

Use [baseline-outbox-resources.json](baseline-outbox-resources.json) and [optimized-outbox.json](optimized-outbox.json) for the comparable resource-instrumented pair. [baseline-outbox.json](baseline-outbox.json) is the earlier latency-only pass and is not used in the table. The instrumented baseline was repeated after restoring the original configuration; this pair is B then A. Worker resources and before/after I/O, WAL and buffer counters are retained for every repetition.

## Internal search plans

The four raw service files contain nested auto_explain ANALYZE/BUFFERS/WAL plans after warm calls, plus forced-index diagnostic plans, installed index definitions, analyze timestamps and function proconfig. Both actual and forced plans are distinguished; forced plans are diagnostics, not measured normal plans.

- This checkout has ranked v8/v7 and autocomplete v6/v5. Ranked v9/v10 and autocomplete v7/v8 are absent. No stored function, grant, ranking rule or candidate cap was changed.
- The boundary functions use force_generic_plan; their implementations use force_custom_plan. The existing search-optimization integration tests exercise parameter-dependent custom planning and equivalence after repeated calls.
- At 100k, common full text uses the vector/trigram BitmapOr, then performs 98,488 posts_pkey visibility lookups and sorts before keeping 1,000 candidates. Both configurations choose that shape.
- At 1m, common full text chooses idx_search_documents_created and stops at 1,000 candidates/lookups. Dataset selectivity/planner statistics change the choice; the larger corpus is not uniformly slower.
- Rare full text keeps the GIN vector path (14 matches at 100k, 143 at 1m). Trigram returns about 98,500/998,500 GIN candidates for recheck in this adversarial title corpus. Buffer tuning does not remove that CPU cost.
- Measured autocomplete uses `Dep`; the additional nested autocomplete plan uses the broad `Per` prefix. The actual GIN and temporal indexes are present and usable; their existence alone does not guarantee the best plan for every selectivity.

A separate query/index change would need ranking, visibility and candidate-limit equivalence tests and another controlled comparison. These measurements support keeping that issue explicit, not changing semantics in a configuration-enforcement patch.

## Validation and implementation files

The full local suite passed 543 files / 16,992 assertions. `make integration` passed
112 files / 11,689 assertions on PostgreSQL 18.6; the latest endpoint/control test
passed another focused 24 assertions. The full Perl::Critic ratchet passed with
15 baseline violations and zero new violations; syntax, formatting and architecture
checks passed. CI now exercises configuration apply/restore on its disposable
PostgreSQL 16/17/18 containers; those remote jobs were not dispatched here.
See [validation.json](validation.json) for scope and the complete changed-file list.

- Sizing/configuration: PostgresProfile, Config, generated environment example and admin settings.
- Runtime assessment: PostgresPerformance, Schema connection hook, RuntimeEvidence, Readiness and its operator findings/translations.
- Administration: PostgresPerformance command, Mojolicious adapter and existing verb registry.
- Measurement: reused bench-sql-functions workload, bench-postgres-configuration, PostgresMetrics and the real outbox benchmark.
- Verification: profile unit cases, isolated-cluster control cases, readiness check count and existing CI matrix.

## Artifacts and reproduction

- [Hardware, commands and provenance](hardware-and-runs.json)
- [All comparisons and resource deltas](comparison.json)
- [Planner statistics and installed function definitions](planner-statistics.json)
- [Original configuration restored and no pending restart](verify-restored-original.json)
- [Validation and changed files](validation.json)
- [Original 100k](baseline-100k.json), [profile 100k](optimized-100k.json)
- [Original 1m](baseline-1m.json), [profile 1m](optimized-1m.json)
- [Operator workflow and reproduction commands](../../../docs/ops/postgres-performance.md)

The measurement implementation was uncommitted over the recorded Git base. Instrumentation was extended during the run to preserve partial failures and share resource helpers; successful service workloads and quantile calculation stayed the same. PostgreSQL configurations and corpus identities are recorded per arm. A/B ordering, desktop activity, synthetic corpus distribution, ordinary migration-owner credentials used by the fixture, and serial operation scope limit extrapolation to production. Restricted runtime-role behavior is verified separately by integration tests.
