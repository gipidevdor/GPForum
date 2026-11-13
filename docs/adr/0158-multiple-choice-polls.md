# ADR 0158: Multiple-Choice Polls

## Status

Accepted (2026-11-01), under the owner's request to complete the product features.

## Context

A poll has immutable options, one changeable ballot per member, and bounded
result reads. Existing workers and account erasure know one selected option.
Extending the ballot key would break their writes and cached result contracts.

## Decision

A poll declares `maximum_choices` at creation, from one (the existing default)
to its number of options, at most ten. Voting accepts a nonempty set of distinct
valid option numbers within that bound. Closure, participation, current thread
access, lock order and idempotent commands retain their existing contracts.

The first selected option remains in `poll_ballots`; additional selections live
in `poll_ballot_extra_choices`, with foreign keys to the ballot and the options.
New command and read versions expose every own selection. Option counters change
in the vote transaction; reading totals never scans voters. Existing single-choice
polls and forms continue to work.

Two narrowly scoped INVOKER trigger functions maintain the additional counters
and remove extra selections when an older worker changes the first selection.
Erasure's existing ballot deletion cascades through these selections and their
counter adjustments. Changing to the same first choice through an older worker
preserves additional selections; new forms always replace the whole selection.
New exports include every selection and only the account holder's ballots.

ADR 0150's reachability invariant is extended to functions attached to actual
schema triggers. They remain versioned `api.core_*` INVOKER functions, with pinned
search path/plan mode and PUBLIC execution revoked. They are not runtime-role
entry points. Static migration checks find their attachment; the migrated-schema
check follows real `pg_trigger` attachments. Unattached helpers still fail.

## Consequences

Ballot and counter mutations are atomic under the existing poll-row lock.
Results count selections, so option totals can exceed the number of voters.
No new read is added to the hot thread page. Single-choice clients can continue
to read the first selection; updated forms show checkboxes for multi-choice polls.
Shipped function boundaries and their typed contracts remain available.

## Validation

`t/integration/postgres-multiple-choice-polls.t` verifies bounded selections,
invalid input, counter replacement, retry/conflict, legacy-worker changes,
private own selections, account export/erasure and closure. Existing concurrent
poll creation/voting, authorization and web tests remain required. Timings and
broader gate results belong in the completion ledger.
