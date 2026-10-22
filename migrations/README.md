# Database migrations

The schema starts from the 1.0 baseline ([ADR 0150](../docs/adr/0150-the-schema-starts-from-a-1-0-baseline.md)):
24 files numbered 1000 to 1023 that build the whole database on an empty one.
A change after it is a new file, numbered after the highest.

## The baseline

| Files | What they hold |
| --- | --- |
| [1000_foundation.sql](1000_foundation.sql) | The trigram extension, schema `api` closed to `PUBLIC`, the migration ledger, the partition registry and the query budgets. Its header says what every table holds to: uuid ids, text with CHECK limits, closed sets as CHECK lists, timestamptz, partial and covering indexes, fillfactor on the rows updated in place. |
| [1001_identity.sql](1001_identity.sql) to [1010_privacy.sql](1010_privacy.sql) | The tables by area: identity, access, forum, records (commands, events, outbox, audit), community, notifications, moderation, attachments, search, privacy. Each table says what it holds, in a comment and in `COMMENT ON TABLE`. |
| [1011_api_core.sql](1011_api_core.sql) | The row types of `api` and the shared steps (`core_`). Its header says what every function holds to: invoker rights, a pinned `search_path` and plan mode, honest volatility, `LANGUAGE sql` for one statement. |
| [1012_api_session.sql](1012_api_session.sql) to [1022_api_operations.sql](1022_api_operations.sql) | The functions of `api` by area, each with a comment saying what it answers or does. |
| [1023_api_entry_points.sql](1023_api_entry_points.sql) | Every `SECURITY DEFINER` entry point (ADR 0127), in one place: each forwards its typed arguments to the version before it. |

Partitions are not named by a migration: `gpforum migrate --apply` makes the
window of months after the migrations (ADR 0113), and the daily timer keeps it
ahead.

## After the baseline

[1024_suspension_timestamptz.sql](1024_suspension_timestamptz.sql) adds typed
suspension lookups and participation gates. They compare timestamptz values
and consider every unrevoked suspension before choosing the newest active
one. The preceding entry points remain available during the application
restart. Apply it with `gpforum migrate`; no PostgreSQL restart is needed.

## Writing a migration

- A new file goes here, `NNNN_what_it_does.sql`, with the next number after
  the highest. The description in its name is what `gpforum migrate` prints.
- One transaction: `BEGIN;` on the first line and `COMMIT;` on the last, or
  no transaction control at all; the runner writes the file's
  `schema_versions` row inside that transaction. A file of several
  transactions is refused.
- An index on a table that already holds rows is built with
  `CREATE INDEX CONCURRENTLY` in a file that starts with
  `-- gpforum:no-transaction`, of plain statements each safe to run again
  (`DROP INDEX CONCURRENTLY IF EXISTS` first).
- Set `lock_timeout` (`SET LOCAL lock_timeout = '1s';`), so a migration waiting
  behind the application fails instead of stalling it.
- A table comes with `COMMENT ON TABLE` (t/05 asks for it).
- A function in `api` follows ADR 0126 and 0127, which t/641 holds every
  migration to: `CREATE FUNCTION`, never `OR REPLACE`; a version suffix and an
  area; `SET search_path = pg_catalog, pg_temp` and `SET plan_cache_mode`;
  `EXECUTE` revoked from `PUBLIC`; tables written with their schema; no
  dynamic SQL; `SECURITY DEFINER` only on a catalogue entry point that
  forwards to its implementation; never a table's row as its result (a row
  type of `api` or `RETURNS TABLE`); and reached from what the catalogue
  calls, so nothing in `api` is left that nothing calls.
- A change to a function is its next version, created beside the one before;
  the version before is dropped a release later (ADR 0126, section 2), and
  t/641's `%RETAINED_BOUNDARIES` lists it until then.

## Running and checking

`gpforum migrate` applies what is pending, then the partition window and the
query budgets; `gpforum migrate --check` says whether the database is where the
code expects it. The runner refuses a recorded file that changed, a migration
numbered below one already applied, and a database that records a migration
this code does not have: one the 0.x chain built (see
[docs/ops/upgrade.md](../docs/ops/upgrade.md)) or a newer release migrated.
`bin/gpforum help migrate` has the operator interface.
