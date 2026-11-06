# Integration plugins and GUI management

Good Phorum ships eleven default provider modules and two instance-scoped modules behind a fixed, checked
[Plugin API v1](plugin-api-v1.md). [ADR 0159](adr/0159-versioned-integration-plugins.md)
records the extension boundary; [ADR 0160](adr/0160-administrator-gui-configuration.md)
records durable GUI settings.

## Available modules

| Module | Supported links | Display |
| --- | --- | --- |
| YouTube | Watch, youtu.be, Shorts, live and embed video URLs | Link plus player loaded on click |
| Vimeo | Public and unlisted videos, player and collection URLs | Player loaded on click, retaining the privacy hash |
| GitLab | Projects, nested groups, issues, merge requests, commits and releases on gitlab.com | Resource link cards |
| Codeberg | Repositories, issues, pull requests, commits and releases | Resource link cards |
| Mastodon | Posts on explicitly allowed instances | Link cards |
| PeerTube | Short and UUID video links on explicitly allowed instances | Player loaded on click |
| GitHub | Repositories, issues, pull requests, commits and releases | Resource link cards |
| Facebook | Posts, videos, story/permalink URLs, reels and watch URLs | Link cards |
| Instagram | Posts, reels and older TV URLs | Link cards |
| Spotify | Tracks, albums, artists, playlists, shows and episodes | Link plus player loaded on click |
| Apple Music | Songs, albums and playlists, including an album's selected track | Link plus player loaded on click |
| Wikipedia | Multilingual page titles, mobile links, sections and permanent revision citations | Source link cards with title and language |
| Mathematics (LaTeX / KaTeX) | Inline and display equations, fractions, matrices and aligned systems | Local accessible MathML, with readable source fallback |

Paste a supported HTTPS URL, or a standalone Markdown link, on its own line
in a message. Composer preview uses the same modules. At most five distinct
cards appear per post; fenced code, quotes, lists and inline links remain
ordinary source. Deleted posts have no cards. Provider content is never
stored as trusted post HTML.

Standalone URL extraction uses an application-owned cache, capped at 512
source prefixes and 1,048,576 characters of prefixes and candidates combined
(excluding Perl overhead). Only the first 50,000 characters are scanned;
source changes select a new entry. Entries remain in worker memory until
eviction or restart and are never fetched by post id or shared externally.
Callers must authorize posts first. Providers, current display modes and
response validation run again on every call; resolved cards are not cached.

Local link and equation modules need no credential. Cards use URL-derived
information; they do not promise that a remote resource exists or is public.
Wikipedia normalizes mobile and query-form reading links, decodes Unicode
titles and preserves section anchors and `oldid` citations. Revision labels
use the revision id rather than assuming a supplied title belongs to it.
The reviewed language-domain list comes from Wikimedia SiteMatrix; no
wildcard host or runtime language discovery is used. Wikipedia namespaces
are preserved, so a card is not a claim that a page is an encyclopedia article.
No article extracts, images or imported text are fetched in API v1.
Facebook and Instagram content is not fetched or embedded. Network operations use separate core-controlled services; see
[announcements, imports and external login](integration-network-v1.md). Live
provider metadata and incoming webhooks remain separate future capabilities. Playback depends on provider availability, account,
region, subscription and embedding permissions; Apple Music may offer previews
rather than full playback to listeners who are not signed in.

## Equations

Enable **LaTeX / KaTeX** in **Admin → Plugins**. Use `$x_i^2$` or `\(x_i^2\)`
inside a sentence, and `$$\frac{a}{b}$$` or `\[\frac{a}{b}\]` for a display
equation. Matrices and aligned systems use KaTeX's supported LaTeX syntax
inside these delimiters. The composer adds inline and display equation
buttons and uses the same live preview. The administrator page also includes
an equation tester. Invalid or unsupported equations retain readable source.

KaTeX **0.19.1** is pinned and served locally, with native MathML output for
accessibility. No CDN, account, remote fonts or network service is needed.
Without JavaScript, escaped LaTeX remains readable. Code spans and fenced code
are excluded. Formulas cannot cross paragraph or code boundaries. At most
50 formulas appear per body; each source is at most 4,096 characters.
Single-dollar inline delimiters cannot enclose leading/trailing whitespace.

Core validates the plugin's source spans and escapes their content; it never
accepts plugin HTML. Rendering disables trusted HTML/resource commands,
isolates macros per equation, limits expansion to 1,000 and sizes to 20 em.
Disabling the module removes equation rendering and its local scripts on
subsequent requests while preserving original posts.

## Manage from the administrator GUI

Open **Menu → Admin → Plugins** (`/admin/plugins`). The same menu links
**Integrations** and **Forum settings**, including the
optional external-login configuration. Each module has its own card with:

- an enabled switch and explicit Save action;
- a player-on-click or link-only choice when the module declares a player;
- installed version, fixed API version, capabilities and recognized domains
  under expandable technical details;
- a shared link tester that resolves locally without publishing or making
  external requests.

Choices persist in PostgreSQL and apply to subsequent requests across web
processes without a restart. Link-only mode removes the player and its CSP
origin. Disabling preserves all posts. The host includes the configuration
revision and active module versions in public page cache variants. Existing
browser/intermediary HTTP cache lifetimes still apply. An unavailable
configuration read disables cards rather than re-enabling a disabled provider.

The installation default is all eleven static modules. Mastodon and PeerTube
are also visible in the GUI before setup, with a link to authorize exact
instance hostnames. Saving those lists applies on the next request without
restarting web processes. Enable the modules in the plugin GUI when first
configured. Removing an instance immediately removes its cards, players and
CSP origin on subsequent requests; an empty list keeps the module inactive even
when an earlier enabled choice remains saved. `GPFORUM_INTEGRATION_PLUGINS`
sets an initial default such as `youtube,github` or `none`; it is not required
for routine GUI management, and saved module choices take precedence.

## General forum settings

**Admin → Forum settings** (`/admin/configuration`) manages branding,
language, appearance, time zone, public address, media size/source policy,
WebSub, legal/operator/privacy contacts and outgoing mail configuration.
Related settings validate and save together. The page groups fields, offers
search and protects unsaved edits. Invalid values are marked; nonsecret input
is preserved when validation or a concurrent edit prevents saving. Each saved
field can be restored to its installation default.

Changes carry a revision precondition and an idempotent command id. A stale
administrator form cannot overwrite a newer configuration. Core verifies
current global administration permission, MFA policy, participation, CSRF and
rate limits; the write and its audit record commit in one transaction.

Live presentation settings apply on the next page. Startup settings are
explicitly labelled and take effect when services restart; startup reads the
saved overrides. SMTP credentials are sealed, never redisplayed, and preserved
when their inputs are blank. Their maximum is 128 UTF-8 bytes. Keep prior
installation signing keys until stored credentials have been resealed during
key rotation.

Database bootstrap credentials, process/service layout, TLS, root signing
keys and host filesystem access remain deployment-owned. The existing
**Server configuration and diagnostics** page exposes that operational
configuration separately from ordinary forum preferences.

## Develop or update a module

Each service has a separate file under `lib/GPForum/Service/Integration/`.
Only the fixed capability methods cross the plugin boundary: `manifest_v1`,
`resolve_link_v1` for links, and `prepare_math_v1` for local equation spans. The host
checks closed input/output records, declared capabilities and exact origins.
There are no arbitrary HTML, script, callback, database or controller fields.
See the [fixed API specification](plugin-api-v1.md) and
[JSON Schema](../etc/plugins/api-v1.schema.json).

Update the affected module, increment its release version, run contract and
web tests, deploy and restart. The API version remains unchanged for URL
recognition fixes. Breaking contract changes require an explicit new API
version. The GUI shows installed versions; this release does not download
unreviewed code or provide a remote plugin marketplace. Modules are trusted
Perl dependencies, not sandboxed code. Providers must perform bounded local
parsing only; core retains authorization, presentation, configuration and audit.

## Network operations and remaining demand

**Admin → Integrations** manages selected-topic
Discord announcements and moderated RSS/Atom candidates. These requests run
through the outbox. Configure the destination or exact source URLs in general
forum settings and restart web and worker processes. Telegram is excluded.

**Account security → External login** lets an existing member explicitly link
an operator-configured OIDC identity. Local passwords and MFA remain in force;
email claims never merge or create accounts. The operator configures pinned
issuer/endpoints and client credentials; no public identity provider is enabled
by default. See the [network capability contract and operations guide](integration-network-v1.md)
for provisioning, recovery and compatibility details.

Reddit, X, TikTok and LinkedIn remain on demand. Their APIs, credentials,
provider approvals and permitted uses must be checked when a concrete community
need is selected. They are not silently activated by installing this release.

## Official references

Checked 2026-11-02; recheck remote requirements before implementing additional
network features:

- [YouTube embedding and privacy-enhanced mode](https://support.google.com/youtube/answer/171780?hl=en-GB)
  and [player parameters](https://developers.google.com/youtube/player_parameters).
- [GitHub API versions](https://docs.github.com/en/rest/about-the-rest-api/api-versions)
  and [webhook validation](https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries).
- [Spotify embeds](https://developer.spotify.com/documentation/embeds/tutorials/creating-an-embed)
  and [Apple Music embeddable players](https://artists.apple.com/support/1117-apple-music-marketing-tools).
- [MediaWiki reading and revision URLs](https://www.mediawiki.org/wiki/Help:URL)
  and [Wikimedia SiteMatrix](https://meta.wikimedia.org/w/api.php?action=sitematrix&format=json&smtype=language).
- [KaTeX options](https://katex.org/docs/options) and
  [untrusted-input security](https://katex.org/docs/security).
- [Vimeo oEmbed](https://developer.vimeo.com/api/oembed/videos),
  [Mastodon oEmbed](https://docs.joinmastodon.org/methods/oembed/),
  [Discord webhooks](https://docs.discord.com/developers/resources/webhook),
  [OpenID Connect Core](https://openid.net/specs/openid-connect-core-1_0.html).
- [Meta embedded posts](https://developers.facebook.com/docs/plugins/embedded-posts/)
  and [Instagram oEmbed](https://developers.facebook.com/docs/instagram-platform/oembed).
  Meta's official pages could not be retrieved during verification. The
  shipped link-only modules assume no Graph API token, approval or version
  requirement. Verify those before implementing remote Meta content.
