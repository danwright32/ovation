#!/bin/bash
# Ported-From: danwright32/downbeat scripts/lock-queue.sh @ 3c30b3f17c6c89841d09a70a7a6b5fa40b5144a3
# Ported-From: danwright32/overture mac/scripts/lib/lock-queue.sh @ 0e7818a619a5fd585959344a3cba52e6e0f8c6a6
#
# Arrival order for the machine wide test lock (downbeat#524). Sourced, never run.
#
# THIS MUST STAY IDENTICAL IN BEHAVIOUR TO DOWNBEAT'S scripts/lock-queue.sh, which
# is where the protocol was written, and to Overture's copy. Three runners read
# one queue, and a runner that reads it differently is a runner that barges. A
# change here is a change to the protocol, so it is made in all three or in none.
#
# WHY IT EXISTS. The lock is `mkdir` on /tmp/xcodebuild-tests.lock, which
# Downbeat, Overture and Ovation all take, and `mkdir` is the ONLY thing that
# keeps two suites apart. That part is unchanged. What it never gave was
# fairness: every waiter retried on its own timer and whichever retried first
# after a release won, so on 2026-09-24 a one minute Downbeat run waited 15 to 20
# minutes three times while newer Overture runs kept taking the lock, and a push
# failed on its 1800 second deadline having run nothing.
#
# THE PROTOCOL, followed exactly:
#
#   The queue is the directory "<lock dir>.queue", beside the lock, derived from
#   the lock's own path so a test pointing a runner at a throwaway lock (here,
#   OVATION_DIR_LOCK) gets a throwaway queue with it.
#
#   A waiter joins by writing one ticket file named "<arrival>.<pid>", where
#   <arrival> is seconds since the epoch with six decimals, zero padded to a fixed
#   width so that a plain byte sort is arrival order. The file holds the pid, a
#   space, and that process's start time as `ps -o lstart=` prints it. It is
#   written under a dot name and renamed into place, so no reader ever sees half
#   a ticket.
#
#   A waiter may try `mkdir` on the lock only while no LIVE ticket sorts before its
#   own. A ticket is dead when its pid is gone, or when the pid is alive but its
#   start time differs, which is a crashed waiter whose number was reused and would
#   otherwise block the queue until every waiter behind it timed out. Anything
#   unreadable counts as alive. An older ticket carrying the waiter's OWN pid is
#   its own leftover and never counts. Any waiter may delete a dead ticket.
#
#   A waiter leaves the queue the moment it holds the lock, and on every exit.
#
# PRIORITY (ovation#598), ported from Overture #4244, an EXTENSION Overture's copy
# and this one have and Downbeat's does not yet (downbeat#527). A run verifying a
# merge joins with the class "priority", and its ticket is named
# "<arrival>.priority.<pid>": the same arrival first, the same pid last, the same
# content. A reader that knows the class serves tickets in two lanes, priority
# first and each lane in arrival order, and a routine ticket that has waited
# LOCK_QUEUE_PRIORITY_BOUND_SECONDS (600) is promoted into the priority lane at its
# own arrival, so a stream of merges delays a routine run by at most the bound and
# never starves it (L1012). Nothing about the HOLDER changes: a priority waiter
# still tries `mkdir` only when nothing is ahead of it, and `mkdir` still admits
# one run at a time.
#
# Why a reader that does NOT know the class is never worse off, measured in
# test-lock-queue.sh against a verbatim copy of the reader this file had before:
# it takes the pid from after the LAST dot, so it reads the right pid; the content
# is the one it has always judged liveness by, so it never clears a live priority
# ticket as dead; and the arrival still leads the name, so its byte sort is still
# arrival order and it counts a priority ticket exactly where an ordinary one would
# sit. The only difference it can meet is a later priority waiter that does not
# wait for it, and then the two race on `mkdir`, as every runner did before the
# queue, until the bound puts the older one first.
#
# Mixing is safe in both directions. A runner that knows nothing of the queue still
# excludes everybody through `mkdir`; it only competes unfairly, which is what every
# runner did before this. So the three repositories can adopt this in any order.
#
# WHO IN OVATION TAKES IT: run-tests.sh, around the hosted suite, and
# regenerate-xcode-project.sh, which tries once and refuses rather than waiting.
# Neither is ever queued while it calls the other: the runner's narrowed
# regeneration happens before it joins (test-run-tests.sh case 524c).

LOCK_QUEUE_DIR=""
LOCK_QUEUE_TICKET=""
LOCK_QUEUE_AHEAD=0
# Of those ahead, how many arrived AFTER this waiter and go first by class, so a
# runner can say it is waiting for a later merge verification, not an earlier run.
LOCK_QUEUE_AHEAD_LATER=0
LOCK_QUEUE_CLASS=""
# How long a routine ticket waits before it is served in plain arrival order again.
# A caller may set it before sourcing; a value that is not a whole number falls
# back to the default where it is read.
: "${LOCK_QUEUE_PRIORITY_BOUND_SECONDS:=600}"

# The start time of a process, or nothing when it is gone.
lock_queue_started() {
    ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'
}

# Joins the queue beside lock dir $1 as process $2, in class $3: nothing for a
# routine run, or "priority" for a merge verification. Anything else is refused
# rather than read as either, so a misspelling cannot jump the queue. Returns non
# zero when the queue cannot be written, and the caller then waits the old way
# rather than not at all.
lock_queue_join() {
    local lock_dir="$1" pid="$2" class="${3:-}" infix arrival started tmp
    LOCK_QUEUE_DIR="${lock_dir}.queue"
    LOCK_QUEUE_TICKET=""
    case "$class" in
        "") infix="" ;;
        priority) infix=".priority" ;;
        *) return 1 ;;
    esac
    LOCK_QUEUE_CLASS="$class"
    mkdir -p "$LOCK_QUEUE_DIR" 2>/dev/null || return 1
    arrival=$(perl -MTime::HiRes=time -e 'printf "%017.6f", time' 2>/dev/null) || return 1
    [ -n "$arrival" ] || return 1
    started=$(lock_queue_started "$pid")
    [ -n "$started" ] || return 1
    tmp="$LOCK_QUEUE_DIR/.joining.$pid"
    printf '%s %s\n' "$pid" "$started" > "$tmp" 2>/dev/null || return 1
    mv "$tmp" "$LOCK_QUEUE_DIR/$arrival$infix.$pid" 2>/dev/null || { rm -f "$tmp"; return 1; }
    LOCK_QUEUE_TICKET="$arrival$infix.$pid"
}

# Whether ticket file $1 belongs to a process that is DEMONSTRABLY gone.
lock_queue_ticket_is_dead() {
    local line pid recorded now
    line=$(cat "$1" 2>/dev/null) || return 1
    pid="${line%% *}"
    case "$pid" in
        '' | *[!0-9]*) return 1 ;;
    esac
    recorded="${line#* }"
    kill -0 "$pid" 2>/dev/null || return 0
    now=$(lock_queue_started "$pid")
    [ -n "$now" ] || return 1
    [ "$now" = "$recorded" ] && return 1
    return 0
}

# Whether ticket name $1 is served in the first lane: a priority ticket, or a
# routine one that arrived at least the bound before now ($2). With no clock ($2
# empty) every ticket is in the first lane, which is plain arrival order, the
# behaviour before the class existed.
lock_queue_first_lane() {
    local name="$1" now="$2" bound="$LOCK_QUEUE_PRIORITY_BOUND_SECONDS" arrival
    [[ "$name" =~ ^[0-9]+\.[0-9]+\.priority\.[0-9]+$ ]] && return 0
    [ -n "$now" ] || return 0
    [[ "$bound" =~ ^[0-9]+$ ]] || bound=600
    arrival="${name%%.*}"
    # A name this cannot date is left in the routine lane: it is not ours to promote.
    [[ "$arrival" =~ ^[0-9]+$ ]] || return 1
    [ $(( now - 10#$arrival )) -ge "$bound" ]
}

# How many live tickets are ahead of this one, clearing dead ones on the way, set
# in LOCK_QUEUE_AHEAD, with LOCK_QUEUE_AHEAD_LATER of them arrivals after this one
# that go first by class. Not queued at all is 0, so a caller whose join failed
# behaves exactly as it did before the queue existed.
#
# AHEAD is: in the first lane while this ticket is not, or in the same lane and
# earlier. With every ticket routine and young that is exactly the arrival order
# it always was. So the scan no longer stops at this ticket: a priority ticket
# behind it in the sort can still be ahead of it.
#
# A VARIABLE and not printed, deliberately. Printing invites `$(lock_queue_ahead)`,
# which runs in a subshell, so a rejoin below would write a ticket the caller never
# learns about, and the caller would then wait behind its own orphan until it timed
# out. That was caught by Downbeat's own test of this file.
lock_queue_ahead() {
    LOCK_QUEUE_AHEAD=0
    LOCK_QUEUE_AHEAD_LATER=0
    [ -n "$LOCK_QUEUE_TICKET" ] || return 0
    local ticket seen=0 mine="${LOCK_QUEUE_TICKET##*.}" now mine_first=0 theirs_first
    now=$(date +%s 2>/dev/null) || now=""
    [[ "$now" =~ ^[0-9]+$ ]] || now=""
    lock_queue_first_lane "$LOCK_QUEUE_TICKET" "$now" && mine_first=1
    for ticket in $(ls "$LOCK_QUEUE_DIR" 2>/dev/null | LC_ALL=C sort); do
        if [ "$ticket" = "$LOCK_QUEUE_TICKET" ]; then
            seen=1
            continue
        fi
        # An older ticket carrying our own pid is a leftover of ours, and waiting
        # behind it would be waiting behind ourselves. A later one cannot be ours
        # to wait for either.
        if [ "${ticket##*.}" = "$mine" ]; then
            [ "$seen" -eq 1 ] || rm -f "$LOCK_QUEUE_DIR/$ticket"
            continue
        fi
        theirs_first=0
        lock_queue_first_lane "$ticket" "$now" && theirs_first=1
        if [ "$theirs_first" -eq "$mine_first" ]; then
            # Same lane: only an earlier arrival is ahead.
            [ "$seen" -eq 0 ] || continue
        elif [ "$theirs_first" -eq 0 ]; then
            # A routine ticket never goes ahead of one in the first lane, whenever
            # it arrived.
            continue
        fi
        if lock_queue_ticket_is_dead "$LOCK_QUEUE_DIR/$ticket"; then
            rm -f "$LOCK_QUEUE_DIR/$ticket"
            continue
        fi
        LOCK_QUEUE_AHEAD=$((LOCK_QUEUE_AHEAD + 1))
        [ "$seen" -eq 0 ] || LOCK_QUEUE_AHEAD_LATER=$((LOCK_QUEUE_AHEAD_LATER + 1))
    done
    # Our own ticket is gone, which only happens when something emptied the queue
    # from outside. Waiting on as though still queued would wait for ever behind
    # nobody, so rejoin at the back, in the same class, and wait one more round;
    # the next call counts from the new ticket, and a failed rejoin leaves this
    # caller unqueued.
    if [ "$seen" -eq 0 ]; then
        lock_queue_join "${LOCK_QUEUE_DIR%.queue}" "$mine" "$LOCK_QUEUE_CLASS" || LOCK_QUEUE_TICKET=""
        LOCK_QUEUE_AHEAD=1
        LOCK_QUEUE_AHEAD_LATER=0
    fi
    return 0
}

lock_queue_leave() {
    [ -n "$LOCK_QUEUE_TICKET" ] && rm -f "$LOCK_QUEUE_DIR/$LOCK_QUEUE_TICKET"
    LOCK_QUEUE_TICKET=""
}
