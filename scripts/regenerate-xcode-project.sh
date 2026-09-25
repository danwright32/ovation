#!/bin/bash
# Regenerate Ovation.xcodeproj, under the build lock and the project's own create
# lock, and never while a build outside those locks is reading it.
#
#     regenerate-xcode-project.sh
#     regenerate-xcode-project.sh --wait <seconds>
#
# ovation#202. The project is generated from project.yml and gitignored, and
# `lib/ensure-xcode-project.sh` deliberately never regenerates one that exists:
# rewriting it on every build rewrites the file underneath an open Xcode. But
# ADDING A SOURCE FILE REQUIRES a regeneration, because project.yml lists
# directories and the generated project lists files. So the moment a new Swift
# file appears somebody deletes the project and remakes it, and nothing checked
# whether a build was reading it at that moment.
#
# IT HAPPENED. On 2026-09-10 `rm -rf Ovation.xcodeproj && xcodegen generate` ran
# while `run-tests.sh` was in its Xcode phase. It survived, and survival is the
# evidence of luck rather than of safety. The repository already had the
# mechanism: the runner takes file locks precisely so two builds do not collide,
# and the one operation that rewrites the project out from under a build was the
# one operation outside the locking (L453).
#
# IT REFUSES RATHER THAN WAITING, unless told to wait. Regenerating was taken to
# be a deliberate act somebody does at a keyboard, where waiting silently behind a
# ten minute suite is worse than being told to try again, and the refusal NAMES
# the holder, so it is actionable rather than just a no (L148).
#
# BUT TRYING AGAIN NEVER WORKS UNDER TRAFFIC (ovation#542). A refusal leaves the
# arrival queue, so every retry joins at the back, behind whoever arrived while it
# was away. On 2026-09-25 a retry every 15 seconds lost for 3617s straight while
# Overture kept queueing runs, and a fresh worktree could not be pushed (L1012).
# So `--wait <seconds>` joins the queue ONCE and keeps its ticket until it is at
# the front and the lock is free, says what it is waiting behind as it goes, and
# refuses by name at the deadline. Every remedy that tells somebody to run this
# names --wait, because the somebody is usually not at a keyboard at all. Without
# it this still refuses at once, for a person who would rather know now.
#
# --wait covers the build lock and its queue, which is where the traffic is. A
# build reading the project OUTSIDE that lock, or another regeneration holding
# the create lock, is still a refusal at once: both are brief and rare.
#
# THE LOCKS ARE THE READERS', not one of its own. A lock must be the one the
# READERS take or it protects nothing (L453). The hosted suite reads the project
# under /tmp/xcodebuild-tests.lock, so this takes that lock; it is shared with
# Downbeat, so it is coarser than the resource it protects, and a private lock
# nothing else takes would guard an empty room (L369).
#
# THAT LOCK STOPPED BEING THE WHOLE ANSWER (ovation#299). Since ovation#271 the
# pure suite builds WITHOUT it, and so do the Debug and Release builds of
# build-products.sh, which travel as the runner's pure command (ovation#302). Both
# can leave the directory lock free while they read the project. The pure suite must not start waiting behind a sibling, so
# it takes no lock; it registers itself against the project through
# lib/ensure-xcode-project.sh, and this refuses while a live registration stands,
# naming it. This also takes that project's create lock while it rewrites, so a
# pure suite starting in the middle waits for the new project rather than building
# from one that has been moved aside.
#
# WHAT IT DOES NOT DO, said rather than left to be discovered. It does not run
# when a source file is added: that is still a step somebody takes, and
# `ensure-xcode-project.sh` still creates a project where there is none, before
# the locks, so a fresh checkout does not queue behind a sibling's build. Whether
# adding a file should TRIGGER this is the open half of ovation#202.
#
# Exit codes, one per outcome (L11):
#
#     0  regenerated
#     1  a lock is held, or a build is reading the project, and it says by whom.
#        Nothing was touched
#     2  there is no generator, or the generator failed
#     3  there is no project.yml to generate from
#     4  used wrongly: an argument it does not know, or a --wait that is not a
#        whole number of seconds. Nothing was touched
#
# Seams: OVATION_REPO_ROOT, OVATION_XCODE_PROJECT, OVATION_XCODEGEN,
# OVATION_DIR_LOCK, OVATION_REGENERATE_WAIT (--wait), OVATION_REGENERATE_POLL (seconds between looks while
# waiting, 5 by default), OVATION_REGENERATE_ANNOUNCE (seconds between "still
# waiting" lines, 30 by default). The arrival queue is "<OVATION_DIR_LOCK>.queue", derived from
# it, so a throwaway lock brings a throwaway queue (downbeat#524).
set -uo pipefail
# ovation#399: every library is loaded through require_lib, which refuses by name
# rather than carrying on without it. See scripts/lib/require.sh.
. "$(dirname "${BASH_SOURCE[0]}")/lib/require.sh" 2>/dev/null || { echo "REFUSED: scripts/lib/require.sh is missing, so nothing was checked." >&2; exit 2; }

# OVATION_REGENERATE_WAIT is --wait by environment, which is how run-tests.sh
# hands this every other setting; an argument given as well wins.
WAIT="${OVATION_REGENERATE_WAIT:-}"
WAIT_FROM="OVATION_REGENERATE_WAIT"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --wait)
            WAIT="${2:-}"
            WAIT_FROM="--wait"
            [ -n "${WAIT}" ] || WAIT="(nothing)"
            shift; [ "$#" -gt 0 ] && shift ;;
        *)
            echo "REFUSED: $1 is not an argument this knows. Nothing was touched." >&2
            echo "         Usage: regenerate-xcode-project.sh [--wait <seconds>]" >&2
            exit 4 ;;
    esac
done
case "${WAIT}" in
    *[!0-9]*)
        echo "REFUSED: ${WAIT_FROM} takes a whole number of seconds, and was given '${WAIT}'." >&2
        echo "         Nothing was touched." >&2
        exit 4 ;;
esac
POLL="${OVATION_REGENERATE_POLL:-5}"
ANNOUNCE="${OVATION_REGENERATE_ANNOUNCE:-30}"

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${OVATION_REPO_ROOT:-$(dirname "${HERE}")}"
# THE TWO PATHS THIS DELETES HONOUR AN EMPTY VALUE, with `-` rather than `:-`, so
# a caller who sets one to nothing gets the refusal below rather than the default.
# Written the usual way an empty OVATION_XCODE_PROJECT silently became the REAL
# project path, so pointing this at nothing pointed it at everything and the
# guard could never fire: a check that cannot be reached is not a check (L29).
PROJECT="${OVATION_XCODE_PROJECT-${REPO_ROOT}/Ovation.xcodeproj}"
DIR_LOCK="${OVATION_DIR_LOCK-/tmp/xcodebuild-tests.lock}"
XCODEGEN="${OVATION_XCODEGEN:-$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)}"

# shellcheck source=lib/dir-lock.sh
require_lib "${HERE}/lib/dir-lock.sh"
# shellcheck source=lib/ensure-xcode-project.sh
require_lib "${HERE}/lib/ensure-xcode-project.sh"

# GUARDED BEFORE ANY DELETE. Both of these come from seams, and a recursive
# delete built from an empty variable is not the place to rely on a caller having
# set one (L5).
if [ -z "${PROJECT}" ] || [ -z "${DIR_LOCK}" ]; then
    echo "REFUSED: this was given an empty project path or an empty lock path, and" >&2
    echo "         it deletes things. Nothing was touched." >&2
    exit 3
fi

SPEC="${REPO_ROOT}/project.yml"
if [ ! -f "${SPEC}" ]; then
    echo "REFUSED: there is no ${SPEC} to generate from, so nothing was regenerated." >&2
    echo "         This is generated from project.yml rather than committed, so a tree" >&2
    echo "         without one has no project to make." >&2
    exit 3
fi

if [ ! -x "${XCODEGEN}" ]; then
    echo "REFUSED: xcodegen is not at ${XCODEGEN}, so the project cannot be made." >&2
    echo "         Install it with: brew install xcodegen" >&2
    exit 2
fi

# AND IT TAKES ITS TURN (downbeat#524). Waiters on this lock are served in the
# order they arrived, through a queue beside it that Downbeat, Overture and the
# runner all read (lib/lock-queue.sh). This does not wait, so it joins, looks
# once, and leaves: a FREE lock with a live earlier waiter queued is that
# waiter's, and taking it anyway is the barging the queue exists to stop. A queue
# that cannot be written is no reason to refuse, since mkdir below is still the
# only exclusion; this then competes the old way.
#
# NEVER CALLED BY A RUN THAT IS ITSELF QUEUED. run-tests.sh regenerates before it
# joins, because its own ticket would be a live earlier waiter here and it would
# wait on this refusal until its deadline (test-run-tests.sh case 524c).
# shellcheck source=lib/lock-queue.sh
require_lib "${HERE}/lib/lock-queue.sh"
# What stands between this run and the lock right now, in WHY_NOT, or nothing
# when the lock was just taken. Asked the same way whether or not it waits, so the
# two modes cannot come to disagree about what a turn is.
take_turn() {
    WHY_NOT=""
    lock_queue_ahead
    if [ "${LOCK_QUEUE_AHEAD}" -gt 0 ]; then
        WHY_NOT="${DIR_LOCK} is $(dir_lock_describe "${DIR_LOCK}"), and ${LOCK_QUEUE_AHEAD} earlier run(s) are queued for it in ${DIR_LOCK}.queue, so it is theirs first"
        return 1
    fi
    if ! dir_lock_take "${DIR_LOCK}" "$(basename "${REPO_ROOT}") regenerate" "$$"; then
        WHY_NOT="${DIR_LOCK} is $(dir_lock_describe "${DIR_LOCK}")"
        return 1
    fi
}

lock_queue_join "${DIR_LOCK}" "$$" || true
if [ -z "${WAIT}" ]; then
    if ! take_turn; then
        lock_queue_leave
        echo "REFUSED: ${WHY_NOT}." >&2
        echo "         Rewriting ${PROJECT} while a build is reading it is the hazard this" >&2
        echo "         refusal exists for. Nothing was touched. Try again when that run is" >&2
        echo "         done, or run this with --wait <seconds> to keep a place in the queue." >&2
        exit 1
    fi
else
    WAIT_STARTED="$(date +%s)"
    ANNOUNCED=0
    until take_turn; do
        WAITED=$(( $(date +%s) - WAIT_STARTED ))
        if [ "${ANNOUNCED}" -eq 0 ]; then
            echo "WAITING: ${WHY_NOT}." >&2
            echo "         Holding this run's place in the queue, for up to ${WAIT}s." >&2
            ANNOUNCED=1
        elif [ "${ANNOUNCE}" -gt 0 ] && [ "$(( WAITED / ANNOUNCE ))" -ge "${ANNOUNCED}" ]; then
            ANNOUNCED=$(( WAITED / ANNOUNCE + 1 ))
            echo "         still waiting after ${WAITED}s of ${WAIT}s: ${WHY_NOT}." >&2
        fi
        if [ "${WAITED}" -ge "${WAIT}" ]; then
            lock_queue_leave
            echo "REFUSED: gave up after ${WAITED}s of ${WAIT}s waiting for a turn: ${WHY_NOT}." >&2
            echo "         Nothing was touched." >&2
            exit 1
        fi
        sleep "${POLL}"
    done
fi
lock_queue_leave
DIR_LOCK_HELD=1

# RELEASED ON EVERY EXIT PATH, including a generator that failed. A mkdir lock is
# not released by the kernel when its holder dies, so one left planted blocks
# every build on this machine until somebody finds the directory by hand (L409).
# THE OLD PROJECT IS MOVED ASIDE, NEVER DELETED, until the new one exists.
#
# It used to be `rm -rf "${PROJECT}"` followed by a generate, so a generator that
# failed left the tree with NO project at all: good state destroyed before its
# replacement was verified to exist (L5). The refusal said so, which is honest
# and is not the same as not doing it. Moving it aside makes the failure
# recoverable rather than merely well described.
ASIDE="${PROJECT}.previous.$$"
CREATE_LOCK="$(xcode_project_create_lock "${PROJECT}")"
CREATE_LOCK_HELD=""

release() {
    # THE ASIDE COPY IS PUT BACK ON EVERY PATH THAT DID NOT REPLACE IT, including
    # an interrupt, because a run killed between the move and the generate would
    # otherwise leave the project under a name nothing looks for (L514, L515).
    if [ -e "${ASIDE}" ]; then
        rm -rf "${PROJECT}" 2>/dev/null || true
        mv "${ASIDE}" "${PROJECT}" 2>/dev/null || true
    fi
    # Only a lock this run TOOK is removed, and each only ONCE. A stopped run
    # passes through here twice (the signal trap, then EXIT), and a second
    # unconditional delete could remove a lock another run took in between.
    if [ -n "${CREATE_LOCK_HELD}" ]; then
        rm -rf "${CREATE_LOCK}" 2>/dev/null || true
        CREATE_LOCK_HELD=""
    fi
    if [ -n "${DIR_LOCK_HELD}" ]; then
        rm -rf "${DIR_LOCK}" 2>/dev/null || true
        DIR_LOCK_HELD=""
    fi
}
# A REGENERATION TOLD TO STOP, STOPS (ovation#302). This was one trap for EXIT,
# INT and TERM, and a trap on INT or TERM that only cleans up RETURNS to the
# script (L473): a stopped regeneration put the old project back, let go of both
# locks, and carried on, into xcodegen unlocked or on to "OK: regenerated" over a
# project the trap had just replaced. ovation#274 fixed the same shape in
# run-tests.sh, and this is the same fix: release, then exit with 128 plus the
# signal, so a stopped run cannot read as a finished one.
#
# As there, bash runs the trap when the command in front of it returns, so a
# signal sent to this pid alone during xcodegen takes effect when xcodegen ends.
trap release EXIT
trap 'release; exit 130' INT
trap 'release; exit 143' TERM

# THE PROJECT'S CREATE LOCK, so a run about to read the project waits for this
# one's result, as it waits for a create (ovation#299, ovation#207). A lock left
# by a run that died is claimed through the same function the waiting side uses.
if ! dir_lock_take "${CREATE_LOCK}" "$(basename "${REPO_ROOT}") regenerate" "$$"; then
    if xcode_project_claim_dead_lock "${CREATE_LOCK}" "${PROJECT}" >&2 \
        && dir_lock_take "${CREATE_LOCK}" "$(basename "${REPO_ROOT}") regenerate" "$$"; then
        :
    else
        echo "REFUSED: ${PROJECT} is being created by another run:" >&2
        echo "         ${CREATE_LOCK} is $(dir_lock_describe "${CREATE_LOCK}")." >&2
        echo "         Nothing was touched. Try again when that run is done." >&2
        exit 1
    fi
fi
CREATE_LOCK_HELD=1

# AND NOBODY IS READING IT OUTSIDE THE BUILD LOCK (ovation#299). Asked AFTER the
# create lock is held, because a pure suite registers and then looks at that lock,
# so whichever of the two moves second sees the first.
if LIVE_READERS="$(xcode_project_live_readers "${PROJECT}")"; then
    echo "REFUSED: a build is reading ${PROJECT} right now, outside the build lock:" >&2
    printf '%s\n' "${LIVE_READERS}" | sed 's/^/         held by /' >&2
    echo "         Rewriting it under that build is the hazard this refusal exists" >&2
    echo "         for, and it would fail as a broken build rather than as a race." >&2
    echo "         Nothing was touched. Try again when that run is done." >&2
    exit 1
fi

if [ -e "${PROJECT}" ] && ! mv "${PROJECT}" "${ASIDE}"; then
    echo "REFUSED: ${PROJECT} could not be moved aside, so nothing was regenerated." >&2
    echo "         It is still there, untouched." >&2
    exit 2
fi

if ! ( cd "${REPO_ROOT}" && "${XCODEGEN}" generate ) >/dev/null 2>&1; then
    echo "REFUSED: xcodegen could not generate ${PROJECT} from ${SPEC}." >&2
    echo "         The project that was there has been put back, so the tree still" >&2
    echo "         builds. Fix project.yml and run this again." >&2
    exit 2
fi

# THE COMMITTED PACKAGE RESOLUTION IS CARRIED OVER (ovation#421). It is a tracked
# file inside the project, and xcodegen writes a project with none, so dropping
# the old project with it would delete a committed file and leave the next build
# to resolve every package afresh: the floating that committing it exists to
# end. Copied before the old project is dropped, and a copy that fails is a
# refusal with the old project put back, never a regeneration reported as done
# over a tree that lost its lock file (L5).
RESOLVED_IN="project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if [ -f "${ASIDE}/${RESOLVED_IN}" ] && [ ! -e "${PROJECT}/${RESOLVED_IN}" ]; then
    if ! { mkdir -p "$(dirname "${PROJECT}/${RESOLVED_IN}")" \
        && cp -p "${ASIDE}/${RESOLVED_IN}" "${PROJECT}/${RESOLVED_IN}"; }; then
        echo "REFUSED: the regenerated project could not be given the committed package" >&2
        echo "         resolution from the old one, so the project that was there has been" >&2
        echo "         put back rather than losing it." >&2
        exit 2
    fi
fi

# THE NEW ONE EXISTS, so the old one is no longer wanted. Dropped here rather
# than left for the trap, which would put it back over the new project.
rm -rf "${ASIDE}" 2>/dev/null || true

echo "OK: regenerated ${PROJECT} from ${SPEC}, under ${DIR_LOCK}."
