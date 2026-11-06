# ADR 0133: Watched Words and Automod Rules

## Status

Accepted. The owner asked on 2026-10-15 for the backlog's features to be
completed under the ADRs, deciding product details along the way; this is
PB-05 (backlog F07, then F06). Unit, PostgreSQL and server-rendered checks
pass; acceptance of this decision does not establish release readiness.

## Date

2026-10-15

## Context

Staff could act on a report, but nothing acted on content as it was
written: no list of words a community does not want, no limit on the links
a brand-new account can post. Rules of this kind are the classic way to
run a regular-expression engine on attacker-chosen text, so the pattern
language itself is part of the security decision. A decision taken by the
server is a moderation decision and must be as traceable as one taken by a
moderator.

## Decision

**Watched words.** Staff keep one list of at most 500 entries in
`public.watched_words` (phrase, action, replacement, who added it, when).
An entry is a word or phrase of at most 100 characters, kept with its
whitespace collapsed and its case folded. It matches whole words, without
regard to case, and any whitespace between its words. The only pattern
syntax is a star at its start or end, which lets the word run on for at
most 32 word characters (`spam*` matches `spammers`). Every entry compiles
to a literal search inside negative word-character lookarounds, so the
matching is linear in the text with a bounded constant: there is no
alternation, nesting or unbounded repetition an entry can introduce, and
no regular expression is ever taken from staff input.

Each entry has one action:

- **block** refuses the write as `invalid`, naming the field and the
  matching words, in the writer's language; nothing is stored;
- **flag** stores the write and puts it in the moderation queue (or,
  when staff ask, holds a new thread or reply for review instead: ADR
  0134);
- **replace** stores the write with each match replaced by the entry's
  replacement (at most 100 characters; `***` when empty).

Block and flag judge the text as written; replacements are applied after,
to the text that is stored.

**Links.** One rule, in the singleton `public.automod_settings`: at most N
links (0–100) in a post by a member whose trust level is below T (default
1, so new members), blocked or flagged. No row, or an empty limit, means
the rule is off; that is the default. Links are counted in the Markdown
source: a URL with a scheme, or one starting with `www.`.

**Flooding** is left to the existing posting rate limiter. A content
rule for it would duplicate a limit that already holds per member and
action, so none is added.

**What is screened.** A new thread (title and body), a reply, a post edit
(body) and a thread title edit, before the command runs. Staff holding the
global `thread.moderate` binding are not screened: they quote what they
act on and they write the rules. The rules, the link rule and the author's
trust level come in one call, `api.moderation_automod_rules`, so a write
pays one extra round trip.

**Flags are system reports.** `reports.reporter_user_id` becomes nullable:
a report without a reporter is the system's, shown as *Automod* in the
queue with the rule that raised it. A write with a flag or a replacement
runs in one transaction with `api.moderation_automod_record`, which opens
the report (at most one open system report per target, serialized by an
advisory lock per target) with its `report.created` event and audit, and
records the audit of each decision. A failure to record undoes the write
and answers `failed`. A write replayed from the command log records
nothing again. A thread's flag targets the thread; a reply's or an edit's,
the post.

**Every decision is audited**, with no actor (the system decided) and the
author, the command and what matched in the metadata:
`automod.blocked` (target: the author), `automod.flagged`,
`automod.replaced`. Staff changes are audited with their actor:
`automod.word_added`, `automod.word_removed` (with the phrase and action
removed), `automod.link_rule_set` (with the rule before and after).

**The admin console** page `GET /admin/automod` lists the words and the
link rule, with a form to add a word, one to remove each and one for the
link rule (`POST /admin/automod/words`, `/admin/automod/words/:id/remove`,
`/admin/automod/links`). Reading needs `admin_console.view`; every change
needs `admin_console.manage`, a CSRF token and the admin write rate limit.
The forms work without JavaScript and answer with a redirect and a notice,
or JSON when asked.

**Storage.** Migration 115 adds the tables and the functions
`moderation_watched_word_add`, `_remove`, `_list`,
`moderation_automod_settings_set`, `moderation_automod_rules` and
`moderation_automod_record`, each an invoker `_v1` behind its definer
`_v2` boundary (ADR 0126, ADR 0127). Perl validates the input, builds the
audit records and the report's event, and reads the results.

## Consequences

- One function call is added to every screened write, and none to any
  read; a write with a flag or a replacement adds a transaction around it.
- Matching is Perl's, per process, with the compiled entries cached; the
  database holds the rules and the decisions.
- A language written without spaces matches an entry inside a longer run
  of text only through a wildcard.
- The report queue now holds reports with no reporter; readers of
  `reports` treat a NULL reporter as the system.

## References

- [ADR 0118](0118-exceptions-are-gpforum-x-classes-required-attributes-are-declared.md)
- [ADR 0126](0126-sql-lives-in-postgresql-functions.md)
- [ADR 0127](0127-separate-runtime-role-for-the-function-api.md)
