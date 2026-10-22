# ADR 0136: Bookmark Folders

## Status

Accepted. The owner asked on 2026-10-15 for the product features of
docs/PRODUCT_BACKLOG.md; A08 (advanced bookmarks, package PB-13) asked for
folders. Local PostgreSQL and HTTP checks pass; acceptance of this decision
does not establish release readiness.

## Date

2026-10-15

## Context

A member's bookmarks are one list, newest first, each with a note. With a
few dozen saved, the list is where a bookmark is lost rather than found.
The bookmark command (ADR 0126) is a commanded write around
`api.community_save_bookmark_v1` with its retries; changing its row for a
label is out of proportion, as it was for the reply link (ADR 0132) and the
thread tags (ADR 0135).

## Decision

A member may file a bookmark in a folder of their own naming, up to forty
characters: with the note when saving from a thread, and from the
bookmarks page afterwards ("Move"), where an empty folder takes the
bookmark out of its folder. The folder is a row beside the bookmark
(`bookmark_folders`, one per bookmark), written after the command through
`api.community_set_bookmark_folder_v1`, which files only the member's own
active bookmark. A write that fails leaves the bookmark as it is.

The bookmarks page names the member's folders with their counts
(`api.community_list_bookmark_folders_v1`) and lists one folder or all
(`api.community_list_bookmarks_v3`, the list of migration 062 with the
folder joined, filtered and returned). A folder is the set of bookmarks
filed under its name: there is no folder object, no rename and no delete;
taking the last bookmark out is the end of the folder.

## Consequences

- The bookmark command, its functions and its tests are untouched; filing
  costs one statement after a save that names a folder, and the bookmarks
  page one more statement for the folder list.
- A bookmark removed keeps its folder row until the bookmark is deleted
  (the folder row goes with it); restored, it is back in its folder.
- Erasure and export are unchanged: bookmarks are not exported today, and
  a folder holds only the words a member chose for their own list.
- `community_list_bookmarks_v1/v2` are retained (ADR 0126 section 4): the
  migration gate and the catalogue test hold them to the arguments of
  their day.
- Functions follow ADR 0126 and ADR 0127 (typed definer boundaries).
