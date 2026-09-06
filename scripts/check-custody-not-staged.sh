#!/usr/bin/env bash
# Refuse if custody data has ever entered git history, or is staged now.
#
# ovation#4. The repository is PUBLIC for the whole build (Dan's decision,
# 2026-09-05, on Actions minutes), so this is the only thing standing between a
# real receipt or a real QuickBooks export and a public URL.
#
# THIS IS A DIFFERENT QUESTION FROM THE IDENTITY GUARD (ovation#5). That one
# searches file CONTENTS for names that should not be there. This one asks
# whether a custody FILE ever entered history at all, and .gitignore cannot
# answer it: an ignore entry added AFTER a file was committed hides it from
# `git status` while leaving it in every clone for ever. Deleting the file later
# does not help either. One of the cases in the suite is exactly that shape, and
# `git status` reports nothing at all for it.
#
# It reads --all, not HEAD, because a file on a branch nobody merged is still in
# the history anyone who clones receives.
#
# NOTHING TO CHECK IS NOT A PASS. Handed an empty path list it refuses naming the
# emptiness, rather than reporting clean while examining nothing (L98). Same trap
# as an identity guard with no needles.
set -uo pipefail

# The custody directories. Machine local, never in the repository, and named here
# rather than discovered, because a guard that discovers what to protect can only
# protect what happens to exist right now.
# `${VAR-default}` WITHOUT the colon, deliberately. `${VAR:-default}`
# substitutes the default when the variable is set but EMPTY, so an explicitly
# empty path list would silently become the full default and this guard would
# report clean while claiming to have examined nothing. An interpolating layer
# rendering a missing setting as empty rather than absent is exactly the shape
# that makes an absence check written as a fallback accept it (L138).
PATHS="${OVATION_CUSTODY_PATHS-.receipt-samples .quickbooks-samples}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "CANNOT MEASURE: this is not a git repository, so history could not be read."
  echo "    Nothing was verified. This is not a pass."
  exit 2
fi

# shellcheck disable=SC2206
PATH_LIST=($PATHS)
if [ "${#PATH_LIST[@]}" -eq 0 ]; then
  echo "REFUSED: no custody paths were given, so nothing was examined."
  echo "    A check that looks at nothing and reports clean is worse than no check."
  exit 3
fi

echo "Checking custody paths: ${PATH_LIST[*]}"

found=0

for p in "${PATH_LIST[@]}"; do
  # 1. Staged right now. Still fixable with `git restore --staged`.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "STAGED: $f"
    echo "    A custody file is staged in the index. It is not committed yet."
    echo "    Remove it with: git restore --staged \"$f\""
    found=$((found+1))
  done < <(git diff --cached --name-only -- "$p" 2>/dev/null)

  # 2. Ever ADDED anywhere in history, on any branch. This is the one .gitignore
  #    and `git status` are both blind to.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "IN HISTORY: $f"
    echo "    A custody file was committed at some point and is in this repository's"
    echo "    history. Deleting it does not remove it: every clone still has it."
    found=$((found+1))
  done < <(git log --all --pretty=format: --diff-filter=A --name-only -- "$p" 2>/dev/null | sort -u)
done

echo
if [ "$found" -gt 0 ]; then
  echo "REFUSED: $found custody path(s) reached git."
  echo "    This repository is public. Treat anything already in history as disclosed:"
  echo "    rewriting history does not un-publish what has been fetched."
  exit 1
fi

echo "No custody data is staged or in history."
exit 0
