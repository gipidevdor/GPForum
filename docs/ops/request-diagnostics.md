# Request diagnostics

Application logs are newline-delimited JSON at the existing `GPFORUM_LOG_PATH`
destination, or stderr when no path is set. The shipped daemonized services
set a file destination because Hypnotoad redirects stderr to `/dev/null`.
Changing the formatter does not redirect those files into journald.

Each record has `timestamp` (Unix seconds), `pid`, `level`, `message`,
`request_id`, `user_hash` and `duration_ms`. Request ids match the validated
`X-Request-ID` response header. The user field is a keyed pseudonym, not an
email, username, IP or session token; guests have null. It changes when the
primary session signing secret changes. Background records have null request
fields. Pseudonyms still allow correlation: apply the same retention/access
rules as other operational logs.

Request completion records use `event: "http.request"` and add route name,
HTTP status and `db_duration_ms`. Query strings and request bodies are not
added. Existing application messages and warning text can still contain
diagnostics supplied by their callers.

```sh
jq -c 'select(.request_id == "REQUEST_ID")' /var/log/gpforum/gpforum.log
jq -c 'select(.event == "perl.warning")' /var/log/gpforum/gpforum.log
```

If a foreground deployment captures application stderr in journald instead:

```sh
journalctl -u gpforum -o json |
  jq -c '.MESSAGE | fromjson? | select(.request_id == "REQUEST_ID")'
```

Synchronous production request warnings become `perl.warning` records with a
bounded warning string and up to twenty stack locations. Call arguments are
excluded. This handler does no SQL; warnings during database failure still
reach the operational log. Jobs and delayed callbacks retain their warning
handlers. These records are not admin moderation reports or chained database
audit records.

Responses include `Server-Timing: app;desc="GPForum";dur=...` and
`db;desc="PostgreSQL";dur=...`. The values are milliseconds, visible in browser
network tools. `db` sums observed query execution/fetch intervals, including
connection setup statements when observed; it excludes time spent rendering,
network transfer. The function call layer closes timing on errors too;
legacy DBIx paths without a query-end callback cannot supply a complete
duration for failed calls. Nested SQL
execution is naturally included in the enclosing call's elapsed time. An
empty cache hit legitimately reports zero. The application duration ends at
response finalization, not after a download or WebSocket closes.

See [schema review](../../etc/schema/README.md),
[reload/restart](reload-and-restart.md) and
[ADR 0153](../adr/0153-postgresql-and-operational-boundaries-are-tested.md).
