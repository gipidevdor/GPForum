# ADR 0166: Member profile editing

## Status

Accepted (2026-11-02), following the owner's request that each member can edit
their own profile freely.

## Context

Members could edit their biography and upload a profile picture, but the public
profile offered no edit action and the public display name could not be changed.
A member should be able to update their public identity without staff intervention.

## Decision

The member's own profile shows **Edit profile** and a picture link. The account
menu also links directly to the profile form. Settings prefill the public name
and biography, offer a picture link and a return to the public profile.

Active members can immediately save their display name (1–100 characters,
without control characters) and biography (up to 500 characters, plain text).
The existing picture upload and moderation rules continue to apply. Login
username and email retain their independent identity and recovery rules.

The controller selects the account exclusively from the authenticated session,
accepts only the two public text fields, and retains CSRF, participation and
rate checks. Both fields save together through the identity workflow and a
fixed PostgreSQL API function. The command fingerprint includes both fields;
replays cannot turn into different edits and recorded responses omit the text.
An unchanged profile avoids a database write. Public views escape both fields.

Migration 2034 adds the dedicated function and its restricted definer entry
point. It changes no table or stored data. Apply it and refresh catalogue-based
runtime grants before restarting application workers. Application rollback may
leave these additive functions in place.

## Validation

PostgreSQL HTTP coverage exercises an ordinary member's edit, own/other/guest
links, immediate public rendering, attempted account selection and privilege
changes, CSRF, command replay and conflict, invalid/oversized fields, atomic
failure, text escaping, normalized line endings and suspended accounts. Existing
biography-only submissions remain compatible.
