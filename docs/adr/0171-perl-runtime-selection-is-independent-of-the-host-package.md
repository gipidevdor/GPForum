# ADR 0171: Perl Runtime Selection Is Independent of the Host Package

## Status

Accepted. Supersedes the system-Perl-only installation policy; the Perl 5.40
floor and dependency lock requirements remain in force.

## Date

2026-11-05

## Context

Rejecting version managers and custom installation prefixes couples the
application runtime to the OS release. An interpreter's installation source
does not establish whether it supports the required language features or
matches the native dependencies installed in `local/`.

## Decision

- Support Perl 5.40+ from distribution packages, Homebrew, perlbrew, plenv,
  asdf and custom prefixes. Do not reject an interpreter by its path or
  `Config{prefix}`.
- Select explicit `GPFORUM_PERL` first, then a compatible Perl on `PATH`,
  followed by common installation paths. Resolve manager shims to their
  actual interpreter. An invalid explicit selection fails.
- Launch cpm, Carton, application commands and their Perl subprocesses with
  the selected interpreter. Honor an explicit selection before loading
  application dependencies, even when the initial Perl meets the floor.
- Record the dependency installation's Perl version, architecture and ABI
  options. Refuse incompatible trees with a non-destructive rebuild command;
  allow equivalent builds at different prefixes. Check native modules for
  legacy trees that have no manifest.
- Cache dependency trees by ABI identity as well as platform and lockfile.
- A persistent service pins an accessible absolute interpreter path in its
  supervisor environment. Runtime patching can proceed independently of OS
  Perl package updates.

## Consequences

Version managers and separately maintained production interpreters become
supported deployment choices. The operator maintains the selected runtime's
patches and compiler/library dependencies. A Perl ABI or CPU architecture
change still requires rebuilding native modules. The bootstrap installs
locked application dependencies, not an interpreter.

## References

- [Perl runtime runbook](../ops/perl-runtime.md).
- [ADR 0117](0117-perl-5-40-floor-and-the-use-v5-40-preamble.md).
- [ADR 0152](0152-parallel-locked-dependency-installation.md).
