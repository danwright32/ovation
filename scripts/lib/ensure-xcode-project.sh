# ovation#151. Make the Xcode project when there is none, and only then.
#
# `Ovation.xcodeproj` is generated from project.yml by xcodegen and is gitignored,
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
# Sourced, so it can read and be read by the caller's own seams.

# shellcheck source=dir-lock.sh
. "$(dirname "${BASH_SOURCE[0]}")/dir-lock.sh"

# The create lock for a project, derived from its path so that two trees never
# share one and one tree always does. In /tmp beside the build locks rather than
# in the tree, so a lock a dead run leaves behind is not a stray directory for
# every tree walking guard to find.
xcode_project_create_lock() {
    printf '/tmp/ovation-project-create-%s.lock' \
        "$(printf '%s' "$1" | cksum | awk '{ print $1 }')"
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
    local lock poll timeout started elapsed owner pid holder announced=""
    lock="$(xcode_project_create_lock "${project}")"
    poll="${OVATION_PROJECT_CREATE_POLL:-0.2}"
    timeout="${OVATION_PROJECT_CREATE_TIMEOUT:-300}"
    started="$(date +%s)"

    while :; do
        # A CREATE IN PROGRESS IS ASKED ABOUT BEFORE THE PROJECT IS. The project
        # directory appears while xcodegen is still writing into it, so its
        # existence is not an answer while somebody holds this lock.
        if [ -d "${lock}" ]; then
            holder="$(dir_lock_describe "${lock}")"
            owner="$(head -1 "${lock}/owner" 2>/dev/null)"
            pid="${owner##*:}"
            case "${pid}" in
                ''|*[!0-9]*) pid="" ;;
            esac
            if [ -n "${pid}" ] && ! ps -p "${pid}" >/dev/null 2>&1; then
                # CLAIMED BY MOVING IT ASIDE, and only if what was moved is still
                # the dead run's. Two waiters can both find the same dead holder;
                # a plain delete by the slower one would remove the lock the faster
                # one has just taken. Moving and then reading what was moved means
                # a fresh lock caught by mistake is put straight back. The window
                # that survives is a third run taking the lock in between, and it
                # is said rather than hidden.
                local aside="${lock}.stale.$$"
                if mv "${lock}" "${aside}" 2>/dev/null; then
                    if [ "$(head -1 "${aside}/owner" 2>/dev/null)" = "${owner}" ]; then
                        rm -rf "${aside}"
                        echo "==> A create lock for $(basename "${project}") was left by a run that is no longer alive (${holder}); claimed it."
                    elif ! mv "${aside}" "${lock}" 2>/dev/null; then
                        echo "Warning: a live create lock was moved aside by mistake and could not be put back: ${aside}" >&2
                    fi
                fi
                continue
            fi
            if [ -z "${announced}" ]; then
                announced=1
                echo "==> Another run is creating ${project} (${holder}); waiting for it rather than generating over it."
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

        if [ -d "${project}" ]; then
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
        if [ -d "${project}" ]; then
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
        if [ ! -d "${project}" ]; then
            echo "Error: xcodegen reported success and ${project} is still not there." >&2
            return 2
        fi

        echo "==> Generated $(basename "${project}") from project.yml, which was absent."
        return 0
    done
}
