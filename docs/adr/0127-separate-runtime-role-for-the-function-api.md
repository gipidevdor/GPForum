# ADR 0127: Separate Runtime Role for the Function API

## Status

Accepted (2026-10-11). The owner requested that PostgreSQL enforce execution
through stored routines and that performance be measured after conversion.
This amends the security model of ADR 0126, section 7; its versioning,
fixed search paths, plan gates and immutable migrations continue to apply.

## Context

The application role currently owns the database and its tables. An owner
cannot give up its implicit table privileges by revoking grants. An invoker
function also requires its caller to hold table privileges. Moving the SQL
text alone therefore cannot enforce the requested database boundary.

## Decision

Keep migration credentials separate from the web and worker credentials.
The runtime login owns no objects, has no administrative attributes and
belongs to no other role. `NOINHERIT` alone is insufficient because a member
can still use `SET ROLE`.

Each of the 194 catalogue operations uses a new `SECURITY DEFINER` entry
point. Migrations 059 and 099 create `_v2` wrappers that forward the typed
arguments to their own `_v1` implementations; they change no shipped
function. Migrations 055–070 complete the runtime implementations for forum,
identity, permissions, community, notifications, search, moderation, admin,
attachments, privacy, portability, plugins, outbox, projections, workers
and operational reads and writes. The wrappers use
`LANGUAGE sql`, a fixed `search_path = pg_catalog, pg_temp`, and an explicit
plan mode. The implementations and shared `core_` helpers remain invoker
functions. The wrapper owner is a plain migration/data role, never a
superuser or a role that bypasses row security.

`GPForum::Service::Operations::ApiRole` prepares and applies individual
signature grants in a transaction. It refuses unsafe roles and owners,
revokes direct table/sequence access and public execution, and grants
`USAGE` on `api` plus `EXECUTE` on the catalogue entry points only. Helpers
and the underlying implementations are not executable by the runtime
login. It verifies both table and column privileges before committing.

This is a dedicated database. Revoking `PUBLIC` temporary-table creation,
schema creation and function execution affects its other logins too; their
explicit privileges must be intentional. PostgreSQL will still accept
session commands and expressions such as `SELECT 1`. The enforced property
is that application data cannot be read or changed through arbitrary SQL.

The application's credentials switch only after every runtime area calls
the function API. Provisioning never silently changes the credentials of
an existing application. Migrations, fixtures, connection settings,
`LISTEN` and external administration remain the exceptions of ADR 0126.
DBIx::Class remains the schema and transaction bridge. PostgreSQL services
select the function adapter automatically; their previous implementations
remain available to memory test doubles and the explicit benchmark baseline.
An unconfigured real schema is an error, rather than an implicit fallback.

## Validation

The migration gate permits definer rights only for a versioned catalogue
boundary forwarding to exactly its own implementation. The live catalogue
gate checks both versions, their types, search paths, plans and public ACLs.

The PostgreSQL role test connects as a distinct login and exercises real
read and write calls. PostgreSQL must refuse table and column reads, data
modification, `TRUNCATE`, `COPY`, schema and temporary-table creation,
helper calls, underlying implementation calls and `SET ROLE`. Provisioning
must refuse an administrative function owner and role membership.

Performance comparisons run the old DBIx path and the function path over
the same seed, including the definer boundaries, warm-up, median and p95,
Perl CPU, exclusive DBIx/DBI time, statement counts and network round trips.
The delayed proxy checks the cost when PostgreSQL is on another host.

The completed conversion and measured results are recorded in
[the performance comparison](../architecture/sql-functions-performance.md).
The [runtime role runbook](../ops/sql-api-role.md) describes activation and
the separate credentials needed for migrations and partition maintenance.

## References

- [PostgreSQL function security](https://www.postgresql.org/docs/18/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY)
- [PostgreSQL privileges](https://www.postgresql.org/docs/18/ddl-priv.html)
- [ADR 0126](0126-sql-lives-in-postgresql-functions.md)
