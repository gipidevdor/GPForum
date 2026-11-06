# ADR 0134: First-Post Review Queue

## Status

Accepted. The owner asked on 2026-10-15 for the backlog's features to be
completed under the ADRs, deciding product details along the way; this is
PB-05 (backlog F05), after the watched words and link rule of ADR 0133.
Unit, PostgreSQL and server-rendered checks pass; acceptance of this
decision does not establish release readiness.

## Date

2026-10-15

## Context

A spammer's first post is usually their worst, and it is read by everyone
before a moderator sees it. Reports and automod flags act after the fact.
A forum that wants to see a new member's first posts before anyone else
does needs to hold them, and held content must not leak: a post that is
stored as a post, even hidden, is a row every reader, counter, feed,
search projection, outbox consumer and JSON answer would have to filter,
and one forgotten filter publishes it.

## Decision

**Held posts are not posts.** A held thread or reply is kept in its own
table, `public.held_posts`: the author, the command id they submitted,
where it goes (the category, or the thread), the title, the Markdown and
its safe rendering as the composer made it, the visibility asked for, the
post it answers (ADR 0132), why it is held and what the automod rules
found. Nothing is written to threads, posts, counters, the event log or
the outbox, so no reader, count, feed, search document, realtime message
or notification can carry it. Only two places read it: the author's own
list and the staff queue.

**What is held.** The review rule lives beside the link rule in
`public.automod_settings`: a number of first posts (0 to 20; 0, the
default, is off) and whether flagged posts are held too (off by default).
A new thread or reply by a member with fewer published posts than the
number is held; a published post is one of theirs that is neither deleted
nor hidden, so a member's posts from before the rule count and an
established member is never held. When flagged posts are held, a new
thread or reply that a watched word or the link rule flags is held
instead of being published with a system report (ADR 0133); otherwise
flags work as before. Edits are never held: an edit is of a published post
and stays with the automod screen. A block still refuses; replacements are
applied to the held text. Staff holding the global `thread.moderate`
binding are neither screened nor held. The rule and the author's published
count (counted up to 20) come in the same call as the automod rules
(`api.moderation_automod_rules_v4`), so holding costs a write no extra
round trip.

**Holding.** A held write is checked as its write would be first: the
thread or category as the author reads it, the thread still accepting
replies, the composer's validation. The author hears at once what is
wrong, and staff never review a post that could not be published. The
author's command id keys the entry, so the same submission again answers
the same entry. The draft it was written in goes, as when a post is
published. A form is answered with a redirect to the author's list
(`/pending`) and a notice; a script asking for a thread fragment gets an
`HX-Redirect` there; JSON gets `202 Accepted` with `status: held` and the
entry's id.

**The author** sees their held posts at `GET /pending`: pending, and those
decided in the last 30 days (approved with a link to the post, rejected
with the reason staff gave, or withdrawn). They may withdraw a pending one
(`POST /pending/:review_id/withdraw`). Nobody else's entries are ever read
there. The list reads the place each entry went as the author reads it now
(`moderation_review_mine_v3`, migration 127, an amendment of 2026-10-17): a
thread or category the author can no longer read, because it was hidden,
deleted or moved somewhere private, is named by neither its title nor its
id, while the author's own words stay; an approved thread links to the
thread it became, the post's.

**Staff** review at `GET /moderation/review`, linked from the report queue
and the automod page: the pending posts, oldest first, rendered as posts,
with the author, where, why (first posts, or flagged with the words or the
link count) and how many are pending. Reading needs `report.view_queue`,
as the report queue does. Approving (`POST
/moderation/review/:review_id/approve`) or rejecting (`.../reject`, with an
optional reason of at most 500 characters) needs the global
`thread.moderate` binding, a CSRF token and the moderation write rate
limit. The forms work without JavaScript and answer with a redirect and a
notice, or JSON when asked.

**An approval publishes the post as its author's command.** Under a row
lock on the entry and in one transaction, the posting workflow writes it
with the command id the author submitted and the author's own viewer, so
every check of a write runs again (a thread locked or gone, an author
suspended or no longer able to read it), and the decision is recorded with
the post's id. The publication is the ordinary write: its events, outbox
messages, counters, search projection, realtime, mentions and subscriber
notifications follow as for any post, at the time of publication. Two staff
approving at once publish it once; approving it again answers unchanged;
a decision against another decision is a conflict. A post that can no
longer be published is refused and nothing is recorded, not even in the
command log, so it can be approved later or rejected.

**Notifications and audit.** The author is notified when a post is
published (on the post or thread) and when a reply is rejected (on its
thread, with the reason). A rejected thread has no place its author can
read, so its decision is on their list only. Staff are not notified per
held post; the queue is their list. Every hold, decision and rule change is
audited: `review.held` (actor the author, with the reason and what the
rules found), `review.approved`, `review.rejected`, `review.withdrawn` and
`review.rule_set` (with the rule before).

**Privacy.** An erased member's held posts are deleted with the other rows
the erasure revokes (`HeldPost`); the export includes the member's own held
posts and their decisions, never who decided.

**Storage.** Migration 116 adds the table, the rule's columns and the
functions `moderation_review_hold`, `_queue`, `_mine`, `_take`, `_decide`
and `_settings_set`, each an invoker `_v1` behind its definer `_v2`
boundary, and new versions of `moderation_automod_rules` (v3/v4),
`privacy_revoke_user` (v9/v10) and `portability_export_parts` (v11/v12)
(ADR 0126, ADR 0127). Perl validates, builds the audit records and reads
the results.

## Consequences

- No read path changes: holding adds nothing to any page a reader loads,
  and the thread page's query budget is untouched.
- A held post gets its position, its time and its events when it is
  published, not when it was written.
- A member's published count includes their thread opening posts, so a
  first thread that is approved counts as a first post.
- The table keeps rejected and withdrawn entries; the author's list shows
  the last 30 days of decisions, and erasure removes them all.

## References

- [ADR 0118](0118-exceptions-are-gpforum-x-classes-required-attributes-are-declared.md)
- [ADR 0126](0126-sql-lives-in-postgresql-functions.md)
- [ADR 0127](0127-separate-runtime-role-for-the-function-api.md)
- [ADR 0132](0132-reply-to-a-post.md)
- [ADR 0133](0133-watched-words-and-automod-rules.md)
