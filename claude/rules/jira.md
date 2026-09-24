# Jira

- Jira comment/ticket on user's behalf (`addCommentToJiraIssue`, `createJiraIssue`): end body/description with footer on own line:

  `— Posted by Claude Code on behalf of <full name>`

  (New tickets: "Created by" not "Posted by".) Get `<full name>` from `/usr/bin/id -F`; fall back to
  `git config user.name` if empty. Never guess or hard-code it.
- Applies even when user dictates content verbatim, unless user explicitly says omit the attribution.
- **Markup: pass `contentFormat: "markdown"` and write actual Markdown.** Cloud Jira instances are
  ADF-backed; the MCP tool converts Markdown, and never wiki markup.
  - Use `##`/`###` headings, `**bold**`, `*italic*`, `-` bullets.
  - Wiki markup renders **literally** — `h1. Title` shows up as the text "h1. Title", `{code}`/`{{mono}}`
    as braces. Same for `_italic_`-style leaders at line start.
  - Don't put `---` immediately above the attribution footer: the footer becomes a bullet. Leave a blank
    line and write the footer as a plain line.
  - Tables convert, but keep them small; long rows read badly in the Jira renderer. Prefer bullet lists.
  - After creating or editing, read the returned `description` back — it is the stored source, so literal
    `h1.` or a mangled footer is visible there immediately. Fix with `editJiraIssue` rather than leaving it.

## Writing for a mixed audience

Bugs and Stories are read by developers and by project managers. Write for both.

- Open with what the user sees and who is affected. Leave the code out of that opening.
- In each section, write the plain-English version first. Put code names, file paths and
  commit ids in a separate paragraph that starts with "For developers:".
- Say how sure you are. If the cause is a guess, name it as one, say what evidence would
  confirm it, and name the other suspect.
- Add a "How to check the fix" section a tester can follow without reading code.
- Put raw logs and stack traces last, in a code block, and don't edit them.
- Internal Tasks for engineering only can skip the plain-English layer.
