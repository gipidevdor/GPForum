# ADR 0163: Versioned Network Integrations and Explicit External Identity

## Status

Accepted (2026-11-02), under the owner's prioritized integration request.
Telegram is excluded by the owner's subsequent instruction.

## Context

Local link recognition already has a frozen Plugin API v1. The requested
Discord announcements, RSS/Atom imports and optional OIDC login perform
external operations with different authority and recovery needs. Federated
posts/video require explicitly reviewed instances. External responses cannot
become trusted post HTML or decide local account ownership.

## Decision

Keep local providers behind the unchanged contract: Vimeo, GitLab and Codeberg
join the default catalogue; Mastodon and PeerTube are instantiated only for
configured exact hostnames and enabled explicitly. Only active permitted
player origins enter CSP. Players continue loading on click.

Network contract 1 lives in core, with versioned PostgreSQL APIs and explicit
outbox events. Discord sends only selected public-topic titles/URLs. A durable
sending marker precedes the external call; source visibility rows are checked
and protected during the bounded call. Confirmed acknowledgements persist,
definite 429 refusals respect provider retry delays, and ambiguous outcomes
require a checked, audited operator retry. No exactly-once remote-delivery
guarantee is made.

RSS 2/Atom 1 responses stage title/link candidates. Exact source/entry and URL
hashes deduplicate imports, including rejected candidates. Only a separate
human publication decision invokes the ordinary forum posting workflow. The
publication and decision commit together. Existing outgoing feeds are reused;
remote descriptions, scripts, images and HTML are not imported.

All outbound requests use pinned public IPv4 peers, original-host TLS
verification, strict HTTPS endpoints, bounded responses/timeouts and no
redirects. Credentials are server-side, sealed in administrator configuration
and revocable. Network features remain disabled until configured. No real
external messages are sent by tests.

OIDC uses pinned endpoints/algorithm, code flow with S256 PKCE, nonce and
five-minute single-use browser state. Bindings identify an exact issuer and
case-sensitive subject, never an email. An owner must first verify an existing
local account, then link with a fresh password/MFA proof and recent provider
authentication. External login retains the ordinary local MFA and session
rotation. Password changes/recovery invalidate old bindings; unlinking revokes
other sessions and outstanding challenges while preserving local recovery.
No automatic external registration, account merge or provider recovery is added.

Reddit, X, TikTok and LinkedIn remain on demand pending a concrete community
need and a fresh review of provider constraints. Telegram is not implemented.

## Operation and compatibility

Apply migrations 2031 and 2032, refresh runtime API-role grants, install the
locked Crypt::JWT dependency, and restart services before configuring optional
network features. Retain deduplication, delivery-outcome and binding records
when disabling or rolling back application code. See the
[network contract and operator guide](../integration-network-v1.md).

## Validation

Unit tests cover URL spoofing, unlisted Vimeo hashes, explicit federated
origins, RSS/Atom limits and signed/invalid OIDC claims with generated RSA keys.
Disposable-PostgreSQL tests exercise public-topic cancellation, deduplicated
selection, rate limits, uncertain sends, checked recovery, import review and
publication, browser-state replay, explicit linking, password-generation
revocation, local MFA and controller permission/CSRF boundaries. Catalogue and
runtime-role tests validate the versioned SQL boundary. Remote responses are
simulated; real-provider provisioning remains an operator action.
