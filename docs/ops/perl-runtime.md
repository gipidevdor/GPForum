# Selecting the Perl runtime

GPForum requires Perl 5.40 or newer. Its installation prefix and provider
are independent of the host OS package: distribution Perl, Homebrew,
perlbrew, plenv, asdf and custom builds are supported.

Selection uses this precedence:

1. `GPFORUM_PERL`, when explicitly set to an executable path or command.
2. The active `perl` on `PATH`, if it meets the version floor.
3. Common installation paths, for shells whose first Perl is too old.

An invalid explicit selection fails with a diagnostic. A version-manager
shim is resolved to the executable it launches, which wrappers then pin
for the process tree. `script/gpforum-system-perl` and `make system-perl`
retain their historical names for compatibility; they validate any supported
runtime.

## Development

Activate an installed Perl with your manager, or set its executable:

```sh
perlbrew use perl-5.44.0
make perl-runtime
```

Alternatively:

```sh
export GPFORUM_PERL=/opt/perl/5.44.0/bin/perl
make perl-runtime
```

Install the host tools for the selected interpreter, then the locked
application dependencies:

```sh
perl_bin="$(script/gpforum-system-perl --require)"
"$perl_bin" -S cpanm -M https://cpan.metacpan.org/ App::cpm Carton
script/bootstrap-deps --postgres
bin/gpforum help
```

Use a supported, maintained patch release of the chosen Perl series.
The bootstrap does not install Perl. Compiler tools, libpq, OpenSSL and zlib
headers still come from the host's package manager. A user-owned Perl prefix
does not require sudo to install its tools.

## Services

Use an absolute interpreter path in the supervisor's environment. Interactive
shell activation is not inherited by systemd, launchd, cron or rc.d.
For systemd, the service's `EnvironmentFile` can contain:

```sh
GPFORUM_PERL=/opt/perl/5.44.0/bin/perl
```

The variable must exist **before** `bin/gpforum` starts; an environment file
read later by a CLI command cannot select the initial interpreter. Provision
the service environment through its supervisor. The front door honors the
selection even when a different compatible Perl first executes its shebang.

Give the service account read/execute access to the interpreter and its
libraries. Install production runtimes outside protected home directories,
for example under `/opt/perl`: units using `ProtectHome=true` cannot read a
developer's perlbrew installation in their home directory. Keep code and
dependencies read-only to the service account, as for a distribution runtime.

## Dependency compatibility and upgrades

After a successful install and lock verification, the bootstrap writes
`local/.gpforum-perl.json`. It records Perl's version, architecture, API
version, threading, multiplicity and numeric ABI options. The executable
path is diagnostic information, not part of the compatibility identity:
equivalent builds at different prefixes can share a dependency tree.

The launcher checks the recorded ABI before loading dependencies. A mismatch
or unreadable manifest refuses startup with this recovery command:

```sh
script/bootstrap-deps --postgres --rebuild-local
```

The old tree is renamed to `local.rebuild.TIMESTAMP` and preserved. Build
with the selected runtime; do not copy compiled dependencies between CPU
architectures or different Perl ABIs. Dependency caches include the ABI
digest as well as the OS, architecture, feature set and lock inputs.

Older installations without a manifest remain supported. Their principal
native modules are loaded as a compatibility probe without modifying the
release. The next successful dependency install writes the manifest.

For an upgrade, install the new interpreter beside the old one, select it
explicitly, rebuild the dependency tree, run the required checks and restart
the services with the new absolute path. An OS Perl package upgrade then
does not change a service pinned to an independently installed runtime.

`t/854-perl-runtime.t` checks managed/custom layouts, PATH and override
precedence, shim resolution, ABI mismatch refusal, corrupt manifests and
compatibility across equivalent prefixes. Existing installation and launcher
tests cover the locked installer and read-only dependency trees.
