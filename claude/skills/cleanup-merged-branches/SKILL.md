---
name: cleanup-merged-branches
description: Remove merged worktrees, local branches and your fork's branches. Keeps open PRs, permanent branches and unmerged work, and asks before deleting anything.
disable-model-invocation: true
---

# Clean up merged branches and worktrees

Nothing is deleted until the user has seen the lists and said yes.

## 1. Report

Run `scripts/report.sh` from this skill's directory. It takes the repository path (default: the current directory) and an
optional `--no-fetch`, in either order. It is read-only apart from `git fetch --all --prune`. Pipe it through
`column -t -s $'\t'` to read it. If `column` fails with "line too long", trim long fields with awk instead.

It works out:

- **Fork, own or shared.** The fork remote is the one owned by the `gh` login. Its parent repository is the upstream; a repo with no parent is `own`. With no fork,
  the shared remote is used, and only branches the user opened a PR from are listed.
- **Bases.** The upstream default branch, plus whichever of `development`, `develop`, `master` and `main` exist upstream. A branch
  counts as merged when it has no change missing from *any* base. A hotfix merged only into master counts.
- **Equivalent changes, not hashes.** It uses `git cherry`, so a branch that was rebased and then merged still counts as merged.
- **The user's PRs** (`gh pr list --author @me --state all`), matched by head branch name.

## 2. Verdicts

| Verdict | Meaning | Action |
| --- | --- | --- |
| `KEEP permanent` | Matches the permanent pattern. | Never offer it. |
| `KEEP open-pr` | Has an open PR. | Never offer it. |
| `KEEP checked-out` | Checked out in the main working tree. | Never offer it. |
| `KEEP unmerged-work` | Has commits that are in no base and no merged PR. | Never offer it. |
| `KEEP/REVIEW in-worktree` | The branch inherits its worktree's verdict. | Decide with the worktree. |
| `DELETE merged` | Nothing on it is missing from a base. | Offer it. |
| `DELETE prunable` | Git already lost this worktree's folder. | `git worktree prune` covers it. |
| `REVIEW uncommitted` | The worktree has real edits or untracked files. | Show `git -C <path> status --short`. Ask. |
| `REVIEW new-branch` | No commits yet, created in the last 3 days. | Probably about to be used. Ask. |
| `REVIEW amended` | The PR merged, but the commits differ from what landed. | Check it as described below. |

Edits only to `.idea/` files are counted in `ide_only` and do not block removal. IDEs write those on their own.

**Checking `REVIEW amended`.** `subjects_in_base` says how many of the branch's own commits have a commit with the same subject
in a base. For each one, find the commit that landed (`git log <base> --format='%h %s' | grep -F "<subject>"`) and compare:
`git range-diff <landed>^! <local>^!`. If the only differences are context lines that changed because of a rebase, the branch is
safe to delete. Say so. Otherwise, show the user what differs and treat it as their call. A branch named `backup/pre-rebase-*`
is expected to differ a little.

**ignored_scratch** lists ignored files that aren't build output, such as `tmp/` drafts. Removing a worktree deletes them. Name
them so the user can save anything they want first.

**Orphan worktree dirs** are folders under `.claude/worktrees/` that git doesn't know about. Look inside (`ls -la`, `du -sh`)
before suggesting `rm -rf`. Don't run `git -C` there: it finds the parent repository and reports that one's state.

## 3. Present

Show grouped lists with counts, so the user can cross-check:

1. Keep: open PRs, with their worktrees.
2. Worktrees to remove.
3. Local branches to remove. Split them into branches checked out in those worktrees and branches with no worktree.
4. Remote branches to remove, naming the remote and its owner.
5. Your call: every REVIEW item, and anything else that is merged but looks deliberate, such as `epic/*`.
6. Left alone: permanent branches, on both the local side and the remote.

Watch for names that look alike. A branch named like a worktree folder is often not the branch checked out in it.

If the bases have diverged (`git rev-list --count <up>/development..<up>/master` is above 0), say so in one line. Master needs
merging back into development. Deleting branches loses nothing either way.

## 4. Remove (only after a yes)

Other sessions may have created worktrees or commits since the report, and branches may have been deleted on the remote.
Re-run `scripts/report.sh` first, with the fetch, and drop anything whose verdict changed or that has disappeared. Then
run the commands directly, in this order:

```bash
git worktree remove <path>            # add --force only when the edits are ide_only
git worktree prune
git branch -D <branch> ...            # -D: some branches merged under another hash, or only into master
git push <fork-remote> --delete <branch> ...
```

A branch can't be deleted while a worktree has it checked out, so worktrees go first. Leave out anything the user didn't
approve, including REVIEW items they didn't answer.

Finish by listing what is left: worktrees, local branches, and branches on the remote.
