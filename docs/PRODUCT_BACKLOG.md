# GPForum verified product backlog

Initial review: 2026-10-11, base commit `3087bf09b778`, with that working tree
inspected. Draft/preview rows were updated against the feature change based on
`b16cfa3`, with local PostgreSQL, HTTP, JavaScript and browser validation on
2026-10-11. Other rows retain the initial review. Status: **proposed post-MVP product plan**. No feature in this
document becomes an accepted architecture decision or a shipped capability by
being listed here.

This backlog reconciles the requested A–L feature inventory with application
routes, schema/migrations, services, workers, templates, assets and existing
tests. The initial inventory is a static repository review; validation of the
draft/preview increment is recorded in the [composer guide][draft-flow]. This
is not a deployed-instance audit. Existing unrelated setup changes are outside this review.

[ADR 0068](adr/0068-mvp-roadmap-sequencing.md) remains the binding roadmap.
The [release criteria](../ROADMAP.md#release-readiness), the
[readiness review](release/readiness-review.md) and
[quality program](QUALITY_PROGRAM.md) retain their gates and work priorities.
The historical completion of milestones 0–10 does not establish completion
of these proposed features or current production readiness.

## Reading the inventory

- **Present:** a product workflow is visible in the inspected implementation.
- **Partial:** a usable subset exists; the row states the missing increment.
- **Foundation:** schema or internal modules exist, but the requested product
  workflow is incomplete or unwired.
- **Not found:** no implementation was found in the inspected product surfaces.
  Recheck before implementation; this is not proof about every historical branch.
- **Evidence needed:** repository checks exist, but the requested external or
  runtime assurance was not established here.

The source links in each row anchor positive findings and delimit the surfaces
searched for missing behavior. PB identifiers refer to the proposed work packages
below. A row marked **Maintain** is existing functionality, not new feature debt.
The two draft rows share PB-10; typing indicators and collaborative editing are
separate deliverables. Related rows share packages without counting as duplicate
features.

Comparison products inform user needs, not an assertion that every feature is
standard in every installation. Discourse describes its capabilities on its
[feature page](https://www.discourse.org/features); Flarum and NodeBB document
extension/plugin installation as part of their ecosystems
([Flarum](https://docs.flarum.org/2.x/extensions/),
[NodeBB](https://docs.nodebb.org/configuring/plugins/)). Version, enabled
extensions and hosting configuration must be specified for any future parity
claim. No competitor source code or assets were imported for this review.

## A. Engagement and conversation

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| A01 | Emoji reactions | Done 2026-10-22 (ADR 0145): four reactions (heart, laugh, celebrate, think) beside the like, one row each (`post_reactions`, migration 133), never on one's own post, counted from rows, erased and exported with the account; read with the thread page's one statement. No custom emoji. [routes], [post-model] | PB-01 |
| A02 | Likes / upvotes / downvotes | Done 2026-10-15 for the reversible like (ADR 0129): one per member and post, not on one's own, counted from rows, erased and exported with the account; votes remain a product decision. [routes] | PB-01 |
| A03 | Polls | Not found in schema, posting workflows or composer. [routes], [composer] | PB-03 |
| A04 | Reply to a particular post | Done 2026-10-15 (ADR 0132): "Reply" and "Quote" under a post open the composer naming it; the link is written after the reply (`post_replies`, migration 114) and shown as "In reply to #N" under the byline. Notifications and feeds do not follow it yet. [post-model], [markup] | PB-10 |
| A05 | Draft autosave | Present in the current change; locally validated. Private thread/reply drafts, revision conflicts, serialized progressive autosave and native Save. [draft-flow], [draft-client], [draft-schema] | PB-10 / Maintain |
| A06 | Rich live preview | Present for the existing safe markup subset in the current change; locally validated. Native Preview and debounced live preview use the canonical post renderer. WYSIWYG/full Markdown remain separate. [draft-flow], [draft-client], [markup] | PB-10 / Maintain |
| A07 | Collaborative editing / typing indicators | Not found. Specify typing presence separately from concurrent document editing. [realtime], [routes] | PB-10 / Defer collaborative editing |
| A08 | Advanced bookmarks | Folders done 2026-10-15 (ADR 0136): a folder named with the note or from the bookmarks page (`bookmark_folders`, migration 121), the page filters by folder and names them with counts. Reminders are not done. [thread-tools], [bookmarks] | PB-13 |
| A09 | Save an unpublished thread | Present in the current change; locally validated. Owner-only title/category/body/visibility drafts with resume/delete, 100-draft quota and 30-day expiry. [draft-flow], [draft-schema], [new-thread] | PB-10 / Maintain |

## B. Content organization

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| B01 | Thread tags | Done 2026-10-15 (ADR 0135): up to five tags named with the title (`tags` + `thread_tags`, migration 117), chips on the thread, category and home rows, `/tags` index and `/tags/:slug` pages. No rename or merge yet. [forum-schema], [routes] | PB-02 |
| B02 | Multiple tags / combined filters | Partly done 2026-10-15 (ADR 0135): a thread carries up to five; the tag page filters by one tag and optionally one category, permission-aware (ADR 0102). All/any filters across tags and search by tag are not done. [search], [forum-schema] | PB-02 |
| B03 | Deep subcategory tree | Partial: fixed space → category → thread hierarchy; categories have no parent field. [forum-schema] | PB-11 |
| B04 | Managed thread prefixes | Not found as structured metadata or staff workflow. [forum-schema], [routes] | PB-11 |
| B05 | Sticky / pinned administration | Done 2026-10-15: pin/unpin routes, the staff action in the thread's tools and on the moderation actions page, the badge on the thread page and in every list; read ordering was already by pin. [forum-schema], [thread-reader], [routes] | PB-11 |
| B06 | Global announcements / site banners | Done 2026-10-15 (ADR 0131): administrators publish and retire plain-text announcements from `/admin/announcements`; every page shows the active ones, newest first, up to three; the public cache is purged with the write (migration 113). Scheduling and dismissal are not taken. [routes], [admin-settings] | PB-11 |
| B07 | Wiki / knowledge base | Not found as a product workflow. [routes] | PB-19 / Defer |
| B08 | Long-form documents / articles | Not found as a distinct content type. [routes], [post-model] | PB-19 / Defer |
| B09 | Event calendar | Not found. [routes], [forum-schema] | PB-19 / Defer |
| B10 | Automatic FAQ / reusable moderator answers | Not found; split FAQ generation from curated response templates. [routes] | PB-19 |

## C. Social and messaging

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| C01 | Direct messages | Done 2026-10-17 (ADR 0139): one private conversation per pair of members (`direct_conversations`, `direct_conversation_members`, `direct_messages`, migration 128), started from a profile (`/messages/new/:username`), listed on `/messages` with unread counts, read and answered on `/messages/:id` (read state per member, plain text up to 5000 characters, never cached, 404 to anyone else). The recipient is notified of the first unread message of a run in the inbox and by email (new notification kind `message`, unsubscribe link included) and gets a realtime hint; nothing carries the text. Blocks refuse messages either way, ignores silence their notices, suspended members cannot send, automod screens them, new members start at most 3 conversations a day (20 otherwise). A participant reports a message; staff read only a reported message, through an audited form. Erasure and export cover them. No editing or deleting of a sent message. [routes] | PB-07 |
| C02 | Private group conversations | Not found; a separate increment after participant authorization and abuse controls. [routes] | PB-07 |
| C03 | Rich profiles | Partial: join date, public activity, contribution counts and, since 2026-10-15, a bio (plain text, 500 characters, set in Settings, erased and exported with the account; migration 111). Custom fields and social links were not found. [profile] | PB-13 |
| C04 | Avatar upload / crop | Done 2026-10-17: `/settings/avatar` uploads a PNG, JPEG, GIF or WebP (5 MB, 8,000 px a side) through the attachment validation and malware scan; the system's image tool (vipsthumbnail, or sips on macOS) centre-crops it to squares of 64/128/256 px, metadata stripped; shown on profiles and beside posts instead of the initial; replace and remove; staff with `avatar.moderate` remove one from the profile, audited; erasure deletes files and rows, export names it (ADR 0144, migration 131). [profile], [posts] | PB-13 |
| C05 | Badges / achievements / medals | Partial: trust-derived contributor badge exists; separate achievement/award system was not found. [profile], [profile-reader] | PB-13 |
| C06 | Visible trust levels | Present, basic: profile shows reputation score, badge and numeric level. Further explanations and privilege UX are optional increments. [profile], [reputation] | Maintain / PB-13 |
| C07 | Ignore / block a user | Done 2026-10-15: ignore and block from the member's profile, the list (at most 500) on `/settings/ignored`; ignored members' posts collapse in threads, their replies and mentions leave the inbox, badge and mentions page; a blocked member cannot mention; staff notices are never silenced; erasure and export cover the list (ADR 0130). Direct messages refuse a block either way (ADR 0139). [routes] | PB-06 |
| C08 | Friends / follow users | Not found; thread subscriptions and a followed-thread feed exist. [routes], [feed] | PB-13 |
| C09 | Group / here / everyone mentions | Partial: username mentions exist with permission checks and bounded fanout; group/broadcast semantics were not found. [mentions] | PB-13 |

## D. Notifications and email

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| D01 | Daily / weekly email digest | Done 2026-10-15: with the Digest channel on (daily or weekly) and email on, the hourly `notification_digests` scheduled job queues one digest per member and UTC day or week (recorded once, bounded by `--limit`, resumable) of unread posts in followed threads and followed categories, read with the member's permissions; the worker mails it in their locale as text and HTML with a one-click unsubscribe that turns the digest off (migration 119, ADR 0078 amended). No page creates a category follow yet. [notification-prefs], [notification-dispatch], [workers] | PB-08 |
| D02 | Preferences by notification type | Done 2026-10-15: per-kind switches (replies in followed threads, mentions, moderation notices) for the inbox and email in settings, beside the channel switches; fanout reads them through one delivery plan (migration 118, ADR 0078 amended). [settings], [notification-prefs] | PB-08 |
| D03 | Web push | Not found; no subscription or service-worker delivery workflow. [routes], [manifest] | PB-16 |
| D04 | Email every reply / first reply | Partial 2026-10-15: a notification of a kind the member takes by email (replies in followed threads when switched on) is queued in the outbox and mailed in their locale, one mail per notification; a first-reply-only mode was not built. [notification-dispatch], [workers] | PB-08 |
| D05 | One-click email unsubscribe | Done 2026-10-15: every notification mail has a signed `/unsubscribe/TOKEN` link and RFC 8058 `List-Unsubscribe`/`List-Unsubscribe-Post` headers; GET shows the choice, the button or one-click POST turns that kind (or all notification email) off, audited; identity mail never carries them. [thread-tools], [identity-mail] | PB-08 |

## E. Identity and access

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| E01 | Social login | Not found; current login uses password credentials and email lifecycle. [routes], [credential-store] | PB-20 |
| E02 | Enterprise SSO / SAML / OIDC | Not found as authentication workflows. OIDC login and OAuth authorization must have explicit contracts. [routes] | PB-20 |
| E03 | TOTP second factor | Done 2026-10-17 (ADR 0142): RFC 6238 codes (SHA-1, 6 digits, 30 s, one step of drift, each step used once) from a 160-bit secret sealed in `second_factors` with `GPFORUM_SECOND_FACTOR_KEY` (encrypt-then-MAC over HMAC-SHA-256, bound to the member; rotation through `GPFORUM_SECOND_FACTOR_KEYS`, resealed at the next sign-in), migration 130. `/settings/security`: the password begins enrollment, a server-drawn SVG QR code and the typed key add it to an app, the first code turns it on, ends the other sessions and shows ten single-use recovery codes (SHA-256, renewable with a code); the password and a code turn it off. Login: a password that verifies opens a challenge (token in the signed cookie, hash stored) answered on `/login/second-factor` within 5 minutes and 5 tries; 10 wrong answers in an hour lock sign-in for the hour. Audit events and localized notice mails for enabled, disabled, reset and locked. Staff see the state on the member's admin page, never the secret; administrators reset a member's and, on `/admin/security`, require it of staff (`admin_permission_allowed_v4` refuses staff consoles to staff without it; their login sends them to set it up). Erasure deletes it; the export says whether it is on. Suspended members may manage it. No WebAuthn, no SMS. [identity-schema], [routes] | PB-04 |
| E04 | WebAuthn / passkeys | Foundation: credential type placeholder exists; ceremony/enrollment/recovery were not found. [identity-schema], [routes] | PB-20 |
| E05 | Magic-link login | Not found; email verification tokens are a different lifecycle. [routes], [identity-mail] | PB-20 |
| E06 | Passwordless login | Not found. [routes], [credential-store] | PB-20 |
| E07 | Registration invitations | Not found in registration workflow or routes. [routes], [identity-flow] | PB-20 |
| E08 | Manual registration approval | Not found; pending/email confirmation does not imply staff approval. [identity-flow] | PB-20 |
| E09 | Registration CAPTCHA | Not found. Consider an optional adapter only after local abuse controls and provider/privacy review. [routes], [identity-flow] | PB-05 |
| E10 | Multi-provider account linking | Not found; depends on safe external identity verification and explicit linking confirmation. [credential-store] | PB-20 |

## F. Moderation and safety

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| F01 | Moderation queues | Present: report, assign-to-self/release/resolve, hide/restore, suspend and reversible audit workflows. [routes], [reports] | Maintain |
| F02 | Spam service / ML classification | Not found; rate limits, reports and malware scanning already exist. Local rules can be the first increment. [rate-limiter], [workers] | PB-05 |
| F03 | Shadowban | Not found; requires an explicit product/privacy decision before adoption. [routes], [moderation-flow] | PB-18 / Defer |
| F04 | Private notes on users | Done 2026-10-17 (ADR 0138): staff holding `member_note.view` read private notes on a member (`member_notes`, migration 125) on the member's admin page and, the three newest, beside every report about the member's profile, posts or threads; `member_note.write` adds, edits and deletes them (CSRF, rate limit, suspended staff refused), every change audited without the text. Never shown to the member, in no feed, search, event or realtime message; left out of the export, deleted by erasure. No note history beyond the audit log. [reports], [moderation-schema] | PB-18 |
| F05 | First-post review queue | Done 2026-10-15: a review rule in `/admin/automod` holds a member's new threads and replies while they have fewer published posts than its number (0–20, off by default), and optionally the posts automod flags; held posts live outside threads and posts, so nothing reads them but the author's `/pending` list (with withdraw) and the staff queue `/moderation/review`, where staff publish (as the author's own command, rechecked) or reject with a reason; the author is notified, and every hold, decision and rule change is audited (ADR 0134). [moderation-flow], [routes] | PB-05 |
| F06 | Automod regex / links / flood | Done 2026-10-15: a link rule in `/admin/automod` limits the links in a post by a member below a trust level (blocked or flagged, off by default); patterns are bounded literal words with an optional end star, never staff-written regular expressions; flooding stays with the posting rate limiter; every decision is audited (ADR 0133). [rate-limiter], [routes] | PB-05 |
| F07 | Watched words | Done 2026-10-15: up to 500 watched words or phrases in `/admin/automod`, each blocking, flagging (a system report in the moderation queue) or replacing what it matches in new threads, replies and edits; staff who moderate are not screened; every change and decision is audited (ADR 0133). [moderation-flow], [routes] | PB-05 |
| F08 | IP / range ban administration | Not found as staff workflow; account suspension and per-address throttling exist. [routes], [rate-limiter] | PB-18 |
| F09 | Attachment content moderation | Partial: scan/quarantine/lifecycle infrastructure exists; a richer staff review workflow needs specification and verification. [attachment-flow], [workers] | PB-18 |
| F10 | Snooze / advanced report assignment | Partial: assign-to-self, release and resolve are implemented; snooze and arbitrary assignee UX were not found. [reports], [routes] | PB-18 |

## G. Search and discovery

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| G01 | PostgreSQL full-text search | Present, including permissions, snippets and title autocomplete/trigram matching. [search] | Maintain |
| G02 | Author/category/date filters | Present, basic: category/author scope and date controls work; typed operators and richer selectors remain. [search-form], [search] | PB-12 |
| G03 | Explicit title-only / post-only search | Done 2026-10-15: the search form offers Everything / Thread titles / Posts (`scope`), bound as the document's entity type on both the function and the ORM path (migration 110, `search_ranked_v7/v8`). [search-form], [search] | PB-12 |
| G04 | Similar threads while composing | Done 2026-10-15: as a title is typed on the new-thread form, the threads it resembles are listed under it (the bounded, permission-aware autocomplete, no new index); nothing without the page's script. [new-thread], [search] | PB-12 |
| G05 | Configurable hot/trending ranking | Not found. Specify transparent ranking, abuse resistance and query budget before adoption. [feed], [search] | PB-12 |
| G06 | Explore beyond followed threads | Partial: home/latest content and followed feed exist; richer discovery remains. [routes], [feed] | PB-12 |

## H. Media and editor

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| H01 | Restricted markup / no raw HTML | Present, deliberate security boundary. [markup] | Maintain |
| H02 | WYSIWYG | Not found; an optional enhancement needs to preserve safe markup and SSR fallback. [composer], [markup] | PB-10 / Later |
| H03 | Complete Markdown | Partial by choice: emphasis, safe links, quotes and code exist; headings/lists/tables/footnotes are outside the current subset. [markup] | PB-10 / Product decision |
| H04 | Image/PDF/text upload, 25 MiB, malware scan | Present as bounded attachment workflows; external operational evidence remains governed by readiness gates. [attachment-validator], [attachment-flow] | Maintain |
| H05 | Gallery / lightbox | Not found; posts currently expose attachment download links. [posts] | PB-14 |
| H06 | Rich third-party embeds | Not found in renderer/product workflows. [markup], [posts] | PB-14 |
| H07 | GIF / emoji picker | Not found; split local Unicode emoji selection from third-party GIF retrieval. [composer] | PB-14 |
| H08 | Screenshot paste enhancement | Not found as an explicit upload enhancement in composer/client code. [composer], [client] | PB-14 |
| H09 | Native video upload | Not found in upload allowlist/workflow. [attachment-validator] | PB-14 / Later |
| H10 | Audio upload | Not found in upload allowlist/workflow. [attachment-validator] | PB-14 / Later |

## I. Internationalization and accessibility

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| I01 | English and Italian | Present. [locales], [i18n] | Maintain |
| I02 | More complete UI languages | Not found among shipped locales; translation infrastructure already exists. [locales], [i18n] | PB-17 |
| I03 | RTL | Foundation: HTML direction/CSS hooks and tests exist; no shipped RTL language establishes a complete localized workflow. [layout], [theme-test], [locales] | PB-17 |
| I04 | Light / dark / high contrast | Present, including automatic selection. [theming] | Maintain |
| I05 | Visual theme builder | Not found; token/theme infrastructure exists. [theming], [admin-settings] | PB-17 / Later |
| I06 | Safe per-tenant custom CSS | Not found; current theme support does not establish multi-tenancy or tenant CSS isolation. [theming] | PB-22 / Defer |
| I07 | Independent accessibility audit | Evidence needed: semantic/contrast/focus checks exist; independent conformance review was not established here. [accessibility], [theme-test] | PB-17 |

## J. Integrations and platform

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| J01 | JSON read responses | Present on selected routes. [api], [routes] | Maintain |
| J02 | Public versioned write API | Partial: browser writes can respond in JSON using session/CSRF; public `/api/v1`, integration tokens and a stable documented contract are pending. [api], [mvp] | PB-15 |
| J03 | Outgoing webhooks | Not found as a wired delivery workflow. [workers], [routes] | PB-15 |
| J04 | Public plugin / extension API | Not found. The unwired registry, manifest and hook modules were deleted on 2026-10-15. [adr-0083] | PB-15 / Later |
| J05 | phpBB import | Not found. The unwired job, manifest and legacy-ID services were deleted on 2026-10-15. [adr-0081] | PB-09 |
| J06 | Discourse import | Not found. [adr-0081] | PB-09 / Later |
| J07 | Flarum / NodeBB / vBulletin import | Not found. [adr-0081] | PB-09 / Later |
| J08 | Whole-community migration export | Partial: operational backup and account export exist; a portable forum-wide pack/reimport workflow was not found. [export-builder], [backup] | PB-09 |
| J09 | Native iOS / Android app | Not found. [api], [manifest] | PB-22 / Defer |
| J10 | Advanced PWA install/offline | Foundation: standalone webmanifest exists; service-worker/offline workflow was not found. [manifest] | PB-16 |
| J11 | ActivityPub / federation | Not found as a product workflow. [routes], [workers] | PB-22 / Defer |
| J12 | Slack / Discord bridge | Not found as a product integration. [workers], [routes] | PB-15 / Later |

## K. Product analytics and administration

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| K01 | Admin console | Present: operational summaries, users/roles, categories, settings, diagnostics, jobs and audit. [admin-console], [routes] | Maintain |
| K02 | `/metrics` | Present, operational metrics. [observability], [routes] | Maintain |
| K03 | DAU / retention / funnel analytics | Not found as product analytics workflows; operational counters are separate. [admin-console], [observability] | PB-21 |
| K04 | Community health dashboard | Partial: operational/admin counts exist; participation, engagement and retention views were not found. [admin-console] | PB-21 |
| K05 | A/B tests / feature-flag UI | Not found as an admin workflow; configuration ADR requirements do not establish implementation. [config-adr], [admin-settings] | PB-21 / Later |
| K06 | Audit log | Present; preserve authorization, filtering and reversible action history. [admin-console], [routes] | Maintain |
| K07 | Account export / deletion | Present, including data-rights review/hold/erasure workflows. [export-builder], [privacy] | Maintain |

## L. Product operations

| ID | Feature | Verified status and scope | Package |
| --- | --- | --- | --- |
| L01 | Setup / doctor / backup | Present; keep operational improvements in the existing quality/readiness program. [doctor], [backup], [quality] | Maintain |
| L02 | Multi-tenancy | Not found as an isolated multi-forum product/operation model. [architecture] | PB-22 / Defer |
| L03 | Built-in staging slot / blue-green | Not found as a managed deployment workflow; staging/upgrade/rollback procedures exist. [deployment], [upgrade] | PB-22 / Later |
| L04 | Extension marketplace | Not found. [adr-0083] | PB-22 / Defer |
| L05 | One-click update | Not found; operator upgrade/doctor procedure exists. [upgrade] | PB-22 / Later |

## Proposed priority roadmap

The requested eight high-value gaps remain the first product candidates:
likes/reactions, DMs, tags, polls, stronger authentication, one major-forum
importer, spam controls and email digests. Sequencing below reflects dependency
and privacy risk, rather than a promise of dates or a claim of full parity.

| Wave | Proposed outcome | Dependencies / exit criteria |
| --- | --- | --- |
| P0 — release evidence | Close existing CI/staging, TLS, SMTP delivery, attachment restore, load and rollback gaps. | Follow the current readiness/quality documents; refresh the historical verdict with actual target evidence. No new runtime feature is adopted by this backlog. |
| P1a — everyday discussion | PB-01 likes, PB-02 tags, PB-03 polls; PB-10 drafts/preview delivered as an adjacent usability increment. | P0 gates maintained. Each package independently releasable, with safe migrations, SSR flows, EN/IT and permission tests. |
| P1b — identity and abuse controls | PB-04 TOTP, PB-05 automod/first-post review, PB-06 user blocking. | P0 gates maintained. Publish recovery, review and block semantics before relying on them for messaging. This work can run alongside P1a. |
| P1c — private conversation, mail, migration | PB-07 DMs, PB-08 preferences/digest, PB-09 phpBB import plus portable export. | DMs require PB-06 and adequate PB-05 controls. Digest requires delivery/opt-out semantics. Import requires validated export mapping and a replayable dry run. Mail/import can progress independently of DMs. |
| P2 — richer product and integrations | PB-11–18 and PB-21, plus optional PB-10 editor increments. | Prioritize measured user demand; preserve existing readiness, performance and privacy gates. |
| Deferred — explicit scope decisions | PB-19 knowledge content, PB-20 broader identity options, PB-22 platform expansion; collaborative editing, shadowban, marketplace, federation, native apps and multi-tenancy. | Require a separate scope/design decision and evidence of demand. Social OIDC login may replace or supplement PB-04 if adoption makes it the stronger identity priority. |

Prioritizing OIDC instead of TOTP changes delivery order, not security guarantees:
social login alone does not provide GPForum's own second-factor protection.

### First product packages and acceptance criteria

These are proposed specifications. Before coding, settle the recorded decisions
and write/amend ADRs for changed contracts under [governance](../GOVERNANCE.md).

| Package | First deliverable / pending decision | Acceptance criteria |
| --- | --- | --- |
| PB-01 | Reversible post like; decide self-like policy and whether multiple emoji or downvotes add value. | One actor/target reaction per chosen rule under concurrent retries; authorize against current post visibility; counters remain rebuildable; removal, moderation and account erasure update derived views; accessible SSR action with CSRF and bounded reads. |
| PB-02 | Managed multi-tag threads and tag filtering; decide who creates tags, tag count limit and all/any filter semantics. | Normalize unique identifiers; permission-aware tag lists/counts/search/feed; audited rename/merge/delete; migrate existing untagged threads safely; keyset queries stay within budgets. |
| PB-03 | Single-choice poll first; decide vote editing, closing and voter visibility. | Options/limits validated; one ballot per voter under races/retries; visibility checked on vote and results; defined behavior for edits/deletion; voter identity protected according to the declared policy; audited staff closure. |
| PB-04 | TOTP enrollment/challenge/recovery; external OIDC login is a separate alternative. | Confirm enrollment before enabling; use reviewed protocol libraries; protect secrets; reject reused challenges, throttle attempts; recovery codes stored as hashes and single-use; reauthentication for reset/removal; session/revocation and recovery tests. |
| PB-05 | Local watched-word/link/flood rules and first-post review; decide hold/reject/report outcomes and authorized overrides. | Bounded rule evaluation; explainable, auditable decisions; queued content unavailable through search/feed/preview/attachments/realtime; staff approval/rejection idempotent; legitimate-user recovery path; tune false positives before any optional external classifier/CAPTCHA. |
| PB-06 | User block/ignore controls; decide which affects content visibility, mentions, notifications and contact attempts. | Enforce server-side on defined surfaces; no message or notification bypass; account deletion cleanup; accessible settings; consistent privacy behavior for both participants. |
| PB-07 | One-to-one DMs, then private groups; decide invitation consent, participant removal/history and retention. | Participant-only reads/writes/attachments; no public search/feed/cache/realtime leakage; block/contact limits; user-initiated reports grant staff only defined access; describe staff-access policy honestly; exports include only conversation content the requester is authorized to access, with explicit treatment of received messages and participant metadata; deletion/retention and race tests. |
| PB-08 | Complete per-event preferences and scheduled daily/weekly digest; decide first/every-reply delivery and unread rules. | Reuse existing preferences; explicit notification-email opt-in on rollout; authorization and opt-out checked at send time; mute/block honored; idempotent schedule/retry; bounded batches; locale/timezone handling; authenticated settings and revocable unsubscribe tokens; applicable one-click mail headers tested; SMTP failure and duplicate-delivery evidence. |
| PB-09 | phpBB importer and versioned community export; decide supported source version/format and permission/BBCode mapping. | Operator-authorized input only; dry-run validation/counts; legacy-ID mapping resumable and replay-safe; preserve dates, attribution and visibility; report unmapped features; no source password hashes in public exports; safe rendering and attachment scans; private-data separation; checksums and a verified export/reimport comparison on synthetic or consented fixtures. |
| PB-10 | Draft thread/reply lifecycle and canonical preview implemented in the current change under [ADR 0128](adr/0128-private-composer-drafts-and-canonical-preview.md); locally validated. Reply-to remains a separate model increment. | Verify owner isolation, 100-live-draft quota, 30-day expiry/bounded cleanup, export/erasure, exact save retries and stale-revision conflicts, failed-publication preservation and atomic consume/replay. Preview target visibility and sanitization follow post rendering; publication rechecks full posting rules. Validate native Save/Preview and JavaScript keyboard/EN/IT flows. Reply-to, typing presence and collaborative editing remain separate deliverables. [draft-flow] |

### Subsequent packages

| Package | Scope | Required evidence before completion |
| --- | --- | --- |
| PB-11 | Pin/unpin administration, managed prefixes/banners; category tree only if justified. | Staff authorization, reversible audit and ordering; accessible banner dismissal; hierarchy permission/move invariants if adopted. |
| PB-12 | Search selectors/operators/scopes, similar threads, richer discovery; ranking later. | Existing filters preserved; restricted metadata/snippets/counts stay hidden; relevant query plans and bounded suggestion requests. |
| PB-13 | Profile bio/fields, avatar, achievement increments, bookmark folders, optional user follows/group mentions. | Safe field rendering, upload/crop validation, visibility/export/erasure; awards explained; bounded mentions with explicit broadcast permission. |
| PB-14 | Image lightbox/paste/emoji first; embeds/GIF providers and audio/video separately. | Keyboard navigation; scans/limits retained; untrusted remote fetches bounded against SSRF; click-to-load embeds; review provider terms, tracking and content rights before integration. |
| PB-15 | Versioned API/scoped tokens, outgoing webhooks; public plugin SDK and bridges later. | Stable documented schemas, auth/revocation/rate limits and contract tests; signed webhook delivery, retries/deduplication and SSRF limits; versioned hook contracts and privacy review before external code runs. |
| PB-16 | Installable PWA, optional web push; define offline scope explicitly. | Manifest/install evidence on supported browsers; authenticated/private content excluded from shared caches; logout clears private local state; push opt-in/revocation and permissions at delivery. |
| PB-17 | External accessibility review, RTL locale, more languages and optional theme tooling. | Track findings to closure; full locale catalogs, keyboard/mobile/RTL checks; token contrast checks; reviewed theme/asset licensing. |
| PB-18 | User moderation notes, report snooze/assignment, attachment review, possible IP bans. | Staff-only access, audited changes, retention/export rules and appeals; correct trusted-proxy/address handling; no silent private-data leakage. Shadowban requires a separate decision. |
| PB-19 | Curated moderator templates; FAQ/wiki/articles/events as independent proposals. | Content ownership, revision/moderation and safe rendering defined; feature-specific authorization and accessibility. |
| PB-20 | OIDC/social login, linking, WebAuthn/passkeys, magic links, invites/manual approval; SAML only on demonstrated demand. | Provider/protocol contract, account takeover/linking tests, recovery/revocation, secret handling and minimal identity claims; provider terms and processing review. |
| PB-21 | Aggregate engagement/community health; A/B/flag administration only if justified. | Define DAU/retention/funnel denominators and retention periods; avoid hidden tracking; restricted cohorts not exposed; measurements reproducible and optional processing governed. |
| PB-22 | Native apps, federation, multi-tenancy, marketplace, deployment slots/update automation. | Separate architecture/scope decisions with migration, isolation, operations and rollback evidence; no implied commitment from this inventory. |

### Shared definition of done

A package is complete only when its acceptance criteria have evidence: canonical
PostgreSQL state; transactional events/audit; idempotent retries; authorized
SSR/JSON/search/feed/notification/attachment/realtime/cache/export surfaces;
safe migrations and rollback/replay notes; EN/IT and accessible interaction;
failure/concurrency tests appropriate to the change; query-budget/profiling
evidence for affected hot paths; dependency review; updated documentation and
accepted ADRs where contracts change. Follow [CONTRIBUTING](../CONTRIBUTING.md)
and the existing release gates. A schema placeholder or passing unit test alone
does not complete a product workflow.

## Original implementation, licensing and data protection

The requested constraint applies to every package: implement from GPForum's own
requirements and architecture. Use public competitor documentation to understand
behavior; do not copy code, templates, prose, branding, screenshots, icons or
other assets without an applicable permission/license and recorded obligations.
The EU software directive distinguishes ideas/principles from protected program
expression; that distinction is not blanket permission to reuse implementation
or other protected material. [Directive 2009/24/EC, Article 1](https://eur-lex.europa.eu/eli/dir/2009/24/oj/eng)

For each introduced dependency or asset, record exact origin/version, license,
required notices and distribution obligations, and review compatibility with
GPForum's [BSD-3-Clause license](../LICENSE). Runtime CPAN additions must update
[CPAN_LICENSE_REVIEW.md](CPAN_LICENSE_REVIEW.md), remain pinned and pass
`script/cpan-license-check`; non-CPAN assets/providers require their own recorded
review. Unknown licensing leaves that material unused until clarified. No new
dependency or third-party asset is introduced by this documentation change.

New DMs, drafts, ballots, identity providers, mail, imports, moderation records
and analytics must declare purpose, legal basis where applicable, access,
retention and export/deletion behavior before collecting data. Minimize personal
data, protect it by default, and review external processing/transfer and optional
tracking implications. These constraints extend
[ADR 0074](adr/0074-privacy-data-protection-legal-operations.md) and the GDPR's
data-protection principles and design/default obligations.
[GDPR, Articles 5, 6 and 25](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng)

Importer fixtures must be synthetic or supplied with authority to process them;
licenses for forum software do not grant rights to other communities' user
content. Embeds, GIF retrieval, CAPTCHA and spam services need review of provider
terms and data flows before adoption. This plan records engineering safeguards;
it does not certify legal compliance of a future deployment or integration.

## Evidence links

These links point to the inspected repository, not copied implementations.
For mail status, current worker wiring and mailer code take precedence over
historical ADR wording that predates the identity mailer.

[routes]: ../lib/GPForum/Bootstrap/Routes.pm
[post-model]: ../lib/GPForum/Schema/Result/Post.pm
[composer]: ../templates/forum/_composer.html.ep
[new-thread]: ../templates/forum/new_thread.html.ep
[markup]: ../lib/GPForum/Service/Forum/BodyRenderer.pm
[realtime]: realtime.md
[thread-tools]: ../templates/forum/_thread_tools.html.ep
[bookmarks]: ../templates/forum/bookmarks.html.ep
[forum-schema]: ../migrations/001-schema/003_forum_projection.sql
[thread-reader]: ../lib/GPForum/Service/Forum/ThreadReader.pm
[admin-settings]: ../lib/GPForum/Service/Admin/Settings.pm
[profile]: ../templates/identity/profile.html.ep
[profile-reader]: ../lib/GPForum/Service/Identity/ProfileReader.pm
[reputation]: ../lib/GPForum/Service/Community/ReputationLedger.pm
[posts]: ../templates/forum/_posts.html.ep
[feed]: ../lib/GPForum/Service/Community/FeedReader.pm
[mentions]: ../lib/GPForum/Service/Community/MentionStore.pm
[notification-prefs]: ../lib/GPForum/Service/Notification/PreferenceStore.pm
[notification-dispatch]: ../lib/GPForum/Service/Notification/Dispatcher.pm
[workers]: ../lib/GPForum/Bootstrap/Workers.pm
[settings]: ../templates/identity/settings.html.ep
[identity-mail]: ../lib/GPForum/Service/Identity/Mailer.pm
[credential-store]: ../lib/GPForum/Service/Identity/CredentialStore.pm
[identity-schema]: ../migrations/001-schema/001_core_identity.sql
[identity-flow]: architecture/identity-workflow.md
[reports]: ../templates/moderation/reports.html.ep
[moderation-flow]: architecture/moderation-workflow.md
[moderation-schema]: ../migrations/001-schema/008_moderation_review.sql
[rate-limiter]: ../lib/GPForum/Service/Operations/RateLimiter.pm
[attachment-flow]: architecture/attachment-workflow.md
[attachment-validator]: ../lib/GPForum/Service/Attachment/Validator.pm
[search-form]: ../templates/forum/search.html.ep
[search]: ../lib/GPForum/Service/Search/Searcher.pm
[client]: ../assets/js/site.js
[locales]: ../lib/GPForum/Service/I18N/Locale.pm
[i18n]: i18n.md
[layout]: ../templates/layouts/default.html.ep
[theme-test]: ../t/65-accessible-theme.t
[theming]: ../THEMING.md
[accessibility]: UI_ACCESSIBILITY.md
[api]: ../API.md
[mvp]: MVP.md
[manifest]: ../site.webmanifest
[adr-0083]: adr/0083-plugin-extension-hook-system.md
[adr-0081]: adr/0081-import-export-legacy-migration.md
[export-builder]: ../lib/GPForum/Service/Portability/ExportBundleBuilder.pm
[backup]: ops/backup-and-restore.md
[admin-console]: ../lib/GPForum/Service/Admin/ConsoleReader.pm
[observability]: OBSERVABILITY.md
[config-adr]: adr/0077-configuration-environments-feature-flags.md
[privacy]: architecture/privacy-workflow.md
[doctor]: ops/doctor.md
[quality]: QUALITY_PROGRAM.md
[architecture]: ../ARCHITECTURE.md
[draft-flow]: architecture/composer-drafts.md
[draft-client]: ../assets/js/composer.js
[draft-schema]: ../migrations/003-evolution/103_forum_drafts.sql
[deployment]: DEPLOYMENT.md
[upgrade]: ops/upgrade.md
