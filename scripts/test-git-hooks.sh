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
harness_begin "git hooks tests" 17

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
check "and it says why, rather than failing silently" \
    "$(printf '%s' "$OUT7" | grep -ci "refus\|blocked\|red")" "1"

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

harness_end
