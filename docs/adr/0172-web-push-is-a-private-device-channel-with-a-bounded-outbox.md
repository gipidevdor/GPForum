# ADR 0172: Web Push Is a Private Device Channel with a Bounded Outbox

## Status

Accepted.

## Date

2026-11-06

## Context

Notifications already use transactional outbox semantics, batched recipient
screening and versioned PostgreSQL APIs. Web Push adds untrusted capability
URLs and background delivery through browser infrastructure. Provider delays
must not occupy publishing requests or the existing dispatch lane.

## Decision

- Add an independent device channel and PostgreSQL delivery outbox. Enqueue
  with the notification transaction, including batched fanout and delivery
  with other channels disabled. Run a separate native Perl sender.
- Bind consent to one account and live server session. Require same-origin
  authenticated CSRF-protected writes and an encrypted single-use visible
  receipt proof. Bound registration rates and device counts.
- Remove bindings and jobs transactionally on revocation or account
  suspension/deletion. Export consent metadata only. Encrypt capabilities
  with owner/purpose authentication and an independent storage key.
- Use RFC 8291 encryption and RFC 8292 VAPID. Keep signing, per-message ECDH
  and storage keys separate. Preserve old signing identities until their
  subscriptions are replaced or revoked.
- Allow approved public HTTPS providers only; pin checked DNS peers while
  preserving TLS hostname validation. Reject redirects and proxy discovery.
  Bound concurrency, caches, payloads, responses and deadlines.
- Resolve peers before refreshing the entire batch's consent, session and
  permission state in one query. Claim and finish batches without holding a
  transaction during network calls. Coalesce bursts and never extend expiry.
- Display generic activity alerts only. A minimal service worker opens the
  fixed inbox, without intercepting fetches or caching application content.

## Consequences

Deployment adds a supervised native worker and persistent key files. Browser
Push services observe routing/timing metadata. Acceptance is not display or
reading, retries can duplicate delivery, and accepted messages cannot reliably
be recalled. Generic payloads constrain the resulting privacy exposure.
Production capacity and browser behavior require deployment-specific tests.

The current limits and deployment procedure are in
[Web Push](../ops/web-push.md).

The host service catalogue includes the sender when Push is enabled. Generated
systemd, rc.d and launchd files share the web runtime, account and environment;
start/restart guidance and doctor observe the same conditional service list.
A disabled launchd sender can exit successfully without a restart loop.
