#!/usr/bin/env bash
# Read-only report of merged branches, worktrees and fork branches for one GitHub repository.
# Usage: report.sh [--no-fetch] [repo-dir]
# Needs git and an authenticated gh. Changes nothing except `git fetch --all --prune`.
set -u

FETCH=1
DIR=.
for arg in "$@"; do
  case "$arg" in
    --no-fetch) FETCH=0 ;;
    -*) echo "unknown option: $arg" >&2; exit 1 ;;
    *) DIR=$arg ;;
  esac
done
REPO=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repository: $DIR" >&2; exit 1; }
cd "$REPO" || exit 1

# Long-lived branches. Never offered for deletion.
PERMANENT='^(main|master|main-master|origin-master|main-development|develop|development|release/.*|sprint/.*)$'
# Ignored paths that are build output or IDE state, not someone's scratch work.
IGNORED_NOISE='^(build|out|bin|target|dist|logs|runtime-aspects|node_modules|\.gradle|\.kotlin|\.idea|\.vscode)/|/(build|node_modules|dist|\.gradle|\.kotlin)/$|\.(iml|ipr|iws|log|tsbuildinfo)$|\.DS_Store$|^\.claude/settings(\.local)?\.json(\.bak)?$'

TMP=$(mktemp -d "${TMPDIR:-/tmp}/cleanup-merged.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
lower() { tr '[:upper:]' '[:lower:]'; }

[ "$FETCH" = 1 ] && git fetch --all --prune --quiet 2>&1 | grep -v '^$' >&2

LOGIN=$(gh api user --jq .login) || { echo "gh is not authenticated" >&2; exit 1; }
LOGIN_LC=$(printf %s "$LOGIN" | lower)

# Map remotes to owner/repo.
git remote -v | awk '$3=="(fetch)"{print $1"\t"$2}' | while IFS=$'\t' read -r name url; do
  slug=$(printf %s "$url" | sed -E 's#^(git@|ssh://git@|https://)github\.com[:/]##; s#\.git$##')
  printf '%s\t%s\n' "$name" "$slug"
done > "$TMP/remotes"

FORK_REMOTE=$(awk -F'\t' -v l="$LOGIN_LC" 'tolower($2) ~ "^"l"/"{print $1; exit}' "$TMP/remotes")
if [ -n "$FORK_REMOTE" ]; then
  FORK_SLUG=$(awk -F'\t' -v r="$FORK_REMOTE" '$1==r{print $2}' "$TMP/remotes")
  UP_SLUG=$(gh repo view "$FORK_SLUG" --json parent --jq 'if .parent then .parent.owner.login + "/" + .parent.name else "" end')
  MODE=fork
  [ -z "$UP_SLUG" ] && { UP_SLUG=$FORK_SLUG; MODE=own; }
else
  MODE=shared
  UP_SLUG=$(awk -F'\t' '$1=="origin"{print $2}' "$TMP/remotes")
fi
UP_LC=$(printf %s "$UP_SLUG" | lower)
UP_REMOTE=$(awk -F'\t' -v s="$UP_LC" 'tolower($2)==s{print $1; exit}' "$TMP/remotes")
[ -z "$UP_REMOTE" ] && { echo "no remote points at $UP_SLUG" >&2; exit 1; }
# In shared mode the user's branches live on the shared remote itself.
[ "$MODE" = shared ] && FORK_REMOTE=$UP_REMOTE

# Bases: the upstream default branch plus whichever classic integration branches exist there.
DEFAULT=$(gh repo view "$UP_SLUG" --json defaultBranchRef --jq .defaultBranchRef.name)
: > "$TMP/bases"
for b in "$DEFAULT" development develop master main; do
  git rev-parse -q --verify "refs/remotes/$UP_REMOTE/$b" >/dev/null && ! grep -qx "$UP_REMOTE/$b" "$TMP/bases" && echo "$UP_REMOTE/$b" >> "$TMP/bases"
done
i=0
while read -r base; do
  git log --format=%s "$base" > "$TMP/subjects.$i"; i=$((i+1))
done < "$TMP/bases"

# The user's PRs on the upstream repo: number, head, state, base.
gh pr list --repo "$UP_SLUG" --author "@me" --state all --limit 1000 \
  --json number,headRefName,state,baseRefName \
  --jq '.[] | [.number, .headRefName, .state, .baseRefName] | @tsv' > "$TMP/prs"

pr_for() { # $1 = branch name; prints e.g. "#12 OPEN->development,#9 MERGED->master"
  awk -F'\t' -v b="$1" '$2==b{printf "%s#%s %s->%s", (n++?",":""), $1, $3, $4}' "$TMP/prs"
}

# Commits on $1 with no equivalent change in each base. Sets UNIQ ("base=n ..."), MIN_UNIQUE and SUBJ_FOUND.
uniq_vs_bases() {
  local ref=$1 out="" n min=999999 i=0 base
  SUBJ_FOUND=""
  while read -r base; do
    n=$(git cherry "$base" "$ref" 2>/dev/null | grep -c '^+')
    out="$out ${base#*/}=$n"
    [ "$n" -lt "$min" ] && min=$n
    i=$((i+1))
  done < "$TMP/bases"
  MIN_UNIQUE=$min
  # For branches that are not contained: how many of their unique commits have a same-subject commit in any base.
  if [ "$min" -gt 0 ]; then
    local total=0 found=0 subj
    while read -r subj; do
      total=$((total+1))
      if cat "$TMP"/subjects.* | grep -Fxq -- "$subj"; then found=$((found+1)); fi
    done < <(git cherry -v "$(head -1 "$TMP/bases")" "$ref" | sed -n 's/^+ [0-9a-f]* //p')
    SUBJ_FOUND="$found/$total"
  fi
  UNIQ=${out# }
}

echo "== CONTEXT"
printf 'login\t%s\nmode\t%s\nfork_remote\t%s\nupstream\t%s (remote %s)\nbases\t%s\n' \
  "$LOGIN" "$MODE" "$FORK_REMOTE" "$UP_SLUG" "$UP_REMOTE" "$(tr '\n' ' ' < "$TMP/bases")"

# Worktrees: path, branch (empty when detached), head, prunable. Fields are split on \x1f because
# bash `read` merges consecutive tabs, which shifts every field after an empty one.
US=$'\x1f'
git worktree list --porcelain | awk -v s="$US" '
  /^worktree /{if(p!="")print p s b s h s pr; p=substr($0,10); b=""; h=""; pr=""}
  /^HEAD /{h=$2} /^branch /{b=substr($2,12)} /^prunable/{pr="prunable"}
  END{if(p!="")print p s b s h s pr}' > "$TMP/worktrees"
MAIN_WT=$(head -1 "$TMP/worktrees" | cut -d"$US" -f1)

wt_state() { # $1 = path; prints "edits<TAB>ide_only<TAB>untracked<TAB>ignored_scratch"
  local p=$1 edits ide untr ign
  edits=$(git -C "$p" status --porcelain --untracked-files=no | grep -vc ' \.idea/')
  ide=$(git -C "$p" status --porcelain --untracked-files=no | grep -c ' \.idea/')
  untr=$(git -C "$p" status --porcelain --untracked-files=normal | grep -c '^??')
  ign=$(git -C "$p" status --porcelain --ignored=matching --untracked-files=normal | sed -n 's/^!! //p' \
    | grep -Ev "$IGNORED_NOISE" | head -12 | tr '\n' ' ')
  printf '%s\t%s\t%s\t%s' "$edits" "$ide" "$untr" "$ign"
}

# True when the branch was created in the last 3 days. A new branch with no commits yet looks merged.
is_fresh() {
  local created
  created=$(git reflog show --format=%ct "refs/heads/$1" -- 2>/dev/null | tail -1)
  [ -n "$created" ] && [ $(( $(date +%s) - created )) -lt 259200 ]
}

echo
echo "== WORKTREES"
printf 'verdict\tpath\tbranch\tedits\tide_only\tuntracked\tignored_scratch\n'
: > "$TMP/wt_verdicts"
tail -n +2 "$TMP/worktrees" | while IFS="$US" read -r path branch head prunable; do
  if [ -n "$prunable" ]; then
    printf 'DELETE prunable\t%s\t%s\t-\t-\t-\t-\n' "$path" "$branch"
    printf '%s\tDELETE prunable\n' "$branch" >> "$TMP/wt_verdicts"; continue
  fi
  st=$(wt_state "$path")
  edits=$(cut -f1 <<<"$st"); untr=$(cut -f3 <<<"$st")
  ref=${branch:-$head}
  pr=""; [ -n "$branch" ] && pr=$(pr_for "$branch")
  uniq_vs_bases "$ref"
  if [ -n "$branch" ] && printf %s "$branch" | grep -Eq "$PERMANENT"; then v="KEEP permanent"
  elif printf %s "$pr" | grep -q OPEN; then v="KEEP open-pr"
  elif [ "$edits" -gt 0 ] || [ "$untr" -gt 0 ]; then v="REVIEW uncommitted"
  elif [ "$MIN_UNIQUE" -eq 0 ] && [ -n "$branch" ] && [ -z "$pr" ] && is_fresh "$branch"; then v="REVIEW new-branch"
  elif [ "$MIN_UNIQUE" -eq 0 ]; then v="DELETE merged"
  elif printf %s "$pr" | grep -q MERGED; then v="REVIEW amended"
  else v="KEEP unmerged-work"; fi
  printf '%s\t%s\t%s\t%s\n' "$v" "$path" "${branch:-(detached $head)}" "$st"
  [ -n "$branch" ] && printf '%s\t%s\n' "$branch" "$v" >> "$TMP/wt_verdicts"
done

echo
echo "== ORPHAN WORKTREE DIRS (not registered with git)"
for d in "$REPO"/.claude/worktrees/*/; do
  [ -d "$d" ] || continue
  d=${d%/}
  cut -d"$US" -f1 "$TMP/worktrees" | grep -Fxq "$d" || printf '%s\t%s\n' "$d" "$(du -sh "$d" | cut -f1)"
done

echo
echo "== LOCAL BRANCHES"
printf 'verdict\tbranch\tworktree\tunique_vs_base\tsubjects_in_base\tupstream\tprs\tlast_commit\n'
git for-each-ref --format="%(refname:short)$US%(upstream:short)%(upstream:track)$US%(committerdate:short)" refs/heads/ |
while IFS="$US" read -r b up last; do
  wt=$(awk -F"$US" -v b="$b" '$2==b{print $1}' "$TMP/worktrees")
  wtv=$(awk -F'\t' -v b="$b" '$1==b{print $2}' "$TMP/wt_verdicts")
  pr=$(pr_for "$b")
  uniq_vs_bases "$b"; u=$UNIQ
  if printf %s "$b" | grep -Eq "$PERMANENT"; then v="KEEP permanent"
  elif [ -n "$wt" ] && [ "$wt" = "$MAIN_WT" ]; then v="KEEP checked-out"
  elif printf %s "$pr" | grep -q OPEN; then v="KEEP open-pr"
  # A branch goes no further than its worktree's verdict: it cannot be deleted while checked out.
  elif [ -n "$wtv" ] && [ "${wtv%% *}" != DELETE ]; then v="${wtv%% *} in-worktree"
  elif [ "$MIN_UNIQUE" -eq 0 ] && [ -z "$pr" ] && is_fresh "$b"; then v="REVIEW new-branch"
  elif [ "$MIN_UNIQUE" -eq 0 ]; then v="DELETE merged"
  elif printf %s "$pr" | grep -q MERGED; then v="REVIEW amended"
  else v="KEEP unmerged-work"; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$v" "$b" "${wt:--}" "$u" "${SUBJ_FOUND:--}" "${up:--}" "${pr:--}" "$last"
done

echo
echo "== REMOTE BRANCHES ON $FORK_REMOTE ($MODE)"
printf 'verdict\tbranch\tunique_vs_base\tsubjects_in_base\tprs\n'
git for-each-ref --format='%(refname:short)' "refs/remotes/$FORK_REMOTE/" | sed "s#^$FORK_REMOTE/##" | grep -vx -e HEAD -e "$FORK_REMOTE" |
while read -r b; do
  pr=$(pr_for "$b")
  # On a shared remote, only branches the user opened a PR from are theirs to delete.
  if [ "$MODE" = shared ] && [ -z "$pr" ]; then continue; fi
  uniq_vs_bases "$FORK_REMOTE/$b"; u=$UNIQ
  if printf %s "$b" | grep -Eq "$PERMANENT"; then v="KEEP permanent"
  elif printf %s "$pr" | grep -q OPEN; then v="KEEP open-pr"
  elif [ "$MIN_UNIQUE" -eq 0 ]; then v="DELETE merged"
  elif printf %s "$pr" | grep -q MERGED; then v="REVIEW amended"
  else v="KEEP unmerged-work"; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$v" "$b" "$u" "${SUBJ_FOUND:--}" "${pr:--}"
done
