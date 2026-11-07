# Accessibility Guidelines

Good Phorum targets WCAG 2.2 AA for the SSR shell.

Required contracts:

- exactly one document `<main>` comes from the base layout;
- every page has a skip link to `#content`;
- header, navigation, main, breadcrumbs, flash messages, and footer use semantic
  landmarks or labeled regions;
- form controls have visible labels;
- invalid forms use `components/error_summary` plus field-level
  `components/field_error` connected through `aria-describedby`;
- pagination is a labeled `<nav>`;
- status and moderation controls include text labels, not color-only cues;
- focus styles stay visible through `:focus-visible`;
- motion-sensitive behavior honors `prefers-reduced-motion`;
- print output removes transient shell controls and preserves readable content.

Automated checks:

- `t/65-accessible-theme.t` covers contrast tokens for every supported theme,
  theme selector rendering, fallback, focus, reduced motion, logical direction
  hooks, screen-reader utilities, and print mode;
- `t/67-ui-system.t` covers component presence, landmarks, localized SSR
  rendering, and representative admin/forum/notification pages.

ARIA should be used only where native HTML needs a name, status, or dialog
semantic. Prefer real labels, headings, lists, forms, and tables.

The focused navigation uses native `details`/`summary` controls. Menu groups
remain operable without JavaScript; enhanced filtering opens matching groups
and announces an empty result. Compact notification/message icons retain
accessible names. Account and reaction disclosures close with Escape and return
focus to their summary when enhanced. Transfer errors retain values, provide a
linked error summary and describe the associated field. Transfer pagination is
an explicit non-mutating form action with `formnovalidate`, so an unfinished
reason or destination cannot prevent browsing or erase selected messages.
