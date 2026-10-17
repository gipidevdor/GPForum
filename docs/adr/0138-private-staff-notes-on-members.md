# ADR 0138: Private Staff Notes on Members

## Status

Accepted. The owner asked on 2026-10-17 for a round of feature completion
under the ADRs, deciding product details along the way; this is backlog
F04 (PB-18). Unit, PostgreSQL and server-rendered checks pass; acceptance
of this decision does not establish release readiness.

## Date

2026-10-17

## Context

Moderators kept what they knew about a member -- a warning given in
private, a pattern seen across reports, an appeal heard -- in action
reasons and report resolutions, which belong to one action or one report,
or nowhere. The next moderator reading a report about the same member
started again. Such a note is about a person and is written by staff for
staff: it must never reach the member, other members, any public surface
or anything a member can export, and it must not outlive the member's
erasure.

## Decision

**A note is a row of its own.** `public.member_notes` holds the member it
is about, its author, its text (1 to 2000 characters, plain text, its
lines kept), when it was written, and who last edited it and when. It is
not a post, an event or a message: nothing writes it to the event log, the
outbox, a counter, a search document or a notification, so no feed,
search, JSON answer of a member's page or realtime message can carry it.
Only three functions read it: the member's notes, the notes beside
reports, and the export, which leaves it out (below).

**Permissions.** Two new permissions, held through the role-binding model
of ADR 0070 at global scope only: `member_note.view` reads the notes and
`member_note.write` adds, edits and deletes them. The owner role made by
`gpforum admin create` gets both (`Bootstrapper::default_permissions`); an
operator gives a moderator role either through the roles page. Reading
without view shows nothing of the notes, not even that they exist; a write
without write is 403. A note is a shared staff record, so any holder of
`member_note.write` edits or deletes any note, not only their own; the
note shows who wrote it and who last edited it.

**Where staff read them.** On the member's admin page
(`/admin/users/:user_id/roles`, which needs `admin_console.view`): every
note, newest first (the latest 100), with author and time, last editor and
time, a form to add one, and for each note an edit form (a native
`<details>`) and a delete form behind the danger confirmation. Beside each
report in the queue (`/moderation/reports`): the member the report is
about -- the profile reported, or the author of the post or thread
reported -- with their three newest notes, how many there are in all, a
link to the admin page and the add form. The queue reads every report's
notes in one call (`moderation_member_notes_for_reports`), so the page
costs one statement more, not one per report. A report about an erased
member shows no block. Notes that cannot be read (the function failing)
are logged as a warning and the page says so, rather than the report
queue or the admin page failing with them.

**Writes.** `POST /moderation/members/:user_id/notes`,
`.../notes/:note_id` (edit) and `.../notes/:note_id/delete`, through the
moderation write path: a CSRF token, the global binding, the moderation
write rate limit (20 a minute), a uuid path id (404 otherwise), and an
active account: a suspended staff member is refused (403) and the refusal
recorded as `suspended_user_block`. The forms work without JavaScript and
answer with a redirect to where they were sent from (a safe `return_to`,
else the member's admin page) and a notice, or JSON (201 for an
addition). The add form's command id is the note's id, so a form sent
twice adds one note (`replayed`); an id another note holds is a conflict.
An edit to the same text changes nothing (`unchanged`). A note is edited
and deleted only under the member it is about.

**Audit.** Every addition, edit and deletion is audited
(`member_note.added`, `member_note.edited`, `member_note.deleted`, target
`member_note`), with the actor, the member and the text's length, never the
text: the audit log is read more widely and kept longer than a note, and a
text kept there would survive its deletion and the member's erasure.
Reading notes is not audited: ADR 0074 asks that staff access to sensitive
moderation records SHOULD be logged, and a page view writing an audit row
would make every admin and queue page a write; the permission is the
control.

**Privacy.** ADR 0074 says an export MUST NOT include internal moderation
notes not legally required, and other users' private data. The export
(`portability_export_parts`) is unchanged: it has no notes about the
member and none they wrote as staff about others. Erasure deletes every
note about the erased member (`privacy_revoke_user` source `MemberNote`);
notes an erased staff member wrote about others stay, shown under the
anonymized account, since they are about those members. A note cannot be
added about an erased member.

**Blocks** (ADR 0130) do not apply: a member's ignore and block list is
theirs, and staff notes are not an interaction with them.

**Storage.** Migration 125 adds the table and the functions
`moderation_member_note_add`, `_edit`, `_delete`, `moderation_member_notes`
and `moderation_member_notes_for_reports`, each an invoker `_v1` behind its
definer `_v2` boundary, and `privacy_revoke_user` v11/v12 (ADR 0126, ADR
0127). Refusals are result values (`invalid`, `not_found`, `conflict`,
`unchanged`, `replayed`); Perl normalizes the text, builds the audit
records and reads the results.

## Consequences

- The report queue reads one more statement for a reader holding
  `member_note.view`, and none for one without it. No member-facing page
  changes, so the hot pages' budgets are untouched.
- Notes have no history: an edit replaces the text, and only the audit
  log says that it changed and by whom.
- Ordering is by the time written to the second, then by id; two notes in
  the same second may list in either order.

## References

- [ADR 0070](0070-permission-matrix-authorization-rules.md)
- [ADR 0074](0074-privacy-data-protection-legal-operations.md)
- [ADR 0118](0118-exceptions-are-gpforum-x-classes-required-attributes-are-declared.md)
- [ADR 0126](0126-sql-lives-in-postgresql-functions.md)
- [ADR 0127](0127-separate-runtime-role-for-the-function-api.md)
- [ADR 0130](0130-members-ignore-and-block-each-other.md)
