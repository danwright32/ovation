#!/bin/bash
# The test runner must genuinely exclude BOTH siblings, release both locks on
# every exit path including a crash, and refuse rather than fail obscurely when
# the tool one of them needs is absent.
#
# ovation#12, decided by Dan on 2026-09-05 as option A: Ovation takes both
# existing locks, by the mechanism each one uses, in a fixed order. Nothing in
# Downbeat or Overture changes.
#
# The two locks use DIFFERENT mechanisms and cannot be merged: Downbeat takes a
# DIRECTORY with mkdir, Overture takes a FILE with Homebrew flock. flock opens
# with O_CREAT and cannot open an existing directory that way; mkdir on a path
# holding a regular file returns EEXIST. So this takes each by its own means.
#
# Every case runs against THROWAWAY lock paths. Nothing here touches
# /tmp/xcodebuild-tests.lock or /tmp/overture-mac-tests.lock, because a test that
# took the real locks would block Dan's other two apps (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
# EVERY SEAM IS CLEARED FIRST, not just the one that was caught. They are
# environment variables, so a value set in the shell that launched this suite is
# inherited by every runner spawned below and silently answers for them (L169,
# L439). Measured twice: exporting OVATION_TEST_FLOOR=9999 to prove the guard
# fires on the real suite made six of these cases fail instead, and running this
# suite THROUGH the runner with the pure and hosted commands injected made the
# hosted skip case fail, because its inner runner inherited a command it was
# never given. The last case in this file asserts this list is complete, so a
# seam added to the runner tomorrow cannot be left out of it (L284, L30).
unset OVATION_TEST_FLOOR OVATION_TEST_COMMAND OVATION_HOSTED_TEST_COMMAND \
      OVATION_UNLOCKED_COMMAND OVATION_SHELL_SUITE_DIR OVATION_SHELL_SUITE_FLOOR \
      OVATION_SKIP_XCODE_PHASE \
      OVATION_DIR_LOCK OVATION_FILE_LOCK OVATION_FLOCK_BIN \
      OVATION_LOCK_TIMEOUT OVATION_LOCK_POLL_INTERVAL \
      OVATION_XCODE_PROJECT OVATION_XCODEGEN OVATION_XCODEBUILD_LISTER \
      OVATION_LOCK_WAIT_LOG OVATION_XCODEBUILD OVATION_XCODE_VERSION_FILE

# THE TOOL THIS WHOLE SUITE NEEDS, ASKED FOR ONCE (L41), AND ITS ABSENCE IS NOT A
# FAILURE (L411).
#
# The runner takes Overture's lock with Homebrew flock and REFUSES to run without
# it, deliberately, so on a machine that does not have it every case here fails
# for one reason that has nothing to do with the runner being wrong. That is a
# red indistinguishable from a real one, and it is what the first CI run of the
# shell suites job produced: 25 failures, all of them this.
#
# CANNOT MEASURE is the honest verdict there, and the harness has its own exit
# code for it. Two cases below still ask the same question because they STAGE a
# held lock rather than merely needing the tool, and they read it from here so
# there is one definition of where flock is.
# WHERE flock IS DIFFERS BY MACHINE (ovation#152). Homebrew puts it at
# /opt/homebrew/bin on this Mac; every Linux distribution ships it at /usr/bin as
# part of util-linux. Hardcoding the Homebrew path made this whole suite answer
# CANNOT MEASURE on the Linux runner, which is honest and measures nothing: the
# runner's own locking is exactly the kind of shell logic that job exists to run.
#
# The Homebrew path is tried FIRST rather than PATH, so on this Mac the tool the
# runner itself uses is the tool this measures (L380).
SUITE_FLOCK="${OVATION_SUITE_FLOCK_BIN:-}"
if [ -z "$SUITE_FLOCK" ]; then
    for candidate in /opt/homebrew/bin/flock /usr/local/bin/flock /usr/bin/flock; do
        [ -x "$candidate" ] && { SUITE_FLOCK="$candidate"; break; }
    done
    SUITE_FLOCK="${SUITE_FLOCK:-/opt/homebrew/bin/flock}"
fi

harness_begin "test runner lock tests" 119

[ -x "$SUITE_FLOCK" ] || harness_cannot_measure \
    "flock is not at $SUITE_FLOCK, and the runner refuses to run without it" \
    "install it with: brew install flock"

TARGET="scripts/run-tests.sh"
REPO_ROOT_SCRIPTS="$PWD/scripts"
require_target "$TARGET"
harness_temp_dir WORK

DIR_LOCK="$WORK/dir.lock"
FILE_LOCK="$WORK/file.lock"

# A PROJECT THAT EXISTS, SO NO CASE HERE DEPENDS ON THE DEVELOPER HAVING ONE.
#
# ovation#151 made the runner generate `Ovation.xcodeproj` when it is absent and
# REFUSE when it cannot. Every case below that drives the real runner through the
# Xcode phase then quietly depended on this machine already having a generated
# project, which is true on Dan's Mac and false on a fresh clone and on the Linux
# job, where the whole suite failed with exit 2 (ovation#152). The cases that are
# ABOUT that behaviour point at their own paths and are unaffected.
STANDIN_PROJECT="$WORK/present.xcodeproj"
mkdir -p "$STANDIN_PROJECT"

# The runner is driven with a trivial command instead of xcodebuild, so these
# cases measure the LOCKING and not a three minute build (L2, L291).
#
# THE COMMAND A LOCK CASE STAGES IS THE HOSTED ONE (ovation#271). The locks wrap
# the hosted suite alone, so a case asking "does the lock stop it" has to hand
# the runner a hosted command; a pure one now runs whatever is held. It prints a
# count because a hosted run that executed nothing is refused (ovation#59).
HOSTED_PASSES='echo "Test run with 5 tests in 1 suite passed"'
# THE XCODE VERSION SEAMS ARE SET HERE TOO (ovation#270), to paths that are not
# there unless a case overrides them. Left unset, every case would run the real
# xcodebuild to ask its version and read the real pin, which is this machine's
# answer to a question no case but the Xcode ones is asking (L284).
run_runner() {
    OVATION_XCODEBUILD="${XCODEBUILD_OVERRIDE:-$WORK/no-xcodebuild-given}" \
    OVATION_XCODE_VERSION_FILE="${XCODE_PIN_OVERRIDE:-$WORK/no-xcode-pin-given}" \
    OVATION_DIR_LOCK="$DIR_LOCK" \
    OVATION_FILE_LOCK="$FILE_LOCK" \
    OVATION_LOCK_TIMEOUT="${TIMEOUT_OVERRIDE:-2}" \
    OVATION_LOCK_POLL_INTERVAL="${POLL_OVERRIDE:-0.05}" \
    OVATION_FLOCK_BIN="${FLOCK_OVERRIDE:-$SUITE_FLOCK}" \
    OVATION_TEST_COMMAND="${PURE_OVERRIDE:-true}" \
    OVATION_HOSTED_TEST_COMMAND="${1:-$HOSTED_PASSES}" \
    OVATION_UNLOCKED_COMMAND="${2:-true}" \
    OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
        "./$TARGET" 2>&1
}

# 1. Nothing held: it runs, and it runs the command it was given.
OUT1="$(run_runner "echo THE-COMMAND-RAN; $HOSTED_PASSES")"; ST1=$?
check "with neither lock held the runner succeeds" "$ST1" "0"
check "and it actually ran the command" \
    "$(printf '%s' "$OUT1" | grep -c "THE-COMMAND-RAN")" "1"

# 2. AND IT RELEASED BOTH. A runner that leaves a lock planted blocks the next
#    run of a DIFFERENT app, which is the failure this whole thing exists to stop.
check "the directory lock was released" \
    "$([ -e "$DIR_LOCK" ] && echo held || echo free)" "free"

# 3. Downbeat's lock held: Ovation must WAIT and then refuse, not barge in.
mkdir -p "$DIR_LOCK"
OUT3="$(run_runner)"; ST3=$?
check "Downbeat's directory lock stops Ovation running" \
    "$([ "$ST3" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
mentions() { if printf '%s' "$1" | grep -q "$2"; then echo yes; else echo no; fi; }
check "and it names which lock it was waiting on" \
    "$(mentions "$OUT3" "$DIR_LOCK")" "yes"
check "and it did NOT run the command anyway" \
    "$(printf '%s' "$OUT3" | grep -c "THE-COMMAND-RAN")" "0"
rmdir "$DIR_LOCK"

# 4. Overture's lock held: same answer, by the other mechanism. Proving only one
#    of the two would leave the other arm untested, and it is the arm that uses
#    the tool Ovation does not own.
    : > "$FILE_LOCK"
    # Held until the test RELEASES it, not for a fixed number of seconds. A
    # timed holder asserts about machine load: too short and it lets go before
    # the test has observed anything, too long and every run pays for it (L290).
    HOLD_SENTINEL="$WORK/hold-1"; : > "$HOLD_SENTINEL"
    ( "$SUITE_FLOCK" "$FILE_LOCK" bash -c 'while [ -e "$1" ]; do sleep 0.02; done' _ "$HOLD_SENTINEL" ) &
    HOLDER=$!
    # Wait for the holder to actually HAVE the lock, rather than sleeping and
    # hoping: a fixed wait asserts about machine load, not about the lock (L290).
    waited=0
    while "$SUITE_FLOCK" -n "$FILE_LOCK" true 2>/dev/null; do
        waited=$((waited+1)); [ "$waited" -gt 100 ] && break; sleep 0.05
    done
    OUT4="$(run_runner)"; ST4=$?
    check "Overture's file lock also stops Ovation running" \
        "$([ "$ST4" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
    check "and it names that lock too" \
        "$(mentions "$OUT4" "$FILE_LOCK")" "yes"
    rm -f "$HOLD_SENTINEL"
    wait "$HOLDER" 2>/dev/null || true


# 5. THE ORDER IS FIXED, and that is what makes deadlock impossible. Neither
#    sibling takes two locks, so as long as Ovation always takes them in the same
#    order it cannot deadlock with itself either. Asserted on the source, because
#    the behaviour is only observable in a race nobody can reliably stage.
DIR_LINE="$(grep -n 'OVATION_DIR_LOCK\|dir_lock' "$TARGET" | head -1 | cut -d: -f1)"
FILE_LINE="$(grep -n 'acquire_file_lock\|OVATION_FILE_LOCK' "$TARGET" | tail -1 | cut -d: -f1)"
check "the directory lock is taken before the file lock" \
    "$([ "$DIR_LINE" -lt "$FILE_LINE" ] && echo dir-first || echo file-first)" "dir-first"

# 6. A CRASH must still release both. The directory lock does NOT self clear the
#    way flock does, so the trap is the whole of Ovation's crash safety on that
#    half (L515, L409).
run_runner "kill -9 \$\$" >/dev/null 2>&1
check "a killed run still releases the directory lock" \
    "$([ -e "$DIR_LOCK" ] && echo held || echo free)" "free"

# 7. Missing flock: say so BY NAME with the remedy, rather than failing
#    obscurely. Ovation inherits this dependency from Overture and does not own
#    it, so it is the one that will be absent on a fresh machine (L148).
# `A=x B="$(cmd)"` is TWO ASSIGNMENTS, not a scoped environment prefix: this
# sets FLOCK_OVERRIDE for the rest of the file. The first version of case 8 below
# then ran with a missing flock and passed for entirely the wrong reason, which
# a test asserting only "it failed somehow" can never notice (L140, L159).
FLOCK_OVERRIDE="/nonexistent/flock"
OUT7="$(run_runner)"; ST7=$?
check "a missing flock does not silently pass" \
    "$([ "$ST7" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names flock as what is missing" \
    "$(mentions "$OUT7" "flock")" "yes"
check "and it gives the command that fixes it" \
    "$(printf '%s' "$OUT7" | grep -c "brew install flock")" "1"
check "and it did not run the tests without the lock" \
    "$(printf '%s' "$OUT7" | grep -c "THE-COMMAND-RAN")" "0"

unset FLOCK_OVERRIDE

# 8. A failing test command must fail the run. A runner that takes locks
#    correctly and swallows the verdict is worse than no runner (L184, L404).
OUT8="$(run_runner "exit 3")"; ST8=$?
check "a failing test command fails the run, with the command's own status" "$ST8" "3"
check "and it got far enough to actually hold both locks first" \
    "$(mentions "$OUT8" "Holding both locks")" "yes"

# 9. THE LOCKS ARE SCOPED TO THE WORK THAT NEEDS THEM.
#
#    Found on the FIRST REAL USE, minutes after this shipped. A push ran the
#    hook, which ran this runner, which took Downbeat's lock and then waited on
#    Overture's, which a real Overture suite had held for four minutes. That is
#    the lock working exactly as intended. But it made the SHELL suites wait too,
#    and they use no xcodebuild and share nothing with either sibling. A gate
#    that queues its cheap checks behind another app's build is a gate people
#    learn to skip (L378, L299).
#
#    So the unlocked work runs FIRST, with no lock at all, and the locks are held
#    only around the xcodebuild run.

# 9a. A failing unlocked command fails the run WITHOUT ever taking a lock.
rm -rf "$DIR_LOCK"
OUT9="$(run_runner "true" "exit 4")"; ST9=$?
check "a failing unlocked check fails the run" "$ST9" "4"
check "and it never took the shared lock to find that out" \
    "$([ -e "$DIR_LOCK" ] && echo held || echo free)" "free"

# 9b. With a sibling holding a lock, the unlocked work STILL RUNS. This is the
#     whole point: the cheap checks are not queued behind another app's build.
mkdir -p "$DIR_LOCK"
TIMEOUT_OVERRIDE=1 OUT9B="$(run_runner "true" "echo UNLOCKED-RAN-ANYWAY")"; ST9B=$?
check "the unlocked work runs even while a sibling holds the lock" \
    "$(mentions "$OUT9B" "UNLOCKED-RAN-ANYWAY")" "yes"
rmdir "$DIR_LOCK"

# 10. OVATION MUST NOT HOLD ONE SIBLING'S LOCK WHILE WAITING FOR THE OTHER'S.
#
#     Also found on the first real use. Ovation took Downbeat's lock, then waited
#     on Overture's for four minutes. For all that time DOWNBEAT could not run
#     either, blocked by Overture through Ovation, which is a coupling nobody
#     chose and which neither sibling can see or diagnose.
#
#     So the second lock is tried WITHOUT blocking, and if it is not free the
#     first is RELEASED before waiting and retrying. Ovation waits for both,
#     holds neither while waiting, and still cannot deadlock.
    : > "$FILE_LOCK"
    HOLD_SENTINEL2="$WORK/hold-2"; : > "$HOLD_SENTINEL2"
    ( "$SUITE_FLOCK" "$FILE_LOCK" bash -c 'while [ -e "$1" ]; do sleep 0.02; done' _ "$HOLD_SENTINEL2" ) &
    HOLDER2=$!
    waited=0
    while "$SUITE_FLOCK" -n "$FILE_LOCK" true 2>/dev/null; do
        waited=$((waited+1)); [ "$waited" -gt 100 ] && break; sleep 0.05
    done

    # Start Ovation while the file lock is held, and watch whether it parks on
    # the directory lock. Wait on the CONDITION rather than a fixed sleep (L290).
    ( TIMEOUT_OVERRIDE=4 run_runner >/dev/null 2>&1 ) &
    RUNNER=$!
    # THE PROPERTY IS "NOT HELD FOR THE DURATION", NOT "NEVER HELD".
    #
    # The design takes the directory lock, tries the file lock without blocking,
    # and releases before waiting. So a brief hold on each attempt is inherent
    # and harmless, because Downbeat's own loop retries. The first version of
    # this asserted the lock was NEVER observed held, which passed standalone and
    # failed the moment the suite ran under load: it was asserting about timing
    # rather than about the design (L205, L224).
    #
    # Observed FREE at least once during the wait is the honest distinction. The
    # old design held it continuously and would never be seen free.
    seen_free=0; polls=0
    while [ "$polls" -lt 80 ] && kill -0 "$RUNNER" 2>/dev/null; do
        [ -e "$DIR_LOCK" ] || seen_free=1
        polls=$((polls+1)); sleep 0.05
    done
    check "Downbeat's lock is released between attempts, not held for the whole wait" \
        "$([ "$seen_free" -eq 1 ] && echo released || echo held-throughout)" "released"
    rm -f "$HOLD_SENTINEL2"; wait "$HOLDER2" 2>/dev/null || true
    wait "$RUNNER" 2>/dev/null || true
    check "and neither lock is left behind afterwards" \
        "$([ -e "$DIR_LOCK" ] && echo held || echo free)" "free"

# ---------------------------------------------------------------------------
# 12. THE PURE SUITE DOES NOT WAIT FOR THE SIBLINGS (ovation#271).
#
#     MEASURED, NOT REASONED. On 2026-09-13, 516 Ovation runs were measured, 406
#     of them beside real Overture and Downbeat suites. The pure suite opens no
#     windows, and no
#     sibling failure ever coincided with it. The hosted suite orders its own
#     windows front, which moves key window status, and all 21 failures of an
#     Overture test that counts rows while focus can move (overture#3876) landed
#     while it was testing. Two Ovation pure suites at once passed 40 of 40. So
#     the locks wrap the hosted suite alone, and the pure suite is not queued
#     behind a sibling's build.
PURE_RAN='echo PURE-SUITE-RAN'
HOSTED_RAN="echo HOSTED-SUITE-RAN; $HOSTED_PASSES"
line_of() { printf '%s\n' "$1" | grep -n "$2" | head -1 | cut -d: -f1; }

# 12a. Downbeat's lock held: the pure suite runs and the hosted suite waits.
mkdir -p "$DIR_LOCK"
OUT12A="$(PURE_OVERRIDE="$PURE_RAN" TIMEOUT_OVERRIDE=1 run_runner "$HOSTED_RAN")"; ST12A=$?
check "with Downbeat's lock held the pure suite still runs" \
    "$(mentions "$OUT12A" "PURE-SUITE-RAN")" "yes"
check "and the hosted suite does not" "$(mentions "$OUT12A" "HOSTED-SUITE-RAN")" "no"
check "and the run fails on the lock rather than passing without the hosted suite" \
    "$([ "$ST12A" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
rmdir "$DIR_LOCK"

# 12b. Overture's lock held, by the other mechanism: the same answer.
    : > "$FILE_LOCK"
    HOLD_SENTINEL3="$WORK/hold-3"; : > "$HOLD_SENTINEL3"
    ( "$SUITE_FLOCK" "$FILE_LOCK" bash -c 'while [ -e "$1" ]; do sleep 0.02; done' _ "$HOLD_SENTINEL3" ) &
    HOLDER3=$!
    waited=0
    while "$SUITE_FLOCK" -n "$FILE_LOCK" true 2>/dev/null; do
        waited=$((waited+1)); [ "$waited" -gt 100 ] && break; sleep 0.05
    done
    OUT12B="$(PURE_OVERRIDE="$PURE_RAN" TIMEOUT_OVERRIDE=1 run_runner "$HOSTED_RAN")"
    check "with Overture's lock held the pure suite still runs" \
        "$(mentions "$OUT12B" "PURE-SUITE-RAN")" "yes"
    check "and the hosted suite does not" "$(mentions "$OUT12B" "HOSTED-SUITE-RAN")" "no"
    rm -f "$HOLD_SENTINEL3"; wait "$HOLDER3" 2>/dev/null || true

# 12c. With nothing held, the ORDER is the design: pure suite, then the locks,
#      then the hosted suite inside them. Asserted on the output, so a runner
#      that took the locks first and ran both inside would fail it.
OUT12C="$(PURE_OVERRIDE="$PURE_RAN" run_runner "$HOSTED_RAN")"; ST12C=$?
check "with nothing held both suites run and the run passes" "$ST12C" "0"
check "the pure suite runs before the locks are even asked for" \
    "$([ "$(line_of "$OUT12C" PURE-SUITE-RAN)" -lt "$(line_of "$OUT12C" 'Waiting for both test locks')" ] 2>/dev/null && echo pure-first || echo locks-first)" "pure-first"
check "and the hosted suite runs only once both locks are held" \
    "$([ "$(line_of "$OUT12C" 'Holding both locks')" -lt "$(line_of "$OUT12C" HOSTED-SUITE-RAN)" ] 2>/dev/null && echo held-first || echo ran-first)" "held-first"

# 12d. A FAILING PURE SUITE NEVER ASKS FOR THE LOCKS. Nothing after a real failure
#      is worth queueing behind a sibling for, which is the same rule the shell
#      suites already follow.
OUT12D="$(PURE_OVERRIDE='echo "Test run with 5 tests in 1 suite failed"; exit 65' run_runner "$HOSTED_RAN")"; ST12D=$?
check "a failing pure suite fails the run with its own status" "$ST12D" "65"
check "and it never asks for the sibling locks" \
    "$(mentions "$OUT12D" "Waiting for both test locks")" "no"
check "and the hosted suite does not run" "$(mentions "$OUT12D" "HOSTED-SUITE-RAN")" "no"


# ---------------------------------------------------------------------------
# NO SUITE MAY TAKE A SUITE LEVEL ARGUMENT.
#
# ovation#25, and this is the class rather than the instance (L30). The runner
# above discovers its suites by glob and runs each one with NO arguments, so it
# can only ever invoke a suite ONE way. A suite that reads a positional
# parameter therefore runs for ever in its DEFAULT mode, its other cases never
# run at all, and its name still appears in every green report (L413).
#
# That is not hypothetical here. scripts/test-built-bundle-identity.sh took the
# configuration as $1 and defaulted to Debug, so its RELEASE assertions, the
# ones that had caught a real security defect hours earlier in ovation#9, never
# ran in the suite or in the pre push gate. A reader saw "built bundle identity
# tests" pass and concluded the shipping bundle was checked (L400, L98).
#
# WHAT THIS CATCHES, AND WHAT IT DOES NOT, said plainly rather than left to be
# inferred from its name. It flags an UNINDENTED read of $1: that is where the
# defect lived, and it is the only place a suite can read its own arguments
# before any function is entered. It deliberately does not flag a $1 inside a
# function (that is the function's own parameter, which every suite here uses),
# an escaped \$1 written into a generated script by a heredoc, or an indented
# `bash -c '...$1...'` whose $1 belongs to the inner shell. An indented top
# level read would slip through, and that is the known limit.
#
# The over match direction is checked as deliberately as the under match one,
# because the shape being matched is not unique to the defect and a guard that
# fires on healthy files is one people learn to skip (L104, L378).
positional_readers() {
    local dir="$1" f found=""
    for f in "$dir"/test-*.sh; do
        [ -f "$f" ] || continue
        if grep -nE '^[^[:space:]#]' "$f" \
            | grep -vE ':[A-Za-z_][A-Za-z0-9_]*\(\)' \
            | grep -qE '(^|[^\\])\$\{?1([^0-9]|$)'; then
            found="${found}$(basename "$f") "
        fi
    done
    printf '%s' "${found% }"
}

STAGE="$WORK/suitescan"
mkdir -p "$STAGE"

# 1. SEEN TO FAIL, on the exact line this issue removed.
#
# The fixture is written from INSIDE a function, and that is not a style choice.
# A guard that hunts for a pattern has to name that pattern in order to look for
# it, so the first version of this staged the offending line at the top level of
# this very file and the guard correctly reported test-run-tests.sh itself
# (L245). Indented, the line is where every other suite's parameters live, and
# the guard is deliberately blind there.
stage_offender() {
    printf '#!/bin/bash\nCONFIG="${1:-Debug}"\necho "$CONFIG"\n' > "$1"
}
stage_offender "$STAGE/test-offender.sh"
# ---------------------------------------------------------------------------
# THE HOSTED SUITE (ovation#59). A second xcodebuild invocation, narrowed with
# -only-testing, and a narrowed run that matches nothing prints ** TEST
# SUCCEEDED ** and exits 0 (L98, L288).
# ---------------------------------------------------------------------------
hosted_run() {
    OVATION_UNLOCKED_COMMAND=true \
    OVATION_DIR_LOCK="$WORK/dir.lock" OVATION_FILE_LOCK="$WORK/file.lock" \
    OVATION_LOCK_POLL_INTERVAL=0.05 OVATION_LOCK_TIMEOUT=5 \
    OVATION_TEST_COMMAND="true" OVATION_HOSTED_TEST_COMMAND="${1}" \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
    "$TARGET" 2>&1
}
hosted_status() { hosted_run "$1" >/dev/null 2>&1; printf '%s' "$?"; }

# A LONG HOSTED OUTPUT IS STILL JUDGED CORRECTLY (ovation#241).
#
# The check asked `printf '%s' "$OUTPUT" | grep -qE 'Test run with [1-9]...'`.
# Under `set -o pipefail`, which this runner sets, `grep -q` EXITS at the first
# match and closes the pipe, `printf` is killed writing the rest, and the
# pipeline takes printf's failure: the negation then reports "executed NO tests"
# about a run that executed plenty (L183).
#
# IT ONLY HAPPENS WHEN THE OUTPUT IS BIG ENOUGH that printf is still writing
# when grep quits, which is why it passed here for weeks and failed on a runner:
# measured 2026-09-12 on CI, one of two identical jobs failed with
# `printf: write error: Broken pipe` immediately after `** TEST SUCCEEDED **`
# and a hosted run of 26 tests. So the fixture is deliberately LARGE, and the
# match is deliberately at the TOP, which is the arrangement that kills printf.
LONG_HOSTED_OUTPUT='echo "Test run with 26 tests in 4 suites passed"; for i in $(seq 1 20000); do echo "a line of ordinary xcodebuild chatter, number $i"; done'
check "a hosted run with a long output is not reported as having run nothing" \
    "$(hosted_status "$LONG_HOSTED_OUTPUT")" "0"
check "and it does not complain about a broken pipe" \
    "$(hosted_run "$LONG_HOSTED_OUTPUT" | grep -c 'Broken pipe' || true)" "0"

# THE PURE SUITE IS JUDGED BY ITS COUNT, NOT ONLY ITS EXIT CODE (ovation#106).
# It is 289 of the 294 tests, and until now it was judged by exit code alone
# while the hosted five had their count read back. A run is judged first by what
# it EXECUTED against what was expected, and only then by its failures (L288): a
# renamed target, a changed scheme, a filter or a future move to parallel workers
# can lose most of the suite and still print a verdict.
pure_run() {
    OVATION_UNLOCKED_COMMAND=true \
    OVATION_DIR_LOCK="$WORK/dir.lock" OVATION_FILE_LOCK="$WORK/file.lock" \
    OVATION_LOCK_POLL_INTERVAL=0.05 OVATION_LOCK_TIMEOUT=5 \
    OVATION_TEST_FLOOR="${2:-100}" \
    OVATION_TEST_COMMAND="${1}" OVATION_HOSTED_TEST_COMMAND='echo "Test run with 5 tests in 1 suite passed"' \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
    "$TARGET" 2>&1
}
pure_status() { pure_run "$1" "${2:-100}" >/dev/null 2>&1; printf '%s' "$?"; }

check "a pure run at the floor passes" \
    "$(pure_status 'echo "Test run with 100 tests in 9 suites passed"' 100)" "0"
# THIS CASE IS THE REVERSE OF WHAT IT ASSERTED, and the reversal is the whole of
# ovation#157 rather than an adjustment. It used to say a run ABOVE its floor
# passes, which is what let the floor sit at 294 while the suite executed 422:
# 128 tests could vanish and the check would still be green (L63). A test
# defending a decision that has been reversed is the guard for the rejected
# behaviour, so it is rewritten to say the new rule rather than tweaked (L252,
# L430).
check "a pure run above the floor is refused, so the floor cannot stand still" \
    "$(pure_status 'echo "Test run with 294 tests in 29 suites passed"' 100)" "7"
check "a pure run BELOW the floor is refused even though it exited 0" \
    "$(pure_status 'echo "Test run with 40 tests in 3 suites passed"' 100)" "7"
check "and it names both numbers, so the drop is readable" \
    "$(pure_run 'echo "Test run with 40 tests in 3 suites passed"' 100 | grep -c '40 .*100')" "1"
check "a pure run that reported success and executed NOTHING is refused" \
    "$(pure_status 'echo "** TEST SUCCEEDED **"' 100)" "7"
check "a pure run that FAILED keeps its own status rather than the floor's" \
    "$(pure_status 'echo "Test run with 294 tests in 29 suites failed"; exit 65' 100)" "65"
check "the streamed output still reaches the terminal" \
    "$(pure_run 'echo "Test run with 294 tests in 29 suites passed"; echo A-LINE-FROM-THE-RUN' 100 | grep -c 'A-LINE-FROM-THE-RUN')" "1"

check "an injected command with no floor announces the skip rather than passing quietly" \
    "$(OVATION_UNLOCKED_COMMAND=true \
       OVATION_DIR_LOCK="$WORK/dir.lock" OVATION_FILE_LOCK="$WORK/file.lock" \
       OVATION_LOCK_POLL_INTERVAL=0.05 OVATION_LOCK_TIMEOUT=5 \
       OVATION_FLOCK_BIN="$SUITE_FLOCK" OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
       OVATION_TEST_COMMAND="true" "$TARGET" 2>&1 | grep -c 'Pure count check skipped')" "1"

# THE FLOOR IS A REAL NUMBER ON DISK, not only a seam. A committed floor that
# nothing reads is the same as no floor (L96).
check "the committed floor is a positive integer" \
    "$(grep -cE '^[1-9][0-9]*$' "$PWD/scripts/pure-test-floor.txt")" "1"
# Deliberately NOT asserted here: that the floor is at or below the real count.
# The runner itself checks exactly that on every run, against the count it just
# executed, and a second copy of the number in this file would be a place for
# the two to disagree (L41). A floor set too high fails the very next run.

check "a hosted run that executed tests passes" \
    "$(hosted_status 'echo "Test run with 5 tests in 1 suite passed"')" "0"
check "a hosted run that reported success and executed NOTHING is refused" \
    "$(hosted_status 'echo "** TEST SUCCEEDED **"')" "6"
check "and it says that nothing about the launch surface was verified" \
    "$(hosted_run 'echo "** TEST SUCCEEDED **"' | grep -c 'executed NO tests')" "1"
check "a hosted run that failed fails the whole run with its own status" \
    "$(hosted_status 'echo "Test run with 5 tests in 1 suite failed"; exit 7')" "7"
check "with no hosted command injected, the skip is announced rather than silent" \
    "$(OVATION_UNLOCKED_COMMAND=true \
       OVATION_DIR_LOCK="$WORK/dir.lock" OVATION_FILE_LOCK="$WORK/file.lock" \
       OVATION_LOCK_POLL_INTERVAL=0.05 OVATION_LOCK_TIMEOUT=5 \
       OVATION_FLOCK_BIN="$SUITE_FLOCK" OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
       OVATION_TEST_COMMAND="true" "$TARGET" 2>&1 | grep -c 'Hosted suite skipped')" "1"

check "a suite reading its own \$1 is caught" \
    "$(positional_readers "$STAGE")" "test-offender.sh"

# 2. AND IT DOES NOT FIRE ON THE LEGITIMATE USES EVERY SUITE HERE ALREADY MAKES.
rm -f "$STAGE/test-offender.sh"
cat > "$STAGE/test-innocent.sh" <<'INNOCENT'
#!/bin/bash
mentions() { if printf '%s' "$1" | grep -q "$2"; then echo yes; else echo no; fi; }
tree() {
    local d="$1"
    printf '%s\n' "$d"
}
cat > /dev/null <<'STUB'
case "\$1" in
  find-identity) echo none ;;
esac
STUB
    ( bash -c 'while [ -e "$1" ]; do sleep 1; done' _ /tmp/sentinel ) &
INNOCENT
check "and a suite using \$1 only inside its own functions is not" \
    "$(positional_readers "$STAGE")" ""

# 3. And the real tree is clean, which is the assertion that goes red the day
#    somebody writes the twelfth suite with a parameter.
check "no suite in this repository takes a suite level argument" \
    "$(positional_readers "$REPO_ROOT_SCRIPTS")" ""

# ---------------------------------------------------------------------------
# EVERY SHELL SUITE RUNS, AND THE RUN SAYS WHAT EACH ONE ANSWERED (ovation#139).
#
# The loop was `"$s" || exit $?`, so the FIRST suite that did not exit 0 ended
# the whole run. Two suites correctly answer CANNOT MEASURE (exit 2) when there
# is no compiled product, which is the normal state of a fresh checkout or
# worktree, and they sort early in the glob. Measured on 2026-09-08 in a fresh
# worktree: every shell suite passed when invoked on its own, and the runner
# reported four of them.
#
# CANNOT MEASURE is still the right verdict and the run still ends non-zero. What
# was wrong is that it ended the run, so the twenty six suites after it were
# never asked, and a stop and a real failure both came out as "non-zero" with the
# reader left to work out which by looking at where it stopped (L11, L98).
#
# THE VERDICTS, and why the locked phase treats two of them differently:
#   pass          the suite measured and was happy
#   fail          the suite measured and was not: nothing after it is worth
#                 running, so this stops the run before xcodebuild, as before
#   cannot measure the suite proved nothing either way, which is not a reason to
#                 refuse to measure everything else, so the run CONTINUES and the
#                 verdict is carried to the end
#
# The suite directory is a seam so these cases drive the loop with throwaway
# suites rather than the thirty three real ones, which would recurse through this
# very file (L245) and take minutes (L291).
# Guarded before any rm, as above (L5).
[ -n "$WORK" ] || exit 1
SUITES="$WORK/suites"
mkdir -p "$SUITES"

# Named so the glob order puts the awkward one FIRST, which is what the real
# defect needed: test-built-bundle-icon.sh sorts fifth of thirty three.
stage_suite() {
    printf '#!/bin/bash\necho "RAN-%s"\nexit %s\n' "$1" "$2" > "$SUITES/test-$1.sh"
    chmod +x "$SUITES/test-$1.sh"
}
clear_suites() { rm -f "$SUITES"/test-*.sh; }

shell_run() {
    OVATION_SHELL_SUITE_DIR="$SUITES" \
    OVATION_SHELL_SUITE_FLOOR="${1:-}" \
    OVATION_DIR_LOCK="$DIR_LOCK" OVATION_FILE_LOCK="$FILE_LOCK" \
    OVATION_LOCK_POLL_INTERVAL=0.05 OVATION_LOCK_TIMEOUT=5 \
    OVATION_TEST_COMMAND="true" \
    OVATION_HOSTED_TEST_COMMAND='echo "Test run with 5 tests in 1 suite passed"' \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
        "$TARGET" 2>&1
}
shell_status() { shell_run "${1:-}" >/dev/null 2>&1; printf '%s' "$?"; }

# 11a. A suite that cannot measure does not take the rest of the run with it.
clear_suites
stage_suite "a-cannot" 2
stage_suite "b-pass" 0
OUT11="$(shell_run)"; ST11=$?
check "a suite that cannot measure does not stop the ones after it" \
    "$(printf '%s' "$OUT11" | grep -c 'RAN-b-pass')" "1"
check "and the run's own verdict is CANNOT MEASURE, not a pass" "$ST11" "2"
check "and the summary names the suite that could not measure" \
    "$(printf '%s' "$OUT11" | grep -c 'test-a-cannot.sh')" "1"

# 11b. AND IT DOES NOT STOP THE LOCKED PHASE EITHER. This is the whole cost the
#      issue was filed about: a change touching only scripts or docs could not
#      learn whether anything else was green without first building both
#      configurations.
check "a suite that cannot measure does not stop the locked phase" \
    "$(printf '%s' "$OUT11" | grep -c 'Holding both locks')" "1"

# 11c. A FAILURE IS THE OTHER OUTCOME AND KEEPS ITS OLD BEHAVIOUR. Something is
#      actually broken, so nothing after it is worth the sibling locks.
clear_suites
stage_suite "a-fail" 3
stage_suite "b-pass" 0
OUT11C="$(shell_run)"; ST11C=$?
check "a failing suite fails the run with its own status" "$ST11C" "3"
check "and the summary names the suite that failed" \
    "$(printf '%s' "$OUT11C" | grep -c 'test-a-fail.sh')" "1"
check "and a failure still stops the run before the locked phase" \
    "$(printf '%s' "$OUT11C" | grep -c 'Holding both locks')" "0"
check "and the suites after a failure are not run" \
    "$(printf '%s' "$OUT11C" | grep -c 'RAN-b-pass')" "0"

# 11d. All green is still all green.
clear_suites
stage_suite "a-pass" 0
stage_suite "b-pass" 0
check "with every suite passing the run passes" "$(shell_status)" "0"

# 11e. A FAILURE OUTRANKS A CANNOT MEASURE, and neither hides the other. Two
#      outcomes reported as one is the thing this issue is about (L11).
clear_suites
stage_suite "a-cannot" 2
stage_suite "b-fail" 4
OUT11E="$(shell_run)"; ST11E=$?
check "a failure outranks a cannot measure in the verdict" "$ST11E" "4"
check "and both are still named, so neither is hidden by the other" \
    "$(printf '%s' "$OUT11E" | grep -c 'test-a-cannot.sh\|test-b-fail.sh')" "2"

# 11f. THE COUNT OF SUITES IS JUDGED, NOT ONLY THEIR VERDICTS (L288).
#      `[ -x "$s" ] || continue` skips a suite that lost its executable bit in
#      silence, and a glob that matches fewer files reads as a full green run.
#      The floor is what makes a DROP visible, exactly as the pure suite's is.
clear_suites
stage_suite "a-pass" 0
stage_suite "b-pass" 0
stage_suite "c-pass" 0
check "a run at the suite floor passes" "$(shell_status 3)" "0"
chmod -x "$SUITES/test-c-pass.sh"
OUT11F="$(shell_run 3)"; ST11F=$?
check "a suite that lost its executable bit is refused, not silently skipped" \
    "$([ "$ST11F" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names the count it ran against the floor" \
    "$(printf '%s' "$OUT11F" | grep -c '2 .*3')" "1"

# 11g. The floor is a real committed number, not only a seam (L96). It is NOT
#      compared against the real suite count here: the runner does exactly that
#      on every run, and a second copy of the number would be a place for the two
#      to disagree (L41).
check "the committed shell suite floor is a positive integer" \
    "$(grep -cE '^[1-9][0-9]*$' "$PWD/scripts/shell-suite-floor.txt")" "1"

# 11h. An injected suite directory with no floor says the count check was
#      skipped, rather than passing quietly, the same way the pure one does
#      (L98, L320).
clear_suites
stage_suite "a-pass" 0
check "an injected suite directory with no floor announces the skip" \
    "$(shell_run | grep -c 'Shell suite count check skipped')" "1"

# ---------------------------------------------------------------------------
# EVERY SEAM THE RUNNER HONOURS IS CLEARED BY THIS SUITE, not just the one that
# was caught being inherited.
#
# The seams are environment variables, so anything set in the shell that
# launched this suite is inherited by every runner spawned below and silently
# answers for them (L169, L439). OVATION_TEST_FLOOR was unset at the top for
# exactly that reason, discovered when exporting it made six cases fail.
#
# It happened again the moment the runner grew two more seams (ovation#139).
# Running this suite THROUGH the runner, with the pure and hosted commands
# injected on the outer run, made the case that asserts the hosted skip fail:
# its inner runner inherited a hosted command it was never given. A suite that
# sets some of a script's seams runs every unset one for real, and the real ones
# are the slow and the dangerous ones (L284).
#
# So the rule is the whole list rather than the instance (L30): every OVATION_
# name the runner reads is cleared here, and each helper sets back only what its
# own case needs. This assertion is what keeps the two in step when the next seam
# is added, since a seam nobody clears fails in exactly the runs that inherit it.
seams_honoured() {
    grep -oE 'OVATION_[A-Z_]+' "$TARGET" | sort -u
}
# Read from the unset STATEMENT, continuation lines and all, rather than from
# the whole file: every seam name necessarily appears elsewhere in here, in the
# helper that sets it, so a whole file search would answer yes to everything and
# the guard would pass while clearing nothing (L135, L245).
cleared_seams() {
    awk '/^unset /{p=1} p{print; if ($0 !~ /\\$/) exit}' scripts/test-run-tests.sh
}
seams_not_cleared() {
    local seam missing="" cleared
    cleared="$(cleared_seams)"
    while read -r seam; do
        printf '%s' "$cleared" | grep -qE "(^|[[:space:]])${seam}([[:space:]]|$)" \
            || missing="${missing}${seam} "
    done < <(seams_honoured)
    printf '%s' "${missing% }"
}
check "every seam the runner honours is cleared by this suite" \
    "$(seams_not_cleared)" ""

# ---------------------------------------------------------------------------
# THE XCODE PHASE CAN BE SKIPPED WHEN THE PUSH CANNOT HAVE CHANGED IT
# (ovation#22).
#
# Measured twice on 2026-09-05, four minutes each time: a push ran the hook, ran
# this runner, and waited on Overture's lock while a real Overture suite ran.
# Overture runs its suite constantly, so that is the normal case rather than bad
# luck, and most pushes in this phase change only documentation or shell scripts,
# which no xcodebuild run can be affected by.
#
# The DECISION is the hook's, because only the hook knows the pushed range. This
# is the seam it acts through, and the run says which of the two it did, because
# a run that skipped the Xcode suite must never look like one that passed it
# (L98, L11).
skip_run() {
    OVATION_SHELL_SUITE_DIR="$SUITES" \
    OVATION_SKIP_XCODE_PHASE="${1}" \
    OVATION_DIR_LOCK="$DIR_LOCK" OVATION_FILE_LOCK="$FILE_LOCK" \
    OVATION_LOCK_POLL_INTERVAL=0.05 OVATION_LOCK_TIMEOUT=5 \
    OVATION_TEST_COMMAND="echo THE-XCODE-PHASE-RAN" \
    OVATION_HOSTED_TEST_COMMAND='echo "Test run with 5 tests in 1 suite passed"' \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
        "$TARGET" 2>&1
}
clear_suites
stage_suite "a-pass" 0
OUT22A="$(skip_run 1)"; ST22A=$?
check "with the skip set the xcode phase does not run" \
    "$(printf '%s' "$OUT22A" | grep -c 'THE-XCODE-PHASE-RAN')" "0"
check "and the sibling locks are never taken for it" \
    "$(printf '%s' "$OUT22A" | grep -c 'Holding both locks')" "0"
check "and the shell suites still ran" \
    "$(printf '%s' "$OUT22A" | grep -c 'RAN-a-pass')" "1"
check "and the run says it skipped rather than reporting a full pass" \
    "$(printf '%s' "$OUT22A" | grep -c 'Xcode phase SKIPPED')" "1"
check "and it still passes" "$ST22A" "0"

# A FAILING SHELL SUITE STILL FAILS. The skip is about the locked phase only, and
# a skip that also swallowed the cheap checks would be the gate switching itself
# off on the pushes it is cheapest to check.
clear_suites
stage_suite "a-fail" 5
check "a failing shell suite still fails a skipped run" \
    "$(skip_run 1 >/dev/null 2>&1; printf '%s' "$?")" "5"

clear_suites
stage_suite "a-pass" 0
check "without the skip the xcode phase runs as before" \
    "$(skip_run "" | grep -c 'THE-XCODE-PHASE-RAN')" "1"

# ---------------------------------------------------------------------------
# THE WAIT SAYS WHO IS HOLDING THE LOCK AND HOW LONG IT WILL WAIT (ovation#22).
#
# It printed the two lock paths and nothing else, so a person watching a push sit
# there had no way to tell a busy sibling from a stuck lock, and a wait that
# cannot be told apart from a hang is the worse of the two (L110). The holder is
# knowable: Downbeat's lock directory carries an owner file, which Ovation writes
# itself, and Overture's file lock can be attributed by asking which process
# holds it.
clear_suites
stage_suite "a-pass" 0
mkdir -p "$DIR_LOCK"
printf 'downbeat:12345\n' > "$DIR_LOCK/owner"
OUT22W="$(TIMEOUT_OVERRIDE=1 run_runner)"
# AT LEAST once, not exactly once: since ovation#236 the holder is named when the
# wait starts AND again when it gives up, and "once" was never the point.
check "the wait names who holds the directory lock" \
    "$([ "$(printf '%s' "$OUT22W" | grep -c 'downbeat:12345')" -ge 1 ] && echo named || echo not-named)" "named"
check "and it says how long it will wait before giving up" \
    "$(printf '%s' "$OUT22W" | grep -cE 'up to [0-9]+ ?s')" "1"
rm -rf "$DIR_LOCK"

# THE DEADLINE IS REAL TIME, NOT A COUNT OF POLLS. It was `elapsed=elapsed+1`
# against a timeout in seconds, so the two were the same number only while the
# poll interval happened to be one second: at the interval these cases use, the
# runner gave up twenty times sooner than it said it would (L226).
#
# A LOWER BOUND ONLY. Asserting how long it took would be a measurement of what
# else this machine is running; asserting it waited at least as long as it said
# it would is a claim about the code (L224).
mkdir -p "$DIR_LOCK"
WAIT_FROM="$(date +%s)"
TIMEOUT_OVERRIDE=2 POLL_OVERRIDE=0.05 run_runner >/dev/null 2>&1
WAITED=$(( $(date +%s) - WAIT_FROM ))
check "it waits for the time it announced, not for a number of polls" \
    "$([ "$WAITED" -ge 2 ] && echo waited || echo "gave-up-after-${WAITED}s")" "waited"
rm -rf "$DIR_LOCK"

# ---------------------------------------------------------------------------
# A WAIT THAT ENDS SAYS WHAT HELD IT, AND EVERY WAIT IS RECORDED (ovation#236).
#
# Measured 2026-09-11: an Ovation run waited over eleven minutes behind seven back
# to back Overture runs and gave up with a message naming two paths. That reads as
# Ovation's fault, and it cannot tell a busy sibling from a lock a dead run left
# behind (L11, L148). And the wait was printed and lost, so how often and how long
# this happens stayed unknown.
#
# So giving up names the holders and how many different holders went ahead, a
# wait that succeeds says what it cost, and every attempt is recorded where the
# start of the next wait reads it back (L46: a record nothing reads is not worth
# writing).
gave_up_part() { printf '%s\n' "$1" | sed -n '/gave up waiting/,$p'; }

# 236a. Giving up names who held Downbeat's lock, not only where the lock is.
mkdir -p "$DIR_LOCK"
printf 'downbeat:12345\n' > "$DIR_LOCK/owner"
OUT236A="$(TIMEOUT_OVERRIDE=1 run_runner)"
check "giving up names who was holding Downbeat's lock" \
    "$(mentions "$(gave_up_part "$OUT236A")" 'downbeat:12345')" "yes"
rm -rf "$DIR_LOCK"

# 236b. And who held Overture's. The description is whatever the runner can
#       honestly say about the holder: a pid where it can ask the system, and
#       that it cannot see one where it cannot (the Linux job has no lsof).
    : > "$FILE_LOCK"
    HOLD_SENTINEL4="$WORK/hold-4"; : > "$HOLD_SENTINEL4"
    ( "$SUITE_FLOCK" "$FILE_LOCK" bash -c 'while [ -e "$1" ]; do sleep 0.02; done' _ "$HOLD_SENTINEL4" ) &
    HOLDER4=$!
    waited=0
    while "$SUITE_FLOCK" -n "$FILE_LOCK" true 2>/dev/null; do
        waited=$((waited+1)); [ "$waited" -gt 100 ] && break; sleep 0.05
    done
    OUT236B="$(TIMEOUT_OVERRIDE=1 run_runner)"
    # THIS IS ALSO THE CASE THAT FOUND THE ERRORS GOING NOWHERE (ovation#281).
    # After a busy attempt at Overture's lock the runner closed its descriptor
    # with `exec 9>&- 2>/dev/null`, and an exec with no command makes its
    # redirections PERMANENT: from the first busy attempt on, every error the run
    # printed went to /dev/null, this message and the reason a push was refused
    # included. A Downbeat-only hold never reaches that line, which is why 236a
    # alone could not see it.
    check "and who was holding Overture's lock" \
        "$(gave_up_part "$OUT236B" | grep -cE "Overture's lock .*: (held by pid|free, or held by a process this run cannot see)")" "1"
    # AND A HOLDER IS COUNTED ONCE, however its children come and go. The holder
    # here, like a real Overture run, starts short lived children the whole time
    # it holds the lock, so the list of processes holding it is different on
    # almost every poll; only the process that TOOK the lock is its identity.
    # Where the holder cannot be seen at all there is no one to count.
    check "and one holder whose children come and go is counted once" \
        "$(gave_up_part "$OUT236B" | grep -cE '(1 different holder|no holder this run could see) went ahead')" "1"
    rm -f "$HOLD_SENTINEL4"; wait "$HOLDER4" 2>/dev/null || true

# 236c. How many DIFFERENT holders went ahead, which is what tells a queue of busy
#       sibling runs from one stuck lock. The holder changes during the wait, and
#       the change is made on a condition, not a timer (L290): only once the
#       runner has printed the first holder.
mkdir -p "$DIR_LOCK"
printf 'overture-run-a:111\n' > "$DIR_LOCK/owner"
OUTFILE236C="$WORK/run-236c.out"; : > "$OUTFILE236C"
( TIMEOUT_OVERRIDE=3 run_runner > "$OUTFILE236C" 2>&1 ) &
RUNNER236C=$!
waited=0
until grep -q 'overture-run-a:111' "$OUTFILE236C"; do
    waited=$((waited+1)); [ "$waited" -gt 200 ] && break; sleep 0.05
done
printf 'overture-run-b:222\n' > "$DIR_LOCK/owner"
wait "$RUNNER236C" 2>/dev/null || true
check "and how many different holders went ahead of it" \
    "$(mentions "$(gave_up_part "$(cat "$OUTFILE236C")")" '2 different holders went ahead')" "yes"
rm -rf "$DIR_LOCK"

# 236d. A wait that SUCCEEDS says what went ahead of it, so a push's output shows
#       the wait rather than leaving it to be inferred from how long it took.
mkdir -p "$DIR_LOCK"
printf 'downbeat-run:333\n' > "$DIR_LOCK/owner"
OUTFILE236D="$WORK/run-236d.out"; : > "$OUTFILE236D"
( TIMEOUT_OVERRIDE=10 run_runner > "$OUTFILE236D" 2>&1 ) &
RUNNER236D=$!
waited=0
until grep -q 'downbeat-run:333' "$OUTFILE236D"; do
    waited=$((waited+1)); [ "$waited" -gt 200 ] && break; sleep 0.05
done
rm -rf "$DIR_LOCK"
wait "$RUNNER236D"; ST236D=$?
check "a wait that ends in both locks passes and says what went ahead of it" \
    "$ST236D:$(grep -c '1 different holder went ahead' "$OUTFILE236D")" "0:1"

# 236e. EVERY attempt is recorded, a wait of nothing included, because how often a
#       run waits is a fraction and needs the runs that did not (L396).
WAITLOG="$WORK/lock-waits.tsv"; rm -f "$WAITLOG"
OVATION_LOCK_WAIT_LOG="$WAITLOG" run_runner >/dev/null 2>&1
mkdir -p "$DIR_LOCK"
OVATION_LOCK_WAIT_LOG="$WAITLOG" TIMEOUT_OVERRIDE=1 run_runner >/dev/null 2>&1
rm -rf "$DIR_LOCK"
check "a run that got the locks at once is recorded as acquired" \
    "$(sed -n 1p "$WAITLOG" 2>/dev/null | cut -f3)" "acquired"
check "and a run that gave up is recorded as gave-up" \
    "$(sed -n 2p "$WAITLOG" 2>/dev/null | cut -f3)" "gave-up"

# 236f. A TEST RUN CAN NEVER WRITE DAN'S REAL RECORD. It is written by real runs
#       and by a run that names a record; an injected run that names none writes
#       nothing, measured where the default would land rather than trusted (L2,
#       L322).
FAKEHOME="$WORK/fakehome"; rm -rf "$FAKEHOME"; mkdir -p "$FAKEHOME"
HOME="$FAKEHOME" run_runner >/dev/null 2>&1
check "an injected run that names no record writes nothing under HOME" \
    "$(find "$FAKEHOME" -type f | wc -l | tr -d ' ')" "0"

# 236g. And the record is read back: the start of a wait quotes recent waits, so
#       the number that used to be lost is in front of the person waiting.
printf '1789000000\t0\tacquired\t0\n1789000100\t40\tacquired\t1\n1789000200\t700\tgave-up\t3\n' > "$WAITLOG"
mkdir -p "$DIR_LOCK"
OUT236G="$(OVATION_LOCK_WAIT_LOG="$WAITLOG" TIMEOUT_OVERRIDE=1 run_runner)"
rm -rf "$DIR_LOCK"
check "the start of a wait quotes the longest recent wait from the record" \
    "$(mentions "$OUT236G" 'longest 700s')" "yes"


# ---------------------------------------------------------------------------
# THE PROJECT IS GENERATED WHEN IT IS ABSENT, AND ONLY THEN (ovation#151).
#
# `Ovation.xcodeproj` is gitignored and generated from project.yml, so a fresh
# clone, Dan's second Mac and any CI runner start with none. What that gave was
# xcodebuild's own "Ovation.xcodeproj does not exist", which names the symptom
# rather than the missing step.
# The recursive delete below is under $WORK, checked rather than trusted: an
# empty $WORK makes it a delete at the root, and `set -u` does not catch it
# because an empty parameter is set (L5).
[ -n "${WORK:-}" ] || { echo "REFUSED: no temp directory"; exit 1; }
PROJ="$WORK/proj"; rm -rf "$PROJ"; mkdir -p "$PROJ"
GEN_LOG="$PROJ/generated.log"
printf '#!/bin/bash\necho "GENERATOR-RAN" >> "%s"\nmkdir -p "%s/Ovation.xcodeproj"\n' \
    "$GEN_LOG" "$PROJ" > "$PROJ/xcodegen"
chmod +x "$PROJ/xcodegen"

run_with_project() {
    OVATION_DIR_LOCK="$DIR_LOCK" OVATION_FILE_LOCK="$FILE_LOCK" \
    OVATION_LOCK_TIMEOUT=2 OVATION_LOCK_POLL_INTERVAL=0.05 \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" \
    OVATION_TEST_COMMAND="true" OVATION_UNLOCKED_COMMAND="true" \
    OVATION_XCODE_PROJECT="$1" OVATION_XCODEGEN="$2" \
        "./$TARGET" 2>&1
}

OUT151A="$(run_with_project "$PROJ/Ovation.xcodeproj" "$PROJ/xcodegen")"; ST151A=$?
check "a run with no project generates one and succeeds" "$ST151A" "0"
check "and it says it made one rather than doing it silently" \
    "$(mentions "$OUT151A" "which was absent")" "yes"
check "and the generator actually ran" \
    "$([ -f "$GEN_LOG" ] && echo ran || echo no)" "ran"

# AND IT IS NOT REGENERATED WHEN IT IS THERE. Rewriting the project file
# underneath an open Xcode is the reason this is not simply run every time.
rm -f "$GEN_LOG"
OUT151B="$(run_with_project "$PROJ/Ovation.xcodeproj" "$PROJ/xcodegen")"; ST151B=$?
check "a run with a project present leaves it alone" \
    "$([ -f "$GEN_LOG" ] && echo regenerated || echo untouched)" "untouched"

# NO GENERATOR AND NO PROJECT REFUSES, naming the step rather than the symptom.
OUT151C="$(run_with_project "$PROJ/absent.xcodeproj" "$PROJ/no-such-xcodegen")"; ST151C=$?
check "no project and no generator refuses" \
    "$([ "$ST151C" -ne 0 ] && echo refused || echo allowed)" "refused"
check "and it names how to install the generator" \
    "$(mentions "$OUT151C" "brew install xcodegen")" "yes"

# A GENERATOR THAT EXITS 0 AND WRITES NOTHING is caught here rather than one step
# later as xcodebuild's own error about a missing project (L100).
printf '#!/bin/bash\nexit 0\n' > "$PROJ/quiet-xcodegen"
chmod +x "$PROJ/quiet-xcodegen"
OUT151D="$(run_with_project "$PROJ/still-absent.xcodeproj" "$PROJ/quiet-xcodegen")"; ST151D=$?
check "a generator that reports success and writes nothing is refused" \
    "$([ "$ST151D" -ne 0 ] && echo refused || echo allowed)" "refused"


# AND EVERY ROUTE TO xcodebuild GOES THROUGH THE SAME HELPER (ovation#151).
#
# A SCAN, and it is honest about what a scan can do: it cannot see whether the
# helper is CALLED before the build, only that the script consults it at all
# (L621). What it does catch is the case that actually happens, a new script
# reaching xcodebuild by its own route with no idea a project has to exist first,
# which is how build-install.sh was left out of the first version of this fix.
uses_helper() {
    grep -q "ensure-xcode-project.sh" "$1" && echo yes || echo no
}
for reaching in scripts/run-tests.sh scripts/build-install.sh; do
    check "$(basename "$reaching") consults the shared project helper" \
        "$(uses_helper "$reaching")" "yes"
done


# ---------------------------------------------------------------------------
# THE FLOOR HAS TO MOVE WITH THE SUITE (ovation#157).
#
# It was committed at 294 and was still 294 with the suite executing 422, so it
# could not see a run that lost a quarter of itself, which is the partial run it
# exists to refuse (L63, L354). Nothing made it move; that is what these cases
# are for. The count is injected, so none of this runs a real suite.
counted_run() {
    # counted_run <count-the-command-prints> <floor>
    OVATION_DIR_LOCK="$DIR_LOCK" OVATION_FILE_LOCK="$FILE_LOCK" \
    OVATION_LOCK_TIMEOUT=2 OVATION_LOCK_POLL_INTERVAL=0.05 \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" \
    OVATION_UNLOCKED_COMMAND="true" \
    OVATION_TEST_FLOOR="$2" \
    OVATION_HOSTED_TEST_COMMAND='echo "Test run with 5 tests in 1 suite passed"' \
    OVATION_TEST_COMMAND="echo 'Test run with $1 tests in 1 suite passed'" \
    OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
        "./$TARGET" 2>&1
}
counted_status() { counted_run "$@" >/dev/null 2>&1; printf '%s' "$?"; }

check "a run that matches its floor exactly passes" "$(counted_status 100 100)" "0"
check "a run BELOW its floor is refused" "$(counted_status 60 100)" "7"

OUT157="$(counted_run 140 100)"
check "a run ABOVE its floor is refused too, because a floor that never moves stops being one" \
    "$(counted_status 140 100)" "7"
check "and it says the tests were ADDED rather than reporting a loss" \
    "$(mentions "$OUT157" "being ADDED")" "yes"
check "and it gives the exact command, with the real number in it" \
    "$(mentions "$OUT157" "140 > ")" "yes"


# ---------------------------------------------------------------------------
# A BUILD RUNNING OUTSIDE THE LOCK IS SAID OUT LOUD (ovation#156).
#
# The lock is voluntary and lives in this script, so any route to xcodebuild that
# is not this one goes around it, and neither run can tell. This does not prevent
# that; it removes the part where nothing notices. The question is asked at the
# one moment it is unambiguous: both locks are held and this run has not started
# building, so anything already building belongs to nobody's lock.
lister_run() {
    OVATION_DIR_LOCK="$DIR_LOCK" OVATION_FILE_LOCK="$FILE_LOCK" \
    OVATION_LOCK_TIMEOUT=2 OVATION_LOCK_POLL_INTERVAL=0.05 \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" \
    OVATION_TEST_COMMAND="true" OVATION_UNLOCKED_COMMAND="true" \
    OVATION_HOSTED_TEST_COMMAND="$HOSTED_PASSES" \
    OVATION_XCODEBUILD_LISTER="$1" \
    OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
        "./$TARGET" 2>&1
}

OUT156A="$(lister_run 'printf "4321\n8765\n"')"
check "an xcodebuild running while both locks are held is reported" \
    "$(mentions "$OUT156A" "started outside them")" "yes"
check "and it names how many" "$(mentions "$OUT156A" "2 xcodebuild")" "yes"
check "and it names the pids, so the other run can actually be found" \
    "$(mentions "$OUT156A" "pid 4321")" "yes"
check "and it does NOT refuse, because a false positive must not block a push" \
    "$(lister_run 'printf "4321\n" ' >/dev/null 2>&1; printf '%s' "$?")" "0"

OUT156B="$(lister_run 'true')"
check "a quiet machine says nothing about other builds" \
    "$(mentions "$OUT156B" "started outside them")" "no"
check "and it still ran, so the quiet case is not a skipped run" \
    "$(mentions "$OUT156B" "Holding both locks")" "yes"

# AND ANOTHER WORKTREE'S PURE SUITE IS NOT ACCUSED (ovation#271). It takes no
# sibling lock by design now, so it is outside them legitimately, and a warning
# that fires on the designed case is one people learn to read past (L36).
#
# A REAL PROCESS carrying the pure scheme's command line, so the runner is judged
# on what `ps` reports rather than on a string this suite hands it. It is killed
# by this suite, not left to a timer (L290).
( exec -a "xcodebuild -project Ovation.xcodeproj -scheme OvationCore -destination platform=macOS test" sleep 300 ) &
FAKE_PURE=$!
waited=0
until ps -o command= -p "$FAKE_PURE" 2>/dev/null | grep -q 'scheme OvationCore'; do
    waited=$((waited+1)); [ "$waited" -gt 100 ] && break; sleep 0.05
done
OUT156C="$(lister_run "printf '%s\n' $FAKE_PURE")"
check "another Ovation pure suite building is not reported as outside the locks" \
    "$(mentions "$OUT156C" "started outside them")" "no"
OUT156D="$(lister_run "printf '%s\n' $FAKE_PURE 4321")"
check "but any other xcodebuild beside it still is" \
    "$(mentions "$OUT156D" "1 xcodebuild")" "yes"
kill "$FAKE_PURE" 2>/dev/null; wait "$FAKE_PURE" 2>/dev/null || true

# ---------------------------------------------------------------------------
# THE RUNNER SAYS WHEN THIS MAC'S XCODE IS NOT THE ONE CI BUILDS WITH
# (ovation#270).
#
# The push gate is supposed to predict CI, and it can only do that while the two
# compile with the same Xcode. CI now selects the version .xcode-version names;
# this Mac builds with whatever is selected here, and a green run on a different
# compiler is not evidence the merge will build (L376). So the runner reads the
# same pin and says, on every run that builds, which of the three it found.
#
# IT NEVER CHANGES THE VERDICT. A person mid Xcode upgrade must still be able to
# run the suite, and a refusal here would be a gate people learn to skip (L378).
# Every case below asserts the exit code as well as the sentence, so a note that
# started failing runs would be caught.
# ---------------------------------------------------------------------------
XCODE_PIN="$WORK/xcode-version"
printf '26.6\n' > "$XCODE_PIN"
xcodebuild_reporting() {
    # xcodebuild_reporting <path> <version>: a stub whose -version says <version>.
    printf '#!/bin/bash\nprintf "Xcode %s\\nBuild version 17F113\\n"\n' "$2" > "$1"
    chmod +x "$1"
}
xcodebuild_reporting "$WORK/xcodebuild-same" "26.6"
xcodebuild_reporting "$WORK/xcodebuild-older" "26.4.1"

run_with_xcode() {
    # run_with_xcode <xcodebuild> [pin file]
    # LOCAL, so the override ends with the case rather than answering for every
    # later one (L439).
    local XCODEBUILD_OVERRIDE="$1" XCODE_PIN_OVERRIDE="${2:-$XCODE_PIN}"
    run_runner
}

OUT_XSAME="$(run_with_xcode "$WORK/xcodebuild-same")"; ST_XSAME=$?
check "a Mac on CI's Xcode runs as before" "$ST_XSAME" "0"
check "and says it is building with the version CI builds with" \
    "$(mentions "$OUT_XSAME" "Xcode 26.6, the version CI builds with")" "yes"

OUT_XOLD="$(run_with_xcode "$WORK/xcodebuild-older")"; ST_XOLD=$?
check "a Mac on a different Xcode is not refused" "$ST_XOLD" "0"
check "and it names both versions, this Mac's and CI's" \
    "$(printf '%s' "$OUT_XOLD" | grep -c 'Xcode 26.4.1.*Xcode 26.6')" "1"
check "and it says what the difference costs, rather than only that there is one" \
    "$(mentions "$OUT_XOLD" "does not show CI")" "yes"

OUT_XNONE="$(run_with_xcode "$WORK/no-such-xcodebuild")"; ST_XNONE=$?
check "a Mac where the Xcode version cannot be read is not refused" "$ST_XNONE" "0"
check "and it says the comparison was not made, rather than staying silent" \
    "$(mentions "$OUT_XNONE" "could not tell which Xcode")" "yes"

OUT_XNOPIN="$(run_with_xcode "$WORK/xcodebuild-same" "$WORK/no-such-pin")"
check "a missing pin names the pin file it could not read" \
    "$(mentions "$OUT_XNOPIN" "$WORK/no-such-pin")" "yes"

# A RUN THAT BUILDS NOTHING SAYS NOTHING ABOUT A COMPILER. The shell only path is
# what CI's Linux job runs, where there is no Xcode at all, and a note there
# would be one every Linux log carries and nobody reads (L36).
OUT_XSKIP="$(OVATION_SKIP_XCODE_PHASE=1 run_with_xcode "$WORK/xcodebuild-older")"
check "a run that skips the Xcode phase makes no claim about Xcode" \
    "$(printf '%s' "$OUT_XSKIP" | grep -c 'Xcode 26')" "0"


# EVERY INVOCATION OF THE REAL RUNNER SETS BOTH MACHINE SEAMS (ovation#152).
#
# An invocation that leaves `OVATION_FLOCK_BIN` or `OVATION_XCODE_PROJECT` unset
# runs the real ones, and the real ones are whatever this machine happens to have:
# Homebrew's flock, and a project that exists here and on no fresh clone. The
# Linux job found both, in two separate rounds, because the failure moves to the
# next unset seam as each is fixed. This is the seam clearing assertion above, one
# level in (L284).
#
# READ BY LOOKING BACK FROM THE INVOCATION, in python rather than awk: the first
# version parsed shell functions with awk, mangled its own regex, and reported
# every helper plus several fragments of syntax as offenders. A guard whose output
# is unreadable is one nobody can act on (L148).
TARGET_SUITE="scripts/test-run-tests.sh"
check "every invocation of the real runner sets flock and the project" \
    "$(python3 - "$TARGET_SUITE" <<'PYSEAMS'
import sys
lines = open(sys.argv[1]).read().splitlines()
# ASSEMBLED FROM PIECES so this program contains no literal instance of what it
# looks for. Written whole, it matched its own source and reported itself as an
# offender, which is the same trap `check-ported-artifacts.sh` records (L245).
needle = "$TARGET" + '" 2>&1'
missing = []
for index, line in enumerate(lines):
    if needle not in line:
        continue
    window = "\n".join(lines[max(0, index - 15):index + 1])
    for seam in ("OVATION_FLOCK_BIN", "OVATION_XCODE_PROJECT"):
        if seam not in window:
            missing.append("line %d:%s" % (index + 1, seam))
print(" ".join(missing))
PYSEAMS
)" ""


harness_end
