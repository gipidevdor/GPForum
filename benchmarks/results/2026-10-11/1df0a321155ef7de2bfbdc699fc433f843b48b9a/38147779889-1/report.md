# GPForum continuous performance evidence

Commit: `1df0a321155ef7de2bfbdc699fc433f843b48b9a` · mode: **main** · status: **failed**
Run: 38147779889 / attempt 1 · 2026-10-11T14:35:36.487519+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, INTEL(R) XEON(R) PLATINUM 8573C.

Versions: {}

Dataset: {}

Baseline: No baseline available.

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| database:query-budget-catalog | — / — / — / — | 1 | ok (indicative) | — | — | — | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.444 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.031 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.427 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.492 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.086 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.891 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.727 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.091 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.088 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.007 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.027 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.006 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.003 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.377 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.450 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.231 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.293 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.071 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.047 | — | — / — | not-comparable |
| database:sql-plan-readers | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.049 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.022 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.365 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.360 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.477 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.379 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.433 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.231 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.296 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 2.699 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 1.040 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.185 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.155 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.011 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.175 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.049 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.018 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.071 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.103 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.054 | — | — / — | not-comparable |
| database:sql-plan-functions | — / — / — / — | 3 | ok (measured-comparative) | — | — | 0.064 | — | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 1 / — | 3 | ok (measured-comparative) | 558.179 | 165.984 | 210.132 | 380.095 | — / — | not-comparable |
| outbox:postgres-dispatch-noop | — / — / 2 / — | 3 | ok (measured-comparative) | 934.107 | 210.340 | 238.546 | 239.646 | — / — | not-comparable |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |

## Suite status and skipped tests

- contracts: **ok** — GitHub Actions step outcome: success
- database: **ok** — See individual gates and diagnostic artifacts; skipped suites never imply execution
- database-plans-functions: **ok** — Nested stored-function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- database-plans-readers: **ok** — Nested stored-function plans require auto_explain LOAD; unavailable or unmeasured is never PASS
- databases: **ok** — GitHub Actions step outcome: success
- hotpaths_workflow: **ok** — GitHub Actions step outcome: success
- http: **failed** — wrk did not identify its version
  - {"reason": "read-only anonymous suite; safe durable auth fixture unavailable", "scenario": "authenticated"}
  - {"reason": "bounded targeted plan: every endpoint at low load; high concurrency on health/thread/search/cache_hit; extra workers only thread/search/cache_hit", "scenario": "full_cartesian_matrix"}
  - {"reason": "bounded PR/main modes; use deep sweep", "scenario": "concurrency_250_500"}
  - {"reason": "eight-worker sweep reserved for capable deep runners", "scenario": "workers_8"}
  - {"reason": "requires explicit --allow-1000 and capable runner", "scenario": "concurrency_1000"}
- http_workflow: **failed** — GitHub Actions step outcome: failure
- migrations: **ok** — GitHub Actions step outcome: success
- outbox: **ok** — See individual gates and diagnostic artifacts; skipped suites never imply execution
- outbox-postgres: **ok** — Fresh owned database is dropped on completion or caught signals; synthetic delivery IDs verify losses and duplicates
- pr_comment: **skipped** — Job Summary and artifacts provide PR results with a read-only token; no privileged fork artifact/comment workflow is enabled.
- profiling: **skipped** — Reserved for bounded weekly/manual deep mode
- query-budget: **ok** — Catalog drift is deterministic; N+1 request counts remain blocking in ci.yml integration tier
- query-plan-static: **ok** — Required index and forbidden OFFSET checks
- setup: **ok** — GitHub Actions step outcome: success
- sql-functions: **skipped** — Reserved for bounded weekly/manual deep mode
- tools: **ok** — GitHub Actions step outcome: success

## Limits

- Shared runners and a colocated load generator give comparative CI evidence, not production capacity.

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38147779889)
