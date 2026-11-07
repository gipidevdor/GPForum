# ADR 0154: Executable boundaries and native Perl

Date: 2026-10-23. Status: accepted.

ADR 0117 already establishes `use v5.40`, native `try/catch`, signatures,
lexical builtins, and the removal of indirect calls and bareword handles.
There is no application dependency on Try::Tiny to remove. Stable `true`
and `false` replace references to literal 1 and 0 in operational JSON.
`is_bool` is still experimental in the supported 5.40 release and is not
needed to serialize these values.

Native `class`, `field` and `method` remain experimental at our supported
floor. Keep Mojo::Base and the required-attribute contract until the native
class feature is stable at the minimum supported Perl. At that point first
port a small value object and validate construction, inheritance, required
fields, serialization and dependency injection before migrating services.
Do not opt the running application into experimental object semantics.

Three project Perl::Critic policies reject persistence imports in controllers,
controller parameters in services and acquisition of resultsets outside
Infrastructure. `make check` runs them through `make architecture`.
PPI distinguishes code from comments and strings; the focused tests include
examples that must fail and examples that must pass.

The ORM paths retained for differential SQL tests and old test doubles are
real exceptions, not an accomplished migration. Their inventory lives in
`etc/architecture-policy-baseline.json`: policy, file, SHA-256 of the enclosing
subroutine and violation count. New calls, altered exceptional subroutines
and increased counts fail the gate. `--inventory` prints evidence for review;
the checker has no baseline-update option. An exception can be removed when
its retained ORM path is retired. The ScheduledJobs controller factory moves
to the bootstrap composition root instead of receiving an exception.

Run `script/gpforum-carton exec script/architecture-policies` independently.
