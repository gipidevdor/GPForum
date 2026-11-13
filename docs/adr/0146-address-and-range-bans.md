# ADR 0146: Address and Range Bans

## Status

Accepted. The owner asked for a round of feature completion under the
ADRs, deciding product details along the way; this is backlog F08 (PB-18).
Unit, PostgreSQL and server-rendered checks pass; acceptance of this
decision does not establish release readiness.

## Date

2026-10-22

## Context

Staff could suspend an account, and every write had a per-address rate
limit, but nothing stopped a visitor from making the next account, or a
spam wave from one provider's addresses from registering and posting
again. A ban on an address has to reach the requests that matter --
registration, the ways into an account, every write -- without slowing the
pages people read, without locking staff out of the console that lifts it,
and without telling the visitor anything but no.

## Decision

**A ban is a row of its own.** `public.address_bans` holds a `cidr` range,
its scope, a reason (one line, 1 to 500 characters, for staff only), when
and by whom it was placed, its expiry, who last edited it and when, and who
lifted it and when. It is not an event, an outbox message or a search
document; it reaches no feed and no realtime channel.

**Ranges are bounded.** Staff write one address (IPv4 or IPv6) or a CIDR
range; Perl parses it with `inet_pton`, clears the host bits
(`203.0.113.7/24` is stored as `203.0.113.0/24`) and reads an IPv4-mapped
IPv6 address (`::ffff:a.b.c.d`) as the IPv4 address, as a dual-stack
listener reports it. A range is at most an IPv4 `/16` (65,536 addresses)
or an IPv6 `/32` (one provider's allocation); a wider one is refused as
`too_broad` by Perl, by the function and by a table constraint. Banning a
country or a whole cloud is out of reach on purpose.

**Three scopes, nested.** `registration` refuses creating an account;
`sign_in` refuses that and every way into one (sign-in, its second step,
the password reset request and its completion); `writes` refuses every
request whose method is not GET, HEAD or OPTIONS. No ban refuses signing
out, the language and theme of the page that says no, a mail's one-click
unsubscribe (RFC 8058), a member's privacy requests (ADR 0074), or the
console's own ban forms, so that staff a ban covers can still lift it.

**Every ban expires.** Staff choose 1 hour, 1 day, 7, 30 or 90 days, or a
year; an address changes hands, and a permanent ban outlives its reason. An
edit keeps the expiry or sets a new length counted from now. A ban that
ended -- lifted or expired -- more than 90 days ago is deleted the next
time a ban is placed: the audit keeps the history, and the address is not
kept longer than it is used.

**Enforced in one place.** `Web::ClientAddress->register` adds, next to the
hook that finds each request's client, an `around_action` hook that asks
`Web::AddressBans->admits` before the endpoint runs. A read never asks. A
write asks `api.admin_address_ban_covering_v2(address, now)` for the live
ban covering the client -- the strongest scope first, then the one that
lasts longest -- and is refused with a plain 403 when that scope reaches
its route. The page and the JSON (`status: address_banned`) say only that
the forum does not accept the request from the visitor's network: neither
the reason nor the range. Each refusal counts as the security event
`address_ban_refusal`. A request whose client is no address (the Unix
socket without a proxy) is never covered. When the lookup fails, the write
goes on and the failure is logged: a database that cannot answer it cannot
take the write either, and the unit tests' applications have no database.

**One indexed lookup per write.** The live ranges have a partial GiST index
(`address_range inet_ops WHERE lifted_at IS NULL`); the lookup is
`address_range >>= address AND expires_at > now`, a generic plan, about
0.02 to 0.1 ms on 20,000 ranges. Reads -- every page in the query budgets --
make no call. An in-process cache was rejected: bans must take effect on
every worker at once, and a write already makes several calls.

**From the admin console.** `/admin/address-bans` lists the bans, live
first, with who placed, edited and lifted each; answers "which ban covers
this address?"; and shows staff the address they write from. Reading needs
`admin_console.view`; placing, editing and lifting need
`admin_console.manage` through the permission and role-binding model, the
CSRF token and the admin write rate limit, and are refused to a suspended
staff member. A form's command id is the ban's id, so a resubmission
answers `replayed`. A sign-in or writes ban that would cover the address
the staff member writes from is refused (`covers_self`); a live ban on the
very same range is a `duplicate`, answered with its id, to edit instead.
Every place, edit and lift is audited (`address_ban.placed`, `.edited`,
`.lifted`) with the range, scope, expiry and the reason's length, never its
text.

**SQL.** Migration 134 adds the table and `api.admin_address_ban_place`,
`_edit`, `_lift`, `api.admin_address_bans` and
`api.admin_address_ban_covering`, each a `_v1` implementation behind its
`_v2` definer boundary (ADR 0126, ADR 0127), and `privacy_revoke_user`
v21/v22.

**Privacy.** A ban is about an address, not about a member, and is
security data: the export leaves bans out (ADR 0074). The erasure of a
staff member removes their id from the bans they placed, edited or lifted
(`privacy_revoke_user` source `AddressBan`); the bans stay.

## Consequences

- A write costs one more indexed call; a read costs nothing.
- A shared address -- a carrier's NAT, an office -- banned for writes
  refuses everyone behind it until the ban ends or is lifted; the bounds,
  the scopes and the expiry keep that deliberate and short.
- Behind a proxy the client is what `Web::ClientAddress` reads (ADR 0086,
  ADR 0137): a misconfigured proxy makes every visitor one address, which
  `covers_self` then protects staff from banning.

## References

- [ADR 0074](0074-privacy-data-protection-legal-operations.md)
- [ADR 0086](0086-packaging-deployment-runtime-processes.md)
- [ADR 0118](0118-exceptions-are-gpforum-x-classes-required-attributes-are-declared.md)
- [ADR 0126](0126-sql-lives-in-postgresql-functions.md)
- [ADR 0127](0127-separate-runtime-role-for-the-function-api.md)
- [ADR 0137](0137-the-forum-reaches-postgresql-and-its-proxy-over-unix-sockets.md)
- [PostgreSQL network address functions and operators](https://www.postgresql.org/docs/18/functions-net.html)
