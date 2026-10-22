# ADR 0150: The Schema Starts From a 1.0 Baseline

## Status

Accepted (2026-10-22). The owner asked for the migrations and the functions
of `api` to be rewritten as one coherent piece of software, "una specie di
1.0 a partire da ora", without breaking anything, with every difference
listed and proven rather than assumed. The owner decided, before any file was
written, that databases built by the 0.x chain are not upgraded, that the
functions nothing calls go, that the tables nothing reads and the empty
schemas go, and that `migration_safety` folds into `schema_versions`.

It amends ADR 0126 (section 2: no version is retained at 1.0; section 10: the
migration test holds every migration, the baseline's included, and a function
never returns a table's row), ADR 0113 (no migration names a month), ADR 0119
(the counter shards and their trigger are gone) and ADR 0127 (the entry
points are one file).

## Date

2026-10-22

## Context

The schema was the sum of 106 files, 001 to 135, about 23,500 lines. Read in
order they told a history: tables created in one file and altered in five
others, one-time data repairs (045 scrubbed login tokens, 046 backfilled
thread activity, 049 dropped partitions 038 had named by month, 051 folded
counter shards behind a trigger kept for the previous release), runner
exceptions for the files written before a rule (049, 051, the gap at 120), and
the versions of 89 functions kept for a previous release's workers. Nothing
had ever been released (version 0.001; decision O1 of 2026-10-09 removed
every compatibility shim), so that history protected no installation.

It also carried three things a 1.0 should not: fourteen tables of the first
blueprint that no function reads or writes, six empty schemas, and 154
functions whose result was a table's row (`RETURNS SETOF public.<table>`),
whose result type changed under a running worker whenever the table gained a
column (the "cached plan must not change result type" of ADR 0126, section 2).

## Decision

### 1. The baseline

The schema is built by 24 files numbered 1000 to 1023:

- 1000 to 1010: the tables, by area (foundation, identity, access, forum,
  records, community, notifications, moderation, attachments, search,
  privacy). Each table is created once, in its final shape, with its
  constraints and indexes beside it.
- 1011 to 1022: the functions of `api`, by area, in an order every
  SQL-language body (checked when it is created) can follow. 1011 holds the
  row types and the shared `core_` steps.
- 1023: every `SECURITY DEFINER` entry point, in one file, so the surface that
  takes the owner's rights is read in one place.

A file is never edited once applied. A change is a new file numbered after
the highest. Versions have four digits from now on, so the string
comparisons of versions in the code stay right.

### 2. Every object the code, the tests or the operators use is unchanged

Same name, signature, body and grants, unless it is one of the differences
below. The proof is a catalogue fingerprint (`script/schema-fingerprint`):
one sorted line per fact -- schemas, relations with their options and
grants, every column with its position, type, default and collation, every
constraint, index, trigger, sequence, type, comment and default privilege,
and every function's contract, settings, grants and the hash of its body. A
database the chain built and one the baseline built, both by
`gpforum migrate --apply` on PostgreSQL 18, differ only in these:

| | Difference | Why |
| --- | --- | --- |
| R1 | 89 `api` functions are gone: the versions kept for a previous release's workers, and two helpers nothing called | No release came before; nothing calls them (t/641 and the catalogue test now refuse a function the catalogue does not reach) |
| R2 | 14 tables, their indexes, the counter-shard trigger and its function are gone | No function, store or operator reads or writes them; the trigger was a shim for the previous release (ADR 0119) |
| R3 | The schemas `app`, `security`, `audit`, `search`, `jobs`, `analytics` are gone | Empty since the first blueprint |
| R4 | `schema_versions` gains `applied_by` and `execution_ms`; `migration_safety` is gone | It repeated the ledger with three columns always false or empty; one row per migration says what, when, who and how long |
| R5 | 28 row types of `api` (one per table some function answers with); the 154 functions that returned a table's row return the type, and the 77 implementations among them name its columns | A table that gains a column no longer changes a shipped function's result type; their contracts are identical once the table is put back for the type |
| R6 | 22 labels: four functions that read `clock_timestamp()` are `VOLATILE`, not `STABLE`; five reads are `STABLE`, not `VOLATILE`; thirteen pure helpers are `PARALLEL SAFE` | A label says what the function does (ADR 0126, section 3) |
| R7 | Every table carries a `COMMENT ON TABLE` | `\d+` says what a table holds |

The rows the baseline seeds are the chain's, less the dead table's. The
[evidence](../architecture/migration-baseline-1.0.md) lists every object of
each difference.

### 3. A database the 0.x chain built is not upgraded

The runner recognises one from `schema_versions` -- versions below 1000 the
tree does not have -- and refuses it before anything runs, in `migrate
--apply` and `migrate --check`, with one sentence that says what to do. A
database that records versions above the tree's (a newer release migrated it)
is refused the same way. Moving the data of a 0.x database into a fresh 1.0
one is a `pg_dump --data-only` and a restore in one transaction
([docs/ops/upgrade.md](../ops/upgrade.md)); it was done once on a seeded
database, and every row arrived, in the right partitions.

### 4. What every table and function holds to

The header of `1000_foundation.sql` and of `1011_api_core.sql` say it where
the SQL is; in short:

- **Types.** Ids are `uuid`, drawn by the application as UUIDv7. Text is
  `text` with a CHECK for a limit, never `varchar(n)`. A closed set of values
  is `text` with a CHECK listing them, not an enum type, so a new value is one
  constraint and not a type every function that names it depends on. Every
  instant is `timestamptz`.
- **Constraints** carry PostgreSQL's conventional names, because the code
  maps a violation to its constraint by name. Uniqueness that settles a race
  is a partial unique index stating the state it is unique in.
- **Indexes** are partial where every query that uses them states the
  predicate, and covering where a hot page reads only their columns, in the
  keyset order of the page. No index is a prefix of another with the same
  predicate.
- **Storage.** `fillfactor` is lowered only where a row is updated in place on
  a hot path (sessions 90, threads 90, thread_counters 80, rate_limit_buckets
  90), so an update that changes no indexed column stays HOT; spaces and
  categories are analysed after any change (`autovacuum_analyze_threshold =
  0`), because the search planner needs their statistics from the first one.
  Statistics targets stay at their default and there is no extended
  statistics object: the plan gate passes on every endpoint without one.
- **Partitions.** The append-only logs (`event_log`, `audit_log`,
  `notifications`) are partitioned by month on `created_at`, with a DEFAULT
  partition and BRIN indexes; no migration names a month.
- **Collation.** Columns use the database's collation; where an order must not
  depend on it (the canonical JSON's keys), the expression says
  `COLLATE "C"`.
- **Functions.** Implementations run with their caller's rights; only the
  entry points of 1023 take the owner's, and each forwards its typed
  arguments to the version before it and does nothing else. Every function
  pins `search_path = pg_catalog, pg_temp` and names its objects with their
  schema, and pins `plan_cache_mode`: generic where one plan serves every
  value, custom where the best plan depends on them (search). A read is
  `STABLE`, a write `VOLATILE`, a pure helper `IMMUTABLE PARALLEL SAFE`. One
  statement is `LANGUAGE sql`, branches and writes are PL/pgSQL. `STRICT` is
  not used: a function answers a missing argument with a refusal the code
  maps to words (ADR 0118), or raises 22023 naming it (ADR 0126, section 6),
  and `STRICT` would turn either into no row at all.
  `LEAKPROOF` is not used: it matters only behind row security or a security
  barrier view, which the forum has neither of, and needs a superuser. No
  function returns a table's row.

### 5. The rules after 1.0

t/641 holds every migration to ADR 0126 and 0127 and adds two rules: no
function returns a table's row, and every function in `api` is one the
catalogue reaches through the bodies it runs. t/05 asks every migration that
creates a table to comment it. A version a release keeps for the previous
one's workers is listed in t/641's `%RETAINED_BOUNDARIES` until a contract
migration drops it, as ADR 0126, section 2 says. Earlier ADRs that cite a
file under `migrations/` cite the 0.x chain; the objects they name are the
baseline's, under the same names.

## Consequences

- A fresh database is built in 24 transactions, about 0.3 s on the
  development laptop.
- Reading the schema means reading one file per area, in its final shape,
  with what each table and function holds and why.
- A database built before 1.0 has to be rebuilt; its data moves with one dump
  and one restore.
- The staging drill's upgrade path is now 1022 to 1023; it means more once a
  migration follows the baseline.
- The history of each object before 1.0 is in the ADRs and the CHANGELOG, not
  in the migrations.

## Alternatives Considered

- **Adopt existing databases.** Recognise a database the chain built from its
  checksums, apply a bridge with the differences above, and record the
  baseline as applied. It would have kept the demo databases without a
  restore, and made "chain plus bridge equals baseline" a test; the owner
  chose not to, as nothing was released and the bridge would be kept for no
  installation.
- **Keep the chain, add a squash file for new databases.** Two ways to build
  one schema, each to keep equal to the other.
- **One file.** 20,000 lines in one transaction: nothing to read by area, and
  a failure anywhere rolls back everything.
- **Number the baseline from 001.** A database the chain built would then
  meet files it recorded with other checksums, and be told its files
  "changed", which is not what happened.
- **`RETURNS TABLE` instead of row types.** The same decoupling, with the
  columns repeated in each of the 154 functions, and, in PL/pgSQL, output
  parameters named like the columns their bodies read.
- **SQL-standard bodies (`BEGIN ATOMIC`).** Their objects are bound when the
  function is created, and dropping one a body uses is refused. But the
  migration test reads bodies as text, PL/pgSQL has no such form, and every
  body would change: not for a baseline that is to prove it changed nothing
  else.

## References

- [The baseline's evidence](../architecture/migration-baseline-1.0.md)
- [migrations/README.md](../../migrations/README.md)
- [ADR 0126](0126-sql-lives-in-postgresql-functions.md),
  [ADR 0127](0127-separate-runtime-role-for-the-function-api.md),
  [ADR 0113](0113-rolling-monthly-partitions.md),
  [ADR 0119](0119-the-reply-count-lives-in-thread-counters.md)
