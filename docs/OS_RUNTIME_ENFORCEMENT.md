# Good Phorum OS Runtime Enforcement

Use `GPForum::OS::RuntimePolicy` to configure the prefork server's workers,
listeners and timeouts. Compare the enforcement report with
[observed runtime evidence](OS_RUNTIME_EVIDENCE.md) before treating a setting
as active.

## Runtime Contract

`GPForum::OS::RuntimePolicy` builds the server configuration at startup.
The configuration retains Mojolicious/Hypnotoad setting names; deployed service
lifecycle follows [the foreground manager contract](ops/unix-daemons.md).

Applied directly to the application:

- `listen`
- `workers`
- `spare`
- `clients`
- `backlog`
- `requests`
- `keep_alive_timeout`
- `inactivity_timeout`
- `graceful_timeout`
- `heartbeat_interval`
- `heartbeat_timeout`
- `upgrade_timeout`
- `proxy`
- `pid_file`

The application also stores the runtime enforcement report in
`gpforum_runtime_enforcement` and exposes it through metrics.

## Worker Enforcement

Default policy:

```text
GPFORUM_RUNTIME_WORKER_POLICY=cap-to-cpu
GPFORUM_RUNTIME_MAX_WEB_PER_CPU=2
```

If `GPFORUM_WEB_PROCESSES` exceeds `cpu_count * max_web_per_cpu`, the server is
configured with the capped value and the runtime enforcement report becomes
`degraded`. Operators can choose `configured` to preserve an explicit worker
count, but the preflight remains responsible for warning about oversubscription.

## Socket Enforcement

This section describes HTTP listener options, not the Perl-to-PostgreSQL
connection. Deployed application services and their local PostgreSQL connections
use Unix sockets; the TCP examples illustrate runtime option handling only.

`SO_REUSEPORT` is applied by adding `reuse=1` to Hypnotoad listen URLs only
when the OS profile reports support and the feature is enabled.

Examples:

```text
http://*:8080        -> http://*:8080?reuse=1
http://*:8080?fd=3   -> unchanged
http+unix://...      -> unchanged
```

HTTP keep-alive is enforced through Hypnotoad `keep_alive_timeout`. Low-level
`SO_KEEPALIVE` and `TCP_NODELAY` remain Mojolicious/runtime socket concerns and
are reported in OS posture rather than patched manually in application code.

## Static Transfer

Static files and attachments are still safest behind a reverse proxy, which
serves the static files itself. Good Phorum hands an attachment to the proxy with
`X-Accel-Redirect` when `GPFORUM_ATTACHMENT_ACCEL_REDIRECT` names a prefix.
The runtime evidence reports `static_transfer` as `configurable` when it does,
and `unavailable` when it does not, in which case Good Phorum serves the file
itself. The sendfile and X-Sendfile settings, which only changed a reported
mode, are gone.

## Degraded Modes

Runtime enforcement reports `degraded` when:

- configured web processes are capped by CPU policy;
- listen backlog is below the conservative floor;
- requested socket features are unsupported;
- no listen locations are configured.

Readiness includes runtime enforcement when the application provides a runtime
policy. Metrics expose the full report under `runtime_enforcement`.

## Backlog Saturation

Portable backlog saturation is not exposed consistently across macOS, FreeBSD,
and Linux. Good Phorum therefore reports the configured backlog and explicitly marks
runtime saturation as unavailable instead of inventing a false metric.

Linux operators can inspect kernel counters separately with tools such as
`ss`, `netstat`, `sar`, or eBPF/perf tooling. FreeBSD operators can use
`netstat`, `systat`, and `sockstat`.

## Before / After

| area | before | after |
| --- | --- | --- |
| Hypnotoad workers | described in runtime profile | configured from OS-aware runtime policy |
| Reuseport | reported in socket snapshot | applied to supported listen URLs |
| Backlog | not applied by app config | configured in Hypnotoad |
| Keep-alive | platform expectation | configured through Hypnotoad timeout |
| Graceful shutdown | supervisor concept | Hypnotoad graceful/upgrade timeout configured |
| Readiness | OS preflight only | optional runtime enforcement warning |
| Metrics | OS posture | OS posture plus runtime enforcement |

## Configuration

Environment variables:

```text
GPFORUM_RUNTIME_LISTEN=http+unix://var%2Frun%2Fgpforum.sock
GPFORUM_RUNTIME_WORKER_POLICY=cap-to-cpu
GPFORUM_RUNTIME_MAX_WEB_PER_CPU=2
GPFORUM_RUNTIME_BACKLOG=256
GPFORUM_RUNTIME_CLIENTS=250
GPFORUM_RUNTIME_REQUESTS=1000
GPFORUM_RUNTIME_KEEP_ALIVE_TIMEOUT=5
GPFORUM_RUNTIME_INACTIVITY_TIMEOUT=30
GPFORUM_RUNTIME_GRACEFUL_TIMEOUT=20
GPFORUM_RUNTIME_HEARTBEAT_INTERVAL=5
GPFORUM_RUNTIME_HEARTBEAT_TIMEOUT=5
GPFORUM_RUNTIME_UPGRADE_TIMEOUT=60
GPFORUM_RUNTIME_SPARE_PROCESSES=1
GPFORUM_RUNTIME_PROXY=on
GPFORUM_RUNTIME_TRUSTED_PROXIES=127.0.0.1,::1
GPFORUM_RUNTIME_PID_FILE=hypnotoad.pid
```

`GPFORUM_RUNTIME_TRUSTED_PROXIES` names the addresses or networks whose
`X-Forwarded-For` is believed. The default, the loopback, fits the shipped
nginx and Caddy units, which run on the same host. A proxy on another host
must be listed (for example `10.0.0.5` or `10.0.0.0/8`): until it is, every
client is seen as the proxy, and shares one rate-limit bucket. Any other
sender's `X-Forwarded-For` is ignored, so a client that reaches the
application directly cannot choose the address it is limited by.

Feature variables:

```text
GPFORUM_OS_REUSEPORT=auto
GPFORUM_OS_MIN_RECOMMENDED_WORKERS=2
GPFORUM_OS_MAX_OPEN_FILE_DESCRIPTORS=65536
GPFORUM_LOCAL_CACHE_MAX_ENTRIES=4096
GPFORUM_CATEGORY_CACHE_TTL_SECONDS=60
GPFORUM_GLIFISTORE_URL=
GPFORUM_REALTIME_LISTENER_ENABLED=on
GPFORUM_REALTIME_LISTENER_POLL_INTERVAL_SECONDS=1
GPFORUM_REALTIME_LISTENER_RECONNECT_BACKOFF_SECONDS=5
GPFORUM_REALTIME_LISTENER_HEARTBEAT_INTERVAL_SECONDS=30
GPFORUM_MINION_ENABLED=off
```

These defaults are the built-in professional small-production baseline for a
real forum, not a benchmark claim. They assume a reverse proxy, bounded
PostgreSQL connections, and `LimitNOFILE=65536` or an equivalent OS limit.
Local development can still override any setting through `GPFORUM_*`
environment variables.

## Production Profiles

Small production, for 2-4 vCPU and 4-8 GB RAM with PostgreSQL on the same host:

```text
GPFORUM_ENV=production
GPFORUM_LOG_LEVEL=info
GPFORUM_PUBLIC_BASE_URL=https://forum.example.com
GPFORUM_WEB_PROCESSES=auto
GPFORUM_RUNTIME_LISTEN=http+unix://var%2Frun%2Fgpforum.sock
GPFORUM_RUNTIME_WORKER_POLICY=cap-to-cpu
GPFORUM_RUNTIME_MAX_WEB_PER_CPU=2
GPFORUM_RUNTIME_BACKLOG=256
GPFORUM_RUNTIME_CLIENTS=250
GPFORUM_RUNTIME_REQUESTS=1000
GPFORUM_RUNTIME_KEEP_ALIVE_TIMEOUT=5
GPFORUM_RUNTIME_INACTIVITY_TIMEOUT=30
GPFORUM_RUNTIME_GRACEFUL_TIMEOUT=20
GPFORUM_RUNTIME_HEARTBEAT_INTERVAL=5
GPFORUM_RUNTIME_HEARTBEAT_TIMEOUT=5
GPFORUM_RUNTIME_UPGRADE_TIMEOUT=60
GPFORUM_RUNTIME_SPARE_PROCESSES=1
GPFORUM_RUNTIME_PROXY=on
GPFORUM_OS_REUSEPORT=auto
GPFORUM_OS_MIN_RECOMMENDED_WORKERS=2
GPFORUM_OS_MAX_OPEN_FILE_DESCRIPTORS=65536
GPFORUM_LOCAL_CACHE_MAX_ENTRIES=4096
GPFORUM_CATEGORY_CACHE_TTL_SECONDS=60
GPFORUM_GLIFISTORE_URL=
GPFORUM_REALTIME_LISTENER_ENABLED=on
GPFORUM_REALTIME_LISTENER_POLL_INTERVAL_SECONDS=1
GPFORUM_REALTIME_LISTENER_RECONNECT_BACKOFF_SECONDS=5
GPFORUM_REALTIME_LISTENER_HEARTBEAT_INTERVAL_SECONDS=30
GPFORUM_MINION_ENABLED=off
```

Medium production, for 4-8 vCPU and 8-16 GB RAM with PostgreSQL on the same
host, reached over its Unix socket and explicitly tuned:

```text
GPFORUM_WEB_PROCESSES=8
GPFORUM_RUNTIME_BACKLOG=512
GPFORUM_RUNTIME_CLIENTS=500
GPFORUM_RUNTIME_REQUESTS=2000
GPFORUM_RUNTIME_KEEP_ALIVE_TIMEOUT=5
GPFORUM_RUNTIME_INACTIVITY_TIMEOUT=30
GPFORUM_RUNTIME_GRACEFUL_TIMEOUT=30
GPFORUM_RUNTIME_UPGRADE_TIMEOUT=60
GPFORUM_LOCAL_CACHE_MAX_ENTRIES=8192
GPFORUM_CATEGORY_CACHE_TTL_SECONDS=120
GPFORUM_GLIFISTORE_URL=tcp://127.0.0.1:7379
GPFORUM_MINION_ENABLED=on
GPFORUM_MINION_PG_URL=postgresql://gpforum_worker@%2Fvar%2Frun%2Fpostgresql/gpforum
```

The Minion URL above explicitly names the Debian/Ubuntu socket directory.
For a server whose socket is in `/tmp`, use
`postgresql://gpforum_worker@%2Ftmp/gpforum`. Configure the job role through the
server's local authentication policy. This separate URL must also use the
socket when Minion is enabled; it is not derived from the application DSN.

## Acceptance Commands

```sh
bin/gpforum os-preflight --json
script/gpforum-carton exec prove -lr t/52-os-preflight.t t/53-os-runtime-policy.t
script/perlcritic --severity 5
```
