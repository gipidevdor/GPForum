# SSR Design System

Use Mojolicious partials and `assets/css/gpforum-ssr.css` for consistent
server-rendered pages. No frontend build step is required.

Keep content prominent: grouped backgrounds, restrained surfaces, subtle borders
and one action tint. The amber line above page titles carries the Segni identity.
Use **Good Phorum** or **GP Forum** for the project; an installation's community
name is separate. See the [brand guide](../BRANDING.md).

The light palette:

- grouped background: `#f2f2f7`; surfaces `#ffffff` and `#f5f5f7`;
- label: `#1d1d1f`; secondary label (`--color-subtle`): `#6e6e73`;
- tint for links and tinted text: `#00509e`, deepened from the system blue
  so that links and filled-control labels reach 7:1 (`t/65`);
- system blue for filled buttons (`--color-action`) and focus: `#0071e3`;
- semantic danger/success/warning tokens; the dark theme is the system's
  dark palette on black.

## Typography

**Inter** is the locally served UI face, with system fallbacks. It sets
navigation, controls, metadata, discussion-list titles and administrator
consoles. **Source Serif 4** sets Latin page titles and long-form prose;
its variable weight and optical-size axes distinguish a display title from
reading text without substituting a different family. Non-Latin script
classes retain their UI fallback. Genuine Roman and italic faces and Latin
subsets are served locally; there are no runtime requests to a font service.
See the [font provenance and license](../../assets/css/source-serif-4.README.md).

- Display titles use a fluid 38–56px scale and a medium weight; discussion
  titles use 32–44px, a bounded measure and balanced wrapping.
- Reading text is 19px with a 1.72 line height, a maximum 65ch measure,
  natural letter spacing and proportional old-style figures. Paragraphs
  have a one-em pause; a heading has more space before it than after it.
- UI text stays on the existing rem scale. Metadata uses 13–15px, normal
  case and neutral tracking; counts and table columns use tabular figures.
  Only the home page's short section labels use spaced capitals.
- Code preserves its monospace face and literal characters. Rich-text
  paragraphs inherit the reading size: list-description selectors target
  direct children and cannot shrink text inside a post.
- Titles, spacing and control sizes remain fluid or relative. Browser text
  scaling, keyboard focus, reduced motion and high-contrast themes remain
  available; the mobile reading column uses its full available measure.

## Layout and interaction

[Functionality coverage](functional-coverage.md) maps every forum area to its
GUI entry and describes the router/form coverage guard. Attachments are visible
on editable posts, and the inbox always offers a new-conversation entry.

The header always exposes **Menu** (`/menu`), including on compact tablets.
The primary navigation is limited to categories, search, notifications and
messages. Wide forum pages use the search field instead of a duplicate search
link. Settings and the native POST sign-out form live in an **Account**
disclosure. Escape and outside clicks close that disclosure when enhanced.
The skip link sits above the sticky header.

Menu keeps the complete role-aware catalogue in native disclosures, ordered
forum, account, moderation, administration and information. Groups show their
link count; an enhanced local search opens matching groups, filters links and
announces empty results. Without JavaScript the same links remain reachable
by opening a group. Media approval is labelled **Photos and uploads to review**.
No permission lookup is added to ordinary discussion pages. A new standalone
screen needs a menu entry or a documented contextual/authentication entry point;
the navigation coverage test enforces this. See
[ADR 0170](../adr/0170-focused-navigation-and-recoverable-forms.md).

Home puts recent discussions first in DOM and visual order. Categories form a
secondary sidebar on wide screens and a plain list after discussions on compact
screens. Discussion lists use inset separators aligned to row padding and a
full-row keyboard focus ring. Thread pages retain their centered 54rem maximum
width, with prose constrained further to the reading measure.

Browser enhancements load when their corresponding interface appears. The
shell declares fingerprinted local asset URLs; the loader accepts only its
own origin and initializes each module once, including after fragment swaps.
The math renderer waits for its local library and remains absent when the
plugin is disabled. Native forms, links and escaped source remain available
when an enhancement cannot load.

Reading navigation measures its own height and the header with
`ResizeObserver`. Post anchors clear both bars after a resize, translated
label or text-size change. This is progressive enhancement; ordinary post
links and server-rendered pagination remain available without JavaScript.

The reading bar has one message selector, previous/next controls with
accessible names, and a thin progress track. The selector includes the first
and last loaded message, so separate endpoint links are unnecessary. The
discussion's primary action is Reply; exploration stays in its own named
control in the header. Follow, bookmarks, polls, export and administrative
actions share the Options sheet. The three header controls wrap when needed
instead of hiding actions beyond a horizontal scroll area. Common options
come first; reports, editing and moderation expand only when requested.
The sheet header stays within reach while a long form scrolls.

Post footers keep likes, replies and full-post quotes visible. A single native
Reactions disclosure exposes the four choices, their counts and selected state;
its summary shows the total and whether the member has reacted. Attaching files,
editing, deleting, reporting and enhanced copy/selection tools live in a
native More actions disclosure. Opening it preserves a selected passage for
quoting; quote insertion still appends to the existing draft. The disclosure
and all server-rendered forms work without JavaScript.

The integrations console puts Discord and moderated feed workflows before a
collapsed, compact catalogue of every installed module and its prerequisites.
Thread organization keeps the action and selected count in a sticky toolbar.
Native POST browsing carries selections across pages, displays removable
selections from other pages, and preserves the form after invalid/conflicting
writes. Browsing does not call the transfer write function. Enhanced controls
show the destination for move/merge and a required title for split; server
validation remains authoritative. History is a separate disclosure.

Administrator pages use the same page-header primitive, keeping a short
action group beside its title when it fits. Plugin cards align their form
actions, separate the current status from technical details and retain real
checkbox semantics for switches. A switch's label supplies the full touch
target. General settings use one surface per group, with labels, fields and
hints sharing an alignment; the enclosing form adds no redundant frame.

Controls retain a 44px minimum height when any coarse pointer is available.
Disabled actions remain still. Reduced motion removes pressed transforms
and category snapping; reduced transparency and the high-contrast theme
replace translucent bars with solid surfaces. Forced-colour mode keeps
surface boundaries and selected controls visible. Motion timing is shared
through `--motion-duration`, `--motion-curve` and `--ease`.

An installation is never shown under the software's name or mark: the name
and the line under it are settings (`GPFORUM_SITE_NAME`,
`GPFORUM_SITE_DESCRIPTION`), every catalog message says `{site}` where it
named the forum, and the browser icon uses the approved orbit with the
installation's name as its accessible title (`/icon.svg`,
`GPForum::Web::SiteIcon`).

All authored website icons and reaction emoticons use the single approved
[Segni family](icons.md). Its open arcs and amber nodes echo the mark while
the interface retains the current surfaces, type and action tint.

`GPForum::Theme::Registry` is the runtime contract for theme names, color
schemes, label keys, theme-color metadata, and semantic color tokens. The SSR
shell applies `data-theme` and `data-color-scheme`; invalid theme values fall
back before rendering.

Core components live in `templates/components/`:

- shell: `site_header`, `primary_nav`, `identity_nav`, `locale_selector`,
  `theme_selector`, `breadcrumbs`, `flash_messages`, `site_footer`;
- content: `page_header`, `section_header`, `card`, `empty_state`;
- feedback: `alert`, `status_banner`, `confirmation`, `error_summary`,
  `field_error`;
- operational UI: `badge`, `status_badge`, `moderation_indicator`,
  `admin_table`, `notification_surface`;
- utility: `pagination`, `loading`, `dialog`.

The authenticated `/settings` surface combines locale, theme, and notification
channel preferences in ordinary SSR forms. It should remain the canonical place
for durable account preferences; shell selectors are quick controls for the same
locale/theme state.

Add new UI by extending semantic tokens and components first. Route-specific CSS
should be rare and justified by a surface that cannot be expressed as a shared
primitive. Theme token changes must update the registry, `gpforum-ssr.css`, and
the matching `themes/*/tokens.css` reference file together.
