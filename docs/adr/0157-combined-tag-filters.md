# ADR 0157: Combined Tag Filters

## Status

Accepted (2026-11-01). The owner requested completion of the product features,
with strict correctness and extremely fast performance.

## Context

Threads carry up to five tags. The existing tag reader accepts one slug and
search accepts no tag predicate. Filtering after LIMIT would omit valid results
and give incorrect candidate-cap semantics.

## Decision

`/tagged` accepts one to five comma-separated exact slugs and `tag_match=all`
(the default) or `any`. Repeated slugs are one requirement. Unknown slugs make
an intersection empty and contribute nothing to a union. Malformed filters are
400 responses. A timestamp/UUID keyset pages the visible matching threads;
category restriction remains available. Filter pages are private/no-store.

Search accepts the same `tags` and `tag_match` fields, with or without text.
New tagged search functions preserve the current live-placement permission
checks and apply membership before the candidate cap and ranking. The unfiltered
search entry points and the hot home/category/thread reads are unchanged.

Migration 1059 adds versioned INVOKER implementations, forwarding DEFINER
boundaries and a bounded tag-membership helper. Every selected tag is checked
against current thread tags; search indexing lag cannot retain an old tag.
No new user data, event type, worker or external service is introduced.

## Consequences

Existing single-tag links and older workers retain their function contracts.
The new filter and search functions are included in the runtime-role catalogue.
No per-row SQL round trips or per-result rendering queries are added. Query
counts alone do not certify cost: representative plans and timings must accompany
the increment before its performance is claimed.

## Validation

`t/integration/postgres-combined-tags.t` exercises intersections, unions,
unknown/duplicate/invalid tags, disjoint keyset pages, live visibility and deleted
categories, filtering before a one-candidate search cap, and SSR/JSON forms.
The existing tag and function-catalogue suites remain applicable. Execution
results and performance evidence are recorded in the completion ledger.
