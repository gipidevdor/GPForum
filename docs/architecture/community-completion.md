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

### CI and development activation follow-up

The [PostgreSQL target run for `6bc1850`](https://github.com/gpicchiarelli/GPForum/actions/runs/39977006913)
passed on PostgreSQL 16, 17 and 18. The main CI's lint and PostgreSQL integration
jobs also passed. Its unit job and the Debian target exposed one stale assertion:
the sign-in guidance now includes staff approval as well as email verification.
`t/379-controller-collapsed-branches.t` checks the current explanation in English
and Italian, the error element and HTTP 401.

The local development database on the Unix socket `/tmp/gpfv`, port 55433,
was advanced from migration 1023 through 1029 using `gpforum migrate --apply`.
The published release's `migrate --check` reports no pending migrations. All 26
users, 120 threads and 1,800 posts were preserved; registration remains open,
without required approval. The updated development server on port 3100 answers
200 for liveness, readiness, home, categories, registration and a visible
thread's poll page. Anonymous admission/transfer administration answers 401.
This instance uses its existing development owner login; it has no separate
restricted runtime role or running outbox worker. This check does not establish
production role provisioning or delivery readiness. The runtime role guide
remains required for production activation.

The [performance run for `6bc1850`](https://github.com/gpicchiarelli/GPForum/actions/runs/39977006751)
completed its ordinary HTTP, SQL and outbox collection steps, but failed the
separate 5,000-connection gate on the shared four-CPU GitHub runner. With four
workers, colocated wrk, three ten-second repetitions and a three-second timeout,
the 5,000-connection cells recorded 8,097, 7,476 and 2,857 transport timeouts.
The 1,000-connection cells passed. The gate remains failing; thresholds and error
handling were not relaxed. This is evidence of a capacity limit for this run,
not a paired before/after result or proof that these features caused a regression.
Raw results and configuration are retained in that run's
[performance artifact](https://github.com/gpicchiarelli/GPForum/actions/runs/39977006751/artifacts/12512835233).

Existing production readiness and the previously observed broad trigram-search
cost remain open. Local PostgreSQL validation used 18.6; the other major versions
were exercised in CI.
