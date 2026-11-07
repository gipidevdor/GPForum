# Good Phorum SSR UI accessibility notes

Use semantic components, visible focus and clear validation feedback. Color
must support a message, never carry it alone.

The [theme registry](../lib/GPForum/Theme/Registry.pm),
[stylesheet](../assets/css/gpforum-ssr.css) and
[design system](ui/design-system.md) define current colors. Check those sources
when changing a token; copied palette values and ratios become stale.

| Check | Required evidence |
| --- | --- |
| Text and action contrast | `t/65-accessible-theme.t` checks AA/AAA targets for defined color pairs |
| Theme and surface contrast | `t/188-theme-contrast.t` checks supported themes and token parity |
| Semantic shell and components | `t/67-ui-system.t` checks shared structure and landmarks |

These checks cover specific contracts. A complete accessibility review also
needs keyboard, screen-reader and workflow checks from the
[accessibility guide](ui/accessibility.md).

The shared stylesheet includes visible `:focus-visible` states, skip links,
reduced-motion handling, semantic breadcrumb/flash styling, form styles, and
validated `auto`, `default`, `dark` and `high_contrast` theme contracts. The SSR shell
uses the configured default theme unless a supported `gpforum_theme` cookie or
authenticated `preferred_theme` session is present.

Form validation errors are exposed through a summary with `role="alert"` and
field-level messages connected by `aria-describedby`. Invalid controls set
`aria-invalid="true"` and receive a border-width/focusable visual treatment in
addition to color, so the state does not depend on color perception alone.

The `/settings` form uses labeled selects, labeled notification checkboxes,
and text descriptions for each channel. Notification state is never communicated
by color alone.

## SSR component contracts

Reusable UI primitives live under `templates/components/` and are documented in
`docs/UI_SYSTEM.md`. New SSR surfaces should prefer these partials before adding
route-local markup:

- `page_header` for the page heading and top-level actions;
- `site_header`, `primary_nav`, `identity_nav`, `locale_selector`,
  `theme_selector`,
  `breadcrumbs`, `flash_messages`, and `site_footer` for the shared shell;
- `pagination` for labeled paging navigation;
- `empty_state` for no-results and not-yet-created states;
- `badge` for status, moderation, job, and audit indicators;
- `alert` for warning/error/success status surfaces.
- `status_banner` for section-level degraded or blocked states;
- `error_summary` and `field_error` for validation feedback;
- `moderation_indicator` for review/audit state labels;
- `admin_table` for operational data that needs column headers;
- `notification_surface` for inbox items and mark-read controls.

Every page should rely on the base layout for the document `<main>` landmark.
Nested `<main>` elements are invalid and are blocked by `t/67-ui-system.t`.

## Theme extension guidance

Add new visual decisions as semantic CSS custom properties first. Prefer
logical properties such as `padding-inline-start` and `inset-inline-start` so
future RTL locales can reuse the layout. Avoid inline `style` attributes in
templates; component and token changes belong in `GPForum::Theme::Registry`,
`assets/css/gpforum-ssr.css`, and `themes/*/tokens.css`.

Print output uses the same content hierarchy but removes navigation, forms,
pagination, and transient messages so long-form discussion pages remain readable
on paper or PDF exports.
