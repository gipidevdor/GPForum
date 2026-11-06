# ADR 0141: No Session Token in a Shared Page

## Status

Accepted. A read-only review of main on 2026-10-15 found that a page served
from the public cache carried the first visitor's CSRF token and that the
token outlived sign-in; the owner asked for every defect it confirmed to be
fixed under the ADRs. Unit and server-rendered checks with two sessions
pass; acceptance of this decision does not establish release readiness.

## Date

2026-10-17

## Context

`Web::PublicHttpCache` renders a public page (categories, a category, a
thread, tags) once and serves that rendering to every visitor who is not
signed in (ADR 0019). The page's footer has two forms, the language and the
theme, and each carried `csrf_field`. So:

- the token in the stored page was the first visitor's, whose session the
  render had just given one; every other visitor posted a token their
  session did not hold and was refused with a 403, and the first visitor's
  token was published to all of them;
- a page that showed a flash message ("Theme updated") was stored with it
  and shown to the visitors after, while a visitor sent back to a page
  already stored never saw their own;
- `Web::CookieSession->replace_login` kept the session's `csrf_token`, so a
  token read before sign-in -- off a page, or from a shared browser -- was
  good for the member's session after it; and sign-out expired the cookie
  but left the member's keys to the page that said they had signed out,
  which was drawn as theirs, logout form included.

A token cannot be both in a page shared by every visitor and bound to one
of them. The ADR 0053 rule stands: every state-changing request is
CSRF-protected, and session-authenticated requests stay CSRF-resistant.

## Decision

1. **A shared rendering carries no token.** `PublicHttpCache` renders the
   page it stores with the `gpforum.shared_render` stash value set, and
   the `csrf_field` helper (`Bootstrap::Security`) writes nothing then. The
   render puts no token in the visitor's session, so a public response
   sets no session cookie.
2. **A visitor who is not signed in may stand on the origin instead.**
   `Web::Access->csrf_invalid` accepts the session's token as before.
   Without it, it lets a request through only when the session is not
   signed in and `Web::Access->same_origin` says the browser posted it from
   this site: `Sec-Fetch-Site: same-origin` when the browser sends fetch
   metadata (`same-site`, `cross-site` and `none` are refused); otherwise
   an `Origin` equal to the request's own origin or to the origin of
   `public_base_url`. A request that names neither, or `Origin: null`, is
   refused. Another site cannot set those headers on a browser's request,
   which is what makes them a CSRF defence. The rule is one for every
   handler, so any form a shared page carries works, today the language and
   the theme.
3. **A signed-in member always needs the token.** They are never served a
   cached page, and their requests are judged by the token of their own
   session alone, wherever they come from.
4. **The token is rotated at sign-in and at sign-out.**
   `CookieSession->replace_login` deletes `csrf_token` with the login keys;
   `CookieSession->sign_out`, which logout now calls instead of expiring
   the cookie, empties the session and keeps it a session, so the page that
   says the member signed out is a visitor's page whose forms carry a token
   that session holds. The masked token `Bootstrap::Security` keeps for the
   response (one mask per response, against BREACH) is kept with the
   session token it masks, so a token rotated mid-request is masked afresh.
5. **A page with a flash message is the visitor's.**
   `Web::PublicCacheAccess->is_cacheable` is false while the session holds
   a flash: that page is neither served from the cache nor stored.

## Consequences

The language and theme forms work for every visitor of a cached page, and
no token is published. A token taken from a page is good only for its own
session, and not past that session's sign-in or sign-out. A login retried
after a lost response still succeeds: the browser never received the new
cookie and retries with the session it had.

An anonymous request from a browser that sends neither fetch metadata nor
`Origin` on a form POST needs the token; every current browser sends
`Origin` on a POST. Behind a proxy that rewrites the scheme or host, the
origin of `public_base_url` is the one that matches, as for the realtime
handshake, whose origin check now lives in `Web::Access` and is shared.

Rollback is reverting the change; nothing is stored.

## Related Decisions and Implementation

- ADR 0016 (shared HTTP access, CSRF), ADR 0018 (cookie session
  ownership), ADR 0019 (public cache access), ADR 0053 (security
  architecture).
- `lib/GPForum/Web/Access.pm`, `lib/GPForum/Web/CookieSession.pm`,
  `lib/GPForum/Web/PublicCacheAccess.pm`,
  `lib/GPForum/Web/PublicHttpCache.pm`,
  `lib/GPForum/Web/RealtimeAccess.pm`,
  `lib/GPForum/Bootstrap/Security.pm`,
  `lib/GPForum/Controller/Identity.pm`.
- `t/711-cached-page-csrf.t`, `t/114-web-cookie-session.t`,
  `t/153-lost-response-retry.t`.
