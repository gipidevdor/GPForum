# ADR 0140: One Maximum Length for a Post Body

## Status

Accepted. A read-only review of main on 2026-10-15 found that a reply could
be any length and that the body renderer took quadratic time on some
input; the owner asked for every defect it confirmed to be fixed under the
ADRs. Unit, PostgreSQL and server-rendered checks pass; acceptance of this
decision does not establish release readiness.

## Date

2026-10-17

## Context

A post body is rendered to HTML when it is written, for a preview, and
again from source on reads (`ViewModel::Forum::Rows`), so what one body
costs is what a member can make every reader of its thread pay. Two things
left that cost open:

- `PostComposer` and `ThreadComposer` checked only that a body was not
  empty. Drafts alone had a maximum, 50,000 characters, written three times
  -- in `DraftStore`, in the preview controller and in the `forum_drafts`
  table (ADR 0128) -- so a thread or reply posted without a draft had none
  but the request size, above 25 MiB to let attachments through.
- `BodyRenderer` searched the rest of the body from each line that opens a
  fence, and the rest of a paragraph from each `[` for the link it might
  open: 4,000 lines of "```a" took over three seconds. The link search was
  quadratic too, though a fast C search kept a body of 50,000 characters
  near a tenth of a second.

## Decision

**One number, in one place.** `GPForum::Service::Forum::BodyLength` holds
the maximum, 50,000 characters, the number drafts already had: a draft must
be able to hold any body that can be published. A new thread, a reply, an
edit (`PostComposer`, `ThreadComposer`), a preview and a draft save
(`Controller::Forum::Drafts`, `DraftStore`) all ask it. A longer body is a
refusal on the `body_source` field, `body is too long`, a result value as
ADR 0118 asks; the forum controllers replace it with `forum.body_too_long`
in the reader's language, which names the limit. Lengths are characters, as
Perl counts a decoded string and PostgreSQL's `char_length` counts `text`.
Composers measure the trimmed body they store; drafts measure the text as
typed, which they store.

**The database enforces it too.** Migration 129 adds
`CHECK (char_length(body_source) <= 50000)` to `post_bodies` and
`held_posts`, beside the one `forum_drafts` has had since migration 103. The
Perl check gives the member a message; the constraint holds for every
writer, including ones that do not go through the composers -- an import, a
held post approved later, a script -- so the renderer's bound is a property
of the stored data. A write that reaches the constraint fails as a
`GPForum::X` like any other database failure; it is not a refusal, since
the Perl check comes first. No function changes, so no new `_vN`.

**The renderer reads a body in one pass.** Fences are cut in one walk over
the lines: lines after an opening line are held until a closing line, and
given back as prose when the body ends first. For links, the `](`, the `)`
after it and the first character a URL may not hold are found once and kept
while the next `[` still lies before them. No character is read more than a
fixed number of times, whatever the body holds; `t/709` counts the
characters read on adversarial bodies rather than timing them.

## Consequences

- A body is at most 50,000 characters everywhere, and changing the limit is
  one constant and one migration for the three constraints.
- Rendering a body is linear in its length, so the length bounds the work
  of a write, a preview and a read.
- The memo of rendered bodies is bounded by count, 2,048 entries; with the
  limit each entry is bounded too. Rendering on reads is left as is.

## Related Decisions and Implementation

- ADR 0118 (refusals and failures), ADR 0126 (SQL in functions and
  migrations), ADR 0128 (drafts and canonical preview).
- `lib/GPForum/Service/Forum/BodyLength.pm`,
  `lib/GPForum/Service/Forum/BodyRenderer.pm`,
  `migrations/003-evolution/129_post_body_length.sql`.
- Tests: `t/709-forum-body-renderer-work.t`, `t/710-forum-body-length.t`,
  `t/integration/postgres-post-body-length.t`.
