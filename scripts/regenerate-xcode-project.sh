#!/bin/bash
# Regenerate Ovation.xcodeproj, under the build lock and the project's own create
# lock, and never while a build outside those locks is reading it.
#
#     regenerate-xcode-project.sh
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
# IT REFUSES RATHER THAN WAITING, and that is the decision rather than a detail.
# Regenerating is a deliberate act somebody is doing at a keyboard; waiting
# silently behind a ten minute suite is worse than being told to try again. The
# refusal NAMES the holder, so it is actionable rather than just a no (L148).
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
#
# Seams: OVATION_REPO_ROOT, OVATION_XCODE_PROJECT, OVATION_XCODEGEN,
# OVATION_DIR_LOCK. The arrival queue is "<OVATION_DIR_LOCK>.queue", derived from
# it, so a throwaway lock brings a throwaway queue (downbeat#524).
set -uo pipefail
# ovation#399: every library is loaded through require_lib, which refuses by name
# rather than carrying on without it. See scripts/lib/require.sh.
. "$(dirname "${BASH_SOURCE[0]}")/lib/require.sh" 2>/dev/null || { echo "REFUSED: scripts/lib/require.sh is missing, so nothing was checked." >&2; exit 2; }

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
QUEUED_AHEAD=0
if lock_queue_join "${DIR_LOCK}" "$$"; then
    lock_queue_ahead
    QUEUED_AHEAD="${LOCK_QUEUE_AHEAD}"
fi
if [ "${QUEUED_AHEAD}" -gt 0 ]; then
    lock_queue_leave
    echo "REFUSED: ${DIR_LOCK} is $(dir_lock_describe "${DIR_LOCK}"), and ${QUEUED_AHEAD} earlier run(s)" >&2
    echo "         are queued for it in ${DIR_LOCK}.queue, so it is theirs first." >&2
    echo "         Nothing was touched. Try again when they are done." >&2
    exit 1
fi

# NON BLOCKING, ON PURPOSE. See the header: a refusal naming the holder beats a
# silent ten minute wait.
if ! dir_lock_take "${DIR_LOCK}" "$(basename "${REPO_ROOT}") regenerate" "$$"; then
    lock_queue_leave
    echo "REFUSED: ${DIR_LOCK} is $(dir_lock_describe "${DIR_LOCK}")." >&2
    echo "         Rewriting ${PROJECT} while a build is reading it is the hazard this" >&2
    echo "         refusal exists for. Nothing was touched. Try again when that run is" >&2
    echo "         done, or find out what is holding the lock." >&2
    exit 1
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

# THE NEW ONE EXISTS, so the old one is no longer wanted. Dropped here rather
# than left for the trap, which would put it back over the new project.
rm -rf "${ASIDE}" 2>/dev/null || true

echo "OK: regenerated ${PROJECT} from ${SPEC}, under ${DIR_LOCK}."
