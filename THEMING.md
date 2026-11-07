# Good Phorum Theming

Use semantic tokens to keep light, dark and high-contrast pages consistent.
`GPForum::Theme::Registry` declares supported themes; `assets/css/gpforum-ssr.css`
and `themes/*/tokens.css` provide their values.

See the [design system](docs/ui/design-system.md) for layout and typography,
the [brand guide](docs/BRANDING.md) for naming and
[artwork sources](assets/source/README.md) for the mark.

## Themes

| Value | Behavior |
| --- | --- |
| `auto` | Follow the device's light or dark preference |
| `default` | Always light; shown as “Light” |
| `dark` | Always dark |
| `high_contrast` | High-contrast palette |

`GPFORUM_DEFAULT_THEME` sets the SSR default (`auto` unless configured).
The stylesheet's automatic dark palette matches the explicit dark theme;
`t/188-theme-contrast.t` checks parity. The page declares both color schemes
and a matching `theme-color` for each device preference.

The CSRF-protected POST `/theme` selector and `/settings` use the same preference.
Guests keep a validated `gpforum_theme` cookie; signed-in members also store
`users.preferred_theme`. New members start with `auto`; existing `default`
preferences stay light. Invalid values fall back to the configured default
before entering HTML attributes.

## Token Files

```text
themes/default/tokens.css
themes/dark/tokens.css
themes/high_contrast/tokens.css
```

Tokens cover text, surfaces, actions, borders, focus and semantic states.
Keep their values synchronized with the registry and reference files.

The stylesheet adds three colours the registry does not hold, each set per
theme: `--color-subtle` for metadata, `--color-hairline` for the rules between
rows, and `--color-mark` for search highlights.

## Type and layout

Use [the design system](docs/ui/design-system.md) for the full visual contract.
The stylesheet defines the implementation; keep these choices consistent:

- **Type:** locally served Inter for controls and metadata; Source Serif 4 for
  Latin headings and long-form prose. Native monospace for code.
- **Scale:** semantic size and weight tokens. Reading text is 19px with a 1.72
  line height and a 65ch measure; display titles scale with the viewport.
- **Color:** semantic tokens for every theme. Use `--color-subtle` for metadata
  and preserve tested contrast on each surface.
- **Layout:** logical `inline`/`block` properties, shared spacing and width
  tokens. Consoles can request the wide shell; prose keeps a readable measure.
- **Navigation:** native links, `aria-current` for the active destination and
  visible focus. Reading and reply controls stay prominent.
- **Lists:** shared rounded surfaces with inset separators. A row with one
  destination provides one clear link target.
- **Choices:** language and theme controls expose the selected value with
  `aria-pressed`.
- **Sheets:** `components/sheet` uses native popovers with Escape and outside-click
  dismissal. Without popover support, its form stays available in the page.
- **Code:** preserve characters and spacing; let fenced blocks scroll horizontally.

Font files, provenance and licenses are recorded in
[Inter](assets/css/inter-LICENSE.txt) and
[Source Serif 4](assets/css/source-serif-4.README.md).

## Accessibility

Theme changes must preserve WCAG 2.2 AA contrast across every supported theme.
Prefer AAA for normal body text and long-form reading surfaces. The registry,
main stylesheet, and `themes/*/tokens.css` files are tested for token parity.

Run:

```sh
carton exec prove -lr t/65-accessible-theme.t t/67-ui-system.t \
    t/188-theme-contrast.t t/320-thread-page-reading-first.t
```

before merging visual changes.
