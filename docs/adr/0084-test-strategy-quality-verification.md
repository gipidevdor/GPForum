# ADR 0084: Test Strategy and Quality Verification

## Status

Accepted.

## Date

2026-09-19

## Context

Good Phorum's correctness depends on authorization, privacy, event and worker
behavior that manual testing cannot reliably cover. The project treats tests
as executable architecture and needs mandatory rules for test architecture,
the quality verification matrix, test data, security regression coverage
and release validation. The rules govern every bounded context and the
release process.

## Decision

### Cross-ADR alignment

- ADR 0098 (operational integrity): tests MUST verify execution discipline,
  not only feature presence. Critical workflow tests SHOULD prove canonical
  state, event emission, audit emission, permission enforcement, projection
  behavior, failure mapping, rebuildability, replayability and operational
  scaling assumptions.

### Testing philosophy

Tests are executable architecture.

Good Phorum MUST test: domain invariants; authorization; persistence; event
workflows; security boundaries; rendering safety; operational commands;
profiling readiness; performance-critical paths.

- The platform MUST avoid relying on manual confidence for critical
  behavior.
- Tests MUST be perfectly mapped to Good Phorum requirements. "Perfectly
  covering" means every critical architectural, security, authorization,
  data, event, worker, privacy and operational requirement has an explicit
  verification strategy.

### Test layers

The test suite SHOULD include: unit tests; service tests; controller tests;
DB integration tests; authorization matrix tests; event consumer tests;
worker tests; template rendering tests; browser or HTMX workflow tests;
migration tests; load and capacity tests where appropriate; profiling tests;
coverage verification.

### Mandatory early tests

- Milestone 0 MUST include: app loads; health endpoints work; configuration
  validation works; logging initializes; database connection can be tested
  safely; Carton dependency installation works; profiling command exists;
  coverage command exists.
- Milestone 1 MUST include: registration; login; logout; session
  revocation; password hashing behavior; CSRF protection.

### Authorization tests

- Authorization tests MUST cover: anonymous access; member access; moderator
  scope; administrator scope; suspended users; banned users; locked threads;
  archived categories; hidden and quarantined content.
- Authorization regressions are release blockers.

### Security tests

Security regression tests SHOULD cover: XSS escaping; CSRF enforcement; SQL
injection resistance through parameterized paths; unsafe upload rejection;
session revocation; rate-limit behavior; password reset token safety.

### Coverage requirements

- Coverage verification MUST exist from the first implementation milestone.
- Coverage MUST track: statements; branches where tooling permits;
  authorization paths; error paths; worker retry paths; event consumer
  paths; security-sensitive paths.
- Coverage targets MUST be explicit per milestone.
- Critical flows SHOULD target complete requirement coverage, not only high
  numeric coverage.
- Uncovered critical requirements MUST block release.

### Event tests

Event tests MUST verify: event emission; idempotent consumer behavior;
replay safety; no duplicate external side effects on retry; projection
rebuild from event history.

### Profiling tests

- Profiling tests MUST verify that profiling can run.
- Profiling validation SHOULD include: Devel::NYTProf execution; profile
  artifact generation; request-path profiling smoke test; worker profiling
  smoke test; slow query timing capture where the database is available;
  memory growth smoke checks for long-running processes.
- Profiling failures in release validation MUST be treated as operational
  readiness failures.

### Test data

- Test data MUST be deterministic.
- Factories SHOULD generate: users; roles; categories; threads; posts;
  moderation states.
- Tests MUST NOT depend on production data.

### Release gates

- Release gates SHOULD include: formatting; Perl::Critic; Carton dependency
  validation; unit tests; integration tests; coverage validation; profiling
  smoke validation; migration validation; security checks; smoke tests.
- Failing release gates MUST block production deployment unless explicitly
  overridden by emergency procedure.

### Verifiable invariants amendment

- Testing MUST enforce ADR 0093.
- Every critical invariant MUST have either an automated test or a
  documented verification plan with release-gate consequences.
- The test suite MUST include negative tests for authorization, search
  leakage, moderation visibility, replay safety, plugin boundary failure and
  projection staleness where those features exist.
- Golden-path workflow tests MUST verify canonical writes,
  event/audit/outbox effects, projection handoff, metrics/logging
  expectations and classified error behavior.

### Accessibility testing amendment

- Testing MUST enforce ADR 0094.
- Critical user-facing routes SHOULD have automated accessibility checks
  where practical, including semantic HTML validation, contrast checks,
  keyboard smoke tests, and axe-core or pa11y scans.
- Accessibility tests MUST cover home, category, thread, composer, search,
  login/register, notifications, moderation and admin dashboard surfaces as
  those surfaces become implemented.

## Consequences

- Test coverage is measured against requirements, not only line counts, so
  every new critical rule in an ADR needs a matching test or verification
  plan.
- Authorization regressions, uncovered critical requirements and broken
  profiling block releases, which makes CI the enforcement point for
  architecture.
- Deterministic factories and no production data keep tests reproducible
  locally and in CI.

## Related Decisions and Implementation

- ADRs: 0093, 0094 and 0098 (cross-alignment and amendments), 0059 (CI/CD
  and release engineering), 0070 (permission matrix), 0076 (bootstrap
  tests), 0089 (profiling and coverage automation).
- Scripts: `script/test`, `script/coverage`, `script/profile-nytprof`,
  `script/perlcritic`, `script/perltidy-check`, `script/perl-syntax-check`,
  `Makefile`, `.github/workflows/ci.yml`.
- Tests: `t/` (suite), `t/integration/postgres.t`, `t/lib/GPForum/Test/`,
  `t/02-health.t`, `t/06-identity-web.t`,
  `t/integration/postgres-admin-authorization.t`,
  `t/35-forum-accessible-ssr.t`, `t/48-browser-security.t`,
  `t/50-security-hardening.t`, `t/86-engineering-correctness.t`,
  `t/144-cpan-install.t`.
- Docs: `docs/ENGINEERING_CORRECTNESS.md`, `docs/PERFORMANCE.md#profiling`.

## Behavior and suite consolidation amendment (2026-11-06)

A passing assertion count does not establish user workflow coverage. A source
scan that finds a route, form, helper or feature provider establishes presence
only. A controller double cannot establish PostgreSQL persistence, and a service
integration cannot establish browser behavior. Reports MUST identify which layer
provided the evidence and MUST NOT count skipped prerequisites as verified flows.

Use the following tiers through `script/test`, from any working directory:

| Tier | Command | Evidence |
| --- | --- | --- |
| Contracts | `script/test unit` or `make test` | Domain, services, controllers and architectural contracts without a database |
| Clients | `script/test clients` | JavaScript state transitions and recovery paths |
| Persistence | `make integration` | Real PostgreSQL, transactions and HTTP integration on isolated databases |
| Browser | `make test-browser` | Real Chromium; persistent posting journeys and isolated fragment cases |
| Complete | `make test-all` | Every tier, including performance contracts; prerequisites must be installed |

`script/test t/path.t` runs only the named tests. The default no longer recursively
collects database tests only to report them as skipped. `make check` also runs the
client contracts. CI runs persistent browser behavior on each push and PR.

Organize tests by responsibility, not by the bug or iteration that created them.
Before creating a test file, extend the suite owning that behavior with a named
subtest or data table. Keep separate files when they require different isolation,
external prerequisites or instrumentation. Do not concatenate unrelated tests
just to reduce a count. Exact renderer markup rules and list cases formerly in
the former renderer-rules and body-lists suites now live in
`t/179-forum-body-renderer.t`, with all original expectations retained. Work-bound
instrumentation and cache pressure tests retain their independent processes.

For each critical GUI workflow, review these input and state partitions: empty,
valid ASCII, accented and decomposed Unicode, non-Latin and non-BMP text; length
boundaries; permissions and expired session/CSRF; slow or interrupted requests;
duplicate submission; validation failure and retry. Cover applicable partitions
at the cheapest layer that establishes the property, and keep at least one real
browser/database journey for each critical persistent interaction. A workflow
without that evidence remains a coverage gap, regardless of line coverage.

GUI behavior follows [WCAG 2.2](https://www.w3.org/TR/WCAG22/), particularly keyboard
operation (2.1.1), visible focus (2.4.7), error identification (3.3.1), labels and
instructions (3.3.2), and status messages (4.1.3). Follow the official
[Playwright testing practices](https://playwright.dev/docs/best-practices): exercise
user-visible behavior, isolate state and prefer role/label locators with waiting
for observable outcomes. These specific checks do not assert complete WCAG
conformance; manual screen-reader and visual review remain necessary.
