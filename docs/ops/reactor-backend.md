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

`GPForum::OS::Reactor` sets `MOJO_REACTOR` and `LIBEV_FLAGS` before event-loop
consumers load. `bin/gpforum` loads it before the command launcher, and the
application loads it before Mojolicious. Inherited preferences for Poll,
select, or another libev backend are overridden on supported hosts.

Application startup verifies both the actual singleton reactor class and
`EV::backend()`. Merely observing `Mojo::Reactor::EV` does not prove epoll or
kqueue: libev can otherwise choose select, including on macOS. Missing EV,
an unavailable native backend, or an already initialised incompatible loop
stops startup. This applies to development, CI and production without a
strict-mode opt-in. Existing loops are never destroyed or replaced.

Use `bin/gpforum start` for the normal entry point. For an embedding process
that loads Mojo first, preload the policy before the framework:

```sh
script/gpforum-carton exec perl -Ilib -MGPForum::OS::Reactor -S hypnotoad bin/gpforum
```

The default EV loop is created when EV loads, so setting `LIBEV_FLAGS` after
that point cannot select a different backend. See the
[EV API](https://metacpan.org/pod/EV) and
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

`.proverc` preloads the same core-only policy before each test process, so
`Test::Mojo` cannot initialise an incompatible default loop before the
application loads. `t/688-native-reactor.t` exercises real subprocesses for
native startup, inherited fallback preferences, missing EV, an existing Poll
singleton and an existing libev select loop. `t/58-os-runtime-evidence.t`
checks that the wrong native backend remains visible in the evidence.

Readiness still includes `/health/ready`, query plans, actual Hypnotoad
workers, descriptors/backlog, request latency and outbox health.
