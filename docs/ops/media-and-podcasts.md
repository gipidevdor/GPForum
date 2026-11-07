# Images, video, audio and internal podcasts

New files, including profile pictures and their cropped variants, are stored
in PostgreSQL. Images and documents accept up to 25 MiB. Audio and MP4 video
accept up to 250 MiB. Profile-picture originals retain their separate 5 MiB
limit. `GPFORUM_MEDIA_MAX_MIB` can lower the audio/video limit to any integer
from 100 to 250. The shipped nginx limit is 251 MiB including the multipart
form; changing application settings does not edit an installed proxy config.

Each member also has an upload allowance: by default, 1024 MiB of source
bytes and at most 20 files awaiting scanning or content approval. The allowance
is shared by post attachments and profile uploads. An upload awaiting both
checks counts once. Removing an attachment from a post does not reset the
byte allowance: soft-deleted attachment records remain included. Administrators
can adjust both limits in the forum settings or deployment configuration.

## Deploy

Initialize a fresh database from the repository's current schema baseline
with the administrative configuration. An existing database must first follow
the supported schema/data migration procedure in [upgrade](upgrade.md);
`attachment-import` copies file bytes, not metadata or migration history.
Refresh the catalogue-based runtime API-role grants using the existing role
provisioning command, then restart the web service and the outbox worker. Set:

```sh
GPFORUM_ATTACHMENT_STORAGE=postgres
GPFORUM_MEDIA_MAX_MIB=250
GPFORUM_ATTACHMENT_OWNER_MAX_MIB=1024
GPFORUM_ATTACHMENT_OWNER_MAX_PENDING=20
GPFORUM_MEDIA_SOURCE_HOSTS="media.your-domain.tld partner.your-domain.tld"
```

Replace the source hostnames with actual approved sources. The default list is
empty: author-created originals can still be submitted, but external sources
are refused. Hostname matching is exact, without implicit subdomains or URL
fetches. The source must use HTTPS and its standard port, without credentials.

Ensure the installed antivirus can scan 250 MiB inputs: clamd's
`StreamMaxLength`, `MaxFileSize` and `MaxScanSize` must cover the upload limit.
Enable clamd's `AlertExceedsMax yes` so exceeded scan limits cannot silently
produce a clean verdict. Configure the equivalent limits and exceed-limit
alert when using a command scanner.
Exceeding a scanner limit must remain an error, never a clean result. Larger
media scans run in the worker; they are not forced into the short web-request
deadline. A scanner error leaves the file unpublished and eligible for retry.

## Publish and manage from the GUI

Open **Menu → Photos, video, audio and podcasts**. Enter a title, description
and category; publishing continues to the upload form. For an existing post,
use **Attach file** beside Reply. The form shows formats and configured limits,
asks for provenance and rights, and keeps a refused upload retryable.

The private upload screen lists the author's files, including those awaiting
review, with their status and any rejection reason. It offers removal and
continuation through older files. Only approved, clean and available files have
preview/download links. If the text itself is held, its pending-page entry offers
attachment management once published. Podcast episodes use prerecorded audio.

## Publication and rejection

The uploader chooses original authorship or an authorized source, confirms
sharing rights, and supplies the source link for external content. Every new
file is held for review. Open **Menu → Moderation → Photos and uploads to
review** as a member with the global `thread.moderate` permission. The menu is
visible in every page header, including on iPad. Its destination is
`/moderation/media`; the regular moderation-review page also links there.

Inspect the actual content and verify provenance before approval. The author
cannot approve their own upload. A decision needs an explanation, and approval
also needs a clean malware scan. Until both gates pass, the public attachment
route and profile-picture processing keep the content unavailable. Private
staff previews become available after the scan. A rejection blocks exact
SHA-256 reuploads; it does not detect visually similar or modified files.

The reviewer must reject prohibited, inappropriate or unverified content.
These controls do not automatically determine legality or recognize all harmful
material. New policy adoption also requires a separate review of legacy files;
importing bytes does not attest their provenance or approve their content.

## Share media and create a podcast

Attach approved images to show them inside posts. MP4 video receives a player
with playback controls and seeking. Supported audio containers are MP3, M4A,
Ogg with Opus/Vorbis, and WAV. Actual playback depends on the browser's codec
support; the server does not transcode uploads.

The media worker also creates a proportional inline image preview, at most
1280 pixels on its longest side, when its PNG encoding is smaller than the
source. Preview bytes and metadata use the existing PostgreSQL variant storage.
Clicking an image still opens the original. Preview requests enforce the
original's permissions and approval before streaming; nothing is converted
during page loading. The existing system image tool and outbox worker must be
enabled. Old or unprocessed uploads fall back to the original until processing
is rerun. Animated images retain their original playback. On macOS sips, JPEGs
with EXIF also keep their original representation to preserve display rotation.

For an internal podcast, create a discussion for the series. Add each episode
as a post containing its title and description, then upload its prerecorded
audio file to that post. Approved episodes receive audio players. Choose the
discussion's visibility and category permissions for its intended audience;
the media route applies those permissions on every request. No recording or
external podcast feed is added by this workflow.

## Bring old files into PostgreSQL

Run from the code directory with the intended database and attachment-root
environment already loaded. First validate without writing:

```sh
bin/gpforum attachment-import
```

Then copy the checked objects:

```sh
bin/gpforum attachment-import --apply
```

The import includes originals, thumbnails and the 64/128/256-pixel avatar
variants. Each object commits independently after its size, checksum and chunk
completeness are checked. Interrupted imports can be rerun; complete objects
are skipped. A missing or changed file stops the run with its key. Live legacy
files are retained for recovery; explicit user deletion or erasure also removes
their retained copies. Already-deleted metadata is excluded from import.
Never remove that tree until import and an independent backup/restore
verification have succeeded.

New PostgreSQL objects are included in normal database dumps, WAL archiving
and recovery. Keep the filesystem backup for any objects not yet imported.
The existing backup command continues archiving that tree as well. See
[backup and restore](backup-and-restore.md) for coordination while filesystem
writes remain active.
