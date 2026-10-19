# Writing voice: commits, PRs and Jira

Write commit messages, PR descriptions, and Jira tickets and comments the way Russ does. This covers voice only.
It does not change `doc-comments.md`, which keeps doc comments imperative. Structure comes from elsewhere:

- Commits: the project's CLAUDE.md. Without one: subject ≤50 chars, blank line, body wrapped at 72, blank line,
  ticket(s).
- Jira: `jira.md` (mixed-audience layout, markup, attribution footer). Where it sets a structure, it wins.

Style source: Russ's commits, PRs and Jira tickets from 2025 and earlier, plus his solution documents. Text from
2026 on is Claude-assisted. Never mine it for style.

## Voice (everywhere)

- First person. "I" for what Russ did, checked or could not find ("I reviewed existing CloudFront distributions.",
  "I couldn't find a reason for this in the git history."). "We" for the codebase and team ("We don't need to
  include the versionId on the live site.").
- Spend the words on **why**, what was verified, and consequences: upgrade risk, API breaks, downstream apps,
  what to do if a migration fails. Skip anything the diff or the log already says.
- Say how sure you are, plainly: "should", "likely", "This may be related to…", "I think this is caused by…",
  "It appears that…". Name the other suspect when there is one. No false confidence.
- A concrete example (HTML, JSON, Gradle snippet, SQL, a log line, a screenshot with a one-line caption) beats a
  description of one.
- Own mistakes and changes of mind directly: "Thanks for catching this. When I added the validation, I did not
  trim whitespace…", "I changed my mind."
- Many good messages are one or two sentences. Don't pad.

## Commits

- Subject: short, verb first, naming the concrete thing. Past tense is the house sound ("Added", "Fixed",
  "Updated", "Removed", "Made"); imperative is also fine. "Don't …" / "Do not …" for behaviour that was stopped.
- Body: plain prose paragraphs. Secondary changes get their own short paragraph opening with "Also," or
  "Additionally,". "Misc other updates from testing." is fine as a catch-all.
- A short list of reasons may be numbered `1)` `2)`. Otherwise no bullets. Never headers.
- Reviewer feedback that drove a change can be quoted with attribution.
- Tickets last, bare, one per line: `PF-2401`. Stack several; other projects' keys (`ENGAGE-6686`) are fine.

## PR descriptions

- Short. Usually the commit body, or just the ticket. No `## Summary` / `## Changes` / `## Test plan` template, no
  bullet inventory of files touched. Fenced code blocks are fine for examples.
- A coordination note after the ticket is normal: rollout timing, snapshot plans, which downstream app Russ will fix,
  a direct question to a reviewer. Include one only when the facts are known. Never invent it.
- **Never hard-wrap a PR description, review comment or issue comment.** GitHub renders every newline as a line break,
  so a body wrapped at 72 or 120 columns shows as ragged fragments. One paragraph per line, blank line between
  paragraphs. Only commit messages wrap (at 72). Keep a draft file for review unwrapped too, so what Russ reads is
  what gets posted.

## Jira

- Summary: `Area / Sub-area / Problem or change`, most general first. "Checklist / Custom Field / Add Number
  Field", "Files / New Folder Dialog / Should focus text input", "CountryInformation / getISO2CountryCode / Empty
  string for code returns AD". Bugs name the observed behaviour.
- Description: bugs follow the section layout in `jira.md`. Otherwise say what is wanted, why, and what should
  happen next.
- Lists that are really lists (use cases, definition of done, permission options, pending steps) are bullets. Short
  tickets use a bold label (`**Use Cases**`, `**DOD**`) rather than a heading.
- Decisions are stated as decisions: "We will allow integers or decimals." Open questions are flagged as open: "When
  implementing we need to know if…".
- Comments are conversational and addressed: @mention the person, answer their point, then say what happens next.
  - Test report: what was tested, where, and why there ("I tested this on the Test install with a 4GB, 3GB, 2GB
    and 1GB file. The reason for testing on Test is…").
  - Resolution: what fixed it, where it stops working, and when to reopen ("Since current large files appear to be
    less than 5GiB, I consider this resolved. We can open a new ticket if we need larger files.").
  - "Working as designed": give the reason and the alternative ("I wouldn't consider this a bug because… If we
    wanted this, we should prompt the user.").
  - Revised plans: strike through the dropped item and add a bold `**edit**:` note rather than deleting it.

## Never

- "This commit/PR/ticket introduces…", third-person narration of the change, "enhance", "streamline",
  "comprehensive", "robust", "seamless", "ensure" as filler, "various improvements".
- Em-dashes. Split into two sentences.
- Closing summaries, sign-offs, or decorative emoji. (The `jira.md` attribution footer is required, not a sign-off.)

## Examples (Russ, verbatim apart from typo fixes)

Commit:

```
Do not include s3 versionId on live site

We don't need to include the S3 versionId on the live site for the
existing file storage implementation and we cannot include it on the new
private S3 file storage implementation (live site). This should also
silence "misguided" security scanning software that reports our URLs
with the versionId parameter in the URL.

I reviewed existing CloudFront distributions. The old code had the
cache policy to include all query parameters, so the substitute of
pfvId for versionId on the live site should have the same cache
busting effect when modifying a file and then regenerating the URL as
including the versionId in the URL on the live site.

PF-2401
```

```
Do not change case and remove underscores in labels

I couldn't find a reason why this was originally done in the git
history.

Since this changes the index to be case insensitive like the label
lookup inside the DAO it is possible that the new index may fail to be
created. If that happens, the data conversion can be injected leaving
the old index in-place with the possibility of manually getting the new
index created later if desired.
```

```
Don't create the editor inside the constructor.

2 reasons not to do this.
1) first instance created is stored for the lifetime of the application
which could cause a resource leak.
2) no reason to do something expensive in order to get the
MIWTContentModel information.
```

PR body:

```
Do not invalidate if we are updating state to reflect changes made in the UI. We do not want to re-render in that case.

PF-2792

I've only done this for ListComponent and TagListComponent to start with.
```

Jira bug (REVIEWR-7158, "Intellij IDEA / Duplicated Classpath"):

```
PF is duplicated in classpath.

[screenshot]

I think this is caused by the morpheus dependency. It may be a bug in how IntelliJ handles having a snapshot
version and a release version for the same version. Maybe it requires further configuration in that scenario.
```

Jira comment (ENGAGE-9316):

```
This was an intentional decision. We only set the metadata on initial import. If it is an existing record, we do
not update the information as it may affect multiple workspaces. We do update the contact labels since those are
workspace specific.

I wouldn't consider this a bug because to do what is described in the ticket without prompting would be surprising
to the user. So, I think if we wanted to do this then we should prompt the user.
```
