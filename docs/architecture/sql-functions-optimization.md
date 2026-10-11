# PostgreSQL function API: second optimization

This follows the [initial DBIx-to-function conversion](sql-functions-performance.md).
The comparison uses the already published function API as its baseline.
The current catalogue has 195 operations. The SQL lives in new immutable
migrations; applying them and reprovisioning the runtime role are operator
steps, separate from publishing or merging the code.

## Changes

[Migration 100](../../migrations/100_optimized_search_functions.sql) introduces
ranked search and autocomplete v3 implementations with narrow v4 definer
boundaries. The search candidate limit still follows the same ACL and live
placement checks. Ranking carries identifiers and ranking inputs through the
sort; a materialized result page bounds the subsequent body, title and author
lookups. The existing v1/v2 functions remain installed. Filter, date boundary,
rank, capped-candidate count, result order and application JSON remain equivalent.

[Migration 101](../../migrations/101_forum_post_context_functions.sql) introduces
`forum_post_context_v1/v2`. Modification, deletion and restoration fetch the
post and the existing thread head in one call. The shared thread visibility
gate still runs before the atomic write. Each successful workflow now needs
two client calls rather than three. Domain refusals, idempotency and the
write's lock order remain unchanged.

The optional ordered autocomplete index was measured and rejected: it did
not give a stable improvement and would add maintenance cost. No new index
is shipped in this batch.

## Alternating service measurements

The canonical [benchmark](../../script/bench-sql-functions) now accepts
`--paired-functions`. Both sides use stored functions: the published search
v2 and two-call post preflight are compared with search v4 and the combined
context. The adapter, atomic write function, database handle and dataset are
shared. This isolates the changed paths; it is not a comparison of two complete
application binaries. The implementation reference is
[`27ec747`](https://github.com/gpicchiarelli/GPForum/commit/27ec747bcf2acbe50c9c4221c37f1610cf09add3),
the published baseline is
[`2cb9945`](https://github.com/gpicchiarelli/GPForum/commit/2cb994530612205a422f9f0ba45078d5bc920b51),
and the measured harness is
[`8316f28`](https://github.com/gpicchiarelli/GPForum/commit/8316f283a12b2894951ab4c892e1f6324e611a7f).

Each run warms up with 15 pairs, then measures 200 read pairs and 100 write
pairs per connection mode. Odd pairs run before/after; even pairs run
after/before. Every search pair must return identical service JSON. Every
edit uses a new body and command ID and must write a revision. Raw records
retain wall time, Perl CPU, pair number, execution order, statements and
client round trips. Two runs contain 4,000 individual measured samples.

The tables give arithmetic means of the two per-run medians and p95 values
in milliseconds, and mean Perl CPU per operation. Quantiles are not pooled.
The harness sorts samples and selects zero-based index
`int(q * (n - 1) + 0.5)` for quantile `q`; with an even sample count its
median selects the upper central observation. Each operation's median
improved in both runs.

| Operation | Direct median before → after | Reduction | Direct p95 before → after | Direct CPU before → after | Calls before → after |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ranked search | 8.39 → 6.89 | 17.8% | 9.87 → 8.28 | 1.424 → 1.309 | 1 → 1 |
| Autocomplete | 3.66 → 2.90 | 20.8% | 5.19 → 3.82 | 0.464 → 0.420 | 1 → 1 |
| Edit a post | 1.73 → 1.62 | 6.6% | 2.30 → 2.01 | 0.481 → 0.389 | 3 → 2 |

![Direct service medians before and after optimization](evidence/sql-functions-2026-10-11-optimization.svg)

The proxy adds 0.5 ms in each direction. Its results show the effect of the
removed post-context round trip.

| Operation | Proxy median before → after | Reduction | Proxy p95 before → after | Proxy CPU before → after |
| --- | ---: | ---: | ---: | ---: |
| Ranked search | 10.29 → 8.65 | 16.0% | 11.85 → 10.16 | 1.604 → 1.488 |
| Autocomplete | 6.31 → 5.36 | 15.1% | 7.84 → 6.85 | 0.579 → 0.525 |
| Edit a post | 8.13 → 6.42 | 20.9% | 9.02 → 7.29 | 0.889 → 0.726 |

The raw [first run](evidence/sql-functions-2026-10-11-paired-1.json) and
[second run](evidence/sql-functions-2026-10-11-paired-2.json) include all samples.
They use PostgreSQL 18.6, Perl 5.44.0, an Apple M4 with 16 GiB and macOS 27.0.1.
Both paths use the fixture account; restricted-login correctness is tested
separately. Pairing reduces order and host-load bias but does not eliminate
it. These are service measurements on one host, excluding HTTP, concurrency
and throughput; no statistical significance or production latency is claimed.

To reproduce on a disposable database created by the harness, use a database
account allowed to create databases:

```sh
GPFORUM_DATABASE_DSN='dbi:Pg:dbname=postgres;host=127.0.0.1;port=55433' \
GPFORUM_DATABASE_USER=gpforum \
script/gpforum-carton exec script/bench-sql-functions --paired-functions --json
```

The harness migrates, seeds and drops its own database. Set the connection
and credentials for the local test server; it does not use a deployed forum.

## Earlier full service measurements

The original 20-operation harness ran twice on the published code and twice
on the optimized code. Each run created, migrated, seeded and dropped its own
database. This preserves the [original workload and measurement method](sql-functions-performance.md#measurement-method):
15 warm-ups, 200 read or 100 write samples, direct access and a proxy delaying
each direction by 0.5 ms, service elapsed time, p95, Perl CPU, exclusive DBIx/DBI
profiling, statements and client round trips. These runs exclude HTTP.

The table gives arithmetic means of the two per-run medians in milliseconds.
All four runs are retained, including the variable second optimized run.

| Operation | Direct before → after | Direct median change | Proxy before → after | Calls before → after |
| --- | ---: | ---: | ---: | ---: |
| Ranked search | 7.82 → 7.27 | −7.0% | 10.94 → 7.95 | 1 → 1 |
| Autocomplete | 3.57 → 2.91 | −18.5% | 6.17 → 5.69 | 1 → 1 |
| Edit a post | 1.38 → 1.61 | +16.9% | 9.43 → 5.35 | 3 → 2 |

The second optimized run slowed several unchanged operations too: the member
thread page median rose from 0.457 ms in optimized run 1 to 0.702 ms in run 2.
A process snapshot immediately afterward showed substantial CPU consumption
by unrelated SBCL and macOS indexing/file-provider processes. This is evidence
of host variation; it does not prove the cause of every slow sample. The full
runs do not establish a stable improvement in local post-edit latency; this
motivated the alternating comparison above. These records remain published.

The baseline code was
[`2cb9945`](https://github.com/gpicchiarelli/GPForum/commit/2cb994530612205a422f9f0ba45078d5bc920b51);
the optimized code was
[`27ec747`](https://github.com/gpicchiarelli/GPForum/commit/27ec747bcf2acbe50c9c4221c37f1610cf09add3).
The database was PostgreSQL 18.6, Perl 5.44.0, on an Apple M4 with 16 GiB
running macOS 27.0.1. Both paths used the fixture account; restricted-login
correctness is tested separately.

Raw measurements include every operation's median, p95, CPU, profiling and counts:

- Baseline [run 1](evidence/sql-functions-2026-10-11-optimization-before-1.json)
  and [run 2](evidence/sql-functions-2026-10-11-optimization-before-2.json).
- Optimized [run 1](evidence/sql-functions-2026-10-11-optimization-after-1.json)
  and [run 2](evidence/sql-functions-2026-10-11-optimization-after-2.json).

## Exploratory search measurement

A separate exploratory comparison used 1,100 additional real threads and
1,100 posts, about 12 KB of body text per document, a 1,000-candidate cap and
20-row page. It alternated v2/v4 calls in each measured pair, with five warm-up
calls per version and 60 samples per version per case in each of two rounds.
The timed unit was `SqlFunction->rows`: binding, execution and fetching rows;
parameter construction, service decoration and HTTP were excluded.

| Case, without a new index | Mean of v2 medians | Mean of v4 medians | Reduction |
| --- | ---: | ---: | ---: |
| Ranked query `Depth` | 12.58 ms | 7.59 ms | 39.7% |
| Autocomplete prefix `Dep` | 3.49 ms | 2.78 ms | 20.3% |

The [56 exploratory records and method metadata](evidence/sql-functions-2026-10-11-search-exploration.json)
retain both the no-index stage and the rejected ordered-index experiment.
The latter finished with a newest-first plan assertion failure after index
creation and `ANALYZE`; it is not shipped validation. This temporary variant
of the integration fixture saved median/p95 summaries, not individual samples
or plan JSON, and is not the canonical service benchmark. The final fixture
without that index passed 437 checks.

## Validation and activation

- The complete `make -j3 check` quality gate passed on clean commit
  [`013dd56`](https://github.com/gpicchiarelli/GPForum/commit/013dd56c48229df986db89502db1247b3f622f36):
  system Perl, syntax for 1,369 files, the suite without DSN (400 unit files
  and 96 integration files visited, 16,162 assertions), strict style with
  zero new violations, formatting and architecture. Most database integration
  tests skip without DSN; the separately executed tier below verifies them.
  The [validation evidence](evidence/sql-functions-2026-10-11-optimization-validation.json)
  records tested commits, counts, benchmark summaries and raw artifact hashes.
- The complete PostgreSQL integration tier passed on the isolated committed
  checkout: 96 files and 9,916 assertions. The benchmark smoke test checks
  paired sample counts, balanced order, exact comparisons and disposable
  database cleanup on success and on a missing-routine failure.
- Both new integration tests passed under NYTProf 6.15 and decoded to CSV.
  The [profile metadata and selected subroutine summaries](evidence/sql-functions-2026-10-11-optimization-profile.json)
  record commands, tested commit, times, call counts and artifact hashes.
  Profiling includes fixtures and both comparison paths, database waits and
  profiler overhead; those times are not operation latency. The large binary
  profiles and full CSV exports remain local and can be reproduced with the
  recorded commands.
- [Search differential and plan test](../../t/integration/postgres-search-optimization.t):
  437 checks, covering exact service JSON and raw typed rows, ACL combinations,
  candidate cap after filtering, dates, ties, stale category/space moves,
  nullable authors and Unicode/wildcard prefixes. Actual nested plans retain
  common newest-first and rare GIN paths and load at most 20 payload rows.
- [Combined context and restricted-login test](../../t/integration/postgres-sql-function-post-context.t):
  86 checks, covering legacy column/timestamp/boolean representations,
  inherited visibility, domain refusals, malformed IDs, edit/delete/restore,
  replay, conflicts and two-call workflow counts.
- The real runtime login can call search v4 and the post context, while direct
  table access and the retired search v1/v2 and implementation v3 calls fail.
  The static and live catalogue gates explicitly recognize retained versions
  and require exact typed forwarding for every definer boundary.
- The previous general CI exposed two failures outside the SQL paths:
  locale-dependent child-process stderr and TLS handshake classification.
  The locale failure is observed directly; the specific newer OpenSSL variant
  was inferred because the old log omitted its message. Regression fixtures
  now cover unavailable locales, handshake variants and certificate/read errors.

Apply migrations 100 and 101 with the ordinary migration owner, drain old
processes, reprovision using the new catalogue and start the updated release.
Reprovisioning grants current search v4 rather than v2. The
[runtime role runbook](../ops/sql-api-role.md) includes upgrade and rollback
steps and the separate optional Minion queue database boundary.
