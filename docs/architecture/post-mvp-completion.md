# Post-MVP feature completion

Scope authorized on 2026-11-01: the missing/incomplete features in the product
inventory, with correctness, bounded reads and performance verified for each
increment. This is an implementation ledger, not a release-readiness assertion.
The working branch is `feature/post-mvp-completion`; the starting commit is
`3ac5dac`. Provider configuration and target-host validation remain explicit
operational steps, never inferred from fixture tests.

| Increment | Implementation | Verification |
| --- | --- | --- |
| Combined tag filtering and tag search | Migration 1059, ADR 0157; SSR/JSON and keyset pages implemented | Real PostgreSQL integration passes; broader regression and performance evidence pending |
| Multiple-choice polls | Native poll creation, choice selection/voting and closure are implemented | `t/integration/postgres-multiple-choice-polls.t` and the executed feature gate |
| User follows | Profile follow/unfollow, follow management and followed-member feed are implemented | Native member GUI tests and `t/integration/postgres-follow-feed-privacy.t` |
| Bookmark reminders | Pending | Pending |
| Rich profile fields and social links | Pending | Pending |
| Private group conversations | Pending | Pending |
| Web Push | Migration 2042, ADR 0172; per-device settings and consent, bounded delivery worker and revocation | Real PostgreSQL workflow tests with controlled delivery, receipt proof and fresh permission/session checks |
| Social login and enterprise SSO | Existing-account OIDC linking/login/unlinking implemented; SAML and separate social-provider adapters remain pending | `t/integration/postgres-network-integrations.t` with real signed local claims |
| Passkeys / WebAuthn | Migration 2043, ADR 0173; GUI enrollment, normal-session login/TOTP, revocation/recovery, export and erasure | Real signed WebAuthn and PostgreSQL GUI workflow tests; client transport/cancellation tests |
| Magic-link sign-in | Pending | Pending |
| Nested categories | Pending | Pending |
| Managed thread prefixes | Pending | Pending |
| Wiki / knowledge base | Pending | Pending |
| Articles | Pending | Pending |
| Event calendar | Pending | Pending |
| Typing indicators | Pending | Pending |
| Collaborative editing | Pending | Pending |
| Group / broadcast mentions | Pending | Pending |
| Custom emoji | Pending | Pending |

The GUI connectivity of implemented features is tracked in
[functional coverage](../ui/functional-coverage.md). Pending product increments
in this ledger have no completed implementation to connect yet.

## Validation environment

Homebrew Perl 5.44.0 was installed because the project's system-Perl gate refused
the inherited perlbrew interpreter. Commands explicitly set
`GPFORUM_PERL=/opt/homebrew/bin/perl`; dependencies in `local/` passed their first
load and tag tests. PostgreSQL integration uses disposable socket-only clusters
through `GPForum::Test::TemporaryPostgres`. No shared database or server tuning
is used for these tests.

## Performance contract

Every increment keeps unfiltered hot reads unchanged unless a measured change
justifies it. Permission checks precede limits. Query counts stay independent of
page length; background fanout is bounded and durable. Timings identify commit
and source hashes, dataset, runtime, concurrency, warm/cold state and exclusions.
Passing the historical latency gate is insufficient evidence for the tighter
latency targets discussed with the owner. Those targets require a representative
host and an independent load generator through TLS.
