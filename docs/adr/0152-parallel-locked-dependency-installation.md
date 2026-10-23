# ADR 0152: Parallel Locked Dependency Installation

## Status

Accepted. Amends the Carton-only installation requirements in ADRs 0052,
0059, 0086, 0089 and 0109.

## Context

Installing the application dependency tree serially with Carton is slow on
small production hosts. App::cpm can build independent distributions in
parallel and reads the existing Carton snapshot. Its default resolver chain
can fall back to CPAN, so reading the snapshot alone does not enforce a lock.

## Decision

- `script/bootstrap-deps` uses App::cpm v1.1 or newer through
  `script/gpforum-cpm`, under the validated OS system Perl, into `local/`.
- Every ordinary install requires `cpanfile.snapshot` and uses
  `--resolver snapshot --no-default-resolvers`. Missing or incompatible pins
  fail; the installer never refreshes the snapshot.
- Five workers are the default. `GPFORUM_CPM_WORKERS` accepts a positive
  integer so operators can limit memory consumption on small hosts.
- Phase selection is explicit: configure, build, test and runtime, plus
  develop on development/CI hosts. Production continues to omit only develop.
  `--postgres` selects the postgres feature. Upstream tests remain disabled,
  matching the former Carton policy.
- `PERL_CARTON_MIRROR` retains its HTTPS/local-path contract. `--cached`
  points the snapshot resolver at the `vendor/cache` mirror only.
  `--home local` preserves source archives at `local/cache/authors/id` for
  Carton bundling; `--final-install all` retains build dependencies.
- Carton remains a host tool: it supplies `Carton::Snapshot` and performs
  `--update`, `check` and `bundle`. Existing `gpforum-carton exec` commands
  and runtime entrypoints remain valid. Neither tool enters the application
  lock or is required by the running service.

## Consequences

Production, developer and CI installs share the same parallel installation
path and committed pins. Hosts must install App::cpm alongside Carton. The
speedup depends on CPU, memory, network and build graph; no fixed installation
time is promised. Lock refresh remains a development operation and cannot be
combined with `--production`.

## References

- [App::cpm](https://metacpan.org/pod/App::cpm)
- [Resolver and CLI options](https://github.com/skaji/cpm/blob/main/lib/App/cpm/CLI.pm)
- `script/bootstrap-deps`, `script/gpforum-cpm`, `docs/DEPLOYMENT.md`.
