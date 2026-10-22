# ADR 0147: A Browser a Member Signs In From Is Not Locked Out

## Status

Accepted. A read-only review of main on 2026-10-15 found that the limit on
the sign-ins one account receives let anyone lock its member out; the owner
asked for every defect it confirmed to be fixed under the ADRs. Unit checks
pass; acceptance of this decision does not establish release readiness.

## Date

2026-10-17

## Context

A sign-in is limited twice, both before the password is checked: per
address (`identity.login`, 10 every five minutes) and per account, from
every address together (`identity.login_account`, 20 every five minutes,
keyed by the identifier as typed). The second stops many addresses, each
under its own limit, from trying one account thousands of times. But it
counts anyone's attempts: twenty wrong passwords every five minutes, sent
from anywhere, and the member's own right password was refused with 429 as
well, for as long as someone cared to keep sending them. Now that
`Web::ClientAddress` gives each request its real client address (ADR 0086),
the per-address limit holds on its own; the account limit is what needs to
stop being a lockout without stopping being a limit.

## Decision

1. **A browser that has signed in is known.** When a password is right --
   a sign-in accepted, or one waiting for its second step (ADR 0142) --
   the response sets `gpforum_device`, a signed cookie (the application's
   secrets, as the session) holding a mark of the identifier as it signed
   in: the SHA-256 digest of `gpforum-device:` and the lower-cased,
   trimmed identifier, so the cookie does not carry it. It holds the marks
   of the last five accounts signed in to there, newest first; it is
   `HttpOnly`, `SameSite=Lax`, `Secure` where the session cookie is, and
   lasts a year. Signing out leaves it.
2. **The account limit does not apply to it.** A sign-in from a browser
   whose cookie carries the mark of the identifier it names is checked
   against its address's limit only. A browser without that mark, or with
   a mark whose signature does not verify, meets both limits, as before.
3. **No account lockout.** Nothing locks the account itself: someone
   guessing its password from elsewhere slows the sign-ins of new browsers
   for as long as they keep at it, never the browsers its member already
   signs in from, and never past their own address's limit.

## Consequences

A member is not locked out of the browsers they use by attempts made from
anywhere else. Guessing an account's password is still bounded by its
account limit from every browser without its mark, and a mark is earned
only with the right password. A member on a new browser, or one whose
cookies were cleared, while their account is under attack, waits as
before; a mark copied with the browser's cookies lets its holder skip the
account limit, which matters little to someone who already has those
cookies, the session cookie among them.

## Alternatives Considered

- **Key the account limit by account and address together.** It cannot
  lock anyone out, but it leaves no limit on one account across addresses,
  which is what the account limit was added for.
- **Count only failed sign-ins against the account.** The member's right
  password would still be refused once the attempts of others had used the
  limit up, so the lockout would remain.
- **Lock the account after N failures.** The very lockout this decision
  removes.
