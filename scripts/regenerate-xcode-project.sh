#!/bin/bash
# Regenerate Ovation.xcodeproj, under the lock every build of it already takes.
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
# THE LOCK IS THE RUNNER'S, not one of its own. A lock must be the one the
# READERS take or it protects nothing (L453), and what reads the project is
# xcodebuild, which runs under /tmp/xcodebuild-tests.lock. That lock is shared
# with Downbeat, so this is coarser than the resource it protects; the
# alternative, a private lock nothing else takes, would be a lock that guards an
# empty room (L369).
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
#     1  the lock is held, and it says by whom. Nothing was touched
#     2  there is no generator, or the generator failed
#     3  there is no project.yml to generate from
#
# Seams: OVATION_REPO_ROOT, OVATION_XCODE_PROJECT, OVATION_XCODEGEN,
# OVATION_DIR_LOCK.
set -uo pipefail

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
. "${HERE}/lib/dir-lock.sh"

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

# NON BLOCKING, ON PURPOSE. See the header: a refusal naming the holder beats a
# silent ten minute wait.
if ! dir_lock_take "${DIR_LOCK}" "$(basename "${REPO_ROOT}") regenerate" "$$"; then
    echo "REFUSED: ${DIR_LOCK} is $(dir_lock_describe "${DIR_LOCK}")." >&2
    echo "         Rewriting ${PROJECT} while a build is reading it is the hazard this" >&2
    echo "         refusal exists for. Nothing was touched. Try again when that run is" >&2
    echo "         done, or find out what is holding the lock." >&2
    exit 1
fi

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

release() {
    # THE ASIDE COPY IS PUT BACK ON EVERY PATH THAT DID NOT REPLACE IT, including
    # an interrupt, because a run killed between the move and the generate would
    # otherwise leave the project under a name nothing looks for (L514, L515).
    if [ -e "${ASIDE}" ]; then
        rm -rf "${PROJECT}" 2>/dev/null || true
        mv "${ASIDE}" "${PROJECT}" 2>/dev/null || true
    fi
    rm -rf "${DIR_LOCK}" 2>/dev/null || true
}
trap release EXIT INT TERM

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
