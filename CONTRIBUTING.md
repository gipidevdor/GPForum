# Contributing

Keep changes focused, operable and consistent with the project's Perl-first,
PostgreSQL-native, SSR-first design.

Use **Good Phorum** or **GP Forum** in prose. Preserve identifiers such as
`GPForum::*`, `gpforum` and `GPFORUM_*`. Follow the
[name guide](docs/BRANDING.md) and [writing guide](docs/WRITING.md).
Project attribution is **GPForum Contributors**; individual credits are in
[CONTRIBUTORS.md](CONTRIBUTORS.md).

## Development loop

1. Select **Perl 5.40 or newer** from your distribution, Homebrew,
   perlbrew/plenv/asdf or a custom build. Set `GPFORUM_PERL=/absolute/path/to/perl`
   or activate it on `PATH`; confirm with `make perl-runtime`. Install App::cpm
   and Carton for that interpreter with
   `cpanm -M https://cpan.metacpan.org/ App::cpm Carton`.
2. Install build tools and PostgreSQL dependencies: a C toolchain,
   `libpq-dev`, `libssl-dev` and `zlib1g-dev` on Debian/Ubuntu; or
   `brew install perl cpanminus postgresql@18` on macOS. A selected custom Perl
   can use Homebrew's PostgreSQL client tools. See the
   [runtime runbook](docs/ops/perl-runtime.md).
3. Run `make install-deps-postgres` (`script/bootstrap-deps --postgres`).
   It installs from `cpanfile.snapshot` over HTTPS MetaCPAN with exclusive
   snapshot resolution, including the PostgreSQL driver. After changing
   `cpanfile`, refresh with `script/bootstrap-deps --update --postgres` and
   commit the snapshot. Omitting `--postgres` can remove the driver from the lock.
4. Run `script/system-preflight` to check the host.
5. Make one focused change. Update the relevant guide and add or amend an ADR
   when a design decision changes. Use the [documentation index](docs/README.md)
   and [ADR index](docs/adr/README.md).
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

Commit first: this check clones **HEAD**, so it excludes uncommitted changes.
It reinstalls dependencies and runs the quick start and `make check` in a
clean checkout, catching missing files, undeclared modules and omitted steps.
With `GPFORUM_DATABASE_DSN` set, it also migrates a throwaway database and runs
the integration tier. `t/166-deploy-contract.t` checks the README's command sequence.

Run profiling for performance-sensitive changes:

```sh
script/profile-nytprof -- -Ilib -It/lib t/17-notifications.t
```

## Architectural rules

- Give services, stores, command handlers and projections narrow responsibilities.
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
