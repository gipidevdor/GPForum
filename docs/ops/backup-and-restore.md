# Backup and Restore

A forum is two things to keep: its PostgreSQL database and its uploads. ADR
0050 asks for point-in-time recovery of the first; this page has the nightly
backup of both, the check that a backup can be restored, and the archive
that recovers the database to any instant.

| | `gpforum backup` | Point-in-time recovery |
| --- | --- | --- |
| Recovers | the database and the uploads | the database cluster |
| Granularity | the moment of the backup | any instant covered by the archive |
| Recoverable window | a successfully completed backup | the verified base backup and the continuous WAL archive |
| Checked by | `gpforum restore --check` | `script/pitr-drill` |
| Good for | a copy off the host, a bad deploy, a copy for staging | deletion, corruption, disk loss |

A nightly backup alone means a bad afternoon costs a day of posts; PITR is
what the ADR asks for. Run both: the backup is the copy you can carry off
the host and check in one command.

## The nightly backup

```console
$ sudo install -d -o gpforum -m 700 /var/backups/gpforum
$ sudo -u gpforum gpforum backup --to /var/backups/gpforum
✓ database gpforum: 4.2 MB, schema 051, PostgreSQL 18.6
✓ attachments: 312 files, 48.1 MB, from /opt/gpforum/var/attachments
✓ Backed up into /var/backups/gpforum/gpforum-20261009T031500Z
Next: check that it can be restored, with sudo -u gpforum gpforum restore --check /var/backups/gpforum/gpforum-20261009T031500Z
```

Run under `sudo -u`, the check it offers runs as the same account, which
alone can read the backup. Each run makes a new directory, named for the time in UTC and readable by
`gpforum` alone, holding:

| File | What it is |
| --- | --- |
| `database.dump` | the database `GPFORUM_DATABASE_DSN` names, as `pg_dump --format=custom` writes it |
| `attachments.tar` | the attachment root (`GPFORUM_ATTACHMENT_ROOT`), relative to it |
| `manifest.json` | when it was taken; the latest migration applied, PostgreSQL's and pg_dump's versions; what the attachment root held; each file's size and SHA-256 |

The manifest is written last, and a backup that fails half-way is removed:
a directory with a manifest is a whole backup. Run it as `gpforum`, who can
read the settings and the uploads. It reads the settings as every `gpforum`
command does, from the environment file; the password reaches pg_dump only
through its environment, and is written nowhere.

What it refuses, it says, with what to do instead: a directory inside the
code directory (an upgrade replaces it) or inside the attachment root (the
backup would copy itself); a directory it cannot make, with the `sudo
install -d` that makes it; a host without `pg_dump`. pg_dump refuses a
server newer than itself: install the client of the server's major
version, or name it with `GPFORUM_PG_DUMP`.

**What it does not hold: the settings.** The environment file holds the
secrets. Keep a copy of `/etc/gpforum/gpforum.env` where you keep secrets,
not beside the backups.

**Every night**, as `gpforum`'s crontab (`sudo crontab -u gpforum -e`):

```cron
15 3 * * * /opt/gpforum/bin/gpforum backup --to /var/backups/gpforum > /dev/null
30 3 * * * find /var/backups/gpforum -maxdepth 1 -name 'gpforum-*' -mtime +14 -exec rm -r {} +
```

Success prints to standard output and a failure to standard error, so cron
mails only a failure. The second line keeps two weeks. A backup on the
forum's own disk is lost with it: copy the directory off the host (`rsync
-a /var/backups/gpforum/ backup-host:gpforum/`).

The uploads are copied after the dump, as tar finds them: an upload made
meanwhile is a file in the archive nothing refers to; an attachment erased
meanwhile is referred to by the dump and missing from the archive. Run it
with attachment writes and deletion jobs paused for the entire database dump
and attachment copy. A quiet forum reduces the risk but does not establish a
consistent snapshot. Keep those writes paused until the manifest is complete,
then resume them; record the pause interval with the backup evidence. An
operator-managed snapshot of both stores is another option when its consistency
has been tested. This command does not create such a snapshot.

## Checking a backup

```console
$ sudo -u gpforum gpforum restore --check /var/backups/gpforum/gpforum-20261009T031500Z
✓ manifest: gpforum, taken 2026-10-09 03:15 UTC, schema 051
✓ database.dump: 4.2 MB, as the backup wrote it; pg_restore reads its 578 entries
✓ attachments.tar: 48.3 MB, as the backup wrote it; 312 files

The backup can be restored; nothing was restored.
Next: to restore it, follow the steps in docs/ops/backup-and-restore.md
```

It reads the manifest; compares each file's size and SHA-256 with it; has
`pg_restore --list` read the dump's table of contents and `tar` the archive,
and counts the archive's files against the manifest. It restores nothing,
needs no database, and runs on any host with `pg_restore` -- the one you
copied the backups to, too -- as an account that can read the backup
(`gpforum`, who made it). Run as an account that cannot read it, it says
so and gives the check as the backup's owner, rather than taking the
backup for lost. A file that changed, was cut short, is gone or is left
out of the manifest is said by name, and the command exits 1:

```console
✗ database.dump: its SHA-256 is not the one the backup wrote: it changed after the backup

This backup cannot be restored as it is.
Next: keep it as it is, and take another with gpforum backup
```

Given the directory of the backups rather than one of them, it offers the
newest. `--json` prints one object with a `status` and each finding, for a
monitor. Integrity and readable archive contents are necessary checks; they
do not prove that a server can restore the backup or that attachment metadata
and files describe the same instant. Rehearse the actual restore with
`gpforum staging-drill` and the attachment filesystem drill, and verify
metadata-to-file references on an isolated copy before a production cutover.

## Restoring a backup

A restore replaces the forum's database and uploads, so it is done by hand.
On Debian, with database `gpforum` on this host, replace `SCHEMA_OWNER` below
with the already provisioned schema-owner or migration operator role. Use the
ordinary owner login for restore, separately from the restricted runtime login;
the local `postgres` operator performs the database rename and creation.

1. **Check it**: `sudo -u gpforum gpforum restore --check DIR`. Restore
   nothing that fails.
2. **Stop the forum**: `sudo systemctl stop gpforum gpforum-outbox`.
3. **Put the database back.** Keep the one you are replacing, renamed, until
   the restore is proven:

   ```sh
   sudo -u postgres psql -c 'ALTER DATABASE gpforum RENAME TO gpforum_before_restore'
   sudo -u postgres createdb --owner SCHEMA_OWNER gpforum
   sudo -u gpforum pg_restore --exit-on-error --no-owner --no-acl --host 127.0.0.1 --username SCHEMA_OWNER \
     --dbname gpforum DIR/database.dump
   ```

   `pg_restore` uses libpq credentials, such as a private `PGPASSFILE` or the
   invoking account's mode-0600 `~/.pgpass`; `PGPASSWORD` is another supported
   environment input. It does not read `GPFORUM_DATABASE_PASSWORD` directly.
   Never put a password on the command line. `--no-acl` omits restored grants:
   provision the restricted runtime role and its required ACLs separately before
   starting the forum. On macOS run `psql` and `createdb` as the account that
   installed PostgreSQL instead of `postgres`.
4. **Put the uploads back**, the same way:

   ```sh
   sudo mv /opt/gpforum/var/attachments /opt/gpforum/var/attachments.before-restore
   sudo install -d -o gpforum -g gpforum -m 750 /opt/gpforum/var/attachments
   sudo -u gpforum tar -xf DIR/attachments.tar -C /opt/gpforum/var/attachments
   ```

5. **Bring the schema to the code**: `sudo -u gpforum gpforum migrate`. A
   backup older than the code has migrations to apply; one newer than the
   code needs the release it was taken with (its manifest says the schema).
6. **Start the forum** and check it: `sudo systemctl start gpforum
   gpforum-outbox`, then `sudo -u gpforum gpforum doctor`.

When it is right, drop `gpforum_before_restore` and remove
`attachments.before-restore`. `gpforum staging-drill` rehearses a dump and
restore on throwaway databases.

## Point-in-time recovery

The archive below recovers the database alone. **The uploads are not in
it**: `FilesystemStorage` writes them under the attachment root, which
neither WAL archiving nor `pg_basebackup` touches, and the database keeps
only their keys -- a recovery without them is a forum whose attachments
may answer 404. Choosing the nightly backup nearest the recovery target does
not establish consistency: an older copy can miss later uploads, while a
newer copy can omit files deleted after the target. Use a documented recovery
point with a jointly quiesced database/filesystem backup, or retain immutable
versions of attachment objects for the whole WAL recovery window. The current
filesystem backend does not implement object versioning. If only nightly
copies exist, constrain the recovery point to a verified consistent backup
and document the resulting loss of newer data.

`script/staging-drill-attachments` verifies filesystem copy/restore integrity
separately; it does not verify a common PITR instant or application attachment
references. Before resuming the forum, inspect attachment metadata and stored
objects on an isolated restore and resolve missing objects. Keep the original
database and attachment tree available for rollback.

### Recovery objectives

Record operator-approved RPO (acceptable data loss) and RTO (acceptable outage)
targets in the deployment's recovery policy, together with backup cadence,
archive monitoring, archive retention and attachment retention. These are
configurable objectives, not guarantees supplied by GPForum. For example, a
deployment can choose different minute targets after measuring its own size
and storage; this repository supplies no default production target.

The achieved database recovery point is bounded by the latest complete,
durable, recoverable archived WAL segment. A WAL switch returning successfully
does not mean archiving has completed, and a low-write system can retain an
unfinished segment for longer than a presumed seconds-level RPO. Monitor
archive failures and the recoverable time gap, verify the archive off-host,
and test whether the chosen archiving policy meets the target. RTO includes
provisioning, transfer, WAL replay, attachment recovery and application checks.
The drill below records recovery and total elapsed seconds separately; its
three-row fixture cannot establish production RPO or RTO.

### Configuring the archive

On the primary:

```
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /srv/gpforum/wal/%f && cp %p /srv/gpforum/wal/%f'
max_wal_senders = 3
```

`archive_command` must return non-zero when it does not archive, or PostgreSQL
believes the segment is safe and recycles it. The `test ! -f` guard refuses to
overwrite an existing segment rather than silently replacing it. Archive to
storage that does not share a failure domain with the data directory: an
archive on the same disk protects against deletion, not against losing the
disk.

Take a base backup after enabling archiving, and again often enough that
replaying WAL from the last one is a tolerable wait:

```sh
pg_basebackup -h HOST -U backup_operator -D /srv/gpforum/base/$(date -u +%Y%m%dT%H%M%SZ) -Fp -Xs
```

`backup_operator` is a placeholder for a dedicated, operator-provisioned login
with the replication privilege required by `pg_basebackup`. Its private libpq
authentication must be configured by the operator. The web runtime login must
have no replication privilege; ordinary migration credentials are not the
physical backup login. These instructions do not create a role or grant a
privilege automatically.

Verify every completed physical backup with the matching PostgreSQL major's
`pg_verifybackup BACKUP_DIRECTORY` before relying on it. A valid manifest proves
backup-file integrity, not continuous archive coverage or an application restore;
those require the recovery rehearsal. Protect backup and WAL directories as
private operator data, and keep credentials in the existing secret store.

### Restoring to an instant

Restore and verify on an isolated cluster before an operator approves any
production cutover. Never replace or start recovery in the production primary's
data directory. Preserve the original data directory and the immutable backup.

1. Allocate a new, private data directory on the recovery host and copy the
   verified base backup into it. Keep the source backup unchanged so another
   recovery attempt can begin from it.
2. Configure this restored copy with its own service identity, socket directory
   and unused port. Override retained primary listeners, archive destinations
   and deployment hooks before first start; use the original WAL archive only
   as a read-only recovery source. Keep application traffic away from the copy.
3. Append the recovery settings to the isolated copy:

   ```
   restore_command = 'cp /srv/gpforum/wal/%f %p'
   recovery_target_time = '2026-09-24 11:27:58+02'
   recovery_target_action = 'promote'
   ```

4. `touch recovery.signal` in that new data directory.
5. Start only the isolated server. It replays WAL to the target and promotes;
   verify the target, exact expected data and `pg_is_in_recovery() = false`.
6. Restore the attachment state associated with the verified recovery point,
   using the consistency policy above. Do not substitute an arbitrary nearest
   nightly copy for a common snapshot.
7. With the application command explicitly configured for the isolated database,
   run `gpforum migrate --check` (`--json` for a script). It should exit
   0 with `pending=0`: if it lists pending migrations, the restore predates a
   deploy and the application will not match the schema. (`--plan` lists the
   files in `migrations/` without asking the database, so it cannot tell.)

8. Verify attachment references, schema compatibility, runtime ACLs and application
   checks on the isolated copy. Plan a manual cutover and rollback with the
   deployment operator; stop application writes before switching database and
   attachment targets together. Preserve the original stores until verification
   is complete.

Choose the target *before* the damage, not after it. If you do not know when
the damage happened, restore to a candidate instant, look, and repeat — which
is why the original data directory and backup remain available.

### Rehearsing it

```bash
script/pitr-drill --json --timeout 180 > pitr-evidence.json
script/pitr-drill --validate pitr-evidence.json
```

The Perl drill builds its own temporary cluster and ignores application DSNs,
credentials and PostgreSQL client environment overrides. It uses a private
Unix socket, requires matching `initdb`, `postgres`, `pg_ctl`, `pg_basebackup`,
`pg_verifybackup` and `psql` binaries on `PATH`, and takes a base backup with a
fast checkpoint. It verifies the backup manifest, writes rows on either side
of a recovery target, waits for the required WAL segment to be archived, and
restores to the target. It checks promotion, the exact initial and retained
row bodies, exclusion of the later row, and the full row counts. Every command
and polling loop has a deadline. The default 180 seconds includes an eight
second cleanup reserve.

The versioned schema is
[`postgres-pitr-schema-v1.json`](postgres-pitr-schema-v1.json). JSON reports
the checkout commit and whether it has local changes (`source_dirty`, or null
when Git provenance cannot be checked), server/client versions, target, dataset,
executed phases,
manifest/archive/recovery checks, recovery seconds and total seconds. A missing
tool, failed verification, timeout or incomplete recovery returns nonzero and
`status=fail`, retaining completed phases without claiming success. Validation
checks schema and secret exclusion; a valid failure report is still a failed
drill. Generic evidence validation also accepts this report type.

`recovery_seconds` starts immediately before the recovered server is launched
and ends after promotion and exact-data checks. `duration_seconds` includes
setup, base backup, archive completion and cleanup as well. Neither includes
production provisioning, off-host transfer or attachment recovery.

`--port N`, `--dir PATH` and `--keep` remain available. The directory must be
new or empty and must not be a symlink. `--keep` preserves files and sanitized
bounded `.log` diagnostics for investigation, but always stops the owned server.
Without `--keep`, only the owned workspace is removed; an originally empty
directory is left empty.
An occupied or symlink workspace is refused with exit 1 and, with `--json`,
`reason=owned_workspace_refused`; existing files are preserved. Malformed
arguments use exit 2. The deprecated `GPFORUM_PITR_PORT` and `GPFORUM_PITR_DIR`
adapter remains until v0.3.0, warns with the replacement flag, and gives explicit
`--port`/`--dir` flags precedence.
TERM/INT and command timeouts converge on cleanup. SIGKILL or a
host crash cannot run cleanup: inspect the owned workspace before removing it.
Publish only the evidence JSON and `.log` files as CI artifacts, with finite
retention; keep base backups, data directories and WAL out of Git and artifacts.

The weekly/manual PostgreSQL recovery workflow exercises this bounded drill;
ordinary PR checks retain the existing logical restore tests. The historical
run is in
[`evidence/2026-10-01-pitr-drill/`](evidence/2026-10-01-pitr-drill/README.md)
(PostgreSQL 18.6, 108 s end to end, recorded before this hardening).

Row counts alone would not catch the failure worth catching, which is a restore
that silently lands on the wrong instant. Verified on PostgreSQL 18: three rows
before the incident, two recovered.

It fails loudly in the case operators actually hit — an incomplete archive,
where the base backup is fine but the WAL needed to roll forward was never
archived, so recovery cannot reach the target and refuses to promote:

```
pitr-drill status=fail reason=archive_not_completed
```

Rehearse after any change to `archive_command`, to the storage the archive
writes to, or to the PostgreSQL major version.

## What this does not give you

Availability. An archive plus base backups is a recovery story: recovering
means downtime measured in however long the replay takes. The streaming
standby that ADR 0050 also asks for, and the failover to it, are in
[standby-and-failover.md](standby-and-failover.md) (ADR 0112).

## Related

- `docs/ops/staging-drills.md` — the dump and restore drill on throwaway
  databases
- `docs/ops/standby-and-failover.md` — the streaming standby and failover
- `docs/ops/reload-and-restart.md` — stopping and starting the service
- `docs/adr/0050-infrastructure-distributed-systems.md` — the requirement
