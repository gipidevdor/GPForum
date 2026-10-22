# ADR 0128: Private Composer Drafts and Canonical Preview

## Status

Accepted. The owner authorized thread/reply drafts and live preview on
2026-10-11. Local PostgreSQL, HTTP, JavaScript and browser behavior checks pass;
acceptance of this decision does not establish release readiness.

## Date

2026-10-11

## Context

The composer needs to preserve unpublished work and show how the existing safe
markup will render. Both features must retain native forms, PostgreSQL authority,
the function-only runtime role and owner privacy. Concurrent tabs and lost save
responses must not silently overwrite newer work or create duplicate posts.

## Decision

Store private thread and reply drafts in PostgreSQL through versioned catalogue
routines. A draft contains its owner's id, kind, category or thread context,
title, source body, intended visibility, revision, publication command id and
creation/update/expiry timestamps. Ownership comes from the authenticated
session, never from a client-supplied owner field. Drafts are unpublished content;
they do not enter search, feeds, notifications, realtime or public post views.

Each owner may keep at most 100 unexpired drafts. Titles are limited to 300
characters and bodies to 50,000 characters. A stored save renews retention for
30 days, including unchanged content saved at its current revision. An exact
retry of a previous save does not change revision or expiry. Expired drafts
cease to be readable immediately; the scheduled
`forum_drafts` job removes expired rows in bounded batches, 100 by default.
Saving also removes the owner's expired rows before checking the quota.

Revision zero creates a draft. Later saves and deletion require the current
revision. An exact retry of an acknowledged save returns its existing result;
a stale revision with different input returns a conflict. The client serializes
saves, retains unacknowledged requests for retry, and stops autosaving on conflict
so the author can compare their text with the saved version.

Native Save and Preview submit buttons work without JavaScript. The progressive
enhancement autosaves after an editing pause and requests live preview; it keeps
no draft in browser persistent storage. Authenticated session writes retain CSRF,
participation and rate-limit checks. Draft and preview responses use
`Cache-Control: private, no-store`.

Preview checks the requested category/thread's visibility and renders the
submitted source with `BodyRenderer` and the `forum.post.body` trusted HTML
policy. It does not read or persist a draft, publish content or expand the markup
language. Publication continues through the existing posting workflow, including
its full write permissions and locked-thread rules. The controller saves the
submitted draft snapshot first; the stored publication routine checks ownership,
revision, command and context, and consumes the draft only in the successful
publication transaction. Command replay is resolved before requiring a draft
that an earlier successful publication already consumed.

Member exports include the owner's unexpired drafts and their manifest count,
excluding internal save-retry bookkeeping. Account erasure removes all that
owner's drafts through the versioned privacy revoker, within the existing
deletion/retention-hold workflow. Manual deletion and expiry remove unpublished
source rather than anonymizing it. Existing backup retention remains separate.

## Consequences

Unpublished work becomes a declared personal-data category with a specific
purpose, access policy, retention and export/erasure contract. Operators must
apply migration 103, provision the updated runtime catalogue and keep the hourly
scheduled-jobs timer enabled. Rollback drains updated processes and provisions
the matching previous catalogue; it leaves the additive draft storage intact.
An older build cannot export, erase or expire those retained drafts. If draft
rows exist, prefer a forward fix or retain draft-aware privacy and retention
support throughout rollback; an application rollback alone is insufficient.

The invariants to verify are owner isolation; target authorization; bounded
storage and expiry; save/delete conflicts and exact retries; canonical safe
preview; no private cache/search/feed/realtime leakage; atomic successful
publication and replay; failed-publication preservation; export/erasure; and
native plus JavaScript EN/IT keyboard flows. Existing readiness, performance,
migration and privacy gates remain required. This decision adds no application
or runtime dependency. Node's built-in test runner is a development/CI tool for
the progressive composer behavior, with no npm packages or application build
step. No competitor implementation or assets are imported.

## Related Decisions and Implementation

This extends the posting and privacy workflows without superseding existing
decisions. In particular, ADR 0068 sequencing and release gates, ADR 0074 privacy,
ADR 0087 governance, ADR 0093 engineering invariants, ADR 0094 frontend behavior,
and ADRs 0126–0127 stored routines/runtime credentials continue to apply.

- [Composer draft guide](../architecture/composer-drafts.md)
- [Implementation review: PR 65](https://github.com/gpicchiarelli/GPForum/pull/65)
- [Posting workflow](../architecture/posting-workflow.md)
- [Privacy workflow](../architecture/privacy-workflow.md)
- [Scheduled jobs](../ops/scheduled-jobs.md)
- Migration: `migrations/003-evolution/103_forum_drafts.sql`
- Tests: `t/650-forum-drafts-web.t`, `t/integration/postgres-drafts-web.t`
  and `t/js/composer.test.cjs`
- Code: `GPForum::Service::Forum::DraftStore`,
  `GPForum::Controller::Forum::Drafts`, `Forum::ComposerBase`,
  `assets/js/composer.js`
