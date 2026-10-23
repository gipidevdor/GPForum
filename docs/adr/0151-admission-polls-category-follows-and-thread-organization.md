# ADR 0151: Admission, Polls, Category Follows and Thread Organization

## Status

Accepted (2026-10-23). The owner requested these four product increments,
with the ADRs, PostgreSQL function API, optimization and correctness preserved.
Acceptance is not a release-readiness assertion. Validation is recorded in
`docs/architecture/community-completion.md`.

## Context

The forum already had registration and email verification, thread subscriptions,
digests, safe post bodies, versioned function entry points, moderation permissions,
idempotent commands and an outbox. It lacked staff-controlled admission, polls,
category follow forms and bounded tools to reorganize posts. New implementations
must reuse those contracts rather than introduce another persistence or delivery
system.

## Decision

### Function and transaction boundaries

Migrations 1025–1029 extend the 1.0 baseline without editing it. Runtime reads and
writes call `Infrastructure::SqlFunction` entries only. Implementations are
INVOKER, versioned, pin search_path and plan_cache_mode, and revoke PUBLIC
EXECUTE. Typed SQL forwarding boundaries alone are SECURITY DEFINER (ADRs
0126, 0127, 0150). Shipped boundaries remain for older workers; deploy updated
workers before relying on admission enforcement and re-apply the runtime-role
grants from the current catalogue.

New commands reuse `core_command_open`/`close`, with a SHA-256 of canonical JSON
including actor, operation and meaningful arguments. The client command UUID is
the idempotency key, independent of generated storage ids. Reusing it for another
actor or request conflicts. Successful writes and audit commit with the command;
failures roll everything back. No dynamic SQL or ORM write fallback is added.

### Admission

`registration_policy` is a singleton, initially open with approval off; existing
members retain their status. Staff with global `admin_console.manage`, unsuspended
and satisfying the staff TOTP policy, choose open, invite-only or closed, and
independently require staff approval for newly registered accounts. Policy writes
serialize with registration's shared lock on that row.

An invitation is a random 256-bit secret, bound to the normalized email and valid
for seven days, once. Only its hash is persisted; the raw secret is shown once to
the issuing operator for delivery. Expired invitations are purged by the existing bounded identity-token
retention job; its total batch limit is preserved. It is never put in a URL, audit, command log or
mail job. A retried issue returns the invitation id without the secret; revoke and
issue another if the response was lost. Staff may revoke an unused invitation.
The registration transaction locks the invitation, checks address/expiry/revocation,
and consumes it only after storing the account successfully. A rejected or duplicate
registration cannot consume it. Public registration refusals remain generic.

Approval is a separate `registration_reviews` row, not a new user status. Email
verification cannot set active while a pending or rejected review exists. Approval
before email verification leaves the account pending; verification before approval
also leaves it pending. Both transitions lock the user before the review decision.
Rejecting is final for this review; it never verifies or activates the account.
Changing the policy does not silently approve accounts already waiting.

### Category follows

The category form writes the existing `subscriptions` row with target_type
`category`, through an authorized, idempotent command. Follow restores a row,
unmute included; mute and remove stamp it. No additional subscription table or
per-category cache is introduced. The existing subscriber lookup unions direct
thread subscribers and category subscribers once per member, so feed and reply
notification delivery inherit category follows. A live muted thread subscription
overrides that category's delivery for the thread. Category mute does not cancel
a separately followed thread. Delivery still applies current source permissions,
ignore/block rules and notification preferences. Digests already support category
subscriptions and retain their existing opt-in and unread semantics.

### Polls

One single-choice poll per thread, created by its author after publication from
the thread's Poll link. Two to ten distinct options, each at most 120 characters;
question at most 200. Question and options are immutable once published. Voting
expires after thirty days or earlier when the author or global thread moderator
closes it. Locked threads cannot create polls or accept votes.

Active, unsuspended members with current access cast or change one ballot until
closure. A poll row serializes ballot mutations and closure; a thread lock settles
concurrent creation. Counts change in the same transaction as the unique
(thread_id,user_id) ballot. Reads fetch at most ten option rows and one indexed
own-ballot lookup; they do not scan voters or disclose identities. Public results
follow the thread/category/space visibility and the canonical viewer's grants.
Suspension and deletion remove membership, as in the existing ViewerResolver.
Results are available before voting. These are aggregate public results, not a
cryptographically secret ballot: operators with database access can inspect storage.
Poll pages are no-store, independent of the hot cached thread page.

### Thread organization

Global `thread.moderate` staff can move numbered replies into an existing thread,
split them into a new one, or merge an entire thread, at most 1000 posts per
command. Existing source and target must be visible, unlocked, in the same
category and have identical public/members visibility. Private threads, private
selected posts and threads carrying polls are refused. Broader audience changes
are deliberately outside this command. The opening post moves only in a complete
merge. A split's first selected post supplies the new author; the new thread keeps
the category and visibility.

Thread rows lock in UUID order, using the same rows as the reply allocator,
before posts/counters are changed. Post ids, bodies, revisions, authors and
attachments remain unchanged. Selected posts append in source position order;
remaining source positions are not renumbered, so existing read markers stay
meaningful. Counters and last activity are reconciled inside the transaction.
Reply-to edges crossing the new boundary are removed and recorded for reversal.

The transfer stores original/new positions and removed edges. Undo refuses when
positions were reused, selected posts moved again, the audience changed, a poll
was added, or new conversation structure makes reversal unsafe. A split that has
received new posts cannot be undone by this command. Successful undo restores
placement and original edges. The source of a full merge is a tombstone with a
permission-filtered redirect; browser history is not sent to an unreadable target.
The read traverses at most sixteen redirect hops.

Both affected threads emit existing `thread.updated` events for reindexing,
cache invalidation and feed projection in the same transaction as the transfer.
Moving historical posts does not synthesize new replies or send reply email.
Thread subscriptions are not copied to another thread; category follows continue
to apply. Transfer history is staff-only, bounded and no-store.

### Privacy and operational consequences

Account export includes only the subject's ballots and admission decision;
never invitation secrets or other voters. Erasure deletes ballots and decrements
option totals, removes admission rows/invitations and anonymizes staff references.
Ballot writes take a user lock conflicting with erasure before acquiring their
thread/poll locks. Audit does not contain ballot choices, invitation secrets or
admission email addresses. Transfer reasons stay staff-only moderation data.

The system acquires no new service or dependency. Nothing changes PostgreSQL
server settings or durability. A rollback uses the existing forward-fix procedure;
a migration is not removed from an installed database. Feature reversibility is
provided by revocation/removal, closing voting, and checked transfer undo, not by
rewinding migrations or silently rewriting decisions.

## References

- ADRs 0074 (privacy), 0078 (notification email), 0102 (visibility), 0111 (locks),
  0126 (SQL functions), 0127 (runtime role), 0142 (TOTP), 0150 (baseline).
- `t/integration/postgres-community-completion.t` and the existing identity,
  notification digest, runtime-role and function catalogue integration tests.
