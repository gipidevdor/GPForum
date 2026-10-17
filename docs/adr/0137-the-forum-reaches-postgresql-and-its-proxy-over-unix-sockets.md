# ADR 0137: The Forum Reaches PostgreSQL and Its Proxy over Unix Sockets

## Status

Accepted (2026-10-17). The owner asked that GPForum talk to PostgreSQL and
to its proxy over Unix sockets, tuned for it. Commit 962543c moved the
listener and the default DSN; a review of that move (2026-10-16) found the
connection options, the peer identities, the upgrade path and the
diagnostics unfinished. This records the decision and what completes it.
It amends ADR 0123 (the printed service files have one variant) and works
within ADR 0127 (the runtime role).

## Date

2026-10-17

## Context

On one host, a TCP loopback connection pays for a protocol stack that a
Unix-domain socket skips, and it is reachable by every local account,
which only the server's authentication then tells apart. A socket is a file:
its directory's permissions decide who reaches it, and PostgreSQL's `peer`
authentication reads the connecting process's operating-system account from
the kernel, so a local service needs no password at all.

Every connection GPForum made also ran six statements after it connected,
one of them a PL/pgSQL block with an exception handler to set
`lc_messages` where the role may. Each web process and each worker makes
its connection on its first request, and reconnects after a restart of
PostgreSQL.

## Decision

1. **Hypnotoad listens on a Unix socket, and the proxy forwards to it.**
   `GPFORUM_RUNTIME_LISTEN` defaults to `var/run/gpforum.sock` under the code
   directory; `gpforum start --service` refuses a TCP listener, in the
   operator's language, with what to set instead. The socket is the
   `gpforum` group's to read and write and nobody else's, so the proxy's
   account joins that group. There is one nginx site, one Caddyfile and one
   systemd unit; the TCP and socket variants are no longer two files.
2. **A local database is reached through its socket.** A DSN without
   `host=` uses libpq's default socket directory; `host=/directory` names
   another. A remote database still names its TCP host.
3. **A connection says who it is in its startup packet.**
   `GPForum::Config::database_connect_info` adds, unless the DSN already
   has them, `application_name=gpforum-ROLE` and `connect_timeout=5`. The
   role is `web` for what Hypnotoad loads and the verb otherwise
   (`gpforum-outbox`, `gpforum-scheduled-jobs`, `gpforum-migrate`), so
   `pg_stat_activity` and the server's log tell the processes apart. A
   local socket answers in milliseconds: five seconds is a server that is
   not answering, and the request fails instead of waiting for the kernel.
4. **The session is set in one statement.** The timeouts, the search
   similarity threshold and the message locale are one `SELECT` of
   `set_config` calls; `lc_messages` is set only where
   `has_parameter_privilege` says the role may (PostgreSQL 15 and later;
   GPForum supports 16 to 18). The settings stay session settings, not
   startup `options`, so a transaction pooler in front of PostgreSQL still
   accepts the connection.
5. **A socket is named by its path.** `gpforum setup`, `gpforum doctor` and
   the failure sentences name the server as libpq does: `host:port` over
   TCP, else the socket file, `DIRECTORY/.s.PGSQL.PORT`. Doctor takes the
   directory from the connection it made (`PQhost`); before a connection,
   a DSN without `host=` names the operating system's libpq default --
   `/var/run/postgresql` on Debian, Ubuntu and Red Hat, `/tmp` for
   Homebrew, the FreeBSD ports and PostgreSQL's own build. A socket that is
   not there is its own failure, "there is no PostgreSQL socket at ...",
   with the start command and `host=` to correct, not a refused connection.

6. **A unit sees the socket despite `PrivateTmp=true`.** The systemd units
   run with a private `/tmp` and `/var/tmp`. A distribution keeps the socket
   in `/var/run/postgresql`, which the units see; PostgreSQL's own build and
   some packages keep it in `/tmp`, which they do not -- doctor, run outside
   the unit, connected while the service found no socket. `gpforum service
   print systemd` writes, for the database socket the DSN names (or libpq's
   default): a directory under `/tmp` bound in with `BindReadOnlyPaths=`,
   which follows a server restart since the directory, not the socket file,
   is bound; for `/tmp` itself `PrivateTmp=false`, with a comment giving the
   way back -- a socket directory of the server's own in
   `unix_socket_directories` and `host=` naming it. Binding the socket file
   alone was rejected: a restarted server makes a new file the unit would
   not see. Doctor fails `database_socket` when the connection it made used
   such a socket and the installed `gpforum.service` hides it.

7. **Peer authentication has a map.** A distribution authenticates the
   socket by `peer`, which admits an account only as the role of its name;
   ADR 0127's runtime role and the operator's migrations are both other
   roles. `GPForum::Service::Operations::PeerAuthentication` writes one
   `pg_hba.conf` line -- `local`, the forum's database, `gpforum` and
   `gpforum_runtime`, `peer map=gpforum` -- to go above the distribution's
   own local lines, and the `gpforum` map: the service's account as both
   roles, the operator's login (`SUDO_USER`, else the real user's) as the
   owner. The line names the forum's database and roles alone, so every
   other connection keeps the distribution's rules, and neither role needs
   a password. `gpforum setup` prints it on a deployed host whose database
   is on the socket, it does not edit the server's files, which are the
   operator's. `gpforum doctor` also connects as `GPFORUM_ADMIN_DATABASE_USER`
   when the file names one, says a peer refusal as `database.peer`, and
   repeats the lines. The `peer-auth` workflow runs Debian's packaged
   cluster with the lines added, as the `gpforum` account and the runner.

### Server settings

| Setting | Value | Why |
| --- | --- | --- |
| `unix_socket_directories` | the distribution's (`/var/run/postgresql` on Debian), or one outside `/tmp` | the DSN, or libpq's default, must name it; systemd's `PrivateTmp=` hides `/tmp` from the service |
| `listen_addresses` | `''` when nothing reaches the server over TCP | no TCP listener to defend; `localhost` when a backup or a standby still connects over TCP |
| `unix_socket_permissions` | the default `0777` | `pg_hba.conf` decides who connects; the directory's mode is the first gate |
| `max_connections` | at least twice the web processes, plus the workers and the operator's sessions | each web process holds a query connection and a `LISTEN` connection |
| `pg_hba.conf` | `local` lines with `peer`, the `gpforum` map | no password for local services; see the runtime role guide |

`tcp_keepalives_*` and `ssl` do not apply to a socket.

## Measurements

On the development host (Apple M4, 10 CPUs, macOS, PostgreSQL 18.6, DBD::Pg,
`fsync=off` cluster made for the purpose), one database migrated to 121,
the connecting process and the server on the same host. The socket used
`peer` authentication with the `gpforum` map, TCP loopback `trust`. Each
pair was measured interleaved -- socket, TCP, TCP, socket -- so drift hit
both alike: 1,000 connections and 20,000 calls each, after 500 warm-up
calls. Microseconds.

| What | Socket median | Socket p99 | TCP median | TCP p99 |
| --- | ---: | ---: | ---: | ---: |
| `SELECT 1` round trip | 19.1 | 26.0 | 33.9 | 41.0 |
| `api.ops_doctor_outbox_v2()` round trip | 48.2 | 55.1 | 62.9 | 72.0 |
| connect, bare | 2,477 | 3,335 | 2,689 | 3,310 |
| connect and six session statements (before) | 3,599 | 4,303 | 3,988 | 4,813 |
| connect, startup options and one statement (now) | 2,617 | 3,189 | 2,872 | 3,407 |

Over the socket an API function's round trip costs 23% less than over TCP
loopback, and a bare one 44% less; the fixed cost of a statement is what
the socket removes. The six statements cost 1.1 ms of each connection: the
PL/pgSQL block alone was 0.98 ms (median), the five `SET`s 15 to 56 us
each. One statement and the startup options make a connection 27% cheaper
over the socket and 28% over TCP.

The script made its own cluster and dropped it; it connected with
`DBI->connect` and ran `$dbh->do` per statement, or a prepared statement
executed and fetched per call, as `GPForum::Infrastructure::SqlFunction`
does.

## Consequences

- A host whose DSN still names `127.0.0.1` for a local server pays the TCP
  costs above and needs a password. In staging and production doctor says
  so (`database_socket`, degraded), with the `host=` to remove or set.
- The proxy's account must be in the `gpforum` group to reach the socket.
  `gpforum service print nginx` and `caddy` say so beside the site, with
  the command for this operating system (`usermod -aG` on Linux, `pw
  groupmod -m` on FreeBSD, `dseditgroup` on macOS); the site always
  forwards to the socket, since the service refuses any other listener.
  The TCP upstream that `ServiceFiles` derived from a TCP listener is gone.
- A connect to the socket is queued at once, and a worker accepting until
  the queue is empty kept a whole burst of the proxy's new upstream
  connections: 59 to 103 of 128 on one of four workers, for as long as the
  proxy kept them alive. Since 2026-10-17 each worker takes one connection
  at a time from a Unix socket (`single_accept=1`, added by
  `GPForum::OS::RuntimePolicy` unless the location sets it), and a burst
  splits evenly ([PERFORMANCE.md](../PERFORMANCE.md#through-the-socket-2026-10-17)).

## Verification

- `t/693-database-session.t`: the startup options, the operator's own
  options winning, the process role, and the one session statement.
- `t/integration/postgres-plain-role.t`: a plain role connects with the
  session set and the server's message locale; a superuser gets `C`.
- `t/694-database-socket-names.t`: the socket a server is named by, in
  setup, doctor and the failure sentences, and a missing socket in both
  languages.
- `t/695-socket-upgrade-path.t`: the TCP refusal in both languages, the
  sites written for the socket, the group note, and the doctor finding.
- `t/696-private-tmp-socket.t`: the printed units for a socket outside, under
  and in `/tmp`, and doctor on an installed unit that hides it.
- `t/697-peer-authentication.t`, `t/integration/postgres-peer-map.t`: the
  lines, the refusal in both languages, doctor's two connections, and a
  cluster of the test's own admitting both roles with the lines and
  neither without them.
- `t/692-unix-listener.t`, `t/integration/postgres-unix-socket-clients.t`:
  the listener, its modes and the client addresses behind the proxy.
- `t/424-os-runtime-policy-report.t`: `single_accept=1` on each Unix
  socket that does not say otherwise, and on no TCP listener.

## References

- [PostgreSQL client connection parameters](https://www.postgresql.org/docs/18/libpq-connect.html#LIBPQ-PARAMKEYWORDS)
- [Peer authentication](https://www.postgresql.org/docs/18/auth-peer.html)
- [User name maps](https://www.postgresql.org/docs/18/auth-username-maps.html)
- [ADR 0123](0123-service-files-are-printed-for-the-host-from-the-templates.md),
  [ADR 0127](0127-separate-runtime-role-for-the-function-api.md)
