# PostgreSQL application role

Good Phorum calls versioned functions in `api`. A separate application login has
`CONNECT`, `USAGE` on `api`, and `EXECUTE` only on the current catalogue's
signatures. It has no table or sequence privileges, no schema creation rights,
no role memberships and no object ownership. Direct reads and writes of forum
tables therefore fail at PostgreSQL's permission boundary.

The functions' owner is the ordinary migration role: no superuser or
`BYPASSRLS` attributes. That role owns the schema and migrations and stays
available to operators. API entry points use `SECURITY DEFINER` with
`search_path = pg_catalog, pg_temp`; implementation functions have no public
execution rights. Session settings, transactions and `LISTEN`/`UNLISTEN` are
connection operations. PostgreSQL also permits expressions such as `SELECT
1` and access to its public system catalogs; the boundary denies direct access
to forum tables and sequences. Administrative migrations and partition DDL
use the operator connection.

Create an application login with PostgreSQL administration first, for example:

```sql
CREATE ROLE gpforum_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION NOBYPASSRLS NOINHERIT;
```

Set its authentication through the host's existing PostgreSQL policy. With
password authentication, use `psql`'s `\password gpforum_runtime` prompt.

### Peer authentication on the socket

Web processes, workers and operator commands reach the local PostgreSQL
server over Unix-domain sockets (ADR 0137). An explicit local DSN is
`dbi:Pg:dbname=gpforum;host=/var/run/postgresql` on Debian/Ubuntu, or
`dbi:Pg:dbname=gpforum;host=/tmp` for the usual Homebrew/FreeBSD socket.
Use the same socket directory in `GPFORUM_ADMIN_DATABASE_DSN` when setting a
separate operator connection. A DSN without `host=` uses libpq's default
socket directory when no host environment override is present, and
a distribution's `pg_hba.conf` authenticates the socket by `peer`: the
connecting process's operating-system account, as the kernel reports it,
must be the role's name. Debian's `local all all peer` therefore refuses
both connections this guide needs -- the web and worker services run as
the `gpforum` account and connect as `gpforum_runtime`, and the operator
runs `migrate` and `api-role` from their own login as `gpforum` -- with
"Peer authentication failed for user". A map in `pg_ident.conf` says which
account may be which role. `sudo gpforum setup` prints these lines for the
host, with the operator's login (here `alice`) in the last one:

```text
# pg_hba.conf, above the distribution's other local lines
local   gpforum   gpforum,gpforum_runtime   peer map=gpforum

# pg_ident.conf
gpforum   gpforum   gpforum
gpforum   gpforum   gpforum_runtime
gpforum   alice   gpforum
```

`SHOW hba_file` and `SHOW ident_file` name the two files
(`/etc/postgresql/18/main/` on Debian); reload with `sudo -u postgres psql -c
'SELECT pg_reload_conf()'`, and `SELECT * FROM pg_hba_file_rules WHERE error
IS NOT NULL` lists a line PostgreSQL could not read. The line applies to the
forum's database and its two roles alone; every other connection keeps the
distribution's rules, and no password is stored for either role. With a
map, PostgreSQL no longer admits an account as its own role by default,
which is why the `gpforum` account's line for the `gpforum` role is there.

`sudo -u gpforum gpforum doctor` connects as `GPFORUM_DATABASE_USER` and, when
the file it reads sets one, as `GPFORUM_ADMIN_DATABASE_USER`; a refusal says
which account was refused which role, and repeats the lines.

Keep the operator environment file separate from the web and worker service
file. The operator file supplies the migration role as
`GPFORUM_DATABASE_USER`, together with its database and authentication, and
sets `GPFORUM_ADMIN_DATABASE_USER` to that same migration role.
`GPFORUM_ADMIN_DATABASE_DSN` can override the database DSN, and
`GPFORUM_ADMIN_DATABASE_PASSWORD` or `.pgpass` supplies its authentication.
The web and worker file supplies `GPFORUM_DATABASE_USER=gpforum_runtime` and
its authentication, with no administrative credentials.

Apply migrations using the operator environment, review the role plan, and
apply it:

```sh
bin/gpforum --env-file /etc/gpforum/admin.env migrate
bin/gpforum --env-file /etc/gpforum/admin.env api-role --role gpforum_runtime --plan
bin/gpforum --env-file /etc/gpforum/admin.env api-role --role gpforum_runtime --apply
```

Without `--apply` it prints the plan. `--json` returns the same plan or
provisioning result as JSON. The
command refuses a privileged role, an object owner, a role with memberships,
or API functions owned by a superuser. Provisioning runs in one transaction
and checks that effective table and column privileges are absent before it
commits.

Provision again after each release changes the function catalogue. Restart
web and worker services using the application environment. Run migration,
partition-maintenance, restore and other administrative commands with the
operator environment. Provisioning does not rewrite service credentials or
restart services.

The current fresh-database baseline is migrations **2000–2025**
([ADR 0162](../adr/0162-a-fresh-database-baseline.md)). Earlier migration
chains are refused; follow the [upgrade guide](upgrade.md) before installing
this baseline. Applying migrations does not provision an existing runtime
role: its grants must match the installed release's current catalogue.

Drain and stop the previous web and worker processes before reprovisioning
the runtime role with the updated release, then start the updated processes.
For an existing systemd installation with the separate files above:

```sh
sudo systemctl stop gpforum gpforum-outbox
bin/gpforum --env-file /etc/gpforum/admin.env migrate
bin/gpforum --env-file /etc/gpforum/admin.env api-role --role gpforum_runtime --plan
bin/gpforum --env-file /etc/gpforum/admin.env api-role --role gpforum_runtime --apply
sudo systemctl start gpforum gpforum-outbox
```

Run the two `api-role` commands as the operator account authenticated as the
migration role. Provisioning grants only the current catalogue and revokes
historical signatures; old workers must not serve during that step. For a
rollback within the same schema baseline, verify that the previous release's
entry points still exist and provision its catalogue before starting it.
The 2000–2025 baseline removes obsolete functions and cannot be substituted
for an older chain's database. Returning to an earlier baseline requires its
matching database backup and code; see the [upgrade guide](upgrade.md).

The optional Minion PostgreSQL backend is disabled by default. When enabled,
it connects through `GPFORUM_MINION_PG_URL` and runs its own queue SQL and
migrations through Mojo::Pg. The forum's API-only runtime login cannot run
that backend. Use a separate queue database and queue credentials if enabling
Minion; do not grant forum table rights to the runtime login for it.

The partition maintenance timer must load the operator environment too. The
provided service templates initially load the same environment file as the
web service; configure the timer's separate operator file as described in
[partition maintenance](partition-maintenance.md#scheduling) before switching
the web login to the restricted application role.
