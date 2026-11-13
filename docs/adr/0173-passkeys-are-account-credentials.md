# ADR 0173: Passkeys are account credentials

## Status

Accepted (2026-11-06).

## Context

The isolated registration example verified WebAuthn but persisted nothing. It
did not satisfy the owner's request to connect every feature to the forum GUI,
accounts and existing authentication workflows.

## Decision

Expose passkeys from the account menu, settings and security page, and add
discoverable sign-in to the login form. Store the verified credential as the
existing `webauthn` credential type, with public-key metadata and a stable opaque
per-account/RP handle in PostgreSQL. Offer ES256 and require user verification.
Preserve configured TOTP, recovery codes and staff enrollment policy.

Use the configured public origin and RP, never request host headers. Require
exact Origin and CSRF on every ceremony. Bind five-minute challenges to a random
browser nonce, purpose, origin and, for enrollment, the current account/session
and freshly verified password credential. Consume a challenge atomically before
verification, including failed responses. A replayed signed cookie cannot
restore it. Bound canonical Base64URL, safe CBOR, explicit ES256, flags and
user-handle checks precede the real Authen::WebAuthn verifier.

Share local password/TOTP proof with OpenID account changes. Repeat credential
and counter checks inside the session/write transaction. Lock the recovery
password before the passkey credential, following existing recovery lock order.
Device-bound signature counters advance; synchronized credentials may report
zero or a lower counter and must retain their original backup eligibility.
Revocation requires fresh proof, closes other sessions and pending TOTP
challenges, and commits with audit. Password rotation revokes every passkey;
erasure already revokes all canonical credentials.

## Consequences

Deploy the main locked dependencies and migration 2043, refresh runtime API
grants and restart the application. HTTPS is required outside loopback
development. A local password remains necessary for recovery and account
changes. The isolated example remains a nonpersistent teaching application.

The executed feature manifest includes native GUI enrollment and revocation,
real signed assertions, normal sessions, TOTP and password recovery. PostgreSQL
tests cover invalid signatures, origin/RP/UV/handle mismatches, counters,
replay and expiration; client tests cover binary transport, cancellation,
unsupported contexts and safe redirects. These do not attest to physical
biometric execution on a particular device.
