# Community workflow completion — 2026-10-23

Design: [ADR 0151](../adr/0151-admission-polls-category-follows-and-thread-organization.md).
Migrations 1025–1029 follow the published 1.0 baseline. They do not modify
PostgreSQL configuration, weaken durability or introduce services/dependencies.

## Product entry points

- Admin dashboard → Registration and invitations: choose registration mode,
  require staff approval, issue/revoke invitations and decide waiting accounts.
  Invitations are entered as codes on the registration form, not in URL queries.
- Category page → follow/mute/unfollow. Existing reply notifications, followed
  feed and opted-in email digests reuse the subscription and delivery machinery.
- Thread toolbar → Poll: authors publish a two-to-ten-option single-choice poll;
  members vote/change their vote; author or staff closes it. Automatic expiry:
  thirty days. Poll pages are not cached.
- Admin dashboard → Organize discussions: supply discussion links, post numbers
  and a reason to move/split/merge; recent history offers checked undo. This
  initial workflow permits equal audiences in the same category and excludes
  private selected content and polls. At most 1000 posts per operation.

## Deployment

Apply migrations through the existing `gpforum migrate --apply`, update workers
and refresh the restricted runtime role's grants using the current catalogue
([runtime role guide](../ops/sql-api-role.md)). Older workers do not enforce the
new admission policy; do not enable a restricted policy during a mixed deployment.
Existing members and the default open registration behavior are unchanged.
Changing admission policy does not decide previously queued reviews.

## Validation

Local validation on Apple M4 / PostgreSQL 18.6:

- General suite: 603 files, 17,879 top-level tests, PASS (database-dependent
  integration files skip here; they are executed separately below).
- PostgreSQL tier: 129 files, 11,856 top-level tests, PASS, including the
  catalogue, restricted-role boundary, identity differential tests, digests,
  privacy, concurrency and query budgets. The five pre-existing attachment
  TODO assertions still report unexpected success, not failures.
- The expanded community test was rerun after the final HTTP error handling
  and fixture cleanup changes: eight subtests, including real verification
  tokens, concurrent erasure/voting, category fanout/mute precedence, reply-link
  reversal, successful browser forms and the canonical thread slug `poll`.
- Full Perl::Critic ratchet: zero baseline and zero new violations. Subsequent
  modified files were checked again under the same brutal profile.
- Syntax, formatting, architecture/SQL-function guards and translation checks
  passed. No critic exemption or baseline entry was added.

[Raw diagnostic evidence](../../benchmarks/community-workflows/2026-10-23/README.md)
contains 100 serial warm-cache poll reads with 1,000 synthetic voters and plans
of the internal option/own-ballot statements: p50 0.180 ms, p95 0.232 ms,
p99 0.288 ms on this machine. This is a single integration smoke measurement,
not sustained HTTP capacity or a before/after improvement claim.

PostgreSQL 16/17 and target deployment evidence remain the CI/staging tier's
responsibility; only PostgreSQL 18.6 was executed locally. Existing production
readiness and the previously observed broad trigram-search cost are unchanged.
