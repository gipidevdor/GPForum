# Unix service lifecycle

`gpforum start --service` always runs the native prefork manager in the
foreground, retaining the supervisor's original PID. `--foreground` remains
accepted explicitly. The manager uses Hypnotoad's public configuration API
and the existing `hypnotoad` settings. It never invokes a hot-deploy executable.
`--listen` is a development option; a service listener comes from configuration.

GPForum runs its web manager and notification workers in the foreground of
the host supervisor. systemd, launchd or FreeBSD's daemon(8) owns their
lifetime. Scheduled jobs and partition maintenance are finite commands,
started by timers or cron; they do not need another permanent daemon.

## Current contract

| Service | Normal stop | Crash recovery |
| --- | --- | --- |
| Web under systemd | TERM drains active requests; 150-second stop deadline | `Restart=on-failure`; HTTP startup readiness and a manager watchdog |
| Outbox and Push under systemd | TERM stops new batches and completes the current one; after 150 seconds systemd kills the remaining process group | `Restart=on-failure`, five-second restart delay |
| Outbox and Push under launchd | TERM stops new batches; `ExitTimeOut` gives the current batch 150 seconds | launchd KeepAlive policy; Push can exit successfully when disabled |
| Outbox and Push under FreeBSD rc.d | TERM to daemon(8) is forwarded to its worker | daemon(8) `-r` restarts its worker |
| Web under FreeBSD rc.d | The rc stop command terminates the supervisor, disabling restart, and its forwarded TERM drains the manager | daemon(8) `-r -R 5` restarts a failed manager |
| Web under launchd | TERM drains active requests; `ExitTimeOut` allows 150 seconds | launchd KeepAlive restarts the foreground manager, throttled to five seconds |

TERM, INT and QUIT all request a graceful stop in supervised web mode.
The systemd web unit limits watchdog abort handling to 15 seconds independently
of its 150-second graceful-stop deadline. The native drill scales these
timeouts down and verifies recovery after a real manager block.

The manager adapts Prefork's scoped handlers at its public `start` boundary,
before workers fork. It does not override private server methods. Ordinary
Mojolicious development servers retain their own signal behavior.

An exclusive nonblocking file lock is acquired before any socket can be
replaced. Workers close their inherited descriptor at the public `ioloop`
boundary before accepting requests. A failed candidate never owns PID-file
cleanup; the manager removes its own PID before releasing its lock. A live
PID or a symlink is refused. Stale dead PIDs are recovered under the lock.
Unexpected shutdown, including a worker failing before its first heartbeat,
returns failure so the supervisor can apply its restart policy.

Outbox and Push allow the current batch to finish. A forced stop can leave
leases to expire; it is not an acknowledgement. Existing claim ownership,
retry and idempotency rules still apply. An external provider may have
accepted a message before a forced stop, so retry can produce a duplicate.

The outbox tests send real INT and TERM signals both during dispatch and
during the idle wait. They verify clean exit and no subsequent batch claim
(`t/83-outbox-worker-wiring.t`).

## Permissions and logs

Every generated service runs as the configured service account. systemd
services, launchd jobs and the FreeBSD rc daemons set umask 0027, so ordinary
new files and directories are not accessible to other users. This does not
change existing modes or override an explicitly chosen file mode.
FreeBSD keeps the root-owned supervisor PID in `/var/run/gpforum` and defaults
application PID/lock state to its private, service-owned `app/` child. An
explicit `GPFORUM_RUNTIME_PID_FILE` from the environment file remains honored.

Application logs use the configured private log directory. systemd also
captures stdout and stderr in the journal. All launchd jobs have explicit
stdout and stderr paths, including failures before application logging has
initialized. `gpforum service print` renders these paths for the host and
prepares its launchd log directory when installing as root.

HUP requests application-log reopening. Signal handlers only set flags; the
next append opens the configured path before replacing the old descriptor.
A failed reopen reports a warning and retains the old destination. The web
logger also opens an independent descriptor after a fork, so file locking
actually excludes concurrent writers instead of sharing one inherited lock.
The web manager forwards HUP to its current workers at its next management turn.
Outbox and Push process HUP through the same logger without stopping their
current batch. HUP does not reload configuration.

On Linux, target the service with `systemctl kill --kill-whom=main
--signal=HUP gpforum` (or `gpforum-outbox` / `gpforum-push`). On macOS, use
`launchctl kill SIGHUP system/com.gpforum.app` (or the worker's label). On
FreeBSD, send HUP to the application child of that service's daemon(8), not
to unrelated Perl processes. Application-log reopening does not reopen a
supervisor's stdout/stderr capture files. Rotate those through the supervisor
or a controlled restart. Retention and disk-space alerts remain host operations.

## Acceptance on each target

Use a staging host with the production supervisor, runtime and database
major, and dedicated test accounts and notification receivers. Record the
commit, generated configuration, timings, process tree and service logs.

1. Start from the generated files and reboot. Confirm the expected manager,
   workers and timers run under the service account, with no second detached
   manager. Check `gpforum doctor` and HTTP readiness.
2. Stop each idle notification worker with its supervisor. Confirm it exits
   successfully, claims no new work and stays stopped. Repeat during a
   controlled delivery and verify the batch outcome or lease recovery.
3. Start a slow HTTP request and stop the web service. Verify the documented
   platform behavior and record any interrupted request. Graceful shutdown
   is a failed criterion if the request is dropped.
4. Kill only the staging manager or worker unexpectedly. Verify the native
   restart policy, PID ownership, absence of orphan workers and lease
   recovery. Do not substitute killing an unrelated application process.
5. Block a staging web manager and verify watchdog recovery on systemd.
   A live worker answering HTTP alone must not keep a blocked manager healthy.
6. Exercise database and provider outages. Verify bounded retries, useful
   errors and recovery after restoring the dependency. Confirm queue age and
   failed deliveries reach the operator's monitoring.
7. Force a worker beyond its stop deadline. Verify the remaining process
   group is cleaned up and the next worker can recover expired claims.
8. Check new state and log permissions, rotate logs, and verify fresh
   output and an intentionally invalid configuration are both observable.

`t/865-unix-service-manager.t` exercises real forked HTTP workers, in-flight
drain, forced deadlines, duplicate starts, live/stale PID ownership, startup
failure and log rotation. It needs no database or external supervisor.

`t/866-native-unix-supervisor.t` exercises an isolated job under the actual
host supervisor: crash recovery, an in-flight HTTP response across stop,
PID cleanup and no respawn after explicit stop. Linux also blocks the manager
to verify systemd watchdog recovery. It stages only source and dependencies
in a private temporary directory, avoiding macOS protected-folder access and
keeping production configuration and secrets out of the fixture. It records
the staged source hashes and runtime. Run explicitly on a test host:

```sh
GPFORUM_REQUIRE_NATIVE_SUPERVISOR=1 script/gpforum-carton exec prove -lv t/866-native-unix-supervisor.t
```

Linux needs systemd and passwordless sudo for its private transient unit;
macOS needs an active user launchd domain; FreeBSD needs daemon(8). The test
removes its own job. An opted-in run fails if the required supervisor is
unavailable. Deployment, macOS and FreeBSD workflows run this native drill.
The platform adapter lives in `GPForum::OS::SupervisorProbe`; the test controls
only its own private job and bounds native command time and captured output.
Parser validation remains an additional check for every shipped template.

For an operations release decision, pair this evidence with
[upgrade and rollback](upgrade.md), [backup and restore](backup-and-restore.md),
[live staging verification](staging-host.md) and
[the private-beta checklist](private-beta-checklist.md). A green local test
suite alone does not establish production recovery times or availability.
