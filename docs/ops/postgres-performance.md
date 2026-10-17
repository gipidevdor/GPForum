# PostgreSQL performance enforcement

GPForum inspects effective PostgreSQL settings through `pg_settings`, without
requiring the runtime login to be an administrator. Each physical schema
connection in staging/production checks the selected profile and logs drift,
including reconnects and Hypnotoad workers. `/health/ready`, `gpforum status`,
`gpforum doctor` and `RuntimeEvidence` expose the same assessment. Ordinary
tuning drift degrades readiness (HTTP 200). Critical evidence, durability or
connection-capacity failures produce failed readiness. Only explicitly setting
`GPFORUM_POSTGRES_STRICT=1` refuses connections for tuning recommendations too.
The default is warning mode; it never silently applies configuration.

## Select a profile

Use the existing service environment file. A shared **host** means GPForum,
PostgreSQL and other processes share RAM; authority over a PostgreSQL **cluster**
is a separate decision. These settings are also in `deploy/gpforum.env.example`.

```sh
GPFORUM_POSTGRES_PROFILE=shared
GPFORUM_POSTGRES_TOPOLOGY=local
GPFORUM_POSTGRES_MEMORY_MB=16384
GPFORUM_POSTGRES_RESERVE_MB=8192
GPFORUM_POSTGRES_CPU_COUNT=8
GPFORUM_POSTGRES_STORAGE=nvme
GPFORUM_POSTGRES_STRICT=0
```

`PROFILE` accepts `shared` (default) or `dedicated`; `TOPOLOGY` accepts `auto`
(unknown ownership/location), `local`, `remote`, `managed`. Managed services
must be declared: there is no portable, reliable provider detector. `auto`
does not infer RAM from the application host, even for a loopback address
(which might be a tunnel). Explicitly local installations can use zero RAM
and CPU values to reuse GPForum's OS/cgroup probes. Remote/managed databases
require database host RAM and cores declared by their operator. Unknown RAM
or storage appears as a recommendation and prevents apply. Read-only inspect
still works. Storage accepts `unknown`, `hdd`, `ssd`, `nvme`.

Memory is in MiB. `RESERVE_MB=0` reserves half the RAM on shared hosts; on
dedicated servers it reserves at least 512 MiB or one sixteenth of RAM.
Increase it for application workers, other services and colocated databases.
This is an operator budget, not a probe of currently free RAM. PostgreSQL's
container limit can differ from the application's; explicit values are best
for separate containers. Reassess the budget after changing concurrency.

| Parameter | Dedicated 16 GiB, 8 cores, SSD/NVMe | Shared host, same RAM/cores, 8 GiB reserve |
| --- | --- | --- |
| shared_buffers | 4096MB | 2048MB |
| effective_cache_size | 12288MB | 6144MB |
| work_mem | 8MB | 4MB |
| maintenance_work_mem | 512MB | 128MB |
| random_page_cost | 1.1 | 1.1 |
| effective_io_concurrency | 100 | 100 |
| jit | off | off |
| max_connections | 100 | 100 |
| track_io_timing | on | on |

The formulas scale buffers/cache and maintenance with the budget and reduce
work memory as needed. Connections scale with CPU (up to 100), allowing two
connections per effective web worker and operational headroom. A minimum
memory estimate includes buffers, four maintenance allocations, 10 MiB per
backend and eight work_mem allocations per connection. This is a conservative
admission estimate, **not a hard memory bound**: sorts, hash_mem_multiplier,
parallel workers, multiple maintenance sessions and other databases can exceed
it. Measure real RSS and concurrency. `effective_cache_size` allocates no RAM.
An insufficient budget has no applicable profile and is critical. HDD/unknown
storage uses random_page_cost 4 and effective_io_concurrency 2; unknown storage
requires an explicit decision before apply. These are starting points, not
measured universal optima.

The tool observes `fsync`, `full_page_writes`, `synchronous_commit` and
`autovacuum` as critical safety settings. It never writes them. Its mutation
allowlist contains only the nine tuning parameters above. `fsync`, `full_page_writes` and `autovacuum` must be `on`; synchronous_commit accepts
`on`, `local`, `remote_write` or `remote_apply`, which confirm local WAL durability.
`off` is critical. Remote acknowledgement policy remains an operator decision
([PostgreSQL WAL settings](https://www.postgresql.org/docs/18/runtime-config-wal.html)).

## Inspect, review, apply, verify

```sh
gpforum postgres-performance inspect
gpforum postgres-performance inspect --json
gpforum postgres-performance verify --strict
```

Reports include each effective value, unit, source, context and pending_restart,
profile formulas/budget, findings and proposed changes. Values are normalized
using actual pg_settings units (including 8kB blocks); missing settings are
visible. Verify returns 1 for any finding even in warning mode. Inspect/plan
return 0 for recommendations and 1 for critical/strict failures. An ordinary
login can inspect and export a plan, but applying needs a plan made with the
separate administrator connection so cluster identity and previous overrides
can be captured. The application login needs no additional catalog grants.

In a **separate operator environment**, set `GPFORUM_ADMIN_DATABASE_DSN`,
`GPFORUM_ADMIN_DATABASE_USER`, `GPFORUM_ADMIN_DATABASE_PASSWORD` (or pgpass).
Do not add administrator credentials to web/outbox service units.

```sh
gpforum postgres-performance plan --output /secure/path/plan.json
# Review the entire file, target system_identifier, budget and affected databases.
gpforum postgres-performance apply --plan /secure/path/plan.json \
  --instance SYSTEM_IDENTIFIER --controlled-instance \
  --allow shared_buffers,effective_cache_size,work_mem,maintenance_work_mem,random_page_cost,effective_io_concurrency,jit,track_io_timing \
  --journal /secure/path/apply.jsonl
```

Use only parameter names listed in the reviewed plan's changes. Values already
matching the profile do not need authorization. `--controlled-instance`
asserts authority over **every database served by the cluster**, not just the
GPForum database. A server administrator/superuser and matching
`pg_control_system().system_identifier` and reviewed server address/port are required. The tool deliberately
does not attempt mutation on managed services or infer permission from a
localhost connection. Remote controlled servers can use the same workflow
with explicitly declared server resources; provider/shared instances use the
plan as input to their own configuration process.

Apply uses `ALTER SYSTEM`, never searches for arbitrary configuration files,
and refuses command-line/session/role overrides that would hide its effects.
It rechecks settings against the plan and current sized profile, serializes
its own runs with an advisory lock, writes only explicitly named parameters,
and requests reload. PostgreSQL cannot transact ALTER SYSTEM: partial failures
are possible, and the journal is the recovery mechanism. Do not edit cluster
configuration concurrently using another tool.

`shared_buffers` and `max_connections` require a restart. Reloadable settings
can still be masked by existing role/session overrides. Apply never restarts
PostgreSQL and never claims that a successful write is already active. Schedule
any restart through the host's normal supervisor, then verify on a **fresh
runtime-role connection**, without administrator credentials. `pending_restart`
fails strict/verify even if the old active value matches the recommendation.

Plan and journal paths must be new files; existing files are never overwritten.
Journals have mode 0600 and contain complete JSON Lines snapshots. Each intended
change is flushed and fsynced before ALTER SYSTEM and recorded again after it.
Keep the journal outside ephemeral directories. It includes original
postgresql.auto.conf overrides, preserving absence with ALTER SYSTEM RESET
rather than persisting an inherited value.

```sh
gpforum postgres-performance apply --restore /secure/path/apply.jsonl \
  --instance SYSTEM_IDENTIFIER --controlled-instance \
  --journal /secure/path/restore.jsonl
gpforum postgres-performance verify
```

Restore also handles partially completed apply journals; an incomplete final
record is ignored. It refuses intervening edits to the same override. Reapply
and restore are idempotent. Restore requests reload; a change that was already
activated by restart can need another scheduled restart to restore the active
value. Strict should be enabled only after verification, and can be disabled
in the service environment while correcting a profile or provider policy.

## Architecture and measurements

The setup command provisions roles/databases and runs migrations. Packages and
supervisors install/start PostgreSQL: systemd on Debian, rc.d on FreeBSD,
Homebrew services on macOS. Setup does not change server tuning. Existing
connection timeouts, application_name and pg_trgm similarity threshold 0.18
remain in Config. DBIx connects lazily per worker and reconnects after fork;
notifications reuse that connection. The connection estimate uses Runtime’s effective Hypnotoad worker cap and includes extra
room for workers, operational commands and graceful reloads; multiple nodes
need a cluster-wide operator budget.

The checkout's search catalogue uses ranked v8 (boundary)/v7 (implementation)
and autocomplete v6/v5. Ranked v9/v10 and autocomplete v7/v8 are absent here.
Candidate caps, live visibility lookups, ranking and permissions are unchanged.
Migration 102 uses force_custom_plan; migration 110 adds scoped ranked search.
GIN vector/trigram indexes and the newest-first index already exist. Use the
existing nested auto_explain capture (ANALYZE, BUFFERS, WAL) to inspect internal
statements instead of reporting only the function wrapper.

`script/bench-postgres-configuration` reuses `script/bench-sql-functions`'s
fixture and service operations and adds common/rare full text and trigram
search, raw latency samples, throughput, process CPU/RSS and database/I/O/WAL
snapshots. Preparation is explicit and restricted to `gpforum_perf_*` databases:

```sh
# On an isolated disposable server, create gpforum_perf_config_template first.
GPFORUM_DATABASE_DSN='dbi:Pg:dbname=gpforum_perf_config_template;host=LOCAL_SOCKET' \
  script/gpforum-carton exec script/bench-postgres-configuration \
  --disposable-database --prepare --search-documents 100000
# Disconnect, clone that same template for each arm, configure/restart manually.
GPFORUM_DATABASE_DSN='dbi:Pg:dbname=gpforum_perf_config_baseline;host=LOCAL_SOCKET' \
  script/gpforum-carton exec script/bench-postgres-configuration \
  --disposable-database --iterations 100 --write-iterations 30 --plans > baseline.json
```

Repeat for the optimized clone and for 1,000,000 documents if resources allow.
Compare document_id_digest and counts. Record hardware, PostgreSQL version,
effective settings and restart state for each arm. Run
`script/performance-outbox.pl --messages 1000 --workers 1,2 --repetitions 3 --json`
on each configuration too; it creates its own disposable database and reports
batch p50/p95/p99, throughput, per-worker CPU/RSS and I/O/WAL snapshots. CPU in the service harness covers the client
and its PostgreSQL backend, not all background workers. `ps` observations
require the database server to run on the same machine. Block/cache counters
are comparable when track_io_timing was off; its timing counters are not.

The measured unit is a serial service operation. It excludes HTTP/template
rendering and is not a saturation/capacity result. Use the existing HTTP and
extreme harnesses for concurrency. Small samples and fixed A-then-B ordering
do not establish a general performance improvement.

CI's PostgreSQL 16/17/18 matrix runs apply/restore checks only on its owned
disposable container (`GPFORUM_POSTGRES_CONTROLLED_TEST=1`). Ordinary test runs
never alter the caller's server. No global runner configuration is required.

Measured local A/B evidence for both corpus sizes is in [the dated benchmark record](../../benchmarks/postgres-configuration/2026-10-17/README.md).

PostgreSQL documents per-operator/parallel-worker memory allocations in
[resource consumption](https://www.postgresql.org/docs/18/runtime-config-resource.html),
setting provenance/restart state in
[pg_settings](https://www.postgresql.org/docs/15/view-pg-settings.html), and the
reload/restart behavior of
[ALTER SYSTEM](https://www.postgresql.org/docs/16/sql-altersystem.html).
