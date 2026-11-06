# ADR 0139: Direct Messages

## Status

Accepted. The owner asked on 2026-10-17 for a round of feature completion
under the ADRs, deciding product details along the way; this is backlog
C01 (PB-07). Unit, PostgreSQL and server-rendered checks pass; acceptance
of this decision does not establish release readiness.

## Date

2026-10-17

## Context

Members could talk only in public or restricted threads. A private
conversation between two members is the most asked-for missing feature of
a forum, and the most abused: it is where spam and harassment go when the
threads are watched. ADR 0130 already promised that a block refuses direct
messages. The feature must be private to its two members in every channel
-- pages, JSON, search, feeds, events, realtime, mail, staff tools -- and
still let a member bring a message to the staff, and let the staff act on
it without reading anything else.

## Decision

**One conversation per pair.** `public.direct_conversations` holds two
members (the lesser uuid first, unique per pair), who started it and when,
and when it last moved. `public.direct_conversation_members` holds each
member's side: whom it is with, when it last moved (the inbox's keyset
order, indexed), when the member last read it and how many messages wait
for them. `public.direct_messages` holds the messages: author, plain text of
1 to 5000 characters (line endings made one, outer blank space trimmed,
the lines inside kept; never Markdown or HTML), time, and a position from
an identity column that orders them: the clock reads whole seconds, and
two messages of one second keep the order they were stored in. Group conversations
(backlog C02) are left out: they need their own membership and moderation
rules.

**Writes.** `community_message_start` writes to a member by username,
finding the pair's conversation or starting it; `community_message_reply`
answers in a conversation of the sender's. Each is an invoker `_v1` behind
its definer `_v2` (ADR 0126, 0127), takes one row the store builds (the
message id, which is the form's command id so a form sent twice sends one
message, the time and the event's ids), holds the conversation row while it
appends, and records `direct_message.sent` with its outbox message in the
same transaction. Refusals are result values: `invalid`, `forbidden` (the
sender's account is not active), `not_found`, `self`, `blocked`, `gone`
(the other member was erased), `limit`, `conflict`, and `replayed` for the
same message again. Sending a message reads the conversation for its
sender.

**Bounds.** A message is at most 5000 characters. A member below trust
level 1 starts at most 3 new conversations in a rolling day, any other
member 20; answering an existing conversation is never counted. The count
is taken under an advisory lock on the sender, so two requests cannot both
take the last place. Sends also stay under the forum's write rate limit
(`message.send`, 20 a minute).

**Who may send.** A signed-in member, with a CSRF token, not suspended
(`message.send` is a participation action: a suspended member reads their
messages and sends none, recorded as `suspended_user_block`). A block
either way refuses the message (ADR 0130); the refusal says only that the
member cannot receive the sender's messages. A member who blocks the other
sees a note instead of the answer form. The watched words and the link rule
screen a message as they screen a reply (ADR 0133): a block refuses it,
naming the words; a replacement rewrites it; a flag sends it and opens the
system's report on the message. Staff who moderate every thread are not
screened. An erased member takes no message (`gone`).

**Reading.** `GET /messages` lists the member's conversations, the one
moved last first, 25 a page, each with the other member, how many messages
wait and the first 140 characters of the latest. `GET /messages/:id` shows
the newest 30 messages oldest first (older ones by `before`), and is found
only by its two members: anyone else gets 404. Opening it with messages
waiting marks it read, and reads the inbox's notifications of it. `GET
/messages/new/:username` is the form that writes to a member, or a redirect
to the conversation the two hold; a profile links it unless the reader
blocks the member. Every message page is `private, no-store`. Erased
members are named by none of their names.

**Notifications.** Messages are a fourth kind of ADR 0078's notifications,
`message`, on in the inbox and by email unless the member turns either off;
the one-click unsubscribe takes the kind. The outbox's notification handler
notifies the recipient of the first message of an unread run only (the
function answers `first_unread`), so a burst is one notification and one
mail; the next run starts once the member reads the conversation. The
notification and the mail name ids only: the mail says a member sent a
private message and links the conversation, never the text or the sender.
A member's ignore silences these notifications as it silences replies
(ADR 0130), and the inbox leaves out those delivered before. The digest
stays about followed threads: a private message is mailed by its own
kind's switch, and repeating it in a digest would mail it twice.

**Realtime.** The outbox maps `direct_message.sent` to a hint,
`direct_message.update` with the conversation and message ids, on the
recipient's own `notifications:` channel and then on the sender's (their
other pages), which only that member may subscribe to.

**Reports.** A member reports the other member's message in a
conversation of theirs (`POST /messages/:id/:message_id/report`) through
the community workflow, as a post is reported: the report rate limit, the
command id, the `report.created` event and audit. `reports.target_type`
gains `message`. The queue shows such a report with a form, not the text:
`POST /moderation/reports/:report_id/message`, for staff holding
`report.view_queue` (CSRF, the moderation write limit, suspended staff
refused), reads the one message the report names through
`moderation_reported_message`, which records the audit
`direct_message.report_read` (the staff member, the message, the report,
never the text) in the same call. No staff page reads a conversation or a
message that was not reported.

**Privacy.** Nothing writes a message's text to an event, the outbox, a
notification, the audit log, a search document or a feed. The export
(`portability_export_parts` v15/v16) holds the member's conversations, the
other member's username and the messages the member wrote, never the other
member's messages (ADR 0074). Erasure (`privacy_revoke_user` v13/v14,
source `DirectMessage`) deletes the messages the erased member wrote and
their side of each conversation; the other member keeps their own
messages, their unread count is counted again, and a conversation nobody is
left in is deleted. A reported message that was erased reads as gone.

**Storage.** Migration 128 adds the tables, the functions
`community_message_start`, `_reply`, `_inbox`, `_conversation`, `_list`,
`_mark_read`, `_conversation_with`, `_for_report`, `_participant` and
`moderation_reported_message`, and new versions of the functions the
feature changes: `notification_list_inbox` and `notification_unread_count`
(v5/v6), `notification_type_preferences`, `notification_set_type_preferences`,
`notification_delivery_plan`, `notification_unsubscribe` and
`moderation_automod_record` (v3/v4), `privacy_revoke_user` (v13/v14) and
`portability_export_parts` (v15/v16). The shipped versions stay.

## Consequences

- The inbox and its unread count keep a direct-message notification while
  its message is in a conversation of the recipient's: one more branch of
  their source filter, a primary-key lookup per row.
- A conversation page costs the request prologue, the conversation, its
  messages, and the mark-read write when messages wait; no hot page
  changes, and the primary navigation links `/messages` without a query.
- Messages cannot be edited or deleted by their author; erasure is the
  way to remove them. Staff act on a reported message through the
  existing tools: resolve the report, warn or suspend the author.

## References

- [ADR 0074](0074-privacy-data-protection-legal-operations.md)
- [ADR 0078](0078-email-notification-delivery.md)
- [ADR 0118](0118-exceptions-are-gpforum-x-classes-required-attributes-are-declared.md)
- [ADR 0126](0126-sql-lives-in-postgresql-functions.md)
- [ADR 0127](0127-separate-runtime-role-for-the-function-api.md)
- [ADR 0130](0130-members-ignore-and-block-each-other.md)
- [ADR 0133](0133-watched-words-and-automod-rules.md)
