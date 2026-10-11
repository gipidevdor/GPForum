# Weekly extreme performance evidence

The dedicated [workflow](../.github/workflows/performance-extreme.yml) brings one
disposable GPForum installation towards saturation on a standard Ubuntu 26.04
GitHub-hosted runner. The ordinary workflow keeps its triggers, scenarios,
baseline rules and publisher; its tooling and tests now run in Perl too.
The extreme job has no push or pull-request trigger and never publishes commits to
`main`. Results are a Job Summary and an immutable artifact for each run/attempt,
retained for 14 days.

The first deployment is **manual only** until a reduced live trial verifies
setup, measurements, cleanup and artifact upload. The commented schedule is
`0 3 * * 0` with `timezone: Europe/Rome`; after that verification, enabling those
three lines schedules Sundays at 03:00 Italian local time. GitHub supports IANA
timezones directly, including daylight-saving changes, so no paired UTC cron or
duplicate benchmark is needed. This local time is outside the repeated autumn
hour and is valid at the spring transition. Hosted scheduling may start late;
03:00 is the requested schedule, not a guaranteed start-time SLA.
[GitHub schedule syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onschedule),
[timezone support announcement](https://github.blog/changelog/2026-03-19-github-actions-late-march-2026-updates/).

## Architecture and time budget

There is one job with `timeout-minutes: 30`, `contents: read` and `actions: read`.
The first step establishes a monotonic deadline before checkout or dependency
setup. Its read-only job API request derives elapsed time from GitHub's job
start timestamp, so runner initialization counts too. When that API is
unavailable it deducts 120 seconds conservatively and records that limitation
in `clock.json`. There is no PostgreSQL service initialized before the clock:
the coordinator creates its own temporary PostgreSQL 16 Docker container under
the same deadline.

The soft measurement deadline is 26 minutes after the job origin, leaving four
minutes for cleanup, JSON/schema validation, the report and artifact upload.
The setup budget ends five minutes after that same origin. The existing locked
Perl setup action has a five-minute backup timeout; generator installation is
also capped by the remaining setup budget. Cold dependency builds may exhaust
that allowance. Such a run keeps an explicit infrastructure/partial report and
does not claim that the stress profile completed.

| Phase | Intended upper budget |
| --- | ---: |
| Checkout, dependencies, container, migrations and seed | 5 minutes |
| Progressive endpoint stress | 8 minutes |
| Mixed anonymous reads | 7 minutes |
| Soak, optional spike and recovery | 6 minutes |
| Cleanup, report, schema and artifact | 4 minutes |

The coordinator checks the global residual budget before each phase and caps
subprocess timeouts. It stops admission of new measurements when the budget is
insufficient, retains completed samples, records skipped work, and terminates
owned processes. The standalone cleanup step is idempotent and runs before
finalization, so its result is included in the uploaded evidence. GitHub's
30-minute timeout is the final barrier. An immediate host kill cannot execute
cleanup or upload; disposable runner/container ownership bounds that failure.

## Workload and interpretation

The coordinator reuses the existing Hypnotoad, deterministic seed, wrk latency
parser, telemetry and disposable PostgreSQL support. It adds orchestration and
mixed/soak scenarios rather than a new load generator. Real endpoint readings
remain separate from the mixed browsing result. The full progression is
10 → 50 → 100 → 250 → 500, with an experimental 1,000-connection cell admitted
only after resource and prior measurement checks. Missing prerequisites or a
stop caused by errors, latency, saturation or budget exhaustion is recorded.
Each endpoint cell has two four-second repetitions (reduced: one second,
concurrency 10/50). Mixed and soak each use ten 30-second windows; reduced uses
three five-second windows. The read-only spike lasts ten seconds (reduced: three)
and uses a measured concurrency capped at 100, followed by bounded recovery.

The initial mixed distribution is configurable through `mixed_weights`:
`thread=50,category=20,home=15,search=10,other=5` (`other` reads the category list). These are percentages of
HTTP requests, not virtual users. Connections, completed requests, effective
concurrency when observable, and any generator limitations are reported
separately. Authentication and writes remain missing coverage unless an existing
safe session/CSRF fixture can support them; no production account is used.

The full deterministic dataset is larger than the ordinary deep fixture where
the setup allowance permits it. The report records requested and actual counts,
seed duration, content distribution, database size, PostgreSQL settings and the
exact application commit. A smaller fallback is explicit and cannot be labelled
completion of the original dataset. All database names and containers belong to
the current run; production connection strings are refused.

Soak windows retain throughput, percentile latency, CPU/RSS and error trends,
database connections/queues where observable, plus post-load recovery checks.
Observed application, database or generator saturation is distinguished from an
inconclusive colocated-runner measurement. Higher concurrency with declining
throughput and rising latency is not classified as an improvement. No result
certifies production capacity or converts req/s into simultaneous users.

## Evidence, security and cost

`extreme.json` contains configuration, environment, dataset, phase/sample
statuses, metrics, recovery and limitations. It uses the separate versioned
[extreme schema](extreme-schema-v1.json), leaving `schema-v1.json` and ordinary
history unchanged. `report.md` is the readable rendering, and `clock.json`
records deadline provenance. Diagnostics are artifact-only and redacted; no
password, token or sensitive connection string is published. The artifact name
is `gpforum-extreme-<run-id>-<attempt>` with no overwrite option.

Checkout does not persist Git credentials. The job has no repository write
permission, privileged PR follow-up, personal token, publisher or external load
service. A dedicated concurrency group preserves an advanced run and prevents
simultaneous extreme installations. Saturation is useful evidence; failed
setup, generator execution, cleanup or evidence validation remains a visible
failure. Skipped work is never a PASS.

GPForum is public: standard Ubuntu 26.04 supplies four vCPUs, 16 GB RAM and
14 GB SSD without execution-minute charges. This workflow uses one such runner
for at most 30 minutes weekly, plus explicitly requested manual runs. Artifact
storage has shared allowances and can incur charges above them; short retention
and compact redacted outputs limit accumulation. No larger runner, self-hosted
machine or paid load generator is provisioned.
[Hosted runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[Actions billing and storage](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

## Run and verify

Start with the reduced profile from the Actions tab, or:

```sh
gh workflow run performance-extreme.yml --ref main -f profile=reduced
gh run list --workflow performance-extreme.yml
gh run view <run-id> --log
gh run download <run-id> --name gpforum-extreme-<run-id>-<attempt>
```

After the reduced run verifies the complete lifecycle, use `-f profile=full`
for the full manual trial and enable the commented Sunday schedule. Optional
weights use `-f mixed_weights='thread=50,category=20,home=15,search=10,other=5'`.

For a local disposable environment with the project's locked dependencies,
use a fresh output directory for each run:

```sh
perl script/performance-extreme init --output artifacts/extreme-local --profile reduced
script/gpforum-carton exec script/performance-extreme run --output artifacts/extreme-local --profile reduced --docker --disposable-database
perl script/performance-extreme cleanup --output artifacts/extreme-local
perl script/performance-extreme finalize --output artifacts/extreme-local
perl script/performance-extreme validate --output artifacts/extreme-local
perl script/performance-extreme check --output artifacts/extreme-local

script/gpforum-carton exec prove -I script/lib -I t/lib -lr t/performance
actionlint
```

No live extreme run or measured duration is claimed by this initial document.
The real trial and its artifact will provide those values before scheduling is
enabled. The existing ordinary Linux run validates reused primitives but does
not validate this new mixed/soak workflow.
