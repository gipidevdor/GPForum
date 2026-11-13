# ADR 0164: Demand-loaded clients and stored image previews

## Status

Accepted (2026-11-02), following the owner's performance optimization request.

## Context

Every default-layout page loaded all optional clients, including KaTeX when
mathematics was enabled even if no equation was present. Formula and embedded
player initialization also searched the entire document after fragment swaps.
Post images displayed the original upload, potentially several megabytes.

## Decision

The default layout loads htmx and one small enhancement loader. The loader
matches content capabilities, loads each local client once, and loads KaTeX
before its equation adapter only when an equation exists. New htmx fragments
and DOM insertions activate the same clients. Failed enhancements retain native
links, forms and escaped equation source. Formula and integration observers
process added subtrees, including the inserted root itself.

The existing media worker makes a separate aspect-preserving PNG with a
1280-pixel maximum side, using the configured system tool. It shares the
thumbnail's source read and existing pixel bounds. Output metadata is stripped;
images are never enlarged. Only outputs smaller than the source are stored.
The existing indexed PostgreSQL variant API and storage backend hold the new
`preview-v1-1280` variant; no schema change or per-post listing query is needed.

Inline images request `download?preview=1280`; their links still download the
original. Delivery authorizes the original first and then selects that one
fixed variant. Missing variants fall back to the original. Unauthorized and
withdrawn media cannot be retrieved through a preview or a conditional request.
Preview validators differ from original validators; range and HEAD delivery
continue streaming PostgreSQL assets. GET requests never perform conversions.

GIF, WebP and animated PNG retain their original representation. macOS sips
does not normalize EXIF rotation, so JPEGs containing EXIF retain their original
representation there; libvips can produce their previews. Existing processed
images retain their originals until processing is rerun. Previously stored
preview variants are reused without reading or converting their sources.

General navigation retains the existing server-rendered page lifecycle. The
current htmx actions continue replacing local fragments. This change introduces
no browser snapshot cache or history handling and changes no draft lifecycle.

## Operation and recovery

Restart web and media workers after updating. No database migration is needed.
The configured image tool and outbox worker are required to create previews.
Ordinary database backup, deletion and erasure already include variants.
Rolling back application code leaves these variants harmlessly stored and
restores original inline image URLs.

## Validation

Node tests cover conditional loading, dependency ordering, duplicate fragment
events, failure fallback and scoped DOM work. Native image-tool tests verify
dimensions, metadata stripping and shrink-only behavior. Worker tests check a
single shared source read and repeated-event reuse. PostgreSQL HTTP tests cover
approval, rejection, distinct validators, HEAD and byte ranges. Existing media,
avatar, permission-role and page-query-budget tests remain applicable.
See [performance evidence](../PERFORMANCE.md#browser-payload-and-image-previews).
