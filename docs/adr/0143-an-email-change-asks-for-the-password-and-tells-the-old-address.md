# ADR 0143: An Email Change Asks for the Password and Tells the Old Address

## Status

Accepted. A read-only review of main on 2026-10-15 found that a signed-in
session alone could move an account to another address and that the
address it left was told nothing; the owner asked for every defect it
confirmed to be fixed under the ADRs. Unit and PostgreSQL checks pass;
acceptance of this decision does not establish release readiness.

## Date

2026-10-17

## Context

`Controller::Identity::Email` started an email change with the session
alone: no password, unlike a change of password. Whoever held a session --
one left open on a shared computer, or stolen -- could name an address of
their own, confirm it from the mail sent there, and then reset the password
through it. The address the account left was told nothing, so its member
learnt of it when they could no longer sign in, and a password reset no
longer reached them.

## Decision

1. **The current password.** `request_email_change` takes
   `current_password`; the workflow refuses a request without one, and
   `AccountStore` checks it as `change_password` does (the active
   credential, `Service::Password->verify_password`), answering
   `invalid_current_password` before it looks the address up, so a wrong
   password learns nothing of whose address is whose. The request keeps the
   rate limit of a password change (`identity.email_change`), and a refusal
   is the 400 a wrong password gets there. The settings form asks for it.
2. **The address it leaves is told.** With the confirmation to the new
   address, `AccountStore` queues `email_change_notice` to the address the
   member has, through the identity mail outbox, about the same token and in
   the member's `preferred_locale`. `Worker::Handler::IdentityMail` sends it
   as it sends the two-step sign-in notices of ADR 0142, from
   `auth.email_change_notice_mail_*`, English and Italian, through
   `Mailer->send_security_notice`, which now keeps a long encoded subject
   on one line as Email::Simple requires. It says a change was asked for
   and how to stop it: the password reset page, which comes to that address
   for as long as the change is unconfirmed. It carries no token: one left
   in a mailbox the member may be leaving would outlive the change.
3. **The way to stop it works.** A password reset, and a change of
   password, withdraw the member's pending email change
   (`TokenStore->withdraw_open_token`, through the existing
   `api.identity_unused_token_v2` and `api.identity_rotate_token_v2`: the
   token is rotated to a secret nobody was given), so its link no longer
   confirms; their audit says whether there was one.
4. **One message per kind and token.** An identity mail's idempotency key
   names its kind as well as its token, since the confirmation and the
   notice are two messages about one token.

## Consequences

Moving an account to another address needs its password, and its member
hears of it at the address they have, with a remedy that reaches them
there. An attacker who has the password as well, and confirms at once,
still takes the address; the notice is then how the member learns of it.

No migration and no new SQL function: the check and the withdrawal use
the identity functions the store already calls. Rollback is reverting the
change; a notice already queued is skipped by the reverted worker, as a
kind without a token it does not know.

## Related Decisions and Implementation

- ADR 0014 (identity workflow boundary), ADR 0053 (security
  architecture), ADR 0118 (exceptions are `GPForum::X`; a refusal is a
  result), ADR 0141 (the session token, rotated at sign-in), ADR 0142
  (the notice mails of two-step sign-in).
- `lib/GPForum/Controller/Identity/Email.pm`,
  `lib/GPForum/Service/Identity/Workflow.pm`,
  `lib/GPForum/Service/Identity/AccountStore.pm`,
  `lib/GPForum/Service/Identity/TokenStore.pm`,
  `lib/GPForum/Service/Identity/Event.pm`,
  `lib/GPForum/Service/Identity/Mailer.pm`,
  `lib/GPForum/Worker/Handler/IdentityMail.pm`,
  `templates/identity/settings.html.ep`, `locale/en.po`, `locale/it.po`.
- `t/713-email-change-guard.t`, `t/integration/postgres-identity-stores.t`.
