# ADR 0177: One body per store operation

## Status

Accepted (2026-11-08). Amends ADR 0174 and ADR 0176.

## Context

ADR 0176 gave every service a request reaches a `METHOD_p` twin on the
worker's pooled connections, and kept the blocking `METHOD` for commands,
jobs, workers and in-memory doubles. Many stores then held each operation
up to three times: the blocking body on `rows` and `txn_do`, the promise
body on `row_p` and `transaction_p`, and a DBIx::Class body for fixture
schemas (`if !$self->functions`). On 2026-11-08 `lib/` held 716 promise
methods and 170 such branches in 61 files.

The copies drift. A review of `main` that day found `answers_p` without the
fallback its blocking twin had, and a refusal added to one path had to be
added to the other by hand. Every fix is paid two or three times.

## Decision

A store writes each operation once, as its promise method, against its call
layer (`functions`, or the `$scope` a transaction hands it).

`GPForum::Infrastructure::SqlFunction` has a blocking layer
(`blocking_layer`). On it, `rows_p` and `row_p` run `rows` on the process's
own connection, and `transaction_p` runs `txn_do`, which opens the
transaction or a savepoint of the one already open, as a pooled transaction
nests. Each answers a promise that is already settled. An `async sub` whose
awaits all meet settled promises runs to its end without an event loop.

The blocking method is that body run on the blocking layer, and nothing
else. A store declares its blocking twins instead of writing them:

    GPForum::Infrastructure::SqlFunction->blocking_twins(
        qw(create_suspension revoke_suspension));

installs `create_suspension` as `settle` of `create_suspension_p`, with the
caller's arguments.

`settle` copies the service with its call layer made blocking, calls the
promise method and returns its value, or raises its failure as it was.
`settled` refuses a promise still pending: blocking code never waits on the
event loop.

The DBIx::Class body goes with the conversion. A store converted this way
needs the function layer and throws `GPForum::X::Unavailable` without one;
its tests run on PostgreSQL (`t/integration`), as the moderation stores'
already did. Tests that compared a store with its retained Perl path state
the expected answers instead.

`SuspensionStore` was the first store converted. Amended 2026-11-09: the
whole moderation area followed -- `ActionStore`, `AutomodStore`,
`MemberNoteStore`, `ReportStore`, `ReviewReader`, `ReviewStore` and
`ThreadTransfers`. `ActionStore`'s eight actions became one table of data
(the event, the target kind, whether the target is already there, the
changes) applied by one body. The other areas follow, each with its tests
moved to PostgreSQL in the same change.

## Consequences

- One body per operation: a fix, a refusal or a lock is written once and
  holds on both paths. `SuspensionStore` went from 880 to about 630 lines;
  the other seven moderation stores together from 3,738 to 2,760.
- A test double of the call layer speaks the whole contract: `row_p` and
  `rows_p` answering settled promises, and `blocking_layer`.
- A web worker still never blocks: the blocking layer reaches the storage's
  blocking handle, which refuses an HTTP request context as before
  (ADR 0176).
- The unit tier no longer covers a converted store on a fake ORM; the
  integration tier does, on the real functions.
- `t/86-engineering-correctness.t` accepts `transaction_p` and the
  `ops_record_event`/`ops_record_audit` calls as a store's transaction and
  recording boundaries.

## Related Decisions and Implementation

ADR 0126, ADR 0174, ADR 0176. `lib/GPForum/Infrastructure/SqlFunction.pm`
(`blocking_layer`, `settle`, `settled`,
`blocking_twins`), the stores of `lib/GPForum/Service/Moderation/`,
`t/integration/postgres-suspension-races.t`,
`t/integration/postgres-sql-function-prologue.t`,
`t/integration/postgres-moderation-review.t`.
