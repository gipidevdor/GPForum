# ADR 0149: OWASP ASVS 5.0 Is the Security Bar

## Status

Accepted. The owner decided on 2026-10-22 that GPForum must comply with
OWASP to the best standards: ASVS 5.0 Level 2 for the whole application,
and Level 3 for authentication, sessions, access control and moderation.
Amends ADR 0053, which says what the security architecture must do, by
naming the standard its verification is measured against. Accepting this
decision claims no level: nothing has been verified against the standard
yet.

## Date

2026-10-22

## Context

ADR 0053 lists what GPForum must defend against and how, but no external
yardstick says when that is achieved, so each review measured the code
against its own reading. A read-only review of main on 2026-10-15 rated
the code well and still confirmed defects in the areas that matter most:
a post body of any length rendered in quadratic time, the session token
in a cached page, an email change without the password, a suspended
member still uploading, a realtime socket that outlived its session, and
a suspension that ends early because its end is compared as a string.
All but the last are fixed under ADRs 0140, 0141, 0143 and 0148 and in the
moderation stores. The last is still an expected failure in
`t/integration/postgres-moderation-review.t`.

The OWASP Application Security Verification Standard is the recognised
yardstick for that question. Version 5.0.0 (May 2025) is the current
release. It has seventeen chapters, from V1 Encoding and Sanitization to
V17 WebRTC, and three levels, each including the ones below it: Level 1 is
the minimum, Level 2 the level most applications should reach, and Level 3
the highest. A requirement is cited as `v5.0.0-<chapter>.<section>.<requirement>`
(for example `v5.0.0-1.2.5`), because identifiers change between versions.
The OWASP Top 10 is an awareness list, not a verification standard.

## Decision

1. **The standard is ASVS 5.0.0.** Compliance is claimed against it alone.
   A requirement is cited with its versioned identifier in ADRs, the
   CHANGELOG, commit messages and tests. A later ASVS release is adopted by
   amending this ADR, never silently.
2. **Level 2 for the whole application.** Every requirement up to Level 2
   in every chapter that applies.
3. **Level 3 for four areas:**
   - **Authentication**: V6, and the requirements of V11 Cryptography that
     password storage, the two-step sign-in code and the mail tokens rest
     on.
   - **Sessions**: V7.
   - **Access control**: V8.
   - **Moderation**: every path through which staff act on members or
     their content -- suspensions, address bans, reports, held posts, the
     moderation queue, staff notes and role changes -- to Level 3 in V2
     (business logic), V8 and V16 (security logging).
4. **What applies.** V10 (OAuth and OIDC) and V17 (WebRTC) do not apply:
   GPForum signs nobody in through another provider, is no provider, and
   has no WebRTC. V9 (self-contained tokens) applies to the tokens whose
   validity rests on their own signature: the signed session cookie and
   the one-click unsubscribe token (ADR 0078). V4 applies to the JSON
   answers and to the realtime WebSocket. A change that makes a chapter
   apply, such as a sign-in through another provider, brings it into scope
   at the level of its area.
5. **A verification record.** One document lists every requirement in
   scope, with its level and its state: met, not met, or not applicable
   with the reason. Each met requirement names its evidence: a test where
   one can be written, otherwise the code or configuration that meets it.
   Until the record exists and shows a level met, GPForum claims none.
6. **Every change.** A change to authentication, sessions, authorization,
   moderation, input handling, output encoding, files, cryptography,
   secrets or security logging is checked against the chapters it touches,
   and names the requirements it meets or affects. A feature is done when
   it meets the requirements of its area's level. A review finding is
   recorded against the requirement it breaks.
7. **The Top 10 as a checklist.** A review walks the OWASP Top 10 to find
   what to look at, and reports what it finds against ASVS requirements.

## Consequences

Security has one external, versioned bar: reviews become comparable, a
claim can be audited, and "secure enough" stops being a matter of opinion.
The work is substantial. The verification record has to be built first,
requirement by requirement, and Level 3 is likely to ask for more than
GPForum has today in the four areas, such as the WebAuthn support that
ADR 0053 already asks for (two-step sign-in is TOTP only, ADR 0142).

The open suspension finding falls in a Level 3 area (V8, moderation) and
is the first known gap.

Nothing changes at run time, so there is nothing to migrate. Rollback is
reverting this ADR and its amendment of ADR 0053.

## Related Decisions and Implementation

- ADR 0049 (foundational architecture), ADR 0053 (security architecture,
  amended here), ADR 0087 (ADR governance).
- Defects of the 2026-10-15 review, fixed under ADR 0140 (one maximum
  length for a post body), ADR 0141 (no session token in a shared page),
  ADR 0143 (an email change asks for the password) and ADR 0148 (a realtime
  socket ends with its session); related security features are ADR 0142
  (two-step sign-in), ADR 0146 (address bans) and ADR 0147 (sign-in
  lockout).
- `t/integration/postgres-moderation-review.t` (the suspension finding).
- OWASP ASVS 5.0.0:
  <https://github.com/OWASP/ASVS/tree/v5.0.0/5.0/en>; project page
  <https://owasp.org/www-project-application-security-verification-standard/>.
