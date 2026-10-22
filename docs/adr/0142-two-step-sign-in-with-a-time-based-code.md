# ADR 0142: Two-Step Sign-In with a Time-Based Code

## Status

Accepted. The owner asked on 2026-10-17 for a round of feature completion
under the ADRs, deciding product details along the way; this is backlog
E03 (PB-04). Unit, PostgreSQL and server-rendered checks pass; acceptance
of this decision does not establish release readiness.

## Date

2026-10-17

## Context

A password is the only thing between an attacker and an account, staff
accounts included, and passwords leak. Every authenticator app speaks the
time-based one-time password of RFC 6238, so a second factor costs a member
nothing to install. The secret it rests on must never leave the forum: not
for a third-party QR image service, not to staff, not in an export, not in
an event, a mail, a log or a backup in the clear. A sign-in must not open a
session until the second step passes, and a lost phone must not lock a
member out for good.

## Decision

**Codes.** RFC 6238 as every app reads it by default: HMAC-SHA-1, six
digits, thirty seconds, a 160-bit secret from `Crypt::URandom`. A code is
taken one step either side of now; all three candidates are computed and
compared in constant time (`Service::Identity::SecondFactorCodes`). The step
a code was accepted for is kept (`second_factors.last_step`) and no equal or
earlier step is accepted again, so a code is used once.

**The secret is sealed with a key the database never sees.**
`Service::Identity::SecretBox` seals with encrypt-then-MAC from HMAC-SHA-256
alone, which Perl brings: a keystream of HMAC(encryption key, nonce ||
counter) XORed with the secret, then HMAC(MAC key) over the format, the key
id, the member's id, the nonce and the ciphertext. Both keys are derived
from the configured one under their own labels; the member's id binds a
sealed secret to its row, so a secret copied to another member's row opens
for nobody. The text is `v1.<key id>.<nonce>.<ciphertext>.<tag>`, base64url.

**The key's lifecycle.** `GPFORUM_SECOND_FACTOR_KEY` seals; it is listed
under `security` in the settings file, made like the session secret
(`openssl rand -hex 32`), shown masked in the admin settings page, and
production refuses one shorter than 32 characters or the development key. Development and test use a fixed development key
when none is set; a deployed forum without one offers no two-step sign-in
(the page says so) and members who already have it keep signing in only
while a key that opens their secret is configured -- so the key is backed
up with the settings file, never with the database dump. To rotate: put the
new key in `GPFORUM_SECOND_FACTOR_KEY` and the old one in
`GPFORUM_SECOND_FACTOR_KEYS` (comma separated); every secret opened with an
old key is sealed again under the new one the next time its member signs in
with a code; `second_factors.key_id` (indexed) says which secrets an old key
still seals, and once none does the old key is removed. A key believed
leaked is rotated the same way, and administrators reset the members whose
secret it still seals. Losing every key that opens a secret is losing that
secret: its member signs in with a recovery code, or an administrator
resets it.

**Enrollment.** On `/settings/security` the password begins it: a new
secret is drawn and sealed (`pending`). The page draws the `otpauth://` link
as an inline SVG QR code on the server (`Web::QrCode`: ISO/IEC 18004 byte
mode, level M, versions 1 to 10, no third-party service) beside the key in
base32 to type. The first right code turns it on (`active`), ends the
member's other sessions -- none of them passed a second step -- and shows
ten recovery codes once, on a page no cache stores. A pending enrollment can
be cancelled.

**Recovery codes.** Ten codes of 80 random bits, written as four groups of
four base32 characters, typed in any case with or without dashes; kept as
SHA-256 of a label, the member's id and the code (80 bits make a slow hash
unnecessary). Each signs in once; a code from the app renews all ten.

**The sign-in.** A password that verifies for a member with two-step
sign-in on opens a challenge instead of a session: 32 random bytes whose
SHA-256 is stored with the password credential that verified; the token
itself goes to the signed session cookie only, and the reader is sent to
`/login/second-factor`. A code or a recovery code answers it within five
minutes; five wrong answers close it, ten wrong answers on the account in
an hour refuse new challenges for that hour, which is audited and mailed to
the member (their password is known to someone). A right answer opens the
session in the transaction that closes the challenge and holds the password
credential `FOR SHARE`, so a password reset that commits first leaves the
challenge expired, as a password login's session does. Both steps keep the login
form's per-address and per-account rate limits; `identity.second_factor`
adds ten answers per address per five minutes. JSON clients get `202
{"status":"second_factor"}` and post the code to the same route.

**Turning it off.** The password and a code from the app or an unused
recovery code turn it off; everything of it is deleted.

**Notices.** The member is mailed, in their language and without an
unsubscribe link, when it is turned on, off, reset by an administrator, or
locked: an `identity.mail.requested` event whose outbox message the
function completes with the address and language, delivered by
`Worker::Handler::IdentityMail`. No mail, event or audit row carries the
secret or a code.

**Staff.** The member's admin page shows whether it is on, since when and
how many recovery codes are left -- never the secret, sealed or not. An
administrator turns a member's off for one who lost their app and their
recovery codes (audited, mailed; never their own). `/admin/security` lists
the staff, those without it first, and holds the policy.

**Requiring it of staff.** Staff are members holding a role that grants
anything besides reading a category. An administrator may require two-step
sign-in of staff, only once they have it on themselves (`unenrolled`
otherwise, so nobody shuts themselves out). While it is required,
`api.admin_permission_allowed_v4` -- every staff console's check, the
moderation queue's and the staff realtime channels' -- refuses a staff
permission to a member without it, and their sign-in sends them to set it
up. Members are not affected, nor is reading a category.

**Data.** `second_factors`, `second_factor_recovery_codes`,
`second_factor_challenges` and the one-row `second_factor_policy`
(migration 130), every read and write an `api.*` function with its ADR 0127
boundary. Erasure deletes all of a member's rows (`privacy_revoke_user_v16`
source `SecondFactor`); the export says whether it is on, since when and
how many recovery codes are left (`portability_export_parts_v18`), never the
secret or the codes' hashes. A suspended member may still secure their
account: two-step sign-in is not a community write.

## Alternatives Considered

- **A row of `credentials` with type `totp`** (the placeholder of ADR
  0053). Credentials hold verifiers -- hashes -- and are revoked, not
  deleted; a TOTP secret must be opened to be checked, a pending one is
  replaced, and the steps used and recovery codes are its own state. A
  table of its own keeps password logic untouched.
- **AES-GCM from CryptX.** A new XS dependency and a license review for
  what HMAC-SHA-256 in encrypt-then-MAC already gives a 20-byte secret.
- **PostgreSQL `pgcrypto`.** The key would travel to the database with
  every call and appear in its logs; the database must never hold it.
- **A QR code from an image service or a CPAN module.** The first sends the
  secret away; the modules found need libqrencode or GD.
- **SMS or email codes.** Weaker, and mail is how an account is recovered;
  WebAuthn remains a later credential type.

## Consequences

- A sign-in with two-step sign-in on costs one more page and four function
  calls; a sign-in without it one more lookup (`challenge_open` answers
  `none`). Each staff console request costs one more indexed lookup while
  the policy is read.
- Operators keep `GPFORUM_SECOND_FACTOR_KEY` with the settings file; a
  restore of the database without it leaves members to their recovery
  codes.
- Every successful second step is audited (`identity.second_factor.passed`),
  so the audit log grows by one row per such sign-in.

## References

- [ADR 0053](0053-security-architecture.md)
- [ADR 0074](0074-privacy-data-protection-legal-operations.md)
- [ADR 0118](0118-exceptions-are-gpforum-x-classes-required-attributes-are-declared.md)
- [ADR 0126](0126-sql-lives-in-postgresql-functions.md)
- [ADR 0127](0127-separate-runtime-role-for-the-function-api.md)
