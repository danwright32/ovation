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
# THE FLOOR SEAM IS CLEARED FIRST. It is an environment variable, so a value set
# in the shell that launched this suite is inherited by every runner spawned
# below and silently answers for them (L169). Measured: exporting
# OVATION_TEST_FLOOR=9999 to prove the guard fires on the real suite made six of
# these cases fail instead, because their child runners inherited it too.
unset OVATION_TEST_FLOOR

harness_begin "test runner lock tests" 38

TARGET="scripts/run-tests.sh"
REPO_ROOT_SCRIPTS="$PWD/scripts"
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
    OVATION_LOCK_POLL_INTERVAL="${POLL_OVERRIDE:-0.05}" \
    OVATION_FLOCK_BIN="${FLOCK_OVERRIDE:-/opt/homebrew/bin/flock}" \
    OVATION_TEST_COMMAND="${1:-true}" \
    OVATION_UNLOCKED_COMMAND="${2:-true}" \
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
    # Held until the test RELEASES it, not for a fixed number of seconds. A
    # timed holder asserts about machine load: too short and it lets go before
    # the test has observed anything, too long and every run pays for it (L290).
    HOLD_SENTINEL="$WORK/hold-1"; : > "$HOLD_SENTINEL"
    ( /opt/homebrew/bin/flock "$FILE_LOCK" bash -c 'while [ -e "$1" ]; do sleep 0.02; done' _ "$HOLD_SENTINEL" ) &
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
    rm -f "$HOLD_SENTINEL"
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
if [ -x "/opt/homebrew/bin/flock" ]; then
    : > "$FILE_LOCK"
    HOLD_SENTINEL2="$WORK/hold-2"; : > "$HOLD_SENTINEL2"
    ( /opt/homebrew/bin/flock "$FILE_LOCK" bash -c 'while [ -e "$1" ]; do sleep 0.02; done' _ "$HOLD_SENTINEL2" ) &
    HOLDER2=$!
    waited=0
    while /opt/homebrew/bin/flock -n "$FILE_LOCK" true 2>/dev/null; do
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
else
    check "Downbeat's lock is released between attempts, not held for the whole wait" "skip" "skip"
    check "and neither lock is left behind afterwards" "skip" "skip"
fi

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
    "$TARGET" 2>&1
}
hosted_status() { hosted_run "$1" >/dev/null 2>&1; printf '%s' "$?"; }

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
    "$TARGET" 2>&1
}
pure_status() { pure_run "$1" "${2:-100}" >/dev/null 2>&1; printf '%s' "$?"; }

check "a pure run at the floor passes" \
    "$(pure_status 'echo "Test run with 100 tests in 9 suites passed"' 100)" "0"
check "a pure run above the floor passes" \
    "$(pure_status 'echo "Test run with 294 tests in 29 suites passed"' 100)" "0"
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

harness_end
