# Doc comments (Javadoc, KDoc, JSDoc/TSDoc, Vue SFC)

## Two kinds of rule, and only one of them is negotiable

**Prose and content are the standard.** They do not bend to what the surrounding
code happens to do. Apply them in every language.

**Markup and formatting are per-language and per-project.** Derive these: read the
codified config first (IntelliJ `JD_*` keys in `.idea/codeStyles`, checkstyle
`Javadoc*` modules, inspection profiles, `eslint-plugin-jsdoc` or `tsdoc` rules in
the ESLint config), then measure the module and follow it. If the project's
CLAUDE.md already records what is enforced, use that instead of re-measuring.

Never assume a codebase is an exemplar without checking. Machine-generated doc
comments have a distinct register, and that register is the thing being
corrected, not a pattern to copy. Measure to learn the markup; never to learn the
prose.

## Prose: the standard

- **Imperative mood for functions.** "Get the subject." not "Gets the subject." or
  "Returns the subject." A value (property, constant, type, ref, prop) gets a noun
  phrase: "The events the admin owns." not "This holds the events."
- **Short declarative sentences.** If a sentence needs a dash to hold itself
  together, it is two sentences.
- **No em-dashes** (`—`, `&mdash;`), and no `--` standing in for one. What replaces
  the dash depends on what the dash was doing:
  - **Joining two independent clauses.** Split into two sentences. `A — B` becomes
    `A. B.`, not `A, B`. This is the common case.
  - **Introducing an appositive or aside.** A comma is correct, because there is no
    second sentence to split into. "Reserved-TLD suffix blocks (RFC 6761) —
    including the sink domain reviewr.test." becomes "…(RFC 6761), including the
    sink domain reviewr.test."
  - **A dash *pair* wrapping a parenthetical.** Reflow rather than re-punctuate.
    Move the aside into its own sentence or to the end of the host sentence;
    swapping both dashes for commas buries the main clause. "Build a supplier for
    groups the user may add — those they can administer — filtered by name."
    becomes "Build a supplier for groups the user may add. Those are the groups they
    can administer. The results are filtered by name."
- `NOTE:` prefixes a caveat. Sparingly. If everything is a note, nothing is.
- No marketing register: "powerful", "simply", "seamlessly", "robust", "leverages".
- **State the mechanism, not the ticket.** "The sweeper reads the time-to-live back
  out of the directory name, so it needs no in-memory record" ages well; "fixed per
  PF-2960" does not.

## Content: the standard

Say what the signature cannot:

- **Ownership and lifecycle.** Who closes it. Who owns it after this call.
- **Why the code is shaped this way**, when a reader would otherwise wonder.
- **Failure modes** and what still holds after one.
- **Thread-safety and reuse**, when either is limited.
- **Reactivity**, in Vue: what a computed depends on when it is not obvious, and
  what a watcher does that the template cannot show.

**Bare restatements are Javadoc-only.** A tag that only repeats the signature
(`@param file the file.`) stays in Java, where the inspection profile or
checkstyle requires the tag to exist. In KDoc, JSDoc and TSDoc no tool requires
it, so delete it. The types already say what it says. Keep a `@param` or
`@returns` in those languages only when it adds something: a unit, a range, a null
contract, an ownership rule.

Do not expand a one-line comment to three lines to look thorough. Comments that
fit on one line stay on one line.

Strive for conciseness in plain english, not restating what is already obvious.
Remove any comments that do not add significant value.
If a comment has a ticket reference then leave at least the ticket reference.
If the comment states what can be figured out from reading the code, then remove the comment.
Favor removing comments versus keeping or rewriting; comments and documentation really need to have value.

## Markup: derived, defaults per language

| | Javadoc (HTML) | KDoc (Markdown) | JSDoc/TSDoc (Markdown) |
| --- | --- | --- | --- |
| paragraph | `<p>…</p>` | blank line (a lone `*`) | blank line (a lone `*`) |
| link | `{@link Type#member}` | `[Type.member]`, `[text][Type]` | `{@link Type.member}`, or `` `name` `` when the reader can find it |
| inline code | `{@code x}` | `` `x` `` | `` `x` `` |
| list | `<ul><li>` | `- ` bullets | `- ` bullets |
| emphasis | `<b>`, `<i>` | `**bold**`, `*italic*` | `**bold**`, `*italic*` |
| return tag | `@return` | `@return` | `@returns` |

Javadoc: prefer `{@code}` to `<code>`; avoid `<dl>/<dt>/<dd>`. Every `{@link}` must
resolve. It is a build error in many configs.

KDoc: never use HTML. `{@link}`/`{@code}` do not exist in KDoc and silently render
as literal text. The first paragraph is the summary, so lead with it.

JSDoc/TSDoc: never use HTML, and never write `{@code}`; TypeScript does not know
it. Never write `@param {Type} name` in TypeScript; the type annotation already
says it. `@param name` alone is legal but usually a bare restatement (see Content).
A `{@link}` is checked by the TypeScript language service, not the build, so a
broken one is a warning in the IDE and nothing in CI. Prefer plain backticks
unless the reader really needs to jump.

**Tag spacing differs and is not a style choice.** Java projects driven by the
IntelliJ `JD_*` keys put a blank line after the `@param` group and after `@return`,
with no blank between consecutive `@param`s. KDoc and JSDoc conventionally run all
tags together with no blank lines. Check the project rather than carrying one
habit into another language.

Kotlin has tags with no Javadoc equivalent: `@property`, `@constructor`,
`@receiver`, `@sample`, `@suppress`. Do not invent them, and never drop one while
editing.

## Vue single-file components

One file, three comment syntaxes. The prose standard is the same in all three.

- **`<script>` / `<script setup>`:** JSDoc, exactly as in a `.ts` file. A
  `defineProps` field takes a JSDoc block above it; that is what the IDE shows on
  hover in the parent template.
- **`<template>`:** `<!-- -->`. Rare, one line, and only for what the markup cannot
  say: why an element is ordered as it is, why a wrapper exists, what an
  `eslint-disable` is excusing. A template comment is never converted to another
  markup; there is nothing to convert.
- **`<style>`:** `/* */` (and `//` when `lang="scss"`). Same rule as the template:
  explain the non-obvious, such as why a magic number or a `!important` exists.
