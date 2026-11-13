# ADR 0145: Post Reactions

## Status

Accepted. The owner asked on 2026-10-15 for the product features of
docs/PRODUCT_BACKLOG.md; A01 (emoji reactions, package PB-01) was left to
weigh separately by ADR 0129. Local PostgreSQL and HTTP checks pass;
acceptance of this decision does not establish release readiness.

## Date

2026-10-22

## Context

ADR 0129 gave a post a reversible like and said a reaction set would be a
new decision. A like says "I saw this and agree"; a reader often wants to
say something else without writing a reply: that a post moved them, made
them laugh, is worth celebrating, or gives them pause. ADR 0095 asks that
such signals stay social and never become an authority system.

## Decision

Beside the like, a member may give a visible post one of four reactions,
each once, and take it back at any time: heart, laugh, celebrate, think.
The author of a post cannot react to it. There is no score, no ranking
and no other set; adding a reaction is a new migration and a new decision.

A reaction is one row in `post_reactions`, keyed by post, member and
reaction. A page's counts are counted from the rows when it is read: the
thread page's one read (`api.forum_thread_page_reads_v3`, the read of
migration 124 with the reactions as one more part) answers them with the
likes, and `api.community_post_reactions_v1` answers them alone. Giving and
taking back are commands on the like's shape (`api.community_react_command_v1`,
`api.community_unreact_command_v1`), logged like every other write; given
twice it is one, and taking back what was not given is nothing. Each
records a domain event (`post.reacted`, `post.unreacted`) with its outbox
message, which invalidates the post's thread in the public HTML cache.

Erasing an account deletes its reactions (`api.privacy_revoke_user_v19`,
source `PostReaction`); a member's export lists them
(`api.portability_export_parts_v21`). Hiding or deleting a post keeps the
rows, shown again when it is restored.

Under each post the page shows the four reactions as small forms for a
member who may react (`POST /p/:post_id/react/:reaction`, `/remove`), the
one they gave pressed, with CSRF and a command id each; a reader who may
not react sees the counts of the reactions given. With the page's script
the post is swapped in place.

## Consequences

- The like, its functions and its tests are untouched; a reaction is its
  own row, so a member may like and react to the same post.
- The thread page's statements are as before: the reactions ride in its one
  read. A page of posts read without that read costs one more statement.
- Four command ids per post are drawn for a signed-in reader's forms, so a
  form sent twice is one reaction and two reactions are two.
- Functions follow ADR 0126 (new versions of erasure, export and the thread
  page read; the shipped ones stay) and ADR 0127 (typed definer boundaries).
