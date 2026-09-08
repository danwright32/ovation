#!/bin/bash
# The hook installer must refuse rather than take over hooks that already exist,
# and the pre-push hook must refuse a red suite.
#
# ovation#11. Until these land, this repository has no gate of its own at all:
# a push from Dan's terminal, from Xcode's source control panel or from any git
# client runs nothing. Whatever the plan says about the style gate and the test
# gate does not apply here until this does.
#
# THE ENV UNSET BELOW IS THE POINT OF THIS SUITE, and it is carried from the
# source as BEHAVIOUR rather than as a value (L501). Downbeat's harness runs
# `env -u SKIP_TEST_RUN -u FORCE_TEST_RUN -u SKIP_STYLE_CHECK -u SKIP_TEST_CHECK`
# before invoking the hook. Without it, under SKIP_TEST_RUN=1 its harness went
# from 36 passed and 0 failed to 15 passed with 21 failed, because the documented
# one push escape hatch was silently switching off twenty one of the checks
# policing the very gate it escapes, at the exact moment somebody had already
# decided to push past a refusal (downbeat#433, L259).
#
# So: every invocation here goes through hook(), which strips those first. A
# constants table would not have carried this across.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "git hooks tests" 27

INSTALLER="scripts/install-git-hooks.sh"
HOOK="scripts/git-hooks/pre-push"
require_target "$INSTALLER"
require_target "$HOOK"
harness_temp_dir WORK

REPO_ROOT="$PWD"

# Invoke the hook with every documented escape hatch STRIPPED, so a suite run
# from a shell that has one set cannot silently switch off what it is measuring.
hook() {
    env -u SKIP_TEST_RUN -u FORCE_TEST_RUN -u SKIP_STYLE_CHECK -u SKIP_TEST_CHECK \
        OVATION_HOOK_TEST_COMMAND="$1" "$REPO_ROOT/$HOOK" 2>&1
}

fresh_repo() {
    local r="$WORK/$1"; rm -rf "$r"; mkdir -p "$r"
    ( cd "$r" && git init -q -b main && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
    mkdir -p "$r/scripts/git-hooks"
    cp "$REPO_ROOT/$INSTALLER" "$r/scripts/"
    printf '%s\n' "$r"
}

# 1. A fresh clone: it points git at the tracked hooks.
R1="$(fresh_repo one)"
OUT1="$( cd "$R1" && bash scripts/install-git-hooks.sh 2>&1 )"; ST1=$?
check "a fresh clone installs cleanly" "$ST1" "0"
check "and git is actually pointed at the tracked hooks" \
    "$( cd "$R1" && git config --local --get core.hooksPath )" "scripts/git-hooks"

# 2. Idempotent. Running it twice is a normal thing to do and must not be an
#    error, or people stop running it.
OUT2="$( cd "$R1" && bash scripts/install-git-hooks.sh 2>&1 )"; ST2=$?
check "running it again is not an error" "$ST2" "0"
check "and it says it was already installed" \
    "$(printf '%s' "$OUT2" | grep -ci "already installed")" "1"

# 3. POINTED SOMEWHERE ELSE: refuse. Silently taking over another tool's hooks
#    is how a gate somebody was relying on stops running without saying anything.
R3="$(fresh_repo three)"
( cd "$R3" && git config --local core.hooksPath "some/other/place" )
OUT3="$( cd "$R3" && bash scripts/install-git-hooks.sh 2>&1 )"; ST3=$?
check "an existing hooksPath is not taken over" \
    "$([ "$ST3" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names where git is currently pointed" \
    "$(printf '%s' "$OUT3" | grep -c "some/other/place")" "1"
check "and it did NOT change the setting" \
    "$( cd "$R3" && git config --local --get core.hooksPath )" "some/other/place"

# 4. A REAL HOOK ALREADY IN .git/hooks: refuse and name it. Those stop running
#    the moment core.hooksPath is set, which is a gate silently disappearing.
R4="$(fresh_repo four)"
printf '#!/bin/bash\nexit 0\n' > "$R4/.git/hooks/pre-commit"
chmod +x "$R4/.git/hooks/pre-commit"
OUT4="$( cd "$R4" && bash scripts/install-git-hooks.sh 2>&1 )"; ST4=$?
check "an existing hook file is not silently disabled" \
    "$([ "$ST4" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names the hook that would have stopped running" \
    "$(printf '%s' "$OUT4" | grep -c "pre-commit")" "1"

# 5. A .sample file is NOT a real hook. git ships those in every clone, and
#    refusing on them would mean the installer refuses on every fresh clone,
#    which is a guard that fires on the normal case (L324).
R5="$(fresh_repo five)"
printf '#!/bin/bash\n' > "$R5/.git/hooks/pre-commit.sample"
OUT5="$( cd "$R5" && bash scripts/install-git-hooks.sh 2>&1 )"; ST5=$?
check "git's own .sample files do not block installation" "$ST5" "0"

# 6. The hook itself: a green suite lets the push through.
OUT6="$(hook "true")"; ST6=$?
check "a green suite allows the push" "$ST6" "0"
check "and it says the suite was green" \
    "$(printf '%s' "$OUT6" | grep -ci "green")" "1"

# 7. A RED suite refuses. This is the whole job.
OUT7="$(hook "exit 1")"; ST7=$?
check "a red suite refuses the push" \
    "$([ "$ST7" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
# WHOLE WORDS. This was `refus\|blocked\|red`, and "red" is a substring of
# "registered": the moment another check in the gate printed the word, this
# counted two matching lines and failed on a hook that was working perfectly
# (ovation#58). A pattern that matches a fragment of an unrelated word is
# measuring the wrong thing in both directions (L156).
check "and it says why, rather than failing silently" \
    "$(printf '%s' "$OUT7" | grep -ciE 'refused|blocked|\bred\b')" "1"

# 8. The documented escape hatch works, and SAYS it was used. An override that
#    can happen quietly is one that happens by accident.
OUT8="$(SKIP_TEST_RUN=1 env OVATION_HOOK_TEST_COMMAND="exit 1" "$REPO_ROOT/$HOOK" 2>&1)"; ST8=$?
check "the documented override lets a red suite through" "$ST8" "0"
check "and it announces itself rather than being silent" \
    "$(printf '%s' "$OUT8" | grep -c "SKIP_TEST_RUN")" "1"

# 9. AND THE CARRY OVER ITSELF. Running this suite under SKIP_TEST_RUN=1 must not
#    change its own counts, because hook() strips it. If that stripping were ever
#    dropped, this assertion goes red rather than the suite quietly measuring a
#    hook with its checks switched off (downbeat#433, L259).
SELF="$(SKIP_TEST_RUN=1 env OVATION_HOOK_TEST_COMMAND="exit 1" bash -c '
    env -u SKIP_TEST_RUN "'"$REPO_ROOT/$HOOK"'" >/dev/null 2>&1; echo $?')"
check "the escape hatch is stripped before the hook is measured" \
    "$([ "$SELF" -ne 0 ] && echo refused || echo allowed)" "refused"

# ---------------------------------------------------------------------------
# THE GATE JUDGES THE TREE BEING PUSHED, NOT THE TREE THE HOOK FILE LIVES IN
# (ovation#138).
#
# core.hooksPath was set to an ABSOLUTE path inside the primary checkout, and the
# hook derived its own root from its own file's location. So a push from a
# worktree ran the primary checkout's hook against the primary checkout's tree
# and the primary checkout's copy of every guard. The branch being pushed was
# never looked at, which is a gate reading its criteria from a revision it is not
# judging (L398).
#
# It failed in BOTH directions, so both are staged here. One test alone would
# prove half of it and the half it proves is the forgiving one.
#
# Measured on 2026-09-08: pushing a worktree branch was refused for a fault that
# existed only in the primary checkout, and the fix for that fault was already
# committed ON the branch being refused.
stage_tree() {
    local r="$WORK/$1"; rm -rf "$r"; mkdir -p "$r/scripts/git-hooks"
    ( cd "$r" && git init -q -b main && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
    printf '#!/bin/bash\necho "SUITE-FROM-%s"\nexit %s\n' "$1" "$2" > "$r/scripts/run-tests.sh"
    chmod +x "$r/scripts/run-tests.sh"
    cp "$REPO_ROOT/$HOOK" "$r/scripts/git-hooks/pre-push"
    printf '%s' "$r"
}

# The hook FILE comes from one tree and the push comes from the other, which is
# exactly the shape a worktree push has. No command is injected: the point is
# WHICH scripts/run-tests.sh gets run.
hook_from_tree_in() {
    ( cd "$2" && env -u SKIP_TEST_RUN -u FORCE_TEST_RUN -u SKIP_STYLE_CHECK -u SKIP_TEST_CHECK \
        bash "$1/scripts/git-hooks/pre-push" 2>&1 )
}

HOOKTREE="$(stage_tree hooktree 0)"   # the checkout the hook file lives in: green
PUSHTREE="$(stage_tree pushtree 1)"   # the tree actually being pushed: red

OUT138A="$(hook_from_tree_in "$HOOKTREE" "$PUSHTREE")"; ST138A=$?
check "a red tree is refused even though the hook file's own checkout is green" \
    "$([ "$ST138A" -ne 0 ] && echo refused || echo allowed)" "refused"
check "and it was the pushed tree's suite that ran, not the hook file's" \
    "$(printf '%s' "$OUT138A" | grep -c 'SUITE-FROM-pushtree')" "1"

# The other direction, and it is the one that actually bit: a green branch
# refused for a fault that lives only in the checkout the hook file sits in.
HOOKTREE2="$(stage_tree hooktree2 1)"  # the hook file's checkout: red
PUSHTREE2="$(stage_tree pushtree2 0)"  # the tree being pushed: green

OUT138B="$(hook_from_tree_in "$HOOKTREE2" "$PUSHTREE2")"; ST138B=$?
check "a green tree is allowed even though the hook file's own checkout is red" \
    "$([ "$ST138B" -ne 0 ] && echo refused || echo allowed)" "allowed"
check "and the hook file's checkout's suite was never run" \
    "$(printf '%s' "$OUT138B" | grep -c 'SUITE-FROM-hooktree2')" "0"

# ---------------------------------------------------------------------------
# AND THE PLATFORM BEHAVIOUR THE FIX RESTS ON IS MEASURED, NOT TRUSTED (L82).
#
# The installer sets core.hooksPath to a RELATIVE path, and the whole reason that
# is the right form is a documented claim about git: a relative hooksPath is
# resolved against the working directory the hook runs in, which for a pre-push
# is the top of the tree being pushed from. If that claim is wrong, every
# worktree runs the primary's hook FILE however carefully the file resolves its
# root. So it is measured here with a real push.
PRIMARY="$WORK/hookpath"; rm -rf "$PRIMARY"; mkdir -p "$PRIMARY/scripts/git-hooks"
git init -q --bare "$WORK/hookpath-remote.git" >/dev/null 2>&1
(
    cd "$PRIMARY" && git init -q -b main && git config user.email t@t && git config user.name t
    git remote add origin "$WORK/hookpath-remote.git"
    printf '#!/bin/bash\necho "HOOK-FROM-PRIMARY" >&2\nexit 0\n' > scripts/git-hooks/pre-push
    chmod +x scripts/git-hooks/pre-push
    git config --local core.hooksPath scripts/git-hooks
    git add scripts/git-hooks/pre-push && git commit -qm one
    git worktree add -q -b side "$WORK/hookpath-wt"
) >/dev/null 2>&1
(
    cd "$WORK/hookpath-wt"
    printf '#!/bin/bash\necho "HOOK-FROM-WORKTREE" >&2\nexit 0\n' > scripts/git-hooks/pre-push
    chmod +x scripts/git-hooks/pre-push
    git add scripts/git-hooks/pre-push && git commit -qm two
) >/dev/null 2>&1
PUSHOUT="$( cd "$WORK/hookpath-wt" && git push origin side 2>&1 )"
check "a relative hooksPath runs the pushing worktree's own hook" \
    "$(printf '%s' "$PUSHOUT" | grep -c 'HOOK-FROM-WORKTREE')" "1"
check "and not the primary checkout's copy of it" \
    "$(printf '%s' "$PUSHOUT" | grep -c 'HOOK-FROM-PRIMARY')" "0"

# ---------------------------------------------------------------------------
# AN ABSOLUTE hooksPath POINTING AT THIS REPOSITORY'S OWN HOOKS IS UPGRADED.
#
# Configuration installed into git is a COPY, so changing the installer changed
# nothing on the machine that had already run the old one, and nothing reported a
# machine still carrying it (L423). This repository's own config held an absolute
# path while the installer had been writing a relative one, which is what made
# every worktree run the primary's hook.
#
# It is only ever upgraded when it points at THIS repository's tracked hooks.
# Anything else is still refused, because taking over another tool's hooks
# silently is how a gate somebody relied on stops running (case 3 above covers
# the relative form of that; this covers the absolute one, which is the form the
# upgrade has to tell apart from its own).
R138="$(fresh_repo upgrade)"
( cd "$R138" && git config --local core.hooksPath "$R138/scripts/git-hooks" )
OUT138C="$( cd "$R138" && bash scripts/install-git-hooks.sh 2>&1 )"; ST138C=$?
check "an absolute path to this repo's own hooks is upgraded, not refused" "$ST138C" "0"
check "and the setting is now the relative form" \
    "$( cd "$R138" && git config --local --get core.hooksPath )" "scripts/git-hooks"
check "and it says what it changed rather than doing it silently" \
    "$(printf '%s' "$OUT138C" | grep -ci "absolute")" "1"

R138D="$(fresh_repo foreign)"
( cd "$R138D" && git config --local core.hooksPath "/somewhere/else/git-hooks" )
OUT138D="$( cd "$R138D" && bash scripts/install-git-hooks.sh 2>&1 )"; ST138D=$?
check "an absolute path to somebody else's hooks is still refused" \
    "$([ "$ST138D" -ne 0 ] && echo refused || echo taken-over)" "refused"

harness_end
