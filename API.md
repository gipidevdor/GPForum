# GPForum API Preparation

GPForum currently exposes SSR routes and JSON-compatible responses on selected
routes. The API posture is preparation-first: do not introduce a separate API
surface until contracts are explicit and tested.

## Versioning

Future REST routes should live under:

```text
/api/v1/...
```

Versioned APIs must preserve:

- stable JSON response envelopes;
- explicit authentication and authorization;
- CSRF-free token auth only for non-browser clients;
- browser routes continuing to use CSRF-protected sessions;
- event/audit consistency for writes.

## Internal Contracts

Until `/api/v1` exists, JSON compatibility is maintained by presenters and
controller response helpers. Existing JSON fields must not be renamed without a
compatibility test.

### Private composer browser routes

The composer uses the following session-authenticated routes. Request JSON with
`Accept: application/json`; native form responses remain available. Every draft
or preview response sends `Cache-Control: private, no-store`. POST requests need
the browser's CSRF field and pass the existing participation/rate-limit guards.
These routes do not introduce `/api/v1` or token authentication.

| Method and path | JSON response / input |
| --- | --- |
| `GET /drafts` | `{drafts: [...]}` for the current owner's unexpired drafts. |
| `GET /drafts/:draft_id` | `{draft: {...}}`; another owner's or expired draft returns 404. |
| `POST /drafts` | `{ok, status, draft, error}`; composer fields include `draft_id`, `draft_revision`, `kind`, category/thread context, title, `body_source`, visibility and `command_id`. |
| `POST /drafts/:draft_id/delete` | Result envelope; needs the current `draft_revision`. |
| `POST /composer/preview` | `{ok: 1, html}` from the canonical safe body renderer; accepts composer fields and does not save/read a draft. |

Revision zero creates a draft; subsequent saves/delete require its current
revision. A stale revision returns 409 and invalid input returns 400. An exact
save retry returns its previous acknowledgement. Use the returned revision and
publication command id for subsequent requests. Owner ids are supplied by the
session, never by the form. The [composer guide](docs/architecture/composer-drafts.md)
describes limits, native responses, expiry and atomic publication, including the
completed local HTTP, PostgreSQL, JavaScript and browser checks. Deployment and
release gates remain separate.

## Token Architecture

Future bot/mobile integrations should use a dedicated token boundary:

- token hashes stored server-side;
- scoped permissions through RBAC/ABAC;
- short-lived access tokens where possible;
- revocation audit;
- rate limits per token, actor, and IP class.

Session cookies remain the browser default.

### Notification badge browser route

`GET /notifications/summary` returns `{ "unread_count": 3 }` for the signed-in
member. The existing permission-aware unread query stops at 100; the interface
shows `99+` at that threshold. No inbox bodies or recipient identifiers are
returned. Responses use `Cache-Control: private, no-store`; anonymous requests
return 401, rate-limited requests 429, and unavailable storage 503. The route
shares the existing notification HTTP limit (120 requests per 60 seconds).

The navigation normally subscribes to the signed-in member's notification
channel over the same-origin `/realtime` WebSocket. Its snapshot and subsequent
`notification.badge` frames update the badge without HTTP polling. The page
advertises this transport only when the realtime listener is enabled. See
[the browser client lifecycle](docs/realtime.md#browser-notification-client).

If WebSocket is unsupported, unavailable or denied, this summary is the
fallback, at most once per minute while visible. Requests coalesce; hidden
tabs release their socket and timers. The inbox reuses its server-rendered
count until a snapshot or fallback updates it. An HTTP response begun before
a push cannot replace the newer count. Temporary failures retain the last
known badge; no notification data is persisted in browser storage.


## Community completion (ADR 0151)

All writes require the existing session, CSRF token, write throttling and a fresh
UUID `command_id`. JSON is selected with `Accept: application/json`; mutations
are PostgreSQL function calls with atomic authorization and command replay.

| Method | Path | Purpose |
| --- | --- | --- |
| GET/POST | `/admin/registration` | Staff policy, email-bound invitations and admission decisions. POST `operation`: policy/invite/revoke/approve/reject. |
| POST | `/c/:category_id/subscription` | `operation`: follow/mute/remove using the existing category subscription. |
| GET/POST | `/t/:thread_id/tools/poll` | Read/create/vote/close a single-choice poll. POST `operation`, with question/options (one option per line) or choice. |
| GET/POST | `/moderation/transfers` | Global thread moderators inspect history or move/split/merge. Forms accept source/target discussion links and comma-separated post numbers. |
| POST | `/moderation/transfers/:transfer_id/undo` | Checked reversal; intervening placement/audience changes may conflict. |

Individual ballots and invitation secrets are absent from public results. An
invitation secret is returned only on its first successful creation response;
replay returns its id. Staff-only pages and poll responses use no-store.
See [ADR 0151](docs/adr/0151-admission-polls-category-follows-and-thread-organization.md)
for bounds, audiences, rollback and privacy semantics.
