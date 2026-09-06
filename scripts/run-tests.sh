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
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DIR_LOCK="${OVATION_DIR_LOCK:-/tmp/xcodebuild-tests.lock}"
FILE_LOCK="${OVATION_FILE_LOCK:-/tmp/overture-mac-tests.lock}"
TIMEOUT="${OVATION_LOCK_TIMEOUT:-1800}"
FLOCK_BIN="${OVATION_FLOCK_BIN:-/opt/homebrew/bin/flock}"
TEST_COMMAND="${OVATION_TEST_COMMAND:-}"

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
if [ ! -x "${FLOCK_BIN}" ]; then
  echo "Error: flock was not found at ${FLOCK_BIN}." >&2
  echo "       Ovation's test runner takes Overture's lock, which uses it." >&2
  echo "       Install it with: brew install flock" >&2
  echo "       Refusing to run the tests without excluding the sibling apps." >&2
  exit 2
fi

# 1. DOWNBEAT'S LOCK FIRST. mkdir is atomic on every filesystem that matters,
#    which is why it is the primitive rather than a check followed by a create.
echo "==> Waiting for the shared xcodebuild lock at ${DIR_LOCK}"
waited=0
until mkdir "${DIR_LOCK}" 2>/dev/null; do
  waited=$((waited+1))
  if [ "${waited}" -gt "${TIMEOUT}" ]; then
    echo "Error: gave up waiting for ${DIR_LOCK} after ${TIMEOUT}s." >&2
    echo "       Another xcodebuild run is holding it, or a previous one died." >&2
    echo "       If nothing is running, remove ${DIR_LOCK} and try again." >&2
    exit 3
  fi
  sleep 1
done
DIR_LOCK_HELD=1
printf '%s:%s\n' "$(basename "${REPO_ROOT}")" "$$" > "${DIR_LOCK}/owner" 2>/dev/null || true

# 2. OVERTURE'S LOCK SECOND, always. Held through a file descriptor rather than
#    by wrapping the command, so the same shell holds both and the trap above can
#    release both.
echo "==> Waiting for Overture's lock at ${FILE_LOCK}"
: > "${FILE_LOCK}" 2>/dev/null || true
exec 9>"${FILE_LOCK}" || { echo "Error: cannot open ${FILE_LOCK}" >&2; exit 3; }
if ! "${FLOCK_BIN}" -w "${TIMEOUT}" 9; then
  echo "Error: gave up waiting for ${FILE_LOCK} after ${TIMEOUT}s." >&2
  echo "       An Overture test run is holding it." >&2
  exit 3
fi
FLOCK_FD=9

echo "==> Holding both locks. Running Ovation's tests."

# The command is injectable so the suite can measure the LOCKING without paying
# for a three minute xcodebuild (L2, L291). The default is the real thing.
if [ -z "${TEST_COMMAND}" ]; then
  bash -c 'for s in "'"${REPO_ROOT}"'"/scripts/test-*.sh; do "$s" || exit 1; done' \
    && xcodebuild -project "${REPO_ROOT}/Ovation.xcodeproj" -scheme OvationCore \
       -destination 'platform=macOS' test
else
  bash -c "${TEST_COMMAND}"
fi
STATUS=$?

# Judge by the EXIT CODE, never by a line of output: a tool's final line is
# routinely a different measurement than its verdict, and usually the more
# reassuring of the two (L184).
exit "${STATUS}"
