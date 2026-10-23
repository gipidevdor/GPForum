# OWASP ASVS 5.0.0 Verification Record

ADR 0149 makes the OWASP Application Security Verification Standard 5.0.0
GPForum's security bar: Level 2 for the whole application, Level 3 for
authentication, sessions, access control and moderation. It claims no level
until a record shows one met. This is that record: every requirement in
scope, its level, its state, and what shows it.

Verified: 2026-10-22, against main as of that day, by reading the code and
the tests named in each row. Nobody outside the project has verified it.
The suspension timestamp and Unicode-password rows were checked again on
2026-10-23 against PostgreSQL integration tests; their evidence is updated below.

## Where it stands

GPForum claims no ASVS level: requirements are not met at every level,
Level 1 included. The [gap list](#gaps-in-priority-order) at the end
orders them, the Level 3 areas first.

| Chapter | In scope | Met | Not met | N/A |
| --- | --: | --: | --: | --: |
| V1 Encoding and Sanitization | 27 | 15 | 2 | 10 |
| V2 Validation and Business Logic | 13 | 3 | 10 | 0 |
| V3 Web Frontend Security | 19 | 9 | 6 | 4 |
| V4 API and Web Service | 10 | 4 | 2 | 4 |
| V5 File Handling | 9 | 5 | 3 | 1 |
| V6 Authentication | 47 | 22 | 13 | 12 |
| V7 Session Management | 19 | 7 | 9 | 3 |
| V8 Authorization | 13 | 6 | 6 | 1 |
| V9 Self-contained Tokens | 7 | 7 | 0 | 0 |
| V11 Cryptography | 21 | 10 | 11 | 0 |
| V12 Secure Communication | 9 | 4 | 4 | 1 |
| V13 Configuration | 13 | 6 | 7 | 0 |
| V14 Data Protection | 9 | 4 | 5 | 0 |
| V15 Secure Coding and Architecture | 13 | 8 | 5 | 0 |
| V16 Security Logging and Error Handling | 17 | 2 | 15 | 0 |
| All chapters | 246 | 112 | 98 | 36 |

| Level | In scope | Met | Not met | N/A |
| --- | --: | --: | --: | --: |
| Level 1 | 65 | 47 | 15 | 3 |
| Level 2 | 152 | 55 | 69 | 28 |
| Level 3 | 29 | 10 | 14 | 5 |

The review also found four places where another document says otherwise.
They are recorded here and left for the change that closes the gap:

- `docs/THREAT_MODEL.md` says a registration naming a taken username or
  address gets the refusal any rejected registration gets. It does, but a
  free one is accepted, so the answer tells whether an address has an
  account (`v5.0.0-6.3.8`).
- ADR 0018 and `lib/GPForum/Web/CookieSession.pm` give a sign-in 30 days.
  Nothing sets the Mojolicious session cookie's expiry, so its one-hour
  default signs out a member idle for an hour (`v5.0.0-7.3.1`).
- ADR 0149 describes the suspension defect as a suspension that ends
  early. The larger effect is that a timed suspension does not end at all
  until it is revoked, because the member's status stays `suspended`
  (`v5.0.0-2.3.2`).
- `docs/THREAT_MODEL.md` lists as a residual risk that moderation writes
  ignore scoped role bindings. The permission check grants a scoped
  binding only on its own resource (`api.admin_permission_allowed_v4`), so
  a moderator bound to a category is refused rather than let beyond it.

## How to read it

Each chapter is a table with one row per requirement in scope:

- **ID** is the versioned identifier, `v5.0.0-<chapter>.<section>.<requirement>`,
  the form ADR 0149 cites. The requirement's own text is in the
  [standard](https://github.com/OWASP/ASVS/tree/v5.0.0/5.0/en); the third
  column only names it.
- **L** is the requirement's level in ASVS. A Level 3 row is here only
  where ADR 0149 asks for Level 3.
- **State** is `met`, `not met` (partly met counts as not met, and the row
  says what is missing) or `n/a` (what the requirement is about does not
  exist in GPForum; the row says why).
- **Evidence** names a test that asserts the behaviour where there is one,
  and the code or configuration that does it, as `path:line`. A `not met`
  row points at the gap when there is a place to point at. SQL is cited
  by the `api.*` function the code calls, at the version the function
  catalogue names (`lib/GPForum/Infrastructure/SqlFunctionCatalogue.pm`),
  and tables by name, not by migration file, because migration files can
  be renumbered.

Line numbers drift as the code changes. `t/721-asvs-record.t` keeps the
record checkable: every requirement in scope is listed once, in order,
under its chapter; every file named exists and has the line cited; the
tallies above add up to the rows; and the gap list names exactly the
requirements not met. It does not verify the requirements again; a change
that affects one updates its row (ADR 0149, decision 6).

## Scope

| Chapter | Levels in scope | Why |
| --- | --- | --- |
| V1, V3, V4, V5, V9, V12, V13, V14, V15 | 1, 2 | Level 2 for the whole application |
| V2 Validation and Business Logic | 1, 2; 3 for moderation | Level 3 rows judged on the moderation paths |
| V6 Authentication | 1, 2, 3 | authentication is a Level 3 area |
| V7 Session Management | 1, 2, 3 | sessions are a Level 3 area |
| V8 Authorization | 1, 2, 3 | access control and moderation are Level 3 areas |
| V11 Cryptography | 1, 2; seven Level 3 rows | Level 3 for what password storage, the two-step sign-in code and the mail tokens rest on: 11.1.3, 11.1.4, 11.2.4, 11.2.5, 11.3.4, 11.3.5, 11.5.2 |
| V16 Security Logging and Error Handling | 1, 2; 3 for moderation | the Level 3 row judged on the moderation paths |
| V10 OAuth and OIDC | none | GPForum signs nobody in through another provider and is no provider |
| V17 WebRTC | none | GPForum has no WebRTC |

The moderation paths are suspensions, address bans, reports, held posts,
the moderation queue, staff notes and role changes. V9 covers the tokens
whose validity rests on their own signature: the signed session cookie and
the one-click unsubscribe token (ADR 0078). V4 covers the JSON answers and
the realtime WebSocket. The Level 3 requirements of V11 left out are key
exchange (11.6.2), which happens in the reverse proxy's TLS, and memory
encryption and minimisation in use (11.7.1, 11.7.2), which none of the
three mechanisms rests on. Other Level 3 requirements are outside the scope
ADR 0149 sets and are not assessed.

## V1 Encoding and Sanitization

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-1.1.1 | 2 | Decode input once, before validating it | met | `lib/GPForum/Service/Forum/PageWindow.pm:86`, `lib/GPForum/Web/Access.pm:115`: Mojolicious percent- and UTF-8-decodes each parameter once; the only further decoding is a base64url page cursor, decoded once where one is expected and checked right after (line 92), and return_to is validated after that single decode. |
| v5.0.0-1.1.2 | 2 | Encode output at the point of use | not met | Held posts are shown with HTML rendered and stored when they were written (`lib/GPForum/Service/Forum/PostingReview.pm:42`) and emitted raw by `templates/forum/pending.html.ep:29` and `templates/moderation/review.html.ep:52`; published posts are re-rendered from source at read time, held ones are not, so a renderer fix would not reach them. |
| v5.0.0-1.2.1 | 1 | Context-appropriate output encoding for HTML and headers | met | `t/179-forum-body-renderer.t:35`, `lib/GPForum/Service/Forum/BodyRenderer.pm:209`, `lib/GPForum/Web/AttachmentAccess.pm:58`: templates auto-escape every interpolation (only RenderPolicy's two contexts, post bodies and search snippets, are raw, both built from xml_escape'd text), there is no inline script or style, and request text reaching a header is cleaned first (an echoed X-Request-ID must match a short allowlist, and a download filename loses quotes and line breaks; the rest of its cleaning is the gap under 1.3.3 and 5.4.2). |
| v5.0.0-1.2.2 | 1 | Encode URL parts; allow only safe link schemes | met | `t/179-forum-body-renderer.t:36`, `lib/GPForum/Service/Forum/BodyRenderer.pm:295`, `assets/js/similar.js:51`: a post link becomes an anchor only for http, https or mailto with no whitespace or entity in the URL; route URLs are built by url_for, which percent-encodes placeholders, and the client encodes its query with encodeURIComponent. |
| v5.0.0-1.2.3 | 1 | Safe JavaScript and JSON generation | met | `templates/layouts/default.html.ep:21`, `lib/GPForum/Controller/Forum/Drafts.pm:97`: pages carry no inline script, only external first-party files, and every JSON answer is produced by Mojolicious's serializer through render(json => ...), never assembled by hand. |
| v5.0.0-1.2.4 | 1 | Parameterized database queries | met | `t/640-sql-function-call-layer.t:50`, `lib/GPForum/Infrastructure/SqlFunctionCatalogue.pm:1830`, `lib/GPForum/Infrastructure/SqlFunction.pm:296`: every api.* call is one prepared statement with typed ? placeholders and bound values; the only dynamic SQL in migrations quotes partition names with format('%I'). |
| v5.0.0-1.2.5 | 1 | No OS command injection | met | `t/196-antivirus-config.t:49`, `lib/GPForum/Infrastructure/ImageTool.pm:166`, `lib/GPForum/Infrastructure/Antivirus/Command.pm:157`: the request-path tools (avatar cropping, virus scan) run through open3 with an argument list, no shell, on file paths the application creates in its own temporary directory. |
| v5.0.0-1.2.6 | 2 | Prevent LDAP injection | n/a | GPForum has no LDAP client or directory lookup: accounts live in PostgreSQL and no LDAP module is in cpanfile or lib. |
| v5.0.0-1.2.7 | 2 | Prevent XPath injection | n/a | No XPath and no XML parsing anywhere in lib; XML (sitemap, Atom feed) is only written. |
| v5.0.0-1.2.8 | 2 | Secure LaTeX processing | n/a | No LaTeX processor is used or invoked by GPForum. |
| v5.0.0-1.2.9 | 2 | Escape metacharacters in regexes built from input | met | `t/683-automod.t:77`, `lib/GPForum/Service/Moderation/Automod.pm:108`, `lib/GPForum/Service/Search/Searcher.pm:754`: automod phrases and search terms are quotemeta'd before they enter a pattern; an automod star is the only wildcard and becomes a bounded word span. |
| v5.0.0-1.3.1 | 1 | Neutralize rich-text HTML with framework feature | met | `t/179-forum-body-renderer.t:35`, `lib/GPForum/Service/Forum/BodyRenderer.pm:209`: there is no WYSIWYG editor and no HTML is accepted; the composer's text is escaped whole with Mojolicious's xml_escape before the renderer adds its own fixed tags, so typed HTML shows as text. |
| v5.0.0-1.3.2 | 1 | No eval or dynamic code execution | met | `templates/layouts/default.html.ep:20`, `lib/GPForum/Security/BrowserHeaders.pm:41`: lib has no string eval, and htmx's eval-based features are switched off (allowEval false) and also blocked by a script-src without 'unsafe-eval'. |
| v5.0.0-1.3.3 | 2 | Sanitize data before dangerous contexts | not met | The X-Accel-Redirect storage key and an echoed X-Request-ID are held to allowlists and return_to refuses control characters (`lib/GPForum/Web/Access.pm:115`), but a download filename is cleaned by a denylist of the double quote, CR and LF alone, with no length cap, before it goes into Content-Disposition (`lib/GPForum/Web/AttachmentAccess.pm:58`); see 5.4.2. |
| v5.0.0-1.3.4 | 2 | Sanitize user-supplied SVG | n/a | Users cannot supply SVG: attachments accept only GIF, JPEG, PNG, WebP, PDF and plain text by magic-number sniffing (`lib/GPForum/Service/Attachment/Validator.pm:15`), avatars only raster images re-encoded to PNG (`lib/GPForum/Service/Community/Avatars.pm:24`); SVG bytes are typed text/plain and sent as a download. |
| v5.0.0-1.3.5 | 2 | Sanitize user markdown or template-language content | met | `t/179-forum-body-renderer.t:34`, `t/391-forum-body-renderer-rules.t:52`, `lib/GPForum/Service/Forum/BodyRenderer.pm:209`: the markdown subset escapes the whole source first and only then adds emphasis, http/https/mailto links, quotes and code; raw HTML, images and other schemes stay text. |
| v5.0.0-1.3.6 | 2 | Prevent server-side request forgery | n/a | The web application makes no outbound request whose destination comes from a request: no link previews, webhooks or URL fetchers; SMTP, clamd and GlifiStore endpoints come from configuration, and Mojo::UserAgent is used only by operator CLI commands. |
| v5.0.0-1.3.7 | 2 | No templates built from untrusted input | met | `lib/GPForum/Web/Partials.pm:133`: every template is read from a file under templates/ (by Mojolicious's renderer or this partial cache); nothing renders an inline template, and user data reaches templates only as escaped stash values. |
| v5.0.0-1.3.8 | 2 | Prevent JNDI injection | n/a | GPForum is Perl; there is no Java runtime and no JNDI. |
| v5.0.0-1.3.9 | 2 | Sanitize data sent to cache stores | met | `lib/GPForum/Service/Operations/SharedCache.pm:634`, `lib/GPForum/Service/Operations/SharedCache.pm:665`: the shared cache (GlifiStore, in place of memcache) gets JSON-encoded values under namespaced keys, and GlifiStore::Client sends each key and value in length-prefixed binary frames, so no delimiter can be injected. |
| v5.0.0-1.3.10 | 2 | No attacker-controlled format strings | met | `lib/GPForum/Service/I18N/Catalog.pm:123`: no sprintf or printf takes its format from input (formats are constants), and message placeholders are filled in one pass that never re-reads a substituted value. |
| v5.0.0-1.3.11 | 2 | Sanitize input passed to mail | met | `lib/GPForum/Service/Identity/Mailer.pm:126`, `lib/GPForum/Service/Identity/AccountStore.pm:764`, `lib/GPForum/Service/Identity/Registration.pm:100`: recipient addresses must match an anchored pattern without whitespace, subjects carrying member text become MIME encoded words (CR and LF end up base64), and Email::Simple indents any embedded newline. |
| v5.0.0-1.4.1 | 2 | Memory-safe strings and buffers | n/a | No unmanaged code: GPForum is Perl and SQL with no C, XS or other systems-language source of its own, and Perl strings and arrays are bounds-checked. |
| v5.0.0-1.4.2 | 2 | Prevent integer overflows | n/a | An unmanaged-code requirement with no subject here: GPForum has no C or XS of its own; Perl promotes integers to floating point instead of wrapping, and PostgreSQL integer types raise an error on overflow. |
| v5.0.0-1.4.3 | 2 | Release memory, avoid dangling pointers | n/a | GPForum's code is Perl, reference-counted, with no manual allocation or pointers. |
| v5.0.0-1.5.1 | 1 | XML parsers configured against XXE | n/a | GPForum parses no XML: no XML::* module or Mojo::DOM in lib; the sitemap and Atom feed are only generated. |
| v5.0.0-1.5.2 | 2 | Safe deserialization of untrusted data | met | `t/113-web-realtime-access.t:56`, `lib/GPForum/Controller/Realtime.pm:110`, `lib/GPForum/Service/Realtime/EventEnvelope.pm:133`: untrusted input is only ever JSON (no Storable, YAML or object tags), which yields plain hashes and arrays; socket messages are size- and shape-checked, and the session cookie's JSON is decoded only after its HMAC verifies. |

## V2 Validation and Business Logic

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-2.1.1 | 1 | Documented validation rules for each kind of input | not met | Rules are documented only for post bodies (`docs/adr/0140-one-maximum-length-for-a-post-body.md:36`), avatars (ADR 0144) and address bans (`docs/adr/0146-address-and-range-bans.md:32`); usernames, emails, titles, display names, tags and moderation fields are defined only in code, e.g. `lib/GPForum/Service/Identity/Registration.pm:89`. |
| v5.0.0-2.1.2 | 2 | Documented consistency rules for combined data items | not met | Only the address-ban ADR documents combined checks (range bounds, covers_self, duplicates at `docs/adr/0146-address-and-range-bans.md:85`); nothing documents how a role binding's resource type, resource id and space id must agree, or how a suspension's end relates to its start and to now. |
| v5.0.0-2.1.3 | 2 | Per-user and global business limits are documented | not met | Limits are scattered (sign-in in `docs/THREAT_MODEL.md:76`, realtime in `docs/realtime.md:270`, DMs and drafts in their ADRs) and several exist only in code, such as reports at 5 a minute (`lib/GPForum/Web/ForumAccess.pm:16`), registration, downloads and notification writes; no document states global limits or that uploads have no per-member storage cap. |
| v5.0.0-2.2.1 | 1 | Input validated against allow lists, patterns and ranges | not met | Most fields are bounded, but a suspension's valid_to reaches the database as free text (`lib/GPForum/Service/Moderation/Workflow.pm:238`), moderation reasons have no maximum (`lib/GPForum/Service/Moderation/Workflow.pm:227`), and a display name only has to be non-empty (`lib/GPForum/Service/Identity/Registration.pm:94`), so a registrant can store megabytes in it. |
| v5.0.0-2.2.2 | 1 | Validation enforced on the server, not the client | met | `t/710-forum-body-length.t:68`, `lib/GPForum/Service/Forum/PostComposer.pm:218`, `lib/GPForum/Service/Identity/Registration.pm:89`: composers, registration and the attachment validator decide in the service layer, with database CHECK constraints behind them, and no client-side check is relied on. |
| v5.0.0-2.2.3 | 2 | Related data combinations checked against defined rules | not met | A role binding takes any resource type, resource id and space id without checking that they agree or exist (`lib/GPForum/Service/Admin/Workflow.pm:146`), and the permission check ignores the binding's resource type and treats a binding with neither id as global (`api.admin_permission_allowed_v4`). |
| v5.0.0-2.3.1 | 1 | Multi-step flows run in order without skipping steps | met | `t/integration/postgres-second-factor.t:167`, `lib/GPForum/Controller/Identity.pm:201`, `lib/GPForum/Service/Moderation/ReviewWorkflow.pm:42`: a password alone signs nobody in until the challenge it issued is answered, and a held post is published or rejected only while it is still pending. |
| v5.0.0-2.3.2 | 2 | Business limits enforced as the application defines them | not met | A suspension sets the member status to suspended and only revocation restores it (`lib/GPForum/Service/Moderation/SuspensionStore.pm:121`); participation refuses that status before consulting the end (`api.moderation_can_participate_v4`), so a timed suspension still needs revocation. Migration 1024 fixes the separate text-comparison and ten-row-window defects: `t/integration/postgres-moderation-review.t:1024` and `t/integration/postgres-moderation-review.t:1062` cover the same-day end, exact expiry, older open-ended rows and three time zones, through both SQL and ORM. |
| v5.0.0-2.3.3 | 2 | Business operations commit wholly or roll back | met | `t/integration/postgres-command-failure.t:65`, `lib/GPForum/Service/Operations/CommandIdempotency.pm:96`, `lib/GPForum/Service/Moderation/SuspensionStore.pm:52`: every workflow command runs in one transaction that is abandoned when it fails, and the moderation stores write row, status, event and audit inside txn_do. |
| v5.0.0-2.3.4 | 2 | Locking prevents double use of limited resources | not met | Drafts, DMs, reports, held posts, bans and role-binding revocation lock their rows, but a suspension is created check-then-insert with no lock or unique index (`lib/GPForum/Service/Moderation/SuspensionStore.pm:63`) and revoked from an unlocked read (`api.moderation_suspension_find_v2`), so concurrent requests can create two active suspensions or audit one revocation twice. |
| v5.0.0-2.3.5 | 3 | High-value actions need approval by several staff | not met | One staff member alone suspends (`lib/GPForum/Controller/Moderation/Suspensions.pm:26`), grants roles (`lib/GPForum/Controller/Admin/Bindings.pm:20`) and places address bans; the danger confirmation is the same person confirming, not a second approver. |
| v5.0.0-2.4.1 | 2 | Anti-automation limits excessive calls to functions | not met | Every HTTP read and write is rate limited (`t/32-forum-web.t:762`), but socket frames other than subscribe are answered with no limit (`lib/GPForum/Controller/Realtime.pm:110`) and nothing caps a member's stored bytes beyond 20 uploads of 25 MiB a minute (`lib/GPForum/Web/AttachmentAccess.pm:13`). |
| v5.0.0-2.4.2 | 3 | Submissions require realistic human pacing | not met | No flow checks the time between a form and its submission; moderation and admin writes are bounded only by 20 a minute (`lib/GPForum/Web/ModerationAccess.pm:13`, `lib/GPForum/Web/AdminAccess.pm:14`), which a script can spend in one burst. |

## V3 Web Frontend Security

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-3.2.1 | 1 | Prevent rendering responses in the wrong context | met | `t/133-web-attachment-access.t:42`, `lib/GPForum/Controller/Attachments/Base.pm:147`, `lib/GPForum/Web/AttachmentAccess.pm:64`: uploaded files go out with their sniffed type and Content-Disposition attachment (kept by nginx's X-Accel-Redirect hand-off too), avatars are re-encoded PNGs, and API answers are application/json under nosniff. |
| v5.0.0-3.2.2 | 1 | Show text via textContent, not HTML sinks | met | `assets/js/similar.js:21`, `assets/js/composer.js:20`: the first-party scripts write text with textContent; their one innerHTML (composer.js line 104) inserts the server's BodyRenderer preview, which is meant as HTML. |
| v5.0.0-3.3.1 | 1 | Secure cookies with __Host- or __Secure- prefix | not met | The session cookie keeps Mojolicious's default name, mojolicious, with no prefix (nothing sets cookie_name beside `lib/GPForum/Bootstrap/Security.pm:24`), and the locale and theme cookies never get Secure, even in production (`lib/GPForum/Web/IdentityAccess.pm:133`). |
| v5.0.0-3.3.2 | 2 | SameSite set per cookie purpose | met | `t/48-browser-security.t:94`, `lib/GPForum/Bootstrap/Security.pm:23`, `lib/GPForum/Web/IdentityAccess.pm:138`: the session, device, locale and theme cookies are all SameSite=Lax, which with the per-session CSRF token suits a site reached by links from elsewhere. |
| v5.0.0-3.3.3 | 2 | __Host- prefix on cookies | not met | No cookie uses the __Host- prefix: the session cookie is mojolicious and the others gpforum_locale, gpforum_theme and gpforum_device (`lib/GPForum/Web/IdentityAccess.pm:31`), though none is meant for another host. |
| v5.0.0-3.3.4 | 2 | HttpOnly session cookie, token only in Set-Cookie | met | `t/48-browser-security.t:92`, `lib/GPForum/Web/CookieSession.pm:90`: the session token is kept only in the signed session cookie, which Mojolicious marks HttpOnly; no page, JSON answer or other header carries it. |
| v5.0.0-3.4.1 | 1 | HSTS on all responses, one year, subdomains | not met | The application sends max-age=31536000; includeSubDomains in staging and production (`t/48-browser-security.t:96`), but static files the proxy serves itself carry none (`deploy/nginx/gpforum.conf:74`, `deploy/caddy/Caddyfile:27`), and nginx drops it from X-Accel-Redirect downloads. |
| v5.0.0-3.4.2 | 1 | CORS allow-origin fixed or allowlisted | n/a | GPForum sends no Access-Control-* header anywhere (lib, templates, deploy), so no cross-origin read is ever granted. |
| v5.0.0-3.4.3 | 2 | CSP with object-src none, base-uri none, allowlist | not met | The global policy has object-src 'none' and a script-src 'self' allowlist but base-uri 'self', not the required 'none' (`lib/GPForum/Security/BrowserHeaders.pm:46`, asserted as 'self' by `t/48-browser-security.t:45`). |
| v5.0.0-3.4.4 | 2 | nosniff on every response | not met | The application and the proxies' static locations send it (`t/48-browser-security.t:38`), but with GPFORUM_ATTACHMENT_ACCEL_REDIRECT set nginx keeps only Content-Type, Content-Disposition and a few other headers of the app's answer, and `deploy/nginx/gpforum.conf:120` adds no nosniff to the uploaded files it then sends. |
| v5.0.0-3.4.5 | 2 | Referrer policy limits leakage | met | `t/48-browser-security.t:40`, `lib/GPForum/Security/BrowserHeaders.pm:21`, `lib/GPForum/Service/Forum/BodyRenderer.pm:20`: every application response sends Referrer-Policy strict-origin-when-cross-origin, so no path or query leaves the site, and links in posts carry rel noreferrer. |
| v5.0.0-3.4.6 | 2 | frame-ancestors on every response | not met | Application responses carry frame-ancestors 'none' (`t/48-browser-security.t:48`), but what nginx or Caddy serve themselves, static assets (`deploy/nginx/gpforum.conf:74`) and X-Accel-Redirect downloads, has no Content-Security-Policy. |
| v5.0.0-3.5.1 | 1 | Anti-forgery checks on state-changing requests | met | `t/50-security-hardening.t:90`, `t/711-cached-page-csrf.t:102`, `lib/GPForum/Web/Access.pm:29`: every POST action checks Mojolicious's per-session CSRF token; a visitor not signed in may instead pass on Sec-Fetch-Site same-origin or a matching Origin, and cross-site, same-site, null and missing origins are refused. |
| v5.0.0-3.5.2 | 1 | No preflight-bypassing calls when relying on CORS | n/a | GPForum does not rely on CORS preflight: it sends no CORS headers and protects writes with the CSRF token and fetch-metadata check of 3.5.1. |
| v5.0.0-3.5.3 | 1 | Sensitive operations never on safe methods | met | `lib/GPForum/Bootstrap/Routes.pm:365`, `lib/GPForum/Bootstrap/Routes.pm:164`: every write, sign-out included, is a POST route; GET links for email confirmation, password reset and unsubscribe only show a form that posts, and GET handlers only read, apart from opening a conversation marking it read. |
| v5.0.0-3.5.4 | 2 | Separate applications on separate hostnames | n/a | GPForum is a single application; the shipped proxy configurations give it its own server name (`deploy/nginx/gpforum.conf:45`, `deploy/caddy/Caddyfile:1`) and host nothing else on that origin. |
| v5.0.0-3.5.5 | 2 | Validate postMessage origin and syntax | n/a | Nothing uses postMessage: neither the first-party scripts nor the bundled htmx send or listen for window messages. |
| v5.0.0-3.7.1 | 2 | Only supported, secure client-side technologies | met | `templates/layouts/default.html.ep:21`, `lib/GPForum/Security/BrowserHeaders.pm:49`: pages use HTML, CSS and three first-party-served scripts (htmx 2.0.10, the composer, similar threads); no plugin is used and object-src 'none' forbids them. |
| v5.0.0-3.7.2 | 2 | Redirects to foreign hosts only via allowlist | met | `t/331-login-return.t:65`, `lib/GPForum/Web/Access.pm:119`: the application never redirects off its origin; every return_to goes through safe_return_to, which refuses absolute, protocol-relative, backslash and control-character targets and falls back to a local page. |

## V4 API and Web Service

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-4.1.1 | 1 | Correct Content-Type with charset on every body | not met | JSON, HTML, text and feed answers carry a charset, but a download is sent with its stored media type alone (`lib/GPForum/Controller/Attachments/Base.pm:146`), so a text attachment goes out as text/plain without one. |
| v5.0.0-4.1.2 | 2 | Only browser-facing endpoints redirect HTTP to HTTPS | not met | Port 80 redirects every path, including the health, metrics and JSON endpoints (`deploy/nginx/gpforum.conf:37`), and Caddy's automatic HTTPS does the same (`deploy/caddy/Caddyfile:1`). |
| v5.0.0-4.1.3 | 2 | Clients cannot override proxy-set forwarding headers | met | `t/691-client-address.t:46`, `lib/GPForum/Web/ClientAddress.pm:67`, `deploy/nginx/gpforum.conf:144`: on the Unix socket the client is the last X-Forwarded-For entry the proxy appended, forged entries ahead of it and X-Forwarded-Proto are ignored, and nginx overwrites X-Real-IP and X-Request-ID. |
| v5.0.0-4.2.1 | 2 | Consistent message framing prevents request smuggling | met | `deploy/nginx/gpforum.conf:142`, `cpanfile.snapshot:1743`: nginx or Caddy parse the client's HTTP/1.1 or HTTP/2 framing and send each request on over HTTP/1.1, and Mojolicious 9.51 reads any body with Transfer-Encoding as chunked and ignores Content-Length. |
| v5.0.0-4.3.1 | 2 | Query depth or cost limits for GraphQL-like APIs | n/a | GPForum has no GraphQL or other client-composed query language; search takes a flat websearch_to_tsquery phrase with bounded result counts (`lib/GPForum/Service/Search/Searcher.pm:24`). |
| v5.0.0-4.3.2 | 2 | GraphQL introspection disabled in production | n/a | There is no GraphQL endpoint or library in GPForum (`cpanfile` lists none). |
| v5.0.0-4.4.1 | 1 | WebSockets only over TLS | met | `t/48-browser-security.t:87`, `deploy/nginx/gpforum.conf:37`, `lib/GPForum/Controller/Realtime.pm:35`: the service listens on a Unix socket behind the proxy, port 80 only redirects, and the session cookie is Secure in staging and production, so a plain ws handshake carries no session and is refused. |
| v5.0.0-4.4.2 | 2 | Handshake Origin checked against allowed origins | met | `t/113-web-realtime-access.t:50`, `lib/GPForum/Controller/Realtime.pm:23`, `lib/GPForum/Web/Access.pm:61`: a handshake whose Origin is neither the request's own nor the configured public origin gets 403; one with no Origin, which only non-browser clients omit, is admitted. |
| v5.0.0-4.4.3 | 2 | Dedicated socket tokens follow session rules | n/a | No dedicated WebSocket token exists: the handshake is authorized by the standard cookie session (`lib/GPForum/Controller/Realtime.pm:34`). |
| v5.0.0-4.4.4 | 2 | Socket tokens derived from authenticated HTTPS session | n/a | No dedicated WebSocket token exists; the upgrade request carries the authenticated HTTPS session itself, and the socket closes when that session ends (`t/719-realtime-session-end.t:72`). |

## V5 File Handling

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-5.1.1 | 2 | Upload types, extensions, sizes and malware handling documented | not met | `README.md:40` names only images, PDFs and text up to 25 MiB and `docs/adr/0144-profile-pictures-cropped-by-the-system-image-tool.md:36` covers avatars; no document lists the exact media types or expected extensions per upload feature, though `docs/adr/0108-uploads-scanned-by-the-system-antivirus.md:53` documents malware handling. |
| v5.0.0-5.2.1 | 1 | Upload size limited to what can be processed | met | `t/22-attachments.t:54`, `lib/GPForum/Service/Attachment/Validator.pm:73`, `lib/GPForum/Service/Community/Avatars.pm:96`: attachments above 25 MiB are refused and requests are cut at 26 MiB, and avatars above 5 MB or 40 megapixels are refused from the header before any decoder runs. |
| v5.0.0-5.2.2 | 1 | File extension and content match the expected type | not met | The type is sniffed from magic bytes, but the filename's extension is never compared with it: only six executable extensions are refused (`lib/GPForum/Service/Attachment/Validator.pm:93`), so a page.html holding text is stored and downloaded under that name, and attachment images are not re-encoded (`lib/GPForum/Service/Attachment/MediaProcessor.pm:112`). |
| v5.0.0-5.2.3 | 2 | Archives checked for unpacked size and file count | n/a | No compressed or archive format is accepted: the allow list is GIF, JPEG, PNG, WebP, PDF and plain text sniffed from the bytes (`lib/GPForum/Service/Attachment/Validator.pm:15`), so zip, gzip, docx and odt read as octet-stream and are refused, and nothing is unpacked. |
| v5.0.0-5.3.1 | 1 | Uploaded files never run as server code | met | `t/63-attachments-web.t:58`, `lib/GPForum/Service/Attachment/FilesystemStorage.pm:20`, `lib/GPForum/Controller/Attachments/Base.pm:147`: files live under var/attachments, outside the static roots, and are only streamed as bytes by the download action with an attachment Content-Disposition and nosniff. |
| v5.0.0-5.3.2 | 1 | File paths built from internal data only | met | `t/410-service-raised-classes.t:44`, `lib/GPForum/Service/Attachment/IntentBuilder.pm:42`, `lib/GPForum/Service/Attachment/FilesystemStorage.pm:93`: the storage key is the owner's id and a generated uuid, never the filename, and storage refuses absolute keys, dot-dot segments and any character outside a safe set. |
| v5.0.0-5.4.1 | 2 | Filenames ignored for paths; Content-Disposition names file | met | `t/133-web-attachment-access.t:42`, `lib/GPForum/Web/AttachmentAccess.pm:64`, `lib/GPForum/Controller/Attachments/Base.pm:147`: the submitted name never reaches a path, and every download names the file in an attachment Content-Disposition. |
| v5.0.0-5.4.2 | 2 | Served filenames encoded per RFC 6266 | not met | The name is only stripped of double quotes, CR and LF (`lib/GPForum/Web/AttachmentAccess.pm:58`): a backslash can escape the closing quote, other control characters pass, and non-ASCII names get no RFC 6266 filename* form. |
| v5.0.0-5.4.3 | 2 | Untrusted uploads antivirus-scanned before serving | met | `t/195-upload-scanning.t:60`, `lib/GPForum/Service/Attachment/UploadPipeline.pm:87`, `lib/GPForum/Config.pm:966`: staging and production scan with the system's clamd by default, infected files are quarantined, and nothing pending or infected is served; an operator can still set GPFORUM_ANTIVIRUS=none. |

## V6 Authentication

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-6.1.1 | 1 | Documented brute-force and stuffing defences, no malicious lockout | met | `docs/adr/0147-a-browser-a-member-signs-in-from-is-not-locked-out.md:16`, `docs/adr/0147-a-browser-a-member-signs-in-from-is-not-locked-out.md:43`, `docs/adr/0142-two-step-sign-in-with-a-time-based-code.md:79`: sign-in is limited per address (10 / 5 min) and per account across addresses (20 / 5 min), a browser that already signed in skips the account limit so nobody can lock a member out, and the second step has its own per-challenge, per-account and per-address caps. |
| v5.0.0-6.1.2 | 2 | Documented list of context-specific banned password words | not met | No document lists organisation, product or role words to refuse; `lib/GPForum/Service/Password.pm:81` checks only presence and minimum length. |
| v5.0.0-6.1.3 | 2 | All authentication pathways documented together with strength | not met | No single document lists the pathways (password, password plus TOTP or recovery code, emailed reset, CLI owner creation, administrator two-step reset) with their controls and strength; they are scattered over `docs/adr/0142-two-step-sign-in-with-a-time-based-code.md`, `docs/adr/0147-a-browser-a-member-signs-in-from-is-not-locked-out.md` and `docs/PRODUCT_FLOWS.md:21`, which is stale (it still says a lost login replays from command_log). |
| v5.0.0-6.2.1 | 1 | Minimum password length of at least 8 | met | `t/110-identity-account-store.t:35`, `t/07-registration-service.t:48`, `lib/GPForum/Service/Password.pm:81`: registration, change and reset refuse fewer than 12 characters (a 9-character password is asserted refused). |
| v5.0.0-6.2.2 | 1 | Members can change their password | met | `t/integration/postgres-identity-stores.t:1226`, `lib/GPForum/Controller/Identity/Password.pm:123`, `templates/identity/settings.html.ep:112`: POST /settings/password rotates the credential and revokes the member's other sessions. |
| v5.0.0-6.2.3 | 1 | Password change needs current and new password | met | `t/integration/postgres-identity-stores.t:1201`, `lib/GPForum/Service/Identity/Workflow.pm:227`, `lib/GPForum/Service/Identity/AccountStore.pm:69`: both fields are required and the current password is verified against the active credential before any write. |
| v5.0.0-6.2.4 | 1 | Refuse the top 3000 common passwords | not met | No common-password list is consulted at registration, change or reset; `lib/GPForum/Service/Password.pm:81` and `lib/GPForum/Service/Identity/Registration.pm:105` check length only, so common passwords of 12 or more characters are accepted. |
| v5.0.0-6.2.5 | 1 | Any character composition allowed, no composition rules | met | `lib/GPForum/Service/Password.pm:29` hashes exact UTF-8 octets; a public salt marker distinguishes the encoding from the original Latin-1 hashes without weakening Argon2id or trying alternative passwords. `t/725-password-unicode.t:26` covers Cyrillic, CJK, emoji, spaces and legacy hashes, including ambiguous byte sequences; `t/integration/postgres-front-door.t:185` creates an owner through UTF-8 stdin, signs in over HTTP and registers another Unicode password. |
| v5.0.0-6.2.6 | 1 | Password inputs masked with type=password | met | `templates/identity/login.html.ep:23`, `templates/identity/register.html.ep:22`, `templates/identity/settings.html.ep:112`: every password field (sign-in, registration, reset, change, email change, two-step settings) is type=password. |
| v5.0.0-6.2.7 | 1 | Paste and password managers not blocked | met | `t/80-settings-web.t:59`, `lib/GPForum/ViewModel/Identity/Presenter.pm:43`, `templates/identity/settings.html.ep:110`: password fields carry current-password or new-password autocomplete hints and no template or script blocks paste or autofill. |
| v5.0.0-6.2.8 | 1 | Password verified exactly as typed, unmodified | met | `lib/GPForum/Controller/Identity.pm:93`, `lib/GPForum/Service/Identity/Registration.pm:32`, `lib/GPForum/Service/Password.pm:39`: verification uses the exact character sequence, encoded according to the hash salt marker, without trimming, truncation, normalisation, case folding or encoding fallback. `t/725-password-unicode.t:26` also asserts that hashing does not mutate its input and distinct character sequences do not match legacy hashes. |
| v5.0.0-6.2.9 | 2 | Passwords of 64+ characters allowed | met | `lib/GPForum/Service/Password.pm:81`, `lib/GPForum/Service/Identity/Registration.pm:105`, `templates/identity/register.html.ep:22`: only a minimum is enforced and no field has a maxlength, so a 200-character password hashes and verifies. |
| v5.0.0-6.2.10 | 2 | No forced periodic password rotation | met | `lib/GPForum/Service/Identity/CredentialStore.pm:135`: a credential (the `credentials` table has no expiry column) stays active until the member changes or resets it. |
| v5.0.0-6.2.11 | 2 | Context-specific word list enforced on new passwords | not met | No such list exists (see 6.1.2), so none is checked; `lib/GPForum/Service/Identity/Registration.pm:105` checks length only. |
| v5.0.0-6.2.12 | 2 | Check new passwords against breached-password sets | not met | No breached-password lookup (local corpus or k-anonymity range query) runs at registration, change or reset; `lib/GPForum/Service/Identity/AccountStore.pm:777` checks length only. |
| v5.0.0-6.3.1 | 1 | Brute-force controls implemented as documented | met | `t/203-login-account-limit.t:50`, `t/717-login-known-device.t:68`, `lib/GPForum/Controller/Identity.pm:83`: sign-in is checked against the per-address and per-account limits ADR 0147 names, and a known browser skips only the account limit. |
| v5.0.0-6.3.2 | 1 | No default accounts such as admin or root | met | `lib/GPForum/Service/Admin/Bootstrapper.pm:390`, `lib/GPForum/Command/AdminBootstrap.pm:130`: no migration seeds a row into the `users` table; the first owner is created by the operator with a username and password they choose, checked by the registration policy. |
| v5.0.0-6.3.3 | 2 | MFA required to access; L3 phishing-resistant hardware factor | not met | Two-step sign-in is optional for members (`lib/GPForum/Service/Identity/AuthStore.pm:101` opens a session on the password alone) and required of staff only if an administrator turns the policy on (off by default, `api.core_identity_second_factor_missing_v1`); there is no WebAuthn or other phishing-resistant factor for L3 and no documented rationale for the relaxation. |
| v5.0.0-6.3.4 | 2 | No undocumented pathways, strength enforced consistently | met | `t/integration/postgres-second-factor.t:167`, `lib/GPForum/Service/Identity/AuthStore.pm:67`, `docs/adr/0142-two-step-sign-in-with-a-time-based-code.md:75`: sessions are opened only by the password sign-in in AuthStore, HTML and JSON alike, which asks for the second step whenever it is on; reset and verification links open no session. |
| v5.0.0-6.3.5 | 3 | Notify users of suspicious authentication attempts | not met | Only ten wrong second-step codes are mailed (`api.identity_second_factor_challenge_answer_v2`); a sign-in from a new browser, a password that verified without the second step, or repeated wrong passwords notify nobody, though `lib/GPForum/Controller/Identity.pm:167` already knows when a browser is new. |
| v5.0.0-6.3.6 | 3 | Email never used as an authentication factor | met | `lib/GPForum/Service/Identity/AuthStore.pm:213`, `lib/GPForum/Controller/Identity/Password.pm:104`, `docs/adr/0142-two-step-sign-in-with-a-time-based-code.md:137`: no emailed code or magic link signs anyone in; the emailed reset only sets a new password and opens no session. |
| v5.0.0-6.3.7 | 3 | Notify after credential, username or email changes | not met | Email changes (to the old address) and two-step changes are mailed, but a password change or reset only writes an audit row (`lib/GPForum/Service/Identity/AccountStore.pm:282`, `lib/GPForum/Service/Identity/AccountStore.pm:226`) and `lib/GPForum/Worker/Handler/IdentityMail.pm:33` has no password notice. |
| v5.0.0-6.3.8 | 3 | No account enumeration via errors, codes or timing | not met | Sign-in and reset answer alike, but registration answers 400 for a taken username or address and 202 otherwise (`lib/GPForum/Service/Identity/Workflow.pm:489`, `api.identity_register_command_v2`), so a fresh username plus a target address reveals whether that address has an account. |
| v5.0.0-6.4.1 | 1 | Initial secrets random, short-lived, single-use | met | `t/integration/postgres-identity-stores.t:965`, `lib/GPForum/Service/SessionToken.pm:16`, `api.identity_consume_token_v2`: no initial password is generated; verification and reset tokens are 256 random bits, stored hashed, spent on first use, expire (24 h, 1 h) and never become a password. |
| v5.0.0-6.4.2 | 1 | No password hints or secret questions | met | `lib/GPForum/Controller/Identity/Password.pm:32`: the `users` table holds no hint or question, and a reset asks only for the identifier and is answered by email. |
| v5.0.0-6.4.3 | 2 | Secure forgotten-password reset that keeps MFA | met | `t/integration/postgres-identity-stores.t:965`, `lib/GPForum/Service/Identity/AccountStore.pm:207`, `lib/GPForum/Service/Identity/AuthStore.pm:67`: a single-use, one-hour, rate-limited token sets the password and revokes every session without signing in, and the next sign-in still asks for the second step. |
| v5.0.0-6.4.4 | 2 | Lost MFA factor needs identity proofing like enrollment | not met | An administrator turns off a member's two-step sign-in with no identity-proofing step (`lib/GPForum/Service/Identity/SecondFactor.pm:334` takes only the two ids) and ADR 0142 defines no proofing procedure. |
| v5.0.0-6.4.5 | 3 | Timely renewal reminders for expiring authenticators | n/a | No GPForum authenticator expires: passwords, TOTP secrets and recovery codes carry no expiry (the `credentials` table), so there is nothing to renew. |
| v5.0.0-6.4.6 | 3 | Admins start resets without choosing user passwords | not met | Administrators cannot set a member's password, but neither can they start a reset for one: the only reset is self-service (`lib/GPForum/Bootstrap/Routes.pm:356`) and the admin routes reset two-step sign-in only (`lib/GPForum/Bootstrap/Routes.pm:76`). |
| v5.0.0-6.5.1 | 2 | TOTP and lookup secrets usable only once | met | `t/integration/postgres-second-factor.t:191`, `api.identity_second_factor_challenge_answer_v2`, `lib/GPForum/Service/Identity/SecondFactor.pm:296`: a code is accepted only for a step newer than the last one used, and a recovery code is marked used on its first sign-in (asserted at line 199 of the same test). |
| v5.0.0-6.5.2 | 2 | Low-entropy lookup secrets stored with salted password hash | not met | Recovery codes have 80 bits (under 112) yet are kept as SHA-256 of a fixed label, the member id and the code (`lib/GPForum/Service/Identity/SecondFactorCodes.pm:151`, asserted in `t/712-second-factor.t:131`), not an approved password hash with a random salt. |
| v5.0.0-6.5.3 | 2 | TOTP seeds and lookup secrets from a CSPRNG | met | `lib/GPForum/Service/Identity/SecondFactorCodes.pm:46`, `lib/GPForum/Service/Identity/SecondFactorCodes.pm:55`, `lib/GPForum/Service/Identity/SecondFactorCodes.pm:132`: the 160-bit TOTP secret and each recovery code are drawn from Crypt::URandom. |
| v5.0.0-6.5.4 | 2 | Lookup secrets have at least 20 bits entropy | met | `t/712-second-factor.t:116`, `lib/GPForum/Service/Identity/SecondFactorCodes.pm:33`: each recovery code is 16 base32 characters from 10 random bytes, 80 bits. |
| v5.0.0-6.5.5 | 2 | TOTP lifetime 30 s, out-of-band 10 min max | not met | The TOTP step is 30 s but a code is accepted one step either side (`lib/GPForum/Service/Identity/SecondFactorCodes.pm:21`, asserted in `t/712-second-factor.t:66`), so a code stays usable for up to 90 s; there are no out-of-band codes. |
| v5.0.0-6.5.6 | 3 | Any lost or stolen factor can be revoked | met | `t/integration/postgres-second-factor.t:413`, `t/integration/postgres-second-factor.t:386`, `lib/GPForum/Service/Identity/SecondFactor.pm:176`: the member turns two-step off with the password and a recovery code, renews the recovery codes, or an administrator resets it; a password is revoked by change or reset. |
| v5.0.0-6.5.7 | 3 | Biometrics only as a secondary factor | n/a | GPForum has no biometric authentication; the only factors are a password, a TOTP code and recovery codes. |
| v5.0.0-6.5.8 | 3 | TOTP checked against trusted server time | met | `lib/GPForum/Service/Identity/SecondFactor.pm:398`, `lib/GPForum/Service/Clock.pm:14`, `docs/DEPLOYMENT.md:756`: the code is matched against the server clock, kept on NTP; the client sends only the code. |
| v5.0.0-6.6.1 | 2 | SMS or phone OTP restrictions, none at L3 | n/a | No phone or SMS authentication exists (`docs/adr/0142-two-step-sign-in-with-a-time-based-code.md:137` rejects SMS codes); the only second factor is TOTP. |
| v5.0.0-6.6.2 | 2 | Out-of-band codes bound to their originating request | n/a | No out-of-band authenticator exists: no emailed, pushed or texted code signs anyone in; emailed reset and verification tokens are account recovery, covered under 6.4. |
| v5.0.0-6.6.3 | 2 | Out-of-band codes rate limited against brute force | n/a | No out-of-band authentication code exists; the emailed reset token (256 bits, 5 requests per 5 min per address) is recovery, covered under 6.4. |
| v5.0.0-6.6.4 | 3 | Push MFA rate limited against push bombing | n/a | GPForum has no push-notification authentication. |
| v5.0.0-6.7.1 | 3 | Assertion-verifying certificates protected from modification | n/a | No cryptographic authenticator exists (no WebAuthn, no client certificates), so no certificate verifies an authentication assertion; the missing WebAuthn is recorded under 6.3.3. |
| v5.0.0-6.7.2 | 3 | Challenge nonce at least 64 bits and unique | n/a | No cryptographic authenticator exists (no WebAuthn or certificate challenge), so there is no challenge nonce. |
| v5.0.0-6.8.1 | 2 | No identity spoofing across multiple IdPs | n/a | GPForum signs nobody in through an external identity provider (`docs/adr/0149-owasp-asvs-5-is-the-security-bar.md:58`). |
| v5.0.0-6.8.2 | 2 | Signatures on authentication assertions always validated | n/a | No JWT, SAML or OIDC authentication assertion is accepted (`docs/adr/0149-owasp-asvs-5-is-the-security-bar.md:58`); the signed session cookie is a session token, covered by V7 and V9. |
| v5.0.0-6.8.3 | 2 | SAML assertions processed once only | n/a | GPForum does not use SAML (`docs/adr/0149-owasp-asvs-5-is-the-security-bar.md:58`). |
| v5.0.0-6.8.4 | 2 | Verify IdP authentication strength and recency claims | n/a | GPForum uses no separate identity provider (`docs/adr/0149-owasp-asvs-5-is-the-security-bar.md:58`). |

## V7 Session Management

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-7.1.1 | 2 | Idle and absolute timeouts documented with NIST justification | not met | Only the 30-day absolute lifetime is written down (`docs/adr/0018-cookie-session-ownership.md:22`), with no reasoning and no comparison with NIST SP 800-63B; the inactivity timeout actually in force (Mojolicious' default one-hour expiry of the signed cookie, which `lib/GPForum/Bootstrap/Security.pm:23` never changes) is documented nowhere and contradicts the "30-day login duration" of `lib/GPForum/Web/CookieSession.pm:146`. |
| v5.0.0-7.1.2 | 2 | Concurrent session limit and its behaviour documented | not met | No document says how many sessions one account may hold or what happens at a limit; the code sets none, every sign-in inserting another row (`lib/GPForum/Service/Identity/SessionStore.pm:49`). |
| v5.0.0-7.1.3 | 2 | Federated session systems and lifetimes documented | n/a | GPForum signs nobody in through another provider and is no provider (no SSO, OAuth, OIDC or SAML code; `docs/adr/0149-owasp-asvs-5-is-the-security-bar.md:58`), so there is no federated session ecosystem to document. |
| v5.0.0-7.2.1 | 1 | Session tokens verified by a trusted backend | met | `t/70-bootstrap-identity.t:59`, `lib/GPForum/Bootstrap/Identity.pm:151`, `api.session_validate_v2`: every request carrying a session is validated in PostgreSQL (member, token digest, revocation, expiry) and is served as a visitor when that fails. |
| v5.0.0-7.2.2 | 1 | Session tokens dynamically generated, not static secrets | met | `t/04-services.t:104`, `lib/GPForum/Service/SessionToken.pm:16`, `lib/GPForum/Service/Identity/SessionStore.pm:276`: each sign-in mints a fresh random reference token whose SHA-256 is stored with its own session row. |
| v5.0.0-7.2.3 | 1 | Reference tokens unique, CSPRNG-made, at least 128 bits | met | `t/04-services.t:104`, `lib/GPForum/Service/SessionToken.pm:16`: the token is 32 bytes (256 bits) from Crypt::URandom, its hash unique by a constraint on the `sessions` table, and a collision is reminted. |
| v5.0.0-7.2.4 | 1 | New token at every authentication; old one ended | not met | Sign-in mints a new session but only drops the previous one from the cookie (`lib/GPForum/Controller/Identity.pm:455`), so signing in again, or as someone else, leaves the earlier sessions row live for its 30 days; the password re-checks before an email change or two-step setup (`lib/GPForum/Service/Identity/AccountStore.pm:99`) do not rotate the session at all. |
| v5.0.0-7.3.1 | 2 | Inactivity timeout set by documented risk decision | not met | No idle limit is decided anywhere: the server row's last_seen_at is refreshed but never compared with a limit (`api.session_validate_v2`), and the only idle cut-off is Mojolicious' undeclared one-hour default on the signed cookie (`lib/GPForum/Bootstrap/Security.pm:23` leaves it unset), untested and undocumented. |
| v5.0.0-7.3.2 | 2 | Absolute session lifetime forces re-authentication | met | `t/160-session-touch-interval.t:162`, `lib/GPForum/Service/Identity/SessionStore.pm:40`, `api.session_validate_v2`: a session expires 30 days after sign-in however it is used (the value ADR 0018 records), and past that it is refused and revoked server-side. |
| v5.0.0-7.4.1 | 1 | Ended sessions unusable and invalidated server-side | met | `t/integration/postgres-identity-stores.t:633`, `lib/GPForum/Service/Identity/Workflow.pm:187`, `api.session_validate_v2`: logout revokes the sessions row and empties the cookie, an expired row is revoked when presented, and every request refuses a revoked or expired row. |
| v5.0.0-7.4.2 | 1 | Sessions end when an account is disabled or deleted | met | `t/339-erasure-unreadable-source.t:69`, `lib/GPForum/Service/Privacy/DeletionWorkflow.pm:708`: account erasure revokes every session of the member, or fails and retries; GPForum has no disabled-account state (a suspension only bars participation and is re-checked on each request). |
| v5.0.0-7.4.3 | 2 | Option to end other sessions after factor changes | not met | A password change or reset (`lib/GPForum/Service/Identity/AccountStore.pm:275`) and turning two-step sign-in on end the other sessions, but turning it off, renewing the recovery codes or an administrator's reset end none and offer nothing (`api.identity_second_factor_disable_v2`, `lib/GPForum/Service/Identity/SecondFactor.pm:204`). |
| v5.0.0-7.4.4 | 2 | Visible logout on every authenticated page | met | `t/61-mvp-user-flow.t:94`, `templates/components/identity_nav.html.ep:2`, `templates/layouts/default.html.ep:46`: the header of the one page layout every full page uses carries a sign-out button whenever a member is signed in. |
| v5.0.0-7.4.5 | 2 | Administrators can end one user's or all sessions | not met | No console route or gpforum verb revokes a member's sessions: `lib/GPForum/Service/Identity/SessionStore.pm:181` is reached only from password change, reset and erasure, and the only all-users lever is dropping the previous signing secret, which secret rotation deliberately keeps for 30 days. |
| v5.0.0-7.5.1 | 2 | Full re-authentication before changing authentication-related attributes | not met | An email change asks for the password only, never the second step of a member who has one (`lib/GPForum/Service/Identity/AccountStore.pm:99`), and new recovery codes take only a code from the app, without the password (`lib/GPForum/Service/Identity/SecondFactor.pm:207`). |
| v5.0.0-7.5.2 | 2 | Members can view and end their active sessions | not met | No page or route lists a member's sessions or ends one other than the current (logout); the security page is two-step sign-in only (`lib/GPForum/Bootstrap/Routes.pm:404`). |
| v5.0.0-7.5.3 | 3 | Extra factor before highly sensitive operations | not met | Asking for account erasure (`lib/GPForum/Controller/Privacy/Requests.pm:27`) and a staff grant of a role (`lib/GPForum/Controller/Admin/Bindings.pm:13`) need only the session and a CSRF token; no password or code is asked again. |
| v5.0.0-7.6.1 | 2 | RP and IdP session lifetimes behave as documented | n/a | Section 7.6 is for relying-party or identity-provider code and GPForum is neither: it signs nobody in through another provider (`docs/adr/0149-owasp-asvs-5-is-the-security-bar.md:58`). |
| v5.0.0-7.6.2 | 2 | Session creation requires consent or explicit action | n/a | Section 7.6 concerns federated sign-in, which GPForum does not have; its sessions are opened only by a posted sign-in form or its second step (`lib/GPForum/Service/Identity/AuthStore.pm:213`). |

## V8 Authorization

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-8.1.1 | 1 | Docs define function-level and data-level access rules | not met | Data rules are documented (`docs/adr/0102-effective-visibility.md:83`), but the function-level matrix names roles and permissions the code does not use, as the ADR itself records (`docs/adr/0070-permission-matrix-authorization-rules.md:160`), and no document maps the implemented permissions to the routes they guard. |
| v5.0.0-8.1.2 | 2 | Docs define field-level read and write rules | not met | No document defines which fields each kind of consumer may read or write; field exposure is decided only in code, such as the public profile's field list (`lib/GPForum/Service/Identity/ProfileReader.pm:289`). |
| v5.0.0-8.1.3 | 3 | Docs define contextual attributes used in security decisions | met | `docs/adr/0146-address-and-range-bans.md:41`, `docs/adr/0147-a-browser-a-member-signs-in-from-is-not-locked-out.md:30`, `docs/THREAT_MODEL.md:76`: the attributes the code uses are each defined (client address for rate limits and bans, the signed known-device mark, the websocket Origin, trusted proxies); time of day and location are not used. |
| v5.0.0-8.1.4 | 3 | Docs define how context drives decisions, thresholds, actions | not met | ADRs 0146 and 0147 and `docs/THREAT_MODEL.md:76` give the address and account limits and their refusals, but no document sets risk thresholds with challenge or step-up actions, and the field-level rules it must sit beside are missing (8.1.2). |
| v5.0.0-8.2.1 | 1 | Functions restricted to explicitly permitted consumers | met | Console actions check the permission gate and deny by default (`api.admin_permission_allowed_v4`). The suspension participation gate now compares typed instants and considers every unrevoked suspension (`api.moderation_active_suspension_v4`, `lib/GPForum/Service/Moderation/SuspensionStore.pm:349`); `t/integration/postgres-moderation-review.t:1024` and `t/integration/postgres-moderation-review.t:1062` assert that a same-day end and older open-ended suspension still bar participation. Revocation preserves deleted and pending accounts and keeps the member suspended while another active suspension remains (`t/integration/postgres-moderation-review.t:849`). |
| v5.0.0-8.2.2 | 1 | Object access limited to permitted consumers (IDOR/BOLA) | met | `t/199-effective-visibility.t:106`, `lib/GPForum/Service/Forum/Visibility.pm:48`, `api.core_forum_write_post_v1`: reads go through the effective-visibility rule on every surface, and edits, deletes, attachments, drafts and sessions are matched to their owner in the store. |
| v5.0.0-8.2.3 | 2 | Field access limited to permitted consumers (BOPLA) | met | `t/42-profile-reader.t:204`, `lib/GPForum/Service/Identity/ProfileReader.pm:289`: no controller binds a request wholesale (each field is read by name), and readers answer a fixed field list per audience, such as a public profile without the address. |
| v5.0.0-8.2.4 | 3 | Adaptive contextual controls at sign-in and during sessions | not met | Context feeds only static rate limits and staff-placed address bans; nothing adapts to risk or steps authentication up, and a session's address and browser are hashed into its row and never compared again (`lib/GPForum/Service/Identity/SessionStore.pm:283`). |
| v5.0.0-8.3.1 | 1 | Authorization enforced server-side, never by client controls | met | `t/44-admin-web.t:701`, `lib/GPForum/Service/Admin/PermissionGate.pm:39`, `api.admin_permission_allowed_v4`: every decision is taken on the server, in the permission gate's SQL function and the stores' own owner and visibility checks; none rests on client script. |
| v5.0.0-8.3.2 | 3 | Authorization changes take effect immediately | not met | Role bindings, suspensions and visibility are read afresh on each request, but a realtime subscription to the moderation or admin channel is authorized once and keeps receiving events after the binding is revoked (`lib/GPForum/Service/Realtime/Hub.pm:357`), and an ended session's sockets in other workers live up to 30 seconds more. |
| v5.0.0-8.3.3 | 3 | Decisions use the originating subject, not intermediaries | met | `lib/GPForum/Service/Admin/PermissionGate.pm:32`, `api.core_forum_write_post_v1`: the database functions decide on the member id passed with each call (their bindings, authorship, readability), never on the broader rights of the runtime role the application connects as. |
| v5.0.0-8.4.1 | 2 | Cross-tenant isolation in multi-tenant applications | n/a | GPForum is single-tenant: one installation serves one forum from one database, and its spaces are sections of that forum, not tenants. |
| v5.0.0-8.4.2 | 3 | Layered admin access beyond identity and network location | not met | The consoles check a role binding on every request and can require two-step sign-in of staff (`api.admin_permission_allowed_v4`), a policy off by default, but nothing assesses device posture or contextual risk. |

## V9 Self-contained Tokens

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-9.1.1 | 1 | Token signature or MAC verified before use | met | `t/717-login-known-device.t:82`, `t/685-notification-preferences.t:63`, `lib/GPForum/Service/Notification/UnsubscribeToken.pm:64`: Mojolicious checks each signed cookie's HMAC against the configured secrets before reading it, and an unsubscribe token is read only once its HMAC verifies. |
| v5.0.0-9.1.2 | 1 | Only allowlisted token algorithms, never none | met | `lib/GPForum/Service/Notification/UnsubscribeToken.pm:81`, `cpanfile:3`: both tokens use one fixed algorithm, HMAC-SHA-256 (Mojolicious 9.51 signs its cookies with it), and carry no algorithm field a client could change. |
| v5.0.0-9.1.3 | 1 | Verification keys come from trusted preconfigured sources | met | `t/01-config.t:573`, `lib/GPForum/Config.pm:1096`, `lib/GPForum/Bootstrap/Core.pm:49`: the keys are the configured signing secrets only, the development default refused where the forum is deployed, and no token names its key or a key source. |
| v5.0.0-9.2.1 | 1 | Token validity window enforced when present | met | `t/70-bootstrap-identity.t:81`, `lib/GPForum/Web/CookieSession.pm:35`, `lib/GPForum/Bootstrap/Identity.pm:204`: the session cookie's signed expiry and its session_expires_at_epoch are checked on every request and a lapsed cookie is cleared; the unsubscribe token carries no time span (ADR 0078). |
| v5.0.0-9.2.2 | 2 | Token type and purpose checked before use | met | `lib/GPForum/Service/Notification/UnsubscribeToken.pm:81`: an unsubscribe signature covers its purpose label, and Mojolicious signs each cookie together with its name, so no signature the application makes for one use verifies for another. |
| v5.0.0-9.2.3 | 2 | Tokens accepted only for their intended audience | met | `lib/GPForum/Service/Notification/UnsubscribeToken.pm:62`, `lib/GPForum/Config.pm:1096`: GPForum is the only issuer and the only audience of both tokens and verifies them solely with its own deployment's secrets under their purpose binding, so a token made for another service does not verify. |
| v5.0.0-9.2.4 | 2 | Shared-key tokens carry a distinct audience restriction | met | `lib/GPForum/Service/Notification/UnsubscribeToken.pm:19`, `lib/GPForum/Service/Identity/MailToken.pm:28`: the one signing secret signs the session and device cookies, each bound to its cookie name, and unsubscribe links, bound to their purpose label, while mail tokens use a key derived from it under their own label. |

## V11 Cryptography

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-11.1.1 | 2 | Documented key-management policy and key lifecycle | not met | No document sets out a key-management policy or lifecycle that follows a standard such as NIST SP 800-57, or limits how widely keys are shared. What exists is rotation steps (`docs/DEPLOYMENT.md:219`, `docs/adr/0142-two-step-sign-in-with-a-time-based-code.md:43`) and a one-line rule that rotation must remain possible (`docs/adr/0053-security-architecture.md:197`). |
| v5.0.0-11.1.2 | 2 | Maintained inventory of keys, algorithms and certificates | not met | No cryptographic inventory exists that lists every key, algorithm and certificate, where each key may be used and what data it protects. The facts are scattered across code, ADRs and the dependency list (`docs/CPAN_LICENSE_REVIEW.md:21`). |
| v5.0.0-11.1.3 | 3 | Automated discovery of every cryptographic use | not met | Nothing discovers cryptographic use. `.github/workflows/security.yml` scans dependency advisories, licenses, leaked secrets and workflows only, and no CBOM, SAST or test lists the hashing, MAC and encryption call sites behind passwords, the TOTP code and mail tokens. |
| v5.0.0-11.1.4 | 3 | Inventory with a migration plan, post-quantum included | not met | There is no inventory and no documented plan for moving Argon2id, the HMAC-SHA-1 TOTP or the sealed-secret format to new standards, post-quantum included. The only forward-looking note is a POD line saying a later format can move to AES-GCM (`lib/GPForum/Service/Identity/SecretBox.pm:225`). |
| v5.0.0-11.2.1 | 2 | Vetted crypto implementations, not home-made constructions | not met | Hashing, HMAC, Argon2id and randomness come from Digest::SHA, Crypt::Argon2 and Crypt::URandom, but the encryption of TOTP secrets and queued mail tokens is a cipher written in the project: an HMAC-SHA-256 counter-mode keystream with encrypt-then-MAC (`lib/GPForum/Service/Identity/SecretBox.pm:121`). This breaks the project's own ban on custom cryptography (`docs/adr/0053-security-architecture.md:203`), and the SCRAM verifier's PBKDF2 is hand-written too (`lib/GPForum/Service/Operations/DatabaseProvisioning.pm:159`). |
| v5.0.0-11.2.2 | 2 | Algorithms, parameters and keys replaceable without rework | not met | Keys can rotate: session secrets through gpforum secret rotate, and sealed secrets carry key ids and are sealed again under the new key at sign-in (`lib/GPForum/Service/Identity/SecondFactor.pm:270`). But the Argon2id parameters are code constants (`lib/GPForum/Service/Password.pm:16`), and a successful sign-in never rehashes an old hash (`lib/GPForum/Service/Identity/AuthStore.pm:181`); verification also accepts only argon2id, and the TOTP algorithm is fixed with no per-secret algorithm field. |
| v5.0.0-11.2.3 | 2 | Every primitive gives at least 128 bits of security | not met | The algorithms and every key the application generates reach 128 bits, and production refuses a current secret or second-factor key shorter than 32 characters (`lib/GPForum/Config.pm:1628`). The still-accepted previous keys have no length rule, though: GPFORUM_SESSION_SECRETS is checked only against the development value (`lib/GPForum/Config.pm:1639`) and GPFORUM_SECOND_FACTOR_KEYS is not checked at all (`lib/GPForum/Config.pm:831`). |
| v5.0.0-11.2.4 | 3 | Secret comparisons and crypto operations run in constant time | met | `lib/GPForum/Service/Identity/SecondFactorCodes.pm:106`, `lib/GPForum/Service/Identity/SecretBox.pm:93`, `lib/GPForum/Service/Password.pm:39`: a TOTP check computes all three candidate codes and compares each without an early exit, sealed secrets and mail tokens check their tags the same way, and Argon2id compares inside the library. An unknown account verifies against a decoy hash, and mail tokens are looked up by their SHA-256, so timing reveals only bits of the hash (no test asserts timing). |
| v5.0.0-11.2.5 | 3 | Crypto failures fail closed and give no oracle | met | `t/712-second-factor.t:158`, `t/718-identity-mail-token-sealed.t:67`, `lib/GPForum/Service/Identity/SecretBox.pm:99`: unseal returns the same undef for a wrong format, an unknown key, a bad tag or another member's value, checks the MAC before decrypting and uses no padding. A TOTP check treats an unopenable secret as a wrong code, the outbox worker mails nothing it cannot open, and password verification returns false for a missing or non-Argon2id hash. |
| v5.0.0-11.3.1 | 1 | No ECB mode or weak padding | met | `lib/GPForum/Service/Identity/SecretBox.pm:70`: the application's only encryption XORs a counter-mode keystream, so no block mode or padding is involved, and no RSA or other public-key padding is used anywhere in the code. |
| v5.0.0-11.3.2 | 1 | Only approved ciphers and modes | not met | The application's only cipher is a project-built keystream of HMAC-SHA-256 in counter mode (`lib/GPForum/Service/Identity/SecretBox.pm:125`), which is not on the approved list (AES-GCM, ChaCha20-Poly1305 and the like). ADR 0142 chose it to avoid adding CryptX (`docs/adr/0142-two-step-sign-in-with-a-time-based-code.md:131`). |
| v5.0.0-11.3.3 | 2 | Encrypted data protected against tampering | met | `t/712-second-factor.t:158`, `lib/GPForum/Service/Identity/SecretBox.pm:71`: every sealed value carries an HMAC-SHA-256 tag, under its own derived key, over the format, key id, member or token id, nonce and ciphertext; the tag is checked in constant time before decryption, and an altered value does not open. |
| v5.0.0-11.3.4 | 3 | A nonce is never reused under the same key | met | `t/712-second-factor.t:153`, `lib/GPForum/Service/Identity/SecretBox.pm:68`: each sealing of a TOTP secret or mail token draws a fresh 128-bit nonce from the OS CSPRNG, which suits the counter-mode keystream and makes a repeat under one key negligibly likely. |
| v5.0.0-11.3.5 | 3 | MAC computed over the ciphertext (encrypt-then-MAC) | met | `t/712-second-factor.t:158`, `lib/GPForum/Service/Identity/SecretBox.pm:71`: the tag is computed over the ciphertext after encryption, and unseal verifies it before applying the keystream, for TOTP secrets and mail tokens alike. |
| v5.0.0-11.4.1 | 1 | Only approved hash functions for crypto; no MD5 | not met | TOTP codes use HMAC-SHA-1 (`lib/GPForum/Service/Identity/SecondFactorCodes.pm:83`), which appendix C rates legacy, not approved, for HMAC; it is kept so standard authenticator apps work. The other SHA-1 and MD5 uses are not cryptographic: an ETag (`lib/GPForum/Web/PublicHttpCache.pm:207`), a sandbox package name (`lib/GPForum/Web/Partials.pm:41`), UUIDv5 ids and a MIME boundary. |
| v5.0.0-11.4.2 | 2 | Passwords stored with a tuned slow hash | met | `t/04-services.t:57`, `lib/GPForum/Service/Password.pm:29`: member passwords are hashed with Argon2id (t=3, m=32 MiB, p=1, a public encoding marker plus 16 random salt bytes and a 32-byte tag), above appendix C's floor of 12 MiB at t>=3; a fresh hash encodes m=32768,t=3,p=1. |
| v5.0.0-11.4.3 | 2 | Integrity hashes collision-resistant and at least 256 bits | met | `t/116-infrastructure-audit-record.t:119`, `lib/GPForum/Infrastructure/AuditRecord.pm:81`: the audit chain, session and token digests, and migration, backup and attachment checksums use SHA-256, while cookies, unsubscribe links and sealed values use HMAC-SHA-256. SHA-1 appears only in identifiers that protect nothing (ETag, UUIDv5). |
| v5.0.0-11.4.4 | 2 | Keys derived from passwords use a stretched approved KDF | not met | The only key derived from a password is the SCRAM-SHA-256 verifier setup writes for the database role: PBKDF2-HMAC-SHA-256 at 4,096 iterations (`lib/GPForum/Service/Operations/DatabaseProvisioning.pm:35`, asserted at `t/532-setup-database-provisioning.t:72`), far below appendix C's 600,000. Setup normally generates a 256-bit random password, but one the operator supplies gets the same 4,096 iterations. |
| v5.0.0-11.5.1 | 2 | Unguessable values from a CSPRNG, at least 128 bits | not met | Session and mail tokens, salts, nonces, CSRF tokens and TOTP secrets come from the OS CSPRNG at 128 to 256 bits (`lib/GPForum/Service/SessionToken.pm:13`). Two-step recovery codes, however, carry only 80 random bits (`lib/GPForum/Service/Identity/SecondFactorCodes.pm:33`) and are stored as a plain SHA-256 (`lib/GPForum/Service/Identity/SecondFactorCodes.pm:151`). |
| v5.0.0-11.5.2 | 3 | Random source stays secure under heavy demand | met | `cpanfile:16`, `lib/GPForum/Service/Password.pm:94`, `lib/GPForum/Service/SessionToken.pm:25`: salts, TOTP secrets, nonces and mail tokens come from Crypt::URandom 0.55, which calls getrandom(2), or reopens /dev/urandom after a fork. It never blocks or degrades under load, and it throws an error rather than fall back to a weaker source (no test exercises load). |
| v5.0.0-11.6.1 | 2 | Approved key generation, no weak asymmetric keys | met | `lib/GPForum/Command/Secret.pm:126`, `lib/GPForum/Service/Identity/SecretBox.pm:121`: secrets are generated as 32 bytes from the OS CSPRNG, and sub-keys are derived with HMAC-SHA-256 under separate labels. The application generates no asymmetric keys and makes no digital signatures; TLS keys belong to nginx or Caddy. |

## V12 Secure Communication

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-12.1.1 | 1 | Only TLS 1.2 and 1.3, newest preferred | met | `deploy/nginx/gpforum.conf:52`, `deploy/caddy/Caddyfile:1`: the nginx site enables TLSv1.2 and TLSv1.3 only and the Caddy site keeps Caddy's identical defaults, so a client that speaks TLS 1.3 negotiates it; no test asserts the protocol line. |
| v5.0.0-12.1.2 | 2 | Strong cipher suites only, strongest preferred | not met | The nginx site sets no ssl_ciphers, so TLS 1.2 uses nginx's default HIGH:!aNULL:!MD5 list (non-forward-secret RSA and CBC suites included) with ssl_prefer_server_ciphers off (`deploy/nginx/gpforum.conf:53`); Caddy's defaults are acceptable. |
| v5.0.0-12.1.3 | 2 | mTLS client certificates validated before trust | n/a | GPForum has no mutual-TLS client authentication: neither the shipped proxies nor the application request or read client certificates, and identity comes from the session cookie alone. |
| v5.0.0-12.2.1 | 1 | HTTPS for all client traffic, no fallback | met | `t/48-browser-security.t:96`, `deploy/nginx/gpforum.conf:37`, `lib/GPForum/Bootstrap/Security.pm:21`: port 80 only redirects to https (Caddy redirects by default), and staging and production send HSTS for a year with includeSubDomains and mark the session cookie Secure. |
| v5.0.0-12.2.2 | 1 | Public-facing certificates publicly trusted | met | `docs/DEPLOYMENT.md:174`, `deploy/nginx/gpforum.conf:49`, `deploy/caddy/Caddyfile:1`: the install takes a Let's Encrypt certificate with certbot for the nginx site, and Caddy obtains a publicly trusted one itself through ACME. |
| v5.0.0-12.3.1 | 2 | Encrypted transport for every backend connection | not met | Default connections stay on the host over Unix sockets, but a remote database gets no sslmode so libpq may fall back to plaintext (`lib/GPForum/Config.pm:1304`), a GlifiStore shared between hosts is plain TCP (`lib/GPForum/Config.pm:55`), and GPFORUM_SMTP_TLS=off is accepted in production (`lib/GPForum/Config.pm:949`). |
| v5.0.0-12.3.2 | 2 | TLS clients verify server certificates | not met | SMTP relies on IO::Socket::SSL's default peer and hostname checks, but nothing asks libpq for verify-full or a root certificate on a remote database, and the preflight recommends only sslmode require, which does not verify (`lib/GPForum/OS/Preflight.pm:292`, `lib/GPForum/Config.pm:1304`). |
| v5.0.0-12.3.3 | 2 | Internal HTTP traffic encrypted or never networked | met | `t/695-socket-upgrade-path.t:64`, `lib/GPForum/CLI/start.pm:158`, `deploy/nginx/gpforum.conf:2`: the only internal HTTP hop, proxy to Hypnotoad, runs over a group-only Unix socket on the same host, and the service refuses to start on a TCP listener. |
| v5.0.0-12.3.4 | 2 | Internal TLS trusts only specific CAs or certificates | not met | No internal TLS trust is configured or documented: a remote PostgreSQL connection names no sslrootcert or verify-full (`lib/GPForum/Config.pm:1304`), and GlifiStore over TCP has no TLS at all (`lib/GPForum/Service/Operations/SharedCache.pm:302`). |

## V13 Configuration

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-13.1.1 | 2 | Document all inbound and outbound communication needs | met | `docs/THREAT_MODEL.md:44`, `deploy/gpforum.env.example:40`, `docs/DEPLOYMENT.md:13`: the trust-boundary diagram names the proxy, PostgreSQL, GlifiStore, clamd and the SMTP relay, and the environment reference documents every endpoint setting; no feature makes the server fetch a user-supplied location. |
| v5.0.0-13.2.1 | 2 | Backend components authenticate without static credentials | not met | The default socket uses peer authentication as the service account, but GlifiStore over TCP carries no credential (`lib/GPForum/Service/Operations/SharedCache.pm:302`), a remote database authenticates with a static password (`deploy/gpforum.env.example:47`), and /metrics with a static bearer token (`lib/GPForum/Web/OperationsAccess.pm:61`). |
| v5.0.0-13.2.2 | 2 | Backend accounts hold least privilege | not met | Setup writes GPFORUM_DATABASE_USER as the schema-owning gpforum role (`lib/GPForum/Command/Setup.pm:436`), so the web service runs as the table owner; the function-only gpforum_runtime role is a manual, optional step (`docs/ops/sql-api-role.md:115`). |
| v5.0.0-13.2.3 | 2 | Service credentials are never defaults | met | `t/01-config.t:573`, `lib/GPForum/Config.pm:1621`, `lib/GPForum/Command/Setup.pm:808`: staging and production refuse the built-in development session secret and second-factor key, the metrics token is required with no default, and setup generates the database password. |
| v5.0.0-13.2.4 | 2 | Allowlist of systems the app may contact | not met | Outbound targets are only what the settings name, but nothing enforces an allowlist: the DSN, SMTP and GlifiStore settings accept any host (`lib/GPForum/Config.pm:55`), and the units set no egress restriction (`deploy/systemd/gpforum.service:7`). |
| v5.0.0-13.2.5 | 2 | Server configured with outbound resource allowlist | not met | Neither the systemd units nor the proxy configurations restrict where the service may connect or read from: the hardening block has no IPAddressAllow, IPAddressDeny or RestrictAddressFamilies, and ProtectSystem=full limits writes only (`deploy/systemd/gpforum.service:38`). |
| v5.0.0-13.3.1 | 2 | Secrets managed in a vault, never in code | not met | Secrets stay out of the repository and setup generates them, but they live in plaintext in one environment file loaded into the processes' environment (`deploy/gpforum.env.example:5`) with no vault, and rotation covers only the session secret and metrics token (`lib/GPForum/Command/Secret.pm:36`). |
| v5.0.0-13.3.2 | 2 | Secret access follows least privilege | not met | The environment file holding every secret is mode 0640 with the service group (`lib/GPForum/Command/Setup.pm:1159`), and the guide adds the proxy's worker account (www-data, caddy) to that group (`docs/DEPLOYMENT.md:727`), so the internet-facing proxy can read the session secret and database password; every unit also reads every secret. |
| v5.0.0-13.4.1 | 1 | No reachable .git or VCS metadata | not met | The documented install is a git clone into the code directory (`docs/DEPLOYMENT.md:48`), so /opt/gpforum/.git stays readable by the service account; the shipped proxies serve only the assets tree, so it is not reachable from outside. |
| v5.0.0-13.4.2 | 2 | Debug modes off in production | met | `lib/GPForum/Bootstrap/Core.pm:50`, `lib/GPForum/Bootstrap/Operations.pm:463`, `deploy/systemd/gpforum.service:14`: the Mojolicious mode follows GPFORUM_ENV, so production renders plain error pages instead of the debug page (a production-mode probe answered 404 without echoing headers), and per-request database headers are never sent in production. |
| v5.0.0-13.4.3 | 2 | No directory listings | met | `deploy/nginx/gpforum.conf:95`, `deploy/caddy/Caddyfile:54`: the static locations enable no autoindex and use file_server without browse, and the application's static handler serves files only. |
| v5.0.0-13.4.4 | 2 | HTTP TRACE unsupported | met | `lib/GPForum/Bootstrap/Routes.pm:15`, `deploy/nginx/gpforum.conf:140`: every route is declared for GET or POST and none for any method, so TRACE matches nothing and a production-mode probe answered 404 without echoing the request; nginx itself refuses TRACE with 405. |
| v5.0.0-13.4.5 | 2 | Docs and monitoring endpoints not exposed | met | `t/300-health-report-access.t:48`, `lib/GPForum/Controller/Operations.pm:17`, `deploy/nginx/gpforum.conf:127`: /metrics requires the token (mandatory in staging and production) and the proxies keep it to loopback, /health and /health/ready give anonymous clients the status alone, and no API documentation is served. |

## V14 Data Protection

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-14.1.1 | 2 | Sensitive data inventoried and classified by level | not met | ADR 0074 only says the platform SHOULD classify personal data categories (`docs/adr/0074-privacy-data-protection-legal-operations.md:43`), and no document assigns GPForum's data to protection levels; the threat model's asset table has none (`docs/THREAT_MODEL.md:17`). |
| v5.0.0-14.1.2 | 2 | Protection requirements documented per level | not met | With no protection levels there is no per-level set of encryption, integrity, retention, logging or database-encryption requirements; ADR 0074 states the duty to define purpose, retention and access per category without defining them (`docs/adr/0074-privacy-data-protection-legal-operations.md:47`). |
| v5.0.0-14.2.1 | 1 | No sensitive data in URLs or query strings | met | `lib/GPForum/Web/CookieSession.pm:90`, `lib/GPForum/Web/OperationsAccess.pm:36`, `lib/GPForum/Bootstrap/Routes.pm:362`: the session token travels only in the cookie, the metrics token only in headers, and credentials are POSTed; one-time, expiring mail-link tokens sit in the link path but are completed by a POST carrying the token in the body. |
| v5.0.0-14.2.2 | 2 | No sensitive data in server-side caches | met | `t/115-web-public-cache-access.t:34`, `lib/GPForum/Web/PublicCacheAccess.pm:23`, `lib/GPForum/Service/Forum/CategoryReader.pm:123`: the page cache (L1 and GlifiStore) stores only anonymous GET responses without a flash, shared lists are cached for the anonymous viewer, and the shipped proxies cache nothing. |
| v5.0.0-14.2.3 | 2 | No sensitive data to trackers or third parties | met | `t/48-browser-security.t:43`, `lib/GPForum/Security/BrowserHeaders.pm:40`: the CSP confines scripts, images, fonts and connections to the forum's own origin, the templates load no third-party resources (fonts, htmx and the TOTP QR code are local), and Referrer-Policy sends only the origin elsewhere. |
| v5.0.0-14.2.4 | 2 | Data controls implemented as each level defines | not met | No protection levels or per-level requirements are documented (see 14.1.1 and 14.1.2), so the controls that exist (event retention, hashed identifiers in audit rows, export and erasure) cannot be checked against a definition (`docs/adr/0074-privacy-data-protection-legal-operations.md:47`). |
| v5.0.0-14.3.1 | 1 | Client-side authenticated data cleared at logout | not met | Sign-out empties the cookie session but sends no Clear-Site-Data (`lib/GPForum/Controller/Identity.pm:376`), and most signed-in pages carry no no-store, so their content stays in the browser cache and history after logout. |
| v5.0.0-14.3.2 | 2 | Cache-Control no-store on sensitive responses | not met | no-store is set page by page (messages, two-step sign-in, drafts, some staff pages), while the privacy export download (`lib/GPForum/Controller/Privacy/Base.pm:232`), settings (`lib/GPForum/Controller/Identity/Settings.pm:94`), the privacy dashboard and notifications are sent without it, and no hook covers signed-in responses. |
| v5.0.0-14.3.3 | 2 | Browser storage holds nothing sensitive | met | `lib/GPForum/Web/CookieSession.pm:85`, `templates/layouts/default.html.ep:20`, `assets/js/composer.js`: the forum's scripts use no localStorage, sessionStorage or IndexedDB, htmx's sessionStorage history is never written because nothing pushes a URL, and the session cookie holds only identifiers, session and CSRF tokens and display preferences. |

## V15 Secure Coding and Architecture

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-15.1.1 | 1 | Documented remediation time frames for vulnerable dependencies | not met | No document sets risk-based time frames for fixing vulnerable components or for routine library updates: `docs/CPAN_LICENSE_REVIEW.md:47` and `docs/CI.md:234` only say that every unexcluded CPANSA advisory fails the scan. |
| v5.0.0-15.1.2 | 2 | Maintained inventory (SBOM) of third-party components, trusted sources | not met | The Carton lock pins the CPAN tree and `script/bootstrap-deps:192` refuses a non-HTTPS mirror, but the vendored htmx 2.0.10 (`assets/js/htmx.min.js`) and the Inter fonts appear in no inventory or review, and no SBOM is produced (`docs/QUALITY_PROGRAM.md:2215`). |
| v5.0.0-15.1.3 | 2 | Document resource-heavy features and availability defenses | met | `docs/THREAT_MODEL.md:105`, `docs/PERFORMANCE.md:445`, `docs/adr/0140-one-maximum-length-for-a-post-body.md:17`: search, body rendering, large-thread removal and reindexing, uploads and N+1 pages are named with their caps, batches and timeouts, and search gets a 2 s timeout so it cannot hold a web worker for the 15 s other queries may take. |
| v5.0.0-15.2.1 | 1 | Components within documented remediation time frames | not met | With no documented time frames (15.1.1) compliance cannot be shown; the CPAN lock passes `script/cpan-audit` today with two justified exclusions (`etc/cpan-audit-ignore.txt`), but the vendored `assets/js/htmx.min.js` is outside any advisory scan. |
| v5.0.0-15.2.2 | 2 | Defenses for resource-heavy features are implemented | met | `t/204-search-bounded-ranking.t:121`, `lib/GPForum/Service/Search/Searcher.pm:322`, `lib/GPForum/Service/Forum/BodyLength.pm:24`: search runs under its own transaction-local statement_timeout over a capped candidate set, and a post body over 50,000 characters is refused before it is rendered. |
| v5.0.0-15.2.3 | 2 | Production ships no test, sample or dev functionality | not met | Nothing extra is reachable over HTTP (test routes exist only inside tests, seeding refuses production, the develop phase is not installed), but the release tarball is a plain `git archive` with no export-ignore (`.github/workflows/release.yml:70`), so t/, the t/lib test doubles and benchmarks/ ship to production hosts (open item `docs/QUALITY_PROGRAM.md:2216`). |
| v5.0.0-15.3.1 | 1 | Responses expose only needed object fields | met | `t/42-profile-reader.t:204`, `lib/GPForum/Service/Identity/ProfileReader.pm:290`: JSON responses are built from explicit field lists by readers and view models; the public profile names its fields and leaves the e-mail address out. |
| v5.0.0-15.3.2 | 2 | Outbound HTTP does not follow redirects | met | `lib/GPForum/Service/Operations/HttpProbe.pm:76`: the only outbound HTTP client, the operator's status and doctor probe, sets max_redirects(0), and its curl fallback (`lib/GPForum/Service/Operations/HttpProbe.pm:147`) passes no --location. |
| v5.0.0-15.3.3 | 2 | Allow-list writable fields per action | met | `lib/GPForum/Controller/Admin/Categories.pm:42`, `lib/GPForum/Service/Admin/CategoryStore.pm:198`, `lib/GPForum/Controller/Forum/Write.pm:26`: no code copies request parameters wholesale (no every_param or params->to_hash in lib/); each action names its fields, owner ids come from the session, and stores build updates from fixed column sets. |
| v5.0.0-15.3.4 | 2 | Client IP taken from trusted proxy data only | met | `t/691-client-address.t:46`, `lib/GPForum/Web/ClientAddress.pm:67`: on the proxy socket only the X-Forwarded-For entry the proxy appended is believed (over TCP only from the trusted proxy list), and that one value feeds rate limits, address bans and audit rows. |
| v5.0.0-15.3.5 | 2 | Strict typing and comparisons, no type confusion | met | `api.moderation_active_suspension_v4` takes a timestamptz clock; the ORM path converts both ends to epoch seconds (`lib/GPForum/Service/Moderation/SuspensionStore.pm:349`). `t/integration/postgres-moderation-review.t:1024` and `t/integration/postgres-moderation-review.t:1062` check later-today, exact-end and expired values under UTC, Europe/Rome and Pacific/Honolulu in both paths. |
| v5.0.0-15.3.6 | 2 | Frontend JavaScript resists prototype pollution | met | `assets/js/composer.js:6`, `assets/js/similar.js:15`: first-party scripts keep per-form state in a WeakMap, read input through FormData and URLSearchParams, and never assign object keys taken from input or server JSON; templates load no inline script. |
| v5.0.0-15.3.7 | 2 | Defend against HTTP parameter pollution | not met | No defense exists: controllers read every field with Mojolicious `param` (e.g. `lib/GPForum/Controller/Forum/Write.pm:26`), which merges route captures, body and query string and returns the last duplicate, so a query-string value overrides the POST body; duplicates are neither rejected nor confined to the body. |

## V16 Security Logging and Error Handling

| ID | L | Requirement | State | Evidence |
| --- | :-: | --- | --- | --- |
| v5.0.0-16.1.1 | 2 | Inventory of logging: where, format, access, retention | not met | No such inventory: `docs/OBSERVABILITY.md:5` covers metrics, query counters and benchmarks; nothing documents the application log (GPFORUM_LOG_PATH), the nginx logs, what audit_log and event_log hold, who may read them, or how long they are kept (retention is left to the owner, `docs/ops/partition-maintenance.md:234`). |
| v5.0.0-16.2.1 | 2 | Log entries carry when, where, who, what | not met | Audit rows carry time, actor, action, target and correlation id (`lib/GPForum/Infrastructure/AuditRecord.pm:23`), but application log lines are free text with only time, pid and level, no request id, user or client (e.g. `lib/GPForum/Controller/Moderation.pm:42`); ADR 0058 records this as an open conflict (`docs/adr/0058-observability-logging-operational-intelligence.md:256`). |
| v5.0.0-16.2.2 | 2 | Synced clocks, UTC or offset timestamps | not met | Hosts are told to run NTP (`docs/DEPLOYMENT.md:756`) and audit rows are stamped in UTC (`lib/GPForum/Infrastructure/AuditRecord.pm:104`), but `lib/GPForum/Log.pm:14` keeps Mojo::Log's default stamp, the host's local time with no zone offset, on every application log line. |
| v5.0.0-16.2.3 | 2 | Logs go only to inventoried destinations | not met | There is no log inventory to hold destinations to (16.1.1); undocumented ones include the access log of the shipped `deploy/nginx/gpforum.conf:140` and the per-process security event snapshot published on /metrics (`lib/GPForum/Service/Operations/SecurityTelemetry.pm:35`). |
| v5.0.0-16.2.4 | 2 | Logs in a common, correlatable format | not met | Application logs are Mojo::Log plain text without a request or correlation id (`lib/GPForum/Log.pm:14`) although nginx sends X-Request-ID; ADR 0058 asks for structured JSON and lists the gap as open (`docs/adr/0058-observability-logging-operational-intelligence.md:256`). |
| v5.0.0-16.2.5 | 2 | Sensitive data masked or excluded from logs | not met | Login audits hash the identifier and address and telemetry keeps fixed keys, but the shipped nginx config logs full request URIs, password-reset and e-mail verification tokens in GET paths included (`deploy/nginx/gpforum.conf:140`, `lib/GPForum/Bootstrap/Routes.pm:359`), and app log lines print raw DBI errors whose statement suffix carries bind values (only search strips it, `lib/GPForum/Controller/Forum/Search.pm:171`). |
| v5.0.0-16.3.1 | 2 | Log successful and failed authentication | not met | Successful sign-ins and sign-outs become audit rows (`lib/GPForum/Controller/Identity.pm:387`), but a refused password, a wrong second-factor code and a second-factor lockout only bump an in-memory counter (`lib/GPForum/Controller/Identity.pm:508`, `lib/GPForum/Service/Operations/SecurityTelemetry.pm:23`); nothing reaches a log. |
| v5.0.0-16.3.2 | 2 | Log failed authorization attempts | not met | Permission denials on admin and moderation routes are logged at info with user, permission and path (`lib/GPForum/Web/Guard.pm:61`), but every other 403, a suspended member's attempted write included (`lib/GPForum/Controller/Forum/Base.pm:1029`), is only counted in process memory (`lib/GPForum/Web/SecurityEvent.pm:49`). |
| v5.0.0-16.3.3 | 2 | Log security events and control-bypass attempts | not met | CSRF failures, rate-limit hits, address-ban refusals and oversized realtime frames are kept only as per-process counters holding the last occurrence (`lib/GPForum/Web/SecurityEvent.pm:34`, `lib/GPForum/Service/Operations/SecurityTelemetry.pm:23`); no log entry is written for any of them. |
| v5.0.0-16.3.4 | 2 | Log unexpected errors and security-control failures | not met | Request errors are logged, but security-control failures are swallowed into counters: a session store that cannot validate a session (`lib/GPForum/Bootstrap/Identity.pm:166`) and a failing rate-limit store (`lib/GPForum/Service/Operations/RateLimiter.pm:94`) discard the exception without a log line. |
| v5.0.0-16.4.1 | 2 | Encode logged data against log injection | not met | Nothing encodes log data: `lib/GPForum/Log.pm:14` sets only level and path, Mojo::Log writes messages verbatim, and lines interpolate exception text that can carry member input with newlines through DBI's statement suffix (e.g. `lib/GPForum/Controller/Forum/Write.pm:247`). |
| v5.0.0-16.4.2 | 2 | Logs protected from access and modification | not met | The audit hash chain only makes edits evident: whoever can write the database can rewrite it consistently and the external anchor is still Proposed (`docs/THREAT_MODEL.md:141`, `docs/adr/0114-audit-chain-without-a-forum-wide-lock.md:5`); the application's own role owns the tables (the table-less API role is not used, `lib/GPForum/Service/Operations/ApiRole.pm:20`) and the service user can rewrite its log file. |
| v5.0.0-16.4.3 | 2 | Ship logs to a separate system | not met | Logs stay on the host: the application writes to a local file or STDERR (`lib/GPForum/Log.pm:30`) and audit rows live in the application database; no shipping to a separate system is configured or documented (`docs/adr/0058-observability-logging-operational-intelligence.md:254` leaves tooling optional). |
| v5.0.0-16.5.1 | 2 | Generic error responses, no internals leaked | met | `t/375-controller-read-failures.t:187`, `lib/GPForum/Web/ErrorPayload.pm:141`, `lib/GPForum/Bootstrap/Core.pm:50`: failing reads answer the fixed internal-error payload, and the deployed units run Mojolicious in production mode, whose exception page and JSON carry no message or trace. |
| v5.0.0-16.5.2 | 2 | Degrade securely when external resources fail | met | `t/177-session-validation-resilience.t:32`, `t/89-tiered-cache.t:360`, `lib/GPForum/Bootstrap/Identity.pm:167`: a session store that cannot answer gives 503 instead of serving the request as its user, and an unreachable GlifiStore is skipped for 15 s instead of stalling requests. |
| v5.0.0-16.5.3 | 2 | Fail closed on exceptions, no fail-open | not met | Most paths fail closed (session check answers 503, a failing suspension lookup aborts the write), but an address-ban lookup that throws lets the write through by design (`lib/GPForum/Web/AddressBans.pm:62`), so a banned address can write whenever the ban query fails. |
| v5.0.0-16.5.4 | 3 | Last-resort handler catches all unhandled exceptions | not met | GPForum defines none and relies on Mojolicious's per-request catch, which logs and keeps the worker up; exceptions in its IOLoop callbacks (websocket frames `lib/GPForum/Controller/Realtime.pm:77`, the session-check timer `lib/GPForum/Service/Realtime/Hub.pm:144`) fall to Mojo::IOLoop's warn on STDERR, which daemonized Hypnotoad points at /dev/null (`lib/GPForum/Log.pm:21`), so their details are lost. |
## Gaps, in priority order

Every requirement not met, grouped where one change closes several. The
Level 3 areas come first, as ADR 0149 asks: authentication, sessions,
access control and moderation. Within each group, defects that members or
staff meet today come before missing documents.

### Level 3 areas: authentication, sessions, access control, moderation

1. **A timed suspension still needs revocation, and concurrent moderation
   writes are not serialized.** The member status stays `suspended` until
   revocation, even after the end. Creation is check-then-insert without a
   lock, and revocation reads without a lock. Timestamp comparison and the
   ten-row lookup window were fixed in migration 1024; these lifecycle and
   concurrency gaps remain. `v5.0.0-2.3.2`, `v5.0.0-2.3.4`.
2. **Failed sign-ins, refused permissions and refused requests leave no
   log.** A wrong password or code, a second-step lockout, a 403 outside
   the consoles, a suspended member's write, a CSRF failure, a rate-limit
   hit and an address-ban refusal only bump an in-memory counter; a
   failing session or rate-limit store is swallowed. `v5.0.0-16.3.1`,
   `v5.0.0-16.3.2`, `v5.0.0-16.3.3`, `v5.0.0-16.3.4`.
3. **Two-step sign-in is optional, and there is no phishing-resistant
   factor.** Members choose, staff need it only if an administrator turns
   the policy on, and there is no WebAuthn (ADR 0053 asks for it); nothing
   beyond the role binding and that policy guards the consoles.
   `v5.0.0-6.3.3`, `v5.0.0-8.4.2`.
4. **Registration tells anyone whether an address has an account.** A
   taken username or address is refused, a free one accepted.
   `v5.0.0-6.3.8`.
5. **Sessions outlive what should end them, and members cannot see them.**
   Signing in again leaves the earlier session live; re-entering the
   password rotates nothing; turning two-step sign-in off, renewing
   recovery codes or an administrator's reset leave other sessions open;
   administrators cannot end a member's sessions, a suspended member's
   included; members have no list of their sessions. `v5.0.0-7.2.4`,
   `v5.0.0-7.4.3`, `v5.0.0-7.4.5`, `v5.0.0-7.5.2`.
6. **The idle timeout is an accident and the timeouts are undecided.**
   Nothing sets the session cookie's expiry, so Mojolicious's one-hour
   default signs out a member idle for an hour, against the 30 days ADR
   0018 records; no document justifies either timeout or limits concurrent
   sessions. `v5.0.0-7.3.1`, `v5.0.0-7.1.1`, `v5.0.0-7.1.2`.
7. **Sensitive changes ask too little.** An email change asks for the
   password but not the second step, new recovery codes need no password,
   and account erasure or a staff role grant asks for nothing again.
   `v5.0.0-7.5.1`, `v5.0.0-7.5.3`.
8. **Weak passwords are accepted.** No common-password list, no
   breached-password check, no context-specific words. `v5.0.0-6.2.4`,
   `v5.0.0-6.2.12`, `v5.0.0-6.1.2`, `v5.0.0-6.2.11`.
9. **Members are not told.** A password change or reset sends no mail; a
    sign-in from a new browser or repeated wrong passwords notify nobody.
    `v5.0.0-6.3.7`, `v5.0.0-6.3.5`.
10. **Moderation acts on one person's word, and some of its inputs are
    unchecked.** One staff member suspends, grants roles and bans
    addresses; no pacing slows a scripted burst; a role binding accepts any
    combination of resource type, resource and space; an address-ban lookup
    that fails lets the write through. `v5.0.0-2.3.5`, `v5.0.0-2.4.2`,
    `v5.0.0-2.2.3`, `v5.0.0-16.5.3`.
11. **Authorization changes do not reach open sockets.** A moderator whose
    role is revoked keeps receiving the moderation and admin channels; an
    ended session's sockets on other workers live up to 30 seconds.
    `v5.0.0-8.3.2`.
12. **Second-factor recovery is weak.** An administrator resets a member's
    two-step sign-in with no identity proofing, and cannot start a password
    reset for a member; recovery codes carry 80 bits under a fast hash; a
    TOTP code is accepted one step either side, up to 90 seconds.
    `v5.0.0-6.4.4`, `v5.0.0-6.4.6`, `v5.0.0-6.5.2`, `v5.0.0-11.5.1`,
    `v5.0.0-6.5.5`.
13. **The cryptography behind sign-in is partly home-made.** TOTP secrets
    and queued mail tokens are sealed with a project-built HMAC-SHA-256
    counter-mode cipher rather than an approved AEAD; TOTP uses HMAC-SHA-1;
    Argon2id's parameters are code constants and old hashes are never
    rehashed; previous keys have no length rule; the database role's SCRAM
    verifier uses 4,096 PBKDF2 iterations. `v5.0.0-11.2.1`,
    `v5.0.0-11.3.2`, `v5.0.0-11.4.1`, `v5.0.0-11.2.2`, `v5.0.0-11.2.3`,
    `v5.0.0-11.4.4`.
14. **No last-resort handler outside requests.** Exceptions in websocket
    frame handlers and the realtime session timer go to STDERR, which a
    daemonized Hypnotoad discards. `v5.0.0-16.5.4`.
15. **Nothing adapts to risk.** Session address and browser hashes are
    stored and never compared again; no step-up on unusual context.
    `v5.0.0-8.2.4`.
16. **Missing documents in the Level 3 areas.** All sign-in pathways with
    their strength in one place; the permission matrix of ADR 0070 replaced
    by the catalogue the code uses, mapped to routes; field-level rules;
    contextual thresholds and actions; a key-management policy, a
    cryptographic inventory with a migration plan, and a way to discover
    every use. `v5.0.0-6.1.3`, `v5.0.0-8.1.1`, `v5.0.0-8.1.2`,
    `v5.0.0-8.1.4`, `v5.0.0-11.1.1`, `v5.0.0-11.1.2`, `v5.0.0-11.1.3`,
    `v5.0.0-11.1.4`.

### Level 1, elsewhere

17. **Uploads keep any name.** The extension is never matched with the
    sniffed type (a text file named `page.html` is stored as such) and
    attachment images are not re-encoded. `v5.0.0-5.2.2`.
18. **Signed-in pages stay in the browser after sign-out.** No
    `Clear-Site-Data`. `v5.0.0-14.3.1`.
19. **Headers the proxy sends alone.** Static files and X-Accel-Redirect
    downloads carry no HSTS; the session cookie has no `__Host-` prefix and
    the locale and theme cookies are never `Secure`; a text download goes
    out without a charset. `v5.0.0-3.4.1`, `v5.0.0-3.3.1`, `v5.0.0-4.1.1`.
20. **Input limits not everywhere.** A suspension's end arrives as free
    text, moderation reasons and display names have no maximum, and the
    validation rules exist only in code. `v5.0.0-2.2.1`, `v5.0.0-2.1.1`.
21. **The code directory is a git clone.** `.git` is readable by the
    service account, though not served. `v5.0.0-13.4.1`.
22. **No remediation time frames for dependencies.** `v5.0.0-15.1.1`,
    `v5.0.0-15.2.1`.

### Level 2, elsewhere

23. **Logs are free text and stay on the host.** No inventory, no request
    id or actor, local time without an offset, no encoding against
    injection, reset tokens in the proxy's access log and bind values in
    DBI errors, no protection from the service user, no shipping.
    `v5.0.0-16.1.1`, `v5.0.0-16.2.1`, `v5.0.0-16.2.2`, `v5.0.0-16.2.3`,
    `v5.0.0-16.2.4`, `v5.0.0-16.2.5`, `v5.0.0-16.4.1`, `v5.0.0-16.4.2`,
    `v5.0.0-16.4.3`.
24. **Secrets and the database role.** The web service runs as the
    schema's owner; every secret sits in one environment file the proxy's
    account can read; backends without credentials; no egress allowlist.
    `v5.0.0-13.2.2`, `v5.0.0-13.3.2`, `v5.0.0-13.3.1`, `v5.0.0-13.2.1`,
    `v5.0.0-13.2.4`, `v5.0.0-13.2.5`.
25. **Personal pages without `no-store`, and no data classification.**
    Settings, the privacy dashboard and export, and notifications are sent
    without `no-store`; no protection levels are defined.
    `v5.0.0-14.3.2`, `v5.0.0-14.1.1`, `v5.0.0-14.1.2`, `v5.0.0-14.2.4`.
26. **Backend transport.** A remote database gets no `sslmode` and no
    certificate check, a shared GlifiStore is plain TCP, SMTP TLS can be
    switched off in production, and nginx keeps its default TLS 1.2
    ciphers. `v5.0.0-12.3.1`, `v5.0.0-12.3.2`, `v5.0.0-12.3.4`,
    `v5.0.0-12.1.2`.
27. **Browser hardening.** `base-uri 'self'` instead of `'none'`; proxy-sent
    files without `nosniff` or `frame-ancestors`; no `__Host-` cookies;
    plain HTTP redirected for the JSON and health endpoints too.
    `v5.0.0-3.4.3`, `v5.0.0-3.4.4`, `v5.0.0-3.4.6`, `v5.0.0-3.3.3`,
    `v5.0.0-4.1.2`.
28. **Encoding at the last step.** Held posts are shown from HTML stored
    when they were written; download filenames are cleaned by a denylist
    and lack the RFC 6266 form. `v5.0.0-1.1.2`, `v5.0.0-1.3.3`,
    `v5.0.0-5.4.2`.
29. **Anti-automation and documented limits.** Socket frames other than
    subscribe have no rate limit; business limits, combined-data rules
    and permitted upload types are not documented. `v5.0.0-2.4.1`,
    `v5.0.0-2.1.2`, `v5.0.0-2.1.3`, `v5.0.0-5.1.1`.
30. **Supply chain and request parsing.** No SBOM (htmx and the fonts are
    in no inventory), the release archive ships tests and benchmarks, and
    a query-string parameter overrides the same one in a POST body.
    `v5.0.0-15.1.2`, `v5.0.0-15.2.3`, `v5.0.0-15.3.7`.
