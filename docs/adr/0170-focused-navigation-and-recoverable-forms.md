# ADR 0170: Focused navigation and recoverable forms

## Status

Accepted (2026-11-03).

## Context

Exposing every feature simultaneously made reading compete with navigation.
The signed-in header had eight destinations plus search, settings and sign-out.
The administrator menu exposed 52 links with equal weight. Sixteen integration
cards preceded actual work. Transfer pagination dropped checked messages and
invalid submissions replaced the working form with a generic error page.

## Decision

Keep frequent destinations in the header and the complete role-aware catalogue
in Menu. Use native disclosures for account tools, menu groups, reaction choices,
integration setup and transfer history. Add local menu filtering as progressive
enhancement, with accessible empty results. Preserve all routes, permissions,
native POST/CSRF semantics and contextual entrances. Move attachment management
to the post's existing More actions disclosure. Keep Reply prominent.

Place recent discussions before categories in both DOM and visual order. Use a
secondary category sidebar on wide screens and a plain list after discussions
on narrow screens. Put Discord and moderated feed work before a compact module
catalogue. Keep the existing typography, themes and reading measure.

Use explicit native POST browsing controls on the transfer form. They carry
checked messages, destination, operation, title and reason to the next bounded
picker read, without invoking a transfer write. Retain at most 1000 numeric
message positions in the form; do not create server sessions, draft tables or
browser-storage state. Expose selected messages from other pages as removable
checkboxes. Database authorization, locking, idempotency, audience compatibility
and reversal rules remain authoritative. JSON commands/history stay compatible.

Invalid or conflicting HTML transfer commands render the same form with values,
selection, a fresh command identity and an accessible inline error. Forbidden or
missing resources retain their normal refusal. Enhancements make target/title
requirements conditional and show a live selection count; the native flow and
server validation remain usable without JavaScript. A sticky action row avoids
scrolling past fifty messages to find the submit action.

## Consequences

Every feature remains reachable, with secondary tools requiring a deliberate
expansion. No new database migration, production query on a discussion page,
remote request or frontend build dependency is introduced. Native GUI regression
tests exercise cross-page selection, non-mutating browsing, invalid-form recovery
and successful correction against PostgreSQL. The feature gate requires these
results. Visual and interaction checks use isolated loopback fixtures at desktop,
tablet and phone widths; they do not establish physical Safari/iPad behavior or
measured improvements in human task-completion time. No LAN preview is opened.
