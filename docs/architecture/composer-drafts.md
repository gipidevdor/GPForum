# Composer Drafts and Preview

[ADR 0128](../adr/0128-private-composer-drafts-and-canonical-preview.md) records
the decision. This guide describes the implementation in the current change. Local
behavior checks pass; deployment and release gates remain separate.

## Browser workflow

Signed-in authors can save an unpublished thread or reply, list their drafts,
resume one and delete it. A thread draft retains title, category, body source and
intended visibility; a reply draft retains its thread, body source and intended
visibility. Drafts can be incomplete, including an empty body or an unselected
thread category. Publication still requires valid post input and current posting
permissions.

Save and Preview are native form buttons. Without JavaScript, Save redirects to
the restored composer; Preview returns the composer with its rendered body and
preserves the submitted fields. Preview alone does not save work. The drafts
page provides native resume links and CSRF-protected delete forms.

`assets/js/composer.js` progressively enhances those forms. Input schedules an
autosave after 900 milliseconds and a preview after 350 milliseconds. Saves run
one at a time; typing during a request is sent after its acknowledged revision
is known. A lost acknowledgement keeps the exact request for retry. A conflict
stops autosave, retains the author's current text and offers a link to the saved
draft. Save/preview failures have visible status messages. Preview requests
discard responses superseded by newer input or a replaced composer. Publication
waits for an acknowledged save before replaying the original form submission.
The script initializes composers inserted by HTMX as well as initial SSR pages.
No `localStorage`, IndexedDB or offline draft cache is used.

## HTTP contract

These are browser session routes with optional JSON responses, not a public
versioned integration API. See [API.md](../../API.md). Ownership is taken from
the current session. All five routes return `Cache-Control: private, no-store`;
POST requests require CSRF and the existing write guards.

| Method and path | Route name | Result |
| --- | --- | --- |
| `GET /drafts` | `drafts` | Owner's unexpired draft list; JSON `{drafts: [...]}`. |
| `POST /drafts` | `draft_save` | Save a revision; JSON `{ok, status, draft, error}` or native resume redirect. |
| `GET /drafts/:draft_id` | `draft_resume` | Restore an owner draft; JSON `{draft: {...}}` when requested. |
| `POST /drafts/:draft_id/delete` | `draft_delete` | Delete the expected revision; JSON result or redirect to drafts. |
| `POST /composer/preview` | `composer_preview` | Render the submitted body; JSON `{ok: 1, html}` or native composer with preview. |

Save accepts `draft_id`, `draft_revision`, `kind`, `category_id`, `thread_id`,
`title`, `body_source`, `visibility` and `command_id`, in addition to the form's
CSRF field. `kind` is `thread` or `reply`. A reply has a thread id and no category
id; a thread has no thread id. UUID spelling, revision, source lengths and
context are validated. Delete needs `draft_revision`; preview uses composer
fields without consulting draft storage. `Accept: application/json` selects
JSON. Invalid input returns 400, an inaccessible draft/target 404, and a stale
revision 409; ordinary authentication, participation and throttling errors also
apply. The acknowledged draft contains the current revision and server-selected
publication `command_id`, which the client must use for subsequent requests.

## Persistence and publication

`DraftStore` binds parameters to the `forum_draft_find`, `forum_draft_list`,
`forum_draft_save`, `forum_draft_remove` and `forum_draft_purge` catalogue
operations. Migration 103 provides the fixed-search-path versioned routines
and their definer entry points. There is no ORM draft-storage fallback. The
runtime login receives only catalogue execution grants under
[ADR 0127](../adr/0127-separate-runtime-role-for-the-function-api.md).

PostgreSQL serializes an owner's save/quota checks and locks an existing draft
for revision comparison. Revision zero creates; each new accepted snapshot
increments the revision. An exact retry of a previous save is acknowledged
without another revision or expiry extension. Saving unchanged content at its
current revision refreshes retention without increasing that revision. Changing
a saved draft's kind or reply thread is refused. At most 100
live drafts belong to an owner; titles and bodies have 300/50,000-character
limits. The draft stores source only, not preview HTML.

The controller saves submitted content before calling `PostingWorkflow`.
Publication uses the acknowledged revision and command id. The command
fingerprint includes the draft id and authored content, while the expected
revision is checked for a new publication. This permits retrying a native
publication whose own presave advanced the submitted revision. The stored routine
checks the locked draft and consumes it in the same transaction as a successful
thread/reply write. Refused publication retains the draft. Successful command
replay remains possible after consumption, while stale revisions and changed
command payloads conflict. This extends the
[posting workflow](posting-workflow.md), rather than introducing a second
publication path.

Preview authorizes the current category/thread and applies the same safe
`BodyRenderer` and `forum.post.body` render policy as posts. It renders the
submitted body only, makes no persistence call and creates no notification or
event. Saving or previewing a visible locked thread does not authorize posting
to it; publication rechecks the existing domain rules. The supported markup
subset is unchanged.

## Personal data and retention

Draft content and its account/context identifiers are personal data collected
to restore an author's unpublished work. Ordinary application access is
owner-only; there is no staff draft-reading product route or public projection.
Database/backup administration retains its existing privileged access.

A stored save sets expiry to 30 days after that save. An unchanged snapshot
submitted at the current revision also refreshes retention; an exact retry of
a previous save does not. Expired drafts
are excluded from list/resume and member export before physical cleanup. The
hourly `forum_drafts` scheduled job removes expired rows in bounded batches,
100 by default and at most 1,000; operators should monitor the reported deleted
count and failed runs. Saving also removes that owner's expired rows before
checking their quota.
Manual deletion checks the current revision.

The member bundle includes a `drafts` array and manifest `counts.drafts` for the
requester's unexpired drafts, excluding internal save-retry fields. Account
erasure deletes all owned drafts through the versioned `privacy_revoke_user`
operation with source `ForumDraft`, subject to the existing erasure/hold process.
Draft source is removed, not retained as an anonymized published discussion.
Backups follow the separate operator retention/restore policy. See the
[privacy workflow](privacy-workflow.md) and
[scheduled-jobs runbook](../ops/scheduled-jobs.md).

Migration 103 is additive and is not reversed when rolling back application
code. An older build lacks draft export, erasure and expiry support. Once drafts
exist, use a forward fix or preserve those draft-aware workflows throughout a
rollback; leaving the table intact does not by itself preserve their contract.

## Verification

HTTP/native composer coverage lives in `t/650-forum-drafts-web.t`; the real
PostgreSQL flow is `t/integration/postgres-drafts-web.t` and requires the usual
`GPFORUM_TEST_DSN` test database. The latter exercises publication through the
stored routines rather than a memory draft store.

JavaScript behavior checks use Node's built-in test runner:

```sh
node --test t/js/composer.test.cjs
```

Ubuntu CI runs this command explicitly. Node is a development/CI tool only;
there are no npm packages, application build step or Node runtime dependency.
`make check` is unchanged. On 2026-10-11, the complete local `make check` passed
syntax, the critic baseline ratchet, perltidy, architecture checks and the general
suite of 503 files / 16,269 assertions with PostgreSQL integration tests skipped;
the complete PostgreSQL integration tier separately passed 99 files / 10,719
assertions on a disposable PostgreSQL 18 instance, and the JavaScript suite
passed 10 checks. The integration tier includes owner
isolation, quota/expiry, export/erasure, atomic publish/refusal preservation,
exact retries and restricted runtime-role checks. A browser smoke check passed
Italian autosave, canonical safe preview, the draft list and source restoration.
Native Save/Preview and EN/IT rendering are covered by the HTTP tests. These
checks do not establish staging/production readiness.

The HTTP draft/preview flow was also captured with NYTProf using
`script/profile-nytprof -- -Ilib -It/lib t/650-forum-drafts-web.t`; all 56 HTTP
checks passed in that run. Its persistence collaborator is a test double;
database correctness and query budgets are covered by the separate real
PostgreSQL tier.
