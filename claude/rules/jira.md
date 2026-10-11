# Jira

- Jira comment/ticket on user's behalf (`addCommentToJiraIssue`, `createJiraIssue`): end body/description with footer on own line:

  `— Posted by Claude Code on behalf of <full name>`

  (New tickets: "Created by" not "Posted by".) Get `<full name>` from `/usr/bin/id -F`; fall back to
  `git config user.name` if empty. Never guess or hard-code it.
- Applies even when user dictates content verbatim, unless user explicitly says omit the attribution.
- **Markup: pass `contentFormat: "markdown"` and write actual Markdown.** Cloud Jira instances are
  ADF-backed; the MCP tool converts Markdown, and never wiki markup.
  - Use `**bold**` labels for sections in ordinary tickets; `##`/`###` headings only in long, document-like
    descriptions. `*italic*` and `-` bullets as needed.
  - Wiki markup renders **literally** — `h1. Title` shows up as the text "h1. Title", `{code}`/`{{mono}}`
    as braces. Same for `_italic_`-style leaders at line start.
  - Don't put `---` immediately above the attribution footer: the footer becomes a bullet. Leave a blank
    line and write the footer as a plain line.
  - Don't put inline code inside bold. In `**Label `x` text.**` the bold stops before the code span, and
    the rest of the label renders as plain text. Write the name without backticks in the label, or move it after.
  - Tables convert, but keep them small; long rows read badly in the Jira renderer. Prefer bullet lists.
  - After creating or editing, read the returned `description` back — it is the stored source, so literal
    `h1.` or a mangled footer is visible there immediately. Fix with `editJiraIssue` rather than leaving it.

## Voice

Write in Russ's voice per `writing-voice.md` (summary format, first person, hedging, comment habits). This file
sets the structure; where the two differ, this file wins.

Bugs and Stories are read by developers and by project managers. Write for both.

## Bug reports

Use these sections, in this order, as short bold labels. Leave out a section only when there is nothing to put in
it.

1. **Problem**: what is wrong and who or what it affects, in a sentence or two.
2. **Expected**: what should have happened.
3. **Actual**: what happened instead.
4. **Steps to reproduce**: numbered, when known. If they aren't known, say so rather than guessing.
5. **Logs**: the stack trace or error log, raw and unedited, in a code block. If it is long (more than about 30
   lines), put only the relevant contiguous excerpt inline. The MCP tools can't attach files, so save the full log
   under the project's `tmp/` and tell the user to attach it.

A suspected cause, with how sure you are, can go after **Actual** or at the end. Keep it separate from the facts.

## Other tickets

- Stories: the goal, then non-goals, then a link to the solution document.
- Internal Tasks: a sentence or two is often enough.
- Code names and file paths are fine inline, but open with a sentence someone outside engineering can follow. No
  separate "For developers:" layer is required.
- Add a "How to check the fix" note only when testing the fix isn't obvious from the steps to reproduce.
