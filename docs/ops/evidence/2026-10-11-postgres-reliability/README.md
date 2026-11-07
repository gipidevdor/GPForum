# PostgreSQL reliability evidence — 2026-10-11

Measured source commit: `3e1a0af78cee9cb79704f4730b7b7d933bc10874`.
All JSON files are unchanged copies of successful GitHub Actions artifacts;
the `.exit` sidecars record exit 0. This archive adds evidence without rewriting
older runs. It contains no raw SQL, connection credentials, binary profiles,
database clusters, base backups or WAL files.

## Linux recovery drills

Standard `ubuntu-26.04` runners, matching PostgreSQL native tools, private
Unix sockets, no external database, deadline 180 seconds. Each drill creates
the three-row fixture, verifies the physical-backup manifest, waits for the
target WAL archive, promotes and verifies the exact two retained bodies.

| Version | Evidence | Total drill seconds | Recovery seconds | Entire job seconds | Run |
| --- | --- | ---: | ---: | ---: | --- |
| PostgreSQL 16.15 | [pitr-pg16.json](pitr-pg16.json) | 3.178231353 | 0.550564870 | 67 | [38164145438](https://github.com/gpicchiarelli/GPForum/actions/runs/38164145438) |
| PostgreSQL 18.6 | [pitr-pg18.json](pitr-pg18.json) | 2.543896772 | 0.186962314 | 53 | [38164142557](https://github.com/gpicchiarelli/GPForum/actions/runs/38164142557) |

Both reports have all five checks true, `source_dirty=false`, exact counts
3 before / 2 after, and `server_stopped=true`. CI uses `--keep` for diagnostic
investigation, so `workspace_removed=false` is expected; the ephemeral runner
disposes of the kept cluster. Only JSON and sanitized bounded logs are uploaded,
with 14-day retention. These JSON copies are permanently available here.

These are single correctness rehearsals, not repeated performance comparisons.
Recovery time starts before the restored server launches and ends after
promotion and data verification. It excludes production provisioning,
off-host transfer and attachment recovery. The fixture cannot establish
production RPO/RTO, attachment consistency, archive durability or a PostgreSQL
version's relative performance. The older 108-second drill used different
tooling/configuration and is not a comparable baseline.

## PostgreSQL matrix

[Run 38164142663](https://github.com/gpicchiarelli/GPForum/actions/runs/38164142663)
completed successfully on all three majors. This existing matrix migrates
the full schema, verifies a second apply is a no-op, seeds the existing
`small` profile (5 users, 3 categories, 12 threads, 96 posts), and runs the
complete integration suite. Tests create additional temporary fixtures.
The collector then reads the seeded database with administrative visibility;
WAL/checkpoint counters include all test databases in this disposable cluster.

| Version | Integration assertions / files | Job seconds | Collector seconds | Diagnostics | Logical restore |
| --- | --- | ---: | ---: | --- | --- |
| PostgreSQL 16.15 | 10,746 / 100 | 243 | 0.026494664 | [JSON](postgres-diagnostics-pg16.json) | [JSON](staging-drill-pg16.json) |
| PostgreSQL 17.11 | 10,746 / 100 | 269 | 0.030427909 | [JSON](postgres-diagnostics-pg17.json) | [JSON](staging-drill-pg17.json) |
| PostgreSQL 18.6 | 10,769 / 100 | 232 | 0.027330897 | [JSON](postgres-diagnostics-pg18.json) | [JSON](staging-drill-pg18.json) |

Each diagnostic report is `status=ok`, has all nine sections `ok`, 25 ranked
statement observations, no findings and `source_dirty=false`. Planning tracking
and nested statement tracking were enabled only in these disposable services.
The snapshots are cumulative counters and estimates, not production workload
benchmarks. Their collection durations are one observation per major and
are not a throughput comparison. Query IDs cannot be compared across majors.

The three logical drills passed fresh migration, no-op reapply, upgrade
102→103 and dump/restore, then dropped all three owned databases. Restored
data includes 5 users and 12 threads. The drill explicitly excludes attachment
files. Four existing TODO expectations for `SuspensionStore` timestamp strings
remain non-blocking in the integration logs; they are not claimed as corrected.

## Validation

Both PITR JSON files pass `script/pitr-drill --validate`; all three diagnostic
files pass `script/postgres-diagnostics --validate`. All eight reports pass
`script/evidence-validate --strict`. A valid schema alone does not turn a
failed or skipped measurement into a pass; the linked runs and report status
establish execution here.

See [the full audit](../../../POSTGRESQL_RELIABILITY.md) for local tests,
file inventory, activation/rollback and deferred changes. Production-scale
recovery, attachment/database reconciliation and off-host backup retention
remain operator verification work.
