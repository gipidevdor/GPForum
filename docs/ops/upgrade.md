# Upgrade

## Fresh-database baseline (2026-11-01)

This checkout starts at migrations **2000–2025**. Create an empty database,
point `GPFORUM_DATABASE_DSN` at it, then run `gpforum migrate` and
`gpforum migrate --check`. Provision the restricted runtime role from the
current catalogue before starting the web/outbox services
([SQL API role](sql-api-role.md)).

Databases recording earlier chains, including 1000–1065, are not upgraded.
The runner stops before applying anything and says:

```text
this database uses an earlier GPForum schema baseline (migrations 1000 to 1065): create an empty database and migrate it (docs/ops/upgrade.md)
```

Use a new database name rather than deleting an existing database. There is no
data import in this reset. The [migration map](../../migrations/README.md) and
[ADR 0162](../adr/0162-a-fresh-database-baseline.md) describe the new baseline.
The ordinary upgrade procedure below applies to later releases on this baseline.

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
