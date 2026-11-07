# Test construction and execution

Use the cheapest tier that proves the property. Source inspection establishes an
architecture declaration; doubles establish a contract; PostgreSQL establishes
persistence; a browser establishes an interaction. None substitutes for another.
See ADR 0084 for the full strategy.

The 7 November passkey follow-up adds a persistent Chromium journey in
`t/browser/passkeys.test.cjs`. It drives normal password sign-in, the account menu,
WebAuthn registration, credential sign-in, ordinary thread publication under that
account, revocation and rejection after revocation.
Only hardware presence/verification is provided by a virtual CTAP2 authenticator;
the browser APIs, frontend, HTTP services, signatures and PostgreSQL are real.
Identity coverage still has browser gaps beyond this journey, including TOTP
and recovery; their PostgreSQL tests do not substitute for a browser test.

| Purpose | Command |
| --- | --- |
| One Perl regression | `script/test t/path.t` |
| Unit, service and controller contracts | `script/test unit` |
| JavaScript clients | `script/test clients` |
| Real PostgreSQL | `script/test integration` |
| Browser behavior | `script/test browser` |
| Every tier | `script/test all` |

The CI integration job runs `script/test-features --configured --jobs 4` once.
This discovers the whole integration directory and its declared unit witnesses;
failed tests and missing executed witnesses both fail the job. Running
`make integration` first would repeat every integration file. It remains useful
for local diagnosis without instrumentation.

## Construction rules

- Assert independently expected behavior and state. Reusing the implementation
  to calculate its expected answer can reproduce the same bug in the assertion.
- Cover relevant refusal, boundary, retry and interrupted-work cases. Establish
  persistence with real storage and user interaction with an actual browser.
- Consolidate shared fixtures and contracts into data tables or named subtests.
  Preserve separate processes for different isolation and instrumentation needs.
- Use `t/js/support/events.cjs` for DOM listener semantics. Its native EventTarget
  preserves multiple listeners and cancellation. A single callback slot per
  event cannot model the composer's formatting and autosave hooks. DOM bubbling
  and layout remain browser responsibilities.
- Prefer held responses, explicit signals and observable outcomes to settling
  sleeps. Deadlines prevent hangs; they are not assertions about machine speed.
- Own and clean up subprocesses. Browser fixtures share
  `t/browser/support/process.cjs`: the child reports its bound ephemeral socket;
  startup failures retain diagnostics; shutdown has a bounded escalation. Five
  Node-only tests exercise its lifecycle independently of Playwright.
- Distinguish normal exit from signals. Shifting a wait status alone can report
  SIGTERM as exit zero. The command-capture gate has a signal negative control.
- Validate important regressions with targeted mutations. A syntax error or
  unavailable fixture does not count as a mutation caught by a behavioral test.

The logging fork test probes a real nonblocking kernel lock on the actual append
descriptor, then verifies the completed write after the parent unlocks. It does
not infer lock independence from a 100 ms scheduling delay.

The duplicate-submit browser test covers both replacement and retention of the
form: a successful toolbar update and a failed response that leaves the source
connected. An explicitly held response and request events prove no duplicate is
admitted or restarted, without an arbitrary settling sleep. The mutation probe
verifies attributes were actually removed in the DOM before interpreting a result.

Minimal `è` and mixed Unicode remain distinct browser partitions. Chinese or
emoji can force a Perl Unicode representation that masks a Latin-1-only defect.
Do not collapse these cases simply to reduce the number of journeys.

## Assessment, 6 November 2026

This review does **not** certify 10/10 quality across the repository. The feature
manifest has 41 features, 188 behavioral witnesses and 235 HTTP requirements.
Alternative acceptable HTTP statuses establish an operation outcome, not every
permission and error branch of that route.

Remaining evidence gaps include fresh branch/condition coverage and persistent
browser journeys beyond posting/local thread fragments, especially identity and
staff workflows. The coverage ratchet gates statements and subroutines; its
recorded measurement is from September 2026. Other legacy client fixtures still
need event-fidelity review. A green count alone cannot close these gaps.

Broad verification used a frozen checkout: base `a21e071` plus this review's
test/CI changes. Concurrent edits produced a transient `AsyncQuery.pm` compilation
error during the first live-checkout runs, which remain failed evidence. The
isolated result does not certify those concurrent application changes.

Logs, targeted mutation results and the reviewed source manifest are under
`artifacts/test-quality/2026-11-06-construction/`. Targeted mutation results cover
only the selected guards and are not a repository-wide mutation score.
