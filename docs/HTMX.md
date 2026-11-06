# htmx in GPForum

## Version and distribution

GPForum vendors the unmodified minified distribution of
[htmx 4.0.1](https://github.com/bigskysoftware/htmx/releases/tag/v4.0.1), released
on 1 November 2026. The upstream Git blob and byte count were checked before
installing the asset. `assets/js/htmx.LICENSE` records the pinned source and SHA-256.
Existing content fingerprints give the new bytes a new asset URL.

The minified file is 37,448 bytes, compared with 51,238 for the previous 2.0.10:
26.91% fewer uncompressed bytes. This measures the library's size, not server
throughput or request latency.

## Integration

The existing 18 fragment form declarations use `hx-boost="true"` with their
native `action` and `method`. Each route is emitted once instead of twice, and
the selected submit button's `formaction` chooses the correct reaction route.
The controllers continue to render the authorized HTML fragment.

`hx-target:inherited` and `hx-swap:inherited` explicitly share the toolbar and
post targets. Implicit inheritance stays disabled. Local mutations explicitly
set `hx-push-url="false"`: htmx 4 otherwise pushes even a boosted form's action
into history. Refreshing must continue to open the discussion.

`hx-sync:inherited="closest form:drop"` shares one request queue between a form
and its htmx submit buttons. Duplicate submissions are discarded while a request
is pending. `hx-disable` temporarily disables submit controls; existing disabled
controls are excluded. Draft buttons and pagination also declare synchronization.
Server-side command identities, authorization and CSRF checks remain authoritative.

The enhancement loader, embedded players and post reading tools use
`htmx:after:process` to initialize each inserted subtree, including out-of-band
content. They do not rescan the full post list for every update. Clients which
need the completed set of swaps, including page navigation, use one
`htmx:after:swap` listener rather than separate legacy main/OOB listeners.

The config uses `includeIndicatorCSS: false`. The removed `allowEval` and
`responseHandling` options are no longer emitted. GPForum uses no inline htmx
handlers or JavaScript expressions; the existing `script-src 'self'` CSP blocks
dynamic evaluation. htmx 4 swaps validation/error responses by default and
excludes 204/304; server `HX-Reswap: none` responses retain their existing meaning.

## Static usage, 6 November 2026

Run the audit against the current source:

```sh
script/gpforum-carton exec perl script/htmx-usage
```

| Measure | Count |
| --- | ---: |
| Literal form declarations | 154 |
| Form declarations with an htmx action or boost | 18 |
| Form coverage | **11.69%** |
| Request elements, including draft buttons and post pagination | 21 |
| Templates declaring request elements | 8 |
| Templates with literal htmx attributes | 10 |
| Templates with forms or request elements | 68 |
| All EP templates | 134 |

The percentage is `18 / 154 × 100`. Conditional branches and loop bodies count
once each; shared partials count at their definition, not at every include.
The audit removes EP instructions and HTML comments before parsing the HTML.
It does not execute dynamically emitted attributes or expand inherited boost.

This is declared form coverage. It does not measure traffic or a percentage of
htmx's available features. The optional composer client can intercept an enhanced
form and use JSON fetch; shared draft buttons can also enhance part of an
otherwise native form. Loading htmx in the default layout does not mean that every
interaction on that page uses it.

## Verification

The ordinary JavaScript suite runs with `node --test t/js/*.test.cjs`.
[Browser checks](../t/browser/README.md) run the real application and vendored
library in Chromium under GPForum's CSP. They cover inherited targets, history,
pagination, OOB notices, all four reaction actions and command identities,
duplicate submission, HTTP 422 responses, transport failure, rejected replies
which retain unsent text, and forms with JavaScript disabled.

Relevant Perl integration tests are `t/48-browser-security.t`,
`t/233-asset-fingerprints.t`, `t/480-thread-fragments.t`,
`t/650-forum-drafts-web.t`, `t/689-post-fragment-cache.t`,
`t/771-reaction-forms.t` and `t/776-degraded-thread-controls.t`.
