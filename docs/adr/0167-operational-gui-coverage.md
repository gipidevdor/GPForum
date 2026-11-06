# ADR 0167: Operational GUI coverage

## Status

Accepted (2026-11-02), following the owner's request to connect every forum
function to the GUI, including the actions inside a page.

## Context

A menu of standalone pages does not prove that their operations are usable.
Starting a private conversation required finding a profile first; media uploads
were buried in a post's edit sheet; signature data had no visible entrance.
An author could also lose sight of a file awaiting approval because it was not
included in the public attachment list.

## Decision

The inbox and Menu expose **New message**, with a recipient form that leads to
the existing conversation or first-message form. Recipient lookup changes no
message or notification state.

The Menu exposes **Photos, video, audio and podcasts**. This starts the normal
discussion composer with the attachment continuation selected. A successful
HTML publication leads to its first post's upload screen. JSON creation keeps
its existing contract. Text held for moderation leads to the pending page;
once published, that page links to attachment management. Podcast episodes
remain prerecorded audio attachments under the existing content rules.

Each editable post exposes **Attach file** directly. Its private screen uses
the existing upload/delete workflows and provides format, size and provenance
controls, retry after validation failure, the author's file metadata, review
status and reason, and removal of unpublished uploads. It checks post visibility,
ownership and participation before showing private data. A fresh command is
issued on retry. Downloads and moderation independently authorize every byte.

The metadata read is one fixed PostgreSQL call, scoped to post and file owner,
without storage keys or bytes. It returns 50 items and one continuation marker,
using a link-id cursor and `(created_at, attachment_link_id)` ordering. An online
partial covering index supports this order for post links. Ordinary thread and
category pages gain no query.

Each post's More actions exposes a signature page. Existing archive visibility,
rate limits and signature verification apply before display. Signature JSON and
public keys remain independently downloadable; missing signatures are stated.

The GUI coverage guard walks the actual router, including generated routes,
and checks menu, link, form and browser-enhancement references. Generated form
URLs require both a producer and a consuming form. Delivered tokens and login
redirects have source witnesses. Protocol endpoints have an explicit reason
instead of an invented human-facing control. These structural checks complement
the existing domain tests and the PostgreSQL workflow tests.

## Operation and validation

Apply migrations 2035 and 2036, refresh catalogue-based runtime-role grants and
restart workers. The read function is additive; the index builds concurrently.
Application rollback can retain both without changing member or file records.

Validation covers native HTML media creation, refused-file retry, actual upload,
private pending-file management, deletion, 50/5 item continuation, forged cursors,
foreign ownership, new-recipient entry and unknown recipients, signature JSON
compatibility and private-post refusal. Existing hot-page query budgets and
API-role/catalogue checks run against isolated PostgreSQL. No LAN listener or
persistent preview database is needed.
