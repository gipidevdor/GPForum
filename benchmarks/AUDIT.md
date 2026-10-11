# Performance CI audit — 2026-10-11

The audit read `docs/PERFORMANCE.md`, `docs/CI.md`,
`docs/ops/stress-load.md`, every GitHub workflow and the shared Perl setup
action before implementation. It inspected the HTTP/Hypnotoad/scaling,
stress, query-plan, query-budget, SQL-function, outbox and NYTProf commands
and their implementation modules.

| Finding | Implementation decision |
| --- | --- |
| `benchmark-http`, `bench-hypnotoad` and `bench-hypnotoad-scaling` issue requests serially. Their client setting cannot establish concurrent page capacity. | Preserve those useful single-client tools; measure each real endpoint independently with wrk and compare against the existing concurrent `stress-load` generator. |
| The existing stress profiles mix light and expensive routes and use a fixed request count. | Reuse its per-route mode as indicative evidence; use time-bounded wrk cells for primary throughput and latency measurements. |
| Parent-process reactor declarations do not prove what Hypnotoad workers use. Forced EV can silently fall back to Poll. | Verify private telemetry from every serving worker, including actual class, EV version/backend and versions; unavailable EV is an explicit skip. |
| The deterministic seeder commits its fixture changes. | Require both disposable acknowledgement and a dedicated database name, and use fresh service databases in CI. |
| Existing query budgets, index/OFFSET gates and reader/nested-function `EXPLAIN (ANALYZE, BUFFERS)` already work. | Reuse them, with SQL times separated from HTTP, rather than implement competing plan or N+1 rules. |
| The existing outbox fixture measures Perl/double overhead, not database concurrency. | Add the actual dispatcher on independent PostgreSQL connections in forked workers, using owned databases and a no-op recording transport. |
| The old profiling workflow's last five inspected runs failed in profiling; the latest inspected failure exited 254 after an assertion without a Test::More plan. Jobs actually started. | Replace that step with the current configured `profile-nytprof` helper in deep mode. Its local real-database invocation succeeded; remove the stale assertion that billing prevented execution. |
| A full endpoint × reactor × worker × concurrency matrix wastes minutes on colocated runners. | PR paired smoke; representative main; targeted weekly deep sweep, progressive concurrency and bounded wall-clock deadlines. |
| The repository is public; standard hosted Linux runners incur no execution-minute charge. Artifact storage still has limits. | Reuse standard Ubuntu, exact locked dependency caches, one measurement job and 14-day diagnostic artifacts; no larger runners or paid service. |
| A write token in a PR job or privileged execution of downloaded code would cross the fork trust boundary. | Read-only PR jobs and no persisted Git credentials; a separate trusted-main publisher consumes validated data only. |
| The user subsequently required deletion of every non-main branch. | Publish canonically on main rather than a permanent results branch; data/index paths do not trigger performance CI, GITHUB_TOKEN suppresses recursive workflows, and ordinary push retries preserve concurrent code commits. |

The repository had no main protection or rulesets at the final permission
inspection, and default workflow permissions were read-only. The publisher
requests `contents: write` for its own job only. Actual billing usage or
account artifact quotas were not available and are not claimed as checked.

Local verification used macOS arm64, Perl 5.44, Mojolicious 9.49,
PostgreSQL 18.6 and wrk 4.2.0. Actual default and forced Poll were Poll;
forcing EV fell back to Poll because EV was unavailable. The subsequent
[successful Linux run](https://github.com/gpicchiarelli/GPForum/actions/runs/38149645101)
verified every serving worker with Poll and EV 4.37/epoll, on four AMD EPYC
vCPUs and about 16 GB RAM, Perl 5.40.1, Mojolicious 9.49 and PostgreSQL 16.15.
It completed 210 HTTP observations (204 wrk, six Mojo), 121 SQL observations
and six real PostgreSQL outbox observations. No HTTP/transport errors were
recorded. Two/four-worker comparisons and three repetitions are archived;
neither EV nor additional workers improved every scenario. An absent
compatible historical baseline is explicitly not comparable.

The same run verified artifact upload, schema validation and a job-scoped
GITHUB_TOKEN push to main. Its measurement job took 10 minutes 7 seconds,
with an additional 11-second publication job. Earlier failed collection
attempts remain archived unchanged. Publication-only commits did not start
another performance measurement.

The real multiprocess outbox validation exposed a buffered pipe-read bug in
the new harness: one child could prefetch another child's release token.
The barrier now uses `sysread`, and repeated one/two-worker integration
tests verify every worker's report and cleanup of its owned database.

Interruption tests also exposed an existing test-support defect: localizing
Perl's magic child status inside the PostgreSQL harness END block converted
an error exit into success. Saving/restoring the scalar explicitly preserves
the exit status. A database-free subprocess test covers exit 0/1/7 and an
unhandled exception. Signal tests cover preserved completed outbox evidence
and cleanup of both owned outbox and SQL-function benchmark databases.

Runner capabilities, costs and token behavior were checked against
[GitHub runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
[Actions limits](https://docs.github.com/en/actions/reference/limits),
[GITHUB_TOKEN behavior](https://docs.github.com/en/actions/concepts/security/github_token),
and [Mojolicious reactor documentation](https://docs.mojolicious.org/Mojo/Reactor).
See [the operational guide](README.md) for triggers, budgets, limitations and
reproduction commands; archived measurements contain their own provenance.
