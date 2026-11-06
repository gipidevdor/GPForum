# Schema review

`postgresql-18.sql` is the schema produced by all migrations, including the
API function bodies, comments and grants. PostgreSQL 18's matrix job dumps
the database again after integration tests and fails with a SQL diff if the
snapshot differs. Its artifact contains the dump and diff even on failure.
The PostgreSQL 16 and 17 jobs also save their native dumps as evidence;
they are not compared across client versions.

Regenerate against a freshly migrated **disposable** PostgreSQL 18 database,
using the same role that applied the migrations:

```sh
PGHOST=/path/to/socket PGPORT=5432 PGUSER=gpforum_migration \
  script/gpforum-carton exec script/schema-snapshot gpforum_schema \
  > etc/schema/postgresql-18.sql
```

Review and commit the SQL diff together with the new migration. Run the same
command with `--check etc/schema/postgresql-18.sql` before the database name
to check it without changing the snapshot. A mismatch prints the actual SQL
and exits 1. `GPFORUM_PG_DUMP` selects the PostgreSQL 18 client; `PSQL` selects
psql. Libpq's `PG*` environment supplies the connection and password.

The script omits rolling month partitions (all non-default public partition
children), pg_stat_statements, version banners and psql's random restriction
key. It normalizes the migration owner's annotations/default privileges so
the snapshot compares across hosts. Default partitions, partitioned parents,
function SQL and explicit grants remain. Ordinary SQL content, including
whitespace in function bodies, is preserved. Snapshot SQL is for review;
install or upgrade with migrations, not by restoring this file.
