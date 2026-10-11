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
