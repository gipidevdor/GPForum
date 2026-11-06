# Reload and Restart

Restart the service to load new code or configuration. The manager drains
active requests up to its graceful timeout; schedule a service interruption.
`systemctl reload gpforum` is unsupported.

## What went wrong

The former `Type=forking` unit tracked a manager PID that Hypnotoad hot deploy
replaced. Reload could leave the replacement unsupervised and fail the service.
The current foreground manager keeps its PID; hot deploy and `USR2` are
unsupported ([ADR 0175](../adr/0175-foreground-services-own-their-unix-lifecycle.md)).

| Signal | Effect in service mode |
| --- | --- |
| `INT`, `TERM`, `QUIT` | Drain active requests, bounded by the graceful timeout |
| `HUP` | Reopen manager and worker logs; configuration stays as loaded |
| `TTIN` / `TTOU` | Grow / shrink the worker pool by one |
| `USR2` | Unsupported; use a controlled service restart |

## What to do instead

Load new code or configuration:

```sh
sudo systemctl restart gpforum
```

Requests still active after the graceful timeout may be terminated. When
continuous service is required, use the multiple-node procedure below.

Resize the worker pool without changing the manager PID:

```sh
sudo systemctl kill --kill-whom=main --signal=TTIN gpforum   # one more worker
sudo systemctl kill --kill-whom=main --signal=TTOU gpforum   # one fewer
```

The `Type=notify` unit tracks the foreground manager. An exclusive instance
lock protects its PID file. See [readiness and watchdog behavior](../adr/0155-host-readiness-mail-and-reproducible-data.md).

## Zero-downtime deploys

Use multiple application nodes and drain each at the proxy before restarting
it. The [native supervisor drill](unix-daemons.md) exercises restart, stop and
watchdog recovery on Linux.

## Related

Mojo::Pg connections belong to the process that opens them. Startup closes the
manager's connection before fork, including failed warmup and disabled warmup;
workers open their own. The actual-fork check in
`t/integration/postgres-mojo-pg.t` verifies native connection ownership.
See [ADR 0174](../adr/0174-mojo-pg-is-the-runtime-stored-function-transport.md)
and [ADR 0153](../adr/0153-postgresql-and-operational-boundaries-are-tested.md).

- `deploy/systemd/gpforum.service` — service unit and lifecycle settings
- [Partition maintenance](partition-maintenance.md) — operations that need a window
