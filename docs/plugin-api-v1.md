# Good Phorum Plugin API v1

This is the fixed boundary for code outside the forum core. All packaged local
integrations implement the same API in independent modules. Providers receive
no controller, database, post, user, token, configuration service or mutable
core object. API v1 permits bounded local URL parsing and LaTeX span detection.

The [JSON Schema](../etc/plugins/api-v1.schema.json) describes the wire shapes.
`Service::Plugin::Contract` enforces them at runtime, including the cross-record
origin and capability checks below. Plain strings, integers, arrays and records
are allowed; blessed objects, callbacks, scalar references and unknown fields
are rejected. The API version is an integer, not a numeric string.

## Required methods

Every provider implements `manifest_v1` and the method for its capability:

```perl
sub manifest_v1 ($self) { ... }
sub resolve_link_v1 ($self, $request) { ... }
sub prepare_math_v1 ($self, $request) { ... } # local math modules instead of link resolution
```

Module-private helpers may use third-party libraries, but consumers call only
the registry. Neither Good Phorum internal class names nor library URL objects are
part of the public plugin input/output contract.

### Manifest

```json
{
  "api_version": 1,
  "id": "spotify",
  "name": "Spotify",
  "version": "0.001",
  "capabilities": ["link.resolve.v1", "media.embed.v1"],
  "url_hosts": ["open.spotify.com"],
  "frame_hosts": ["open.spotify.com"]
}
```

All fields are required; additional fields are forbidden. Provider ids are
lowercase ASCII identifiers up to 32 characters. Module versions have two or
three numeric components; API compatibility depends on `api_version`, not
the provider's release number. Names are nonempty strings up to 256 characters.
Capability lists have at most 16 unique items; each host list has at most
1,024 unique items, accommodating reviewed multilingual Wikipedia origins.
Hosts are exact lowercase ASCII names:
wildcards, ports, paths and schemes are forbidden.

Link modules require `link.resolve.v1`; `media.embed.v1` is optional and must
correspond to a nonempty `frame_hosts`. A math module instead declares only
`math.render.v1` and both host lists must be empty. These are the complete
initial API v1 capabilities. Duplicate ids,
unknown capabilities, missing methods and incompatible versions are rejected
before activation. Manifests are validated, copied and pinned by the host.

### Link request

```json
{"api_version": 1, "url": "https://open.spotify.com/track/0Lr4kGOYn9l83EjuK6cZFQ"}
```

Both fields are required; additional fields are forbidden. The host validates
the URL, copies and locks the request, and invokes only providers declaring
that exact host. A provider cannot mutate the request or inspect unrelated
links. URLs are limited to 2,048 characters, HTTPS, no credentials, no control
characters, quotes, angle brackets or backslashes, and port 443 or no explicit
port. The provider parses the URL string itself.

### Link response

Return `undef`/JSON `null` for no match, or:

```json
{
  "api_version": 1,
  "provider": "spotify",
  "kind": "audio",
  "label": "Spotify track 0Lr4kGOYn9l83EjuK6cZFQ",
  "url": "https://open.spotify.com/track/0Lr4kGOYn9l83EjuK6cZFQ",
  "embed": {
    "kind": "audio",
    "url": "https://open.spotify.com/embed/track/0Lr4kGOYn9l83EjuK6cZFQ"
  }
}
```

Only `embed` is optional. Its two fields are both required if it is present.
The provider id must match the pinned manifest. The outer kind must be one
of `video`, `audio`, `post`, `article`, `repository`, `issue`, `pull_request`, `commit`,
`release`; an embed kind must be `audio` or `video` and match the outer kind.
The label is a nonempty string up to 256 characters. Link URLs must use a
declared `url_hosts` origin; embed URLs must use a declared `frame_hosts`
origin and require `media.embed.v1`. The host validates and copies the response.

HTML, JavaScript, CSS, template names, event handlers, redirects, database
statements and arbitrary extension fields are not part of this API. Core adds
display names and validated origin metadata, escapes all template fields,
applies the administrator's link-only policy and builds CSP from the active
manifests. Its generic browser renderer loads a player only after a click.
No browser provider-specific API is needed when another conforming player is
added. A provider response never becomes raw trusted post HTML.

### Mathematics request and response

`prepare_math_v1` accepts the closed record
`{"api_version":1,"source":"Energy $E=mc^2$"}`. Source is a string of at most
50,000 characters, with no control characters other than tab, CR and LF.
Core removes fenced/code contexts before invoking the capability, copies and
locks the request, and receives only:

```json
{
  "api_version": 1,
  "provider": "mathematics",
  "spans": [{"start": 7, "length": 8, "source": "E=mc^2", "display": "inline"}]
}
```

All fields are required and additional fields are forbidden. Offsets and
lengths are integer Unicode character counts, with no string coercion. Spans
must be ordered, nonoverlapping and within the exact input. At most 50 spans
are allowed, each with a nonempty source up to 4,096 characters. `display`
is exactly `inline` or `block`. Core verifies that the selected input equals
the returned source surrounded by `$…$` / `\(…\)` for inline, or `$$…$$` /
`\[…\]` for display. Providers return no HTML, assets, renderer options,
macros or callbacks. No remote origins are permitted.

Core escapes LaTeX into fixed containers and owns the pinned local KaTeX
renderer, MathML output, trust policy, expansion/size limits and fallback.
At most 50 formulas render across all prose contexts in one body. Plugin
exceptions or invalid spans leave the original body readable. This initial
v1 contract is finalized before release; later operations or shape changes
must use a new explicit API version.

## Failure, lifecycle and authority

Provider exceptions and invalid responses produce no card, leave the original
post intact and log only the provider id. Post authorization, moderation,
rendering, configuration, audit, storage and browser consent belong to core.
The host scans at most 50,000 source characters and emits five distinct cards.
Providers must not perform I/O, so no external timeout or retry belongs to the
synchronous v1 operation. In-process Perl remains privileged code: this API
is a checked interface and review boundary, not a process sandbox.

The administrator GUI manages enable/disable and link/player mode. Core stores
those choices, revisions and audit records; no plugin owns authoritative state.
Disabling requires no post rewrite, migration or data rollback. Module releases
are reviewed deployments; the application does not download arbitrary code or
silently update provider interfaces. The installed version is visible in the GUI.

API v1 is frozen: changing fields, accepting new capabilities or changing
semantics requires an explicit v2 operation and host support, with v1 tests
retained. Provider URL fixes can ship as new module versions without changing
the core contract. Network metadata, notifications, webhooks, login, importing
and publishing need separately specified versioned capabilities, scoped
credentials and core-controlled workers. They cannot be smuggled into v1.

Network announcement, syndication and login operations have their own
[versioned core contract](integration-network-v1.md). They add no methods or
privileges to this frozen local provider API.
