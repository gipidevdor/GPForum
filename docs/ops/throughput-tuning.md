# Throughput tuning: 8 and 16 cores

Start with worker scaling, then per-worker connection admission. These profiles
are hypotheses to measure, not capacity promises. They do not install services
or change PostgreSQL settings.

## Published baseline

The [5 November campaign](../../benchmarks/http-complete/2026-11-05/report.html)
measured these authenticated pages at 100 concurrent sessions on a shared Apple
M4, 10 cores, 16 GiB. Values are medians of three repetitions:

| Page | 2 workers req/s | 4 workers req/s | 4 workers p95, ms |
| --- | ---: | ---: | ---: |
| Home | 326.6 | 579.6 | 298.8 |
| Thread | 165.7 | 307.9 | 808.4 |
| Search | 202.8 | 361.4 | 536.7 |

The current thread p95 falls from 1,096.4 ms with two workers to 808.4 ms
with four. The 723.3 to 808.4 ms increase compares the older and current
four-worker campaigns; it does not show latency worsening when adding workers.
At four workers and 100 sessions, application p95 is 11.63 ms, database p95
1.50 ms and outside-application p95 798.11 ms. The latter includes waiting,
transport and client overhead, rather than measuring a PostgreSQL lock or
the worker queue alone. Percentiles of these components cannot be added.

This closed-loop load keeps 100 requests outstanding. At roughly 308 req/s,
Little's law predicts a mean response time near 325 ms at saturation; the
ratio of p95 to mean alone cannot identify contention. Separate worker and
admission sweeps from measurements at a fixed offered request rate.

The complete campaign establishes neither
8/16-worker scaling nor a comparison with Discourse/NodeBB. Match hardware,
dataset, permissions, sessions, response content, cache state, durability and
generator before comparing competitors. Do not add estimated percentage gains.

A [thread-only follow-up](../../benchmarks/thread-tail/2026-11-05/README.md)
on the same frozen application source measured 308.4 req/s / 790.4 ms p95
at four workers and 2048 connections per worker, versus 499.4 req/s /
286.7 ms at eight workers and 16 connections per worker (100 sessions,
three repetitions). All 59,910 measured responses across the three admitted
configurations were valid. Four workers / 32 connections reduced p95 at 100
sessions but worsened it at 50, so admission needs a workload sweep.
The [reverse-order confirmation](../../benchmarks/thread-tail/2026-11-06/README.md)
reproduced the advantage of 8/16 at 100 sessions in both orders. Across six
repetition statistics, the local reference is **491.8 req/s / 302.5 ms p95**,
versus 304.6 req/s / 797.0 ms for 4/2048. All 118,259 measured
responses in the 72 accepted forward/reverse cells were valid. Attempts with
detected concurrent tests are preserved and excluded. The 8/16 observed range
was 447.2–500.4 req/s and 284.2–324.5 ms p95; medians of cell
percentiles are not pooled request percentiles. [BASELINE.json](../../benchmarks/thread-tail/BASELINE.json)
records the frozen source, fixture and runtime for this thread-only reference.
The 200 ms p95 target remains open. Production defaults, mixed-write/realtime
capacity and the full PostgreSQL profiles below still require their own tests.

## Native transport follow-up

The [7 November regression investigation](../../benchmarks/mojo-pg-regression/2026-11-07/README.md)
compares the native transport and its fixes at a fixed two-worker budget. It
tracks promise overhead, connection churn in security/visibility checks and
atomic community commands, alongside complete HTTP correctness. Its source
manifests, rejected attempts and measured limits accompany the raw results.
Body preparation/signing and extended moderation/mention transactions retain
their bounded process isolation. Security decisions still read live SQL.

The native target-command changes require migration
`2044_native_community_targets.sql` and refreshed runtime API grants before the
new application workers start. Worker counts and database durability settings
were kept fixed during this comparison.

## Candidate configurations

Merge one fragment into the existing service environment, retaining required
credentials, listener and other installation settings. Keep the old environment
for rollback. CPU values must reflect available CPU/container limits; RAM and
reserve must reflect the database host. A 16-core/16-GiB machine needs a different
memory budget from the second example.

- [8 cores / 16 GiB](../../deploy/profiles/throughput-8core.env.example)
- [16 cores / 32 GiB](../../deploy/profiles/throughput-16core.env.example)

| Setting | 8 cores / 16 GiB | 16 cores / 32 GiB |
| --- | ---: | ---: |
| Web workers | 8 | 16 |
| Connections admitted per worker | 32 | 32 |
| Listen backlog | 1024 | 1024 |
| Temporary spare workers | 2 | 4 |
| Keep-alive requests / idle seconds | 1000 / 5 | 1000 / 5 |
| RAM reserved outside PostgreSQL, MiB | 8192 | 16384 |
| PostgreSQL shared_buffers, MiB | 2048 | 4096 |
| PostgreSQL effective_cache_size, MiB | 6144 | 12288 |
| PostgreSQL work_mem, MiB | 4 | 4 |
| PostgreSQL maintenance_work_mem, MiB | 128 | 128 |
| PostgreSQL max_connections | 100 | 100 |

The PostgreSQL rows are outputs of `Infrastructure::PostgresProfile` for these
inputs. Both also propose `random_page_cost=1.1`, `effective_io_concurrency=100`,
`jit=off` and `track_io_timing=on`. Recompute with the installed revision.
The reserve must cover workers, caches, other services and upgrade overlap.
`effective_cache_size` allocates no RAM; `work_mem` may be allocated by multiple
operations per active query. See PostgreSQL's [memory settings](https://www.postgresql.org/docs/18/runtime-config-resource.html)
and [planner settings](https://www.postgresql.org/docs/18/runtime-config-query.html).

The 32-client value is an experimental starting point. Sweep 16/32/50/250 at a
fixed worker count; 250 is the current application default. `clients` limits
accepted connections, including idle keep-alive connections. It does not enable
parallel synchronous SQL execution within one worker. Check long-lived realtime
connections separately before adopting a lower limit.

`OS::RuntimePolicy` already sets `accepts=10000`. This controls worker recycling,
not queue capacity; lowering it to 1000 can add restart overhead. `spare` supplies
temporary workers during graceful recycling. Software upgrades can temporarily
double the worker pool: budget RAM and database connections for overlap.
See [Hypnotoad settings](https://docs.mojolicious.org/Mojo/Server/Hypnotoad#SETTINGS).

`GPFORUM_POSTGRES_*` selects an assessment policy, without tuning the cluster.
Use the existing [inspect/plan/apply/restore workflow](postgres-performance.md).
Keep administrator credentials outside application services. `shared_buffers`
and `max_connections` require a database restart; verify using a fresh runtime
connection afterwards. Retain WAL durability and autovacuum.

## Benchmark procedure

1. **Freeze the comparison.** Use an isolated checkout and disposable database.
   Record commit/local diff, versions, effective CPU/RAM limits, storage, reactor,
   listener, cache backend, effective PostgreSQL settings and generator. Keep
   fixture/session counts identical and run arms sequentially.
2. **Measure worker scaling.** The command below runs 4/8 then 8/4 workers with
   independent authenticated sessions. Each output directory must be new.
3. **Inspect every result.** Require `status=ok`, zero failed responses and
   complete planned-cell coverage in `http-complete.json`/`report.html`. Preserve
   failed attempts and reruns. Compare matching scenario/concurrency cells,
   reporting medians and ranges across repetitions. Keep percentiles per cell.

```sh
for arm in a4 a8 b8 b4; do
  case "$arm" in
    a4|b4) worker_count=4 ;;
    a8|b8) worker_count=8 ;;
  esac
  script/gpforum-carton exec script/benchmark-http-complete \
    --output "artifacts/throughput-$arm" --workers "$worker_count" \
    --worker-clients 32 \
    --iterations 100 --warmup 10 --duration 15 --repetitions 3 \
    --concurrency 1,8,32,100 --deadline 1800 \
    --scenario member.home --scenario member.thread \
    --scenario member.search --scenario member.notifications || exit 1
done
```

This command measures worker count with the harness's own configuration:

- The complete harness accepts at most 8 workers and 100 sessions.
- `--worker-clients` sets the connection limit per worker (default 2048);
  configuration and serving-worker telemetry both record it. Sweep this option,
  rather than the service environment, which the harness overrides. Backlog is
  fixed at 1024 and keep-alive requests at 100,000,000.
- Its private PostgreSQL cluster has its own settings, including
  `max_connections=80`; the profile variables do not tune that cluster.
- Only the four hot member pages above get concurrent read cells. Guest and
  category reads are single-client latency measurements.
- Background delivery and realtime listeners are disabled.

Do not label its outputs as tuned-PostgreSQL or 16-worker results. A 32-client
result requires `--worker-clients 32` and matching serving-worker telemetry.
Supporting 16 workers, 128 sessions and guest/category concurrency in this
harness requires separate implementation work.

4. **Measure actual admission settings on isolated staging.** Run the normal
   application entrypoint with a candidate environment on a seeded staging
   instance. Restart through its normal supervisor after changes. Check actual
   workers/settings with `gpforum status`, `gpforum doctor` and
   `gpforum postgres-performance inspect --json`.

   Sweep workers 4/8/12 on the 8-core host and 8/12/16 on the 16-core host.
   Then hold the selected worker count and sweep clients 16/32/50/250. Reverse
   arm order for confirmation. Stop adding workers when CPU, contention or RAM
   rises without a repeatable throughput/latency improvement.

For the guest cache-hit arm, set these two variables to the isolated staging
origin and its seeded public thread path. Preserve every command's output with
worker/client arm, concurrency and repetition; the five-second pass is warmup:

```sh
: "${GPFORUM_BENCHMARK_BASE_URL:?set the isolated staging origin}"
: "${GPFORUM_BENCHMARK_THREAD_PATH:?set a seeded public /t/ID path}"
for concurrency in 1 8 32 128; do
  wrk --latency -t1 -c "$concurrency" -d5s \
    "$GPFORUM_BENCHMARK_BASE_URL$GPFORUM_BENCHMARK_THREAD_PATH"
  for repetition in 1 2 3; do
    wrk --latency -t1 -c "$concurrency" -d30s \
      "$GPFORUM_BENCHMARK_BASE_URL$GPFORUM_BENCHMARK_THREAD_PATH"
  done
done
```

Confirm HTTP 200, expected content and `X-GPForum-Source: public-http-cache`
before calling this a cache hit. Record errors/timeouts and actual cache
outcomes; measure misses separately. Repeat for guest home/category/search.
Keep proxy/TLS identical across arms. Standard wrk's displayed latency report
does not include p95: use raw samples or an explicit p95 histogram for that SLO.
Closed-loop wrk results do not establish latency at a fixed offered arrival rate.

The complete harness cannot target this staging instance. Authenticated
16-worker/admission sweeps need a generator supporting independent login/session
fixtures. One shared Cookie header measures a single-user workload, not that
session distribution. Do not compare absolute throughput between generators.

5. **Select and confirm.** Report per path/actor/cache state/concurrency:
   successful req/s, requests/errors, available p50/p95/p99, app/database/client
   timings, per-worker request distribution, application/PostgreSQL CPU and
   worker RSS. Linux CPU deltas can support requests per CPU-second; macOS `ps`
   averages are indicative. Report req/s per allocated core with database cores
   included. RSS snapshots are not peaks and can count shared pages repeatedly.

   Choose the smallest arm meeting throughput and p95 at the intended load,
   with no correctness failures or sustained memory pressure. A 400–500 req/s
   authenticated-thread target with p95 below 150 ms needs an explicit offered
   load and new measurements. Confirm with a longer mixed read/write run and
   normal background work. Restore the previous environment for rollback;
   database changes use the separate journal/restore procedure.

## Optimize only the remaining measured cost

Prepared statements are already cached per DBI handle in `PreparedQuery` and
`SqlFunction`; the latter uses `pg_prepare_now`. DBIx connects lazily and
reconnects after fork. Four to eight pooled connections per synchronous worker
increase backend count without making that page execute SQL concurrently.
Measure usage/contended connections before adding a pool.

Eligible public category/thread pages already have SSR caching. Profile the
existing bounded source/presentation caches and template/serialization cost
before adding another layer. Member HTML includes permissions, CSRF/session
data, read state and personal counters. Any new fragment needs viewer scope,
locale/theme/version keys and changed-permission/cross-user tests. Existing
PostgreSQL invalidation and revision checks are described in
[Performance](../PERFORMANCE.md#the-public-page-cache); asynchronous outbox
delivery alone does not provide immediate visibility revocation.

Inspect internal plans and actual query budgets before adding covering indexes
or more function logic. A single main page-function call does not eliminate
configuration/session/authorization/counter queries around it. Keep canonical
writes and required audit/authorization checks in their existing transaction.
