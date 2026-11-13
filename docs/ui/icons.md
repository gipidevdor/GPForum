# GPForum Segni

The approved website family: **28 interface icons and 8 emoticons**.
The source is [`gpforum-icons.svg`](../../assets/img/gpforum-icons.svg); the
runtime allowlist is [`IconSet.pm`](../../lib/GPForum/Web/IconSet.pm).

Use this family exclusively for authored interface symbols. Do not add icon
fonts, system emoji, third-party pictograms, data-URL SVG or CSS drawings as
substitutes. Browser-native controls, member-uploaded images, QR codes and
members' own message contents are not interface icons.

## Visual language

- 24 × 24 viewbox, 1.75-unit rounded strokes and rounded joins.
- Open arcs and an optional amber node echo the GPForum mark.
- Geometry stays fixed across devices. Colour follows the host theme.
- `--color-icon-accent`: `#9b6d32` in light, `#c69955` in dark, black in
  high contrast. Filled action buttons use their label colour for the node.
- 18px for interface labels; 24px for reactions. The hit target is separate
  from the drawing: reaction buttons are at least 44 × 44px.
- No animation. Meaning never depends on the amber node alone.

## Use

Beside visible text, the SVG is decorative:

```html+ep
<a class="button" href="#reply-body"><%= ui_icon('reply') %><%= t('forum.reply') %></a>
```

A standalone informative image needs a translated label:

```html+ep
<%= ui_icon('warning', t('ui.warning')) %>
```

An icon-only **control** still needs its own accessible name. Do not label
both the decorative image and its parent button. The helper emits
`aria-hidden="true"` and `focusable="false"` by default; an explicit image
label produces `role="img"` with escaped `aria-label`.

Each `use` references the same local, fingerprinted sprite. Unknown symbol
names fail closed. Dynamic reading controls clone approved SVGs from inert
templates in the SSR layout; if unavailable they fall back to text.
Breadcrumbs, disclosure indicators and sheet dismiss controls also use the
family. `/icon.svg` renders the approved orbit from the same source, with
the installation's own name as its accessible title.

## Catalogue

The family is used directly in page templates as well as the shared shell:
search, composing and draft controls, messages, account and security forms,
privacy actions, moderation and administration. Header actions explicitly
pass `icon` to the shared page-header component. Feedback components use
the matching warning/check symbol, pagination uses the approved arrows,
and empty states receive a context-specific `empty_icon`. All retain their
visible translated text; icons are decorative rather than replacement labels.

**Interface:** `orbit`, `discussion`, `reply`, `quote`, `search`, `categories`,
`tag`, `bookmark`, `bell`, `message`, `compose`, `feed`, `settings`, `user`,
`attachment`, `image`, `link`, `copy`, `check`, `close`, `more`, `arrow-left`,
`arrow-right`, `shield`, `download`, `upload`, `warning`, `poll`.

**Emoticons:** `emote-heart`, `emote-laugh`, `emote-celebrate`, `emote-think`,
`emote-smile`, `emote-wink`, `emote-surprise`, `emote-thanks`.

The first four replace existing post reactions without changing their
meaning, storage or routes. The other four are available to interface
components; this does not introduce additional stored reaction types or
rewrite emoji typed by members.

## Accessibility checks

- Meaningful strokes and the accent node are checked against theme
  backgrounds at 3:1 or better (WCAG 2.2 SC 1.4.11).
- Existing text labels, focus styles and keyboard behaviour remain.
- Reactions expose a localised action, count and `aria-pressed`; selected
  reactions also have a visible check, so colour is not the only cue.
- Forced-colour mode uses `currentColor` for both the node and the stroke.
- `t/764-icon-set.t` checks the catalogue, safe references, labels,
  decorative semantics, reaction state and browser-icon geometry.
  `t/188-theme-contrast.t` checks colours mathematically. These checks cover
  the integration; they are not a certification of the entire website.

References: [non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html),
[target size](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html),
[name, role and value](https://www.w3.org/WAI/WCAG22/Understanding/name-role-value.html).

## Browser exports

`favicon.ico` contains 16, 32 and 48px bitmap frames. The 180px Apple touch icon
and 192/512px PNG installation icons are exports of the same approved orbit as
`/icon.svg`. Regenerate these exports when that source changes. They are served
as application assets; no browser icon falls back to framework artwork.
