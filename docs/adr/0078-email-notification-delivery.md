# ADR 0078: Email, Notification Delivery and Communication

## Status

Accepted.

## Date

2026-09-19

## Context

Outbound messages leave the platform's control and can leak private
content, duplicate under retries or be abused for account takeover. GPForum
needs mandatory rules for the email architecture, verification and password
reset flows, digest delivery, notification channels, unsubscribe behavior
and delivery observability. The rules govern the identity, notification and
worker bounded contexts and any feature that sends outbound communication.

## Decision

### Cross-ADR alignment

- ADR 0094 (accessibility): notification and email surfaces MUST be
  accessible. Notification inboxes, badges, read/unread state, digests,
  unsubscribe flows and realtime notification updates MUST expose accessible
  text/state and MUST NOT rely on badge-only, color-only or disruptive
  live-region behavior.
- ADR 0101 (retrieval): digests, feed emails, notification excerpts and
  syndication-adjacent communication MUST remain permission-aware,
  moderation-aware, deletion-aware, anti-leak, rate-limited, and derived
  from safe canonical or projection state.

### Communication philosophy

Outbound communication is a user trust boundary.

GPForum MUST send messages that are: expected; permission-aware;
rate-limited; auditable; privacy-safe; unsubscribe-aware where applicable.

The platform MUST avoid: leaking private content in email; sending duplicate
messages during retries; exposing moderation secrets; relying on email as a
secure identity proof after account compromise.

### Email use cases

- Email MAY be used for: account verification; password reset; security
  alerts; notification delivery; digest delivery; moderation notifications;
  policy updates.
- Security-sensitive email MUST use short-lived signed tokens.

### Delivery architecture

- Email delivery MUST be asynchronous.
- HTTP requests MUST NOT block on provider delivery.
- Delivery attempts MUST record: message type; recipient user; provider;
  status; `attempted_at`; error code; correlation id.
- Retries MUST be idempotent.

### Templates

- Email templates MUST be: versioned; localizable; plaintext-compatible;
  HTML-safe where HTML email exists.
- Templates MUST NOT include: raw unsafe user HTML; secret tokens in logs;
  private content beyond the minimum required.

### Verification

- Email verification MUST: create a short-lived token; store the token hash,
  not the raw token; bind the token to user and purpose; expire the token;
  emit audit events.
- Verification links MUST be single-purpose.

### Password reset

Password reset MUST: avoid confirming whether an email exists; use
short-lived hashed tokens; revoke active sessions after successful reset
where policy requires; emit security events; rate-limit requests.

### Digests

- Digest delivery SHOULD: respect subscriptions; respect notification
  preferences; respect visibility at generation time; avoid duplicate
  content; support unsubscribe.
- Digest generation MUST be asynchronous.

### Bounce and complaint handling

- The platform SHOULD support: bounce processing; complaint processing;
  delivery suppression; provider webhook signature validation.
- Users with failing email delivery SHOULD not cause unbounded retry loops.

### Unsubscribe

- Non-security notification emails MUST support unsubscribe.
- Unsubscribe links MUST be scoped and safe.
- Security alerts SHOULD remain deliverable unless the account email is
  invalid or policy requires suppression.

### Amendment 2026-10-15: preferences by kind and one-click unsubscribe

Backlog D02 and D05, with the minimal email delivery (D04) they need to
mean anything. Migration 117.

- **Kinds.** A member controls three kinds of notification, each for the
  inbox and for email, beside the existing channel switches: replies in
  threads they follow (`reply`, and `follow` activity), mentions
  (`mention`) and moderation notices about their own posts
  (`review_approved`, `review_rejected`). A notification type outside
  these follows the channel switches alone and is never emailed. Quotes
  have no notification of their own yet; a kind is added when a type that
  belongs to it exists. Choices live in `notification_type_preferences`
  (one row per member, kind and channel); a missing row is the default:
  every kind in the inbox, email for mentions and moderation notices, not
  for replies (a busy thread would otherwise flood the inbox of everyone
  following it). The settings form posts them with the channels, under
  the same command log entry, kinds checked before anything is written.
- **Delivery plan.** `api.notification_delivery_plan` answers in one read
  where a notification goes: the inbox when the in-app channel and the
  kind's in-app switch are on; email when the email channel and the
  kind's email switch are on and the account is active with a verified
  address. The dispatcher asks it for every recipient (fanout included,
  after the ADR 0102 permission check and before the ADR 0130 relation
  check); a failed read keeps the inbox and drops the email.
- **Email delivery.** A notification taken by email is a
  `notification.email.requested` event in the event log and the outbox,
  in the delivery's transaction, its id derived from the notification's
  idempotency key, so a retried fanout queues it once. It carries the
  type, source and thread, never the address. The worker handler
  (`NotificationMail`, under the idempotent job runner as
  `worker.notification_mail`) asks the plan again when it sends, so an
  unsubscribe or a lost verification in between is honoured, and sends a
  plain-text mail in the member's locale (the renderer's existing
  `email_subject`/`email_body` templates), linking the thread or the
  inbox, with no post text. Each notification is its own mail; digests
  (D01) remain open.
- **Unsubscribe.** Every notification mail carries an unsubscribe link and
  the RFC 8058 headers `List-Unsubscribe: <https://…/unsubscribe/TOKEN>`
  and `List-Unsubscribe-Post: List-Unsubscribe=One-Click`. The token is
  the member id and a scope (the mail's kind, or `all`) signed with
  HMAC-SHA-256 under the application's signing secrets and a fixed
  purpose; it needs no storage, does not expire (a link in an old mail
  must keep working), survives secret rotation while the old secret is
  listed, and can only ever turn email off. `GET /unsubscribe/TOKEN`
  changes nothing (mail scanners follow links): it shows the scope, the
  choice of all notification email, and a button posting with CSRF. The
  mail client's one-click `POST` (body `List-Unsubscribe=One-Click`) has no
  session; the signed token is its credential, so it is accepted without
  a CSRF token and stops the mail's kind. Both are rate limited by
  address (`identity.unsubscribe`) and need no sign-in. `api.notification_unsubscribe`
  turns the kind's email (or the email channel) off and audits a change
  as `notification.email_unsubscribed` with its scope and how it was made;
  no change, no audit. The headers count as one-click only under a DKIM
  signature covering them, which the sending MTA adds.
- **Transactional mail.** Verification, password reset, email change and
  the console's test message never carry the headers and are never
  governed by these preferences.
- **Portability.** The export includes the member's stored choices
  (`portability_export_parts` v14). They are settings, not content: an
  erased account keeps no address, so nothing is mailed and the rows go
  with the user row.

## Consequences

- Email is always sent asynchronously, so request latency is independent of
  provider latency and retries can be made idempotent.
- Tokens are stored only as hashes and bound to a purpose, which limits the
  damage of a database or log leak.
- Delivery attempts become auditable records, adding a table and retention
  obligation (ADR 0074).
- Open conflicts: delivery-attempt records, digests and bounce or
  complaint handling do not exist yet. Notification email is sent
  asynchronously through the outbox (amendment of 2026-10-15) and identity
  mail through its own outbox event; `docs/audit/email-lifecycle.md`
  records that verification and reset tokens are hashed, single-use and
  expiring.

## Related Decisions and Implementation

- ADRs: 0094 and 0101 (cross-alignment), 0056 (workers), 0074 (privacy and
  retention), 0077 (email configuration), 0085 (webhook contracts); 0009 and
  0025 (outbox retry), 0014 (identity workflow), 0015 (attachment and
  notification workflow), 0043 (notification access).
- Code: `lib/GPForum/Service/Identity/TokenStore.pm`,
  `lib/GPForum/Service/Identity/AccountStore.pm`,
  `lib/GPForum/Controller/Identity/Email.pm`,
  `lib/GPForum/Controller/Identity/Password.pm`,
  `lib/GPForum/Service/Notification/`.
- Code (2026-10-15): `lib/GPForum/Service/Notification/PreferenceStore.pm`,
  `lib/GPForum/Service/Notification/UnsubscribeToken.pm`,
  `lib/GPForum/Worker/Handler/NotificationMail.pm`,
  `lib/GPForum/Controller/Identity/Unsubscribe.pm`.
- Migrations: `migrations/005_notifications_subscriptions.sql`,
  `migrations/025_identity_lifecycle_tokens.sql`,
  `migrations/117_notification_type_preferences.sql`.
- Tests: `t/06-identity-web.t`, `t/integration/postgres-identity-stores.t`,
  `t/17-notifications.t`, `t/107-notification-workflow.t`,
  `t/110-identity-account-store.t`, `t/685-notification-preferences.t`,
  `t/integration/postgres-notification-preferences.t`.
- Docs: `docs/audit/email-lifecycle.md`,
  `docs/architecture/notification-workflow.md`.
