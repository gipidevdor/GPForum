# ADR 0144: Profile Pictures, Cropped by the System's Image Tool

## Status

Accepted. The owner asked on 2026-10-17 for a round of feature completion
under the ADRs, deciding product details along the way; this is backlog
C04 (PB-13). Unit, PostgreSQL and server-rendered checks pass; acceptance
of this decision does not establish release readiness.

## Date

2026-10-17

## Context

Profiles and posts drew every member as the initial of their name on one of
three tints. Members asked for a picture of their own. A picture is an
upload like any other -- it must be validated and scanned for malware (ADR
0108) -- but unlike an attachment it is shown to everyone, beside every post
the member wrote, at a few small sizes, and it is personal data that erasure
must take away.

The media pipeline had a step for images, but it copied the original under
a `thumbnail` key: nothing in GPForum decodes or resizes an image, and no
image library is installed. A Perl decoder for JPEG and WebP is out of the
question, and an XS library (Imager, GD) would be a new build dependency on
every host. The precedent is the antivirus: the owner chose to rely on the
free tool the operating system's package manager installs, and bundle
nothing.

## Decision

**A picture is an attachment the member owns, linked to their profile.** It
goes through `Attachment::UploadPipeline` -- the validator, the storage, the
scan at upload or, with a slow scanner, the attachment worker -- after a
check of its own: a PNG, GIF, JPEG or WebP (sniffed from the bytes, never
the client's type), at most 5 MB, at most 8,000 pixels a side and 40
megapixels, the size read from the header before any tool decodes it, so a
decompression bomb never reaches one. The existing download rule already
serves a profile-linked attachment to its owner only; nobody else ever gets
the original.

**The system's image tool crops it.** `GPFORUM_IMAGE_TOOL=system` (the
default; `none` in the test environment, and the operator's switch to turn
pictures off) takes libvips' `vipsthumbnail` where the OS layer says the
package puts it -- Debian and Ubuntu `libvips-tools`, FreeBSD `vips`,
Homebrew `vips` -- and on a Mac without it, the `sips` every Mac has.
Without either, the settings page says pictures are not available and
nothing is accepted. The tool runs without a shell, on a private copy in a
private temporary directory, within one 20-second deadline for the picture,
and the directory is removed whatever happens. A tool that exits with an
error, is killed by a signal or writes anything but a PNG of the exact size
asked for has not read the picture; one that cannot start or outruns its
time is unavailable, and the picture waits for the media worker's retry.

**A server-side centre crop to a square, at 64, 128 and 256 pixels.** No
client-side crop library and no crop form: the picture is cropped about its
centre to the largest square it holds, then scaled, which suits the
portraits and logos pictures mostly are, and needs no JavaScript.
`vipsthumbnail --size NxN --smartcrop centre` does it in one run a side and
honours EXIF orientation; `sips` crops then resamples in two runs, and does
not. The squares are PNG -- lossless, transparent, written by every tool --
and each is rewritten by `Infrastructure::ImageBytes::plain_png` with only
the chunks that draw it (`IHDR`, `PLTE`, `tRNS`, `IDAT`, `IEND`), so no
EXIF, location or comment of the original survives whatever the tool kept.
They are stored as the attachment's variants `avatar_64`, `avatar_128` and
`avatar_256`. Posts show 64 with 128 for dense screens, the profile 128 with
256.

**The media pipeline does it.** When the scan answers at once (clamd, or
scanning off) the upload is cropped in the request and shown on the
redirect. Otherwise `Attachment::MediaProcessor`, on the clean scan's event,
hands an upload waiting to be a picture to `Community::Avatars::process`
instead of making its thumbnail. Both paths are idempotent: a redelivered
event finds the picture already shown.

**One row says what a member shows.** `public.member_avatars` holds the
attachment shown (with since when) and the one waiting (`checking`, or
`unreadable` once the tool failed; `refused` is read from the attachment's
scan). The picture shown stays until the new one is ready; a picture
replaced, removed, or found unreadable is discarded: its files are deleted,
then its attachment row is marked deleted with the attachment's own event
and audit. An infected upload is never offered and stays quarantined as ADR
0108 keeps it.

**Shown beside the name.** The profile and the thread page show the
picture where the initial was, through one partial
(`components/avatar`). The thread page reads it with the posts: new
versions of the two post reads wrap the shipped ones, keeping their order,
and join the author's row, so the page's statement count and budget are
unchanged; the profile reads one more statement. The cached post fragments
key on the picture shown. The picture's address,
`/avatars/:user_id/:avatar_id/:size`, names the picture shown, so a new one
gets a new address: it answers with an ETag and an hour of public caching,
`nosniff` and a CSP that allows nothing. An address of a picture since
replaced -- a page cached before the change -- answers with the one shown
now, cached a minute; a member who shows none answers 404. It follows the
forum's access like any page: it is no more private than the profile.

**Members remove theirs; staff remove one, audited.** The settings page
(`/settings/avatar`) uploads, replaces and removes, with CSRF and the churn
limit of ten a minute; a suspended member uploads none but may remove
theirs. Staff holding `avatar.moderate` globally see a form on the member's
profile that removes the picture they saw (named in the form, so one
uploaded since is not removed unseen), with an optional reason of up to 500
characters; the removal is audited as `avatar.removed` with the member and
the reason, a suspended staff member is refused, and the member may upload
another. The permission is part of the bootstrap role.

**Erasure and export.** Erasure deletes the files of every upload the
member linked to their profile, then `privacy_revoke_user` (`Avatar`)
deletes the row and marks those uploads deleted. The export says which
picture is shown, since when, and what waits; the upload itself is among
the member's attachments. Pictures appear in no search document, feed,
event payload of their own, outbox fan-out or realtime message.

**SQL in functions.** Migration 131 adds the table and
`community_avatar_offer`, `_settle`, `_remove`, `_status`, `_image` and
`_objects`, each an invoker implementation behind its definer boundary (ADR
0127), the post reads `forum_thread_page_posts(_scoped)` v3/v4,
`privacy_revoke_user` v17/v18 and `portability_export_parts` v19/v20.
Refusals are result values; Perl sniffs, measures, runs the tool, stores
the files and reads the results.

## Consequences

- An installation without libvips (or a Mac) offers no pictures until the
  operator installs it; nothing fails.
- A page cached before a picture changed shows the new picture through the
  old address within a minute, and a removed one stops answering at once:
  the cached page shows a missing image until it expires (about a minute).
- Shared caches may keep a removed picture's bytes for up to the hour of
  their `max-age`.
- Each upload runs the tool three times (four with `sips`) on a picture of
  at most 40 megapixels; the churn limit bounds it per member.
- Photos taken sideways keep their EXIF turn only with `vipsthumbnail`.

## References

- [ADR 0074](0074-privacy-data-protection-legal-operations.md)
- [ADR 0108](0108-uploads-scanned-by-the-system-antivirus.md)
- [ADR 0118](0118-exceptions-are-gpforum-x-classes-required-attributes-are-declared.md)
- [ADR 0126](0126-sql-lives-in-postgresql-functions.md)
- [ADR 0127](0127-separate-runtime-role-for-the-function-api.md)
- [ADR 0130](0130-members-ignore-and-block-each-other.md)
- [ADR 0138](0138-private-staff-notes-on-members.md)
