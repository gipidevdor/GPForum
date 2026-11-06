# Throughput tuning: 8 and 16 cores

Start with worker scaling, then per-worker connection admission. These profiles
are hypotheses to measure, not capacity promises. They do not install services
or change PostgreSQL settings.

## Published baseline

The [2 November campaign](../../benchmarks/http-complete/2026-11-02/README.md)
measured these authenticated pages at 100 concurrent sessions on a shared Apple
M4, 10 cores, 16 GiB. Values are medians of three repetitions:

| Page | 2 workers req/s | 4 workers req/s | 4 workers p95, ms |
| --- | ---: | ---: | ---: |
| Home | 271.6 | 485.5 | 329.8 |
| Thread | 117.8 | 223.4 | 723.3 |
| Search | 133.0 | 254.2 | 903.4 |

These supersede older measurements for this fixture. They establish neither
8/16-worker scaling nor a comparison with Discourse/NodeBB. Match hardware,
dataset, permissions, sessions, response content, cache state, durability and
generator before comparing competitors. Do not add estimated percentage gains.

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
    --iterations 100 --warmup 10 --duration 15 --repetitions 3 \
    --concurrency 1,8,32,100 --deadline 1800 \
    --scenario member.home --scenario member.thread \
    --scenario member.search --scenario member.notifications || exit 1
done
```

This command measures worker count with the harness's own configuration:

- The complete harness accepts at most 8 workers and 100 sessions.
- Its server fixes `clients=2048`, backlog 1024 and keep-alive requests
  100,000,000, overriding service-environment values for these settings.
- Its private PostgreSQL cluster has its own settings, including
  `max_connections=80`; the profile variables do not tune that cluster.
- Only the four hot member pages above get concurrent read cells. Guest and
  category reads are single-client latency measurements.
- Background delivery and realtime listeners are disabled.

Do not label its outputs as a 32-client, tuned-PostgreSQL or 16-worker result.
Supporting 16 workers, 128 sessions, admission options and guest/category
concurrency in this harness requires separate implementation work.

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
