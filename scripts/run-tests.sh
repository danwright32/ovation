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
# around the work that needs them.
#
# AND THAT IS NOW THE HOSTED SUITE ALONE, MEASURED RATHER THAN INHERITED
# (ovation#271). ovation#12 decided HOW to share the siblings' locks, never
# whether every xcodebuild run needed them. On 2026-09-13, 516 Ovation runs were
# measured, 406 of them beside real Overture and Downbeat suites, and:
#
#   - Ovation's own suites never failed because a sibling was running. Two of its
#     tests failed under load from anything, which is those tests (ovation#272).
#   - An Overture test that counts rows while key focus can move failed 21 times,
#     every one while Ovation's HOSTED suite was testing and ordering its own
#     windows front, and never with nothing beside it (overture#3876).
#   - No sibling failure ever coincided with the PURE suite, which opens no
#     windows, and two Ovation pure suites run at once passed 40 of 40.
#
# So the pure suite runs without waiting for either sibling, and both locks are
# taken, in the same fixed order, around the hosted suite only. The lock does not
# make that Overture test safe from focus changes in general (anything taking
# focus trips it, which is overture#3876's to fix); it stops Ovation being one.
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
XCODE_PROJECT="${OVATION_XCODE_PROJECT:-${REPO_ROOT}/Ovation.xcodeproj}"
XCODEGEN="${OVATION_XCODEGEN:-$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)}"
TEST_COMMAND="${OVATION_TEST_COMMAND:-}"
HOSTED_TEST_COMMAND="${OVATION_HOSTED_TEST_COMMAND:-}"
UNLOCKED_COMMAND="${OVATION_UNLOCKED_COMMAND:-}"
SKIP_XCODE_PHASE="${OVATION_SKIP_XCODE_PHASE:-}"
# What lists this Mac's preference domains (ovation#263). A seam, because the
# real list is the whole Mac's and another checkout's run can add to it, so the
# runner's own suite must judge a list it controls (L375).
DOMAINS_COMMAND="${OVATION_DEFAULTS_DOMAINS_COMMAND:-defaults domains}"
DOMAINS_BRACKETED=""

# STATUS IS THE RUN'S VERDICT AND IT EXISTS FROM THE TOP. The locked phase used to
# be the only thing that set it, so the skip path above reached the exit with it
# unbound and, under `set -u`, the runner died with a shell error where a verdict
# should have been.
STATUS=0

# Same reason: the bracket is opened inside the locked phase, so the compare at
# the end has to be able to see that it never was.
LIVE_DATA_FINGERPRINT=""

DIR_LOCK_HELD=""
FLOCK_FD=""

# The `ovation.tests.` preference domains on this Mac, one per line, sorted
# (ovation#263). `defaults domains` prints one comma separated line, so it is
# split and trimmed here. It FAILS rather than answering with nothing when the
# list cannot be read: an empty list and an unreadable one are different facts,
# and only the first is clean (L98, L215).
test_domains() {
  local listed
  listed="$(bash -c "${DOMAINS_COMMAND}" 2>/dev/null)" || return 1
  [ -n "${listed}" ] || return 1
  printf '%s\n' "${listed}" | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep '^ovation\.tests\.' | sort -u
  return 0
}

count_lines() { printf '%s' "$1" | grep -c . || true; }

# Released on EVERY exit path, not only the tidy one. A directory lock left
# planted blocks the next run of a DIFFERENT app, which is the failure this
# whole thing exists to prevent.
release_locks() {
  [ -n "${FLOCK_FD}" ] && eval "exec ${FLOCK_FD}>&-" 2>/dev/null || true
  [ -n "${DIR_LOCK_HELD}" ] && rm -rf "${DIR_LOCK}" 2>/dev/null || true
  DIR_LOCK_HELD=""
  FLOCK_FD=""
}
# AND A RUN TOLD TO STOP, STOPS (ovation#274). This was one trap for EXIT, INT
# and TERM, and a trap on INT or TERM that only cleans up RETURNS to the script:
# a runner told to stop let go of its locks and carried on, back to waiting for
# them or on into xcodebuild, and reported whatever that reached as its verdict.
# Seen 2026-09-13: two push gate runs stopped with an ordinary signal were still
# alive and still waiting seconds later. Stopping one for real then needed
# `kill -9`, which skips every trap, and the directory lock is the half that does
# not clear when its holder dies (L473).
#
# So EXIT keeps the cleanup, and INT and TERM release and then EXIT with the
# conventional status, 128 plus the signal, so a caller can tell a stopped run
# from a red one. The EXIT trap runs again on the way out and finds nothing held.
#
# WHAT A SIGNAL CANNOT DO, said so it is not expected: bash runs the trap when
# the command in front of it returns, so a signal sent to this pid alone while
# xcodebuild is running takes effect when that build finishes. Ctrl+C reaches
# the whole foreground group, the build included, and is the prompt way to stop.
trap release_locks EXIT
trap 'release_locks; exit 130' INT
trap 'release_locks; exit 143' TERM

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

# THE LOCKED PHASE CAN BE SKIPPED WHEN THE PUSH CANNOT HAVE CHANGED IT
# (ovation#22).
#
# Measured twice on 2026-09-05, four minutes each time: a push ran the hook, ran
# this runner, and waited on Overture's lock while a real Overture suite ran.
# Overture runs its suite constantly, so that is the normal case rather than bad
# luck, and most pushes in this phase change only documentation or shell scripts,
# which no xcodebuild run can be affected by.
#
# THE DECISION IS NOT MADE HERE. Only the caller knows what is being pushed, so
# this is the seam it acts through, and the run SAYS which of the two happened,
# because a run that skipped the Xcode suite must never look like one that passed
# it (L98, L11). The shell suites above are unaffected: a skip that also swallowed
# the cheap checks would switch the gate off on the pushes it is cheapest to run.
if [ -n "${SKIP_XCODE_PHASE}" ]; then
  echo "==> Xcode phase SKIPPED: the caller says this change cannot affect it."
  echo "    The shell suites above are the whole of this run. Nothing was built,"
  echo "    no sibling lock was taken, and the Swift suites did not run."
else
  # ---------------------------------------------------------------------------
  # PHASE TWO. The pure suite runs without waiting for the siblings, and only the
  # hosted suite takes their locks (ovation#271, measured; see the header).
  # ---------------------------------------------------------------------------
  # THE PROJECT IS GENERATED WHEN IT IS ABSENT, AND ONLY THEN (ovation#151).
  # The rule and the reasoning live in the shared helper, because build-install.sh
  # reaches xcodebuild by its own route and needs the same thing (L613).
  #
  # It happens BEFORE the locks, and that is now a scoped claim rather than the
  # blanket one it used to be. This CREATES a project where there is none, so a
  # fresh checkout does not queue behind a sibling's build for a file nothing can
  # be reading. REGENERATING an existing one is a different act and does take the
  # lock, in regenerate-xcode-project.sh: it rewrites a file a running build is
  # reading, which happened on 2026-09-10 and survived on luck (ovation#202).
  # A create does take a lock of its own, scoped to the project path, so a second
  # run creating the same project waits for the first's result instead of
  # generating over it, and nothing about a sibling's build can hold it
  # (ovation#207). The create itself is the ensure_xcode_project call below the
  # Xcode version note.
  #
  # WHICH XCODE THIS RUN BUILDS WITH, AGAINST THE ONE CI BUILDS WITH (ovation#270).
  #
  # The push gate is meant to predict CI, and it can only do that while both
  # compile with the same Xcode. CI selects the version .xcode-version names; this
  # Mac builds with whatever is selected here. A green run on a different compiler
  # is not evidence the merge will build (L376), so every run that builds says
  # which of the three it found, the matching case included, so its silence can
  # never be read as a comparison that passed (L98).
  #
  # IT NEVER CHANGES THE VERDICT. Somebody partway through an Xcode upgrade must
  # still be able to run the suite, and a refusal here would be a gate people
  # learn to skip (L378). It sits here, inside the phase that builds, because a
  # shell only run compiles nothing and a note about a compiler there would be
  # one every Linux log carried and nobody read (L36).
  # shellcheck source=lib/xcode-pin.sh
  . "${REPO_ROOT}/scripts/lib/xcode-pin.sh"
  XCODE_PIN_FILE="${OVATION_XCODE_VERSION_FILE:-${REPO_ROOT}/.xcode-version}"
  XCODEBUILD_FOR_VERSION="${OVATION_XCODEBUILD:-xcodebuild}"
  if ! CI_XCODE="$(xcode_pin_read "${XCODE_PIN_FILE}")"; then
    echo "==> NOTE: could not read the Xcode CI builds with from ${XCODE_PIN_FILE}"
    echo "    (it should hold one version number, like 26.6), so this Mac's Xcode was"
    echo "    not compared with CI's. The run continues."
  elif ! LOCAL_XCODE="$(xcode_active_version "${XCODEBUILD_FOR_VERSION}")"; then
    echo "==> NOTE: could not tell which Xcode this Mac builds with, so it was not"
    echo "    compared with Xcode ${CI_XCODE}, the version CI builds with. The run continues."
  elif [ "${LOCAL_XCODE}" = "${CI_XCODE}" ]; then
    echo "==> Building with Xcode ${LOCAL_XCODE}, the version CI builds with (.xcode-version)."
  else
    echo "==> NOTE: this Mac builds with Xcode ${LOCAL_XCODE} and CI builds with Xcode ${CI_XCODE} (.xcode-version)."
    echo "    A green run here does not show CI's compiler will agree, so a push can"
    echo "    pass this gate and still fail to build in CI (ovation#270). The run continues."
  fi

  # shellcheck source=lib/ensure-xcode-project.sh
  . "${REPO_ROOT}/scripts/lib/ensure-xcode-project.sh"
  ensure_xcode_project "${REPO_ROOT}" "${XCODE_PROJECT}" "${XCODEGEN}" || exit 2

  # AND THE PROJECT THAT IS THERE LISTS THE SWIFT FILES THAT ARE THERE
  # (ovation#206). The helper above deliberately never regenerates, so a Swift
  # file added after the project was made is invisible to both suites, and the
  # build then fails with `cannot find ... in scope`, naming the code rather than
  # the project. Asked here, before anything is built from it, through the same
  # script the push gate runs, so the two cannot disagree about "current" (L70).
  #
  # 0 is current and 2 is nothing to compare (no project file to read), and both
  # go on: xcodebuild says plainly when a project is absent. Anything else stops
  # the run with the check's own words and status, which is a real fault in the
  # tree rather than something that went unmeasured.
  OVATION_REPO_ROOT="${REPO_ROOT}" OVATION_XCODE_PROJECT="${XCODE_PROJECT}" \
    "${REPO_ROOT}/scripts/check-xcode-project-current.sh"
  PROJECT_CURRENT_STATUS=$?
  case "${PROJECT_CURRENT_STATUS}" in
    0|2) ;;
    *) exit "${PROJECT_CURRENT_STATUS}" ;;
  esac

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
  # WHO HOLDS IT, AND HOW LONG THIS WILL WAIT (ovation#22). It printed the two
  # paths and nothing else, so a person watching a push sit here could not tell a
  # busy sibling from a stuck lock, and a wait that cannot be told apart from a
  # hang is the worse of the two (L110). Both holders are knowable: Downbeat's
  # lock directory carries an owner file, which Ovation writes for its own runs,
  # and the file lock can be attributed by asking which process holds it.
  # ovation#202. Taking it and describing its holder live in lib/dir-lock.sh,
  # because the regenerator now takes the same lock and a second copy of the
  # owner line's format would drift into a refusal naming nobody (L370).
  # shellcheck source=lib/dir-lock.sh
  . "${REPO_ROOT}/scripts/lib/dir-lock.sh"
  describe_dir_holder() { dir_lock_describe "${DIR_LOCK}"; }
  describe_file_holder() {
    local pid pids="" desc=""
    if [ -x /usr/sbin/lsof ]; then
      pids="$(/usr/sbin/lsof -t "${FILE_LOCK}" 2>/dev/null)"
    fi
    if [ -z "${pids}" ]; then
      printf 'free, or held by a process this run cannot see'
      return
    fi
    for pid in ${pids}; do
      desc="${desc}${pid} ($(ps -o comm= -p "${pid}" 2>/dev/null | sed 's|.*/||')) "
    done
    printf 'held by pid %s' "${desc% }"
  }

  # ---------------------------------------------------------------------------
  # BRACKET THE RUN AGAINST LIVE DATA (ovation#58, plan 1.9).
  #
  # Taken BEFORE the pure suite, which now runs outside the locks, so the bracket
  # still spans everything that builds and tests (ovation#271).
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

  # ---------------------------------------------------------------------------
  # AND AGAINST PREFERENCE DOMAINS LEFT BEHIND (ovation#263).
  #
  # Two fixtures made a UserDefaults suite by name and never removed it, so every
  # run left one more `ovation.tests.<uuid>` domain on the Mac: 426 when the
  # issue was filed on 2026-09-13 and 4692 by that night, each a plist in
  # ~/Library/Preferences. OvationTests/ThrowawayDefaultsTests.swift is the fix;
  # this is what notices the next test that goes around it, by measuring the
  # list itself rather than reading the test sources (L63).
  #
  # BY NAME, NOT BY COUNT, so a run that clears one old leftover while making a
  # new one cannot read as clean (L367). A leftover already there before the run
  # is not this run's.
  # ---------------------------------------------------------------------------
  DOMAINS_BRACKETED=1
  DOMAINS_UNMEASURED=""
  DOMAINS_BEFORE="$(test_domains)" || DOMAINS_UNMEASURED=1

  # The command is injectable so the suite can measure the LOCKING without paying
  # for a three minute xcodebuild (L2, L291). The default is the real thing.
  #
  # THE OUTPUT IS TEED, NOT CAPTURED. The count has to be read back (below), and a
  # plain $(...) would hold three minutes of a real xcodebuild in a variable with
  # the terminal silent, so a person watching could not tell a slow run from a hung
  # one. PIPESTATUS[0] is the run's own status: the pipe's is tee's (L183, L184).
  PURE_OUTPUT="$(mktemp)"
  if [ -z "${TEST_COMMAND}" ]; then
    xcodebuild -project "${XCODE_PROJECT}" -scheme OvationCore \
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
    elif [ "${PURE_COUNT}" -gt "${PURE_FLOOR}" ]; then
      # AND A FLOOR THAT DOES NOT MOVE STOPS BEING A FLOOR (ovation#157).
      #
      # It was committed at 294 and was still 294 with the suite executing 422:
      # a floor 128 below the real count cannot see a run that loses a quarter of
      # itself, which is precisely the partial run it exists to refuse, and it
      # passes the whole time (L63, L354). Nothing made it move, so it was a rule
      # living in whoever remembered it (L27).
      #
      # REFUSED RATHER THAN PRINTED. A notice on a green run is one nobody reads,
      # and this is the only moment both numbers are in front of anybody. The cost
      # is one command per change that adds tests, and the message is that command
      # rather than a description of it (L399).
      echo "Error: the suite executed ${PURE_COUNT} tests and the floor says ${PURE_FLOOR}." >&2
      echo "       That is tests being ADDED, which is good, and the floor has to" >&2
      echo "       move with them or it stops being able to see a run that loses" >&2
      echo "       some. Run this, then push:" >&2
      echo "" >&2
      echo "       printf '%s\\n' ${PURE_COUNT} > ${FLOOR_FILE}" >&2
      echo "" >&2
      STATUS=7
    fi
  fi
  rm -f "${PURE_OUTPUT}"

  # ---------------------------------------------------------------------------
  # THE HOSTED SUITE, AND ONLY THE HOSTED SUITE, UNDER BOTH LOCKS (ovation#271).
  #
  # ovation#59 added OvationHostedTests, which renders real SwiftUI views and
  # therefore launches the app. It is a SECOND xcodebuild invocation rather than a
  # wider scheme, because the pure suite must stay in a scheme the app is not part
  # of: a broken app cannot then fail, slow, or even be needed by the run that
  # reports on 100+ domain tests. That split is also what lets the locks wrap this
  # half alone: it is the half that orders windows front and moves key focus.
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
      # No lock is taken for a suite that does not run.
      echo "==> Hosted suite skipped: the pure command was injected and no hosted one was."
    else
      # WHO WENT AHEAD, AND A RECORD OF EVERY WAIT (ovation#236).
      #
      # Measured 2026-09-11: a run waited over eleven minutes behind seven back to
      # back Overture runs, then gave up naming two paths, which reads as Ovation's
      # fault and cannot tell a queue of busy siblings from one lock a dead run left
      # behind (L11, L148). And the wait was printed and lost, so how often and how
      # long this happens was unknown.
      #
      # So the holders are noted on every poll and a CHANGE of holder counts as one
      # more run that went ahead; giving up names them and the count; a wait that
      # succeeds says what it cost; and every attempt, a wait of nothing included,
      # is one line in a record the next wait quotes back (L46).
      #
      # THE RECORD IS WRITTEN BY REAL RUNS AND BY A RUN THAT NAMES ONE. A run with
      # injected commands that names none writes nothing, so no test run can reach
      # Dan's real record by forgetting a seam (L2).
      WAIT_LOG="${OVATION_LOCK_WAIT_LOG:-}"
      if [ -z "${WAIT_LOG}" ] && [ -z "${TEST_COMMAND}${HOSTED_TEST_COMMAND}" ]; then
        WAIT_LOG="${HOME}/Library/Logs/Ovation/lock-waits.tsv"
      fi
      holders_seen=0
      last_dir_holder=""
      last_file_holder=""
      last_file_id=""
      WAIT_OUTCOME=""
      note_holders() {
        local d f f_id
        d="$(describe_dir_holder)"
        f="$(describe_file_holder)"
        # A FILE LOCK HOLDER IS ITS LOWEST PID, NOT THE WHOLE LIST. Every process
        # holding the descriptor is listed, and a real Overture run starts and
        # ends children the whole time it holds the lock, so the list changed on
        # almost every poll and one run counted as six. The process that TOOK the
        # lock started first and lives as long as the hold, so it is the lowest
        # pid in the list. Measured 2026-09-13: flock and its bash stayed put while
        # a third pid changed on every sample. The one way this misleads is the
        # system's pids wrapping round mid wait, which can only overcount.
        f_id="$(printf '%s' "${f}" | grep -oE '[0-9]+ \(' | grep -oE '[0-9]+' | sort -n | head -1)"
        # "free" is nobody, and so is a file lock whose holder cannot be seen: a
        # count must only ever be of holders this run actually observed.
        case "${d}" in
          free) ;;
          *) [ "${d}" != "${last_dir_holder}" ] && holders_seen=$((holders_seen + 1)) ;;
        esac
        if [ -n "${f_id}" ] && [ "${f_id}" != "${last_file_id}" ]; then
          holders_seen=$((holders_seen + 1))
        fi
        last_dir_holder="${d}"
        last_file_holder="${f}"
        last_file_id="${f_id}"
      }
      holders_sentence() {
        case "${holders_seen}" in
          0) printf 'no holder this run could see' ;;
          1) printf '1 different holder' ;;
          *) printf '%s different holders' "${holders_seen}" ;;
        esac
      }
      record_wait() {
        [ -n "${WAIT_LOG}" ] || return 0
        mkdir -p "$(dirname "${WAIT_LOG}")" 2>/dev/null || true
        # Said, not swallowed, but never a reason to fail a run somebody is waiting
        # on: the record is a measurement of the queue, not part of the verdict.
        printf '%s\t%s\t%s\t%s\n' "${wait_started}" "${waited_for}" "${WAIT_OUTCOME}" \
          "${holders_seen}" >> "${WAIT_LOG}" 2>/dev/null \
          || echo "    (the lock wait record at ${WAIT_LOG} could not be written)" >&2
      }

      echo "==> Waiting for both test locks, up to ${TIMEOUT}s"
      if [ -n "${WAIT_LOG}" ] && [ -s "${WAIT_LOG}" ]; then
        wait_history="$(tail -n 20 "${WAIT_LOG}" | awk -F'\t' 'NF >= 3 { n++; s = $2 + 0; if (s > 0) waited++; if (s > longest) longest = s } END { if (n) printf "%d recorded, %d waited at all, longest %ds", n, waited, longest }')"
        [ -n "${wait_history}" ] && echo "    recent waits on this Mac: ${wait_history}"
      fi
      note_holders
      echo "    ${DIR_LOCK}: ${last_dir_holder}"
      echo "    ${FILE_LOCK}: ${last_file_holder}"
      : > "${FILE_LOCK}" 2>/dev/null || true
      # ELAPSED IS REAL TIME, NOT A COUNT OF ITERATIONS. It was `elapsed=$((elapsed+1))`
      # against a timeout in seconds, which measures iterations and is only the same
      # number while the poll interval happens to be one second, so any change to the
      # interval silently rescaled the deadline (L226).
      wait_started="$(date +%s)"
      announced=0
      while :; do
        if dir_lock_take "${DIR_LOCK}" "$(basename "${REPO_ROOT}")" "$$"; then
          DIR_LOCK_HELD=1
          # Non blocking. If Overture has it, we do not queue holding Downbeat's.
          exec 9>"${FILE_LOCK}" || { echo "Error: cannot open ${FILE_LOCK}" >&2; exit 3; }
          if "${FLOCK_BIN}" -n 9; then
            FLOCK_FD=9
            break
          fi
          # A BARE CLOSE, NEVER `exec 9>&- 2>/dev/null` (ovation#281). An exec with
          # no command makes EVERY redirection on it permanent, so that line sent
          # this run's stderr to /dev/null from the first busy attempt on: the
          # give-up message, and the reason a push was refused, simply vanished.
          # Closing a descriptor needs no silencing; it never errors here.
          exec 9>&-
          release_locks
        fi
        note_holders
        elapsed=$(( $(date +%s) - wait_started ))
        # STILL ALIVE, said out loud every thirty seconds with who is holding it, so
        # a long wait reads as a queue rather than as a hang.
        if [ "$((elapsed / 30))" -gt "${announced}" ]; then
          announced=$((elapsed / 30))
          echo "    still waiting after ${elapsed}s of ${TIMEOUT}s: ${DIR_LOCK} ${last_dir_holder}, ${FILE_LOCK} ${last_file_holder}; $(holders_sentence) so far"
        fi
        # GIVING UP ENDS THE WAIT, NOT THE RUN. It used to `exit 3` here, which was
        # harmless while the live data bracket had not been opened yet. It now has:
        # the pure suite ran before this wait, so the run has to reach the compare
        # at the end, which a verdict of 3 still does.
        if [ "${elapsed}" -gt "${TIMEOUT}" ]; then
          echo "Error: gave up waiting for the test locks after ${TIMEOUT}s." >&2
          echo "       Downbeat's lock ${DIR_LOCK}: ${last_dir_holder}" >&2
          echo "       Overture's lock ${FILE_LOCK}: ${last_file_holder}" >&2
          echo "       $(holders_sentence) went ahead of this run while it waited." >&2
          echo "       Several holders is a busy sibling. ONE holder the whole time with" >&2
          echo "       nothing running is a run that died holding it: remove ${DIR_LOCK}" >&2
          echo "       and try again." >&2
          STATUS=3
          WAIT_OUTCOME=gave-up
          break
        fi
        sleep "${POLL}"
      done
      waited_for=$(( $(date +%s) - wait_started ))
      WAIT_OUTCOME="${WAIT_OUTCOME:-acquired}"
      if [ "${WAIT_OUTCOME}" = acquired ] && { [ "${waited_for}" -gt 0 ] || [ "${holders_seen}" -gt 0 ]; }; then
        echo "==> Waited ${waited_for}s for the test locks; $(holders_sentence) went ahead of this run."
      fi
      record_wait
    fi
  fi

  if [ -n "${FLOCK_FD}" ]; then
    echo "==> Holding both locks. Running the hosted suite (it launches the app)."

    # AND IF SOMETHING IS ALREADY BUILDING, IT IS BUILDING OUTSIDE THE LOCK
    # (ovation#156). The lock is voluntary: it lives in this script and in
    # build-products.sh, so any invocation that reaches xcodebuild another way goes
    # around it and neither run can tell. A rule that lives only in a comment plus
    # whoever remembers is a hope (L27).
    #
    # THIS IS THE ONE MOMENT THE QUESTION IS CHEAP AND UNAMBIGUOUS. Both locks are
    # held right now and the hosted suite has not started building yet, so any
    # xcodebuild already running belongs to nobody's lock. No polling, no
    # background watcher, and no window in which a legitimate run looks guilty.
    #
    # EXCEPT AN OVATION PURE SUITE, which takes no lock by design (ovation#271).
    # Another worktree's pure run is outside the locks legitimately, and a warning
    # that fires on the designed case is one people learn to read past (L36). It
    # is recognised by what `ps` says it is running, so a pid that cannot be read
    # is still reported rather than excused.
    #
    # IT REPORTS AND DOES NOT REFUSE. A false positive that blocked a push would be
    # a gate people learn to skip, and the honest remedy is Dan's: stop the other
    # build, or let both run and distrust the result. What it removes is the part
    # that made this invisible.
    #
    # Xcode.app itself does NOT show up here: it builds through XCBBuildService
    # rather than the xcodebuild binary, so a person working in the IDE is not
    # accused. The lister is injectable so the suite can stage the finding without
    # starting a real build (L196).
    BUILDER_LISTER="${OVATION_XCODEBUILD_LISTER:-pgrep -x xcodebuild}"
    OTHER_BUILDERS=""
    for builder in $(bash -c "${BUILDER_LISTER}" 2>/dev/null | grep -v "^$$\$"); do
      case "$(ps -o command= -p "${builder}" 2>/dev/null)" in
        *"-scheme OvationCore"*) continue ;;
      esac
      OTHER_BUILDERS="${OTHER_BUILDERS}${builder}"$'\n'
    done
    OTHER_BUILDER_COUNT="$(printf '%s' "${OTHER_BUILDERS}" | grep -c . || true)"
    if [ "${OTHER_BUILDER_COUNT}" -gt 0 ]; then
      echo "==> WARNING: ${OTHER_BUILDER_COUNT} xcodebuild process(es) are running while"
      echo "    this run holds BOTH test locks, so they were started outside them:"
      printf '%s' "${OTHER_BUILDERS}" | sed 's/^/        pid /'
      echo "    One of them landing beside the hosted suite is what the locks exist to"
      echo "    prevent (ovation#12, ovation#271). This run continues; the result it"
      echo "    reports is worth less than usual."
    fi

    if [ -n "${HOSTED_TEST_COMMAND}" ]; then
      HOSTED_OUTPUT="$(bash -c "${HOSTED_TEST_COMMAND}" 2>&1)"
    else
      HOSTED_OUTPUT="$(xcodebuild -project "${XCODE_PROJECT}" -scheme Ovation \
        -destination 'platform=macOS' -only-testing:OvationHostedTests test 2>&1)"
    fi
    HOSTED_STATUS=$?
    printf '%s\n' "${HOSTED_OUTPUT}"

    if [ "${HOSTED_STATUS}" -ne 0 ]; then
      STATUS="${HOSTED_STATUS}"
    # A HERE STRING, NOT A PIPE (ovation#241). This asked
    # `printf ... | grep -qE ...`, and under the `set -o pipefail` at the top of
    # this file that is a false failure waiting for a big enough output:
    # `grep -q` exits at the first match and closes the pipe, `printf` is killed
    # writing the rest, and the pipeline takes printf's status, so the negation
    # reports "executed NO tests" about a run that executed plenty (L183).
    #
    # Measured 2026-09-12 on CI: one of two identical jobs failed with
    # `printf: write error: Broken pipe` straight after `** TEST SUCCEEDED **`
    # and a hosted run of 26 tests. A here string is a file rather than a pipe,
    # so there is no producer left to kill.
    elif ! grep -qE 'Test run with [1-9][0-9]* test' <<<"${HOSTED_OUTPUT}"; then
      echo "Error: the hosted run reported success and executed NO tests." >&2
      echo "       A -only-testing: path that matches nothing does exactly this." >&2
      echo "       Nothing about the launch surface was verified." >&2
      STATUS=6
    fi

    # LET GO THE MOMENT THE HOSTED SUITE IS DONE, rather than at exit: the live
    # data compare below needs neither lock, and a sibling should not wait on it
    # (L366). The trap still covers every path that never reaches this line.
    release_locks
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

# The other end of the preference domain bracket (ovation#263).
if [ -n "${DOMAINS_BRACKETED}" ]; then
  if [ -n "${DOMAINS_UNMEASURED}" ] || ! DOMAINS_AFTER="$(test_domains)"; then
    # A run whose list could not be read is not a run that left nothing behind,
    # and it keeps CANNOT MEASURE's own code rather than reading as a failure or
    # a pass (L11, L98). It never overwrites a real failure.
    echo "Error: could not list this Mac's preference domains (${DOMAINS_COMMAND})," >&2
    echo "       so whether this run left an ovation.tests. domain behind was not measured." >&2
    [ "${STATUS}" -eq 0 ] && STATUS=2
  else
    DOMAINS_LEFT="$(comm -13 <(printf '%s\n' "${DOMAINS_BEFORE}" | sed '/^$/d') \
                             <(printf '%s\n' "${DOMAINS_AFTER}" | sed '/^$/d'))"
    if [ -n "${DOMAINS_LEFT}" ]; then
      left_count="$(count_lines "${DOMAINS_LEFT}")"
      echo "Error: this run left ${left_count} ovation.tests. preference domain(s) on this Mac:" >&2
      printf '%s\n' "${DOMAINS_LEFT}" | sed -n '1,10p' | sed 's/^/    /' >&2
      [ "${left_count}" -gt 10 ] && echo "    and $((left_count - 10)) more" >&2
      echo "       A test made a UserDefaults suite by name and did not remove it. Use" >&2
      echo "       ThrowawayDefaults, which keeps its settings out of ~/Library/Preferences." >&2
      echo "       If another checkout was running tests from before ovation#263 at the" >&2
      echo "       same time, it made them instead, and this run is not at fault." >&2
      [ "${STATUS}" -eq 0 ] && STATUS=7
    else
      echo "==> No ovation.tests. preference domain was left behind ($(count_lines "${DOMAINS_BEFORE}") before, $(count_lines "${DOMAINS_AFTER}") after)."
    fi
  fi
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
