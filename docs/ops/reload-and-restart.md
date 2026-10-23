# Reload and Restart

**`systemctl reload gpforum` is not supported, and that is deliberate.** It
used to be, and it killed the service.

## What went wrong

`ExecReload=` was byte-identical to `ExecStart=`. Running `hypnotoad` against a
live instance is its hot-deploy path: the new manager starts, sends `QUIT` to
the old one and takes over. Under `Type=forking` with `PIDFile=`, systemd read
the pid file once at start and went on tracking the original manager, so a
reload handed the service to a process systemd no longer supervised. The unit
was then either restarted or marked failed, depending on `Restart=`.

`ExecReload=/bin/kill -USR2 $MAINPID` does not fix it. `USR2` **is** the hot
deploy — see `perldoc Mojo::Server::Hypnotoad` — so the manager moves either
way. Hypnotoad has no reload-in-place signal:

| Signal | Effect |
| --- | --- |
| `INT`, `TERM` | Stop immediately |
| `QUIT` | Stop gracefully |
| `TTIN` / `TTOU` | Grow / shrink the worker pool by one |
| `USR2` | Hot deploy: replace the manager |

There is nothing honest to put in `ExecReload=`, so the directive is gone.
`systemctl reload` now fails with "operation not supported" instead of stopping
the forum.

## What to do instead

Pick up new code or new configuration with a restart:

```sh
sudo systemctl restart gpforum
```

Workers finish in-flight requests during the graceful stop, so this is a short
interruption rather than a dropped connection, but it *is* an interruption.
Schedule it like any other deploy step.

To change the worker pool without a restart, signal the manager directly. This
does not move the pid, so systemd keeps supervising the same process:

```sh
sudo systemctl kill --kill-whom=main --signal=TTIN gpforum   # one more worker
sudo systemctl kill --kill-whom=main --signal=TTOU gpforum   # one fewer
```

The current `Type=notify` unit tracks the foreground manager directly, so
there is no pid file to look up. Its readiness and watchdog behavior is
specified in [ADR 0155](../adr/0155-host-readiness-mail-and-reproducible-data.md).

## Zero-downtime deploys

The foreground `Type=notify` unit now reports readiness and feeds a watchdog.
It still does not transfer systemd's `MAINPID` to a replacement manager, so
Hypnotoad hot deploy remains unsupported. Use multiple application nodes and
drain them at the proxy around each restart when upgrades must keep serving
requests. Actual systemd restart behavior requires validation on Linux.

## Related

The application's PostgreSQL connection is lazy in each worker. The warmup
closes the manager's handle even when rendering fails, and the pre-server hook
also closes an existing handle when warmup is disabled. DBIx discards an
inherited handle on PID change without disconnecting the parent's backend.
`t/integration/postgres-query-catalogue.t` exercises an actual fork and checks
that the parent still queries afterwards. These guarantees concern database
connection ownership; they do not change the systemd manager-tracking limit
above. See [ADR 0153](../adr/0153-postgresql-and-operational-boundaries-are-tested.md).

- `deploy/systemd/gpforum.service` — the unit, with the reasoning inline
- `docs/ops/partition-maintenance.md` — another operation that needs a window
