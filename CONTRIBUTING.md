# Contributing

Project attribution: **GPForum Contributors**. See [CONTRIBUTORS.md](CONTRIBUTORS.md) for individual credits.

Good Phorum accepts changes that keep the project independent, Perl-first,
PostgreSQL-authoritative, operable, and explicit.

Use **Good Phorum** in project documentation and **GP Forum** as its short
form. The **P** in **Phorum** stands for **Perl**. Keep technical identifiers
such as `GPForum::*`, `gpforum` and `GPFORUM_*` as implemented; see the
[name and brand guide](docs/BRANDING.md).

## Development loop

1. Select **Perl 5.40 or newer** from your distribution, Homebrew,
   perlbrew/plenv/asdf, a custom prefix. Set
   `GPFORUM_PERL=/absolute/path/to/perl` or activate it on `PATH`, then run
   `make perl-runtime`. Install App::cpm and Carton for that interpreter with
   `cpanm -M https://cpan.metacpan.org/ App::cpm Carton`. Build dependencies
   include a C toolchain, `libpq-dev`, `libssl-dev` and `zlib1g-dev` on Debian
   and Ubuntu. On macOS use `brew install perl cpanminus postgresql@18`, or
   your selected Perl with Homebrew's PostgreSQL client tools. See the
   [runtime runbook](docs/ops/perl-runtime.md) for persistent services and interpreter upgrades.
2. Install dependencies with `make install-deps-postgres`
   (`script/bootstrap-deps --postgres`), as the README quick start does.
   That runs cpm with exclusive snapshot resolution from `cpanfile.snapshot` over
   HTTPS MetaCPAN under the selected Perl, PostgreSQL driver included. Use
   `script/bootstrap-deps --update --postgres` only when refreshing the lock
   after a `cpanfile` change, as the README says (without `--postgres` the
   PostgreSQL feature can drop out of the lock), then commit
   `cpanfile.snapshot`.
3. Run `script/system-preflight` to check the host.
4. Make small changes around one bounded context.
5. Update the relevant documentation and add or amend an ADR when a design
   decision changes. Start with [docs/README.md](docs/README.md) and the
   [ADR index](docs/adr/README.md).
6. Run the quality gate before opening a pull request:

```sh
make check
```

When a change touches what a new contributor runs first — the README quick
start, `cpanfile` or `cpanfile.snapshot`, `script/bootstrap-deps`, or the
`check` target — also run:

```sh
make fresh-checkout
```

It clones the last commit into a temporary directory and runs the quick start
and `make check` there, so it catches what an already set-up checkout hides: a
file that is present but untracked, a module only your `local/` has, a step the
README leaves out. Commit first, since uncommitted changes are not part of the
run. It installs every dependency again and takes a while; with
`GPFORUM_DATABASE_DSN` set it also migrates a throwaway database and runs the
integration tier. `t/166-deploy-contract.t` keeps its steps and the README's
commands in step.

Run profiling for performance-sensitive changes:

```sh
script/profile-nytprof -- -Ilib -It/lib t/17-notifications.t
```

## Architectural rules

- Keep boundaries narrow; do not introduce god classes.
- Prefer domain services, stores, command handlers, and projections.
- PostgreSQL is authoritative. Search, inboxes, feeds, and counters are rebuildable projections.
- cpm, Carton, Perl::Critic, tests, coverage, and profiling are mandatory project surfaces.
- Any deviation from Perl-first, PostgreSQL-native or SSR-first needs an ADR.
  Shared caching is optional; PostgreSQL remains the source of truth.
- Durable event writes should use `GPForum::Infrastructure::EventRecorder`.
- Raw SSR HTML must pass through `GPForum::Web::RenderPolicy`.
- Browser security headers belong in `GPForum::Security::*`, not controllers.

## Migrations

- Follow the [migration layout and rules](migrations/README.md). The schema
  starts from the fresh-database baseline, 2000 to 2025 (ADR 0162); a new migration goes
  in `migrations/` with the next number after the highest. Keep existing
  filenames and SQL bytes intact.
- An applied migration never changes: the runner compares checksums and
  refuses to run when a file differs from what the database recorded.
- An index on a table that already exists is built with
  `CREATE INDEX CONCURRENTLY`, so writes to the table go on while it builds.
  PostgreSQL refuses that inside a transaction block, and the runner sends a
  file whole, so start the file with `-- gpforum:no-transaction`: its
  statements then run one at a time. Each must be safe to repeat; begin with
  `DROP INDEX CONCURRENTLY IF EXISTS` for the index, because a failed
  concurrent build leaves an invalid one behind. A partitioned parent cannot
  be built concurrently: say so in a `-- gpforum:blocking-index <reason>`
  line. `t/209-migration-indexes.t` enforces this from migration 049 on.

## Pull requests

Every pull request should include:

- a short user or operator reason;
- tests for the affected behavior;
- documentation and ADR updates when contracts change;
- migration and rollback notes when database shape changes;
- profiling notes when hot paths change.

For isolated PostgreSQL integration tests, install the postgres dependency
feature and PostgreSQL client/server programs, then run `make integration`
(`JOBS=8` by default). Each test file owns its temporary socket-only cluster;
an explicit database DSN still selects an existing server.

Generate a service and its SQL contract from the repository root:

```sh
script/gpforum-carton exec perl -Ilib local/bin/mojo generate gpforum-service Forum::Name
```

Review the generated migration, add authorization and behavior, then run its
integration test and `make check`. The generator refuses existing files.
