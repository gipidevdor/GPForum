# GPForum Architecture

GPForum is an SSR-first Mojolicious monolith with modular internal boundaries.
The current direction is a layered modular monolith, not a distributed rewrite.

## Architecture Audit

The current repository already has strong boundaries:

- `GPForum.pm` is a small composition root that delegates to bootstrap modules.
- Controllers are HTTP-oriented and increasingly delegate write flows to services.
- Every statement the services send is a call to a versioned function in
  PostgreSQL's `api` schema, made through `GPForum::Infrastructure::SqlFunction`
  ([ADR 0126](docs/adr/0126-sql-lives-in-postgresql-functions.md)): Perl binds
  the parameters and reads the rows, and the SQL lives in numbered migrations.
- Controllers and templates reach no resultset, and `script/architecture-check`
  refuses one.
- Internal `GPForum::*` module dependency cycles are rejected by
  `script/architecture-check`.
- Forum read paths use reader services and presenter view models.
- Event log and outbox tables are real, durable boundaries.
- Minion-facing workers consume outbox domain event payloads.
- SSR templates use shared components, i18n helpers, CSRF fields, and semantic landmarks.

Priority risks found during the audit:

1. `Controller::Forum` remains too large and still owns several response/error helpers.
   `Controller::Identity`, `Controller::Admin`, and `Controller::Moderation`
   have the same drift risk at smaller scale.
2. Event, audit, and outbox creation was duplicated in write stores.
3. Raw HTML output existed in templates without a central rendering policy.
4. Browser security headers lived directly in bootstrap, making policy drift harder to test.
5. Theme tokens existed in CSS but lacked a runtime registry and explicit theme contract.
6. The target `Application/Domain/Infrastructure/Web/Security/Theme` structure was not yet represented in code. ADR 0107 replaced it with the layers the code has, and a check.

## Layer Map

Five layers, listed from the top. A module may depend on its own layer and the
layers below it, never on one above ([ADR 0107](docs/adr/0107-layers-are-the-namespaces-that-exist.md)).
`GPForum::Application::LayerMap` declares them and `t/192-layering.t` checks
every module in `lib/` against the declaration; `script/architecture-check`
runs the same test.

| Layer | Namespaces | Holds |
| --- | --- | --- |
| composition | the `GPForum` class, `Bootstrap`, `CLI`, `Application` | wiring the others together |
| adapter | `Controller`, `Command`, `Worker`, `Benchmark` | the ways in: HTTP, the command line, jobs |
| presentation | `Web`, `ViewModel`, `View`, `Theme`, `Security`, `I18N` | turning service results into pages and headers |
| service | `Service` | the application: rules, workflows, readers, stores |
| foundation | `Base`, `X`, `Config`, `Log`, `Runtime`, `OS`, `Domain`, `Jobs`, `Schema`, `Migration`, `Infrastructure` | configuration, persistence, cross-cutting contracts |

A new top-level namespace fails the check until it is placed in a layer. This
is a layered architecture, not a hexagonal one: services call the database's
functions directly, and ADR 0107 says so.

## Data Access

ADR 0126 moves every statement into a function in the `api` schema,
`api.<name>_v<N>`. A migration installs it (at 1.0,
`migrations/1011_api_core.sql` to `1023_api_entry_points.sql`,
[ADR 0150](docs/adr/0150-the-schema-starts-from-a-1-0-baseline.md)), a change
is a new version rather than a replacement, and
`GPForum::Infrastructure::SqlFunctionCatalogue` lists it, which a PostgreSQL
test checks against `pg_proc`. A separate runtime login can be limited to
calling those functions
([ADR 0127](docs/adr/0127-separate-runtime-role-for-the-function-api.md)).

DBIx::Class is still loaded while it leaves area by area (ADR 0126, section
8): its storage owns the connection and the transaction a call joins, the
unit tests' in-memory doubles answer the `resultset` branch a store keeps
beside each call, and a few cold paths not yet moved still search through it. A new statement is a
function, never a resultset.

## Flow

```mermaid
flowchart TD
    Browser["Browser / SSR Client"] --> Routes["Mojolicious Routes"]
    Routes --> Controllers["Thin Controllers"]
    Controllers --> Commands["Command / Workflow Services"]
    Controllers --> Queries["Reader / Query Services"]
    Commands --> Stores["Infrastructure Stores"]
    Stores --> EventLog["event_log"]
    Stores --> Audit["audit_log"]
    Stores --> Outbox["outbox_messages"]
    Queries --> Calls["SqlFunction: api.*_vN calls"]
    Stores --> Calls
    Calls --> Postgres["PostgreSQL functions and tables"]
    Outbox --> Minion["Minion / Domain Event Transport"]
    Outbox --> Notify["PostgreSQL NOTIFY"]
    Notify --> Realtime["Websocket Fanout"]
    Minion --> Workers["Idempotent Workers"]
    Workers --> Projections["Search / Inbox / Feed / Cache Projections"]
    Controllers --> Presenters["ViewModel Presenters"]
    Presenters --> Templates["Mojolicious SSR Templates"]
    Templates --> Browser
```

## Current Decisions

- Durable events use `GPForum::Domain::EventEnvelope`.
- Forum, identity, moderation, privacy, export, attachment, admin role, mention fanout, and rate-limit write paths now use `GPForum::Infrastructure::EventRecorder` for event/outbox/audit coordination. Canonical audit hashing lives in `GPForum::Infrastructure::AuditRecord`.
- Browser headers use `GPForum::Security::BrowserHeaders`.
- Repeated web error hashes use `GPForum::Web::ErrorPayload`.
- Health and realtime transport messages use dedicated `GPForum::Web::*Payload`
  modules so technical JSON contracts stay out of controllers.
- Realtime subscriptions use strict policy-backed authorization and
  PostgreSQL LISTEN/NOTIFY for multi-process enhancement fanout.
- Metrics, robots, sitemap, and Atom feed payload composition also lives in
  dedicated `GPForum::Web::*Payload` modules; service builders still own
  crawler/feed document encoding.
- SSR raw HTML pass-through uses `GPForum::Web::RenderPolicy`.
- Theme metadata and supported token contracts use `GPForum::Theme::Registry`;
  SSR theme selection is validated before it reaches HTML attributes.

## Roadmap

1. Keep new service writes behind `Infrastructure::EventRecorder`; direct `EventLog`, `OutboxMessage`, and `AuditLog` writes should remain confined to infrastructure.
2. Extract common controller response/error/auth helpers into `Web::*`.
3. The query-plan gate explains the statements inside the hot functions (ADR 0126, section 9); a new hot read joins `GPForum::Benchmark::QueryPlanEndpoints`.
4. Add command handler interfaces around moderation, privacy, attachment, and identity writes.
5. Normalize Minion job payloads through `Jobs::*`.
6. Add i18n namespace validation and catalog extraction reporting.
7. Move the remaining resultset paths into functions, then drop DBIx::Class (ADR 0126, section 8).
