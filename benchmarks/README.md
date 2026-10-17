# Performance evidence

This branch holds GPForum's continuous performance history only: the
`benchmarks/results/<UTC-date>/<commit>/<run-id>-<attempt>/` directories,
`benchmarks/latest.json` (the latest valid complete run) and
`benchmarks/history.json` (every run, partial ones included).

It shares no history with `main`. The publication job of
`.github/workflows/performance.yml` on `main` appends to it; nothing else
writes here, and nothing here is executed. The harness, schema and
documentation live on `main` in `benchmarks/`; see `benchmarks/README.md`
there. Until 2026-10-17 this history was committed to `main` itself; it was
moved here with its contents unchanged.
