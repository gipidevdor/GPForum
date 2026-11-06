# Network integrations, contract 1

The frozen local Plugin API v1 still parses plain URLs or equation spans only.
Network capabilities live in core services and outbox workers. They do not give
provider modules a controller, database handle, credentials or HTML authority.
Telegram is excluded. Reddit, X, TikTok and LinkedIn remain on demand.

**Menu → Admin → Integrations** is the common entry point for all thirteen
installed modules, selected Discord announcements, moderated feeds and optional
OpenID login. Every card links to its workflow or the exact settings still
missing. Unconfigured federated modules remain visible. Status describes local
configuration; it does not claim a provider or worker is reachable. The page
also links to native media publication, upload review, jobs and diagnostics.

Discord and OpenID require a canonical public HTTPS hostname on port 443,
accepted by the same URL policy as their runtime services. The panel lists this
prerequisite alongside missing endpoints or credentials. Incomplete OpenID
configuration does not offer a login button. Discord cannot queue new work
without its prerequisites; an existing queued announcement is refused before
being marked as sending if public configuration becomes incompatible.

## Activate

Install the locked dependencies, apply all pending migrations (through 2038 in this release) with the
administrative database configuration, refresh the catalogue-based runtime API
role grants, then restart web and outbox processes. Existing site settings and
link modules remain compatible. Crypt::JWT 0.038 or later is required; the
snapshot pins the actual distribution. Core verifies response and token data;
remote HTML is never trusted as a post body.

Optional settings are available in **Admin → Forum settings**. Secrets are
sealed in PostgreSQL, are never redisplayed, and blank fields preserve existing
values. Network secrets accept at most 192 UTF-8 bytes, including the complete
Discord webhook URL; this fits the bounded sealed-secret format. Use **Reset**
to return a secret to its deployment value; with no deployment webhook, this
disables Discord. An unreadable saved network secret disables Discord and OIDC
without reviving deployment credentials. An empty Discord webhook or OIDC issuer disables that feature. If current
administrator policy cannot be read, network features stop without falling
back to an earlier environment credential; local login/recovery remains separate. These
settings are also available through deployment-owned environment variables:

```sh
GPFORUM_MASTODON_HOSTS="social.example.org"
GPFORUM_PEERTUBE_HOSTS="video.example.org"
GPFORUM_DISCORD_WEBHOOK=""
GPFORUM_SYNDICATION_SOURCES="https://publisher.example.org/feed.atom"
GPFORUM_OIDC_ISSUER=""
GPFORUM_OIDC_AUTHORIZATION_ENDPOINT=""
GPFORUM_OIDC_TOKEN_ENDPOINT=""
GPFORUM_OIDC_JWKS_URI=""
GPFORUM_OIDC_CLIENT_ID=""
GPFORUM_OIDC_CLIENT_SECRET=""
GPFORUM_OIDC_SIGNING_ALGORITHM=RS256
```

Replace example hostnames with reviewed real ones. Instance lists are exact
lowercase hostnames separated by spaces, without wildcard subdomains. Save
these lists in **Admin → Forum settings**, then enable Mastodon or PeerTube in
**Admin → Plugins**. Changes saved in the GUI apply without restarting; changing
the deployment environment itself still requires restarting the processes.
Empty lists keep the corresponding provider inactive without breaking forum
startup; previously saved enable choices apply again to a newly authorized
list. The cache variant includes the active origin policy. Only authorized
PeerTube origins enter the player CSP. Vimeo preserves unlisted
privacy hashes and loads its player only after the reader clicks.

The network client accepts credential-free HTTPS URLs on port 443, verifies
TLS for the original hostname, resolves and pins a public IPv4 peer for the
request, and rejects private/reserved or mixed public/private DNS answers.
There are no redirects, unbounded downloads or automatic client-side retries.
Compression negotiation and automatic decompression are disabled; encoded
responses are refused so compressed data cannot bypass the output bound.
Each response is limited to one MiB, connection timeout is three seconds and
request timeout is ten seconds. IPv6-only endpoints and HTTP proxy routing are
not supported by this initial contract. An endpoint change is an operator
configuration decision, never taken from a remote response or token header.

## Selected public-topic announcements

Open `/admin/integrations` through **Admin → Plugins**. Select one of the
recent public discussions and queue its announcement to the configured Discord
incoming webhook. The server requires global administration permission, MFA
policy, participation, CSRF and rate checks. Selection is deduplicated by topic
and destination. Queuing and its audit/event commit together.

The event is `integration.discord.requested`, schema version 1, carrying only
`announcement_id`. Core looks up the topic; queued titles and post bodies are
not delivery authority. It rechecks the space, category and topic immediately
before sending. It holds those rows against visibility changes during the
bounded external request. A topic that became restricted or deleted is
cancelled. Only the current title and canonical forum URL are sent; mentions
and rich embeds are suppressed. Configuring another webhook does not redirect
an existing queued announcement to it.

Discord API v10 executes the webhook with `wait=true`. A confirmed message id
is recorded before the event is acknowledged. A definite 429 refusal returns
the row to the queue, with the provider's upward-rounded retry delay preserved
by the outbox. The existing five-attempt retry cap and dead-letter controls
apply. No retry occurs earlier than the longer of that delay and normal
backoff; delays beyond one day require operator intervention.

A lost response, an ambiguous server failure, or a crash after the durable
sending marker becomes **Check remote outcome**. The worker never blindly
resends it. Check Discord first; the administration page offers a deliberate,
audited retry with a required confirmation and reason. This is not a claim
of exactly-once delivery across a database and a remote webhook API.

## Moderated RSS/Atom imports

Configure exact, public HTTPS source URLs and use **Check for new entries** on
`/admin/integrations`. The event `integration.feed.requested`, schema version 1,
carries `source_url`. The worker checks the current allowlist again before
fetching it. Polling is serialized per source at no more than once per five
minutes. HTTP ETag and Last-Modified cursors support conditional fetches.

RSS 2 and Atom 1 supply at most 100 candidates per response. A candidate stores
only title, source URL, entry identity hash and canonical article URL. Document
types/entities are refused; descriptions, scripts, images and remote HTML are
not imported. Unique source/entry hashes and unique URL hashes deduplicate
repeated and concurrent imports, including candidates previously rejected.
This matches exact normalized URLs/entry ids, not semantically similar articles.

An administrator must separately inspect provenance and appropriateness before
choosing **Approve and publish** and a public category. Publication uses the
normal forum workflow, with its current permissions and content controls,
inside the same transaction as the candidate decision and audit. The new
post contains the original article link and feed source; it does not reproduce
the article. Rejection remains stored so the same entry cannot return as new.
The existing public Atom feed and forum visibility rules include approved
public discussions without a second outgoing-feed implementation.

This is human review with technical gates, not automatic proof of legality or
copyright ownership. An authorized publisher can still supply inappropriate
content; the reviewer must refuse it. Removing a source also prevents approval
of its pending candidates.

## Optional OIDC login and independent recovery

Register a confidential OIDC client with the exact callback formed from
`GPFORUM_PUBLIC_BASE_URL` plus `/auth/oidc/callback`, including any mount path.
Pin the issuer, authorization endpoint, token endpoint and JWKS URI. The token
endpoint must support `client_secret_post` and S256 PKCE. Use RS256, or explicitly
configure ES256; no symmetric, unsigned or token-selected algorithm is accepted.
No discovery or token-supplied key URL can widen the configured network origins.

Members first create and verify a local account through the existing admission
flow. In **Account security → External login**, linking requires the current
local password and a fresh local MFA/recovery code when enabled. Provider
reauthentication is requested and verified for linking. A binding is the exact
issuer and case-sensitive subject, never an email address. Another local
account cannot take over an existing binding. There is no automatic registration,
email-based merging, provider password reset or social-provider SDK in this
contract.

Authorization uses code flow, S256 PKCE, nonce and browser-bound single-use
state expiring after five minutes. Core consumes state before code exchange;
provider configuration changes invalidate a pending flow. Signed ID tokens must
match the pinned algorithm, issuer, audience, authorized party, nonce and time
claims. Claims and access/ID tokens are not persisted. External authentication
then follows the ordinary local MFA challenge and server-session/cookie rotation.

Local password recovery stays available if the provider fails. Changing or
resetting the password invalidates its previous identity binding until the
owner explicitly links again. Unlinking requires a fresh local password/MFA
proof, preserves the current local session, revokes other sessions and removes
outstanding transactions/challenges. Deleting an account cascades its bindings.
Disabling OIDC leaves local login/recovery available and denies external starts.

## Verify and roll back

Tests use generated RSA keys, disposable PostgreSQL and simulated remote
responses; they send no real Discord messages and contact no identity provider.
A local NYTProf run of the expansion unit suite (67 assertions, including RSA
key generation and simulated HTTP) completed in 0.92 seconds with about 106 MiB
maximum resident memory. This measures the test process, not provider latency
or production throughput; external requests retain the explicit bounds above.

Exercise a real provider only after the administrator configures reviewed
endpoints and credentials. Check private-topic cancellation, destination
revocation, 429 backoff, uncertain-send recovery and candidate approval before
turning on operational use. API-role catalogue checks cover every new function.

Disable the affected connector or remove its configured destination/source to
stop new work. Retain announcement outcomes, rejected import identities and
binding records during an application rollback; deleting them loses deduplication
or recovery evidence. Existing outbox failures remain visible through the
normal diagnostics and dead-letter tools.

Official references checked 2026-11-02: [Discord webhooks](https://docs.discord.com/developers/resources/webhook),
[Vimeo embedding](https://developer.vimeo.com/api/oembed/videos),
[PeerTube player URLs](https://docs.joinpeertube.org/api/embed-player),
[OpenID Connect Core](https://openid.net/specs/openid-connect-core-1_0.html),
[Crypt::JWT verification](https://metacpan.org/pod/Crypt::JWT),
[Atom](https://www.rfc-editor.org/rfc/rfc4287) and [RSS 2](https://www.rssboard.org/rss-specification).
