# ADR 0174: Mojo::Pg is the runtime stored-function transport

## Status

Accepted (2026-11-06).

## Decision

`GPForum::Schema` owns `Mojo::Pg` through `Infrastructure::PgStorage` and no
longer inherits DBIx::Class, loads result models or exposes resultsets.
Domain reads and writes use the fixed, typed `api.*_vN` stored-function
catalogue. PostgreSQL functions retain their existing result and transaction
contracts; no client-side table SQL or ORM query generation is introduced.
The query-plan command defaults to those same function calls.

Connection/session settings, transaction/savepoint control, LISTEN/NOTIFY,
schema migrations and administrative inspection remain infrastructure work.
Mojo::Pg itself uses DBD::Pg and DBI; removing DBIx does not remove that driver.

## Transaction and connection contracts

A synchronous worker retains its Mojo::Pg database object across calls.
Nested transactions use savepoints. Joining an already-open transaction does
not commit its caller. Exceptions preserve the original failure after rollback.
Forks obtain a new connection and never close the parent's socket. Reconnect
and stale-result-plan retries are bounded and do not replay an open transaction.
`pg_prepare_now` is enabled from the first prepared call to preserve the existing
DBD::Pg result-type-change protection.

Query timing, query budgets and debug observers remain attached to the native
transport. Notifications consumed by Mojo::Pg during query completion enter
the existing bounded broker queues, preserving cache invalidation and realtime.

## Historical fixtures

ORM models, reference schemas and the historical DBIx bucket profiler live
under `t/lib` only. DBIx::Class is a
maintainer dependency for historical differential and metadata tests, rather
than a runtime dependency. Fixture schemas retain legacy setup helpers while
their application services execute through the native stored-function adapter.

## Limits and validation

This decision covers the native stored-function transport. Production
qualification requires the quality gates for the resulting code revision and
evidence from the target deployment.

Focused PostgreSQL checks cover typed JSON/binary calls, transactions and
savepoints, external transaction ownership, fork ownership, reconnect and
restricted API-role access. Historical DBIx comparisons remain maintainer-only
evidence; they do not establish the throughput of the new transport.
