# Good Phorum: name and brand

**Good Phorum** is the full project name. **GP Forum** is its short form.
**GP** stands for **Good Phorum**, and the **P** in **Phorum** stands for
**Perl**, the language the application is written in.

## Meaning

*Phorum* is a deliberate spelling of *forum*, with a P for Perl. The name
connects the software to its language while keeping its purpose broad:
communities can discuss any subject, share interests, ask questions and
build lasting conversations. A community does not have to be about Perl.

*Good* expresses the aim: a welcoming place where people can contribute,
find useful conversations and disagree respectfully. Readability,
accessibility and clear moderation support that aim.

## Writing the name

- Use **Good Phorum** in project titles, introductions and ordinary prose.
- Use **GP Forum** when a short form is useful, with the full name on first
  mention when space allows.
- Keep the capital **P** in **Phorum** and write the language as **Perl**.
- Use `GPForum` for the Perl application class, `GPForum::*` namespaces and
  other existing technical identifiers. Commands remain `gpforum`, settings
  remain `GPFORUM_*`, and the repository is `gipidevdor/GPForum`.
- Keep existing paths, filenames, protocol names and HTTP headers exactly
  as implemented when documenting them. Historical output and archived
  evidence retain the names they actually recorded.
- The maintainer and copyright attribution remains **GPForum Contributors**,
  as required by [ADR 0092](adr/0092-github-project-success-contract.md).

For example, write "Good Phorum stores its canonical data in PostgreSQL"
and "Run `gpforum doctor` to check the installation."

## Each community has its own name

Good Phorum identifies the software project. An installation uses its own
community name through `GPFORUM_SITE_NAME` and an optional introduction
through `GPFORUM_SITE_DESCRIPTION`. Member-facing pages, mail and
notifications use that configured name. Project branding belongs in the
software's documentation and project materials; see the
[design system](ui/design-system.md).

## Visual identity

The existing mark consists of two open arcs and an amber node, suggesting
dialogue and connection. Its geometry and asset filenames carry forward
under the Good Phorum name. Accessible labels on project artwork use
**Good Phorum**.

See the [editable artwork](../assets/source/README.md) and
[theming guide](../THEMING.md) for the source files and visual system.
