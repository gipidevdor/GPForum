# Weekly extreme performance evidence

The dedicated [workflow](../.github/workflows/performance-extreme.yml) brings one
disposable GPForum installation towards saturation on a standard Ubuntu 26.04
GitHub-hosted runner. The ordinary workflow keeps its triggers, scenarios,
baseline rules and publisher; its tooling and tests now run in Perl too.
The extreme job has no push or pull-request trigger and never publishes commits to
`main`. Results are a Job Summary and an immutable artifact for each run/attempt,
retained for 14 days.

The schedule is enabled after the real reduced trial
[38158309753](https://github.com/gpicchiarelli/GPForum/actions/runs/38158309753)
verified setup, measurements, recovery, cleanup, schema and artifact upload.
`0 3 * * 0` with `timezone: Europe/Rome` requests Sundays at 03:00 Italian
local time. GitHub supports IANA
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

Use `-f profile=full` for a full manual trial; scheduled runs already select
that profile. Optional
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

## Verified evidence on 2026-10-11

The reduced [Linux trial](https://github.com/gpicchiarelli/GPForum/actions/runs/38158309753)
measured commit `dd08edc9a7d5486ddfe6d2ae22f8acbfe6d33112` on four vCPUs
(AMD EPYC 7763), approximately 16 GB RAM, Ubuntu 26.04, Perl 5.40.1,
Mojolicious 9.49 and PostgreSQL 16.15. Both serving workers verified EV with
epoll backend 4. The seed actually contained 25 users, eight categories,
240 threads and 4,800 posts. Thirty-nine real samples completed with zero
HTTP, transport or timeout errors. Setup, mixed/soak/spike, recovery and
cleanup completed; progression remains **partial** because homepage and
cache-miss degradation at 50 connections caused explicit inconclusive stops.
The Actions job succeeded in **2 minutes 45 seconds**; this is a successful
evidence lifecycle, not a claim that saturation or every full-profile cell passed.

| Reduced scenario | Requested connections | Median RPS | Median p95 ms |
| --- | ---: | ---: | ---: |
| HTTP health (two one-second samples) | 10 | 2,282.6 | 5.7 |
| Home (two one-second samples) | 10 | 196.1 | 81.3 |
| Thread (two one-second samples) | 10 | 1,583.9 | 9.4 |
| Search (two one-second samples) | 10 | 111.4 | 128.1 |
| Weighted mix (three five-second samples) | 50 | 468.0 | 270.5 |
| Soak mix (three five-second samples) | 50 | 491.2 | 243.5 |

Mixed server CPU was about 164% summed across processes (about 1.64 CPU cores),
with sampled RSS around 376 MiB; shared pages can be counted more than once.
Recovery completed three successful health/thread/search rounds in 0.52 seconds.
The job clock used its explicit conservative fallback, including the 120-second
deduction; `extreme.json` records 277.45 seconds for that accounting clock.
The immutable artifact is `gpforum-extreme-38158309753-1` (53,644 compressed
bytes, expires 2026-10-25). Its schema was validated again after download;
diagnostics were checked for DSNs/tokens/password fields without findings.

The full 96,000-post profile, long soak and 100–1,000 connection levels have
not been executed by this trial. No cross-revision regression or production
capacity is established. The ordinary workflow retains its own paired/history
baselines and SQL/outbox/worker/reactor comparisons.

Port validation used ten Perl contract suites (249 top-level tests), 402
application suites (16,167 tests), four real PostgreSQL suites (221 tests),
workflow YAML parsing/actionlint, the architecture gate, strict Perl::Critic
and syntax checks. No new critic baseline entry or CPAN dependency was added.
The first ordinary CI trial preserved an infrastructure failure when a test
assumed the caller's password could not equal `postgres`; the test was isolated
and the complete contracts rerun with the real CI environment. Historical
archived files were not rewritten during the language migration.

The subsequent ordinary [main run 38158530813](https://github.com/gpicchiarelli/GPForum/actions/runs/38158530813)
also completed and published its
[permanent report](results/2026-10-11/d7bc8a523ef7f7c35515c9f1413738910b3e6d15/38158530813-1/report.md):
210 HTTP observations (204 wrk, six Mojolicious), 121 SQL observations and six
real PostgreSQL outbox observations, all successful. HTTP/transport errors,
outbox losses and duplicates were zero. Measurement took 10 minutes 29 seconds;
publication took 12 seconds and preserved the concurrently committed Sunday
schedule. `latest.json` now points to this valid run. The data-only publication
has no resulting CI run, confirming the publication does not loop.

No compatible cross-revision baseline was available after the harness migration.
Within that run, the three-repeat configuration comparisons found EV thread
p99 higher by 34.2% at concurrency 10 and 25.8% at 50; EV search p95 was 18.0%
higher at 10. Four Poll workers improved thread throughput by 45.7% at 50,
with about 64% more summed RSS. Those are advisory configuration findings on
this shared runner, and do not justify changing application defaults.
The complete general CI (including its broad coverage tier) was still in
progress when these performance runs completed; its pending stages are not
claimed as validated by the two benchmark jobs.
