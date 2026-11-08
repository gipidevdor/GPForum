# ADR 0176: A web worker never forks to reach PostgreSQL

## Status

Accepted (2026-11-08). Amends ADR 0174.

## Context

Controllers reach services through `call_p`. Until now, a service without a
native promise method fell back to the bounded subprocess executor: the
worker forked for that one call, the child opened a PostgreSQL connection of
its own, and each worker admitted one such child at a time. A call cost
30-90 ms and serialized the worker behind it. The notifications page made two
such calls per request; measured by PostgreSQL sessions, it opened 54 in 23
requests against the home page's 9.

## Decision

Every service a request reaches now has a `METHOD_p` twin (or an
`async_call_p`) that runs on the worker's pooled asynchronous connections
through `SqlFunction` `rows_p`, `row_p` and `transaction_p`. Writes that the
blocking path ran in one `txn_do` run in one `transaction_p`; collaborators
join it by being cloned with `functions => $scope`, savepoints go through
`UniqueConflict->attempt_p`, and command logs through
`CommandIdempotency->result_of_p`. `transaction_p` also takes
`{ read_only => 1, repeatable_read => 1 }`, which the mbox archive reads its
pages under. Validation, value building and answer shaping are plain
subroutines both paths call. In-memory doubles, which hold no connection,
still answer through the blocking method in process.

`call_p` has no child-process fallback. A PostgreSQL-backed service without a
twin croaks, so a missing one shows up as a failing request in the
integration tier instead of as a slow page in production.
`AsyncWork::service_p`, `service_args_p`, `service_result_p` and the
controllers' `work_p`/`work_args_p` are gone.

A child process remains the right place for CPU-bound or blocking system
work: Argon2, image decoding and cropping, body rendering and signing, large
upload hashing, antivirus scans, QR codes, name resolution and OS snapshots.
That work goes through `AsyncWork::cpu_p`, whose child cannot open
PostgreSQL (`PgStorage` croaks under `$NO_DATABASE`). Its input and answer are
plain data. An upload's antivirus scan runs before its transaction opens, so
no pooled connection or post lock waits on clamd.

The one remaining child with a connection is the command-line outbox
runner's: `AsyncWork::job_p` hands each lane of a claimed batch to a child,
per batch and never per query, in a process that serves no requests.
`t/885-no-database-in-children.t` holds both rules: no module starts a child
except through `cpu_p`, and only `Service::Outbox::Dispatcher` calls `job_p`.

## Consequences

Readiness keeps answering when the pool is busy only as far as the pool
does: its database checks now take a pooled lease like any read, and its
host checks run in a CPU child. Each web worker's connection budget drops
from four to three (two query leases and the LISTEN broker); the isolated
workflow connection is gone.

On macOS, a forked child that opens a TCP connection to PostgreSQL can crash
in libpq's GSSAPI probe. Web workers no longer do that; the outbox runner's
children still can, over TCP only, and `PGGSSENCMODE=disable` avoids it.
