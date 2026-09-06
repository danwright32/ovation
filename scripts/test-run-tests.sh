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
harness_begin "test runner lock tests" 16

TARGET="scripts/run-tests.sh"
require_target "$TARGET"
harness_temp_dir WORK

DIR_LOCK="$WORK/dir.lock"
FILE_LOCK="$WORK/file.lock"

# The runner is driven with a trivial command instead of xcodebuild, so these
# cases measure the LOCKING and not a three minute build (L2, L291).
run_runner() {
    OVATION_DIR_LOCK="$DIR_LOCK" \
    OVATION_FILE_LOCK="$FILE_LOCK" \
    OVATION_LOCK_TIMEOUT="${TIMEOUT_OVERRIDE:-2}" \
    OVATION_FLOCK_BIN="${FLOCK_OVERRIDE:-/opt/homebrew/bin/flock}" \
    OVATION_TEST_COMMAND="${1:-true}" \
        "./$TARGET" 2>&1
}

# 1. Nothing held: it runs, and it runs the command it was given.
OUT1="$(run_runner "echo THE-COMMAND-RAN")"; ST1=$?
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
if [ -x "/opt/homebrew/bin/flock" ]; then
    : > "$FILE_LOCK"
    ( /opt/homebrew/bin/flock "$FILE_LOCK" sleep 5 ) &
    HOLDER=$!
    # Wait for the holder to actually HAVE the lock, rather than sleeping and
    # hoping: a fixed wait asserts about machine load, not about the lock (L290).
    waited=0
    while /opt/homebrew/bin/flock -n "$FILE_LOCK" true 2>/dev/null; do
        waited=$((waited+1)); [ "$waited" -gt 100 ] && break; sleep 0.05
    done
    OUT4="$(run_runner)"; ST4=$?
    check "Overture's file lock also stops Ovation running" \
        "$([ "$ST4" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
    check "and it names that lock too" \
        "$(mentions "$OUT4" "$FILE_LOCK")" "yes"
    kill "$HOLDER" 2>/dev/null || true
    wait "$HOLDER" 2>/dev/null || true
else
    check "Overture's file lock also stops Ovation running" "skipped-no-flock" "skipped-no-flock"
    check "and it names that lock too" "skipped-no-flock" "skipped-no-flock"
fi

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

harness_end
