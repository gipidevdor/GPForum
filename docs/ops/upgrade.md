# Upgrade

`gpforum upgrade` prints the three commands that upgrade the forum, written
for the host it runs on, and runs none of them. On a Debian or Ubuntu host
installed as [DEPLOYMENT.md](../DEPLOYMENT.md#install-on-debian-or-ubuntu)
shows, they are:

```sh
sudo git -C /opt/gpforum pull && sudo make -C /opt/gpforum install-deps-production
sudo -u gpforum gpforum migrate && sudo systemctl restart gpforum gpforum-outbox
sudo -u gpforum gpforum doctor --upgrade
```

Take a backup before the first one, so there is something to come back to.
The first time, its directory is made too, by root for `gpforum`, since
`/var/backups` is root's (and a fresh Debian host has no
`/var/backups/gpforum`):
`sudo install -d -o gpforum -m 700 /var/backups/gpforum && sudo -u gpforum gpforum backup --to /var/backups/gpforum`.
Once the directory is there, `gpforum upgrade` prints the backup alone.

1. **The code and its dependencies.** `git pull` brings the release, and
   `make install-deps-production` installs what its `cpanfile.snapshot`
   pins for the Perl the host runs. Run it after an upgrade of the system
   Perl too (a new Debian release): modules built for the Perl before do
   not load.
2. **The schema, then the services.** `gpforum migrate` applies the new
   migrations, keeps the monthly partitions ahead and syncs the query
   budgets. When there is nothing to apply it prints `Schema is current`
   and names no restart. The restart is on this line all the same: the web
   service and the outbox worker read the code only when they start, and
   the code changed. `systemctl reload` is refused on purpose
   ([reload-and-restart.md](reload-and-restart.md)).
3. **The check.** [`gpforum doctor --upgrade`](doctor.md#after-an-upgrade)
   says what the upgrade left behind, with the command for each:
   - a setting the new release needs, or one it retired;
   - a module missing, too old, or built for another Perl;
   - a migration still to apply;
   - a unit file that differs from the release's;
   - a service still running the code it was started with.

   It ends with `Nothing to fix.` when the upgrade is complete.

A unit file that differs is shown with the `diff` that says how, and with
the `gpforum service print`, `daemon-reload` and restart that install the
release's, written for this host. A copy you changed on purpose differs
too. Keep the change in the environment file instead, where every setting
belongs, and print the unit again.

The [CHANGELOG](../../CHANGELOG.md) lists each release's changes. Its
"Operator action required" section says what a release asks beyond these
three commands.

On FreeBSD and macOS, `gpforum upgrade` ends the second line with that
host's restart:

- FreeBSD: `sudo service gpforum restart && sudo service gpforum_outbox
  restart`.
- macOS: `sudo launchctl kickstart -k system/com.gpforum.app` and
  `system/com.gpforum.outbox`.

In a development checkout it prints `cd` to the checkout, `git pull` and
`make install-deps-postgres`, then `gpforum migrate`, then `gpforum doctor
--upgrade`, and says to restart the forum you run with `gpforum start
--foreground`. Run it with `gpforum --env-file FILE upgrade`, and each
`gpforum` command it prints reads that file too.

To roll back, check out the release before, install its dependencies and
restart. A migration is not undone. Restore the backup taken before the
first command ([backup-and-restore.md](backup-and-restore.md#restoring-a-backup))
if the release before cannot run on the new schema. A migration that breaks
the forum is fixed forward, by a new migration in the next release: an
applied one is never edited, and the runner refuses a file whose checksum
differs from the one the database recorded.

## Discussion search and navigation

Migration 1030 adds the thread-scoped search implementation and its typed API
entry point. It changes no table data and keeps the previous search signatures
available. Numbered navigation and deep post links use the existing readable-post
queries; the browser suggestions use the existing autocomplete endpoint.

For an installation using the restricted runtime role, apply the schema with
the operator environment and reprovision that role before starting the updated
services. Follow the service drain/restart procedure in the
[role guide](sql-api-role.md); do not give the web service operator credentials.
Using the separate operator file from that guide:

```sh
bin/gpforum --env-file /etc/gpforum/admin.env migrate --plan
bin/gpforum --env-file /etc/gpforum/admin.env migrate
bin/gpforum --env-file /etc/gpforum/admin.env api-role --role gpforum_runtime --plan
bin/gpforum --env-file /etc/gpforum/admin.env api-role --role gpforum_runtime --apply
```

After starting the updated services with their runtime environment, verify a
thread-scoped search and a deep link with a member account. An inaccessible
thread or post must still return not found. Check the schema again with
`migrate --check`; repeating the migration must leave no pending work.

## Suspension timestamp and Unicode-password fixes

For a database already on the 1.0 baseline, the normal upgrade above applies
migration 1024 and restarts the application and outbox. It adds API function
versions; it rewrites no table and changes no PostgreSQL setting. The
preceding function boundaries stay installed for workers from the previous
release. A PostgreSQL restart or database rebuild is unnecessary. If the
service uses the restricted API runtime role, stop the old workers and
reprovision the current function grants before starting the new ones, using
the operator credentials as shown in the [role guide](sql-api-role.md).
`gpforum migrate` alone does not grant new signatures to that role.

New password hashes remain standard Argon2id PHC strings. Their salt has a
public UTF-8 encoding marker followed by 16 random bytes; existing 16-byte
salts keep their original Latin-1 interpretation. Existing passwords do not
need resetting. A candidate is checked using one encoding only, so two
different character sequences whose bytes happen to overlap cannot both
satisfy the same hash. Rolling back to code before this fix will not verify
new non-ASCII passwords correctly; deploy the hashing and verification
change together on every worker, and retain a backup for a full rollback.

The [ASVS record](../security/asvs-5.0.md) still lists automatic expiration
of a suspended member status and serialization of concurrent suspension
writes as open gaps. Correct timestamp comparisons do not close those
separate lifecycle issues.

## From a forum built before 1.0

GPForum 1.0 starts its schema from a baseline (ADR 0150) and does not upgrade
a database the 0.x migrations (001 to 135) built: `gpforum migrate` and
`gpforum migrate --check` stop on one with

```text
this database was built by GPForum before 1.0 (migrations 001 to 135), which 1.0 does not upgrade: create an empty database and migrate it, then move the data over if you need it (docs/ops/upgrade.md)
```

and change nothing. The tables and columns 1.0 keeps are the ones 0.x had,
under the same names, so the data moves with one dump and one restore:

1. Take a backup of the old database (`gpforum backup`).
2. Make an empty database, point the forum's `GPFORUM_DATABASE_DSN` at it and
   run `gpforum migrate`.
3. Dump the old database's rows, without the migration ledger, the partition
   registry, the query budgets (`gpforum migrate` wrote the new database's
   own) and the tables 1.0 dropped, and restore them in one transaction:

   ```sh
   pg_dump --data-only --load-via-partition-root --schema=public \
     --exclude-table=public.schema_versions --exclude-table=public.migration_safety \
     --exclude-table=public.partition_registry --exclude-table=public.endpoint_query_budgets \
     --exclude-table=public.admin_role_audit_projection --exclude-table=public.aggregate_stream_versions \
     --exclude-table=public.audit_checkpoints --exclude-table=public.category_stats \
     --exclude-table=public.database_role_contracts --exclude-table=public.effective_permissions \
     --exclude-table=public.idempotency_keys --exclude-table=public.permission_grants \
     --exclude-table=public.permission_revocations --exclude-table=public.posts_archive \
     --exclude-table=public.role_binding_events --exclude-table=public.thread_counter_shards \
     --exclude-table=public.view_count_deltas --exclude-table=public.visibility_events \
     --dbname=gpforum_0x --file=gpforum-0x-data.sql
   psql --single-transaction -v ON_ERROR_STOP=1 --dbname=gpforum --file=gpforum-0x-data.sql
   ```

4. Run `gpforum doctor`.

`pg_dump` warns that `posts` and `post_bodies` reference each other: the
restore goes through anyway, because the reference from `posts` is checked at
commit and the restore is one transaction. `--load-via-partition-root` sends
each row of the monthly logs through its parent, so it lands in the new
database's partition for its month, or in DEFAULT. This was done on a 0.x
database seeded with the `medium` profile: every row of every table arrived,
the same.


## Admission and community workflows (migrations 1025–1029)

[ADR 0151](../adr/0151-admission-polls-category-follows-and-thread-organization.md)
adds optional staff-controlled admission, polls, category follow forms and
bounded post organization. Apply the migrations through the existing migration
command, deploy updated web/outbox workers and refresh restricted runtime-role
EXECUTE grants from the current catalogue. Keep admission open during mixed
worker versions; older registration/user-update boundaries are retained for
compatibility and do not enforce the new policy. Enable invite-only or approval
mode from the admin registration console only after old workers have stopped.

The default policy preserves open registration and existing member status.
Expired invitation rows join the existing bounded identity-token retention job.
No PostgreSQL server configuration or restart is required. Follow the normal
forward-fix/restore procedure for deployment rollback; do not delete installed
migration ledger entries or run inverse schema DDL. Transfer undo is a checked
product command and can refuse when later content placement has changed.
