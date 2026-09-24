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
# THE ORDER IS FIXED AND THAT IS WHAT MAKES DEADLOCK IMPOSSIBLE. Every runner
# that takes both takes them in THIS order, so nothing can hold Overture's while
# waiting for Downbeat's. A future version taking them in the opposite order
# reintroduces the classic deadlock, which is why the order is asserted by the
# suite.
#
# WHY THAT SENTENCE CHANGED, 2026-09-14. It used to say deadlock was impossible
# because "neither sibling takes two locks", and that stopped being true the day
# it was written about: overture#3571 made Overture's runner take Downbeat's
# directory lock as well as its own, because the two had never actually excluded
# each other despite Downbeat's own comment saying they did. So the safety no
# longer rests on Ovation being the only runner holding two. It rests on the
# ORDER, and on every runner that takes both agreeing about it, which is now
# Ovation and Overture. Downbeat takes only the directory lock and so cannot
# deadlock either way.
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
#
# HOW TO RUN IT, AND HOW TO RUN ONE SUITE (ovation#321):
#
#     scripts/run-tests.sh
#         Everything: the shell suites, then the pure Swift suite, then the hosted
#         suite under both sibling locks.
#
#     scripts/run-tests.sh --only OvationTests/<Suite>[/<testFunction>]
#     scripts/run-tests.sh --only OvationHostedTests/<Suite>[/<testFunction>]
#         One Swift suite, or one test in it, through everything below that
#         protects a run: the project is made current, the live data and
#         preference domain brackets are held, the hosted half takes both sibling
#         locks, and a filter that matched NOTHING is refused rather than reported
#         as a pass. The shell suites are skipped, and so is the half of the Swift
#         suite the filter is not in, and each skip is said out loud.
#
# WHY THE NARROWED RUN EXISTS AT ALL. Without it a test first cycle called
# xcodebuild by hand, which is outside the lock protocol the three apps on this
# Mac share and outside the project checks: on 2026-09-14 a hand written wait loop
# nearly reported a false failure, because the regeneration a new test file needs
# refuses WITHOUT waiting while a build holds the lock, and the loop kept only the
# last line of that refusal (ovation#321). A red and a green run happen many times
# in a feature, so the cheap path is the one that has to be the safe one (L378).
set -uo pipefail
# ovation#399: every library is loaded through require_lib, which refuses by name
# rather than carrying on without it. See scripts/lib/require.sh.
. "$(dirname "${BASH_SOURCE[0]}")/lib/require.sh" 2>/dev/null || { echo "REFUSED: scripts/lib/require.sh is missing, so nothing was checked." >&2; exit 2; }

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
# What answers whether the project lists every Swift file on disk, and what makes
# it list them again. Seams for the same reason every other command here is one:
# a narrowed run over a stale project has to be measured without a real xcodegen
# and without a real project to rewrite (L2, L291). The defaults are the scripts
# the push gate runs, so nothing here has a second opinion about "current" (L70).
PROJECT_CURRENT_COMMAND="${OVATION_PROJECT_CURRENT_COMMAND:-}"
REGENERATE_COMMAND="${OVATION_REGENERATE_COMMAND:-}"

# ---------------------------------------------------------------------------
# THE ARGUMENTS, READ BEFORE ANYTHING RUNS (ovation#321).
#
# No argument is exactly what it always was. `--only <Target>/<Suite>` narrows the
# run to one Swift suite, or to one test in it.
#
# EVERYTHING ELSE IS REFUSED, BY NAME, WITH THE FORMS THAT ARE ACCEPTED. A runner
# that ignored an argument it did not understand would run the whole suite while
# the person watching believed it was running one file, and the only symptom would
# be how long it took (L98, L320). The refusal happens before the shell suites,
# before any lock and before anything is built, so a mistyped invocation costs
# nothing.
# ---------------------------------------------------------------------------
ONLY_TESTING=""
ONLY_TARGET=""
# A suite name, and optionally one test in it. Swift Testing writes a function
# with parentheses and XCTest without, so both are accepted; a target other than
# the two this repository has is not, because -only-testing with an unknown target
# is precisely the filter that matches nothing (L98).
ONLY_PATTERN='^(OvationTests|OvationHostedTests)/[A-Za-z_][A-Za-z0-9_]*(/[A-Za-z_][A-Za-z0-9_]*(\(\))?)?$'

only_usage() {
  echo "Usage: scripts/run-tests.sh" >&2
  echo "       scripts/run-tests.sh --only OvationTests/<Suite>[/<testFunction>]" >&2
  echo "       scripts/run-tests.sh --only OvationHostedTests/<Suite>[/<testFunction>]" >&2
  echo "       With no argument every suite runs. With --only, one Swift suite runs," >&2
  echo "       under the same project checks and sibling locks as the whole run, and" >&2
  echo "       the rest is skipped and said out loud." >&2
}
refuse_usage() {
  echo "Error: $1" >&2
  only_usage
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --only)
      [ -z "${ONLY_TESTING}" ] || refuse_usage "--only was given twice, and a narrowed run runs one thing."
      [ "$#" -ge 2 ] || refuse_usage "--only needs a suite to run."
      [[ "${2:-}" =~ ${ONLY_PATTERN} ]] \
        || refuse_usage "'${2:-}' is not a suite in OvationTests or OvationHostedTests."
      ONLY_TESTING="$2"
      shift 2
      ;;
    *)
      refuse_usage "unknown argument '$1'."
      ;;
  esac
done

if [ -n "${ONLY_TESTING}" ]; then
  ONLY_TARGET="${ONLY_TESTING%%/*}"
  # THE COMMANDS CAN SEE THE FILTER. The injected seams are what the runner's own
  # suite measures, and a filter that reached xcodebuild but not the seam could
  # not be asserted on at all (L52). It is EXPORTED, so it also reaches a real
  # xcodebuild's environment, and it is the one place the value lives.
  export OVATION_ONLY_TESTING="${ONLY_TESTING}"
  if [ -n "${SKIP_XCODE_PHASE}" ]; then
    echo "Error: --only runs a Swift suite and OVATION_SKIP_XCODE_PHASE skips the Swift" >&2
    echo "       suites, so this run would test nothing at all. Refusing rather than" >&2
    echo "       printing a pass over a run that did nothing." >&2
    exit 2
  fi
else
  # A FULL RUN NARROWS NOTHING, whatever the shell that started it holds. The
  # variable is exported to every child, so a value left over from a narrowed run
  # in the same shell would otherwise reach the commands below and quietly run a
  # fraction of the suite (L169, L439).
  unset OVATION_ONLY_TESTING
fi

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
# The pid this run registered as reading the project under, while it is
# registered (ovation#299). Empty otherwise, so the trap removes nothing it did
# not write.
PROJECT_READER_PID=""

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
  # A registration left standing would refuse every regeneration of this tree
  # until a later one noticed this pid was gone (ovation#299).
  if [ -n "${PROJECT_READER_PID}" ]; then
    xcode_project_read_end "${XCODE_PROJECT}" "${PROJECT_READER_PID}"
    PROJECT_READER_PID=""
  fi
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
# And an INT sent to this pid ALONE can be absorbed outright by bash 5: when a
# foreground command exits normally after the shell got INT, bash takes that
# command as having handled it and does not run this trap. Ctrl+C, and `kill`
# (TERM) to this pid, both stop the run.
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

# WHICH SHELL SUITES, and it is CI's question, never Dan's (ovation#161, Dan's
# decision 2026-09-23). The shell suites ran three times per push: the macOS
# shell job, the Linux one, and again inside the macOS build job. They now run
# ONCE on Linux, and the macOS build job runs only the suites that cannot measure
# anywhere else, which today are the four that read a built product or
# xcodebuild's settings.
#
# A SUITE DECLARES THAT ITSELF, with the line `# ovation-runs-on: macos`, so the
# set is derived from the suites rather than listed in the workflow or here, where
# a new one would be missing until somebody remembered (L41, L96). And the Linux
# run REFUSES a suite that could not measure and carries no marker: without that,
# a new suite that needs a Mac would answer CANNOT MEASURE on Linux, be skipped by
# the macOS job, and be measured by CI nowhere, with every run still green (L98).
#
#     (unset)       every suite: the push gate on Dan's Mac, unchanged
#     macos-only    only suites carrying the marker, for the macOS build job
#     must-measure  every suite, and an unmarked CANNOT MEASURE fails the run
SHELL_SUITES_MODE="${OVATION_SHELL_SUITES:-}"
SHELL_SUITE_MARKER='# ovation-runs-on: macos'
case "${SHELL_SUITES_MODE}" in
  ""|macos-only|must-measure) ;;
  *)
    echo "Error: OVATION_SHELL_SUITES is '${SHELL_SUITES_MODE}', which is not a mode this runner has." >&2
    echo "       It takes macos-only or must-measure, or nothing for every suite." >&2
    exit 64
    ;;
esac
suite_needs_a_mac() { grep -qxF -- "${SHELL_SUITE_MARKER}" "$1" 2>/dev/null; }

if [ -n "${ONLY_TESTING}" ]; then
  # A NARROWED RUN IS ABOUT ONE SWIFT SUITE, and the shell suites take minutes and
  # answer a different question. Said in one line rather than simply not happening,
  # because a skip nobody is told about reads as a check that passed (L98, L320).
  echo "==> Shell suites SKIPPED: this run is narrowed to ${ONLY_TESTING}, so only that Swift suite runs. Run scripts/run-tests.sh with no argument for the whole gate."
elif [ -n "${UNLOCKED_COMMAND}" ]; then
  bash -c "${UNLOCKED_COMMAND}" || exit $?
else
  echo "==> Running the shell suites (no lock needed)"
  suites_ran=0
  suites_passed=0
  failed_status=0
  failed_names=""
  unmeasured_names=""
  unmarked_unmeasured=""
  left_to_linux=0
  for s in "${SUITE_DIR}"/test-*.sh; do
    [ -x "$s" ] || continue
    if [ "${SHELL_SUITES_MODE}" = "macos-only" ] && ! suite_needs_a_mac "$s"; then
      left_to_linux=$((left_to_linux+1))
      continue
    fi
    suites_ran=$((suites_ran+1))
    # NAMED BEFORE IT RUNS, NEVER AFTER (ovation#337). A suite says nothing until
    # it finishes, so a job killed part way through ends after the last suite that
    # COMPLETED and says nothing about the one that was running: the reader is left
    # working out what comes next in a glob they do not have in front of them.
    # Twice on 2026-09-15 that cost an hour, and the first diagnosis was wrong.
    # A name printed first cannot be lost, because it is already out when the kill
    # arrives.
    echo "==> $(basename "$s")"
    "$s"
    suite_status=$?
    suite_name="$(basename "$s")"
    if [ "${suite_status}" -eq 0 ]; then
      suites_passed=$((suites_passed+1))
    elif [ "${suite_status}" -eq 2 ]; then
      unmeasured_names="${unmeasured_names}${suite_name} "
      if [ "${SHELL_SUITES_MODE}" = "must-measure" ] && ! suite_needs_a_mac "$s"; then
        unmarked_unmeasured="${unmarked_unmeasured}${suite_name} "
      fi
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
  if [ "${SHELL_SUITES_MODE}" = "macos-only" ]; then
    echo "    ${left_to_linux} suite(s) carrying no '${SHELL_SUITE_MARKER}' line were left to the Linux job (ovation#161)."
    if [ "${suites_ran}" -eq 0 ]; then
      echo "Error: no suite carries '${SHELL_SUITE_MARKER}', so the macOS run measured nothing at all." >&2
      exit 7
    fi
  fi
  if [ -n "${unmarked_unmeasured}" ]; then
    for name in ${unmarked_unmeasured}; do
      echo "Error: ${name} could not measure here and carries no '${SHELL_SUITE_MARKER}' line," >&2
      echo "       so no CI job would ever measure it. Make it measure on Linux, or mark it as" >&2
      echo "       needing a Mac so the macOS build job runs it (ovation#161)." >&2
    done
    failed_status=1
  fi

  if [ "${failed_status}" -ne 0 ]; then
    echo "    the run stops here: a failing suite means nothing after it is worth" >&2
    echo "    taking the sibling locks for." >&2
    exit "${failed_status}"
  fi

  # The floor is checked only when nothing FAILED, because a failure breaks out
  # of the loop and the short count is then a consequence of the failure rather
  # than a fact about the tree. Reporting both would name the wrong cause (L11).
  if [ "${SHELL_SUITES_MODE}" = "macos-only" ]; then
    # THE FLOOR COUNTS EVERY SUITE, and this run is deliberately a subset of them.
    # The Linux job runs them all and holds the count; said rather than skipped
    # silently, for the reason the injected directory case below gives (L98).
    echo "==> Shell suite count check left to the Linux job: this run is the macOS subset (ovation#161)."
  elif [ -n "${OVATION_SHELL_SUITE_DIR:-}" ] && [ -z "${SUITE_FLOOR}" ]; then
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
    elif [ "${suites_ran}" -gt "${SUITE_FLOOR}" ]; then
      # AND A FLOOR THAT DOES NOT MOVE STOPS BEING A FLOOR (ovation#329), which
      # is the same reversal ovation#157 made to the pure floor, and this one
      # never got it. It said 59 on 2026-09-15 with 65 suites in scripts/: six
      # could lose their executable bit, be renamed or be deleted and the count
      # would still clear a floor six beneath it, which is exactly the partial
      # run it exists to refuse, and it passed the whole time (L63, L182, L354).
      # Nothing made the number move, so it was a rule living in whoever
      # remembered it (L27).
      #
      # REFUSED RATHER THAN PRINTED, for the pure floor's reason: a notice on a
      # green run is one nobody reads, and this is the only moment both numbers
      # are in front of anybody. The message is the command that fixes it rather
      # than a description of it (L399).
      echo "Error: the shell suites ran ${suites_ran} and the floor says ${SUITE_FLOOR}." >&2
      echo "       That is suites being ADDED, which is good, and the floor has to" >&2
      echo "       move with them or it stops being able to see a run that loses" >&2
      echo "       some. Run this, then push:" >&2
      echo "" >&2
      echo "       printf '%s\\n' ${suites_ran} > ${SHELL_FLOOR_FILE}" >&2
      echo "" >&2
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
  # (ovation#207). The create itself is the xcode_project_read_begin call below
  # the Xcode version note.
  #
  # AND THE PURE SUITE REGISTERS AS READING THE PROJECT (ovation#299). It builds
  # outside the directory build lock since ovation#271, so that lock no longer
  # tells a regeneration whether anything is reading the project. The same call
  # that makes sure a project exists registers this run against it, and a
  # regeneration refuses by name while the registration stands. Nothing a sibling
  # does can hold it, so the pure suite still never waits behind one.
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
  #
  # THE PAIR IS NAMED EVERY RUN, THE EXPLANATION SAID ONCE PER PAIR (ovation#320).
  # The mismatch became a state that lasts months rather than an afternoon: Xcode
  # updated itself here to 27.0, and macos-26, the image CI builds on, offers
  # 26.0.1 up to 26.6 and nothing newer (measured 2026-09-16), so there is no
  # version both sides can hold. A three line note on every build run is the note
  # people stop reading (L36). What is dropped is the PARAGRAPH; the versions
  # themselves stay on every run, because silence must never come to mean the bad
  # state, which is the same reason the matching case speaks at all.
  #
  # THE STAMP IS KEYED ON BOTH VERSIONS, not on the fact that they differ. A
  # message naming two things and deduplicated on one of them goes stale without
  # a symptom (L641): either half moving is a new pair and is explained again.
  # It is written on every measured run, matching or not, so that a mismatch
  # returning after a matching run is a change and is explained.
  #
  # IT IS A CACHE, and lives in one on purpose. Losing it costs one repeated
  # paragraph, it is not Dan's data and must not sit in the directory that holds
  # it, and a machine that has never run this is indistinguishable from one whose
  # cache was cleared, which is the harmless direction.
  # shellcheck source=lib/xcode-pin.sh
  require_lib "${REPO_ROOT}/scripts/lib/xcode-pin.sh"
  XCODE_PIN_FILE="${OVATION_XCODE_VERSION_FILE:-${REPO_ROOT}/.xcode-version}"
  XCODEBUILD_FOR_VERSION="${OVATION_XCODEBUILD:-xcodebuild}"
  XCODE_NOTICE_STATE="${OVATION_XCODE_NOTICE_STATE:-${HOME}/Library/Caches/Ovation/xcode-notice-state}"

  # ALREADY EXPLAINED <pair>: true when this machine was last told about exactly
  # this pair. An unreadable or absent stamp answers false, which repeats the
  # paragraph rather than dropping it: of the two ways to be wrong, saying it
  # twice is the one that loses nothing (L93).
  xcode_pair_already_explained() {
    [ -f "${XCODE_NOTICE_STATE}" ] || return 1
    [ "$(head -n 1 "${XCODE_NOTICE_STATE}" 2>/dev/null)" = "$1" ] || return 1
  }
  # REMEMBERING IS BEST EFFORT AND NEVER THE VERDICT. A read only home directory
  # must not fail a test run, and the failure is not silent: not remembering is
  # exactly the old behaviour, so the next run explains again.
  xcode_remember_pair() {
    mkdir -p "$(dirname "${XCODE_NOTICE_STATE}")" 2>/dev/null \
      && printf '%s\n' "$1" > "${XCODE_NOTICE_STATE}" 2>/dev/null || true
  }

  if ! CI_XCODE="$(xcode_pin_read "${XCODE_PIN_FILE}")"; then
    echo "==> NOTE: could not read the Xcode CI builds with from ${XCODE_PIN_FILE}"
    echo "    (it should hold one version number, like 26.6), so this Mac's Xcode was"
    echo "    not compared with CI's. The run continues."
  elif ! LOCAL_XCODE="$(xcode_active_version "${XCODEBUILD_FOR_VERSION}")"; then
    echo "==> NOTE: could not tell which Xcode this Mac builds with, so it was not"
    echo "    compared with Xcode ${CI_XCODE}, the version CI builds with. The run continues."
  elif [ "${LOCAL_XCODE}" = "${CI_XCODE}" ]; then
    echo "==> Building with Xcode ${LOCAL_XCODE}, the version CI builds with (.xcode-version)."
    xcode_remember_pair "${LOCAL_XCODE}|${CI_XCODE}"
  else
    echo "==> NOTE: this Mac builds with Xcode ${LOCAL_XCODE} and CI builds with Xcode ${CI_XCODE} (.xcode-version)."
    if ! xcode_pair_already_explained "${LOCAL_XCODE}|${CI_XCODE}"; then
      echo "    A green run here does not show CI's compiler will agree, so a push can"
      echo "    pass this gate and still fail to build in CI (ovation#270). The run continues."
      echo "    Said once for this pair of versions. It is said again whenever either"
      echo "    moves, and scripts/check-runner-xcode.sh watches for the day CI's image"
      echo "    can hold the version this Mac has."
    fi
    xcode_remember_pair "${LOCAL_XCODE}|${CI_XCODE}"
  fi

  # THE TWO COMMANDS THAT JUDGE AND REPAIR THE PROJECT, in one place each, so the
  # narrowed run below and the check further down cannot come to mean different
  # things by "current" (L70, L613).
  project_current() {
    if [ -n "${PROJECT_CURRENT_COMMAND}" ]; then
      OVATION_REPO_ROOT="${REPO_ROOT}" OVATION_XCODE_PROJECT="${XCODE_PROJECT}" \
        bash -c "${PROJECT_CURRENT_COMMAND}"
    else
      OVATION_REPO_ROOT="${REPO_ROOT}" OVATION_XCODE_PROJECT="${XCODE_PROJECT}" \
        "${REPO_ROOT}/scripts/check-xcode-project-current.sh"
    fi
  }
  regenerate_project() {
    if [ -n "${REGENERATE_COMMAND}" ]; then
      OVATION_REPO_ROOT="${REPO_ROOT}" OVATION_XCODE_PROJECT="${XCODE_PROJECT}" \
      OVATION_DIR_LOCK="${DIR_LOCK}" OVATION_XCODEGEN="${XCODEGEN}" \
        bash -c "${REGENERATE_COMMAND}"
    else
      OVATION_REPO_ROOT="${REPO_ROOT}" OVATION_XCODE_PROJECT="${XCODE_PROJECT}" \
      OVATION_DIR_LOCK="${DIR_LOCK}" OVATION_XCODEGEN="${XCODEGEN}" \
        "${REPO_ROOT}/scripts/regenerate-xcode-project.sh"
    fi
  }

  # ---------------------------------------------------------------------------
  # A NARROWED RUN REGENERATES A STALE PROJECT RATHER THAN STOPPING (ovation#321).
  #
  # A Swift file the project does not list is the NORMAL state of test first work:
  # the test file was written a minute ago, project.yml lists directories and the
  # generated project lists files. A full run stops and names the command, which is
  # right for a push gate; stopping a red-then-green cycle to run one command by
  # hand is what sent every such cycle around this runner in the first place.
  #
  # AND IT WAITS, WHERE THE REGENERATOR ITSELF REFUSES. regenerate-xcode-project.sh
  # refuses WITHOUT waiting while a build holds the lock or a run is reading the
  # project, deliberately, because it is normally a person at a keyboard who can
  # try again (scripts/regenerate-xcode-project.sh). Nobody is at the keyboard
  # inside this run, so this waits for it, at the same poll and deadline as the
  # sibling locks, SAYING the refusal's own words the first time and how long it
  # has been waiting as it goes: a wait that cannot be told from a hang is the
  # worse of the two (L110, L148).
  #
  # IT HAPPENS BEFORE THIS RUN REGISTERS AS A READER, because a regeneration
  # refuses while any live registration stands, and this run's own would be one
  # (ovation#299).
  if [ -n "${ONLY_TESTING}" ]; then
    CURRENT_WORDS="$(project_current 2>&1)"
    CURRENT_STATUS=$?
    if [ "${CURRENT_STATUS}" -eq 1 ]; then
      printf '%s\n' "${CURRENT_WORDS}"
      echo "==> The project does not list every Swift file on disk, which a new test file is."
      echo "    Regenerating ${XCODE_PROJECT} for this narrowed run, waiting up to ${TIMEOUT}s if"
      echo "    another run is using it."
      regen_started="$(date +%s)"
      regen_announced=0
      regen_refused=""
      while :; do
        REGEN_WORDS="$(regenerate_project 2>&1)"
        REGEN_STATUS=$?
        # 1 is the regenerator's "a lock is held, or a build is reading it", the
        # one outcome worth waiting on. Anything else is a fault in the tree that
        # waiting cannot mend, and it keeps its own status and its own words.
        [ "${REGEN_STATUS}" -eq 1 ] || break
        if [ -z "${regen_refused}" ]; then
          regen_refused=1
          echo "    The regeneration refused, so this run waits for it rather than stopping. It said:"
          printf '%s\n' "${REGEN_WORDS}" | sed 's/^/    /'
        fi
        regen_elapsed=$(( $(date +%s) - regen_started ))
        if [ "$((regen_elapsed / 30))" -gt "${regen_announced}" ]; then
          regen_announced=$((regen_elapsed / 30))
          echo "    still waiting to regenerate after ${regen_elapsed}s of ${TIMEOUT}s: ${REGEN_WORDS%%$'\n'*}"
        fi
        if [ "${regen_elapsed}" -gt "${TIMEOUT}" ]; then
          echo "Error: gave up waiting to regenerate ${XCODE_PROJECT} after ${TIMEOUT}s." >&2
          echo "       Nothing was built, and the project still does not list every Swift" >&2
          echo "       file on disk. The last refusal said:" >&2
          printf '%s\n' "${REGEN_WORDS}" | sed 's/^/       /' >&2
          exit 3
        fi
        sleep "${POLL}"
      done
      if [ "${REGEN_STATUS}" -ne 0 ]; then
        echo "Error: ${XCODE_PROJECT} could not be regenerated (the regenerator exited ${REGEN_STATUS})," >&2
        echo "       so this narrowed run stops rather than building the old set of files." >&2
        printf '%s\n' "${REGEN_WORDS}" | sed 's/^/       /' >&2
        exit "${REGEN_STATUS}"
      fi
      printf '%s\n' "${REGEN_WORDS}"
      # ASKED AGAIN AFTERWARDS. A regeneration that reported success and left the
      # project still missing a file is a run that would fail as a compiler error
      # about the code rather than about the project (ovation#206, L100).
      CURRENT_WORDS="$(project_current 2>&1)"
      CURRENT_STATUS=$?
      if [ "${CURRENT_STATUS}" -ne 0 ]; then
        printf '%s\n' "${CURRENT_WORDS}" >&2
        if [ "${CURRENT_STATUS}" -eq 1 ]; then
          echo "Error: ${XCODE_PROJECT} was regenerated and still does not list every Swift file" >&2
          echo "       on disk, so nothing here would be built from the tree as it is." >&2
        else
          echo "Error: ${XCODE_PROJECT} was regenerated and then could not be judged current" >&2
          echo "       (the check exited ${CURRENT_STATUS}), which is not a verdict that it is." >&2
        fi
        exit "${CURRENT_STATUS}"
      fi
    fi
  fi

  # shellcheck source=lib/ensure-xcode-project.sh
  require_lib "${REPO_ROOT}/scripts/lib/ensure-xcode-project.sh"
  xcode_project_read_begin "${REPO_ROOT}" "${XCODE_PROJECT}" "${XCODEGEN}" \
    "$(basename "${REPO_ROOT}") pure suite" "$$" || exit 2
  PROJECT_READER_PID="$$"

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
  project_current
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
  require_lib "${REPO_ROOT}/scripts/lib/dir-lock.sh"
  describe_dir_holder() { dir_lock_describe "${DIR_LOCK}"; }
  # ovation#433. ONE HOLDER IS ONE HOLDER HOWEVER MANY DESCRIPTORS ITS CHILDREN
  # INHERIT, which lives in lib/file-lock.sh with the measurement behind it. It
  # was four lines here and `lsof -t` answered with the holder and every child it
  # had started, so the words changed on almost every poll and the count below
  # read one holder as several (L441).
  # shellcheck source=lib/file-lock.sh
  require_lib "${REPO_ROOT}/scripts/lib/file-lock.sh"
  describe_file_holder() { file_lock_describe "${FILE_LOCK}"; }

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
  if [ "${ONLY_TARGET}" = "OvationHostedTests" ]; then
    # A run narrowed to the hosted suite builds the pure scheme for nothing, so it
    # is skipped, and said: a suite that did not run must never look like one that
    # passed (L98).
    echo "==> Pure suite SKIPPED: this run is narrowed to ${ONLY_TESTING}, which is in the hosted suite."
    STATUS=0
  else
    # THE FILTER IS ONE WORD OR NOTHING. `${X:+...}` expands to a single argument
    # when the filter is set and to NO argument at all when it is not, so the full
    # run's command line is exactly what it was.
    if [ -z "${TEST_COMMAND}" ]; then
      xcodebuild -project "${XCODE_PROJECT}" -scheme OvationCore \
        -destination 'platform=macOS' ${ONLY_TESTING:+"-only-testing:${ONLY_TESTING}"} \
        test 2>&1 | tee "${PURE_OUTPUT}"
    else
      bash -c "${TEST_COMMAND}" 2>&1 | tee "${PURE_OUTPUT}"
    fi
    STATUS="${PIPESTATUS[0]}"
  fi

  # THE PURE SUITE HAS STOPPED READING THE PROJECT, so a regeneration may go ahead
  # (ovation#299). The hosted suite reads it under the directory build lock, which
  # a regeneration also takes, so the registration is not needed past here.
  xcode_project_read_end "${XCODE_PROJECT}" "${PROJECT_READER_PID}"
  PROJECT_READER_PID=""

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
  if [ "${STATUS}" -eq 0 ] && [ -n "${ONLY_TESTING}" ]; then
    # THE FLOOR IS NOT APPLIED TO ANY NARROWED RUN, the hosted one included, where
    # the pure suite did not run at all and its skip is said above.
    #
    # A NARROWED RUN IS PART OF THE SUITE BY DESIGN, so the floor cannot judge it,
    # and that is said rather than silently not done (L98, L320).
    #
    # WHAT REPLACES IT IS THE ONE THING STILL WORTH REFUSING: that the filter
    # matched SOMETHING. `-only-testing:` with a path that resolves to no tests
    # makes xcodebuild print ** TEST SUCCEEDED ** and exit 0, so a misspelled suite
    # name reads as a passing test file, which is the exact failure a hand run of
    # one file produced and this option exists to end (L98, L288).
    #
    # THE COUNT IS ONLY READ WHEN THE PURE SUITE ACTUALLY RAN. A run narrowed to
    # the hosted suite skipped it, and reading an empty output there would refuse
    # every hosted narrowed run for having matched nothing, which was true of a
    # suite nobody asked to run (L11, L530). The hosted half reads its own count.
    if [ "${ONLY_TARGET}" = "OvationTests" ]; then
      echo "==> Pure test floor NOT APPLIED: this run is narrowed to ${ONLY_TESTING}, so it runs part"
      echo "    of the suite on purpose. It must still have executed at least one test."
      if ! grep -qE 'Test run with [1-9][0-9]* test' "${PURE_OUTPUT}"; then
        echo "Error: the filter ${ONLY_TESTING} matched nothing: the run reported success and" >&2
        echo "       executed NO tests. Check the suite and test names against the source," >&2
        echo "       and note that the suite name is the TYPE's name, not its display name." >&2
        STATUS=6
      fi
    fi
  elif [ "${STATUS}" -eq 0 ] && [ -n "${TEST_COMMAND}" ] && [ -z "${OVATION_TEST_FLOOR:-}" ]; then
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
    if [ "${ONLY_TARGET}" = "OvationTests" ]; then
      # The filter is in the pure suite, so the hosted half has nothing to run and
      # NEITHER SIBLING LOCK IS TAKEN for it: the pure suite takes none by design
      # (ovation#271), and a narrowed run that queued behind another app's build
      # for a suite it is not running would be the cheap path made expensive (L378).
      echo "==> Hosted suite SKIPPED: this run is narrowed to ${ONLY_TESTING}, which is in the pure suite, so no sibling lock was taken."
    elif [ -n "${TEST_COMMAND}" ] && [ -z "${HOSTED_TEST_COMMAND}" ]; then
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
      last_dir_id=""
      last_dir_owner=""
      last_file_holder=""
      last_file_id=""
      WAIT_OUTCOME=""
      note_holders() {
        local d d_id d_owner f f_id
        # A DIRECTORY LOCK HOLDER IS THE DIRECTORY IT MADE, NOT ITS DESCRIPTION
        # (ovation#303). Every change in the words used to count as one more run,
        # and the words change twice in a hold nobody else took: a holder is
        # unnamed between its mkdir and its owner line, and again while the lock
        # is being removed. On a busy machine a look landed in that moment often
        # enough to make one holder read as two, and the runner's own suite
        # failed on it. So a new holder is a new directory, or a different NAMED
        # owner in the same one, which is how a lock handed over faster than one
        # poll still counts when the filesystem reuses the inode number. An
        # unnamed moment is never a holder of its own. The one way this misleads
        # is two holders that never name themselves, back to back in one poll,
        # on a reused inode number, which can only undercount.
        d_id="$(dir_lock_identity "${DIR_LOCK}")"
        d_owner="$(dir_lock_owner "${DIR_LOCK}")"
        d="$(dir_lock_words "${DIR_LOCK}" "${d_owner}")"
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
        if [ -n "${d_id}" ]; then
          if [ "${d_id}" != "${last_dir_id}" ]; then
            holders_seen=$((holders_seen + 1))
            last_dir_owner="${d_owner}"
          elif [ -n "${d_owner}" ]; then
            if [ -n "${last_dir_owner}" ] && [ "${d_owner}" != "${last_dir_owner}" ]; then
              holders_seen=$((holders_seen + 1))
            fi
            last_dir_owner="${d_owner}"
          fi
        else
          last_dir_owner=""
        fi
        if [ -n "${f_id}" ] && [ "${f_id}" != "${last_file_id}" ]; then
          holders_seen=$((holders_seen + 1))
        fi
        last_dir_id="${d_id}"
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
          echo "       Several holders is a busy sibling. ONE holder the whole time is either" >&2
          echo "       a long run or one that died holding it, and the remedy depends on which" >&2
          echo "       lock (ovation#492): Downbeat's is a folder, so remove ${DIR_LOCK} if its" >&2
          echo "       named run has ended; Overture's is held by a live process, so removing a" >&2
          echo "       file frees nothing, and the fix is to stop the pid named above once you" >&2
          echo "       have checked its run has ended." >&2
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

    # THE HOSTED SUITE IS STARTED WITH THE LOCK'S DESCRIPTOR CLOSED (ovation#492).
    # The lock IS descriptor 9, and a numbered descriptor opened by `exec` is
    # inherited by every process started while it is held (L441). xcodebuild
    # starts many processes of its own, and one that outlived this run kept
    # Overture's lock held after the run that took it had gone: every later run on
    # this Mac, in all three apps, then waited out its timeout. `9>&-` closes it in
    # the child only, so this run still holds the lock and nothing it starts can.
    if [ -n "${HOSTED_TEST_COMMAND}" ]; then
      HOSTED_OUTPUT="$(bash -c "${HOSTED_TEST_COMMAND}" 2>&1 9>&-)"
    else
      # NARROWED IN PLACE OF THE WHOLE HOSTED TARGET, never beside it: two
      # -only-testing arguments are a union, so a filter added beside the target
      # would run the whole hosted suite while reading as one test (ovation#321).
      HOSTED_OUTPUT="$(xcodebuild -project "${XCODE_PROJECT}" -scheme Ovation \
        -destination 'platform=macOS' \
        "-only-testing:${ONLY_TESTING:-OvationHostedTests}" test 2>&1 9>&-)"
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
      if [ -n "${ONLY_TESTING}" ]; then
        echo "Error: the filter ${ONLY_TESTING} matched nothing: the run reported success and" >&2
        echo "       executed NO tests. Check the suite and test names against the source." >&2
      else
        echo "Error: the hosted run reported success and executed NO tests." >&2
        echo "       A -only-testing: path that matches nothing does exactly this." >&2
        echo "       Nothing about the launch surface was verified." >&2
      fi
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
