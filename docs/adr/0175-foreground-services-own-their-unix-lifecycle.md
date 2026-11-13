# ADR 0175: Foreground services own their Unix lifecycle

Date: 2026-11-06. Status: accepted.

The supervisor must keep the process it starts. `gpforum start --service`
runs a native `Mojo::Server::Prefork` manager directly, using Hypnotoad's public
configurator for the existing settings. It always remains in the foreground;
the shipped explicit `--foreground` remains accepted. This removes the
detached/hot-deploy path from service mode. Development serving remains a
separate command mode. A service refuses `--listen`; its validated configuration
supplies the Unix listener.

The service manager subclasses public `start`, `run` and `ioloop` methods.
After Prefork installs its scoped handlers, `start` maps TERM and INT to its
existing graceful QUIT handler before forking. Worker handlers remain
Prefork's own. No private server method or vendor file is changed. Kernel
tests pin this integration boundary so a dependency update cannot silently
change stop behavior. The configured graceful deadline bounds a stuck request.

An exclusive nonblocking lock precedes listener creation. PID-file writes and
cleanup belong to the lock holder. Inherited descriptors are closed before
workers obtain their loop, so a dead manager's workers cannot prevent a
replacement. The inherited unconditional PID destructor is disabled even for
failed candidates. A startup failure or other unrequested stop returns failure;
a graceful stop returns success. Supervisors own restart and its delay.

systemd keeps its readiness notification and manager watchdog. launchd sends
TERM to the original manager and gives it an explicit stop deadline. FreeBSD
daemon(8) supervises and restarts the foreground manager with a five-second
delay. Its rc stop command terminates the supervisor first; forwarded TERM
drains the child without causing a restart. FreeBSD startup diagnostics reach
syslog. Finite maintenance jobs continue to use native timers or cron.

Application file logging owns HUP. The handler requests reopening; append
opens a replacement before relinquishing the previous handle. Failure retains
the old destination and is observable. The web manager propagates the request
to current workers. Configuration changes require a controlled restart; HUP
is not partial configuration reload. Supervisor stdout/stderr rotation remains
a separate host operation.

Each forked logger opens its own file descriptor before its first append.
An inherited open-file description would share flock ownership with its
parent, defeating exclusion between concurrent writers. A kernel-lock test
holds the parent's lock and verifies that a ready child cannot append until
that lock is released.

All services use an unprivileged account and umask 0027. Worker shutdown
deadlines and supervisor capture destinations are explicit. The generated
templates and their command guidance remain the deployment source of truth.

Real-process tests cover signals, concurrent starts, ownership, startup failure,
forced deadlines and log reopening. An opt-in native supervisor drill verifies
crash restart and in-flight drain under systemd, launchd or daemon(8); on Linux
it also verifies watchdog recovery. CI invokes it explicitly and fails when
the required supervisor is absent. Local evidence on one OS does not certify
another OS or establish production availability and recovery objectives.

See [the operational contract](../ops/unix-daemons.md) and
[reload and restart](../ops/reload-and-restart.md).
