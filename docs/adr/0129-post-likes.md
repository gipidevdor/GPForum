# ADR 0129: Post Likes

## Status

Accepted. The owner asked on 2026-10-15 for the product features of
docs/PRODUCT_BACKLOG.md, PB-01 first; local PostgreSQL, HTTP and browser
checks pass. Acceptance of this decision does not establish release
readiness.

## Date

2026-10-15

## Context

ADR 0095 asks for lightweight acknowledgements that stay social signals and
never become an authority system. The backlog's first package (PB-01) is a
reversible like on a post, with the self-like policy, concurrency, visibility,
rebuildable counters, erasure and export, and an accessible server-rendered
action left to decide. Emoji reactions and downvotes were to be weighed
separately.

## Decision

A member may like a visible post once and take the like back at any time.
The author of a post cannot like it. Nothing else is added now: no emoji
set, no downvote, no score.

A like is one row in `post_likes`, keyed by post and member, with when it was
given. A page's counts are counted from the rows when the page is read
(`api.community_post_likes_v1`), so there is no counter to rebuild. Liking
and unliking are commands (`api.community_like_command_v1`,
`api.community_unlike_command_v1`), logged like every other write, so a
retried request is answered once; a like already given is kept and a like
not given is nothing to take back, each without a second event. The like
refuses a post that is deleted or not visible, and the request itself is
authorized against the post the viewer may read. The unlike always goes
through, since it adds nothing.

Each like and unlike records a domain event (`post.liked`, `post.unliked`)
with its outbox message; the public HTML cache of the post's thread is
invalidated by it, as for any change to a post. No notification, feed entry,
search change or reputation change is made by a like.

Erasing an account deletes its likes (`api.privacy_revoke_user_v5`, source
`PostLike`); a member's export lists the posts they liked and when
(`api.portability_export_parts_v5`). Hiding or deleting a post keeps its
likes rows, which no page shows while it is hidden; restoring it shows them
again.

The page offers a native form per post (`POST /p/:post_id/like`,
`/p/:post_id/like/remove`), with CSRF and a command id, a pressed state the
screen reader hears, and the count beside it; a reader who is not signed in
sees the count alone. With the page's script the post is swapped in place.

## Consequences

- One row per like keeps counts honest under concurrent retries: the primary
  key is the only arbiter, and the count is never stored.
- Every page of posts reads one more statement, bounded by the page size.
- A later reaction set or score would be a new decision, not a change of
  this one; the rows name only that a member liked a post.
- Functions follow ADR 0126 (new versions of erasure and export; the shipped
  ones stay) and ADR 0127 (typed definer boundaries).
