# ADR 0160: Administrator GUI Configuration

## Status

Accepted (2026-11-01), under the owner's explicit request for ergonomic GUI
management of plugins and general forum settings, without requiring the CLI.

## Date

2026-11-01

## Context

The old settings console displayed environment values and asked an operator
to edit files. That is unsuitable for routine forum administration. Mutable
forum choices also need one shared state across web processes, rather than
process-local flags or edits to a root-owned environment file.

## Decision

Provide `/admin/plugins` and `/admin/configuration` as primary management
surfaces, linked from the admin dashboard and existing diagnostics page.
Use native forms, labels, keyboard controls, grouped settings, localized
choices, optional search, explicit save actions and progressive details.
The primary workflow needs no JavaScript. Search and unsaved-edit protection
enhance it. A failed save preserves nonsecret input and highlights validation
problems. Existing secrets are never redisplayed.

Core owns a singleton PostgreSQL configuration row with a revision and JSON
sections for plugins and general settings. Providers cannot access it. New
versioned functions validate known keys, enforce active global administrator
manage permission, current MFA policy and participation, and write through
the existing idempotent command and audit functions. Writes use a revision
precondition; stale forms return conflict rather than overwrite another
administrator. Successful changes and audit records commit atomically.

The GUI manages each of the eight independent modules and its declared display
mode. It can test link recognition without publishing or contacting the
external service. Runtime configuration is read once per request; disabled
plugins and link-only mode apply across processes without restarting. A failed
configuration read disables plugin cards while preserving post source.
Public page cache variants include the durable configuration revision.
The authoritative read is one SQL statement on every page request, including
public cache hits; a hit skips forum-content queries, not this configuration
read. Query budgets count it explicitly. This amends ADR 0019's cache access
sequence without changing HTTP validators or anonymous-only caching.

General GUI settings cover branding, language, theme, time zone, public forum
address, media size/source policy, WebSub, legal/operator/privacy contacts
and outgoing mail configuration. Installation defaults remain the fallback
and may be restored per field. Related values validate and save together.
SMTP credentials are sealed with the existing SecretBox and installation
signing keys, with a setting-specific context. They are never returned in
forms, JSON, audit metadata or logs. Blank secret input preserves the stored
secret. A keyed request fingerprint allows safe idempotent retries even
though sealing generates a new nonce on each attempt.

Live presentation settings apply on the next page. Services read startup
settings on restart; the GUI labels these explicitly and startup loads the
durable overrides. Existing browsers and intermediary cache lifetimes still
apply. Host bootstrap authority (database location, process/service layout,
root signing keys, TLS and filesystem access) remains deployment-owned; the
diagnostics page exposes it separately, not as ordinary forum preferences.
Liveness and metrics do not depend on the mutable configuration read.

## Consequences

Routine plugin and forum administration no longer needs command-line access.
State is shared, audited, conflict-safe and reversible through the GUI.
The migration is required before editable controls are available. Core still
starts before that migration for initial setup; it never pretends a failed
database write succeeded. Signing-key rotation must retain previous keys
until saved SMTP secrets have been resealed with the current key.

## Related Decisions and Implementation

- ADR 0159 and [Plugin API v1](../plugin-api-v1.md).
- `migrations/2012_api_core.sql`, `migrations/2016_api_admin.sql`,
  `lib/GPForum/Service/Admin/Configuration.pm`,
  `lib/GPForum/Controller/Admin/Configuration.pm`,
  `lib/GPForum/Controller/Admin/Plugins.pm`,
  `templates/admin/configuration.html.ep`, `templates/admin/plugins.html.ep`.
- `t/integration/postgres-admin-configuration.t`,
  `t/764-plugin-api-contract.t`.
