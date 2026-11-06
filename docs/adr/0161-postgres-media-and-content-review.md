# ADR 0161: PostgreSQL Media and Content Review

## Status

Accepted. Amends the media persistence requirements and implementation gaps
in ADRs 0049, 0050, 0053, 0068, 0086 and 0091.

## Date

2026-11-01

## Context

Members need inline images, MP4 video, audio and internal podcasts made from
prerecorded episodes. Audio and video require at least 100 MB per file.
The operator chose PostgreSQL for uploaded bytes, including original and
cropped profile pictures, and requires provenance checks and rejection of
inappropriate material before publication.

## Decision

New uploads use PostgreSQL by default. Audio/video accept 250 MiB, configurable
between 100 and 250 MiB; images and documents retain 25 MiB. The HTTP request
limit includes one additional MiB for the multipart form. nginx ships 251m.

Objects are immutable, logged rows plus one MiB `bytea` chunks. The composite
primary key answers random reads. `STORAGE EXTERNAL` avoids spending CPU
recompressing media; PostgreSQL still provides TOAST, WAL, crash recovery,
physical/logical replication and consistent database backups. Large Objects
are unnecessary at this limit and would introduce a separate ownership and
cleanup lifecycle. See [PostgreSQL TOAST](https://www.postgresql.org/docs/current/storage-toast.html).

Foreign keys and indexed ownership cascade byte deletion with attachment metadata; variant deletion removes its binary object in the same transaction.

Creation, chunks, completeness validation, attachment metadata, provenance,
links, events and command replay share the schema connection and transaction.
SHA-256 is computed incrementally and checked again during storage. Partial
objects never become readable. Binary values are bound as `PG_BYTEA` and are
redacted from query observations. No full-size string is needed on the normal
upload or HTTP playback paths. The HTTP asset caches one MiB and supports
closed, open and suffix ranges, conditional requests and HEAD without keeping
a transaction open for a slow client.

Every new upload requires a rights attestation and either original authorship
or an HTTPS source whose exact hostname is authorized by the operator. Source
URLs are never fetched. This declaration is evidence for review, not proof of
authorship. A separate global moderator must verify provenance and content
before publication, giving a reason. Malware scanning remains a separate gate.
A trigger prevents later clean scans from publishing pending or rejected
files. Staff previews require global moderation, a clean scan and a private
route with no-store caching. Rejected hashes prevent exact reuploads; changed
content still requires a new review. Decisions are audited transactionally. Advisory lock class `2026110101`
serializes content decisions sharing one SHA-256, so withdrawing duplicate
files takes locks in one consistent order.

This is a human review workflow with technical gates, not an automatic
classifier or a guarantee that all unlawful or inappropriate content is
recognized. No perceptual hashing, external content-analysis service or
transcoding is claimed. Already-published legacy files retain their existing
review status; an operator must review those separately when adopting a new
content policy.

An internal podcast is a discussion used as a series, with a prerecorded audio
episode attached to each post and the episode title/description in that post.
The existing forum permissions control the series and every media request.
There is no browser recording, RSS syndication or automatic conversion.

## Compatibility and operation

The new storage reads existing filesystem objects during migration. The import
command checks size and SHA-256, copies in bounded chunks, resumes by keyset and
never removes originals. It imports originals and derived variants, including
the three profile-picture sizes. Existing backups continue including the
legacy attachment tree. PostgreSQL contains new upload bytes from the switch
onward; legacy bytes join the same backup/recovery lifecycle after import.

The filesystem backend remains available for rollback compatibility. Its older
upload path does not carry the PostgreSQL streaming-memory guarantee. A switch
back requires exporting database objects first; changing a setting alone does
not move bytes.

Initialize the current schema baseline before starting web and worker
processes, and reapply the catalogue-based API role grants. ADR 0162 requires
an empty database and refuses earlier migration histories; there is no
schema/data import for those histories. The binary import only copies files
whose metadata is already present in the current schema. Follow the
[upgrade guide](../ops/upgrade.md).
Retain these tables, their functions and provenance decisions during any
application rollback; follow the database compatibility guidance for that release.

## Validation

Unit tests cover format sniffing, 25/100/250 MiB boundaries, rights declarations
and source hostname spoofing. PostgreSQL integration tests exercise an actual
file above 100 MiB, binary round trips, indexed seeks, atomic rollback,
immutability, moderation, audit entries and cascading cleanup. HTTP tests cover
range playback, access checks, private previews and the media markup.

The development NYTProf run on 2026-11-01 exercised real 101 MiB file storage,
indexed reads, rollback and review scenarios: 42 assertions passed in 6.22 s
end to end, with 163.2 MiB maximum resident memory for the test process. Timing
includes the temporary PostgreSQL cluster and fixtures; it describes this
local verification run, rather than production throughput.
