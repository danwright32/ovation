#!/bin/bash
# Refuse a machine whose git runs another checkout's copy of this repository's hooks.
#
# ovation#430. `core.hooksPath` held an ABSOLUTE path into the primary checkout
# (measured 2026-09-19), so every worktree ran the primary checkout's pre-push
# against its own tree, and a push based on origin/main was refused over a script
# that existed only on the branch the primary checkout was standing on. The gate
# was reading one branch's hook and another branch's tree.
#
# `scripts/install-git-hooks.sh` already rewrites that form to the relative one
# (ovation#138). Configuration installed into git is a COPY, though, so changing
# the installer changed nothing on a machine that had run the older one, and
# nothing asked (L423). This asks, and names the installer as the remedy.
#
# WHAT IT REFUSES, stated so it can be argued with: an absolute hooks path into
# ANY checkout of this repository, the primary or a worktree, judged by the git
# directory that checkout shares rather than by comparing it with this one's own
# folder. From a worktree the stale path names the primary's hooks, which is a
# different folder from the worktree's, so a folder comparison passes on exactly
# the case this exists for (L70).
#
# WHAT IT LEAVES ALONE: an unset path, which is every fresh clone and every CI
# runner, and a path pointing at another tool's hooks, which the installer itself
# refuses to take over. Neither is this check's to refuse (L324).
#
# Exit codes: 0 nothing to refuse, 1 refused.
set -uo pipefail

CURRENT="$(git config --get core.hooksPath 2>/dev/null)"
WANT="scripts/git-hooks"

if [ -z "$CURRENT" ]; then
    echo "OK: the hooks are not installed here (core.hooksPath is unset), so there is nothing to judge."
    exit 0
fi
if [ "$CURRENT" = "$WANT" ]; then
    echo "OK: core.hooksPath is $WANT, so each checkout runs its own hooks."
    exit 0
fi
case "$CURRENT" in
    /*) ;;
    *)
        echo "OK: core.hooksPath is '$CURRENT', a relative path this check does not own."
        exit 0
        ;;
esac

# Which repository does that folder belong to? Asked of git, from the folder two
# levels up (the checkout the hooks folder sits in), and compared by the git
# directory every checkout of one repository shares.
OURS="$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)"
THEIRS="$(cd "$CURRENT/../.." 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)"
TAIL="${CURRENT%/}"; TAIL="${TAIL##*/scripts/}"

if [ -n "$THEIRS" ] && [ "$THEIRS" = "$OURS" ] && [ "$TAIL" = "git-hooks" ]; then
    echo "REFUSED: core.hooksPath is an absolute path into a checkout of this repository:"
    echo "    $CURRENT"
    echo "    So a push from any other checkout, a worktree included, runs THAT checkout's"
    echo "    copy of the hooks against its own tree, and the gate judges one branch by"
    echo "    another branch's rules."
    echo "    Fix it once, from any checkout: bash scripts/install-git-hooks.sh"
    exit 1
fi

echo "OK: core.hooksPath points at '$CURRENT', which is not this repository's hooks, so it is left alone."
exit 0
