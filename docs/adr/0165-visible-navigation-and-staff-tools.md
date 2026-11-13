# ADR 0165: Visible navigation and staff tools

## Status

Accepted (2026-11-02), following the owner's request to connect all existing
functions to the GUI after media approval proved difficult to find on iPad.

## Context

Account, moderator and administrator screens existed but several had no visible
entrance from the main header. Media approval could require knowing its URL.
Adding a permission query for each header link would increase the cost of every
page and undermine the existing query budgets.

## Decision

Every page header has a visible **Menu** link to `/menu`. The server-rendered
menu groups moderation, administration, account, forum and information links.
Staff groups appear first and empty groups are omitted. Ordinary pages and
anonymous requests incur no new permission query. A signed-in menu visit reads
its username and six relevant global permission flags in one bounded call to
`api.admin_navigation_context_v2`.

The finite catalogue includes media approval, held posts, reports, thread
organization, moderation history, suspensions, all administrator consoles,
plugins and network integrations, profile and avatar settings, security and
external login, ignored/blocked members, privacy, following, mentions, drafts,
pending posts, messaging, tag filters and outgoing feeds. Resource-specific
forms stay on their discussion, profile, message or administrator list pages.
Authentication callbacks, challenge/token flows and machine endpoints are not
ordinary menu destinations.

Only active global grants are considered. Scoped, revoked and suspended grants
cannot expose global staff consoles. The menu is private and not stored in a
shared cache; permissions are read afresh on each visit. Failure retains common
destinations with an explicit notice and omits staff links. Destination
controllers independently enforce their existing permission, MFA, CSRF and
participation rules. Menu visibility never authorizes an operation.

The Menu link and destination links use native navigation, with 44-pixel minimum
touch targets, labelled groups and responsive cards. No new JavaScript is needed.
The menu catalogue is checked against standalone human-facing GET routes so a
new screen cannot silently become reachable only by typing its URL.

## Operation and recovery

Apply migration 2033 with the administrative connection, refresh catalogue-based
runtime-role grants, and restart the web processes. The new functions only read
existing tables; no member or attachment data is migrated. Rollback application
code without dropping API functions needed by a running newer worker.

## Validation

Unit tests cover ordinary, anonymous and staff navigation, English/Italian
labels, route registration and coverage, independent response data, a single
permission lookup and failure behavior. PostgreSQL tests cover actual global
and scoped grants, revocation, suspension and account deletion. Catalogue/API
role tests validate the new boundary. Existing hot-page query budgets remain
unchanged. Browser checks cover header discovery, the moderator-to-upload path
and tablet width without horizontal page overflow.
