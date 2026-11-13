# Writing guide

Help the reader complete a task with the fewest decisions and enough context
to act safely. Keep the guide's language consistent and preserve product names,
commands, flags and technical identifiers.

## Start with the task

Open with the outcome and the command or choice that gets the reader there.
Put prerequisites before the step that needs them. Give each section one task;
use headings that help readers find it.

| Instead of | Write |
| --- | --- |
| This document defines the current observability surface. | Use request IDs, query counters and metrics to diagnose a slow request. |
| The command is intentionally non-executing. | The command prints a plan; it changes nothing. |
| The following section provides information on how to perform an upgrade. | Back up the forum, then run the upgrade plan. |

## Keep every sentence useful

Use concrete nouns and active verbs. Prefer short paragraphs. Define a technical
term where it affects a decision; link to the implementation guide for depth.
Remove repeated introductions and promises such as “simple”, “seamless” or
“production-ready” that the evidence cannot establish.

Use lists for steps and tables for choices or field definitions. Label examples
as commands or sample output. Put long output in a collapsible example when it
interrupts the procedure; keep required commands visible and copyable.

## Preserve the contract

Copy commands from the supported workflow. State the working directory, user
and environment when they matter. Explain a destructive action or service
interruption before the command. Keep required checks and recovery steps.

A prose edit must preserve command syntax, paths, settings, field names and
links. Check technical claims against the current implementation. Run the
existing documentation checks after changing navigation or procedures.

## Separate guidance from evidence

Living guides describe the current behavior. ADRs explain decisions; dated
reviews, audits and benchmark reports preserve what was tested. Link to those
records rather than rewriting their results as current guarantees.

Tie performance claims to a revision, workload, dataset, configuration and host.
Distinguish an implemented feature from a passing test, and a local check from
release qualification. Update readiness claims only with matching evidence.

Start at the [documentation index](README.md). Follow the repository's
[contribution rules](../CONTRIBUTING.md) for changes and review.
