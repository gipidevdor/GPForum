# ADR 0155: Host readiness, signed mail and reproducible data

Date: 2026-10-23. Status: accepted.

The systemd web unit runs Hypnotoad in the foreground with `Type=notify`,
`NotifyAccess=main` and a 30-second watchdog. Only the manager notifies.
Hypnotoad's manager does not run Mojo::IOLoop: a recurring timer would only
run in workers and could mask a dead manager. Its public `wait` event instead
probes HTTP every ten seconds. READY requires both a worker heartbeat and a
successful `/health/ready` request. WATCHDOG then requires a successful
`/health/live` probe, so a downstream outage does not itself restart a
responsive server. Restart remains the supported deployment operation. Actual
systemd restart behavior must also be exercised on a Linux host.

Optional application DKIM signing occurs after complete MIME construction and
before the transport sends. RSA-SHA256 covers the one-click unsubscribe
headers as well as standard headers. A configured signing failure aborts
delivery so the outbox retries; it never silently sends unsigned. The private
key must be a regular 0600 file. Doctor signs a probe and verifies it against
the selector's DNS key without sending mail. Hosts may retain MTA signing by
leaving the application key path empty.

`gpforum doctor --calibrate-password` measures warmed Argon2id hashes with a
monotonic clock, reports the worst of three measurements per candidate, and
prints settings for hashes below 250 ms. It never writes configuration or
weakens the 19 MiB / two-iteration floor. Defaults remain 32 MiB / three
iterations. Existing PHC hashes carry their original costs and still verify.
Latency under production concurrency requires separate load testing.

`gpforum anonymize --copy-to gpforum_anon_NAME` dumps the configured database
through administrative credentials, creates a new database and restores into
it, then scrubs only that copy. It refuses existing targets. UUIDs and email
addresses receive a fresh, unrecorded salt; display names come from a fixed
list. Forum body lengths and core relational counts survive, while body text,
titles, usernames, slugs and biographies are replaced. Credentials, sessions,
tokens, queues, logs, private messages and attachment metadata are emptied;
attachment files are never copied. Unknown sensitive columns in retained
tables abort the operation. Foreign keys are revalidated; failure drops the
incomplete copy. The dump is removed immediately after restore and the final
copy is vacuumed. The target remains accessible only to its owner until its
staging role is provisioned. Use a separate empty attachment root and staging
mail settings. Shape and timestamps can still disclose information about
activity: this is a scrubbed benchmark/staging dataset, not a guarantee of
legal anonymization or a public export.

`make integration` runs eight processes by default. Each test process starts
its own socket-only Test::PostgreSQL cluster; forked race workers cannot stop
their parent's cluster. Explicit DSNs still select externally managed servers.
Cluster startup failures fail tests instead of skipping them. PostgreSQL's
programs and the postgres dependency feature must be installed. The existing
prove harness provides parallelism; changing to yath is unnecessary to obtain
isolation and is not part of this decision. Specialized tests still require
their documented replication or extension settings.

Discovery uses a sitemap index and root-level numbered 1000-resource pages,
filtered by current public visibility at every level. JSON-LD describes the original post
and public replies present on the first page, including full visible text;
later pages do not present their first reply as a new original. Private and
moderated content is excluded and script delimiters are escaped.

`mojo generate gpforum-service Forum::Name` creates a service, a new SQL API
migration, a catalogue entry and an integration test. Its migration keeps the
invoker implementation and a typed v2 forwarding boundary, as ADR 0127 requires.
The initial API accesses
no application data and returns an empty document. Add authorization and
domain behavior before using it. Files are never overwritten.
