# ADR 0130: Members Ignore and Block Each Other

## Status

Accepted. The owner asked on 2026-10-15 for the backlog's features to be
completed under the ADRs, deciding product details along the way; this is
PB-06 (backlog C07). Unit, PostgreSQL and server-rendered checks pass;
acceptance of this decision does not establish release readiness.

## Date

2026-10-15

## Context

A member had no way to stop hearing from another member: the only mute
applies to one thread's subscription. Direct messages (PB-07) depend on a
block that the server enforces. The controls must be private to the member
who uses them, cost little on the hot thread page, and never let a member
silence the staff.

## Decision

A member keeps one private list of other members, each either **ignored** or
**blocked**, in `public.member_relations` (owner, other member, kind, created
and updated times; one row per pair, never oneself). Every read and write is
a versioned function of schema `api` (ADR 0126) with its definer boundary
(ADR 0127): `community_relation_set`, `_remove`, `_list` and `_between`.

**Ignore** means, for the owner only:

- the ignored member's posts are collapsed in threads, behind a native
  `<details>` control that shows the post, with or without JavaScript;
- their replies and mentions are not delivered to the owner's inbox
  (`Notification::Dispatcher` skips them as `member_relation`), and those
  delivered before are left out of the inbox, its unread count and the
  mentions page, judged in the query before `LIMIT` so a page stays full
  (`notification_list_inbox_v3`, `notification_unread_count_v3`,
  `community_list_mentions_v3`). Taking the member off the list brings the
  earlier ones back; notifications skipped meanwhile are not created later.
- their threads and posts are left out of the owner's personal feed, judged
  in the query before `LIMIT` as well (`community_list_feed_v3`, migration
  126, an amendment of 2026-10-17: the feed had kept them while the inbox,
  the mentions page and the digest left them out). Taking the member off
  the list brings them back.

**Block** is ignore plus a refusal of the blocked member's actions towards the
owner: a mention of the owner is not recorded at all (`MentionStore` skips it
as `blocked`), so it neither notifies nor lists. Direct messages refuse a
message when either member blocks the other, and an ignored or blocked
member's messages notify nothing (ADR 0139, an amendment of 2026-10-17).

Product decisions:

- A list holds at most **500** members; the function refuses the next one
  (`limit`) while holding the owner's row, so concurrent requests cannot both
  take the last place. Changing a listed member's kind is always allowed.
- Only the member notification types `reply` and `mention` are silenced. Any
  other type, such as a staff or moderation notice, always arrives, whoever
  sends it; staff can be ignored as authors, never as staff.
- Nobody is told they were ignored or blocked; their own pages, posts and
  replies are unchanged. A blocked member can still read the blocker's public
  posts and reply in a thread.
- Any signed-in member may manage their list, a suspended one included: it is
  a safety tool, not participation. Writes check the CSRF token and the
  `identity.member_relation` rate limit (60 in five minutes); there is no
  audit or domain event, since the list is personal and the audit log is read
  by staff.
- Profile pages offer Ignore, Block (in a sheet that states the consequence),
  Stop ignoring and Unblock to the signed-in reader; `GET /settings/ignored`
  lists the members with a way to remove each, linked from the settings page.
- Erasure removes the erased member's list and the erased member from every
  other list (`privacy_revoke_user` source `MemberRelation`); the export holds
  the member's own list under `member_relations`, never who listed them.

## Consequences

The viewer resolver reads the reader's list in its one query
(`forum_resolve_viewer_v5`), so a thread page pays no query more.
The inbox, mentions and feed reads add an anti-join on the list's primary
key.

## References

- [ADR 0102](0102-effective-visibility.md)
- [ADR 0118](0118-exceptions-are-gpforum-x-classes-required-attributes-are-declared.md)
- [ADR 0126](0126-sql-lives-in-postgresql-functions.md)
- [ADR 0127](0127-separate-runtime-role-for-the-function-api.md)
- [Privacy workflow](../architecture/privacy-workflow.md)
