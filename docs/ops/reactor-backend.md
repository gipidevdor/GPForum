# Reactor backend

GPForum requires the native event backend on every supported operating system:

| Operating system | Mojo reactor | Required libev backend | `LIBEV_FLAGS` |
| --- | --- | --- | --- |
| Linux | `Mojo::Reactor::EV` | epoll | 4 |
| macOS | `Mojo::Reactor::EV` | kqueue | 8 |
| FreeBSD | `Mojo::Reactor::EV` | kqueue | 8 |

`EV` is a mandatory runtime dependency installed and pinned by Carton. Run
`script/bootstrap-deps --postgres` to install the locked dependency set.
An optional OS EV package is no longer part of the performance workflow.

## Startup enforcement

libev reads `LIBEV_FLAGS` once, when EV loads and creates its default loop,
and an existing loop cannot be replaced. On macOS libev's own default is
select, and on FreeBSD kqueue is outside libev's recommended set, so whatever
loads EV first decides. The backend is therefore chosen before any Perl
starts, at each entry point:

- `bin/gpforum` loads `GPForum::OS::Reactor`, which sets `MOJO_REACTOR` and
  `LIBEV_FLAGS`, before anything else; Hypnotoad, `gpforum start` and the
  service units inherit them.
- `script/gpforum-carton exec` exports the same two variables (from
  `uname -s`) for everything it runs: `morbo bin/gpforum`, `prove` with or
  without `--norc`, `yath`, `perl t/...` and profilers. `t/698` keeps its
  table equal to the module's.
- The application module loads `GPForum::OS::Reactor` before Mojolicious, for
  an embedding process that loads nothing first.

Inherited preferences for Poll, select, or another libev backend are
overridden on supported hosts.

Application startup verifies both the actual singleton reactor class and
`EV::backend()`. Merely observing `Mojo::Reactor::EV` does not prove epoll or
kqueue. In production (`GPFORUM_ENV` production, production-small,
production-medium) a fallback stops startup and names the variables and the
entry points that set them. In development and tests -- a runner that loaded
`Test::Mojo` or `Mojo::IOLoop` before GPForum and bypassed the front door --
the application starts on the loop that exists and logs a warning with the
same text: the backend changes throughput, not behavior. Missing EV stops
startup everywhere. Existing loops are never destroyed or replaced.

An embedding process that loads Mojo first and does not start through the
front door preloads the policy, or exports the variables itself:

```sh
perl -Ilib -MGPForum::OS::Reactor -S hypnotoad bin/gpforum
LIBEV_FLAGS=8 MOJO_REACTOR=Mojo::Reactor::EV hypnotoad bin/gpforum
```

See the [EV API](https://metacpan.org/pod/EV) and
[libev backend documentation](https://metacpan.org/pod/libev).

Unknown operating systems retain the conservative portable behavior of the
generic OS profile; they are outside the supported native-backend matrix.

## Evidence and verification

`GPForum::OS::RuntimeEvidence` reports the declared backend, expected and
actual reactor, and expected and actual libev backend flags. A matching EV
class with the wrong libev backend is a mismatch. HTTP and extreme-load
benchmarks require EV with the host backend, and verify it in every serving
worker; a failed probe cannot select Poll. Historical benchmark artifacts
retain their observed reactor values.

`t/688-native-reactor.t` exercises real subprocesses for native startup,
inherited fallback preferences, missing EV, an existing Poll singleton and an
existing libev select loop. `t/698-reactor-entry-points.t` checks the front
door's backend, a `Test::Mojo`-first test through it, a development start on
an existing select loop and the production refusal. Nothing preloads the
policy in front of a test with an explicit interpreter, so
`HARNESS_PERL_SWITCHES` (Devel::Cover, NYTProf) reach every test
(`t/699-harness-switches.t`). `t/58-os-runtime-evidence.t`
checks that the wrong native backend remains visible in the evidence.

Readiness still includes `/health/ready`, query plans, actual Hypnotoad
workers, descriptors/backlog, request latency and outbox health.
