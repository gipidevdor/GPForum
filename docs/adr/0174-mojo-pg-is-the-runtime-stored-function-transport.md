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

The synchronous `rows` and `txn_do` APIs remain available to commands and
isolated workflows. HTTP controllers use Mojolicious async/await and prefer
native promise service methods. Shared request state and rendering reads are
prepared before dispatch or synchronous hydration. Persistent operations without
a native method execute as complete service workflows in the shared bounded
subprocess executor. A blocking PostgreSQL checkout in an HTTP request context
is rejected. Only data crosses IPC; native ResultRow subclasses retain their
pure data methods, binary strings and Unicode flags through trusted Storable IPC.

`rows_p`, `row_p` and `transaction_p` own leases outside Mojo::Pg's pinging idle
queue. Native transactions serialize their commands, use asynchronous savepoints
and preserve failures after rollback without replaying commits. SQLSTATE 57014
rejects cancelled queries even though DBD::Pg returns zero for cancellation.
Native handles disable destructor-driven deallocation; stale prepared plans are
retired with an asynchronous DEALLOCATE before a bounded retry outside a
transaction. Parameterless control commands avoid overlapping asynchronous
prepare and simple-query execution; zero-input catalogue calls retain a typed
internal bind and named-plan result-type protection.

Connection establishment uses DBD::Pg asynchronous connect, watching the exact
socket/readiness libpq requests, under a five-second deadline. Trusted database
hostname resolution uses the bounded subprocess executor and pins hostaddr
while preserving hostname/TLS semantics. Libpq service definitions can require
an isolated peer-selection probe. Connection/session initialization, including
strict performance checks, returns promises. After fork workers asynchronously
warm two native query leases. One additional idle connection serves the shared
LISTEN broker, and one belongs to isolated workflow work: four connections per
web worker remain the capacity-planning budget.

Cache and realtime state stay in the web process. A reactor-driven listener
feeds bounded per-channel queues; reads never ping or check out the synchronous
handle. Realtime admission, authorization, visibility, badge snapshots, session
checks and outbox backstops use promises. CLI users retain the synchronous
notification interface. In-memory collaborators retain parent-owned state;
rate-limit fallback windows and counters must never be copied into transient
children.

Argon2id, account workflows, image tools, checksums, archive generation,
uncached body rendering, QR generation and filesystem content reads stay off
the HTTP reactor. File and database streams apply write backpressure before
reading the next bounded chunk. Template compilation and small framework
metadata/logging operations retain Mojolicious's standard semantics. Template
warmup waits for async completion before the manager forks. The cost-keyed
password decoy is also warmed before fork.

PostgreSQL tests cover typed JSON/binary binding, commit/rollback/savepoints,
external transaction isolation, query cancellation, fork ownership, cache
invalidation, reconnect, result-type migrations and the restricted SQL API
role. A silent TCP peer test verifies the connection deadline while unrelated
reactor work progresses. Unit tests exercise asynchronous admission, context
restoration, bounded queues and conditional/range file streaming.
