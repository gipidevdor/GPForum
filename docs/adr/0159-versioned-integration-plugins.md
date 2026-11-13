# ADR 0159: Versioned Integration Plugins

## Status

Accepted (2026-11-01), under the owner's request for YouTube, GitHub, Facebook, Instagram, Spotify, Apple Music and Wikipedia plugins. Replaces the withdrawn ADR 0083's unwired hook design.

## Date

2026-11-01

## Context

External services change their URLs, APIs, permissions and embedding rules
more often than forum posting rules. Each needs a replaceable adapter and
a way to disable it without altering posts. The old plugin system was
removed because nothing called it.

## Decision

Ship reviewed provider modules behind `Service::Integration::Registry`.
The frozen [Plugin API v1](../plugin-api-v1.md) requires closed manifests,
plain immutable requests, checked response records and declared capabilities.
Manifests declare stable ids, module versions, API versions and exact allowed
origins. Link capability accepts a validated HTTPS URL and returns plain
presentation data or undef; mathematics accepts prose and returns bounded,
validated source spans. Neither returns HTML. The contract grants no database, account, template,
network, filesystem or event capabilities. These are trusted Perl modules,
not sandboxed or downloadable code. Updates are reviewed deployments.

`GPFORUM_INTEGRATION_PLUGINS` selects packaged providers at startup.
Unknown ids and incompatible contracts fail startup; `none` disables all.
Providers require no external credentials. The GUI uses the configuration
migration specified by ADR 0160. Installation defaults are overridden by durable administrator GUI choices
under ADR 0160. GUI enable/disable and display mode changes apply on the next
request; code deployments require restart. Public page cache keys include the
configuration revision, active provider ids, versions and display modes. Existing browser/intermediary cache lifetimes still apply.

The authorized post presenter and canonical composer preview call this
extension point on source, never persisted HTML. Processing is bounded to
50,000 source characters and five distinct standalone links. Fenced code,
quotes, lists and inline links do not create cards. Deleted posts have no
cards. Authorization and visibility remain core-owned. Provider exceptions
are logged by id without source or exception details, leaving posts readable.
Providers do bounded local parsing only: no I/O timeout or retry belongs
to this synchronous contract. In-process plugin code is privileged and
must be reviewed for compliance; the registry is not a sandbox.

Initial providers:

- YouTube: a video link and privacy-enhanced iframe created in the browser
  only after reader activation. The original link is always present.
- GitHub: repository, issue, pull request, commit and release link cards,
  without claims about visibility, titles or current repository state.
- Facebook: supported post, permalink, reel and video link cards, without
  fetching content or implying that the remote post is public.
- Instagram: canonical post, reel and TV link cards, without loading Meta content.
- Spotify: track, album, artist, playlist, episode and show players on click.
- Apple Music: album, song and playlist players on click, preserving selected tracks.
- Wikipedia: multilingual source cards, readable titles, sections and permanent revision citations, without fetching remote article content.
- Mathematics: a separate math.render.v1 source-span capability, local pinned KaTeX with accessible MathML, no remote origins or plugin HTML, and GUI equation testing. Core owns escaping and rendering limits.

Templates escape all fields. No remote HTML or JavaScript SDK is accepted.
CSP adds only exact frame origins declared by active modules with player
mode enabled: YouTube privacy-enhanced, Spotify and Apple Music. Script and connection origins stay local.
The frame's referrer policy transmits the site origin, not the thread path.
No remote thumbnails or videos load just because a page is viewed.

Future metadata, incoming webhooks, notifications, account linking and
publication need separate versioned contracts. Side effects use durable
outbox workers, scoped revocable credentials and core-owned authorization.
HTTP calls need destination allowlists, bounded responses, timeouts, rate
limits and retry policy. Webhooks need signature checks and deduplication.
New state requires versioned PostgreSQL functions and migrations. Generic
arbitrary callbacks must not bypass these boundaries.

## Consequences

Providers evolve separately in source while posting rules stay stable.
Disabling loses no data and needs no migration or post rewrite. Core works
with every plugin disabled. Initial functionality needs no tokens but has
no live metadata, social login, synchronization or cross-posting. API
outages cannot slow this local parsing extension.

## Related Decisions and Implementation

- ADRs 0083, 0060, 0085, 0093, 0094, 0096 and 0126.
- `lib/GPForum/Service/Integration/Registry.pm` and adjacent provider modules;
  `lib/GPForum/ViewModel/Forum/Rows.pm`,
  `lib/GPForum/Controller/Forum/Drafts.pm`,
  `templates/forum/_integrations.html.ep`, `assets/js/integrations.js`.
- `t/762-integration-plugins.t`, `t/763-integration-plugins-web.t`,
  `t/js/integrations.test.cjs`, `docs/integrations.md`.
