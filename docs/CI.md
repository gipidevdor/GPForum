# GPForum CI

The pipeline enforces [ADR 0059](adr/0059-cicd-quality-release-engineering.md): code does not
bypass automated validation, security scanning, critic enforcement or testing.
This page maps every GPForum target to the workflow that proves it, and every
mandatory pipeline stage to where it runs.

Workflows live in [.github/workflows](../.github/workflows). Every job installs
the locked tree the same way an operator does — the OS system Perl,
`script/bootstrap-deps`, `cpanfile.snapshot` — so a green run means the
documented host instructions work, not that CI has a private path.

## Platform targets

| Target | Workflow | Runner | Trigger | Blocks merge |
| --- | --- | --- | --- | --- |
| Ubuntu (primary quality gate) | [ci.yml](../.github/workflows/ci.yml) | `ubuntu-26.04`, system `/usr/bin/perl` | every push and pull request to `main`; coverage nightly and on demand | yes |
| Debian stable | [platform-debian.yml](../.github/workflows/platform-debian.yml) | `debian:trixie` container | code paths on `main`, weekly, manual | no |
| FreeBSD | [platform-freebsd.yml](../.github/workflows/platform-freebsd.yml) | FreeBSD VM on an Ubuntu runner | OS/rc paths on `main`, weekly, manual | no |
| macOS developer host | [platform-macos.yml](../.github/workflows/platform-macos.yml) | `macos-latest` with Homebrew | OS/launchd paths on `main`, weekly, manual | no |

Debian and FreeBSD are the deployment platforms named in the README and in
[deploy/](../deploy); macOS is the supported developer host. The macOS workflow
splits into a fast Homebrew system-Perl contract job and a scheduled full gate,
because building the locked tree for Homebrew's Perl compiles every XS
dependency and takes much longer than the contract checks.

## Database targets

| Target | Workflow | What it proves |
| --- | --- | --- |
| PostgreSQL 16, 17, 18 | [postgres-matrix.yml](../.github/workflows/postgres-matrix.yml) | migration plan, apply, apply-again idempotency, every PostgreSQL integration test in `t/integration/` (`make integration`), `gpforum platform-check --with-db`, and the fresh/upgrade/dump-restore drill with a version-matched `pg_dump` |

`ci.yml` keeps one server (PostgreSQL 16) in the blocking gate; the matrix runs
on migration/schema paths and their SQL consumers, database tooling and
matching tests, nightly, and on demand. The matrix enables `pg_stat_statements`
only on its disposable PostgreSQL service, with one bounded restart. It runs
the existing full integration tier, then collects and schema-validates
read-only diagnostics even if a later gate failed. Public JSON contains
allowlisted counters and query identifiers; it never retrieves SQL text.

[postgres-recovery.yml](../.github/workflows/postgres-recovery.yml) runs the
existing isolated PITR drill weekly on Tuesday at 03:47 UTC on PostgreSQL 18,
or manually on 16/17/18. It checks physical-backup integrity, completed WAL
archiving, targeted promotion, exact recovered records and owned-server
cleanup. Its one standard Linux job has a 15-minute limit; the drill has a
180-second limit including cleanup. It adds no recovery job to each PR.
The token is read-only, concurrency preserves an active recovery measurement,
and JSON/sanitised logs are retained for 14 days. Physical backups, WAL and
data directories are excluded from artifacts. Reports distinguish setup
failure and unavailable measurements from successful recovery; this small
fixture does not establish production RPO/RTO or attachment consistency.

## Readiness targets

The README status table tracks three readiness targets. CI covers what can be
proven without a staging host; it never converts an operator residual into a
claim.

| Readiness target | Covered by CI | Still operator work |
| --- | --- | --- |
| Local, personal use | `ci.yml`, `postgres-matrix.yml`, `platform-*.yml` | — |
| Private beta | [ops-drills.yml](../.github/workflows/ops-drills.yml): backup/restore, attachment restore, deploy templates, host verify, mail transport probe, mail lifecycle, dead letters, stress-load planning, evidence validation | staging TLS, SMTP `--send`, stress 100/500/1000 against the target, unit install — see [ops/private-beta-checklist.md](ops/private-beta-checklist.md) |
| Public production | [deploy-units.yml](../.github/workflows/deploy-units.yml), [release.yml](../.github/workflows/release.yml), `postgres-matrix.yml` | live staging numbers, rehearsed rollback on the target host |

A green `ops-drills.yml` run does not claim private-beta readiness. The drills
run in their offline, simulate and dry-run modes, exactly as
`script/gpforum-private-beta-checklist` describes them.

## Mandatory pipeline stages

[ADR 0059](adr/0059-cicd-quality-release-engineering.md) defines the required pipeline stages.

| Stage | Where it runs |
| --- | --- |
| Dependency validation | `ci.yml` (`script/gpforum-carton check`), every platform workflow, `release.yml` |
| Static analysis | `ci.yml` (`script/perlcritic`, `script/perl-syntax-check`, `script/architecture-check`), `security.yml` (actionlint, shellcheck) |
| Formatting validation | `ci.yml` (`script/perltidy-check`) |
| Test execution | `ci.yml`, `platform-debian.yml`, `platform-freebsd.yml`, `platform-macos.yml`, `postgres-matrix.yml` |
| Coverage validation | `ci.yml` coverage job, nightly and on demand (`script/coverage`, `cover_db/` artifact) |
| Continuous performance evidence and profiling | [performance.yml](../.github/workflows/performance.yml) (paired PR HTTP/SQL/outbox, representative main runs, weekly/manual deep sweep and configured NYTProf) |
| Bounded Sunday saturation and recovery evidence | [performance-extreme.yml](../.github/workflows/performance-extreme.yml), single standard runner, maximum 30 minutes, immutable artifacts |
| Security scanning | [security.yml](../.github/workflows/security.yml) (CPANSA advisories, license review, gitleaks, workflow and shell linting, OpenSSF Scorecard) |
| Artifact creation | `release.yml` (reproducible `git archive` tarball, Carton vendor bundle, `SHA256SUMS`, build provenance attestation) |
| Deployment validation | `deploy-units.yml` (`systemd-analyze verify`, `nginx -t`, `caddy validate`, `sh -n` on the rc(8) unit, deploy checklist drill) |
| Migration validation | `postgres-matrix.yml` (plan, apply, idempotent re-apply, fresh/upgrade/dump-restore drill) |
| Database recovery validation | `postgres-recovery.yml` (weekly/manual manifest-verified isolated PITR; no PR matrix expansion) |
| Accessibility gates | `ci.yml` test suite (`t/65-accessible-theme.t`, `t/35-forum-accessible-ssr.t`, the `*-access.t` authorization suite) per [ADR 0094](adr/0094-accessibility-engineering.md) |

## What ci.yml runs

Until 2026-10-17 `ci.yml` was one sequential job of about two hours, with
`cancel-in-progress` on every ref. Every push to `main` cancelled the run
before it, so from a69a995 on `main` had no finished result; the integration
tier ran twice (`make integration`, then again inside `prove -lr t`), and no
`prove` ran in parallel. It is now four jobs that start together. A run on
`main` is never cancelled: a newer push waits for it, and GitHub keeps one
pending run per branch. Other refs still cancel a superseded run.

| Job | Runs | Typical length |
| --- | --- | --- |
| `lint` | every push and pull request | under 10 minutes |
| `unit` | every push and pull request | under 10 minutes |
| `integration` | every push and pull request, PostgreSQL 16 over its Unix socket | under 10 minutes |
| `coverage` | nightly at 02:17 UTC and on demand (`workflow_dispatch`) | under an hour |

`t/706-ci-finishes.t` reads the two tables below: every check that ran before
must still run, every command of the second table must be in its job, and
every one-line step of `ci.yml` must be in the second table.

### Before: one job, in this order

| Command | Now |
| --- | --- |
| `script/gpforum-system-perl --preflight` | same |
| `script/bootstrap-deps --postgres` | same |
| `script/gpforum-carton check` | same |
| `script/cpan-license-check` | same |
| `git diff --check` | same |
| `prove -I script/lib -I t/lib -lr t/performance` | same |
| `node --test t/js/*.test.cjs` | same |
| `script/gpforum-carton exec script/perl-syntax-check` | same |
| `script/perltidy-check` | same |
| `script/perlcritic` | same |
| `bin/gpforum migrate` | same |
| `bin/gpforum performance-seed --profile small` | same |
| `bin/gpforum budgets --sync` | same |
| `bin/gpforum budgets --check` | same |
| `script/architecture-check` | same |
| `script/query-plan-check --require-db` | same |
| `bin/gpforum os-preflight --json` | same |
| `postgresql-client-16` | same |
| `clamd --config-file` | same |
| `make integration` | `make integration JOBS=4` |
| `script/gpforum-carton exec prove -lr t` | `script/gpforum-carton exec prove -l -j 4 t`, `make integration JOBS=4` |
| `bin/gpforum benchmark --fixture --check` | same |
| `bin/gpforum query-plan-evidence --check` | same |
| `script/benchmark-http --configured --check` | same |
| `bin/gpforum hypnotoad-benchmark --check` | same |
| `bin/gpforum platform-check --with-db` | same |
| `script/coverage` | `script/coverage -j 4` |
| `name: gpforum-cover-db` | same |

`t/553-backup-postgres.t`, the one test under `t/` that needed a database,
is now `t/integration/postgres-backup.t`: the unit job has none, as on a
developer's laptop.

### After: four jobs

| Job | Command |
| --- | --- |
| every job | `script/gpforum-system-perl --preflight` |
| every job | `script/bootstrap-deps --postgres` |
| `lint` | `script/gpforum-carton check` |
| `lint` | `script/cpan-license-check` |
| `lint` | `git diff --check` |
| `lint` | `prove -I script/lib -I t/lib -lr t/performance` |
| `lint` | `node --test t/js/*.test.cjs` |
| `lint` | `script/gpforum-carton exec script/perl-syntax-check` |
| `lint` | `script/perltidy-check` |
| `lint` | `script/perlcritic` |
| `lint` | `script/architecture-check` |
| `lint` | `script/gpforum-carton exec perl script/adr-index --check` |
| `unit` | `script/gpforum-carton exec prove -l -j 4 t` |
| `integration` | `postgresql-client-16` |
| `integration` | `bin/gpforum migrate` |
| `integration` | `bin/gpforum performance-seed --profile small` |
| `integration` | `bin/gpforum budgets --sync` |
| `integration` | `bin/gpforum budgets --check` |
| `integration` | `script/query-plan-check --require-db` |
| `integration` | `bin/gpforum os-preflight --json` |
| `integration` | `clamd --config-file` |
| `integration` | `make integration JOBS=4` |
| `integration` | `bin/gpforum benchmark --fixture --check` |
| `integration` | `bin/gpforum query-plan-evidence --check` |
| `integration` | `script/benchmark-http --configured --check` |
| `integration` | `bin/gpforum hypnotoad-benchmark --check` |
| `integration` | `bin/gpforum platform-check --with-db` |
| `coverage` | `postgresql-client-16` |
| `coverage` | `bin/gpforum migrate` |
| `coverage` | `bin/gpforum performance-seed --profile small` |
| `coverage` | `bin/gpforum budgets --sync` |
| `coverage` | `clamd --config-file` |
| `coverage` | `script/coverage -j 4` |
| `coverage` | `name: gpforum-cover-db` |

The ADR index check is new as a step of its own; it also runs inside
`t/190-gate-honesty.t`.

## Running the gates locally

```sh
make check                          # the ci.yml quality gate
make cpan-audit                     # CPANSA advisories against the lock
make evidence-archive-check         # archived ops evidence, --strict
make staging-drill                  # migration fresh/upgrade/dump-restore
make staging-drill-attachments      # attachment restore + deploy templates
make mail-lifecycle-check           # identity mail under the test transport
make dead-letter-check              # dead-letter lifecycle, in memory
make stress-load-dry                # stress-load plan, no HTTP traffic
make staging-host-verify            # non-destructive host verify
make private-beta-checklist         # print-only preparation status
```

`make cpan-audit` needs CPAN::Audit installed for the system Perl. It is a host
tool, like Carton: it audits `cpanfile.snapshot`, so it must not become part of
it.

```sh
sudo "$(script/gpforum-system-perl --print)" -S cpanm -M https://cpan.metacpan.org/ CPAN::Audit
```

## Pipeline rules

- **Actions are pinned to a commit SHA** with a version comment. `security.yml`
  fails the build when an unpinned `uses:` appears in a workflow or in the
  composite action.
- **Tool downloads are checksummed.** gitleaks and actionlint are installed from
  pinned release archives verified with `sha256sum --check --strict`.
- **Workflow permissions start at `contents: read`** and are widened per job
  only where a job needs it (SARIF upload, release creation, attestation).
- **Secrets never enter the repository.** [.gitleaks.toml](../.gitleaks.toml)
  scopes the scan; its only content allowlist covers `t/` fixture hashes, which
  exist to prove hashing and redaction behaviour.
- **Accepted advisories are documented.**
  [etc/cpan-audit-ignore.txt](../etc/cpan-audit-ignore.txt) carries a reason, a
  mitigation and a review trigger per entry. Anything else fails the scan.
- **The dependency cache is keyed on the lock** (`cpanfile`,
  `cpanfile.postgres`, `cpanfile.snapshot`), the runner OS and architecture, and
  the system Perl version, so a cache hit can never change the installed tree.
- **Evidence is validated, not trusted.** Every JSON blob a workflow produces
  goes through `bin/gpforum evidence-validate --strict`, and archived
  evidence goes through `script/gpforum-evidence-archive-check`.

## Shared setup

[.github/actions/setup-gpforum-perl](../.github/actions/setup-gpforum-perl/action.yml)
is the composite action every Ubuntu workflow uses: system packages, Carton for
the system Perl, the system-Perl assertion, the dependency cache, and
`script/bootstrap-deps`. `ci.yml` keeps those steps inline on purpose — it is
the canonical gate, pinned command by command by `t/18-github-project.t` and
`t/706-ci-finishes.t`, so the contract tests read the pipeline itself rather
than an indirection. Its jobs share each setup step through a YAML anchor
(`&checkout`, `*checkout`), written once in the first job.

## Continuous performance measurements

[benchmarks/README.md](../benchmarks/README.md) documents the scenarios,
baseline rules, bounded cost, schema, local commands and publication model.
Relevant PRs and pushes to `main` now run real Hypnotoad and PostgreSQL
benchmarks automatically. PR jobs compare the exact base/head revisions on
one runner with separate disposable databases and locked dependency trees;
main runs retain compact evidence at `benchmarks/results/` on the
`performance-data` branch, never on `main`.
The weekly Monday 01:37 UTC/manual deep run adds
targeted worker/reactor scaling, PostgreSQL service comparisons and profiles.
The harnesses, schema validator, comparisons, report renderer, publisher and
contract tests are all Perl. Core-only bootstrap/report commands remain usable
before dependency installation. Run the contracts with
`script/gpforum-carton exec prove -I script/lib -I t/lib -lr t/performance`.
The separate [extreme workload](../benchmarks/EXTREME.md) adds a read-only
progressive/mixed/soak/spike/recovery job, with its own schema and artifact-only
results. It neither writes history nor grants repository write access.

Measurement jobs have a read-only token and upload summaries/artifacts even
after failures. Only a separate trusted-main job can write history; it
validates artifacts as data, rejects overwritten results and retries
ordinary concurrent Git pushes against the latest `performance-data` tip.
It never writes `main`, so publication can neither create a benchmark loop
nor race the pushes of the code. The data branch's rules must permit the
job-scoped token to append evidence commits. Raw diagnostic
logs/profiles have 14-day retention; permanent history contains small JSON
and regenerated Markdown only.

Timing regressions use compatible scenarios, repetitions, medians and MAD,
and remain advisory on shared runners. Functional, query-budget, N+1 and
plan-shape violations remain deterministic failures. Skipped/unmeasured
tests are shown explicitly and are never converted to PASS.

The earlier statement that Actions could not start because of account
budget is historical, not the current audit result. On 2026-10-11 the
[performance run 38122509516](https://github.com/gpicchiarelli/GPForum/actions/runs/38122509516)
completed its benchmark sequence before failing in the NYTProf step
(`Tests were run but no plan was declared and done_testing() was not seen`,
exit 254). The continuous harness preserves completed data when profiling
fails; a local configured profile must still be verified independently.
