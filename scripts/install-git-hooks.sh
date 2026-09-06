#!/bin/bash
# Ported-From: danwright32/downbeat scripts/install-git-hooks.sh @ 563865a7e8a93c678e6eed38c86281c8d9a730d0
#
# Points git at this repo's tracked hooks.
#
# Run once per clone:
#
#     scripts/install-git-hooks.sh
#
# It is idempotent, and it REFUSES rather than overwrites when git is already
# pointed somewhere else, since silently taking over another tool's hooks is how
# a gate you were relying on stops running without saying anything (L98).
#
# Ported unchanged in behaviour. Every constant re-checked: the hooks directory
# name, the .sample exclusion (git ships those in every clone, so refusing on
# them would refuse on every fresh clone, which is a guard firing on the normal
# case, L324), and the refusal messages.
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel) || exit 1
WANT="scripts/git-hooks"
CURRENT=$(git -C "$REPO_ROOT" config --local --get core.hooksPath 2>/dev/null)

if [ "$CURRENT" = "$WANT" ]; then
    echo "Already installed: core.hooksPath is $WANT"
    exit 0
fi

if [ -n "$CURRENT" ]; then
    echo "Not installing. core.hooksPath is already set to '$CURRENT'." >&2
    echo "Pointing it at $WANT would stop whatever lives there from running." >&2
    echo "Decide which you want, then set it by hand." >&2
    exit 1
fi

# A hook file already in .git/hooks would stop running too. `.sample` files are
# git's own and are not hooks.
EXISTING=$(ls "$REPO_ROOT/.git/hooks" 2>/dev/null | grep -v '\.sample$')
if [ -n "$EXISTING" ]; then
    echo "Not installing. .git/hooks already contains:" >&2
    echo "$EXISTING" >&2
    echo "Those stop running the moment core.hooksPath is set. Move them into" >&2
    echo "$WANT first, then run this again." >&2
    exit 1
fi

git -C "$REPO_ROOT" config --local core.hooksPath "$WANT"
echo "Installed: core.hooksPath is now $WANT"
echo "git push will run Ovation's suite first and refuse a red one."
