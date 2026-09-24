#!/bin/bash
# Every branch beside the state of the pull request it was the head of. Deletes nothing.
#
# ovation#359 and ovation#396. Merged branches pile up locally and on GitHub:
# `gh pr merge --delete-branch` cannot delete a branch a worktree has checked out,
# and then leaves the remote one too. And because this repository SQUASH merges,
# no merged branch is ever an ancestor of main, so every local way of asking
# whether a branch shipped answers no (L642). The only truthful answer is the pull
# request, which is what this prints beside each branch.
#
# IT DELETES NOTHING, on purpose. A checkout can be shared by concurrent sessions,
# and deleting a branch another session stands on destroys its work; the listing
# makes clearing one a decision, and the decision stays with a person.
#
# ORIGIN IS ASKED, NOT REMEMBERED. The remote tracking refs keep a branch deleted
# on GitHub until a fetch with --prune, so the first run of this listed two
# branches deleted that same day as still on origin: a local copy is named after
# what it mirrors, and reading it answered about the past (L454). Where origin
# cannot be reached the tracking refs are used, and the report says so.
set -uo pipefail

GH="${OVATION_GH:-gh}"

if remote_heads="$(git ls-remote --heads origin 2>/dev/null)"; then
    on_origin="$(sed -E 's|.*refs/heads/||' <<< "$remote_heads")"
    origin_source="origin, asked just now"
else
    on_origin="$(git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin 2>/dev/null)"
    origin_source="this checkout's last fetch, because origin could not be reached"
fi

names="$( { printf '%s\n' "$on_origin"
            git for-each-ref --format='%(refname:lstrip=2)' refs/heads 2>/dev/null; } \
          | grep -vxE 'HEAD|main' | grep -v '^$' | sort -u )"

if [ -z "$names" ]; then
    echo "No branch but main, locally or on origin: nothing to report."
    exit 0
fi

merged=0
count=0
printf '%-44s %-8s %-8s %s\n' "branch" "local" "origin" "pull request"
while IFS= read -r b; do
    [ -n "$b" ] || continue
    count=$((count + 1))
    here="no"; git show-ref --verify --quiet "refs/heads/$b" && here="yes"
    there="no"; grep -qxF -- "$b" <<< "$on_origin" && there="yes"
    state="$("$GH" pr list --head "$b" --state all --json state --jq '.[0].state // empty' 2>/dev/null || true)"
    [ -n "$state" ] || state="no pull request"
    [ "$state" = "MERGED" ] && merged=$((merged + 1))
    printf '  %-42s %-8s %-8s %s\n' "$b" "$here" "$there" "$state"
done <<< "$names"

echo
echo "${count} branch(es) besides main; ${merged} belong to a merged pull request."
echo "The origin column is from ${origin_source}."
echo "nothing was deleted. A MERGED one is safe to clear once no worktree stands on it:"
echo "    git worktree list                                   (who is standing where)"
echo "    gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>   (on GitHub)"
