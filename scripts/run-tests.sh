#!/usr/bin/env bash
# Ported-From: danwright32/downbeat scripts/run-tests.sh @ 563865a7e8a93c678e6eed38c86281c8d9a730d0
#
# Run Ovation's tests while genuinely excluding BOTH sibling apps.
#
# THE DECISION, MADE BY DAN ON 2026-09-05 (ovation#12, option A). Three macOS
# apps share this Mac and running two xcodebuild suites at once corrupts both
# runs, which teaches Dan to distrust a red suite. That is the exact failure
# Downbeat's own runner says its lock exists to prevent, and its header asserts
# the lock "is shared with Overture deliberately". That is NOT TRUE:
# xcodebuild-tests.lock appears nowhere in Overture's tree, so the two have never
# excluded each other. Filed as overture#3571.
#
# Ovation takes BOTH existing locks, by the mechanism each one uses, in a FIXED
# ORDER, and changes nothing in either sibling.
#
#   1. mkdir on /tmp/xcodebuild-tests.lock       Downbeat's, a DIRECTORY
#   2. flock on /tmp/overture-mac-tests.lock     Overture's, a FILE
#
# They cannot be merged into one path. flock opens with O_CREAT and cannot open
# an existing directory that way; mkdir on a path already holding a regular file
# returns EEXIST, which Downbeat's loop reads as "lock held" and then waits out
# its thirty minute timeout. So each is taken by its own means.
#
# THE ORDER IS FIXED AND THAT IS WHAT MAKES DEADLOCK IMPOSSIBLE. Neither sibling
# takes two locks, so nothing can hold Overture's while waiting for Downbeat's.
# A future version taking them in the opposite order reintroduces the classic
# deadlock, which is why the order is asserted by the suite.
#
# WHY NOT CONVERT OVERTURE TO ONE MECHANISM (option B, declined): flock is
# released by the kernel when its holder dies and a mkdir lock is NOT, which is
# why Downbeat carries claim-stale-lock.sh and a 1800 second timeout. Converting
# Overture without bringing that across would trade a crash safe lock for one
# that parks a stuck lock for half an hour (L409).
#
# Because the directory lock does not self clear, THE TRAP IS THE WHOLE OF
# OVATION'S CRASH SAFETY on that half, and it runs on every exit path rather than
# only the tidy one (L515, L514).
#
# THE LOCKS ARE SCOPED TO THE WORK THAT ACTUALLY NEEDS THEM, and that was learned
# on the first real use rather than reasoned out. Minutes after this shipped, a
# push ran the hook, which ran this runner, which took Downbeat's lock and then
# waited on Overture's, which a real Overture suite had held for four minutes.
# The lock was working exactly as intended. What was wrong is that it made the
# SHELL suites wait too, and they run no xcodebuild and share nothing with either
# sibling. A gate that queues its cheap checks behind another app's build is a
# gate people learn to skip (L378, L299).
#
# So: the unlocked work runs FIRST and fails fast, and the locks are taken only
# around the xcodebuild run.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DIR_LOCK="${OVATION_DIR_LOCK:-/tmp/xcodebuild-tests.lock}"
FILE_LOCK="${OVATION_FILE_LOCK:-/tmp/overture-mac-tests.lock}"
TIMEOUT="${OVATION_LOCK_TIMEOUT:-1800}"
# The poll interval is a seam from the day it is written, not a retrofit. A hard
# coded delay makes every test that crosses this loop wait for real, and this
# loop is crossed by every case that stages a held lock (L524, L290). The default
# is what a person waiting on a sibling's build should pay; a test sets it low
# and exercises the same code instantly.
POLL="${OVATION_LOCK_POLL_INTERVAL:-1}"
FLOCK_BIN="${OVATION_FLOCK_BIN:-/opt/homebrew/bin/flock}"
TEST_COMMAND="${OVATION_TEST_COMMAND:-}"
HOSTED_TEST_COMMAND="${OVATION_HOSTED_TEST_COMMAND:-}"
UNLOCKED_COMMAND="${OVATION_UNLOCKED_COMMAND:-}"

DIR_LOCK_HELD=""
FLOCK_FD=""

# Released on EVERY exit path, not only the tidy one. A directory lock left
# planted blocks the next run of a DIFFERENT app, which is the failure this
# whole thing exists to prevent.
release_locks() {
  [ -n "${FLOCK_FD}" ] && eval "exec ${FLOCK_FD}>&-" 2>/dev/null || true
  [ -n "${DIR_LOCK_HELD}" ] && rm -rf "${DIR_LOCK}" 2>/dev/null || true
  DIR_LOCK_HELD=""
  FLOCK_FD=""
}
trap release_locks EXIT INT TERM

# Ovation does not own flock, it inherits the dependency from Overture, so this
# is the one that will be absent on a fresh machine. Say so BY NAME with the
# remedy rather than failing obscurely: a refusal whose message does not say what
# to do leaves the reader facing the same command with no way to learn why (L148).
# ---------------------------------------------------------------------------
# PHASE ONE, unlocked. Nothing here touches xcodebuild or any shared state, so
# it must not wait behind a sibling's build.
# ---------------------------------------------------------------------------
# EVERY SUITE IS ASKED, AND EACH ANSWER IS KEPT (ovation#139).
#
# This loop was `"$s" || exit $?`, so the FIRST suite that did not exit 0 ended
# the whole run. Two of them correctly answer CANNOT MEASURE (exit 2) when there
# is no compiled product, which is the normal state of a fresh checkout or
# worktree, and they sort early in the glob. Measured on 2026-09-08 in a fresh
# worktree: every shell suite passed when invoked on its own, and this reported
# four of the thirty three.
#
# THREE VERDICTS, AND THE LOCKED PHASE TREATS TWO OF THEM DIFFERENTLY:
#
#   pass            nothing to say.
#   fail            something is actually broken, so nothing after it is worth
#                   the sibling locks. The run stops here, as it always did, and
#                   keeps the suite's own status.
#   cannot measure  the suite proved nothing either way, which is a reason to
#                   refuse the run at the END and no reason at all to stop
#                   asking the other suites or to skip xcodebuild. The verdict is
#                   carried to the exit and the run continues.
#
# A stop and a real failure both used to come out as "non-zero" with the reader
# left to work out which by looking at where it stopped (L11). The summary below
# is what tells them apart, so it prints on every path including the green one.
#
# THE COUNT IS JUDGED, NOT ONLY THE VERDICTS (L288). `[ -x "$s" ] || continue`
# drops a suite that lost its executable bit in silence, and a glob that matches
# fewer files reads as a full green run. The floor is a committed number for the
# same reason the pure suite's is: refusing only an empty run would catch the
# total loss and miss every partial one.
SUITE_DIR="${OVATION_SHELL_SUITE_DIR:-${REPO_ROOT}/scripts}"
SUITE_FLOOR="${OVATION_SHELL_SUITE_FLOOR:-}"
SHELL_UNMEASURED=""

if [ -n "${UNLOCKED_COMMAND}" ]; then
  bash -c "${UNLOCKED_COMMAND}" || exit $?
else
  echo "==> Running the shell suites (no lock needed)"
  suites_ran=0
  suites_passed=0
  failed_status=0
  failed_names=""
  unmeasured_names=""
  for s in "${SUITE_DIR}"/test-*.sh; do
    [ -x "$s" ] || continue
    suites_ran=$((suites_ran+1))
    "$s"
    suite_status=$?
    suite_name="$(basename "$s")"
    if [ "${suite_status}" -eq 0 ]; then
      suites_passed=$((suites_passed+1))
    elif [ "${suite_status}" -eq 2 ]; then
      unmeasured_names="${unmeasured_names}${suite_name} "
    else
      failed_names="${failed_names}${suite_name} "
      failed_status="${suite_status}"
      break
    fi
  done

  # ONE SUMMARY, WHATEVER HAPPENED, so a green run and a short run do not look
  # alike and neither outcome is readable only by scrolling back through
  # thirty three suites' output.
  echo "==> Shell suites: ${suites_ran} ran, ${suites_passed} passed, verdicts below"
  [ -n "${failed_names}" ] && echo "    failed: ${failed_names% }"
  [ -n "${unmeasured_names}" ] && echo "    could not measure: ${unmeasured_names% }"

  if [ "${failed_status}" -ne 0 ]; then
    echo "    the run stops here: a failing suite means nothing after it is worth" >&2
    echo "    taking the sibling locks for." >&2
    exit "${failed_status}"
  fi

  # The floor is checked only when nothing FAILED, because a failure breaks out
  # of the loop and the short count is then a consequence of the failure rather
  # than a fact about the tree. Reporting both would name the wrong cause (L11).
  if [ -n "${OVATION_SHELL_SUITE_DIR:-}" ] && [ -z "${SUITE_FLOOR}" ]; then
    # Said out loud rather than skipped silently, the same way the pure count
    # skip is: a run driven with throwaway suites cannot be judged against the
    # real floor, and a skip nobody is told about is indistinguishable from a
    # check that passed (L98, L320).
    echo "==> Shell suite count check skipped: the suite directory was injected and no floor was given."
  else
    SHELL_FLOOR_FILE="${REPO_ROOT}/scripts/shell-suite-floor.txt"
    SUITE_FLOOR="${SUITE_FLOOR:-$(cat "${SHELL_FLOOR_FILE}" 2>/dev/null || echo 0)}"
    if [ "${SUITE_FLOOR}" -eq 0 ]; then
      echo "Error: no shell suite floor to judge the run against (${SHELL_FLOOR_FILE})." >&2
      echo "       A run nothing can be compared to is not a green run." >&2
      exit 7
    elif [ "${suites_ran}" -lt "${SUITE_FLOOR}" ]; then
      echo "Error: the shell suites ran ${suites_ran} of a floor of ${SUITE_FLOOR}." >&2
      echo "       Suites are found by glob and skipped when not executable, so" >&2
      echo "       this is a suite that lost its executable bit, was renamed, or" >&2
      echo "       was deleted. Nothing about the missing ones was judged." >&2
      echo "       If suites were deliberately removed, lower ${SHELL_FLOOR_FILE}." >&2
      exit 7
    fi
  fi

  # Carried to the exit rather than acted on here. It is not a reason to skip
  # xcodebuild, and it IS a reason for the run to end non-zero.
  [ -n "${unmeasured_names}" ] && SHELL_UNMEASURED=1
fi

# ---------------------------------------------------------------------------
# PHASE TWO, locked. Only xcodebuild needs to exclude the siblings.
# ---------------------------------------------------------------------------
if [ ! -x "${FLOCK_BIN}" ]; then
  echo "Error: flock was not found at ${FLOCK_BIN}." >&2
  echo "       Ovation's test runner takes Overture's lock, which uses it." >&2
  echo "       Install it with: brew install flock" >&2
  echo "       Refusing to run the tests without excluding the sibling apps." >&2
  exit 2
fi

# BOTH LOCKS, TAKEN WITHOUT EVER HOLDING ONE WHILE WAITING FOR THE OTHER.
#
# The first version took Downbeat's, then waited on Overture's. On its first real
# use it sat there for four minutes, and for all of that time DOWNBEAT could not
# run either: blocked by Overture, through Ovation, a coupling nobody chose and
# which neither sibling can see or diagnose.
#
# So the second is tried WITHOUT BLOCKING, and if it is not free the first is
# RELEASED before waiting and trying again. Ovation waits for both and holds
# neither while waiting. The fixed order still stands for the acquisition itself,
# and since nothing is ever held across a wait there is nothing to deadlock on.
echo "==> Waiting for both test locks (${DIR_LOCK}, ${FILE_LOCK})"
: > "${FILE_LOCK}" 2>/dev/null || true
elapsed=0
while :; do
  if mkdir "${DIR_LOCK}" 2>/dev/null; then
    DIR_LOCK_HELD=1
    printf '%s:%s\n' "$(basename "${REPO_ROOT}")" "$$" > "${DIR_LOCK}/owner" 2>/dev/null || true
    # Non blocking. If Overture has it, we do not queue holding Downbeat's.
    exec 9>"${FILE_LOCK}" || { echo "Error: cannot open ${FILE_LOCK}" >&2; exit 3; }
    if "${FLOCK_BIN}" -n 9; then
      FLOCK_FD=9
      break
    fi
    exec 9>&- 2>/dev/null || true
    release_locks
  fi
  elapsed=$((elapsed+1))
  if [ "${elapsed}" -gt "${TIMEOUT}" ]; then
    echo "Error: gave up waiting for the test locks after ${TIMEOUT}s." >&2
    echo "       ${DIR_LOCK} is Downbeat's, ${FILE_LOCK} is Overture's." >&2
    echo "       An Overture test run is holding it, or a previous run died." >&2
    echo "       If nothing is running, remove ${DIR_LOCK} and try again." >&2
    exit 3
  fi
  sleep "${POLL}"
done

echo "==> Holding both locks. Running Ovation's tests."

# ---------------------------------------------------------------------------
# BRACKET THE RUN AGAINST LIVE DATA (ovation#58, plan 1.9).
#
# The resolvers refuse, and scripts/check-isolation-floor.sh refuses one that is
# not registered. Both of those read the CODE. This measures the DISK, because
# the thing being protected is that nothing lands in Dan's real store, not that a
# particular function returns nil (L63). A test that builds its own path reaches
# the folder without going through any resolver at all.
# ---------------------------------------------------------------------------
LIVE_DATA_GUARD="${REPO_ROOT}/scripts/check-live-data-untouched.sh"
LIVE_DATA_FINGERPRINT=""
if [ -x "${LIVE_DATA_GUARD}" ]; then
  LIVE_DATA_FINGERPRINT="$(mktemp)"
  "${LIVE_DATA_GUARD}" snapshot "${LIVE_DATA_FINGERPRINT}" >/dev/null || LIVE_DATA_FINGERPRINT=""
fi

# The command is injectable so the suite can measure the LOCKING without paying
# for a three minute xcodebuild (L2, L291). The default is the real thing.
#
# THE OUTPUT IS TEED, NOT CAPTURED. The count has to be read back (below), and a
# plain $(...) would hold three minutes of a real xcodebuild in a variable with
# the terminal silent, so a person watching could not tell a slow run from a hung
# one. PIPESTATUS[0] is the run's own status: the pipe's is tee's (L183, L184).
PURE_OUTPUT="$(mktemp)"
if [ -z "${TEST_COMMAND}" ]; then
  xcodebuild -project "${REPO_ROOT}/Ovation.xcodeproj" -scheme OvationCore \
    -destination 'platform=macOS' test 2>&1 | tee "${PURE_OUTPUT}"
else
  bash -c "${TEST_COMMAND}" 2>&1 | tee "${PURE_OUTPUT}"
fi
STATUS="${PIPESTATUS[0]}"

# ---------------------------------------------------------------------------
# THE PURE SUITE IS JUDGED BY WHAT IT EXECUTED, NOT ONLY BY ITS EXIT CODE.
#
# ovation#106. The hosted run's count has been read back since ovation#59; the
# pure suite, which is the overwhelming majority of the tests, was judged by exit
# code alone. A run is judged first by the count it EXECUTED against the count
# expected, and only then by its failures (L288). A renamed target, a changed
# scheme, a filter, or a move to parallel workers or sharding can lose most of
# the suite and still print a verdict, and the push gate stands on this suite
# being green, so a half run is a gate that passed without judging the change.
#
# THE FLOOR IS A COMMITTED NUMBER, not zero. Refusing only an empty run would
# catch the total loss and miss every partial one, which is the likelier and
# quieter failure. A change that adds tests bumps the file, which is what makes
# a DROP visible rather than a matter of somebody noticing.
if [ "${STATUS}" -eq 0 ] && [ -n "${TEST_COMMAND}" ] && [ -z "${OVATION_TEST_FLOOR:-}" ]; then
  # Said out loud rather than skipped silently, the same way the hosted skip is:
  # the runner is being measured with an injected command, which prints no count,
  # so a floor would refuse every test of the locking. A skip nobody is told
  # about is indistinguishable from a check that passed (L98, L320).
  echo "==> Pure count check skipped: the command was injected and no floor was given."
elif [ "${STATUS}" -eq 0 ]; then
  FLOOR_FILE="${REPO_ROOT}/scripts/pure-test-floor.txt"
  PURE_FLOOR="${OVATION_TEST_FLOOR:-$(cat "${FLOOR_FILE}" 2>/dev/null || echo 0)}"
  PURE_COUNT="$(grep -oE 'Test run with [0-9]+ test' "${PURE_OUTPUT}" \
    | grep -oE '[0-9]+' | sort -rn | head -1)"
  PURE_COUNT="${PURE_COUNT:-0}"
  if [ "${PURE_FLOOR}" -eq 0 ]; then
    echo "Error: no test floor to judge the run against (${FLOOR_FILE})." >&2
    echo "       A run nothing can be compared to is not a green run." >&2
    STATUS=7
  elif [ "${PURE_COUNT}" -lt "${PURE_FLOOR}" ]; then
    echo "Error: the suite executed ${PURE_COUNT} tests against a floor of ${PURE_FLOOR}." >&2
    echo "       It exited 0, so this is a run that lost most of itself and" >&2
    echo "       still reported success. Nothing about the missing tests was judged." >&2
    echo "       If tests were deliberately removed, lower ${FLOOR_FILE}." >&2
    STATUS=7
  fi
fi
rm -f "${PURE_OUTPUT}"

# ---------------------------------------------------------------------------
# THE HOSTED SUITE, still under both locks.
#
# ovation#59 added OvationHostedTests, which renders real SwiftUI views and
# therefore launches the app. It is a SECOND xcodebuild invocation rather than a
# wider scheme, because the pure suite must stay in a scheme the app is not part
# of: a broken app cannot then fail, slow, or even be needed by the run that
# reports on 100+ domain tests.
#
# A NARROWED RUN THAT MATCHES NOTHING PRINTS SUCCESS. `-only-testing:` with a
# path that resolves to no tests makes xcodebuild print ** TEST SUCCEEDED ** and
# exit 0, so a renamed target would silently stop running these while the gate
# stayed green (L98, L288). The count is read back and a run that executed no
# tests is refused.
if [ "${STATUS}" -eq 0 ]; then
  if [ -n "${TEST_COMMAND}" ] && [ -z "${HOSTED_TEST_COMMAND}" ]; then
    # Said out loud rather than skipped silently: the runner is being measured
    # with an injected command, so the real hosted run would be meaningless here.
    echo "==> Hosted suite skipped: the pure command was injected and no hosted one was."
  else
    echo "==> Running the hosted suite (it launches the app)"
    if [ -n "${HOSTED_TEST_COMMAND}" ]; then
      HOSTED_OUTPUT="$(bash -c "${HOSTED_TEST_COMMAND}" 2>&1)"
    else
      HOSTED_OUTPUT="$(xcodebuild -project "${REPO_ROOT}/Ovation.xcodeproj" -scheme Ovation \
        -destination 'platform=macOS' -only-testing:OvationHostedTests test 2>&1)"
    fi
    HOSTED_STATUS=$?
    printf '%s\n' "${HOSTED_OUTPUT}"

    if [ "${HOSTED_STATUS}" -ne 0 ]; then
      STATUS="${HOSTED_STATUS}"
    elif ! printf '%s' "${HOSTED_OUTPUT}" | grep -qE 'Test run with [1-9][0-9]* test'; then
      echo "Error: the hosted run reported success and executed NO tests." >&2
      echo "       A -only-testing: path that matches nothing does exactly this." >&2
      echo "       Nothing about the launch surface was verified." >&2
      STATUS=6
    fi
  fi
fi

# The other end of the bracket. A run that wrote to live data FAILS, whatever
# the tests said, because a green suite that reached Dan's store is the worst of
# both.
if [ -n "${LIVE_DATA_FINGERPRINT}" ]; then
  if ! "${LIVE_DATA_GUARD}" compare "${LIVE_DATA_FINGERPRINT}"; then
    [ "${STATUS}" -eq 0 ] && STATUS=7
  fi
  rm -f "${LIVE_DATA_FINGERPRINT}"
fi

# A SHELL SUITE THAT COULD NOT MEASURE ENDS THE RUN NON-ZERO, at the END rather
# than where it was found (ovation#139). It keeps its own code, 2, so a caller
# can tell "something is broken" from "something went unchecked", which is the
# distinction the suites themselves went to trouble to draw and which this
# runner used to collapse (L11, L260). It never overwrites a real failure.
if [ "${STATUS}" -eq 0 ] && [ -n "${SHELL_UNMEASURED}" ]; then
  echo "==> The run is CANNOT MEASURE: every suite that could run passed, and at" >&2
  echo "    least one could not measure. Nothing is known about what it covers." >&2
  STATUS=2
fi

# Judge by the EXIT CODE, never by a line of output: a tool's final line is
# routinely a different measurement than its verdict, and usually the more
# reassuring of the two (L184).
exit "${STATUS}"
