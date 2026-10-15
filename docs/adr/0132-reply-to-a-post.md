# ADR 0132: Reply to a Post

## Status

Accepted. The owner asked on 2026-10-15 for the product features of
docs/PRODUCT_BACKLOG.md; A04 is the first of the discussion ones after the
like. Local PostgreSQL, HTTP and browser checks pass; acceptance of this
decision does not establish release readiness.

## Date

2026-10-15

## Context

A thread is one list of posts. Quoting carries a post's words into a reply,
but nothing records which post a reply answers, so a reader cannot follow
an answer back to its question, and a later reply cannot be told from a
reply to the thread. The reply command (ADR 0126 section 5) is the most
guarded write in the forum, with its races and its drafts; changing its
shape for a hint is out of proportion.

## Decision

A reply may answer one post. The page offers "Reply" under each post, which
opens the composer with the post named ("Replying to #12 by @name") and a
way to drop it; "Quote" does the same and quotes the words. The reply is
created as before; then, and only when the reply was made, the link is
written to `post_replies` (`api.forum_link_reply_v1`), and it holds only
when both posts are in the same thread and the post answered is there to be
read. A link written twice is one; a reply retried is one. A link that
cannot be written leaves the reply as it is: the reply is the content, the
link a hint.

The page reads the links of its posts in one call
(`api.forum_reply_targets_v1`) and shows "In reply to #12" under the reply's
byline, a link to the post on its page. Nothing follows the link into
notifications, feeds or search; those are separate decisions.

## Consequences

- The reply command, its functions and its differential tests are
  untouched; the link costs one more statement after a reply that answers a
  post, and one more read per page of posts.
- A post answered that is later hidden or deleted keeps the link; the page
  shows it as long as the post is on the page, which is what the reader can
  follow.
- Erasure and export carry nothing new: the rows hold ids only.
- Functions follow ADR 0126 and ADR 0127 (typed definer boundaries).
