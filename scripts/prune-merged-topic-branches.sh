#!/usr/bin/env bash

# Script to delete merged topic branches: story, task, bug, etc.

# [Semi]Permanent Branches plus current branch
PERMANENT_BRANCHES='main.*|master.*|release.*|develop.*|sprint.*|[*] .*'

function mergedBranches() {
  git branch --merged | grep -Ev "$PERMANENT_BRANCHES"
}

echo "Finding merged branches to prune..."

TO_PRUNE="$(mergedBranches | sed 's/^\s*//' | xargs)"
if [ -z "$TO_PRUNE" ]; then
  echo
  echo "There are no branches to prune. Have a great day!"
  exit
else
  echo
  echo "Branches to prune: "
  echo "$TO_PRUNE" | fmt | xargs -Iline printf "\t%s\n" line
  echo
fi

declare -i interactive=0
read -p "Are you sure? [yni] (yes, no, interactive) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[YyIi]$ ]]; then
  exit 1
elif [[ $REPLY =~ ^[Ii]$ ]]; then
  interactive=1
fi
echo
echo "NOTE: you may get an error if an upstream branch doesn't exist and we try to delete it. That's okay."
echo
sleep 1
for branch in $(mergedBranches); do
  echo
  # Find upstream - FIXME : find out if remote exists and just skip upstream delete if it doesn't
  ref="$(git rev-parse --symbolic-full-name "$branch")"
  upstream="$(git for-each-ref --format='%(upstream:short)' "$ref" | sed -E 's/(^[^/]+)[/](.*)/\1/' 2>/dev/null)"
  # echo "upstream -->> $upstream $?"
  uprompt=""
  if [ -n "$upstream" ]; then
    uprompt=" (upstream: $upstream)"
  fi

  if [ $interactive -eq 1 ]; then
    shopt -s nocasematch
    if [[ "${branch}" =~ .*[/]([a-z]{2,9}-[0-9]+) ]]; then
      ticket="${BASH_REMATCH[1]}"
      echo "Ticket => https://proteusco.atlassian.net/browse/${ticket}"
    fi
    read -p "Prune branch: ${branch}${uprompt}? [yn] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Pruning branch: $branch and upstream remote: $upstream"
      git branch -d "$branch"
      if [ -n "$upstream" ]; then
        git push "$upstream" --delete "$branch"
      fi
    else
      echo "NOT pruning branch: $branch"
    fi
  else
    echo "Pruning branch: $branch"
    git branch -d "$branch"
    if [ -n "$upstream" ]; then
      git push "$upstream" --delete "$branch"
    fi
  fi
done

echo
echo "All done! Happying versioning!"
