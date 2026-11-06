# ADR 0148: A Realtime Socket Ends With Its Session

## Status

Accepted. A read-only review of main on 2026-10-15 found that a realtime
socket stayed open after the session it was opened in had ended; the owner
asked for every defect it confirmed to be fixed under the ADRs. Unit and
PostgreSQL checks pass; acceptance of this decision does not establish
release readiness.

## Date

2026-10-22

## Context

`/realtime` checks the session once, when the WebSocket opens. After that
the socket lives in one Hypnotoad worker's `Realtime::ConnectionRegistry`
and nothing looks at the session again. Signing out, a password change, a
password reset or a staff sign-out everywhere revokes the session row, and
the socket opened in it kept receiving the member's notification badges
and the updates of the threads they follow, for as long as the browser
kept it open. The sign-out may reach another worker than the one holding
the socket, and workers share nothing but PostgreSQL.

## Decision

1. **The socket remembers its session.** `Controller::Realtime` registers
   the socket with the session id it was opened in, beside the user id.
2. **Each worker checks its sockets' sessions.** While a worker holds a
   socket, `Realtime::Hub` asks every 30 seconds, in one call for all its
   sockets (`live_session_ids`, `api.session_live_v2`, migration 135),
   which of their sessions are still live -- not revoked and not past
   their expiry, read as `api.session_validate_v1` reads it -- and closes
   every other socket, and any opened with no session, with WebSocket code
   1008, `session ended`. The check is a read: it revokes nothing. The
   timer stops with the worker's last socket.
3. **Signing out closes at once where it can.** The sign-out closes the
   sockets of that session on the worker that served it straight away;
   other workers close theirs at their next check.
4. **A failed check closes nothing.** A store that cannot answer is no
   evidence that a session ended; the failure is counted in the hub's
   `session_check_failures` and the next check tries again.

## Consequences

A socket outlives its session by at most half a minute, and on the worker
that signed it out not at all. Each worker holding sockets adds one indexed
read every 30 seconds, whatever its number of sockets. A client learns why
from the close code; a new socket needs a live session, which the
handshake checks (ADR 0017).

## Alternatives Considered

- **Publish a session-ended event through PostgreSQL `LISTEN/NOTIFY`.**
  Immediate on every worker, but it needs a listening connection per
  worker and a notification from every place that revokes a session; the
  periodic read covers every revocation, expiry included, with no new
  path.
- **Check the session on every message sent to the socket.** One read per
  delivery, on the hottest path, and a socket that receives nothing would
  still stay open.
- **Close sockets only on sign-out.** It misses revocations made
  elsewhere -- a password change, a reset, a staff action -- and expiry.
