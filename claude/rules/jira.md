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
