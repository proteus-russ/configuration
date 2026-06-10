# Jira

- When adding a Jira comment or creating a Jira ticket on the user's behalf (e.g. `addCommentToJiraIssue`, `createJiraIssue`), end the comment body or ticket description with a footer line on its own line:

  `— Posted by Claude Code on behalf of Russ Tennant`

  (For new tickets, use "Created by" instead of "Posted by".)
- This applies even when the user dictates the content verbatim, unless they explicitly say to omit the attribution.
