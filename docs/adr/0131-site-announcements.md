# ADR 0131: Site Announcements

## Status

Accepted. The owner asked on 2026-10-15 for the product features of
docs/PRODUCT_BACKLOG.md; B06 is the first of the administration ones. Local
PostgreSQL, HTTP and browser checks pass; acceptance of this decision does
not establish release readiness.

## Date

2026-10-15

## Context

Operators had no way to tell every reader something at once: a maintenance
window, a rule change, a welcome. The presentation layer has status banners
for a page's own state, but nothing an administrator writes and takes down,
and nothing the public page cache knows to drop when that happens.

## Decision

An administrator publishes a site announcement from the console
(`/admin/announcements`): plain text, 1 to 500 characters, in a `notice` or
a `warning` tone. Every page shows the announcements not yet retired, newest
first and at most three, between the site header and the page's own
content, as a region named "Announcements". An administrator retires an
announcement; nothing is deleted, and who published and who retired it, and
when, stay on the row (`site_announcements`).

Publishing and retiring are admin commands (`admin.announcement_publish`,
`admin.announcement_retire`), logged like every other write, audited, and
each records a domain event (`announcement.published`,
`announcement.retired`). The write purges the public page cache at once, so
no reader sees a stale set; the cache invalidation worker purges it again on
the event, for the copies a purge could not reach.

The text is plain: no markup, no links. What an announcement may say is the
operators' responsibility, as the rest of the console is.

## Consequences

- Every page reads the active announcements once; the read is bounded and
  degrades to none, with a warning in the log, if it fails.
- Retired announcements accumulate; the console lists the newest fifty.
- Scheduling (start and end times) and per-reader dismissal are separate
  decisions, not taken here.
- Functions follow ADR 0126 and ADR 0127 (typed definer boundaries).
