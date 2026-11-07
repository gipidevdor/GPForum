# Forum functions and their GUI entry points

The header's **Menu** is available on every page. Account and staff destinations
follow the signed-in member's permissions. Resource actions also appear where
the resource is being read; a member does not need to type an endpoint or an ID
to use an available action.

| Area | Entry point | Operations |
| --- | --- | --- |
| Discussions | Menu → Start a thread; category and discussion pages | Create, edit title/body/tags, choose visibility, move, delete and restore one's content; reply, quote, jump to a message and resume reading |
| Reading and discovery | Menu → Categories, Tags, Search, Feed, Following | Category/tag filters, scoped search, suggestions, follows, unread position, mark read and outgoing feed |
| Saved work | Menu → Drafts, Bookmarks, Your posts awaiting review | Save/preview/resume/delete drafts; bookmark and file into folders; inspect, withdraw or open reviewed posts |
| Media and podcast episodes | Menu → Photos, video, audio and podcasts; own post → More actions → Attach file | Create the discussion and continue to upload; choose a file and provenance, confirm rights, inspect review status/reason, retry, remove own uploads and open approved media |
| Reactions and polls | Post footer; discussion → Options → Poll | Like/unlike and reactions; create a poll, vote and close it when allowed |
| Messages | Menu → New message; inbox → New message; another member's profile | Choose a recipient, start/open a conversation, reply and report a message |
| Profile and relationships | Own profile → Edit profile; Menu → Your account | Public name, biography, profile picture; follow, ignore, block, unblock and report another member |
| Account and preferences | Menu → Your account | Language, theme, time zone, notification channels/types/digests, password/email changes, external identity linking, two-step sign-in and recovery controls |
| Passkeys | Menu → Passkeys; account/security settings; login form | Register a verified persistent key, sign in through normal sessions and TOTP, revoke keys/other devices, export metadata and erase credentials |
| Device notifications | Account settings → Notifications on this device | Enable device consent, verify receipt, choose notification kinds and revoke the device |
| Personal data | Menu → Your account → Your data | Request/download an export and request account deletion |
| Moderation | Menu → Moderation; discussion Options; report and action lists | Choose source/destination discussions by title and messages with checkboxes; review uploads/held posts, assign/release/resolve reports, audit-read reported messages, staff notes, hide/restore, pin/unpin, lock/unlock, suspend/revoke, reverse actions and organize/undo thread transfers |
| Administration | Menu → Admin | Users, roles, permissions and bindings; categories, announcements, admission policy, two-step policy/reset and address bans |
| Integrations | Menu → Admin → Integrations / Plugins | Configure available modules, test link/math rendering, selected Discord announcements and retries, approved feed imports and decisions, instance/source restrictions and optional external login settings |
| Operations and privacy review | Menu → Admin | Audit/status/jobs, dead-letter replay, search rebuild, cache purge, mail/antivirus diagnostics, settings/reset, export/deletion review, holds/releases and erasure jobs |
| Export and authenticity | Category/discussion export; post → More actions → Message signature | Download MBOX, inspect an available verified signature and download signature JSON/public keys |

Menu groups are native disclosures with an optional local search; the complete
catalogue remains available without JavaScript. The integrations page puts
network workflows first and lists every installed module in a separate
disclosure, with readiness and links to the exact missing configuration fields. Federated
instance changes saved in the GUI reach cards, players and CSP without a restart.
Account settings link directly to external identity linking.

The available integrations still require their actual administrator-approved
sources and provider configuration. Their GUI exposes configuration and status;
an unconfigured external provider is not presented as a working connection.

## Executed functional coverage

Run the complete gate from the repository root:

```sh
script/gpforum-carton exec script/test-features --output /tmp/gpforum-features --jobs 8
```

Choose a new output directory. PostgreSQL server tools must be on PATH. By
default, each integration test gets an isolated temporary PostgreSQL cluster;
caller database credentials are ignored and the cluster stops at process exit.
No persistent preview server or LAN listener is opened. CI uses
`--configured` explicitly against its disposable PostgreSQL service; never use
that option with a production database.

The command runs **the whole integration directory**, plus the unit witnesses
named by `etc/feature-coverage.json`. The manifest currently assigns every one
of the **235 registered HTTP operations** to exactly one of **41 feature
families** and declares **188 behavioral criteria**. For each operation it
requires an observed, explicitly accepted HTTP outcome. For each family it
also requires every declared successful assertion about the result, ownership,
privacy or durable state. Read the manifest for the exact assertion and test
file behind each criterion.

The report is `features.json`, with missing assertion/HTTP witnesses and stale,
duplicate or unmapped routes; `tests.log` holds TAP and failure diagnostics.
The command exits unsuccessfully if any test fails, any criterion is missing,
a route has no HTTP requirement or a newly registered operation is unmapped.
Skipped, failed and TODO assertions do not count. A response alone does not
establish that a command changed the database.

| Additional complete workflow | Executable evidence |
| --- | --- |
| Roles, permissions, bindings/revocation, announcements/retirement, category edits, configuration reset and search rebuild | `t/integration/postgres-gui-admin-features.t` |
| Follow/unfollow, profile/thread reports, bookmark folders, notification reads, thread moves, password/email updates, email verification, recovery and deletion review/erasure | `t/integration/postgres-gui-member-features.t` |
| Report assignment/release/resolution, action reversal audit, post transfer/undo, mail/antivirus diagnostics, dead-letter replay, public discovery, WebSub and a real WebSocket subscription | `t/integration/postgres-gui-staff-features.t` |
| Explicit OpenID linking/login/unlinking, selected Discord announcements, checked retry and authorized feed fetch | `t/integration/postgres-network-integrations.t` |
| Actual 100 MiB multipart upload, PostgreSQL size/chunks/checksum, unpublished byte access denial, approval, video range reads and prerecorded audio/player rendering | `t/integration/postgres-gui-large-media.t` |
| Every packaged link/math provider, independent disabling and link-only behavior; controlled Mastodon/PeerTube instance lists | `t/781-feature-providers.t` |
| Running-GUI instance policies, configure-to-worker-to-publication flows, native move/split/merge selection and reversal, cross-page selection and invalid-form recovery | `t/integration/postgres-feature-integration.t` |
| Persistent WebAuthn registration/login, TOTP, revocation/recovery, synced counters, exports and erasure | `t/integration/postgres-passkeys.t`, `t/js/forum-passkeys.test.cjs`; real browser registration/login/revocation in `t/browser/passkeys.test.cjs` |
| Device notification consent, encrypted delivery, visibility rechecks, revocation and session/account lifecycle | `t/integration/postgres-web-push.t`, `t/857-push-supervision.t` |
| Native form controls and strict coverage failure cases | `t/779-gui-form-controls.t`, `t/780-feature-coverage-gate.t` |

Native GUI tests read the forms actually rendered by the app: action, fields,
CSRF token, command ID and chosen submit button. Unchecked checkboxes and
unselected buttons are omitted. They verify saved results independently of
redirects. External network boundaries use controlled responses, including
signed OpenID claims; no real announcement or email is sent. These checks
establish the declared contracts, not live provider availability or browser
codec playback on every device.

`t/778-gui-functional-coverage.t` remains a **static wiring guard** for menu,
template and continuation references. It is not a functional execution test.
The existing domain suites continue to cover permissions, privacy, concurrent
commands, retries, moderation and failure paths beyond these GUI witnesses.
The CI integration job runs the feature gate and publishes its report.
See [ADR 0168](../adr/0168-executed-feature-coverage.md).

The browser wiring guard also requests every asset named by the templates.
`node --test t/js/*.test.cjs` verifies that each optional GUI client is supplied
by the actual layout and loaded when its controls appear, including swaps.
With Push enabled, service generation includes the sender on systemd, rc.d
and launchd; configuration restart advice and doctor follow the same setting.
