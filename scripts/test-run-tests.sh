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
      OVATION_LOCK_WAIT_LOG OVATION_LOCK_WAIT_RECORD_STAGED OVATION_RENDER_RECORD_STAGED \
      OVATION_XCODEBUILD OVATION_XCODE_VERSION_FILE \
      OVATION_XCODE_NOTICE_STATE \
      OVATION_DEFAULTS_DOMAINS_COMMAND \
      OVATION_PROJECT_CREATE_POLL OVATION_PROJECT_CREATE_TIMEOUT \
      OVATION_REPO_ROOT \
      OVATION_ONLY_TESTING OVATION_PROJECT_CURRENT_COMMAND OVATION_REGENERATE_COMMAND \
      OVATION_REGENERATE_WAIT \
      OVATION_SHELL_SUITES OVATION_SHOT_DIR TEST_RUNNER_OVATION_SHOT_DIR \
      OVATION_APP_CHANGES_ROOT OVATION_APP_CHANGES_BASE OVATION_APP_BUILD_COMMAND

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

# ovation#433. Describing the file lock's holder lives in lib/file-lock.sh, so
# the rule that one holder is one holder however many descriptors its children
# inherit is measured directly rather than only through a whole runner wait.
# shellcheck source=lib/file-lock.sh
. "$PWD/scripts/lib/file-lock.sh"

harness_begin "test runner lock tests" 292

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

# THE PREFERENCE DOMAINS THE RUNNER BRACKETS ARE A FILE HERE (ovation#263). The
# real list is the whole Mac's, and another checkout running its tests beside
# this suite can add to it, so a case reading it would be judged on somebody
# else's run (L375). Each line of the file is one domain, the way `defaults
# domains` separates them once split.
DOMAINS="$WORK/domains.txt"
printf 'com.apple.finder\n' > "$DOMAINS"
DOMAINS_LISTER="cat '$DOMAINS'"

# THE XCODE VERSION SEAMS ARE SET HERE TOO (ovation#270), to paths that are not
# there unless a case overrides them. Left unset, every case would run the real
# xcodebuild to ask its version and read the real pin, which is this machine's
# answer to a question no case but the Xcode ones is asking (L284).
#
# OVATION_XCODE_NOTICE_STATE IS ONE OF THEM (ovation#320), and it is the seam this
# suite would most damage by leaving real: the runner REMEMBERS there which pair
# of versions it last explained, and its default is Dan's own machine state. A
# case that did not set it would suppress the explanation on his next real run,
# and every case here would be judged against whatever his last run left behind.
run_runner() {
    OVATION_XCODEBUILD="${XCODEBUILD_OVERRIDE:-$WORK/no-xcodebuild-given}" \
    OVATION_XCODE_VERSION_FILE="${XCODE_PIN_OVERRIDE:-$WORK/no-xcode-pin-given}" \
    OVATION_XCODE_NOTICE_STATE="${XCODE_NOTICE_STATE_OVERRIDE:-$WORK/shared-notice-state}" \
    OVATION_DEFAULTS_DOMAINS_COMMAND="${DOMAINS_OVERRIDE:-$DOMAINS_LISTER}" \
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

# CONDITIONS THE CASES WAIT ON, for harness_wait_for (ovation#303). Every wait in
# this suite used to break out of a hand written loop after a fixed number of
# polls and carry on as if the condition held, so a wait that ran out was silent
# and the case after it failed on an assertion about something never staged. A
# wait is now an assertion that fails by name.
staged_file_lock_held() {
    ! "$SUITE_FLOCK" -n "$FILE_LOCK" true 2>/dev/null
}
file_mentions() {
    grep -q "$2" "$1" 2>/dev/null
}
# Not `ps | grep -q`: under pipefail a grep ending early fails the ps (L183).
process_shows() {
    [[ "$(ps -o command= -p "$1" 2>/dev/null)" == *"$2"* ]]
}

# 1. Nothing held: it runs, and it runs the command it was given.
OUT1="$(run_runner "echo THE-COMMAND-RAN; $HOSTED_PASSES")"; ST1=$?
check "with neither lock held the runner succeeds" "$ST1" "0"
check "and it actually ran the command" \
    "$(printf '%s' "$OUT1" | grep -c "THE-COMMAND-RAN")" "1"

# 1a. ovation#373. THE COMPILER'S SYMPTOM GETS THE RULE BESIDE IT. OvationTests
#     compiles the app's sources in and has no host, so `@testable import Ovation`
#     in one of its files names a module nothing builds, and the error names the
#     symptom rather than the missing step: twenty minutes went on a full rebuild
#     chasing the wrong cause. The rule is enforced at push time by
#     test-project-configuration.sh; this says it the moment the error appears.
OUT1A="$(PURE_OVERRIDE="echo \"/x/OvationTests/NewThingTests.swift:3:8: error: Unable to resolve module dependency: 'Ovation'\"; exit 65" run_runner)"; ST1A=$?
check "a pure run failing on the app module import still fails" \
    "$([ "$ST1A" -ne 0 ] && echo failed || echo passed)" "failed"
check "and it names the fix, deleting the import, beside the error" \
    "$(printf '%s' "$OUT1A" | grep -c 'delete the line @testable import Ovation')" "1"
OUT1A2="$(PURE_OVERRIDE='echo "error: cannot find Foo in scope"; exit 65' run_runner)"
check "and an unrelated compile error gets no such advice" \
    "$(printf '%s' "$OUT1A2" | grep -c 'delete the line @testable import Ovation')" "0"

# 1c. ovation#383. THE SCREENSHOT SUITES RUN ON EVERY RUN. They did nothing unless a
#     folder was named for them and nothing named one, so every run and every CI run
#     executed nothing while reporting a pass, and a capture that crashed the test
#     process shipped unseen (L98, L606). The runner now names a folder every time:
#     a fresh temporary one, unless the caller names its own.
OUT1C="$(run_runner 'echo "SHOT-DIR=[${TEST_RUNNER_OVATION_SHOT_DIR:-}]"; echo "Test run with 5 tests in 1 suite passed"')"
SHOT_SEEN="$(grep -oE 'SHOT-DIR=\[[^]]*\]' <<< "$OUT1C" | head -1)"
check "the hosted suite is always given a folder to capture into" \
    "$([ "$SHOT_SEEN" != "SHOT-DIR=[]" ] && [ -n "$SHOT_SEEN" ] && echo given || echo "not given")" "given"
OUT1C2="$(OVATION_SHOT_DIR="$WORK/named-shots" run_runner 'echo "SHOT-DIR=[${TEST_RUNNER_OVATION_SHOT_DIR:-}]"; echo "Test run with 5 tests in 1 suite passed"')"
check "and a folder the caller names is the one used" \
    "$(grep -c "SHOT-DIR=\[$WORK/named-shots\]" <<< "$OUT1C2")" "1"
check "and it says where the pictures went" "$(grep -c 'screenshots' <<< "$OUT1C2")" "1"

# 1b. ovation#492. A CHILD THAT OUTLIVES THE RUNNER DOES NOT KEEP THE LOCK. The
#     lock is a DESCRIPTOR, and a numbered descriptor opened by `exec` is inherited
#     by every process started while it is held (L441), so a survivor of the hosted
#     suite held Overture's lock for ever after the run that took it had gone, and
#     wedged all three apps' testing. The child records its own pid and is stopped
#     by that pid, never by matching its command text (L1011).
CHILD_PID_FILE="$WORK/outliving-child.pid"
rm -f "$CHILD_PID_FILE"
OUT1B="$(run_runner "sleep 30 >/dev/null 2>&1 & echo \$! > '$CHILD_PID_FILE'; $HOSTED_PASSES")"; ST1B=$?
CHILD_PID="$(cat "$CHILD_PID_FILE" 2>/dev/null)"
check "a run whose hosted suite leaves a child running still succeeds" "$ST1B" "0"
check "and once it has exited the file lock is free, although the child is still alive" \
    "$( if [ -n "$CHILD_PID" ] && kill -0 "$CHILD_PID" 2>/dev/null; then \
          staged_file_lock_held && echo held || echo free; else echo "no child"; fi )" "free"
[ -n "$CHILD_PID" ] && kill "$CHILD_PID" 2>/dev/null

# 2. AND IT RELEASED BOTH. A runner that leaves a lock planted blocks the next
#    run of a DIFFERENT app, which is the failure this whole thing exists to stop.
check "the directory lock was released" \
    "$([ -e "$DIR_LOCK" ] && echo held || echo free)" "free"

# 3. Downbeat's lock held: Ovation must WAIT and then refuse, not barge in.
mkdir -p "$DIR_LOCK"
OUT3="$(run_runner)"; ST3=$?
check "Downbeat's directory lock stops Ovation running" \
    "$([ "$ST3" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
mentions() { if grep -q "$2" <<< "$1"; then echo yes; else echo no; fi; }
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
    harness_wait_for "Overture's lock to be taken by HOLDER" 100 0.05 staged_file_lock_held
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

# 6b. A RUN TOLD TO STOP STOPS (ovation#274).
#
#     The trap was `trap release_locks EXIT INT TERM`, and a trap on INT or TERM
#     that only cleans up RETURNS to the script: the runner let go of its locks
#     and carried on, back to waiting for them or on into xcodebuild. Seen
#     2026-09-13: two push gate runs stopped with an ordinary signal were still
#     alive and still waiting seconds later, and needed `kill -9`, which skips the
#     trap entirely and can leave Downbeat's lock planted for every sibling.
#
#     So each case asserts the run has EXITED, with the conventional status, and
#     only then that the locks are free. Free locks alone are what the broken
#     trap also produced, so asserting only that would pass on the defect (L140).
#
#     THE RUNNER IS STARTED WITH INT RESTORED. A background job in a shell with
#     no job control starts with SIGINT IGNORED, and a signal ignored on entry
#     cannot be trapped, so without this the INT case would measure bash's rule
#     for background jobs rather than the runner. Every seam is set on the one
#     command, as every other invocation here does (ovation#152).
#
#     AND IN A PROCESS GROUP OF ITS OWN, so INT can be sent the way Ctrl+C sends
#     it: to the runner AND the command it is waiting on. The first version sent
#     INT to the runner's pid alone and failed on one of CI's two identical Linux
#     jobs, still running, while passing on this Mac in every run. Measured here,
#     bash 3.2 ran the INT trap in 12 of 12 trials whether INT went to the pid or
#     the group. Bash 5 on Linux applies its rule for a foreground command that
#     exits normally after INT, which is to take the command as having handled
#     it, so a pid-only INT arriving mid `sleep` was absorbed or not by timing.
#     A person's Ctrl+C reaches the whole group, and that is the stop this case
#     is about. TERM stays pid-only below: `kill` sends it that way, and it is
#     not subject to that rule.
start_stoppable_runner() {
    OVATION_DIR_LOCK="$DIR_LOCK" \
    OVATION_FILE_LOCK="$FILE_LOCK" \
    OVATION_LOCK_TIMEOUT=120 \
    OVATION_LOCK_POLL_INTERVAL=0.05 \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" \
    OVATION_TEST_COMMAND=true \
    OVATION_HOSTED_TEST_COMMAND="$2" \
    OVATION_UNLOCKED_COMMAND=true \
    OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
    OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
        python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.setpgrp(); os.execv(sys.argv[1], sys.argv[1:])' \
        "./$TARGET" > "$1" 2>&1 &
    STOPPABLE_PID=$!
}
# Waits for the run to exit, on the condition rather than for a fixed time, and
# sets STOPPED to its status or `still-running`. A run still alive after the
# budget is the defect, so it is killed here rather than left behind this suite
# (L290). IT SETS A VARIABLE AND IS NEVER CALLED INSIDE `$(...)`: a substitution
# is a subshell, the runner is not ITS child, and `wait` there answers nonsense
# about a process it never started (the first version read -1).
stopped_status() {
    local pid="$1" polls=0
    while kill -0 "$pid" 2>/dev/null && [ "$polls" -lt 200 ]; do
        polls=$((polls+1)); sleep 0.05
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
        STOPPED=still-running
        return
    fi
    wait "$pid" 2>/dev/null
    STOPPED=$?
}
wait_for_line() {
    harness_wait_for "'$2' in $(basename "$1")" 200 0.05 file_mentions "$1" "$2"
}

# 6b-i. INT while WAITING on Overture's held lock: the case the issue saw.
#        Indented like every other holder in this file, because the suite level
#        argument scan below reads unindented lines and the holder's inner `$1`
#        belongs to its own shell.
    rm -rf "$DIR_LOCK"
    : > "$FILE_LOCK"
    HOLD_SENTINEL274="$WORK/hold-274"; : > "$HOLD_SENTINEL274"
    ( "$SUITE_FLOCK" "$FILE_LOCK" bash -c 'while [ -e "$1" ]; do sleep 0.02; done' _ "$HOLD_SENTINEL274" ) &
    HOLDER274=$!
    harness_wait_for "Overture's lock to be taken by HOLDER274" 100 0.05 staged_file_lock_held
    OUT274A="$WORK/run-274a.out"
    start_stoppable_runner "$OUT274A" "$HOSTED_PASSES"
    wait_for_line "$OUT274A" 'Waiting for both test locks'
    # To the whole group, as Ctrl+C does: the runner and whatever it is waiting on.
    kill -INT -- "-$STOPPABLE_PID"
    stopped_status "$STOPPABLE_PID"
    check "a run interrupted while waiting for a lock exits, with status 130" \
        "$STOPPED" "130"
    check "and it left Downbeat's lock free behind it" \
        "$([ -e "$DIR_LOCK" ] && echo held || echo free)" "free"
    rm -f "$HOLD_SENTINEL274"; wait "$HOLDER274" 2>/dev/null || true
    # A killed broken run can leave the directory lock planted, which would
    # then answer for the next case.
    rm -rf "$DIR_LOCK"

# 6b-ii. TERM while HOLDING BOTH, inside the hosted suite. The signal is handled
#        when the command it is running returns, and the broken trap then ran
#        on to report that suite's verdict as the run's. The hosted command
#        blocks on a sentinel this case removes, so nothing here is timed.
rm -rf "$DIR_LOCK"
IN_HOSTED="$WORK/in-hosted-274"; HOLD_HOSTED="$WORK/hold-hosted-274"
rm -f "$IN_HOSTED"; : > "$HOLD_HOSTED"
OUT274B="$WORK/run-274b.out"
start_stoppable_runner "$OUT274B" "touch '$IN_HOSTED'; while [ -e '$HOLD_HOSTED' ]; do sleep 0.02; done; $HOSTED_PASSES"
harness_wait_for "the hosted command to start inside both locks (6b-ii)" 200 0.05 test -e "$IN_HOSTED"
kill -TERM "$STOPPABLE_PID"
rm -f "$HOLD_HOSTED"
stopped_status "$STOPPABLE_PID"
check "a run terminated while holding both locks exits, with status 143" \
    "$STOPPED" "143"
check "and Downbeat's lock is free" \
    "$([ -e "$DIR_LOCK" ] && echo held || echo free)" "free"
check "and Overture's lock is free" \
    "$("$SUITE_FLOCK" -n "$FILE_LOCK" true 2>/dev/null && echo free || echo held)" "free"

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
    harness_wait_for "Overture's lock to be taken by HOLDER2" 100 0.05 staged_file_lock_held

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
    harness_wait_for "Overture's lock to be taken by HOLDER3" 100 0.05 staged_file_lock_held
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
#
# A QUOTED HEREDOC'S BODY IS DATA AND IS NOT READ (ovation#344). `<<'SH' ... SH`
# passes its body through untouched, so nothing in it is ever read by the suite's
# own shell: a suite that STAGES a stub inspecting the arguments IT was given is
# innocent, and two of them, test-report-finding.sh and test-output-privacy.sh,
# tripped this rule on their stub's body while ovation#339 was built. An UNQUOTED
# heredoc is a different thing and is still read, because its body IS expanded by
# the suite's own shell, so a $1 in it is a genuine read of the suite's first
# argument. The exemption is written as that reason rather than as "a heredoc"
# (L362, L615).
#
# A heredoc that is never terminated is REPORTED. Everything after the opener
# goes unread, and a file nothing was read from otherwise reports exactly like a
# clean one, which is the way this kind of tracking fails quietly (L98, L11).
# The candidate terminator is matched with its leading whitespace stripped, which
# is what `<<-` means and is looser than a plain heredoc allows: ending the skip
# EARLY costs a false positive somebody reads, and ending it late costs a file
# nobody checks (L93).
#
# EACH FINDING NAMES THE LINE, as `<suite>:<line>:<the line>`. Naming only the
# file sent the reader hunting for a parameter through a suite that takes none,
# with the remedy invisible from what the message said (L11, L148).
positional_readers() {
    local dir="$1" f
    for f in "$dir"/test-*.sh; do
        [ -f "$f" ] || continue
        awk -v name="$(basename "$f")" -v q="'" '
            BEGIN {
                single = "<<-?[ \t]*" q "[A-Za-z_][A-Za-z0-9_]*" q
                double = "<<-?[ \t]*\"[A-Za-z_][A-Za-z0-9_]*\""
            }
            inhd {
                candidate = $0
                sub(/^[ \t]+/, "", candidate)
                if (candidate == term) inhd = 0
                next
            }
            {
                opened = 0
                if (match($0, single) || match($0, double)) {
                    term = substr($0, RSTART, RLENGTH)
                    sub("^<<-?[ \t]*", "", term)
                    gsub(q, "", term)
                    gsub("\"", "", term)
                    opened = 1
                    openedat = NR
                }
                if ($0 ~ /^[^ \t#]/ \
                    && $0 !~ /[A-Za-z_][A-Za-z0-9_]*\(\)/ \
                    && $0 ~ /(^|[^\\])\$\{?1([^0-9]|$)/) {
                    printf "%s:%d:%s\n", name, NR, $0
                }
                if (opened) inhd = 1
            }
            END {
                if (inhd) {
                    printf "%s:%d:a quoted heredoc opened here is never terminated, so the rest of this file was never read\n", name, openedat
                }
            }
        ' "$f"
    done
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
    OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
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
    OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
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
       OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
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
       OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
       OVATION_FLOCK_BIN="$SUITE_FLOCK" OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
       OVATION_TEST_COMMAND="true" "$TARGET" 2>&1 | grep -c 'Hosted suite skipped')" "1"

check "a suite reading its own \$1 is caught" \
    "$(positional_readers "$STAGE" | cut -d: -f1)" "test-offender.sh"
# AND THE REFUSAL NAMES THE LINE, not only the file (ovation#344). A message
# naming the file sends the reader hunting for a parameter through a suite that
# takes none, and the remedy is invisible from what it says (L11, L148). The
# line number and the line itself are what the rule already knows.
check "and it names the line number and the line, so the reader is not sent hunting" \
    "$(positional_readers "$STAGE")" 'test-offender.sh:2:CONFIG="${1:-Debug}"'

# 2. AND IT DOES NOT FIRE ON THE LEGITIMATE USES EVERY SUITE HERE ALREADY MAKES.
rm -f "$STAGE/test-offender.sh"
cat > "$STAGE/test-innocent.sh" <<'INNOCENT'
#!/bin/bash
mentions() { if grep -q "$2" <<< "$1"; then echo yes; else echo no; fi; }
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

# 2b. A QUOTED HEREDOC IS DATA, NOT THE SUITE'S OWN CODE (ovation#344).
#
#     Several suites here stage a stub script that inspects the arguments it was
#     given, and `<<'SH' ... SH` passes its body through untouched: nothing in it
#     is ever read by the suite's own shell. The rule read those lines exactly
#     like the suite's, so test-report-finding.sh and test-output-privacy.sh both
#     tripped it on their stub's body while building ovation#339, and the message
#     named the suite file rather than the line.
rm -f "$STAGE"/test-*.sh
cat > "$STAGE/test-stager.sh" <<'STAGER'
#!/bin/bash
cat > "$WORK/gh" <<'SH'
case "$1" in
  issue) echo '{}' ;;
esac
SH
echo staged
STAGER
check "a stub staged in a quoted heredoc is not read as the suite's own parameter" \
    "$(positional_readers "$STAGE")" ""

# 2c. AND THE SKIP ENDS AT THE TERMINATOR. A heredoc tracker that swallows the
#     rest of the file is the way this direction goes wrong quietly: the guard
#     keeps passing while it stops reading (L98, L182). So the real defect is
#     staged AFTER a heredoc and still caught, and the line number proves it is
#     the line after it rather than a coincidence.
rm -f "$STAGE"/test-*.sh
cat > "$STAGE/test-after.sh" <<'AFTER'
#!/bin/bash
cat > /dev/null <<'SH'
case "$1" in
  find-identity) echo none ;;
esac
SH
CONFIG="${1:-Debug}"
AFTER
check "and the code after the terminator is still read" \
    "$(positional_readers "$STAGE")" 'test-after.sh:7:CONFIG="${1:-Debug}"'

# 2d. AN UNQUOTED HEREDOC IS NOT DATA. Its body IS expanded by the suite's own
#     shell, so a $1 in it is a genuine read of the suite's first argument and
#     the exemption must not reach it. Written as the REASON for exempting, which
#     is that the body is passed through untouched, rather than as "a heredoc"
#     (L362, L615).
rm -f "$STAGE"/test-*.sh
cat > "$STAGE/test-expanding.sh" <<'EXPANDING'
#!/bin/bash
cat > /dev/null <<SH
the configuration this suite was given is $1
SH
EXPANDING
check "an UNQUOTED heredoc is expanded by the suite's own shell, so its \$1 is caught" \
    "$(positional_readers "$STAGE" | cut -d: -f1)" "test-expanding.sh"

# 2e. AND A HEREDOC THAT IS NEVER TERMINATED SAYS SO. It is the one state this
#     tracker cannot represent any other way: everything after the opener goes
#     unread, and a file nothing was read from reports exactly like a clean one
#     (L98, L11). Named as its own outcome rather than folded into the others.
rm -f "$STAGE"/test-*.sh
#     Staged from INSIDE a function for the reason case 1 records: a guard that
#     hunts for a pattern has to name that pattern to look for it, and at the top
#     level of this file the line is a finding about this very suite (L245).
stage_unterminated() {
    printf '#!/bin/bash\ncat > /dev/null <<%sSH%s\nCONFIG="${1:-Debug}"\n' "'" "'" > "$1"
}
stage_unterminated "$STAGE/test-unterminated.sh"
check "a quoted heredoc that is never terminated is reported, not silently skipped" \
    "$(positional_readers "$STAGE")" \
    'test-unterminated.sh:2:a quoted heredoc opened here is never terminated, so the rest of this file was never read'

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
    OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
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
    "$(printf '%s' "$OUT11" | grep '^    could not measure:' | grep -c 'test-a-cannot.sh')" "1"

# 11a1. ovation#161, Dan's decision 2026-09-23: the shell suites run ONCE, on
#       Linux, and the macOS build job runs only the suites that need a Mac. Which
#       ones those are is DECLARED by the suite, one marker line, never listed
#       here or in the workflow (L41, L96), and the Linux job refuses a suite that
#       cannot measure there and carries no marker, so a new Mac only suite cannot
#       quietly go unmeasured by CI.
stage_marked_suite() {
    printf '#!/bin/bash\n# ovation-runs-on: macos\necho "RAN-%s"\nexit %s\n' "$1" "$2" > "$SUITES/test-$1.sh"
    chmod +x "$SUITES/test-$1.sh"
}
clear_suites
stage_marked_suite "a-needs-a-mac" 2
stage_suite "b-anywhere" 0
stage_suite "c-cannot-and-unmarked" 2
OUT161A="$(OVATION_SHELL_SUITES=macos-only shell_run)"; ST161A=$?
check "the macos only run runs the suite marked as needing a Mac" \
    "$(printf '%s' "$OUT161A" | grep -c '^RAN-a-needs-a-mac$')" "1"
check "and none of the others" \
    "$(printf '%s' "$OUT161A" | grep -cE '^RAN-(b-anywhere|c-cannot-and-unmarked)$')" "0"
check "and it says the others were left to the Linux job" \
    "$(printf '%s' "$OUT161A" | grep -c 'were left to the Linux job')" "1"
OUT161B="$(OVATION_SHELL_SUITES=must-measure shell_run)"; ST161B=$?
check "on Linux, an unmarked suite that cannot measure fails the run" \
    "$([ "$ST161B" -ne 0 ] && [ "$ST161B" -ne 2 ] && echo failed || echo "exit $ST161B")" "failed"
check "and it names that suite and says to mark it or make it measure" \
    "$(printf '%s' "$OUT161B" | grep -c 'test-c-cannot-and-unmarked.sh.*ovation-runs-on: macos')" "1"
clear_suites
stage_marked_suite "a-needs-a-mac" 2
stage_suite "b-anywhere" 0
OUT161C="$(OVATION_SHELL_SUITES=must-measure shell_run)"; ST161C=$?
check "and a MARKED suite that cannot measure there is allowed, as it always was" "$ST161C" "2"
OUT161D="$(shell_run)"; ST161D=$?
check "with no mode, every suite runs, which is the push gate on Dan's Mac" \
    "$(printf '%s' "$OUT161D" | grep -cE '^RAN-(a-needs-a-mac|b-anywhere)$')" "2"

# 11a2. EACH SUITE IS NAMED BEFORE IT RUNS (ovation#337). The macOS shell suites
#       job is cancelled at its cap intermittently, and the log then ends after
#       the last suite that FINISHED, so the one that was running is whichever
#       comes next in a glob nobody has in front of them. Twice on 2026-09-15 that
#       cost an hour of reading to answer "where was it", and the first answer was
#       wrong. A name printed before the work costs nothing and cannot be lost,
#       because it is already out when the kill arrives.
check "each suite is named before it runs, so a killed job says where it was" \
    "$(printf '%s' "$OUT11" | grep -c '^==> test-a-cannot.sh$')" "1"
named_at="$(printf '%s' "$OUT11" | grep -n '^==> test-a-cannot.sh$' | head -1 | cut -d: -f1)"
ran_at="$(printf '%s' "$OUT11" | grep -n '^RAN-a-cannot$' | head -1 | cut -d: -f1)"
check "and the name comes BEFORE that suite's own output, never after it" \
    "$([ -n "$named_at" ] && [ -n "$ran_at" ] && [ "$named_at" -lt "$ran_at" ] && echo before || echo "not before ($named_at, $ran_at)")" "before"
check "and every suite is named, not only the first" \
    "$(printf '%s' "$OUT11" | grep -c '^==> test-b-pass.sh$')" "1"

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
    "$(printf '%s' "$OUT11C" | grep '^    failed:' | grep -c 'test-a-fail.sh')" "1"
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
    "$(printf '%s' "$OUT11E" | grep '^    \(failed\|could not measure\):' | grep -c 'test-a-cannot.sh\|test-b-fail.sh')" "2"

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

# 11f2. AND A RUN ABOVE THE FLOOR IS REFUSED TOO (ovation#329), which is the same
#       reversal ovation#157 made to the pure floor and the shell one never got.
#       Refusing only a run BELOW it let the committed number sit at 59 while 65
#       suites sat in scripts/: six suites could lose their executable bit, be
#       renamed or be deleted and the count would still clear a floor six beneath
#       it, which is precisely the partial run the floor exists to refuse (L63,
#       L182, L354). Nothing made the number move, so it was a rule living in
#       whoever remembered it (L27).
clear_suites
stage_suite "a-pass" 0
stage_suite "b-pass" 0
stage_suite "c-pass" 0
stage_suite "d-pass" 0
OUT11F2="$(shell_run 3)"; ST11F2=$?
check "a run ABOVE the suite floor is refused, so the floor cannot stand still" \
    "$ST11F2" "7"
# READ THE LINE THIS CASE IS ABOUT, never the whole output (L135, L178): the
# remedy line below carries the same two numbers, and a path holding a digit
# answers a loose pattern as readily as the sentence does. That is the third time
# in one day a check counting a phrase was answered by a second line (#316, #337).
check "and it names both numbers, so what moved is readable" \
    "$(printf '%s' "$OUT11F2" | grep -c '^Error: the shell suites ran 4 and the floor says 3\.$')" "1"
# THE MESSAGE IS THE COMMAND THAT FIXES IT, not a description of one (L399, L406),
# exactly as the pure floor's is, so the reader pastes a line rather than
# composing it from a sentence about a file they have to go and find.
check "and the remedy is the command that moves the floor, ready to paste" \
    "$(printf '%s' "$OUT11F2" | grep -c "printf '%s.n' 4 > .*scripts/shell-suite-floor.txt")" "1"

# 11f3. AND THE REFUSAL SAYS THE NUMBER COMES FROM THIS RUN (ovation#351), which
#       is what ovation#346 settled for a suite's declared assertion count, and
#       the two are one problem in two files. The floor is one number committed
#       beside the suites it counts, so any two branches that each add a suite
#       conflict on it and NEITHER side's number is right: it happened three
#       times on 2026-09-15, on the branches for ovation#201, #329 and #339. The
#       resolution invites arithmetic over two diffs, which is how a wrong number
#       gets committed (L554), so the refusal says not to do it.
check "and it says the number came from this run, not from adding up two diffs" \
    "$(printf '%s' "$OUT11F2" | grep -c 'two diffs')" "1"

# 11f4. AND A SHORT RUN IS NEVER HANDED A NUMBER TO PASTE (ovation#351). Writing
#       what a short run counted is exactly how the floor stops seeing a suite
#       that lost its executable bit, which is the defect it exists to prevent,
#       so the paste ready remedy belongs to the other direction only (L11, L93).
#       Green before and after ovation#351: it is the property being protected
#       while the sentence above is added beside it.
check "a short run is given no floor to paste, because that would silence the check" \
    "$(printf '%s' "$OUT11F" | grep -c "printf '%s.n'")" "0"

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
        grep -qE "(^|[[:space:]])${seam}([[:space:]]|$)" <<< "$cleared" \
            || missing="${missing}${seam} "
    done < <(seams_honoured)
    printf '%s' "${missing% }"
}
check "every seam the runner honours is cleared by this suite" \
    "$(seams_not_cleared)" ""

# AND NO CONDITION WAIT IN THIS SUITE GIVES UP IN SILENCE (ovation#303). Each one
# goes through harness_wait_for, which fails by name when it runs out; a loop
# that breaks out on a poll count and carries on is refused here, so the next
# case written by copying an old one cannot bring the silent kind back (L613).
check "no condition wait in this suite breaks out of a poll count and carries on" \
    "$(grep -cE '" -gt [0-9]+ \] && [b]reak' scripts/test-run-tests.sh)" "0"

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
    OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
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
    harness_wait_for "Overture's lock to be taken by HOLDER4" 100 0.05 staged_file_lock_held
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

# 236b-i. A HOLDER IS ONE HOLDER HOWEVER MANY DESCRIPTORS ITS CHILDREN HOLD
#         (ovation#433). `flock` takes a lock on a plain file descriptor, and a
#         descriptor is INHERITED by every process started while it is held
#         (L441), so `lsof -t` answers with the holder AND its children.
#
#         MEASURED ON THIS MAC, 2026-09-22: a holder running `sleep 0.05` in a
#         loop answered with THREE pids, the flock, its bash, and a sleep that
#         had already exited by the next call a moment later. So the words
#         describing one holder were different on almost every poll, and the
#         runner counted a change of words as a change of holder, which is what
#         made 236b below go red on CI and green on a re-run of the same commit.
#
#         THIS CASE HOLDS A CHILD OPEN rather than racing the short lived ones,
#         so the set genuinely has more than one pid in it at the moment the
#         description is taken, on every run and every machine.
    : > "$FILE_LOCK"
    HOLD_SENTINEL4I="$WORK/hold-4i"; : > "$HOLD_SENTINEL4I"
    # THE CHILD ENDS ON THE SAME SENTINEL AND THE HOLDER WAITS FOR IT. A child
    # that outlives its parent keeps the descriptor, and the descriptor is the
    # lock, so a fixture whose child runs on would hold this lock after its
    # holder had gone and every case below it would measure that instead. Found
    # by writing it the other way first: five later cases failed.
    ( "$SUITE_FLOCK" "$FILE_LOCK" bash -c \
        '( while [ -e "$1" ]; do sleep 0.05; done ) & \
         while [ -e "$1" ]; do sleep 0.02; done; wait' _ "$HOLD_SENTINEL4I" ) &
    HOLDER4I=$!
    lock_has_more_than_one_pid() {
        [ "$(/usr/sbin/lsof -t "$FILE_LOCK" 2>/dev/null | grep -c .)" -gt 1 ]
    }
    if [ -x /usr/sbin/lsof ]; then
        harness_wait_for "the lock to be held through more than one descriptor (236b-i)" \
            200 0.05 lock_has_more_than_one_pid
        DESC4I="$(file_lock_describe "$FILE_LOCK")"
        check "a holder whose children hold the descriptor is named once" \
            "$(printf '%s' "$DESC4I" | grep -oE '[0-9]+ \(' | grep -c .)" "1"
        check "and the one named is the process that took the lock" \
            "$(printf '%s' "$DESC4I" | grep -c 'flock)')" "1"
    else
        # No lsof is an honest answer rather than a skipped case: the Linux job
        # has none, and the describer says so in its own words (L98).
        harness_wait_for "the holder to take the lock (236b-i, no lsof)" \
            200 0.05 staged_file_lock_held
        check "a holder whose children hold the descriptor is named once" \
            "$(file_lock_describe "$FILE_LOCK")" \
            "free, or held by a process this run cannot see"
        check "and the one named is the process that took the lock" \
            "$(file_lock_describe "$FILE_LOCK")" \
            "free, or held by a process this run cannot see"
    fi
    rm -f "$HOLD_SENTINEL4I"; wait "$HOLDER4I" 2>/dev/null || true

# 236c. How many DIFFERENT holders went ahead, which is what tells a queue of busy
#       sibling runs from one stuck lock. The holder changes during the wait, and
#       the change is made on a condition, not a timer (L290): only once the
#       runner has printed the first holder.
mkdir -p "$DIR_LOCK"
printf 'overture-run-a:111\n' > "$DIR_LOCK/owner"
OUTFILE236C="$WORK/run-236c.out"; : > "$OUTFILE236C"
( TIMEOUT_OVERRIDE=3 run_runner > "$OUTFILE236C" 2>&1 ) &
RUNNER236C=$!
harness_wait_for "the runner to print the first holder (236c)" 200 0.05 \
    file_mentions "$OUTFILE236C" 'overture-run-a:111'
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
harness_wait_for "the runner to print the holder (236d)" 200 0.05 \
    file_mentions "$OUTFILE236D" 'downbeat-run:333'
rm -rf "$DIR_LOCK"
wait "$RUNNER236D"; ST236D=$?
check "a wait that ends in both locks passes and says what went ahead of it" \
    "$ST236D:$(grep -c '1 different holder went ahead' "$OUTFILE236D")" "0:1"

# 303. A LOCK CHANGING HANDS WHILE ITS OWNER IS BEING READ IS NOT ANOTHER HOLDER
#      (ovation#303).
#
# 236d above failed on busy machines, CI and the push gate alike, expecting 0:1
# and getting 0:0, and passed on rerun. The test's timing was not the cause. The
# runner described Downbeat's lock by asking whether the owner file existed and
# then reading it in a separate process, and it counted every change in that
# description as one more run that went ahead. A release landing between the
# two steps read as `held by ` with nothing after it, a description the holder
# never had, so one holder counted as two. A new holder landing between its
# mkdir and its owner line did the same from the other side. Load only widens
# the gap, which is why it was rare; measured 2026-09-14, a `head` that sleeps
# 0.3s first failed 236d in 20 of 20 runs, while 180 runs beside 24 busy loops
# never did (L681, L203).
#
# So the moment is STAGED, not raced (L290): a `head` stand in does to the lock
# what the case needs at the instant the runner reads its owner, and the case
# arms it only once the runner has printed the first holder. Each case also
# proves the stand in fired, because a runner that stopped reading the owner
# with `head` would pass a race nobody staged (L159).
REAL_HEAD="$(command -v head)"
OWNER_READ_SHIM="$WORK/owner-read-shim"
mkdir -p "$OWNER_READ_SHIM"
cat > "$OWNER_READ_SHIM/head" <<SHIM
#!/bin/bash
for arg in "\$@"; do
    if [ "\$arg" = "$DIR_LOCK/owner" ] && [ -f "$OWNER_READ_SHIM/armed" ]; then
        case "\$(cat "$OWNER_READ_SHIM/armed")" in
            release) rm -rf "$DIR_LOCK"; rm -f "$OWNER_READ_SHIM/armed"
                     : > "$OWNER_READ_SHIM/fired" ;;
            replace) rm -rf "$DIR_LOCK"; mkdir "$DIR_LOCK"
                     printf 'name\n' > "$OWNER_READ_SHIM/armed"
                     : > "$OWNER_READ_SHIM/fired" ;;
            name)    printf 'overture-run-c:444\n' > "$DIR_LOCK/owner"
                     rm -f "$OWNER_READ_SHIM/armed" ;;
        esac
        break
    fi
done
exec "$REAL_HEAD" "\$@"
SHIM
chmod +x "$OWNER_READ_SHIM/head"

# wait_for_holder_line <file>: the condition the arming waits on.
wait_for_holder_line() {
    harness_wait_for "the runner to print the holder in $(basename "$1")" 400 0.05 \
        file_mentions "$1" 'downbeat-run:333'
}

# 303a. Released while its owner is read: one holder went ahead, not two.
rm -f "$OWNER_READ_SHIM/armed" "$OWNER_READ_SHIM/fired"
mkdir -p "$DIR_LOCK"
printf 'downbeat-run:333\n' > "$DIR_LOCK/owner"
OUTFILE303A="$WORK/run-303a.out"; : > "$OUTFILE303A"
( PATH="$OWNER_READ_SHIM:$PATH" TIMEOUT_OVERRIDE=10 run_runner > "$OUTFILE303A" 2>&1 ) &
RUNNER303A=$!
wait_for_holder_line "$OUTFILE303A"
printf 'release\n' > "$OWNER_READ_SHIM/armed"
wait "$RUNNER303A"; ST303A=$?
check "a lock released while its owner is read is counted as the one holder it was" \
    "$ST303A:$(grep -c '1 different holder went ahead' "$OUTFILE303A")" "0:1"
check "and the release really landed during an owner read" \
    "$([ -f "$OWNER_READ_SHIM/fired" ] && echo staged || echo not-staged)" "staged"
rm -rf "$DIR_LOCK"

# 303b. Replaced by a new holder that names itself one read later: two holders
#       went ahead, not three. The runner gives up here, since the new holder
#       never lets go, and giving up is where the count is said.
rm -f "$OWNER_READ_SHIM/armed" "$OWNER_READ_SHIM/fired"
mkdir -p "$DIR_LOCK"
printf 'downbeat-run:333\n' > "$DIR_LOCK/owner"
OUTFILE303B="$WORK/run-303b.out"; : > "$OUTFILE303B"
( PATH="$OWNER_READ_SHIM:$PATH" TIMEOUT_OVERRIDE=2 run_runner > "$OUTFILE303B" 2>&1 ) &
RUNNER303B=$!
wait_for_holder_line "$OUTFILE303B"
printf 'replace\n' > "$OWNER_READ_SHIM/armed"
wait "$RUNNER303B" 2>/dev/null || true
check "a new holder caught before it names itself is counted once" \
    "$(mentions "$(gave_up_part "$(cat "$OUTFILE303B")")" '2 different holders went ahead')" "yes"
check "and the new holder really was caught unnamed and then named" \
    "$(cat "$DIR_LOCK/owner" 2>/dev/null):$([ -f "$OWNER_READ_SHIM/armed" ] && echo armed || echo spent)" \
    "overture-run-c:444:spent"
rm -rf "$DIR_LOCK"
rm -f "$OWNER_READ_SHIM/armed" "$OWNER_READ_SHIM/fired"

# 236e. EVERY attempt is recorded, a wait of nothing included, because how often a
#       run waits is a fraction and needs the runs that did not (L396).
#
#       THIS CASE SAYS IT IS MEASURING THE RECORD (ovation#368). Every case here
#       injects its commands, so every wait it stages is staged, and a staged run
#       writes nothing to a record unless it declares that the staging is what it
#       measures, the way test-design-render.sh does for the restart record.
WAITLOG="$WORK/lock-waits.tsv"; rm -f "$WAITLOG"
OVATION_LOCK_WAIT_RECORD_STAGED=1 OVATION_LOCK_WAIT_LOG="$WAITLOG" run_runner >/dev/null 2>&1
mkdir -p "$DIR_LOCK"
OVATION_LOCK_WAIT_RECORD_STAGED=1 OVATION_LOCK_WAIT_LOG="$WAITLOG" TIMEOUT_OVERRIDE=1 run_runner >/dev/null 2>&1
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

# 236f2. NOR INTO A RECORD SOMEBODY NAMED (ovation#368). The name used to be taken
#        whatever else was true, which is the shape that let the renderer write
#        staged faults into the record CI carries to the tracker (ovation#366): a
#        record named for a whole job is inherited by every suite in it (L439).
STAGEDLOG="$WORK/staged-waits.tsv"; rm -f "$STAGEDLOG"
OVATION_LOCK_WAIT_LOG="$STAGEDLOG" run_runner >/dev/null 2>&1
check "an injected run writes nothing to a record it names without declaring the staging" \
    "$([ -e "$STAGEDLOG" ] && echo written || echo untouched)" "untouched"
# The declaration belongs to THIS record: the renderer's own does not reach it.
OVATION_RENDER_RECORD_STAGED=1 OVATION_LOCK_WAIT_LOG="$STAGEDLOG" run_runner >/dev/null 2>&1
check "and the restart record's declaration does not open the lock wait record" \
    "$([ -e "$STAGEDLOG" ] && echo written || echo untouched)" "untouched"

# 236g. And the record is read back: the start of a wait quotes recent waits, so
#       the number that used to be lost is in front of the person waiting.
printf '1789000000\t0\tacquired\t0\n1789000100\t40\tacquired\t1\n1789000200\t700\tgave-up\t3\n' > "$WAITLOG"
mkdir -p "$DIR_LOCK"
OUT236G="$(OVATION_LOCK_WAIT_RECORD_STAGED=1 OVATION_LOCK_WAIT_LOG="$WAITLOG" TIMEOUT_OVERRIDE=1 run_runner)"
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
    OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
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


# ---------------------------------------------------------------------------
# A PROJECT THAT DOES NOT LIST THE SWIFT FILES ON DISK STOPS THE RUN BY NAME
# (ovation#206).
#
# project.yml lists directories and the generated project lists files, so a new
# Swift file is invisible to every build until the project is regenerated. On
# 2026-09-10 that surfaced as `cannot find 'YearEndExportCommand' in scope`,
# which names the code rather than the project. The runner asks
# check-xcode-project-current.sh before either Swift suite, so a direct run is
# told the real subject and the command that fixes it. The stale project here
# lists one name that is in no tree, against this repository's real sources.
STALE="$WORK/stale.xcodeproj"; mkdir -p "$STALE"
printf '{\n\t\t000000000000000000000001 /* NotInAnyTree.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NotInAnyTree.swift; sourceTree = "<group>"; };\n}\n' \
    > "$STALE/project.pbxproj"
stale_project_run() {
    OVATION_DIR_LOCK="$DIR_LOCK" OVATION_FILE_LOCK="$FILE_LOCK" \
    OVATION_LOCK_TIMEOUT=2 OVATION_LOCK_POLL_INTERVAL=0.05 \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" \
    OVATION_TEST_COMMAND="echo PURE-SUITE-RAN" OVATION_UNLOCKED_COMMAND="true" \
    OVATION_HOSTED_TEST_COMMAND="$HOSTED_PASSES" \
    OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
    OVATION_XCODE_PROJECT="$1" \
        "./$TARGET" 2>&1
}
OUT206="$(stale_project_run "$STALE")"; ST206=$?
check "a project that does not list the Swift files on disk fails the run" "$ST206" "1"
check "and it stops before the pure suite is built from it" \
    "$(mentions "$OUT206" "PURE-SUITE-RAN")" "no"
check "and it gives the command that regenerates the project" \
    "$(mentions "$OUT206" "bash scripts/regenerate-xcode-project.sh")" "yes"

# ---------------------------------------------------------------------------
# TWO RUNS CREATING THE SAME PROJECT AT ONCE MAKE IT ONCE (ovation#207).
#
# ovation#202 put regeneration under the lock every build takes and left the
# CREATE alone, on purpose: a fresh checkout must not queue behind a sibling's
# build for a file nothing can be reading. That holds against a build and not
# against a second create. Two runs starting together on a fresh tree both saw no
# project and both ran xcodegen at the same path, and a second run could see the
# project DIRECTORY the first had only begun to write and build from it.
#
# So a create takes a lock scoped to the project path, and a run that finds one
# held waits for that run's result rather than generating over it. The helper is
# driven directly, with generators that block on a sentinel this suite removes,
# so the overlap is staged on conditions rather than on timing (L290).
[ -n "${WORK:-}" ] || { echo "REFUSED: no temp directory"; exit 1; }
CREATE="$WORK/create"; rm -rf "$CREATE"; mkdir -p "$CREATE"
CREATE_LIB="$PWD/scripts/lib/ensure-xcode-project.sh"
# stage_generator <name> <mkdir-first|mkdir-last|fail>
stage_generator() {
    local body
    case "$2" in
        mkdir-first) body="mkdir -p '$CREATE/Ovation.xcodeproj'; touch '$CREATE/started'; while [ -e '$CREATE/hold' ]; do sleep 0.02; done" ;;
        mkdir-last) body="touch '$CREATE/started'; while [ -e '$CREATE/hold' ]; do sleep 0.02; done; mkdir -p '$CREATE/Ovation.xcodeproj'" ;;
        fail) body="exit 1" ;;
    esac
    printf '#!/bin/bash\necho GENERATOR-RAN >> "%s"\n%s\n' "$CREATE/generated.log" "$body" > "$CREATE/$1"
    chmod +x "$CREATE/$1"
}
reset_create() {
    rm -rf "$CREATE/Ovation.xcodeproj" "$CREATE/started" "$CREATE/generated.log"
    : > "$CREATE/hold"
}
# create_in_background <output file> <generator>: sets CREATE_PID.
create_in_background() {
    OVATION_PROJECT_CREATE_POLL=0.05 \
        bash -c '. "$1"; ensure_xcode_project "$2" "$3" "$4"' _ \
        "$CREATE_LIB" "$CREATE" "$CREATE/Ovation.xcodeproj" "$CREATE/$2" > "$1" 2>&1 &
    CREATE_PID=$!
}
wait_for_file() {
    harness_wait_for "$(basename "$1") to exist" 200 0.05 test -e "$1"
}
# create_now <generator> [timeout]: runs the helper in the foreground. The inner
# `$1` belongs to `bash -c`, which is why every call lives inside a function: the
# suite level argument scan below reads unindented lines.
create_now() {
    OVATION_PROJECT_CREATE_POLL=0.05 OVATION_PROJECT_CREATE_TIMEOUT="${2:-300}" \
        bash -c '. "$1"; ensure_xcode_project "$2" "$3" "$4"' _ \
        "$CREATE_LIB" "$CREATE" "$CREATE/Ovation.xcodeproj" "$CREATE/$1" 2>&1
}
create_lock_of() {
    bash -c '. "$1"; xcode_project_create_lock "$2"' _ "$CREATE_LIB" "$1"
}
CREATE_LOCK="$(create_lock_of "$CREATE/Ovation.xcodeproj")"
check "the create lock is a real path derived from the project" \
    "$([ -n "$CREATE_LOCK" ] && [ "$CREATE_LOCK" != "$CREATE/Ovation.xcodeproj" ] && echo derived || echo "none:$CREATE_LOCK")" "derived"

# 207a. The generator writes the project only when it finishes, so a second run
#       that does not wait generates a second time.
reset_create; stage_generator gen-last mkdir-last
create_in_background "$CREATE/a.out" gen-last; FIRST_CREATE=$CREATE_PID
wait_for_file "$CREATE/started"
create_in_background "$CREATE/b.out" gen-last; SECOND_CREATE=$CREATE_PID
wait_for_line "$CREATE/b.out" 'creating'
rm -f "$CREATE/hold"
wait "$FIRST_CREATE"; ST207A1=$?
wait "$SECOND_CREATE"; ST207A2=$?
check "two runs creating one project at once both succeed" "$ST207A1:$ST207A2" "0:0"
check "and the generator ran once, not once for each" \
    "$(grep -c GENERATOR-RAN "$CREATE/generated.log" 2>/dev/null)" "1"
check "and the second run says it waited for the first rather than generating" \
    "$(grep -c 'waiting for it rather than generating over it' "$CREATE/b.out")" "1"

# 207b. The generator makes the directory FIRST, which is what a half written
#       project looks like from outside. A run must not take that as ready.
reset_create; stage_generator gen-first mkdir-first
create_in_background "$CREATE/a.out" gen-first; FIRST_CREATE=$CREATE_PID
wait_for_file "$CREATE/started"
create_in_background "$CREATE/b.out" gen-first; SECOND_CREATE=$CREATE_PID
wait_for_line "$CREATE/b.out" 'creating'
check "a project still being created is waited for, not built from" \
    "$(kill -0 "$SECOND_CREATE" 2>/dev/null && echo waiting || echo returned-early)" "waiting"
rm -f "$CREATE/hold"
wait "$FIRST_CREATE"; wait "$SECOND_CREATE"; ST207B=$?
check "and once it is made the waiting run goes on with it" "$ST207B" "0"

# 207c. A LOCK LEFT BY A RUN THAT DIED is claimed, not waited on for ever. A mkdir
#       lock is not released by the kernel, and run-tests.sh exits on INT and TERM
#       (ovation#274), so a stopped create leaves one behind (L409).
reset_create; rm -f "$CREATE/hold"; stage_generator gen-last mkdir-last
bash -c 'exit 0' & DEAD_PID=$!; wait "$DEAD_PID"
mkdir -p "$CREATE_LOCK"; printf 'Ovation create:%s\n' "$DEAD_PID" > "$CREATE_LOCK/owner"
OUT207C="$(create_now gen-last)"; ST207C=$?
check "a create lock left by a run that died is claimed and the project made" "$ST207C" "0"
check "and it says whose lock it claimed" "$(mentions "$OUT207C" "left by a run that is no longer alive")" "yes"
check "and the lock is gone afterwards" "$([ -e "$CREATE_LOCK" ] && echo held || echo free)" "free"

# 207d. A generator that fails still gives the lock back, or every later run on
#       this tree would wait on a create that is not happening.
reset_create; rm -f "$CREATE/hold"; stage_generator gen-fail fail
create_now gen-fail >/dev/null; ST207D=$?
check "a generator that failed is refused" "$ST207D" "2"
check "and the create lock is released anyway" "$([ -e "$CREATE_LOCK" ] && echo held || echo free)" "free"

# 207e. A create by a LIVE run that does not finish is a refusal naming it, not a
#       wait with no end (L110). This suite's own pid is the live holder.
reset_create; rm -f "$CREATE/hold"
mkdir -p "$CREATE_LOCK"; printf 'Ovation create:%s\n' "$$" > "$CREATE_LOCK/owner"
OUT207E="$(create_now gen-last 1)"; ST207E=$?
check "a create that a live run never finishes is refused after the deadline" "$ST207E" "2"
check "and the refusal names the run holding it" "$(mentions "$OUT207E" "Ovation create:$$")" "yes"
rm -rf "$CREATE_LOCK"

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
    OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
    OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
        "./$TARGET" 2>&1
}
counted_status() { counted_run "$@" >/dev/null 2>&1; printf '%s' "$?"; }

check "a run that matches its floor exactly passes" "$(counted_status 100 100)" "0"
check "a run BELOW its floor is refused" "$(counted_status 60 100)" "7"
# AND A SHORT RUN IS NEVER HANDED A NUMBER TO PASTE, for the shell suite floor's
# reason (ovation#351, case 11f4): writing what a short run counted is how the
# floor stops seeing the tests that dropped out (L11, L93, L30).
check "a short run is given no pure floor to paste, because that would silence the check" \
    "$(counted_run 60 100 | grep -c "printf '%s.n'")" "0"

OUT157="$(counted_run 140 100)"
check "a run ABOVE its floor is refused too, because a floor that never moves stops being one" \
    "$(counted_status 140 100)" "7"
check "and it says the tests were ADDED rather than reporting a loss" \
    "$(mentions "$OUT157" "being ADDED")" "yes"
check "and it gives the exact command, with the real number in it" \
    "$(mentions "$OUT157" "140 > ")" "yes"
# And it says the number comes from this run, for the reason the shell suite
# floor's refusal does (ovation#351, case 11f3): the floor file conflicts on every
# pair of branches that add tests, and arithmetic over two diffs is how a wrong
# number gets committed (L554, L30).
check "and it says the number came from this run, not from adding up two diffs" \
    "$(mentions "$OUT157" "two diffs")" "yes"


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
    OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
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
harness_wait_for "the stand in pure suite to show its command line" 100 0.05 \
    process_shows "$FAKE_PURE" 'scheme OvationCore'
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

# ---------------------------------------------------------------------------
# THE EXPLANATION IS SAID ONCE PER PAIR, THE PAIR ITSELF EVERY RUN (ovation#320).
#
# Xcode updated itself on Dan's Mac to 27.0 and the pinned 26.6 is no longer
# installed, and the runner image CI builds on does not offer 27.0 at all:
# measured 2026-09-16, macos-26 carries 26.0.1 up to 26.6 and nothing newer. So
# the mismatch is not a state anybody can leave in an afternoon, and the three
# line note above printed on EVERY build run for as long as it lasts, which is
# the note people stop reading (L36).
#
# SILENCE MUST NEVER COME TO MEAN THE BAD STATE, so the pair of versions is still
# named on every run, on one line. What is said once is the PARAGRAPH explaining
# what the difference costs. Once per PAIR, not once ever: the stamp is keyed on
# both versions, because a message naming two things and deduplicated on one goes
# stale silently (L641).
#
# EVERY CASE SETS ITS OWN STATE FILE. Sharing one would make each case's verdict
# depend on which ran before it.
# ---------------------------------------------------------------------------
run_with_state() {
    # run_with_state <state file> <xcodebuild> [pin file]
    local XCODE_NOTICE_STATE_OVERRIDE="$1"
    shift
    run_with_xcode "$@"
}
explains() { mentions "$1" "does not show CI"; }

# 1. FIRST TIME: the pair and the explanation.
ST_FRESH="$WORK/state-fresh"
OUT_X1="$(run_with_state "$ST_FRESH" "$WORK/xcodebuild-older")"
check "the first run on a new pair names both versions" \
    "$(printf '%s' "$OUT_X1" | grep -c 'Xcode 26.4.1.*Xcode 26.6')" "1"
check "and explains what the difference costs" "$(explains "$OUT_X1")" "yes"

# 2. AGAIN, UNCHANGED: the pair, and no paragraph.
OUT_X2="$(run_with_state "$ST_FRESH" "$WORK/xcodebuild-older")"; ST_X2=$?
check "a second run on the same pair still names both versions" \
    "$(printf '%s' "$OUT_X2" | grep -c 'Xcode 26.4.1.*Xcode 26.6')" "1"
check "and does not repeat the explanation" "$(explains "$OUT_X2")" "no"
check "and the quietened run is still not refused" "$ST_X2" "0"

# 3. THIS MAC'S XCODE MOVES: the pair changed, so it is explained again.
xcodebuild_reporting "$WORK/xcodebuild-newer" "27.0"
OUT_X3="$(run_with_state "$ST_FRESH" "$WORK/xcodebuild-newer")"
check "a run after this Mac's Xcode moves explains the new pair" \
    "$(explains "$OUT_X3")" "yes"
check "and names the version this Mac now builds with" \
    "$(printf '%s' "$OUT_X3" | grep -c 'Xcode 27.0.*Xcode 26.6')" "1"

# 4. THE PIN MOVES: the other half of the pair, which a stamp keyed on one
#    version alone would miss entirely (L641).
printf '26.5\n' > "$WORK/moved-pin"
OUT_X4="$(run_with_state "$ST_FRESH" "$WORK/xcodebuild-newer" "$WORK/moved-pin")"
check "a run after the pin moves explains the new pair" "$(explains "$OUT_X4")" "yes"

# 5. THROUGH A MATCHING RUN AND BACK. The pair in between was a different pair,
#    so the mismatch is a change again and is explained again. A stamp written
#    only on mismatches would stay silent here.
ST_ROUND="$WORK/state-round"
run_with_state "$ST_ROUND" "$WORK/xcodebuild-older" >/dev/null
run_with_state "$ST_ROUND" "$WORK/xcodebuild-same" >/dev/null
OUT_X5="$(run_with_state "$ST_ROUND" "$WORK/xcodebuild-older")"
check "a mismatch returning after a matching run is explained again" \
    "$(explains "$OUT_X5")" "yes"

# 6. A FAILURE TO MEASURE IS NEVER QUIETENED. It is rare, and it is the state
#    where nothing is known, which must not come to look like the healthy day
#    (L98, L11). Both of its causes speak on every run, not once.
ST_NONE="$WORK/state-none"
run_with_state "$ST_NONE" "$WORK/no-such-xcodebuild" >/dev/null
OUT_X6="$(run_with_state "$ST_NONE" "$WORK/no-such-xcodebuild")"
check "an unreadable Xcode version is reported on every run, not once" \
    "$(mentions "$OUT_X6" "could not tell which Xcode")" "yes"
ST_NOPIN="$WORK/state-nopin"
run_with_state "$ST_NOPIN" "$WORK/xcodebuild-same" "$WORK/no-such-pin" >/dev/null
OUT_X7="$(run_with_state "$ST_NOPIN" "$WORK/xcodebuild-same" "$WORK/no-such-pin")"
check "an unreadable pin is reported on every run, not once" \
    "$(mentions "$OUT_X7" "$WORK/no-such-pin")" "yes"

# 7. THE STATE FILE IS THE RUNNER'S OWN, and a run that cannot measure must not
#    write one: a stamp written from a reading that failed would suppress the
#    explanation of a pair nobody ever saw.
check "a run that could not measure leaves no stamp behind" \
    "$([ -e "$ST_NONE" ] && echo stamped || echo nothing)" "nothing"

# 8. AN UNWRITABLE STATE DIRECTORY MUST NOT FAIL THE RUN, and must not silence
#    the explanation either: a note that cannot be remembered is said every time,
#    which is the old behaviour and the safe direction (L93).
OUT_X8="$(run_with_state "$WORK/no-such-dir/deep/state" "$WORK/xcodebuild-older")"; ST_X8=$?
check "a stamp that cannot be written does not fail the run" "$ST_X8" "0"
check "and the explanation is given rather than silently dropped" \
    "$(explains "$OUT_X8")" "yes"


# ---------------------------------------------------------------------------
# A RUN MUST NOT LEAVE A PREFERENCE DOMAIN BEHIND (ovation#263).
#
# Two fixtures made a UserDefaults suite by NAME and never removed it, so every
# run left one more `ovation.tests.<uuid>` domain on the Mac: 426 when the issue
# was filed on 2026-09-13, 4656 by that evening. The runner lists them before
# the Swift suites and after, and refuses a run that added one.
#
# BY NAME, NOT BY COUNT. A run that removed one old leftover and made one new one
# would hold the count steady while leaking (L367). And a leftover that was
# already there is not this run's, which is also the state of every Mac that ran
# the suite before this change.
#
# The pure command stands in for a test: it adds a line to the listed file, which
# is what a leaking test does to the real list.
# ---------------------------------------------------------------------------
printf 'com.apple.finder\novation.tests.OLD-LEFTOVER\n' > "$DOMAINS"
OUT263A="$(PURE_OVERRIDE="printf 'ovation.tests.LEAKED-BY-THIS-RUN\n' >> '$DOMAINS'" run_runner)"; ST263A=$?
check "a run that leaves an ovation.tests domain behind is refused" "$ST263A" "7"
check "and it names the domain it left" \
    "$(mentions "$OUT263A" "ovation.tests.LEAKED-BY-THIS-RUN")" "yes"
check "and it names the other explanation, another checkout's older tests running at once" \
    "$(mentions "$OUT263A" "another checkout")" "yes"

printf 'com.apple.finder\novation.tests.OLD-LEFTOVER\n' > "$DOMAINS"
OUT263B="$(run_runner)"; ST263B=$?
check "a leftover that was there before the run is not blamed on it" "$ST263B" "0"
check "and a clean run says it checked, with both counts" \
    "$(mentions "$OUT263B" "1 before, 1 after")" "yes"

# NOTHING LISTED IS NOT NOTHING LEFT BEHIND (L98, L215).
OUT263C="$(DOMAINS_OVERRIDE="false" run_runner)"; ST263C=$?
check "a domain list that cannot be read is not a clean run" "$ST263C" "2"
check "and it says the list could not be read" \
    "$(mentions "$OUT263C" "could not list")" "yes"

# THE SHAPE `defaults domains` ACTUALLY PRINTS: one line, comma separated.
printf 'com.apple.finder, ovation.tests.OLD-LEFTOVER' > "$DOMAINS"
OUT263D="$(PURE_OVERRIDE="printf ', ovation.tests.COMMA-LEAK' >> '$DOMAINS'" run_runner)"; ST263D=$?
check "a leak in the comma separated form is refused too" "$ST263D" "7"
check "and named without its separator" \
    "$(printf '%s' "$OUT263D" | grep -c '^ *ovation\.tests\.COMMA-LEAK$' || true)" "1"
printf 'com.apple.finder\n' > "$DOMAINS"


# ---------------------------------------------------------------------------
# ONE SUITE, OR ONE TEST, THROUGH THE RUNNER'S OWN PATH (ovation#321).
#
# The runner had no way to run one test file, so every red and green run of a
# test first cycle called xcodebuild with -only-testing by hand: outside the
# project checks, outside the lock protocol the siblings rely on, and behind a
# hand written wait on the build lock that kept only the last line of a
# regeneration's refusal. And a narrowed run that matches nothing prints ** TEST
# SUCCEEDED ** and exits 0, which the runner already refused for the hosted suite
# and a hand run did not (L98, L288).
#
# EVERY INVOCATION HERE SETS EVERY SEAM, the usage refusals included. A refusal
# that is not implemented yet runs the whole runner, and without the seams that
# is the real shell suites, this file among them, and a real xcodebuild (L2, L284).
#
# THE REAL COMMAND LINE IS JUDGED TOO, not only the variable an injected command
# can read. A stand in xcodebuild first on PATH records the arguments it was given,
# so a runner that exported the filter and forgot to pass it to xcodebuild fails
# here by name. The version seam points elsewhere, so the stand in answers only the
# build (L52 is why it records rather than judges).
# ---------------------------------------------------------------------------
[ -n "${WORK:-}" ] || { echo "REFUSED: no temp directory"; exit 1; }
ONLY="$WORK/only"; rm -rf "$ONLY"; mkdir -p "$ONLY/bin"
cat > "$ONLY/bin/xcodebuild" <<STUB
#!/bin/bash
printf '%s\n' "\$@" > "$ONLY/xcodebuild-args"
echo "Test run with 3 tests in 1 suite passed"
STUB
chmod +x "$ONLY/bin/xcodebuild"

# A CHECKOUT WHOSE APP ONLY FILES ARE UNCHANGED, for every narrowed run that is
# not about them (ovation#515). A narrowed pure run builds the app when a file the
# pure target leaves out differs from main, and the checkout it asks by default is
# this one: on a branch that edits OvationApp.swift, every case below would then
# ask for a real app build (L2, L284). So each narrowed run is pointed at this
# throwaway repository, carrying the REAL project.yml so the list of left out
# files is derived from the file that decides it (L41), and at a stand in build.
APPREPO="$WORK/app-changes"; rm -rf "$APPREPO"; mkdir -p "$APPREPO/Ovation/App"
cp project.yml "$APPREPO/project.yml"
printf '@main struct OvationApp {}\n' > "$APPREPO/Ovation/App/OvationApp.swift"
printf '<plist/>\n' > "$APPREPO/Ovation/Info.plist"
printf 'struct Other {}\n' > "$APPREPO/Ovation/Other.swift"
appgit() { git -C "$APPREPO" -c user.name=suite -c user.email=suite@example.invalid -c commit.gpgsign=false "$@"; }
appgit init -q
appgit add -A
appgit commit -qm base
appgit update-ref refs/remotes/origin/main HEAD
APP_BUILD_STANDIN='echo APP-BUILD-RAN'

# What an injected command prints by default: the filter it can see, and a count.
ONLY_COUNTED='echo "FILTER=${OVATION_ONLY_TESTING:-none}"; echo "Test run with 3 tests in 1 suite passed"'

# only_run [runner arguments]. Overrides are prefixes on the call, and every call
# sits inside a `$(...)`, so none of them outlives its case (L439).
only_run() {
    OVATION_APP_CHANGES_ROOT="${ONLY_APP_ROOT:-$APPREPO}" \
    OVATION_APP_CHANGES_BASE="${ONLY_APP_BASE:-origin/main}" \
    OVATION_APP_BUILD_COMMAND="${ONLY_APP_BUILD-$APP_BUILD_STANDIN}" \
    PATH="${ONLY_PATH:-$PATH}" \
    OVATION_XCODEBUILD="$WORK/no-xcodebuild-given" \
    OVATION_XCODE_VERSION_FILE="$WORK/no-xcode-pin-given" \
    OVATION_DEFAULTS_DOMAINS_COMMAND="$DOMAINS_LISTER" \
    OVATION_DIR_LOCK="$DIR_LOCK" OVATION_FILE_LOCK="$FILE_LOCK" \
    OVATION_LOCK_TIMEOUT="${TIMEOUT_OVERRIDE:-2}" OVATION_LOCK_POLL_INTERVAL=0.05 \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" \
    OVATION_TEST_FLOOR="${ONLY_FLOOR:-}" \
    OVATION_TEST_COMMAND="${ONLY_PURE-$ONLY_COUNTED}" \
    OVATION_HOSTED_TEST_COMMAND="${ONLY_HOSTED-$ONLY_COUNTED}" \
    OVATION_UNLOCKED_COMMAND="echo UNLOCKED-RAN" \
    OVATION_SKIP_XCODE_PHASE="${ONLY_SKIP:-}" \
    OVATION_PROJECT_CURRENT_COMMAND="${ONLY_CURRENT:-exit 2}" \
    OVATION_REGENERATE_COMMAND="${ONLY_REGENERATE:-echo REGENERATE-RAN; exit 99}" \
    OVATION_LOCK_WAIT_LOG="${ONLY_WAIT_LOG-$ONLY/lock-waits.tsv}" \
    OVATION_XCODEBUILD_LISTER=true \
    OVATION_XCODE_PROJECT="$STANDIN_PROJECT" \
        "./$TARGET" "$@" 2>&1
}
count_of() { printf '%s\n' "$1" | grep -cE -- "$2" || true; }

# 321a. USAGE. Anything but no argument or one well formed --only is refused
#       before anything runs, with the forms that are accepted.
OUT321A="$(only_run --only)"; ST321A=$?
check "--only with no value is refused as a usage error" "$ST321A" "2"
check "and the refusal names both accepted forms" \
    "$(count_of "$OUT321A" '--only (OvationTests|OvationHostedTests)/<Suite>')" "2"
check "and nothing ran before it was refused" \
    "$(count_of "$OUT321A" 'UNLOCKED-RAN|FILTER=')" "0"
OUT321B="$(only_run --only DownbeatTests/SomeSuite)"; ST321B=$?
check "a target other than OvationTests or OvationHostedTests is refused, naming what it was given" \
    "$ST321B:$(count_of "$OUT321B" 'DownbeatTests/SomeSuite')" "2:1"
OUT321C="$(only_run --verbose)"; ST321C=$?
check "an unknown argument is refused, naming it" \
    "$ST321C:$(count_of "$OUT321C" "'--verbose'")" "2:1"
OUT321D="$(only_run --only OvationTests)"; ST321D=$?
check "a whole target with no suite is refused, since running all of it is the full run" \
    "$ST321D:$(count_of "$OUT321D" 'UNLOCKED-RAN')" "2:0"
OUT321E="$(ONLY_SKIP=1 only_run --only OvationTests/SomeSuiteTests)"; ST321E=$?
check "a narrowed run the caller also told to skip the Xcode phase is refused, since it would test nothing" \
    "$ST321E:$(count_of "$OUT321E" 'test nothing')" "2:1"

# 321b. A NARROWED PURE RUN takes no lock (ovation#271), so a sibling holding
#       Downbeat's lock does not stop it, and it hands the filter to its command.
rm -rf "$DIR_LOCK"; mkdir -p "$DIR_LOCK"
OUT321F="$(ONLY_HOSTED='echo HOSTED-SUITE-RAN; echo "Test run with 5 tests in 1 suite passed"' \
    only_run --only OvationTests/SomeSuiteTests)"; ST321F=$?
check "a narrowed pure run passes while a sibling holds Downbeat's lock, because it takes none" "$ST321F" "0"
check "and the sibling's lock is still where it was" \
    "$([ -d "$DIR_LOCK" ] && echo held || echo free)" "held"
rm -rf "$DIR_LOCK"
check "and the command it ran was handed the filter" \
    "$(count_of "$OUT321F" '^FILTER=OvationTests/SomeSuiteTests$')" "1"
check "and it never asked for the sibling locks" \
    "$(count_of "$OUT321F" 'Waiting for both test locks')" "0"
check "and no shell suite ran" "$(count_of "$OUT321F" 'UNLOCKED-RAN')" "0"
check "and it said the shell suites were skipped, in one line" \
    "$(count_of "$OUT321F" 'Shell suites SKIPPED: this run is narrowed to OvationTests/SomeSuiteTests')" "1"
check "and the hosted suite did not run, and it said so" \
    "$(count_of "$OUT321F" 'HOSTED-SUITE-RAN'):$(count_of "$OUT321F" 'Hosted suite SKIPPED: this run is narrowed to OvationTests/SomeSuiteTests')" "0:1"

# 321c. THE PURE TEST FLOOR IS NOT APPLIED to a run that is part of the suite by
#       design, and that is said rather than skipped quietly (L98).
OUT321G="$(ONLY_FLOOR=500 only_run --only OvationTests/SomeSuiteTests)"; ST321G=$?
check "the pure test floor is not applied to a narrowed run" "$ST321G" "0"
check "and the run says the floor was not applied" \
    "$(count_of "$OUT321G" 'test floor NOT APPLIED')" "1"

# 321d. A RUN WITH NO --only HANDS ITS COMMANDS NO FILTER, EVEN ONE INHERITED. The
#       variable is exported to children, so a value left in the launching shell
#       would otherwise narrow a full run nobody asked to narrow (L169).
OUT321H="$(OVATION_ONLY_TESTING=OvationTests/Inherited only_run)"
check "a full run clears an inherited filter before its commands can see it" \
    "$(count_of "$OUT321H" '^FILTER=none$')" "2"

# 321e. THE REAL PURE COMMAND LINE CARRIES THE FILTER, and is still the pure scheme.
rm -f "$ONLY/xcodebuild-args"
OUT321I="$(ONLY_PATH="$ONLY/bin:$PATH" ONLY_PURE="" only_run --only OvationTests/SomeSuiteTests/itCountsRows)"; ST321I=$?
check "the real pure xcodebuild is narrowed with -only-testing" \
    "$ST321I:$(grep -cx -- '-only-testing:OvationTests/SomeSuiteTests/itCountsRows' "$ONLY/xcodebuild-args" 2>/dev/null)" "0:1"
check "and it still builds the pure scheme, so the app is not part of it" \
    "$(grep -cx 'OvationCore' "$ONLY/xcodebuild-args" 2>/dev/null)" "1"

# 321f. A NARROWED HOSTED RUN takes both locks, skips the pure suite and says so,
#       and hands the filter to its command.
OUT321J="$(ONLY_PURE='echo PURE-SUITE-RAN; echo "Test run with 3 tests in 1 suite passed"' \
    ONLY_HOSTED='echo "HOSTED-FILTER=${OVATION_ONLY_TESTING:-none}"; echo "Test run with 2 tests in 1 suite passed"' \
    only_run --only OvationHostedTests/LaunchTests)"; ST321J=$?
check "a narrowed hosted run passes" "$ST321J" "0"
check "and its command was handed the filter" \
    "$(count_of "$OUT321J" '^HOSTED-FILTER=OvationHostedTests/LaunchTests$')" "1"
check "and it ran only once both sibling locks were held" \
    "$([ "$(line_of "$OUT321J" 'Holding both locks')" -lt "$(line_of "$OUT321J" 'HOSTED-FILTER=')" ] 2>/dev/null && echo held-first || echo not-held)" "held-first"
check "and the pure suite did not run, and it said so" \
    "$(count_of "$OUT321J" 'PURE-SUITE-RAN'):$(count_of "$OUT321J" 'Pure suite SKIPPED: this run is narrowed to OvationHostedTests/LaunchTests')" "0:1"
mkdir -p "$DIR_LOCK"
OUT321K="$(TIMEOUT_OVERRIDE=1 ONLY_HOSTED='echo "HOSTED-FILTER=${OVATION_ONLY_TESTING:-none}"; echo "Test run with 2 tests in 1 suite passed"' \
    only_run --only OvationHostedTests/LaunchTests)"; ST321K=$?
rm -rf "$DIR_LOCK"
check "a narrowed hosted run waits on Downbeat's lock and does not run past it" \
    "$ST321K:$(count_of "$OUT321K" 'HOSTED-FILTER=')" "3:0"

# 321g. THE REAL HOSTED COMMAND LINE carries the filter IN PLACE of the whole
#       hosted target, not beside it.
rm -f "$ONLY/xcodebuild-args"
OUT321L="$(ONLY_PATH="$ONLY/bin:$PATH" ONLY_PURE="" ONLY_HOSTED="" only_run --only OvationHostedTests/LaunchTests)"; ST321L=$?
check "the real hosted xcodebuild is narrowed to the filter in place of the whole hosted target" \
    "$ST321L:$(grep -cx -- '-only-testing:OvationHostedTests/LaunchTests' "$ONLY/xcodebuild-args" 2>/dev/null):$(grep -cx -- '-only-testing:OvationHostedTests' "$ONLY/xcodebuild-args" 2>/dev/null)" "0:1:0"

# 321g2. A RUN WITH NO INJECTED COMMAND STILL RECORDS ITS WAIT (ovation#368). The
#        rule that silences staged runs must leave real ones exactly as they were,
#        or the fix would pass every staged case by recording nothing at all (L63).
#        The xcodebuild here is a stand in on PATH, which the runner treats as the
#        real one: its commands were not injected, so to the record it is real.
rm -f "$ONLY/lock-waits.tsv"
ONLY_PATH="$ONLY/bin:$PATH" ONLY_PURE="" ONLY_HOSTED="" only_run --only OvationHostedTests/LaunchTests >/dev/null 2>&1
check "a run with no injected command writes its wait to the record it names" \
    "$(sed -n 1p "$ONLY/lock-waits.tsv" 2>/dev/null | cut -f3)" "acquired"
REALHOME="$WORK/realhome"; rm -rf "$REALHOME"; mkdir -p "$REALHOME"
HOME="$REALHOME" ONLY_WAIT_LOG="" ONLY_PATH="$ONLY/bin:$PATH" ONLY_PURE="" ONLY_HOSTED="" \
    only_run --only OvationHostedTests/LaunchTests >/dev/null 2>&1
check "and with none named, to the default record under the home directory" \
    "$(sed -n 1p "$REALHOME/Library/Logs/Ovation/lock-waits.tsv" 2>/dev/null | cut -f3)" "acquired"

# 321h. NO TESTS EXECUTED IS A REFUSAL, whatever the exit code said (L98, L288).
check "a narrowed run that reported success and printed no count is refused" \
    "$(ONLY_PURE='echo "** TEST SUCCEEDED **"' only_run --only OvationTests/NoSuchSuite >/dev/null 2>&1; printf '%s' "$?")" "6"
OUT321M="$(ONLY_PURE='echo "Test run with 0 tests in 0 suites passed"' only_run --only OvationTests/NoSuchSuite)"; ST321M=$?
check "and so is one whose count says zero tests" "$ST321M" "6"
check "and it says the filter matched nothing, naming the filter" \
    "$(count_of "$OUT321M" 'OvationTests/NoSuchSuite matched nothing')" "1"
check "a narrowed run that FAILED keeps its own status rather than the refusal's" \
    "$(ONLY_PURE='echo "Test run with 3 tests in 1 suite failed"; exit 65' only_run --only OvationTests/SomeSuiteTests >/dev/null 2>&1; printf '%s' "$?")" "65"
OUT321N="$(ONLY_HOSTED='echo "** TEST SUCCEEDED **"' only_run --only OvationHostedTests/NoSuchSuite)"; ST321N=$?
check "a narrowed hosted run that executed no tests is refused, naming the filter" \
    "$ST321N:$(count_of "$OUT321N" 'OvationHostedTests/NoSuchSuite matched nothing')" "6:1"

# 321i. A STALE PROJECT IS REGENERATED FOR A NARROWED RUN. A new test file is the
#       normal case in test first work, so stopping would send every such run back
#       to a hand regeneration. The regeneration refuses WITHOUT waiting while the
#       build lock is held, so the runner waits for it, and says so (L110).
#
#       Both commands are stand ins: the currency check answers stale until the
#       regeneration has happened, and the regeneration refuses as many times as
#       it is told to first, with the real refusal's shape, on stderr.
REGEN="$ONLY/regen"; mkdir -p "$REGEN"
cat > "$REGEN/current" <<CURRENT
#!/bin/bash
if [ -e "$REGEN/regenerated" ]; then echo "OK: the generated project lists all 9 Swift files."; exit 0; fi
echo "REFUSED: the generated project does not list the Swift files on disk."
echo "    on disk, not in the project: OvationTests/BrandNewSuiteTests.swift"
exit 1
CURRENT
cat > "$REGEN/regenerate" <<REGENERATE
#!/bin/bash
echo "attempt \$OVATION_XCODE_PROJECT \$OVATION_DIR_LOCK" >> "$REGEN/attempts"
echo "wait \${OVATION_REGENERATE_WAIT:-none}" >> "$REGEN/args"
left="\$(cat "$REGEN/refusals" 2>/dev/null || echo 0)"
if [ "\$left" -gt 0 ]; then
    printf '%s\n' "\$((left - 1))" > "$REGEN/refusals"
    echo "REFUSED: $DIR_LOCK is held by downbeat:4242." >&2
    echo "         Nothing was touched." >&2
    exit 1
fi
if [ -e "$REGEN/fails" ]; then echo "REFUSED: xcodegen is not at /nowhere/xcodegen." >&2; exit 2; fi
[ -e "$REGEN/stays-stale" ] || : > "$REGEN/regenerated"
echo "OK: regenerated the stand in project."
REGENERATE
chmod +x "$REGEN/current" "$REGEN/regenerate"
reset_regen() { rm -f "$REGEN/regenerated" "$REGEN/attempts" "$REGEN/args" "$REGEN/refusals" "$REGEN/stays-stale" "$REGEN/fails"; }
regen_run() { ONLY_CURRENT="'$REGEN/current'" ONLY_REGENERATE="'$REGEN/regenerate'" only_run "$@"; }
PURE_MARKED='echo PURE-SUITE-RAN; echo "Test run with 3 tests in 1 suite passed"'

reset_regen; printf '3\n' > "$REGEN/refusals"
OUT321O="$(ONLY_PURE="$PURE_MARKED" regen_run --only OvationTests/BrandNewSuiteTests)"; ST321O=$?
check "a narrowed run over a stale project regenerates it and passes" "$ST321O" "0"
check "and it waited out the regeneration's refusals rather than stopping at the first" \
    "$(grep -c attempt "$REGEN/attempts" 2>/dev/null)" "4"
check "and it printed the refusal's own words once, when it first refused" \
    "$(count_of "$OUT321O" 'held by downbeat:4242')" "1"
# AND EACH ATTEMPT HOLDS ITS PLACE IN THE QUEUE (ovation#542). A regeneration that
# refuses and is called again joins at the back each time, and under sibling
# traffic never gets a turn, so every attempt is asked to wait, for no longer than
# this run has left of its own deadline (2s here, OVATION_LOCK_TIMEOUT in only_run).
check "and every attempt was asked to wait in the queue, within this run's deadline" \
    "$(grep -c -v -E '^wait [0-2]$' "$REGEN/args" 2>/dev/null):$(grep -c . "$REGEN/args" 2>/dev/null)" "0:4"
check "and the regeneration was pointed at this run's project and build lock" \
    "$(sort -u "$REGEN/attempts" 2>/dev/null)" "attempt $STANDIN_PROJECT $DIR_LOCK"
check "and the suite ran only after the project was regenerated" \
    "$([ "$(line_of "$OUT321O" 'OK: regenerated')" -lt "$(line_of "$OUT321O" 'PURE-SUITE-RAN')" ] 2>/dev/null && echo regenerated-first || echo ran-first)" "regenerated-first"

reset_regen; : > "$REGEN/stays-stale"
OUT321P="$(ONLY_PURE="$PURE_MARKED" regen_run --only OvationTests/BrandNewSuiteTests)"; ST321P=$?
check "a project still stale after regenerating is refused by name" \
    "$ST321P:$(count_of "$OUT321P" "$STANDIN_PROJECT was regenerated and still does not list")" "1:1"
check "and the suite was not built from it" "$(count_of "$OUT321P" 'PURE-SUITE-RAN')" "0"

reset_regen; printf '100000\n' > "$REGEN/refusals"
OUT321Q="$(TIMEOUT_OVERRIDE=1 ONLY_PURE="$PURE_MARKED" regen_run --only OvationTests/BrandNewSuiteTests)"; ST321Q=$?
check "a regeneration refused for the whole wait gives up with the lock wait's status and says so" \
    "$ST321Q:$(count_of "$OUT321Q" 'gave up waiting to regenerate')" "3:1"
check "and the suite was not built from the stale project" "$(count_of "$OUT321Q" 'PURE-SUITE-RAN')" "0"

reset_regen; : > "$REGEN/fails"
OUT321R="$(ONLY_PURE="$PURE_MARKED" regen_run --only OvationTests/BrandNewSuiteTests)"; ST321R=$?
check "a regeneration that fails outright is not waited on, and keeps its own status and words" \
    "$ST321R:$(count_of "$OUT321R" 'xcodegen is not at'):$(grep -c attempt "$REGEN/attempts" 2>/dev/null)" "2:1:1"

# 321j. THE FULL RUN KEEPS TODAY'S BEHAVIOUR for a stale project: it stops, by the
#       check's own words, and regenerates nothing (ovation#206).
reset_regen
OUT321S="$(regen_run)"; ST321S=$?
check "a full run over a stale project still stops without regenerating" \
    "$ST321S:$([ -e "$REGEN/attempts" ] && echo regenerated || echo untouched)" "1:untouched"
reset_regen

# ---------------------------------------------------------------------------
# THE DIRECTORY LOCK IS SERVED IN ARRIVAL ORDER (downbeat#524).
#
# Every waiter on Downbeat's lock used to retry on its own timer, and whoever
# looked first after a release won. On 2026-09-24 a Downbeat run waited 15 to 20
# minutes three times behind newer runs and a push failed on its deadline having
# run nothing. lib/lock-queue.sh keeps a queue BESIDE the lock, "<lock>.queue",
# and a waiter may try mkdir only while no live earlier ticket is queued. These
# cases stage tickets in the throwaway queue beside $DIR_LOCK, never the real one.
queue_tickets() { ls "$DIR_LOCK.queue" 2>/dev/null | wc -l | tr -d ' '; }
queue_has_tickets() { [ "$(queue_tickets)" -ge "$1" ]; }
live_ticket_for() {
    mkdir -p "$DIR_LOCK.queue"
    printf '%s %s\n' "$1" "$(ps -o lstart= -p "$1" | sed 's/^ *//; s/ *$//')" \
        > "$DIR_LOCK.queue/00000000001.000000.$1"
}

# 524a. A LIVE WAITER THAT ARRIVED EARLIER HOLDS THE TURN EVEN WHEN THE LOCK IS
#       FREE. Taking it anyway is exactly the barging the queue exists to stop.
rm -rf "$DIR_LOCK" "$DIR_LOCK.queue"
sleep 60 & EARLIER524=$!; disown "$EARLIER524" 2>/dev/null
harness_on_exit "kill $EARLIER524 2>/dev/null"
live_ticket_for "$EARLIER524"
OUT524A="$(TIMEOUT_OVERRIDE=1 run_runner "echo HOSTED-524A-RAN; $HOSTED_PASSES")"; ST524A=$?
check "a run behind an earlier queued waiter does not take a free lock, and gives up" \
    "$ST524A:$(count_of "$OUT524A" 'HOSTED-524A-RAN')" "3:0"
check "and it says it is queued behind an earlier run, and again when it gives up" \
    "$(count_of "$OUT524A" '1 earlier run')" "2"
check "and the run that gave up leaves the queue, and the earlier ticket stands" \
    "$(ls "$DIR_LOCK.queue" 2>/dev/null | tr '\n' ' ')" "00000000001.000000.$EARLIER524 "
kill "$EARLIER524" 2>/dev/null
rm -rf "$DIR_LOCK" "$DIR_LOCK.queue"

# 524b. TWO RUNS WAITING ON A HELD LOCK GO IN THE ORDER THEY ARRIVED. The LATER one
#       polls eight times as often, so without the queue it is the one that looks
#       first after the release and usually wins. With both on one rhythm the
#       earlier run's poll always landed first and this passed with the queue
#       switched off, which Downbeat measured before splitting the rhythms (L1).
: > "$WORK/order524"
mkdir -p "$DIR_LOCK"; printf 'downbeat:524\n' > "$DIR_LOCK/owner"
( TIMEOUT_OVERRIDE=30 POLL_OVERRIDE=0.8 \
    run_runner "echo first >> '$WORK/order524'; $HOSTED_PASSES" >/dev/null 2>&1 ) &
FIRST524=$!
harness_wait_for "the first run to join the queue (524b)" 200 0.05 queue_has_tickets 1
( TIMEOUT_OVERRIDE=30 POLL_OVERRIDE=0.1 \
    run_runner "echo second >> '$WORK/order524'; $HOSTED_PASSES" >/dev/null 2>&1 ) &
SECOND524=$!
harness_wait_for "the second run to join the queue (524b)" 200 0.05 queue_has_tickets 2
rm -rf "$DIR_LOCK"
wait "$FIRST524" "$SECOND524"
check "two waiting runs take the lock in the order they arrived" \
    "$(tr '\n' ' ' < "$WORK/order524")" "first second "
check "and the queue is empty once both have run" "$(queue_tickets)" "0"
rm -rf "$DIR_LOCK" "$DIR_LOCK.queue"

# 524d. A STOPPED WAITER ENDS, and takes its ticket with it. A trap on TERM that
#       only cleaned up would return to the loop, which would rejoin the queue at
#       the back and wait on (L473): Downbeat shipped exactly that and caught it
#       with this case. The holder's lock is not this run's and must be untouched.
mkdir -p "$DIR_LOCK"; printf 'downbeat:524d\n' > "$DIR_LOCK/owner"
( TIMEOUT_OVERRIDE=30 run_runner > "$WORK/stopped524.out" 2>&1 ) &
STOPPED524=$!
harness_wait_for "the waiter to join the queue (524d)" 200 0.05 queue_has_tickets 1
WAITER524="$(ls "$DIR_LOCK.queue" | head -1)"; WAITER524="${WAITER524##*.}"
kill -TERM "$WAITER524" 2>/dev/null
wait "$STOPPED524"; ST524D=$?
check "a waiter stopped with TERM ends with 143 rather than waiting on" "$ST524D" "143"
check "and it leaves the queue empty, and the holder's lock untouched" \
    "$(queue_tickets):$(head -1 "$DIR_LOCK/owner" 2>/dev/null)" "0:downbeat:524d"
rm -rf "$DIR_LOCK" "$DIR_LOCK.queue"

# 524c. A NARROWED RUN'S OWN REGENERATION IS NEVER QUEUED BEHIND THE RUN ITSELF.
#       The runner calls regenerate-xcode-project.sh, which takes the same lock
#       through the same queue and refuses while any live earlier ticket stands. A
#       runner that joined the queue before regenerating would hold exactly such a
#       ticket, and would wait on its own child until its deadline. So this runs
#       the REAL regenerator, with a stand in generator writing only into this
#       suite's temp directory (L2), and the runner must get through it.
cat > "$REGEN/xcodegen" <<GENERATOR
#!/bin/bash
: > "$REGEN/regenerated"
mkdir -p "\$OVATION_XCODE_PROJECT"
GENERATOR
chmod +x "$REGEN/xcodegen"
reset_regen
OUT524C="$(OVATION_XCODEGEN="$REGEN/xcodegen" TIMEOUT_OVERRIDE=3 ONLY_PURE="$PURE_MARKED" \
    ONLY_CURRENT="'$REGEN/current'" ONLY_REGENERATE="'$PWD/scripts/regenerate-xcode-project.sh'" \
    only_run --only OvationTests/BrandNewSuiteTests)"; ST524C=$?
check "a narrowed run's real regeneration is not queued behind the run itself" \
    "$ST524C:$(count_of "$OUT524C" 'OK: regenerated'):$(count_of "$OUT524C" 'PURE-SUITE-RAN')" "0:1:1"
check "and it leaves no ticket behind" "$(queue_tickets)" "0"
reset_regen
rm -rf "$DIR_LOCK" "$DIR_LOCK.queue" "$STANDIN_PROJECT"; mkdir -p "$STANDIN_PROJECT"

# ---------------------------------------------------------------------------
# A NARROWED PURE RUN BUILDS THE APP WHEN A FILE THE PURE TARGET LEAVES OUT HAS
# CHANGED (ovation#515). OvationTests compiles the app's sources in and excludes
# OvationApp.swift, which carries @main, so a narrowed run never compiled it. On
# 2026-09-24 removing an import that file still needed passed every narrowed run
# and failed the push gate's hosted phase about ten minutes in.
#
# The checkout asked is the throwaway one above, and the build is a stand in, so
# nothing here compiles anything (L2). Each case puts the fixture back to main.
# ---------------------------------------------------------------------------
reset_app() { appgit reset -q --hard origin/main; appgit clean -qfd; }

# 515a. NOTHING LEFT OUT HAS CHANGED: no app build, and the run says so, naming
#       what it compared, so a skip never reads as a build that passed (L98).
reset_app
OUT515A="$(ONLY_PURE="$PURE_MARKED" only_run --only OvationTests/SomeSuiteTests)"; ST515A=$?
check "a narrowed pure run with nothing left out changed passes without building the app" \
    "$ST515A:$(count_of "$OUT515A" 'APP-BUILD-RAN')" "0:0"
check "and it says the app build was not needed, naming the file it compared" \
    "$(count_of "$OUT515A" 'App build not needed.*Ovation/App/OvationApp.swift')" "1"

# 515b. AN UNCOMMITTED EDIT TO OvationApp.swift builds the app, BEFORE the suite.
reset_app
printf '// edited\n' >> "$APPREPO/Ovation/App/OvationApp.swift"
OUT515B="$(ONLY_PURE="$PURE_MARKED" only_run --only OvationTests/SomeSuiteTests)"; ST515B=$?
check "an uncommitted edit to OvationApp.swift makes a narrowed pure run build the app" \
    "$ST515B:$(count_of "$OUT515B" 'APP-BUILD-RAN')" "0:1"
check "and the app is built before the narrowed suite runs" \
    "$([ "$(line_of "$OUT515B" 'APP-BUILD-RAN')" -lt "$(line_of "$OUT515B" 'PURE-SUITE-RAN')" ] 2>/dev/null && echo built-first || echo not-first)" "built-first"
check "and it names the changed file as the reason" \
    "$(count_of "$OUT515B" 'Ovation/App/OvationApp.swift differs from origin/main')" "1"

# 515c. A COMMITTED EDIT on the branch, with a clean tree, still counts: the push
#       gate judges commits, not the working tree.
reset_app
printf '// committed\n' >> "$APPREPO/Ovation/App/OvationApp.swift"
appgit commit -qam edit
OUT515C="$(ONLY_PURE="$PURE_MARKED" only_run --only OvationTests/SomeSuiteTests)"; ST515C=$?
check "a committed edit to OvationApp.swift on a clean tree also builds the app" \
    "$ST515C:$(count_of "$OUT515C" 'APP-BUILD-RAN')" "0:1"

# 515d. THE OTHER LEFT OUT FILE, read from the same project.yml entry, counts too,
#       and a file the pure target DOES compile does not.
reset_app
printf '<!-- edited -->\n' >> "$APPREPO/Ovation/Info.plist"
OUT515D="$(ONLY_PURE="$PURE_MARKED" only_run --only OvationTests/SomeSuiteTests)"
check "an edit to Info.plist, which the pure target also leaves out, builds the app" \
    "$(count_of "$OUT515D" 'APP-BUILD-RAN')" "1"
reset_app
printf '// edited\n' >> "$APPREPO/Ovation/Other.swift"
OUT515E="$(ONLY_PURE="$PURE_MARKED" only_run --only OvationTests/SomeSuiteTests)"
check "an edit only to a file the pure target compiles builds no app" \
    "$(count_of "$OUT515E" 'APP-BUILD-RAN')" "0"

# 515e. AN APP THAT DOES NOT BUILD STOPS THE RUN with the build's own status,
#       before the suite, and says which file and what to run (L148, L399).
reset_app
printf '// edited\n' >> "$APPREPO/Ovation/App/OvationApp.swift"
OUT515F="$(ONLY_PURE="$PURE_MARKED" ONLY_APP_BUILD='echo "error: cannot find type MailSender in scope"; exit 65' \
    only_run --only OvationTests/SomeSuiteTests)"; ST515F=$?
check "a narrowed run whose app does not build fails with the build's status and runs no suite" \
    "$ST515F:$(count_of "$OUT515F" 'PURE-SUITE-RAN')" "65:0"
check "and it says the app did not build, naming the file the pure target never compiles" \
    "$(count_of "$OUT515F" 'the app did not build.*OvationApp.swift')" "1"

# 515f. WHEN THE COMPARISON CANNOT BE MADE, THE APP IS BUILT. Building costs a
#       minute; not building is the defect this exists to end (L93).
reset_app
OUT515G="$(ONLY_PURE="$PURE_MARKED" ONLY_APP_BASE=origin/no-such-branch only_run --only OvationTests/SomeSuiteTests)"; ST515G=$?
check "a base that cannot be found builds the app rather than assuming nothing changed" \
    "$ST515G:$(count_of "$OUT515G" 'APP-BUILD-RAN')" "0:1"
check "and it says why it built" \
    "$(count_of "$OUT515G" 'could not compare .* with origin/no-such-branch')" "1"
APPREPO2="$WORK/app-changes-no-excludes"; rm -rf "$APPREPO2"; cp -R "$APPREPO" "$APPREPO2"
printf 'targets: {}\n' > "$APPREPO2/project.yml"
git -C "$APPREPO2" -c user.name=suite -c user.email=suite@example.invalid -c commit.gpgsign=false commit -qam "no excludes"
git -C "$APPREPO2" update-ref refs/remotes/origin/main HEAD
OUT515H="$(ONLY_PURE="$PURE_MARKED" ONLY_APP_ROOT="$APPREPO2" only_run --only OvationTests/SomeSuiteTests)"; ST515H=$?
check "a project.yml the left out files cannot be read from builds the app, and says so" \
    "$ST515H:$(count_of "$OUT515H" 'APP-BUILD-RAN'):$(count_of "$OUT515H" 'could not read which files the pure target leaves out')" "0:1:1"

# 515g. ONLY THE NARROWED PURE RUN. A narrowed hosted run and a full run both
#       build the app already, through the hosted scheme, so neither builds it twice.
reset_app
printf '// edited\n' >> "$APPREPO/Ovation/App/OvationApp.swift"
OUT515I="$(only_run --only OvationHostedTests/LaunchTests)"
check "a narrowed hosted run does not build the app a second time" \
    "$(count_of "$OUT515I" 'APP-BUILD-RAN')" "0"
OUT515J="$(only_run)"
check "and neither does a full run" "$(count_of "$OUT515J" 'APP-BUILD-RAN')" "0"

# 515h. AN INJECTED PURE COMMAND WITH NO APP BUILD NAMED BUILDS NOTHING REAL, and
#       says so, for the same reason the hosted suite is skipped then (L2).
OUT515K="$(ONLY_PURE="$PURE_MARKED" ONLY_APP_BUILD="" ONLY_PATH="$ONLY/bin:$PATH" \
    only_run --only OvationTests/SomeSuiteTests)"; ST515K=$?
check "an injected pure command with no app build named skips the build and says so" \
    "$ST515K:$(count_of "$OUT515K" 'App build skipped: the pure command was injected')" "0:1"

# 515i. THE REAL BUILD IS THE APP SCHEME, Debug, through the one place the app
#       build is written (scripts/lib/build-one-configuration.sh).
APPBIN="$WORK/app-bin"; rm -rf "$APPBIN"; mkdir -p "$APPBIN"
cat > "$APPBIN/xcodebuild" <<STUB
#!/bin/bash
printf '%s ' "\$@" >> "$APPBIN/calls"; printf '\n' >> "$APPBIN/calls"
echo "Test run with 3 tests in 1 suite passed"
STUB
chmod +x "$APPBIN/xcodebuild"
OUT515L="$(ONLY_PATH="$APPBIN:$PATH" ONLY_PURE="" ONLY_APP_BUILD="" only_run --only OvationTests/SomeSuiteTests)"; ST515L=$?
check "the real app build is the Ovation scheme in Debug, before the pure scheme" \
    "$ST515L:$(sed -n 1p "$APPBIN/calls" 2>/dev/null | grep -c -- '-scheme Ovation -configuration Debug'):$(sed -n 2p "$APPBIN/calls" 2>/dev/null | grep -c -- '-scheme OvationCore')" "0:1:1"
reset_app


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
check "every invocation of the real runner sets flock, the project and the domain lister" \
    "$(python3 - "$TARGET_SUITE" <<'PYSEAMS'
import re
import sys
lines = open(sys.argv[1]).read().splitlines()
# ASSEMBLED FROM PIECES so this program contains no literal instance of what it
# looks for. Written whole, it matched its own source and reported itself as an
# offender, which is the same trap `check-ported-artifacts.sh` records (L245).
# ANY ARGUMENTS BETWEEN THE RUNNER AND ITS REDIRECT STILL COUNT (ovation#321). The
# needle was the runner followed directly by the redirect, so the first calls
# that passed the runner an argument walked past this guard unexamined (L247).
needle = re.compile(re.escape("$TAR" + "GET") + '"' + r"( .*)? 2>&1")
missing = []
for index, line in enumerate(lines):
    if not needle.search(line):
        continue
    window = "\n".join(lines[max(0, index - 15):index + 1])
    for seam in ("OVATION_FLOCK_BIN", "OVATION_XCODE_PROJECT", "OVATION_DEFAULTS_DOMAINS_COMMAND"):
        if seam not in window:
            missing.append("line %d:%s" % (index + 1, seam))
print(" ".join(missing))
PYSEAMS
)" ""


harness_end
