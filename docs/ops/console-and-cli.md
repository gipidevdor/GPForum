# Console and command line

Every verb of `gpforum`, the front door (ADR 0120), and where an
administrator finds the same thing in the admin console, or why there is
none. Quality program item 6.5 asked for the two to stop drifting apart;
`t/214-console-cli-parity.t` keeps this page honest: it fails when a verb is
missing from the table below, when the table names a verb that no longer
exists, or when it names a console route that `lib/GPForum/Bootstrap/Routes.pm`
does not register.

`bin/gpforum` is the only command: `gpforum migrate`, `gpforum admin create`,
`gpforum partitions`. It reads the service's environment file, re-runs itself
under Carton when `local/` is not on `@INC`, and runs the verb's command;
Hypnotoad loads the same file as the application that serves the console.
`gpforum` alone lists the verbs by what the operator is doing, and `gpforum
help --all` adds the benchmarks, seeds, drills and evidence commands, with
Mojolicious's and Minion's own (`daemon`, `routes`, `minion`). `--dry-run`
shows and does not do on `migrate`, `admin` and `secret`.

A verb without a console route is not a gap by default. Some run before
there is a console (`gpforum setup`, `gpforum admin create`), at deploy
(`gpforum migrate`) or on a timer; others are benchmarks, seeds, drills and
evidence tools that belong to the operator's or developer's shell, not to a
live forum's web process.

## Commands

The **Console** column names the route, as `Routes.pm` names it, that covers
the verb, or says `none`.

| Verb | Console | Notes |
| --- | --- | --- |
| `gpforum setup` | none | Makes the account, the environment file, the database and the schema before the forum runs; there is no console yet. |
| `gpforum migrate` | none | The migrations, the partition window and the query budgets. Runs at deploy, before the new code serves. A web request must not change the schema of the database it is reading. |
| `gpforum postgres-performance` | none | Inspect, plan, apply and verify server tuning with a separate operator connection; cluster-wide changes require explicit authority ([runbook](postgres-performance.md)). |
| `gpforum api-role` | none | Plans the application login's access to the catalogued PostgreSQL functions; `--apply` provisions it after migrations. Uses the separate operator connection and environment file ([application role provisioning](sql-api-role.md)); web and worker services use the restricted login. |
| `gpforum admin` | none | `gpforum admin create` makes the forum's owner, active and verified, before anyone can sign in to the console; `gpforum admin grant EMAIL` makes a member one. Later administrators are bound on `/admin/users/:user_id/roles`. |
| `gpforum secret` | none | It writes the environment file, which the console only reads (`/admin/settings`). |
| `gpforum service` | none | Prints the service files for this host; installing them needs root on the host, not a web request. |
| `gpforum start` | none | Starts the service the console runs in; `--foreground` runs Mojolicious's `daemon`, for development. |
| `gpforum outbox` | none | The worker processes dispatch the outbox continuously; a web request is not a worker. `/admin/jobs` shows the outbox and its dead letters. |
| `gpforum scheduled-jobs` | none | Run by its timer (`gpforum-scheduled-jobs.service`). Running a pass from a web request would race the timer. |
| `gpforum doctor` | none | Checks the host, from the settings to the public address. `/admin/status` shows the running service's own readiness. |
| `gpforum status` | `admin_status` | The running service's readiness report, which `/admin/status` shows. |
| `gpforum mail-check` | `admin_settings` `admin_mail_test` | **Send test message** on `/admin/settings` sends one message through the configured transport to the signed-in administrator's own address and audits the outcome (`admin.mail_test_sent`). Sending to another address (`--send --to`) and the dry-run transport probes stay on the shell: a console that mailed any address would be an open relay. |
| `gpforum antivirus-check` | `admin_settings` `admin_antivirus_check` | **Run antivirus check** on `/admin/settings` runs the same check (`Service::Operations::AntivirusCheck`) with the service's scanner and audits the report (`admin.antivirus_checked`). With `GPFORUM_ANTIVIRUS=command` only the shell can run it: clamscan loads its signatures for every file and three scans outlast a web request. |
| `gpforum platform-check` | none | Checks the host's Perl, modules and database prerequisites. Developer and operator tooling. |
| `gpforum os-preflight` | none | Inspects the host (limits, file descriptors, CPU) before the service starts. `/admin/status` shows the running service's own mode and health. |
| `gpforum search-rebuild` | `admin_jobs` `admin_search_rebuild` | **Rebuild search index** on `/admin/jobs` rebuilds through the outbox and audits the request (`admin.search_rebuild_requested`). |
| `gpforum dead-letters` | `admin_jobs` `admin_dead_letter_replay` | The **Replay** button per dead letter on `/admin/jobs`, over the same service (`Service::Outbox::DeadLetterReplay`), audited with the actor. |
| `gpforum partitions` | none | DDL on the partitioned tables, run by its daily timer or crontab and, through its lifecycle, by `gpforum migrate` (ADR 0113). It needs locks and time a web request does not have. |
| `gpforum budgets` | `admin_status` | `/admin/status` shows the query budgets and their drift (`--print`, `--check`). `--sync` makes the `endpoint_query_budgets` table match the catalog in the code -- it inserts, updates, and deletes the rows of endpoints the catalog dropped -- and stays on the shell. |
| `gpforum mail-in` | none | Reads one authenticated MIME reply from the local MTA; [protocol runbook](community-protocols.md). |
| `gpforum gemini` | none | Runs the separate public Gemini TLS listener; [protocol runbook](community-protocols.md). |
| `gpforum sign-posts` | none | Attests existing unsigned revisions in bounded batches; new posts and edits are signed automatically. |
| `gpforum anonymize` | none | Creates a scrubbed copy in a new staging database; requires administrative PostgreSQL credentials. |
| `gpforum backup` | none | Dumps the database and the uploads; it needs the database owner and the host's disk, not a web request. |
| `gpforum restore` | none | Checks that a backup restores, into a database of its own. |
| `gpforum upgrade` | none | Prints the commands that upgrade this forum, which run on the host. |
| `gpforum benchmark` | none | HTTP benchmark against a running instance. `/admin/status` shows the benchmark commands and whether a baseline exists; running load from inside the instance under test would measure itself. |
| `gpforum hypnotoad-benchmark` | none | Benchmark: starts the Hypnotoad it measures. Developer and operator tooling. |
| `gpforum hypnotoad-scaling` | none | Benchmark of worker counts; starts its own servers. Developer and operator tooling. |
| `gpforum performance-seed` | none | Seeds performance data. Never on a live forum. |
| `gpforum stress-load` | none | Load generator against a running instance. Operator's shell. |
| `gpforum query-plan-evidence` | none | Evidence tooling: EXPLAIN on a seeded database. Developer tooling. |
| `gpforum staging-drill` | none | Staging drill, for release evidence. Operator's shell. |
| `gpforum staging-drill-attachments` | none | Staging drill for attachments, for release evidence. Operator's shell. |
| `gpforum staging-host-verify` | none | Verifies a staging host, for release evidence. Operator's shell. |
| `gpforum evidence-meta` | none | Evidence tooling: stamps evidence archives. Operator's shell. |
| `gpforum evidence-validate` | none | Evidence tooling: validates evidence archives. Operator's shell. |
| `gpforum dead-letter-check` | none | A drill of the dead-letter runbook against an in-memory outbox, for staging evidence. The live dead letters are listed, and replayed, on `/admin/jobs`. |
| `gpforum mail-lifecycle-check` | none | A drill of the three identity mails under the test transport, for evidence. Developer and operator tooling. |

## Machine-readable output

Every command that reports state takes `--json` and prints one JSON object on
one line of standard output instead of its lines -- a command that loops
prints one per pass, so its output reads as JSON Lines. Every object has
`status`, and most a `command` (its name, such as `gpforum-migrate`) and a
`mode`. The exit code
is the same as without `--json`: 0 ok, 1 a problem, 2 misuse, 78 settings the
command cannot use (EX_CONFIG; every problem is reported on standard error,
its last line naming the environment file read). Misuse says what was wrong
and prints the usage on standard error, and nothing on standard output. When the work
itself fails -- the database cannot be reached -- the reason goes to standard
error, the exit code is 1, and the object still comes, with `status` `fail`,
the reason in `error` and the lists empty. Work already done shows where the
command knows it: `dead-letters --id` keeps the ids it replayed before the
failure, and a looping `outbox` has printed a line for each batch
before it. `migrate` leaves `applied` out when a migration failed:
each one commits as it goes, so those before the failure are in the schema,
and `--check` lists what is left (`applied` is `[]` only when the database
was never reached). `scheduled-jobs` lists no job, though the jobs that ran
before the failure did their work.

No object carries a secret. What is printed is what the lines print, except
that `platform-check` adds each check's report: what `os-preflight --json`
prints, and the operational profile's floors. An inline password in a
failure's reason -- a DSN's `password=`, which DBI's connect error repeats --
is replaced by `[redacted]`, on standard error too.
Each object is flushed as it is printed, so a reader on a pipe gets every
batch of a looping command when it ends.

For the commands from `migrate` to `search-rebuild` below, `status` is `ok`
or `fail` as the exit code says (`platform-check` adds `degraded`), and keys
are sorted, so the same state prints the same bytes. `os-preflight`,
`antivirus-check` and the evidence commands keep their own vocabulary (`ok`
or `pass`, `degraded`, `disabled`, `fail`); the evidence commands print JSON
by default and their lines with `--human`, except `gpforum mail-check`, which,
as a check in the front door's help, prints its lines unless given `--json`.

| Command and mode | Object |
| --- | --- |
| `gpforum migrate --plan --json` | `migrations`: every file in `migrations/`, each `{version, description, file}`; `pending`: those the database has not recorded. Connects to the database. |
| `gpforum migrate --check --json` | `pending`: the migrations the database has not recorded, as above; `status` `fail` when any are, or (`error`) when an applied file changed since. |
| `gpforum migrate --json` | `applied`: each `{version, description, checksum, execution_time_ms}`; left out when a migration failed (above). `partitions`: the window step after the migrations, shaped as `gpforum partitions --json` less `command` and `mode`; left out with `--no-partitions`. `budgets`: the query budget sync after them, `{synced, written, removed}`. A conflict or error in either makes `status` `fail` with `applied` still listed. |
| `gpforum admin create --json`, `gpforum admin grant --json` | `mode` (`create` or `grant`), `role`, `user` (`id`, `username`, `email_normalized`, `status`), `counts` (what the run created) and `permissions`; with `--dry-run`, `dry_run` 1 and `user`. A refusal: `status` `fail` and `error`, the sentence printed on standard error. |
| `gpforum api-role --role ROLE --json` | `mode` (`plan` by default) and `role`; a plan lists SQL in `statements`, while `--apply` reports the number of granted signatures in `functions`. |
| `gpforum secret rotate --json` | `kind` (`session` or `metrics`), `mode` (`rotate` or `finish`), `file`, `changed` (the variables written), `dry_run`. Never a secret. |
| `gpforum partitions --json` | `lookahead_months`, `skipped` (1 when another run held the maintenance lock) and the lists `created`, `existing`, `planned`, `conflicts`, `errors` (`partition-maintenance.md`). |
| `gpforum platform-check --json` | `mode`, `strict`, `checks`: each `{name, status, report}`, `report` being the check's own (`os-preflight --json` for `os_preflight`). `status` is the worst check's, `fail` when the exit code is 1. |
| `gpforum budgets --print --json` | `endpoints`: the catalog, keyed by endpoint name. |
| `gpforum budgets --check --json` | `missing`, `extra`, `mismatched`: endpoint names. |
| `gpforum budgets --sync --json` | `synced`: the number the line prints, every endpoint in the catalog, whether its row was written or already matched; `removed`: the endpoints whose rows were deleted because the catalog no longer has them. |
| `gpforum scheduled-jobs --json` | `jobs`: each `{name, count}` and, when there are any, `ok`, `skipped`, `error`, `errors` (`scheduled-jobs.md`). |
| `gpforum outbox --json` | One object per batch: `selected`, `dispatched`, `failed`, `dead_lettered` (`dead-letters.md`), `acknowledged` (written `done`) and `lost` (claims another worker took before this one wrote the outcome; `OUTBOX_LIFECYCLE.md`, Claims and Leases). |
| `gpforum dead-letters --list --json` | `dead_letters`, as `/admin/jobs` lists them (`dead-letters.md`). With `--id` instead, `outcomes`: each `{dead_letter_id, status}`, with `outbox_id` when replayed or `error` when refused. |
| `gpforum search-rebuild --status --json` | `lag_status` (`current` or `behind`), `pending`, `lag_seconds`, `oldest_pending_at` (UTC, or `null`). `status` is the command's, `ok`. |
| `gpforum search-rebuild --json` | `entity_type`, `indexed`, `unchanged`, `pruned`. |
| `gpforum os-preflight --json` | The preflight report: `checks`, each `{name, status}`, and the host it read. |
| `gpforum antivirus-check --json` | The antivirus evidence (`antivirus.md`). |
| `gpforum mail-check --json` | The mail evidence (`mail-check.md`). |
| `gpforum dead-letter-check`, `gpforum mail-lifecycle-check`, `gpforum evidence-validate`, `gpforum staging-*`, `gpforum stress-load` | JSON evidence by default (their runbooks). |

A field may be added; one is not renamed or removed without a CHANGELOG
entry. For example, to fail a deploy step when the schema is behind:

```sh
bin/gpforum migrate --check --json | jq -e '.status == "ok"'
```

## Only in the console

Some work has no command, because it is an administrator's decision rather
than an operator's procedure: roles, permissions and their bindings
(`/admin/roles`, `/admin/users`), categories (`/admin/categories`),
watched words, the link rule and the first-post review rule
(`/admin/automod`), the review queue (`/moderation/review`), the audit viewer
(`/admin/audit`), moderation, privacy review, the public page cache purge
(`/admin/jobs`) and the effective configuration (`/admin/settings`).

## Settings are not edited here

`/admin/settings` shows every variable `GPForum::Config` reads, its effective
value and whether it came from the environment or is the default, with every
secret shown only as set or not set. It does not change them: configuration
lives in the service's environment, `/etc/gpforum/gpforum.env`
(`/usr/local/etc/gpforum/gpforum.env` on FreeBSD), and takes effect on
`systemctl restart gpforum` (see `reload-and-restart.md`).

`gpforum anonymize --copy-to gpforum_anon_NAME` creates a scrubbed staging
database copy through administrative PostgreSQL credentials. It never
overwrites a database. See ADR 0155 for what it retains and removes.

`gpforum doctor --calibrate-password` measures this host and prints Argon2id
memory and iteration settings for the 250 ms budget without changing them.

`gpforum help VERB` renders the command module’s POD with `Pod::Usage`; `make man` generates matching man pages under `artifacts/man` with `Pod::Man` (the `pod2man` renderer). Options come from executable usage, so there is no separate manual option list.
