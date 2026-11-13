# ADR 0169: Runtime feature integration

## Status

Accepted (2026-11-03).

## Context

The owner requires product workflows to be integrated as well as tested. A
federated instance list saved in the GUI did not reach the application-owned
plugin catalogue until restart. The integrations console exposed only two
network workflows, account settings omitted the external-identity entrance,
and thread transfers required identifiers or URLs and manually typed numbers.
A configure-to-worker test also exposed a queued Discord announcement becoming
stuck as sending when its canonical public address failed the outbound policy.

## Decision

Make the existing integrations console the common entrance for all installed
modules, Discord announcements, moderated feeds and OpenID. Show missing local
prerequisites and link to their exact configuration fields. Federated modules
remain discoverable before any instance is authorized. Configuration status is
not a network availability claim; no remote request occurs while rendering.
Never pass secrets to the overview. Account settings link to explicit identity
linking with its existing password, recovery and MFA rules.

Use shared local readiness checks in the console and runtime services.
Discord and OpenID need the public address accepted by the existing HTTPS
transport policy. An incomplete provider is not offered as usable login.
Discord validates prerequisites before queueing new work and before taking a
sending claim, preserving a queued announcement if configuration needs repair.
No network operation is performed by a local link/math module.

Each web application owns one current, validated provider catalogue. A changed
exact-instance policy replaces that slot for subsequent requests. Existing
request selections remain immutable; old catalogues are not retained by
revision. Source scanning remains bounded. Provider policy and configuration
revision remain part of cache variants, and only current authorized player
origins enter CSP. Removing the last instance disables the module without
reviving an installation default. Network and instance settings consumed by
fresh request/job configuration are labeled live in the configuration GUI.

Give the existing moderation transfer page a native title chooser and bounded
message checkboxes. A versioned PostgreSQL function checks global moderation,
current thread visibility, category/audience compatibility and poll exclusions.
It returns at most fifty source/destination choices and fifty-one replies for
keyset continuation. Excerpts are plain, length-bounded text. A concurrent
partial trigram index supports title lookup, including newly created threads.
No ordinary discussion page gains a query. Existing write functions retain all
locking, idempotency, audit, visibility and reversal checks. Multiple native
checkbox values and existing comma-separated API values reach the same write
contract. JSON history remains compatible.

## Consequences

Native GUI tests exercise configuration changes in the running application,
instance revocation in cards/CSP, real outbox delivery through a controlled
network boundary, moderated import publication, and move/split/merge with
independent reversals. Permissions and private-source refusal remain enforced
in PostgreSQL. These behaviors are mandatory feature-manifest witnesses.

Deploy the new code and pending migrations, refresh runtime API grants and
restart once for the code deployment. Subsequent supported GUI configuration
changes need no process restart. Actual provider accounts, approved instances,
credentials, TLS and an outbox worker remain operator-supplied configuration.
No Telegram integration or LAN preview is introduced.
