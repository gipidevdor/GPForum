# PostgreSQL operator diagnostics

For request correlation, structured warnings and browser SQL timings, see
[request diagnostics](request-diagnostics.md). Schema review evidence is
documented in [the snapshot directory](../../etc/schema/README.md).

`script/postgres-diagnostics` produces a bounded, versioned read-only snapshot
on PostgreSQL 16–18. It complements request query budgets and actual reader
plans; it does not run a workload, install an extension, vacuum, reset counters,
change privileges or tune the server. The application does not load its modules.

## Collect and validate

Use the operator environment in the shell, with the locked Perl dependencies:

```sh
script/gpforum-carton exec script/postgres-diagnostics --json > diagnostics.json
script/postgres-diagnostics --validate diagnostics.json
bin/gpforum evidence-validate --strict --human diagnostics.json
```

The first command reads `GPFORUM_DATABASE_DSN`, `GPFORUM_DATABASE_USER` and
`GPFORUM_DATABASE_PASSWORD` from the shell. It does not automatically source
the production service environment. Keep credentials in the existing private
operator environment or `.pgpass`, not command-line arguments or evidence.
Validation uses core Perl and [schema v1](postgres-diagnostics-schema-v1.json).
`--limit N` accepts 1–100 rows (25 by default) for table/index/query rankings.
`--require-statements` makes unavailable query observations a nonzero result;
the disposable CI matrix uses it. Normal collection remains usable without
an optional extension and returns a report marked `degraded`.

The dedicated connection uses five-second connection timeout, two-second
statement and half-second lock limits. It opens a read-only transaction with
a fixed catalog search path, isolates each section with a savepoint and rolls
everything back. It refuses an existing caller-owned transaction.

## Optional statement statistics

`pg_stat_statements` requires shared preload and a server restart, plus
`CREATE EXTENSION pg_stat_statements` in each inspected database. Activation
is an operator decision; do not overwrite a host's existing preload list.
Keep the extension under the operator's ownership, not the web login.
These are PostgreSQL's [documented requirements](https://www.postgresql.org/docs/16/pgstatstatements.html).

Start with planning tracking off and top-level tracking if that provides
enough evidence. `track = all` observes nested SQL-function statements;
`track_planning = on` enables planning cost/variability at additional overhead.
CI enables both only on its disposable service. Review overhead on a staging
workload before changing production settings.

The report ranks current-database observations by cumulative execution time
and records calls, mean/stddev execution and planning times, buffer hit/read/
dirty/write counters, temporary blocks and WAL records/FPI/bytes. Disabled
planning fields are null and `planning_measured` is false. The same applies to
planning times for a statement with zero observed planning calls, even when
tracking is currently enabled. Cumulative counters may span changes in the
tracking configuration. It explicitly calls
`pg_stat_statements(false)` and never selects the SQL text column: normalization
alone does not reliably remove all sensitive literals.

The extension's counters are cumulative. Capture the beginning and end of a
controlled workload; check the same server, database, role OID, top-level flag,
query ID and reset window before calculating deltas. A stored-function call
includes nested execution, so adding its total to nested totals double-counts
work. Query IDs are not a stable cross-major or independently recreated
database identifier. Existing `performance-hotpaths` comparisons use named
scenarios and deterministic fixtures instead.

Ordinary observers see only their own query IDs; `pg_read_all_stats` supplies
broader visibility and can expose other sessions' private data outside this
tool. Grant it only to a separate trusted observer if necessary. Do not add
`pg_monitor`, superuser, table rights or monitoring memberships to the
restricted web/worker login. Limited visibility is explicitly reported.

## Existing nested plan diagnostics

Use the existing command on a disposable seeded database:

```sh
bin/gpforum query-plan-evidence --functions --analyze --check --json > plans.json
```

It loads `auto_explain` only for its dedicated diagnostic session, sets
sampling to one for the deterministic gate, disables parameter logging,
collects buffers/WAL and rolls the transaction back. The six-call warm-up
policy and deterministic plan rules remain in place. Numeric metrics are
recorded per nested statement, without publishing Query Text, Filter values,
raw plans or bind values and without summing inclusive nested counters.
Unavailable metrics remain null; unmeasured plans fail the existing gate.

For production investigations, choose a bounded slow-query threshold and a
low sample rate through the operator's PostgreSQL configuration. Start with
`log_analyze = off`. If actual rows/buffers are necessary, enable it briefly
with `log_timing = off` and `log_parameter_max_length = 0`, then disable it.
Even with parameter logging off, raw plans can contain literals: restrict
database logs and do not attach them to public CI reports. Per-node timing
has overhead for instrumented statements even when they are too fast to log;
see the [PostgreSQL auto_explain documentation](https://www.postgresql.org/docs/16/auto-explain.html).

## Maintenance interpretation

| Section | Measurements | Interpretation |
| --- | --- | --- |
| database | commits/rollbacks, deadlocks, temporary bytes, buffer counters, size, XID age, reset time | Counters since reset; no instantaneous deadlock rate |
| tables | estimated live/dead rows, changes since analyze, scan/churn counters, vacuum/analyze timestamps, leaf XID age, relation/index size, table vacuum options | Dead tuple estimates are not physical bloat; empty estimates yield null percentages |
| indexes | size and scan counters; valid/ready/unique/primary/partial/constraint flags | Zero scans in a short or reset window do not justify dropping an index |
| activity | aggregate active/idle client transactions, row waiters, blocked client backends and oldest client transaction; collector connection excluded | Autovacuum and parallel workers are excluded; no statement, username, client address or session identifier is published |
| wal/archive/checkpoints | records/bytes/FPI, archiver successes/failures/times, timed/requested checkpoints, write/sync time | Cluster-wide counters include other applications and databases |
| settings | strict configuration allowlist and pending-restart flags | No archive/restore commands, connection strings, source files or secrets |

PostgreSQL 16 checkpoint counters come from `pg_stat_bgwriter`; 17/18 use
`pg_stat_checkpointer`. Table diagnostics inspect heap/materialized-view
relations and partition leaves; partition parents have no heap or meaningful
`relfrozenxid`. Their existing horizon/retention diagnostics remain in
`gpforum partitions`. Rankings are bounded and are not an exhaustive
catalog audit.

Use multiple snapshots and real growth/churn before tuning per-table vacuum
or analyze thresholds. Existing search ACL tables already carry per-table
analyze settings; re-evaluate them against measured churn. Compare estimated
dead tuples with size growth and actual vacuum progress; investigate long
transactions before blaming autovacuum.
There is no automatic `VACUUM FULL`, index drop, historical deletion or global
parameter change. Current settings and stats reset boundaries are evidence,
not a recommendation based on a tiny fixture.

## Activation, rollback and retained evidence

The collector works immediately with existing operator access. Without the
optional extension, install nothing and inspect its explicit unavailable
section. A connection failure produces `fail`, never `ok`.
Local reports include commit SHA and dirty-tree status. CI validates JSON and
keeps diagnostics in artifacts for 14 days; sensitive raw SQL logs are not
part of these reports. The existing permanent HTTP/SQL/outbox performance
history is unchanged.

Rollback the tooling independently of application migrations. If an operator
enabled optional logging, restore the preceding logging settings. Removing
a shared preload library requires its own planned server restart. Never reset
shared counters or delete an extension another application uses during cleanup.
