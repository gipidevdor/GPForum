# PostgreSQL application role

GPForum calls versioned functions in `api`. A separate application login has
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

`bin/gpforum-api-role` is the standalone alias. Without `--apply` it prints the
plan. `--json` returns the same plan or provisioning result as JSON. The
command refuses a privileged role, an object owner, a role with memberships,
or API functions owned by a superuser. Provisioning runs in one transaction
and checks that effective table and column privileges are absent before it
commits.

Provision again after each release changes the function catalogue. Restart
web and worker services using the application environment. Run migration,
partition-maintenance, restore and other administrative commands with the
operator environment. Provisioning does not rewrite service credentials or
restart services.

The partition maintenance timer must load the operator environment too. The
provided service templates initially load the same environment file as the
web service; configure the timer's separate operator file as described in
[partition maintenance](partition-maintenance.md#scheduling) before switching
the web login to the restricted application role.
