# ADR 0135: Thread Tags

## Status

Accepted. The owner asked on 2026-10-15 for the product features of
docs/PRODUCT_BACKLOG.md; B01 and B02 are the first of the discovery ones
(package PB-02). Local PostgreSQL, HTTP and browser checks pass; acceptance
of this decision does not establish release readiness.

## Date

2026-10-15

## Context

A category is the one classification a thread has, and a subject is often
discussed in several. Nothing lets a reader gather "everything about Perl"
across the forum, nor an author say in a word what a thread is about. The
thread command (ADR 0126 section 5) is guarded by its races, drafts and
automod; changing its shape for a hint is out of proportion, as it was for
the reply link (ADR 0132).

## Decision

A thread carries up to five tags its author names, each up to thirty
characters, typed as a comma-separated field with the title: on the
new-thread form and in the thread's edit-title sheet. A tag is one row by
its slug (`tags`: the name lower-cased, its marks dropped, anything but a
letter or digit a dash), with the name first given; a thread's tags are
rows of their own (`thread_tags`, in order), written after the thread is
made or its title saved, through `api.forum_set_thread_tags_v1`, which
replaces the set. A field left out leaves the tags; a field sent empty
clears them. A write that fails leaves the thread as it is: the thread is
the content, the tags a hint.

Anyone who may read a thread sees its tags as chips under its title, on
its page, on its category's rows and on the home page's latest list, each
a link to the tag's page. `/tags/:slug` lists the threads under a tag the
reader may read (ADR 0102's rule for the thread, then its category and its
space), newest activity first, in every category or in the one
`?category=` names; `/tags` lists every tag with how many such threads it
has. Anyone may create a tag by using it; there is no tag management, no
rename and no merge: the first name given is the name.

## Consequences

- The thread command, its functions and its differential tests are
  untouched; the tags cost one statement after a thread that names them,
  and one read per page of threads (the category page, the thread page and
  the home page each take one more statement; the query budget records
  it).
- A thread hidden, deleted or made members-only keeps its tags; the tag
  page and the index show it only to those who may read it. A tag only
  unreadable threads carry is absent from the index and its page is not
  found.
- Thread events purge the tag pages (`forum:tags`) with the thread's own.
- Erasure and export carry nothing new: the rows hold ids and the words an
  author chose for a thread, which the thread's export already carries.
- Functions follow ADR 0126 and ADR 0127 (typed definer boundaries).
