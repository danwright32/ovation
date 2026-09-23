# ovation#433. Describing who holds the file lock the runner waits on.
#
# WHY THIS IS A LIBRARY AND NOT FOUR LINES IN THE RUNNER. It was four lines in
# the runner, and the rule it has to keep cannot be stated in them.
#
# `flock` takes its lock on a file DESCRIPTOR, and a descriptor is inherited by
# every process started while it is held (L441). So `lsof -t` answers with the
# holder AND all of its children, and a holder that starts short lived children,
# which is what a real Overture test run does the whole time it holds the lock,
# answers differently on almost every poll.
#
# MEASURED, 2026-09-22, on this Mac: a holder running `sleep 0.05` in a loop
# answered with three pids, the flock, its bash, and a sleep that had already
# exited by the next call a moment later.
#
# The runner counts a CHANGE in these words as a change of holder, so one holder
# read as several, which is what made `test-run-tests.sh` case 236b go red on CI
# and green on a re-run of the same commit. A suite that goes red for reasons
# unrelated to the change is one people stop reading (L293, L538).
#
# THE IDENTITY OF A HOLDER IS THE PROCESS THAT TOOK THE LOCK, and among a set of
# processes sharing one inherited descriptor that is the one whose parent is not
# also in the set. Every other member holds it because that one does.
#
# A PID WHOSE PARENT CANNOT BE READ HAS GONE, and is dropped rather than counted.
# It is the case `lsof` produces by itself: the set is gathered, and a short
# lived child in it has exited before its parent can be asked for. Counting it
# would put back exactly the flicker this exists to remove.
#
# NO lsof IS ITS OWN ANSWER, never "free". The Linux job has none, and a lock
# reported free when it is held is the one answer that matters being
# indistinguishable from the safe one (L98).

# The parent of a pid, or nothing where it can no longer be asked.
file_lock_parent_of() {
    ps -o ppid= -p "$1" 2>/dev/null | tr -d ' '
}

# Every pid holding this file open, reduced to the ones that TOOK it.
file_lock_holders() {
    local lock="$1" pid parent pids=""
    [ -x /usr/sbin/lsof ] || return 0
    # SEPARATED BY SPACES, because the membership test below asks whether a
    # parent is IN this list and does that by looking for it surrounded by
    # spaces. `lsof -t` answers one pid per line, and against newlines that test
    # never matches anything: every pid read as its own holder and the count was
    # exactly what it was before the fix. Caught by the case, not by review.
    pids="$(/usr/sbin/lsof -t "${lock}" 2>/dev/null | tr '\n' ' ')"
    [ -n "${pids# }" ] || return 0
    for pid in ${pids}; do
        parent="$(file_lock_parent_of "${pid}")"
        # Gone between the listing and this question: not a holder to name.
        [ -n "${parent}" ] || continue
        # Holds it because its parent does: not a holder of its own.
        case " ${pids} " in *" ${parent} "*) continue ;; esac
        printf '%s\n' "${pid}"
    done
}

# What the runner says about the holder, in one sentence.
file_lock_describe() {
    local lock="$1" pid desc=""
    for pid in $(file_lock_holders "${lock}"); do
        desc="${desc}${pid} ($(ps -o comm= -p "${pid}" 2>/dev/null | sed 's|.*/||')) "
    done
    if [ -z "${desc}" ]; then
        printf 'free, or held by a process this run cannot see'
        return
    fi
    printf 'held by pid %s' "${desc% }"
}
