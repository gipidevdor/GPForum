# GPForum continuous performance evidence

Commit: `85c8441767f2bb8f46e89f9479dff7078cf4ec84` · mode: **main** · status: **skipped**
Run: 38147240758 / attempt 1 · 2026-10-11T14:27:45.842714+00:00

Runner: ubuntu-26.04, Linux/x86_64, 4 CPUs, AMD EPYC 9V74 80-Core Processor.

Versions: {}

Dataset: {}

Baseline: No baseline available.

Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.

| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |

## Baseline changes

| Scenario | Classification | Percentage changes |
| --- | --- | --- |

## Reactor and worker configuration changes

These compare configurations within this run; they are not commit regressions.

| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |
| --- | --- | --- | ---: | --- | --- |

## Suite status and skipped tests

- database: **skipped** — No measurement data was produced.
- databases: **skipped** — GitHub Actions step outcome: skipped
- hotpaths_workflow: **skipped** — GitHub Actions step outcome: skipped
- http: **skipped** — No measurement data was produced.
- http_workflow: **skipped** — GitHub Actions step outcome: skipped
- migrations: **skipped** — GitHub Actions step outcome: skipped
- outbox: **skipped** — No measurement data was produced.
- pr_comment: **skipped** — Job Summary and artifacts provide PR results with a read-only token; no privileged fork artifact/comment workflow is enabled.
- setup: **skipped** — GitHub Actions step outcome: skipped
- tools: **skipped** — GitHub Actions step outcome: skipped

## Limits

- Shared runners and a colocated load generator give comparative CI evidence, not production capacity.

[Persistent history](https://github.com/gpicchiarelli/GPForum/tree/main/benchmarks/results)
[Run and artifacts](https://github.com/gpicchiarelli/GPForum/actions/runs/38147240758)
