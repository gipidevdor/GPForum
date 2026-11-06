# Entrypoint Layout

Put application commands behind `bin/gpforum`; put repository and toolchain
utilities in `script/`. `script/architecture-check` enforces the layout in
`make check` and CI.

## The rule

- **`bin/`** holds **one Perl application entrypoint**, `bin/gpforum`, the
  front door. It loads the application for commands and the web service. Every
  command is one of its verbs (`bin/gpforum migrate`): a `GPForum::CLI`
  adapter, listed in `GPForum::Command::Support::Verbs`, over the
  `GPForum::Command` class that does the work. `bin/` never contains shell.

- **`script/`** holds **repository and toolchain utilities**. Keep the runtime
  wrappers available in deployed checkouts: `bin/gpforum` uses them to select
  Perl and load dependencies. A tool is POSIX `sh` unless it needs Perl: the gates
  (`perl-syntax-check`, `query-plan-check`, `cpan-license-check`,
  `adr-index`), most benchmarks, and the schema and evidence tools are Perl,
  and most of those load `GPForum::*` code through `-Ilib`, as the `perl
  -Ilib` one-liners in some `sh` tools do. Application operations go through
  `gpforum`: for example, `system-preflight` runs `bin/gpforum os-preflight`.

- **No wrappers.** A command is typed through the front door, `bin/gpforum
  VERB` (`bin/gpforum stress-load`), which finds the Perl and the
  dependencies itself; neither `bin/` nor `script/` holds a file that only
  runs one. The `gpforum-` prefix inside `script/` is reserved for the
  standalone tools that set up and check the toolchain and the evidence:
  `gpforum-carton`, `gpforum-cpm`, `gpforum-system-perl`,
  `gpforum-homebrew-env`, `gpforum-private-beta-checklist`,
  `gpforum-evidence-live` and `gpforum-evidence-archive-check`.

- **Invariant.** No basename appears in both `bin/` and `script/`.

- A `bin/` path a `script/` file names must exist, and every file in both
  directories must be executable.

- What a command exits with -- 0, 1 for a failure, 2 for misuse, 78 for
  settings -- is the console contract, in
  [docs/ops/console-and-cli.md](ops/console-and-cli.md).

## CPAN tools

`script/bootstrap-deps` installs the locked distributions in parallel through
`script/gpforum-cpm`, which runs App::cpm with the validated selected Perl.
Carton still supplies snapshot parsing, lock updates, checks and bundles.

The only script that invokes `carton` directly is `script/gpforum-carton`
itself. Bare `carton` would bypass interpreter selection in
`script/gpforum-system-perl`, and on macOS the `carton` found first on `PATH`
can belong to another Perl, so documentation uses `script/gpforum-carton exec`
throughout.

## Legacy collisions

None. No basename exists in both directories, and
`ENTRYPOINT_COLLISION_ALLOWLIST` in `script/architecture-check` is empty. It
may not grow again: a new basename in both directories fails the check.
