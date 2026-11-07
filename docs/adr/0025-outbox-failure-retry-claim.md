# ADR 0025: Outbox Failure, Retry, and Claim Query Boundaries

## Status

Accepted.

## Context

`Service::Outbox::Dispatcher` owned PostgreSQL `FOR UPDATE SKIP LOCKED` SQL,
failure-type regexes, attempt increment, cancelled-versus-failed status, lock
duration, and backoff together with transport dispatch and row updates. ADR
0009 already required stable `failure_type` categories; those rules were not
unit-testable without a schema and transport fake.

## Decision

Split the dispatcher behind the existing public methods:

- `GPForum::Service::Outbox::FailureType` owns declared and regex
  classification;
- `GPForum::Service::Outbox::Retry` owns attempt increment, cancelled status,
  lock duration, and linear backoff;
- `GPForum::Service::Outbox::ClaimQuery` owns the claim statement and bind
  order. (Amended 2026-11-01: the claim is `api.outbox_claim_ready`, migration
  1034, and ClaimQuery is gone.)

`GPForum::Service::Outbox::Dispatcher` still claims, dispatches, updates
rows, and writes dead letters. `DeadLetterRecorder`, `EventRecorder`, and
`Outbox::MessageBuilder` load `Service::Id` lazily so tests can inject
`Test::Id` without Crypt::URandom.

### Amendment 2026-11-01: messages due later

The claim takes a message once `next_attempt_at` has passed, which a retry
always relied on. A message may now also be written due later: a timed
suspension queues its end due a second after its `valid_to`
(`api.core_moderation_queue_suspension_end_v1`, migration 1055), carrying a
`user.suspension_end_due` payload whose `event_id` is the suspension's, so
the handler's claim is one per suspension
(`Worker::Handler::SuspensionEnd`). Nothing else is a timer: there is no
event in `event_log` for it, and the realtime mapper ignores its type.
Readers that measure the outbox's age count a pending message from when it
fell due (`api.search_observe_lag_v3`; `api.ops_doctor_outbox_v1` already
did), so an end queued for next week is not a week of lag.

## Consequences

Classification, retry ceilings, and claim bind order are unit-testable without
DBIx::Class. `t/13-outbox-dispatcher.t` keeps the same SQL, bind indexes, and
retry schedule. Public dispatcher method names stay unchanged.

## Alternatives Rejected

- Keep regexes and SQL as dispatcher private constants: rejected because
  operators need those rules tested without a claim transaction.
- Move retry policy into `DeadLetterRecorder`: rejected because dead letters
  are terminal evidence, not scheduling.

## Alignment

- `docs/adr/0009-outbox-retry-semantics.md`
- `docs/OUTBOX_LIFECYCLE.md`
- `docs/ENGINEERING_CORRECTNESS.md`
- `t/13-outbox-dispatcher.t`
- `t/121-outbox-boundaries.t`
