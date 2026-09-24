#!/bin/bash
# The check that git runs THIS checkout's hooks, and that it can fail.
#
# ovation#430. `core.hooksPath` held an ABSOLUTE path into the primary checkout,
# so every worktree ran the primary checkout's pre-push against its own tree: a
# push based on origin/main was refused over a script that existed only on the
# branch the primary checkout happened to be on. The installer already upgrades
# that form, and nothing asked a machine whether it still carried it (L423).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "hooks path tests" 10

TARGET="scripts/check-hooks-path.sh"
require_target "$TARGET"
harness_temp_dir WORK
ROOT="$PWD"

# A throwaway repository shaped like this one: tracked hooks under scripts/git-hooks.
new_repo() {
    # Guarded against an empty WORK before any rm, the way stage_tree in
    # scripts/test-git-hooks.sh is: a recursive delete built from a variable is not
    # the place to rely on the harness having made it (L5).
    [ -n "$WORK" ] || exit 1
    local r="$WORK/$1"; rm -rf "$r"; mkdir -p "$r/scripts/git-hooks"
    ( cd "$r" && git init -q -b main && git config user.email t@t && git config user.name t \
      && printf '#!/bin/sh\n' > scripts/git-hooks/pre-push && git add . && git commit -qm init ) >/dev/null 2>&1
    printf '%s\n' "$r"
}
run_check() { ( cd "$1" && bash "$ROOT/$TARGET" 2>&1 ); }
says() { if grep -qi -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# 1. The relative form: passes.
R1="$(new_repo relative)"
git -C "$R1" config core.hooksPath scripts/git-hooks
OUT="$(run_check "$R1")"; ST=$?
check "the relative form passes" "$ST" "0"

# 2. THE MEASURED FAULT: an absolute path to this repository's own hooks.
R2="$(new_repo absolute)"
git -C "$R2" config core.hooksPath "$R2/scripts/git-hooks"
OUT="$(run_check "$R2")"; ST=$?
check "an absolute path to this repository's own hooks is refused" "$ST" "1"
check "and the refusal names the remedy" "$(says "$OUT" "install-git-hooks.sh")" "yes"

# 3. FROM A WORKTREE, which is where it bit: the absolute path names the PRIMARY
#    checkout's hooks, a different directory from the worktree's own, and it is
#    still this repository's, so it is still refused. A comparison against the
#    worktree's own directory would pass here, on exactly the case that matters.
git -C "$R2" worktree add -q "$WORK/absolute-wt" -b other >/dev/null 2>&1
OUT="$(run_check "$WORK/absolute-wt")"; ST=$?
check "from a worktree, an absolute path into the primary checkout is refused" "$ST" "1"

# 4. SEEN TO RECOVER: the installer's upgrade clears it.
( cd "$R2" && bash "$ROOT/scripts/install-git-hooks.sh" ) >/dev/null 2>&1
OUT="$(run_check "$R2")"; ST=$?
check "after the installer runs, the same repository passes" "$ST" "0"
check "and git now holds the relative form" "$(git -C "$R2" config --get core.hooksPath)" "scripts/git-hooks"

# 5. UNSET, which is every fresh clone and every CI runner: not this check's
#    business, so it passes and says so rather than failing every runner (L324).
R5="$(new_repo unset)"
OUT="$(run_check "$R5")"; ST=$?
check "an unset hooks path passes" "$ST" "0"
check "and says the hooks are not installed here" "$(says "$OUT" "not installed")" "yes"

# 6. POINTED DELIBERATELY ELSEWHERE, which the installer refuses to take over:
#    also not this check's to refuse.
R6="$(new_repo elsewhere)"; mkdir -p "$WORK/other-tool-hooks"
git -C "$R6" config core.hooksPath "$WORK/other-tool-hooks"
OUT="$(run_check "$R6")"; ST=$?
check "a hooks path pointing at another tool's hooks passes" "$ST" "0"
check "and says where it points" "$(says "$OUT" "other-tool-hooks")" "yes"

harness_end
