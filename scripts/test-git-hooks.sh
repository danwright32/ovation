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
harness_begin "git hooks tests" 49

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
        OVATION_HOOK_TEST_COMMAND="$1" "$REPO_ROOT/$HOOK" < /dev/null 2>&1
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
OUT8="$(SKIP_TEST_RUN=1 env OVATION_HOOK_TEST_COMMAND="exit 1" "$REPO_ROOT/$HOOK" < /dev/null 2>&1)"; ST8=$?
check "the documented override lets a red suite through" "$ST8" "0"
check "and it announces itself rather than being silent" \
    "$(printf '%s' "$OUT8" | grep -c "SKIP_TEST_RUN")" "1"

# 9. AND THE CARRY OVER ITSELF. Running this suite under SKIP_TEST_RUN=1 must not
#    change its own counts, because hook() strips it. If that stripping were ever
#    dropped, this assertion goes red rather than the suite quietly measuring a
#    hook with its checks switched off (downbeat#433, L259).
SELF="$(SKIP_TEST_RUN=1 env OVATION_HOOK_TEST_COMMAND="exit 1" bash -c '
    env -u SKIP_TEST_RUN "'"$REPO_ROOT/$HOOK"'" < /dev/null >/dev/null 2>&1; echo $?')"
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
# EVERY CHECK THE GATE NAMES GETS A PASSING STUB, derived from the hook itself
# rather than listed here, so a check added to the gate tomorrow is staged by
# these cases without anybody remembering to (L41, L96). The gate refuses a name
# it cannot find, which is what makes that derivation load bearing rather than
# convenient.
gate_check_names() { grep -oE '^gate_check +check-[a-z-]+\.(sh|py)' "$REPO_ROOT/$HOOK" | awk '{print $2}'; }

stage_tree() {
    local r="$WORK/$1"; rm -rf "$r"; mkdir -p "$r/scripts/git-hooks"
    ( cd "$r" && git init -q -b main && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
    printf '#!/bin/bash\necho "SUITE-FROM-%s"\necho "SKIP=${OVATION_SKIP_XCODE_PHASE:-}"\nexit %s\n' "$1" "$2" > "$r/scripts/run-tests.sh"
    chmod +x "$r/scripts/run-tests.sh"
    local c
    for c in $(gate_check_names); do
        printf '#!/bin/bash\nexit 0\n' > "$r/scripts/$c"
        chmod +x "$r/scripts/$c"
    done
    cp "$REPO_ROOT/$HOOK" "$r/scripts/git-hooks/pre-push"
    printf '%s' "$r"
}

# The hook FILE comes from one tree and the push comes from the other, which is
# exactly the shape a worktree push has. No command is injected: the point is
# WHICH scripts/run-tests.sh gets run.
hook_from_tree_in() {
    ( cd "$2" && env -u SKIP_TEST_RUN -u FORCE_TEST_RUN -u SKIP_STYLE_CHECK -u SKIP_TEST_CHECK \
        bash "$1/scripts/git-hooks/pre-push" < /dev/null 2>&1 )
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

# ---------------------------------------------------------------------------
# THE GATE READS EXIT CODES, NOT TRUTHINESS (ovation#135).
#
# Every check was `if ! script; then echo <one sentence>; exit 1; fi`, so a check
# that went to real trouble to keep three outcomes apart had two of them
# collapsed into the single sentence that sends somebody hunting for a leak that
# is not there. Worse, it meant NOBODY BUT THIS MAC COULD PUSH: the identity
# guard derives its needles from sources outside the repository, so a fresh
# clone, Dan's second machine and a CI runner were each told the tree was
# contaminated (L11, L148, L36).
#
# DAN'S DECISION, 2026-09-08: refuse only when the machine SHOULD have been able
# to measure. So the codes carry that, and one function applies it to every check
# rather than ten copies of the same case statement drifting apart (L30, L613).
#
#   0  passed
#   2  could not measure, and nothing here ever could have: allowed, and said
#   4  could not measure, and this machine had what it needed: refused
#   anything else: refused, with that check's own sentence
add_check() {
    printf '#!/bin/bash\necho "CHECK-%s-RAN"\nexit %s\n' "$2" "$3" > "$1/scripts/$2"
    chmod +x "$1/scripts/$2"
}

G1="$(stage_tree gate1 0)"; add_check "$G1" "check-identity-leaks.sh" 1
OUT135A="$(hook_from_tree_in "$G1" "$G1")"; ST135A=$?
check "a check that found a fault refuses the push" \
    "$([ "$ST135A" -ne 0 ] && echo refused || echo allowed)" "refused"
check "and it says a real identity is in the tree, which is what code 1 means" \
    "$(printf '%s' "$OUT135A" | grep -ci 'identity appears')" "1"

G2="$(stage_tree gate2 0)"; add_check "$G2" "check-identity-leaks.sh" 2
OUT135B="$(hook_from_tree_in "$G2" "$G2")"; ST135B=$?
check "a check nothing on this machine could answer does not refuse the push" \
    "$([ "$ST135B" -ne 0 ] && echo refused || echo allowed)" "allowed"
# The closing line, not just any mention: the notice that matters scrolls past
# several minutes of suite output, and the last line is the one that gets read.
check "and the closing line names the check that went unmeasured" \
    "$(printf '%s' "$OUT135B" | grep -c 'unmeasured on this machine: check-identity-leaks')" "1"
check "and it does NOT accuse the tree of holding a real identity" \
    "$(printf '%s' "$OUT135B" | grep -ci 'identity appears')" "0"

G3="$(stage_tree gate3 0)"; add_check "$G3" "check-identity-leaks.sh" 4
OUT135C="$(hook_from_tree_in "$G3" "$G3")"; ST135C=$?
check "a check that should have been able to measure and could not refuses" \
    "$([ "$ST135C" -ne 0 ] && echo refused || echo allowed)" "refused"
check "and it says the fault is on this machine, not in the tree" \
    "$(printf '%s' "$OUT135C" | grep -ci 'machine')" "1"

# THE SUITE ITSELF ANSWERS THE SAME WAY NOW (ovation#139). run-tests.sh returns 2
# when every suite that could run passed and at least one could not, which on a
# tree with no built product is the two bundle suites. Refusing there would mean
# no push at all until both configurations are built, which is the cost that
# issue was filed about.
G4="$(stage_tree gate4 2)"
OUT135D="$(hook_from_tree_in "$G4" "$G4")"; ST135D=$?
check "a suite that could not measure does not refuse the push" \
    "$([ "$ST135D" -ne 0 ] && echo refused || echo allowed)" "allowed"
check "and the gate does not call that run green" \
    "$(printf '%s' "$OUT135D" | grep -ci 'suite is green')" "0"
check "and it says the suite itself is what went unmeasured" \
    "$(printf '%s' "$OUT135D" | grep -c 'unmeasured on this machine: the test suite')" "1"

# SEEN TO FAIL (L1). The refusal above is the whole reason the stub staging is
# derived from the hook, so it has to be shown firing rather than assumed.
G5="$(stage_tree gate5 0)"; rm -f "$G5/scripts/check-identity-leaks.sh"
OUT135E="$(hook_from_tree_in "$G5" "$G5")"; ST135E=$?
check "a check the gate names and the tree does not hold refuses the push" \
    "$([ "$ST135E" -ne 0 ] && echo refused || echo allowed)" "refused"
check "and it names the check it could not find" \
    "$(printf '%s' "$OUT135E" | grep -c 'check-identity-leaks.sh is named by this gate')" "1"

# ---------------------------------------------------------------------------
# A PUSH THAT CANNOT HAVE CHANGED THE XCODE RUN DOES NOT WAIT FOR IT (ovation#22).
#
# Measured twice on 2026-09-05, four minutes each time: the hook ran the runner,
# which waited on Overture's lock while a real Overture suite ran. Overture runs
# its suite constantly, so that is the normal case, and most pushes in this phase
# change only documentation or shell scripts.
#
# ONLY THE HOOK KNOWS WHAT IS BEING PUSHED, which is why the decision is here and
# the runner only carries it out. It FAILS CLOSED: anything it cannot place, and
# anything outside a short list of paths no xcodebuild run can read, means the
# full thing runs. And it SAYS which of the two it decided, because a push that
# skipped the Swift suites must never read like one that passed them (L98).
commit_file() {
    ( cd "$1" && mkdir -p "$(dirname "$2")" && printf 'x\n' > "$2" \
      && git add "$2" && git commit -qm "c" ) >/dev/null 2>&1
    ( cd "$1" && git rev-parse HEAD )
}
hook_with_range() {
    ( cd "$1" && printf '%s\n' "$2" | env -u SKIP_TEST_RUN -u FORCE_TEST_RUN \
        -u SKIP_STYLE_CHECK -u SKIP_TEST_CHECK \
        bash "$1/scripts/git-hooks/pre-push" origin "$1" 2>&1 )
}
ZEROS="0000000000000000000000000000000000000000"

R22="$(stage_tree range 0)"
BASE22="$(commit_file "$R22" "docs/one.md")"
DOCS22="$(commit_file "$R22" "docs/two.md")"
OUT22A="$(hook_with_range "$R22" "refs/heads/main $DOCS22 refs/heads/main $BASE22")"; ST22A=$?
check "a push touching only docs skips the xcode phase" \
    "$(printf '%s' "$OUT22A" | grep -c 'SKIP=1')" "1"
check "and it says so rather than skipping quietly" \
    "$(printf '%s' "$OUT22A" | grep -ci 'skipping the xcode')" "1"
check "and the push is still allowed" "$ST22A" "0"

SWIFT22="$(commit_file "$R22" "Ovation/Domain/Thing.swift")"
OUT22B="$(hook_with_range "$R22" "refs/heads/main $SWIFT22 refs/heads/main $DOCS22")"
check "a push touching a Swift file runs the xcode phase" \
    "$(printf '%s' "$OUT22B" | grep -c 'SKIP=$')" "1"
check "and it names the kind of change that made it run the full thing" \
    "$(printf '%s' "$OUT22B" | grep -c 'Thing.swift')" "1"

# A RANGE IT CANNOT PLACE RUNS EVERYTHING. The remote sha of a branch that does
# not exist yet is all zeros, and a stub repository has no remote to work back
# from, so this is the case that must not be guessed at.
OUT22C="$(hook_with_range "$R22" "refs/heads/side $SWIFT22 refs/heads/side $ZEROS")"
check "a range that cannot be placed runs the xcode phase" \
    "$(printf '%s' "$OUT22C" | grep -c 'SKIP=$')" "1"

# NO RANGE AT ALL, which is what happens when the hook is run by hand.
OUT22D="$( cd "$R22" && env -u SKIP_TEST_RUN bash "$R22/scripts/git-hooks/pre-push" < /dev/null 2>&1 )"
check "no range at all runs the xcode phase" \
    "$(printf '%s' "$OUT22D" | grep -c 'SKIP=$')" "1"
check "and it says it could not tell what was being pushed" \
    "$(printf '%s' "$OUT22D" | grep -ci 'could not')" "1"

# ONE RELEVANT PATH AMONG MANY IRRELEVANT ONES IS STILL RELEVANT. A rule applied
# to the first path, or to most of them, is not a rule about the push.
MIXED22="$( cd "$R22" && mkdir -p docs && printf 'y\n' > docs/three.md \
    && printf 'y\n' > Ovation/Domain/Other.swift && git add docs/three.md Ovation/Domain/Other.swift \
    && git commit -qm mixed >/dev/null 2>&1 && git rev-parse HEAD )"
OUT22E="$(hook_with_range "$R22" "refs/heads/main $MIXED22 refs/heads/main $SWIFT22")"
check "one relevant path among irrelevant ones still runs the xcode phase" \
    "$(printf '%s' "$OUT22E" | grep -c 'SKIP=$')" "1"

# THE READ IS GUARDED, asserted on the source because a blocking read cannot be
# staged as a test without a timeout, and a test that waits for a fixed period to
# decide something did NOT happen is a test about this machine's load (L290).
# Every case above supplies its own stdin, so none of them can reach it.
check "the ref loop does not read a terminal it was never given" \
    "$(grep -c 'if \[ -t 0 \]; then' "$REPO_ROOT/$HOOK")" "1"

harness_end
