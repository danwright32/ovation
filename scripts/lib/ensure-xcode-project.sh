# ovation#151. Make the Xcode project when there is none, and only then.
#
# `Ovation.xcodeproj` is generated from project.yml by xcodegen and is gitignored
# (all but its committed package resolution, ovation#421),
# so a fresh clone, Dan's second Mac and any CI runner start without one. What
# that gave was `xcodebuild: error: Ovation.xcodeproj does not exist`, which names
# the symptom rather than the missing step.
#
# NEVER REGENERATED WHEN IT IS THERE, and that is the whole of the decision.
# Rewriting the project on every build is a different act from making one on a
# machine that has none: it rewrites the file underneath an open Xcode. The third
# option, committing the project the way Overture does, was not taken because this
# repository deliberately ignores it and would then owe a freshness check to carry
# the drift, which Overture pays for with `scripts/check-pbxproj-fresh.sh`.
#
# IT IS A SHARED FUNCTION rather than a block copied into each caller, because
# every route to xcodebuild needs it and a second copy is a second thing to keep
# correct (L613, L370).
#
# TWO CREATES AT ONCE MAKE IT ONCE (ovation#207). ovation#202 put REGENERATING
# under the lock every build takes and left this alone, on purpose: a fresh
# checkout must not queue behind a sibling's build for a file nothing can be
# reading. That holds against a build and not against a second create. Two runs
# starting together on a fresh tree both saw no project and both ran xcodegen at
# the same path; and because xcodegen makes the project DIRECTORY before it has
# finished writing into it, a second run could also see "there is a project" and
# build from a half written one.
#
# SO A CREATE TAKES A LOCK, AND IT IS NOT THE BUILD LOCK. The build lock is shared
# with Downbeat, so taking it here means either queueing a fresh checkout behind a
# sibling's build, which ovation#202 refused, or falling through without it when
# it is busy, which leaves this race open exactly while a sibling is building. The
# lock is scoped to the resource instead: one lock per project path, which only
# another create of that same project can hold (L369). A run that finds it held
# WAITS FOR THAT RUN'S RESULT rather than generating over it, and that wait is
# the length of one xcodegen, which is seconds.
#
# A LOCK LEFT BY A RUN THAT DIED IS CLAIMED. A mkdir lock is not released by the
# kernel, and run-tests.sh exits on INT and TERM (ovation#274), so a stopped
# create leaves one behind. The owner line names the pid, and a pid that is no
# longer running is not creating anything (L409, L600). A live holder that never
# finishes is refused at a deadline, naming it, rather than waited on for ever
# (L110). No trap is set here: this is sourced, and a trap would replace the
# caller's own.
#
# AND A BUILD READING THE PROJECT OUTSIDE THE BUILD LOCK IS VISIBLE (ovation#299).
# Since ovation#271 the runner builds the pure suite without the directory build
# lock, so that lock stopped saying whether anything is reading the project, and
# regenerate-xcode-project.sh could move the project aside under a pure build.
# The failure that makes reads as a broken build or a missing file rather than a
# race, so the diagnosis starts in the wrong place.
#
# The same project scoped mechanism answers it, rather than a third lock. A
# regeneration takes THIS create lock while it rewrites, so a run about to read
# the project waits for it exactly as it waits for a create. And a run reading the
# project REGISTERS itself in a folder beside the lock, one file per run named by
# pid and holding the same owner line, which the regeneration reads and refuses
# on by name. It is a registration rather than the create lock held for the whole
# build, because two pure suites reading one project at once is fine (measured,
# ovation#271), and holding the create lock would make the second wait minutes on
# a message saying the project is being created. Nothing here can be held by a
# sibling, so the pure suite still never waits behind Downbeat or Overture.
#
# THE ORDER CLOSES THE RACE. A reader registers and THEN looks at the create lock;
# a regeneration takes the create lock and THEN looks at the registrations. Either
# ordering of the two leaves one of them seeing the other.
#
# Sourced, so it can read and be read by the caller's own seams.

# shellcheck source=dir-lock.sh
# ovation#399: libraries are loaded through require_lib, which refuses by name.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/require.sh" 2>/dev/null || { echo "REFUSED: scripts/lib/require.sh is missing, so nothing was checked." >&2; exit 2; }
require_lib "$(dirname "${BASH_SOURCE[0]}")/dir-lock.sh"

# The key every per project path is derived from, in one place, so the create
# lock and the registrations beside it can never be derived differently (L70).
xcode_project_key() {
    printf '%s' "$1" | cksum | awk '{ print $1 }'
}

# The create lock for a project, derived from its path so that two trees never
# share one and one tree always does. In /tmp beside the build locks rather than
# in the tree, so a lock a dead run leaves behind is not a stray directory for
# every tree walking guard to find.
xcode_project_create_lock() {
    printf '/tmp/ovation-project-create-%s.lock' "$(xcode_project_key "$1")"
}

# Where a run reading a project outside the build lock registers itself
# (ovation#299). Beside the create lock, for the same reasons.
xcode_project_readers() {
    printf '/tmp/ovation-project-readers-%s' "$(xcode_project_key "$1")"
}

# WHETHER THERE IS A PROJECT (ovation#421). The directory alone stopped being
# the answer when the package resolution inside it was committed: a fresh clone
# has an Ovation.xcodeproj/ holding that one file and nothing Xcode can open.
# Taken as a project, the create would be skipped and xcodebuild would meet a
# project with no project file, naming the symptom rather than the missing step.
# So a directory holding NOTHING BUT the committed resolution is no project, and
# anything else xcodegen or a person put there still is, exactly as before.
# xcodegen generates into such a directory and leaves the resolution where it
# is. lib/built-product.sh asks the same question the same way, and
# scripts/test-package-resolution.sh holds the two to agree.
XCODE_PROJECT_RESOLVED_IN="project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
xcode_project_present() {
    [ -d "$1" ] || return 1
    [ -f "$1/${XCODE_PROJECT_RESOLVED_IN}" ] || return 0
    [ -n "$(find "$1" -type f ! -path "$1/${XCODE_PROJECT_RESOLVED_IN}" -print 2>/dev/null | head -1)" ]
}

# Claims a create lock whose owner is no longer running. Answers 0 when the
# holder was dead (the lock is then free, or was taken by somebody else in
# between), and 1 when the lock is held by a live run or one that named no pid,
# which is a holder this cannot judge and so is treated as live (L42).
#
# CLAIMED BY MOVING IT ASIDE, and only if what was moved is still the dead run's.
# Two waiters can both find the same dead holder; a plain delete by the slower one
# would remove the lock the faster one has just taken. Moving and then reading
# what was moved means a fresh lock caught by mistake is put straight back. The
# window that survives is a third run taking the lock in between, and it is said
# rather than hidden.
xcode_project_claim_dead_lock() {
    local lock="$1" project="$2" owner pid holder aside
    [ -d "${lock}" ] || return 1
    holder="$(dir_lock_describe "${lock}")"
    owner="$(head -1 "${lock}/owner" 2>/dev/null)"
    pid="${owner##*:}"
    case "${pid}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    ps -p "${pid}" >/dev/null 2>&1 && return 1
    aside="${lock}.stale.$$"
    if mv "${lock}" "${aside}" 2>/dev/null; then
        if [ "$(head -1 "${aside}/owner" 2>/dev/null)" = "${owner}" ]; then
            rm -rf "${aside}"
            echo "==> A create lock for $(basename "${project}") was left by a run that is no longer alive (${holder}); claimed it."
        elif ! mv "${aside}" "${lock}" 2>/dev/null; then
            echo "Warning: a live create lock was moved aside by mistake and could not be put back: ${aside}" >&2
        fi
    fi
    return 0
}

# Answers 0 when there is a project to build, and REFUSES with its own message
# otherwise. Takes the repository root, the project path and the generator, all
# from the caller, so nothing here re-derives a path a caller already knows (L70).
#
# Seams, for the suite: OVATION_PROJECT_CREATE_POLL, how often a waiting run looks
# again, and OVATION_PROJECT_CREATE_TIMEOUT, how long it waits on a live holder.
# Both are injectable from the day they were written, because a delay that is not
# makes every test that crosses it wait for real (L524).
ensure_xcode_project() {
    local repo_root="$1" project="$2" generator="$3"
    local lock poll timeout started elapsed holder announced=""
    lock="$(xcode_project_create_lock "${project}")"
    poll="${OVATION_PROJECT_CREATE_POLL:-0.2}"
    timeout="${OVATION_PROJECT_CREATE_TIMEOUT:-300}"
    started="$(date +%s)"

    while :; do
        # A CREATE IN PROGRESS IS ASKED ABOUT BEFORE THE PROJECT IS. The project
        # directory appears while xcodegen is still writing into it, so its
        # existence is not an answer while somebody holds this lock. A
        # regeneration holds it too (ovation#299), and during one the project has
        # been moved aside.
        if [ -d "${lock}" ]; then
            xcode_project_claim_dead_lock "${lock}" "${project}" && continue
            holder="$(dir_lock_describe "${lock}")"
            if [ -z "${announced}" ]; then
                announced=1
                echo "==> Another run is creating or regenerating ${project} (${holder}); waiting for it rather than generating over it."
            fi
            elapsed=$(( $(date +%s) - started ))
            if [ "${elapsed}" -gt "${timeout}" ]; then
                echo "Error: another run has been creating ${project} for ${elapsed}s" >&2
                echo "       and has not finished: ${lock} is ${holder}." >&2
                echo "       Refusing to wait longer. If nothing is creating it, remove" >&2
                echo "       ${lock} and try again." >&2
                return 2
            fi
            sleep "${poll}"
            continue
        fi

        if xcode_project_present "${project}"; then
            [ -n "${announced}" ] && echo "==> $(basename "${project}") was made by that run; going on with it."
            return 0
        fi

        if [ ! -x "${generator}" ]; then
            echo "Error: there is no Xcode project at ${project} and xcodegen" >&2
            echo "       is not at ${generator}, so one cannot be made." >&2
            echo "       The project is generated from project.yml rather than committed." >&2
            echo "       Install it with: brew install xcodegen" >&2
            return 2
        fi

        # Lost the race for it: somebody else is creating, so go round and wait.
        dir_lock_take "${lock}" "$(basename "${repo_root}") create" "$$" || continue

        # Asked again UNDER the lock, because a run can have finished between the
        # look above and the take.
        if xcode_project_present "${project}"; then
            rm -rf "${lock}" 2>/dev/null || true
            return 0
        fi

        if ! ( cd "${repo_root}" && "${generator}" generate ); then
            rm -rf "${lock}" 2>/dev/null || true
            echo "Error: xcodegen could not generate ${project} from project.yml." >&2
            return 2
        fi
        # Released on every path out of the create, a failed one included, or every
        # later run on this tree would wait on a create that is not happening.
        rm -rf "${lock}" 2>/dev/null || true

        # A GENERATOR THAT EXITS 0 AND WRITES NOTHING is the shape this exists for:
        # without it the next line is xcodebuild's own error about a missing project,
        # one step further from the cause (L100, L184).
        if ! xcode_project_present "${project}"; then
            echo "Error: xcodegen reported success and ${project} is still not there." >&2
            return 2
        fi

        echo "==> Generated $(basename "${project}") from project.yml, which was absent."
        return 0
    done
}

# Makes sure there is a project, then registers the caller as reading it
# (ovation#299). Takes what ensure_xcode_project takes, plus the words that name
# the reader and its pid, which together are the owner line a refusal quotes.
# Answers 0 registered, and otherwise ensure_xcode_project's own refusal, or 2.
#
# A REGISTRATION THAT CANNOT BE WRITTEN IS A REFUSAL, not a build that goes on
# unseen. A regeneration would then find nobody reading, which is the one answer
# that must not be wrong (L42, L98). It is tried three times first, because the
# last reader leaving removes the empty folder and can do so between a mkdir and
# a write here.
xcode_project_read_begin() {
    local repo_root="$1" project="$2" generator="$3" who="$4" pid="$5"
    local readers lock attempt status
    readers="$(xcode_project_readers "${project}")"
    lock="$(xcode_project_create_lock "${project}")"
    while :; do
        ensure_xcode_project "${repo_root}" "${project}" "${generator}"
        status=$?
        [ "${status}" -eq 0 ] || return "${status}"
        attempt=0
        until mkdir -p "${readers}" 2>/dev/null \
            && printf '%s:%s\n' "${who}" "${pid}" > "${readers}/${pid}" 2>/dev/null; do
            attempt=$((attempt + 1))
            if [ "${attempt}" -ge 3 ]; then
                echo "Error: could not register this run as reading ${project}" >&2
                echo "       at ${readers}, so a regeneration could not see it." >&2
                echo "       Refusing to build from a project that could be rewritten under it." >&2
                return 2
            fi
        done
        # REGISTERED, THEN ASKED. A regeneration that took the lock between the
        # look inside ensure_xcode_project and the write above has not seen this
        # registration, so this run steps back and waits for it.
        [ -d "${lock}" ] || return 0
        rm -f "${readers}/${pid}" 2>/dev/null || true
    done
}

# Removes the caller's registration, and the folder when it was the last one.
xcode_project_read_end() {
    local readers
    readers="$(xcode_project_readers "$1")"
    rm -f "${readers}/$2" 2>/dev/null || true
    rmdir "${readers}" 2>/dev/null || true
}

# Prints the owner line of every LIVE run reading the project, one per line, and
# answers 0 when there is at least one. A registration whose pid is no longer
# running is removed, because a run killed with -9 runs no trap and a dead pid is
# not reading anything (L409). One that names no pid is counted as live: a holder
# this cannot judge is not a holder it may wave through (L42).
xcode_project_live_readers() {
    local readers entry owner pid found=1
    readers="$(xcode_project_readers "$1")"
    [ -d "${readers}" ] || return 1
    for entry in "${readers}"/*; do
        [ -f "${entry}" ] || continue
        owner="$(head -1 "${entry}" 2>/dev/null)"
        pid="${owner##*:}"
        case "${pid}" in
            ''|*[!0-9]*) pid="" ;;
        esac
        if [ -n "${pid}" ] && ! ps -p "${pid}" >/dev/null 2>&1; then
            rm -f "${entry}" 2>/dev/null || true
            continue
        fi
        printf '%s\n' "${owner:-a run that left no owner line}"
        found=0
    done
    return "${found}"
}
