#!/bin/bash
# Ported-From: danwright32/downbeat scripts/test-lock-queue.sh @ 3c30b3f17c6c89841d09a70a7a6b5fa40b5144a3
# Ported-From: danwright32/overture mac/scripts/lib/lock-queue.test.sh @ 0e7818a619a5fd585959344a3cba52e6e0f8c6a6
#
# Tests the arrival order queue in lib/lock-queue.sh (downbeat#524).
#
# The same cases as Downbeat's suite for its copy, and since ovation#598 the
# priority cases of Overture's, because the copies must agree in behaviour, and
# a case one side has and the other lacks is where they would drift apart unseen.
#
# Each case holds real processes (a `sleep`) as the waiters, because the queue's
# whole judgement is about whether a process is alive and is still the same
# process, and a stubbed liveness check would test the stub.
#
# NOTHING HERE TOUCHES /tmp/xcodebuild-tests.lock OR ITS QUEUE. Every lock path is
# under the harness's own temp directory, and the queue is derived from it (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "lock queue tests" 51

TARGET="scripts/lib/lock-queue.sh"
require_target "$TARGET"
# shellcheck source=lib/lock-queue.sh
. "./$TARGET"

harness_temp_dir WORK
SLEEPERS=""
harness_on_exit 'for pid in $SLEEPERS; do kill "$pid" 2>/dev/null; done'
# A SPACE in the path, as Overture's fixture has: the queue directory is derived
# from the lock's path, and an unquoted expansion anywhere in the derivation would
# split it.
mkdir -p "$WORK/shared lock"
LOCK="$WORK/shared lock/xcodebuild-tests.lock"

# A live waiter: a process that stays alive until this file ends.
waiter() {
    sleep 60 &
    WAITER_PID=$!
    SLEEPERS="$SLEEPERS $WAITER_PID"
    disown "$WAITER_PID" 2>/dev/null
}

# Joins as process $1 and prints the ticket. Printing is safe HERE only because
# nothing below reads the queue from inside the same subshell.
join_as() {
    lock_queue_join "$LOCK" "$1" || { echo "JOIN-FAILED"; return; }
    echo "$LOCK_QUEUE_TICKET"
}
gone_or_there() { [ -e "$1" ] && echo there || echo gone; }

# ---------------------------------------------------------------- arrival order

waiter; A=$WAITER_PID
waiter; B=$WAITER_PID
waiter; C=$WAITER_PID
TA=$(join_as "$A"); TB=$(join_as "$B"); TC=$(join_as "$C")

ahead_of() { LOCK_QUEUE_DIR="$LOCK.queue"; LOCK_QUEUE_TICKET="$1"; lock_queue_ahead; echo "$LOCK_QUEUE_AHEAD"; }

check "the first to arrive has nobody ahead"      "$(ahead_of "$TA")" "0"
check "the second has one ahead"                  "$(ahead_of "$TB")" "1"
check "the third has two ahead"                   "$(ahead_of "$TC")" "2"

# The ticket names alone must sort into arrival order, since that is all a reader
# in another repository has to go on.
ORDER=$(ls "$LOCK.queue" | LC_ALL=C sort | tr '\n' ' ')
check "tickets sort in arrival order" "$ORDER" "$TA $TB $TC "

# The file content is the other half of the protocol every repository reads: the
# pid, a space, and the process start time exactly as `ps -o lstart=` prints it.
check "a ticket holds its pid and that process's start time" \
    "$(cat "$LOCK.queue/$TA")" "$A $(ps -o lstart= -p "$A" | sed 's/^ *//; s/ *$//')"

# The first leaving moves everybody up.
LOCK_QUEUE_DIR="$LOCK.queue"; LOCK_QUEUE_TICKET="$TA"; lock_queue_leave
check "leaving removes the ticket"                "$(gone_or_there "$LOCK.queue/$TA")" "gone"
check "after the first leaves, the second is next" "$(ahead_of "$TB")" "0"
check "and the third has one ahead"               "$(ahead_of "$TC")" "1"
rm -rf "$LOCK.queue"

# ---------------------------------------------------------------- dead waiters

# A waiter that died without leaving must not hold up the queue for ever.
waiter; LIVE=$WAITER_PID
sleep 60 & DOOMED=$!
TD=$(join_as "$DOOMED")
TL=$(join_as "$LIVE")
kill "$DOOMED"; wait "$DOOMED" 2>/dev/null
check "a dead waiter ahead does not count"        "$(ahead_of "$TL")" "0"
check "and its ticket is cleared"                 "$(gone_or_there "$LOCK.queue/$TD")" "gone"
rm -rf "$LOCK.queue"

# A crashed waiter whose pid now belongs to something else. Its ticket records a
# start time the live process does not have, so it is dead all the same.
waiter; REUSED=$WAITER_PID
waiter; BEHIND=$WAITER_PID
TR=$(join_as "$REUSED")
TBH=$(join_as "$BEHIND")
printf '%s %s\n' "$REUSED" "Thu Jan  1 00:00:00 1970" > "$LOCK.queue/$TR"
check "a reused pid does not count as the waiter" "$(ahead_of "$TBH")" "0"
rm -rf "$LOCK.queue"

# But a ticket that cannot be read is alive, as an unreadable lock owner is: the
# only thing that writes one is a waiter mid join.
waiter; LATE=$WAITER_PID
TLATE=$(join_as "$LATE")
: > "$LOCK.queue/00000000000.000001.1"
check "an unreadable ticket ahead still counts"   "$(ahead_of "$TLATE")" "1"
rm -rf "$LOCK.queue"

# An older ticket of our OWN, left by an earlier join of this process, never
# counts: waiting behind it would be waiting behind ourselves.
waiter; SELF=$WAITER_PID
LOCK_QUEUE_TICKET=""; lock_queue_join "$LOCK" "$SELF"; STALE_SELF="$LOCK_QUEUE_TICKET"
lock_queue_join "$LOCK" "$SELF"
lock_queue_ahead
check "our own older ticket does not count"       "$LOCK_QUEUE_AHEAD" "0"
check "and it is cleared"                         "$(gone_or_there "$LOCK.queue/$STALE_SELF")" "gone"
lock_queue_leave
rm -rf "$LOCK.queue"

# ---------------------------------------------------------------- the edges

# Our own ticket vanishing (somebody emptied the queue) rejoins rather than waiting
# behind nobody for ever, and asks for one more round. Called directly, never
# through `$(...)`, which is the whole of why the count is a variable.
waiter; LOST=$WAITER_PID
LOCK_QUEUE_TICKET=""; lock_queue_join "$LOCK" "$LOST"
OLD_TICKET="$LOCK_QUEUE_TICKET"
rm -f "$LOCK.queue/$OLD_TICKET"
lock_queue_ahead
check "a lost ticket waits one more round"        "$LOCK_QUEUE_AHEAD" "1"
check "and is back in the queue, once"            "$(ls "$LOCK.queue" | wc -l | tr -d ' ')" "1"
lock_queue_ahead
check "and next round is at the front"            "$LOCK_QUEUE_AHEAD" "0"
lock_queue_leave
rm -rf "$LOCK.queue"

# A caller whose join failed is not queued, and waits exactly as before the queue.
LOCK_QUEUE_TICKET=""
lock_queue_ahead
check "unqueued has nobody ahead"                 "$LOCK_QUEUE_AHEAD" "0"
check "joining a queue that cannot be written fails" \
    "$(lock_queue_join "/nonexistent-root-$$/lock" "$$" && echo joined || echo refused)" "refused"
LOCK_QUEUE_TICKET=""

# A process that is gone cannot join, since it has no start time to record.
bash -c 'exit 0' & GONE=$!; wait "$GONE"
check "a dead pid cannot join" \
    "$(lock_queue_join "$LOCK" "$GONE" && echo joined || echo refused)" "refused"

# ---------------------------------------------------------------- merge verification goes first (ovation#598)
#
# Overture #4244's PRIORITY class, ported case for case from Overture's
# mac/scripts/lib/lock-queue.test.sh. A run verifying a merge joins as a priority
# waiter and goes ahead of routine runs that arrived before it. It never goes ahead
# of the HOLDER: `mkdir` is still the only exclusion, and a runner tries it only
# once this says nothing is ahead.

# Now, in whole seconds, and a ticket name for an arrival that many seconds ago,
# as a hand written ticket needs one. The arrival is the only thing the anti
# starvation bound reads.
now_seconds() { date +%s; }
ticket_at() { printf '%010d.000000%s.%s' "$(( $(now_seconds) - $1 ))" "$2" "$3"; }
# Writes a ticket by hand for live process $1, arrived $2 seconds ago, with name
# infix $3 ("" or ".priority"), in the format every repository writes, and prints
# its name.
hand_ticket() {
    local name
    name="$(ticket_at "$2" "$3" "$1")"
    mkdir -p "$LOCK.queue"
    printf '%s %s\n' "$1" "$(ps -o lstart= -p "$1" | sed 's/^ *//; s/ *$//')" > "$LOCK.queue/$name"
    echo "$name"
}

# THE READER BEFORE THE CLASS, verbatim from this file as it stood before
# ovation#598 and from Downbeat's, which is the same, renamed so it can sit beside
# the new one. Its one change is the rejoin on a lost ticket, left out because no
# case here loses one. It is what a Downbeat run still does, so every
# compatibility claim below is made against it rather than a description of it.
old_reader_ahead() {
    LOCK_QUEUE_AHEAD=0
    [ -n "$LOCK_QUEUE_TICKET" ] || return 0
    local ticket seen=0 mine="${LOCK_QUEUE_TICKET##*.}"
    for ticket in $(ls "$LOCK_QUEUE_DIR" 2>/dev/null | LC_ALL=C sort); do
        if [ "$ticket" = "$LOCK_QUEUE_TICKET" ]; then
            seen=1
            break
        fi
        if [ "${ticket##*.}" = "$mine" ] || lock_queue_ticket_is_dead "$LOCK_QUEUE_DIR/$ticket"; then
            rm -f "$LOCK_QUEUE_DIR/$ticket"
            continue
        fi
        LOCK_QUEUE_AHEAD=$((LOCK_QUEUE_AHEAD + 1))
    done
    if [ "$seen" -eq 0 ]; then
        LOCK_QUEUE_TICKET=""
        LOCK_QUEUE_AHEAD=1
    fi
}
old_ahead_of() { LOCK_QUEUE_DIR="$LOCK.queue"; LOCK_QUEUE_TICKET="$1"; old_reader_ahead; echo "$LOCK_QUEUE_AHEAD"; }
# How many of those ahead arrived LATER, which is how a runner can say it is
# waiting for a later merge verification rather than an earlier run.
later_of() { LOCK_QUEUE_DIR="$LOCK.queue"; LOCK_QUEUE_TICKET="$1"; lock_queue_ahead; echo "$LOCK_QUEUE_AHEAD_LATER"; }

join_priority_as() {
    lock_queue_join "$LOCK" "$1" priority || { echo "JOIN-FAILED"; return; }
    echo "$LOCK_QUEUE_TICKET"
}

waiter; OA=$WAITER_PID
waiter; OB=$WAITER_PID
waiter; PM=$WAITER_PID
TOA=$(join_as "$OA"); TOB=$(join_as "$OB"); TPM=$(join_priority_as "$PM")

check "a priority ticket is named arrival, .priority, pid" \
    "$([[ "$TPM" =~ ^[0-9]+\.[0-9]+\.priority\.${PM}$ ]] && echo yes || echo no)" "yes"
check "and holds exactly what an ordinary ticket holds, so an old reader judges it alive" \
    "$(cat "$LOCK.queue/$TPM" 2>/dev/null)" "$PM $(ps -o lstart= -p "$PM" | sed 's/^ *//; s/ *$//')"
check "an ordinary join is still named arrival, pid" \
    "$([[ "$TOA" =~ ^[0-9]+\.[0-9]+\.${OA}$ ]] && echo yes || echo no)" "yes"

check "a merge verification arriving after two routine runs has nobody ahead" "$(ahead_of "$TPM")" "0"
check "the first routine run now waits for it" "$(ahead_of "$TOA")" "1"
check "and the second waits for it and the first" "$(ahead_of "$TOB")" "2"
check "and the first says the one it waits for arrived later" "$(later_of "$TOA")" "1"
check "while the merge verification has no later arrival ahead" "$(later_of "$TPM")" "0"

# The old reader, over the SAME queue: it reads the priority ticket as an
# ordinary one in arrival order.
check "an old reader at the front still sees nobody ahead, as today" "$(old_ahead_of "$TOA")" "0"
check "an old reader second still sees one ahead, as today" "$(old_ahead_of "$TOB")" "1"
check "an old reader counts the priority waiter as an ordinary later arrival, not dead" \
    "$(gone_or_there "$LOCK.queue/$TPM")" "there"
rm -rf "$LOCK.queue"

# Arriving BEFORE an old reader, a priority ticket is simply an earlier ticket to it.
waiter; PE=$WAITER_PID
waiter; OL=$WAITER_PID
TPE=$(join_priority_as "$PE"); TOL=$(join_as "$OL")
check "an old reader behind an earlier priority ticket counts it once" "$(old_ahead_of "$TOL")" "1"
check "and so does a new one" "$(ahead_of "$TOL")" "1"
check "and the priority ticket survives both readings" "$(gone_or_there "$LOCK.queue/$TPE")" "there"
rm -rf "$LOCK.queue"

# Two merge verifications go in the order they arrived.
waiter; P1=$WAITER_PID
waiter; P2=$WAITER_PID
waiter; O3=$WAITER_PID
TO3=$(join_as "$O3"); TP1=$(join_priority_as "$P1"); TP2=$(join_priority_as "$P2")
check "the earlier merge verification is first" "$(ahead_of "$TP1")" "0"
check "the later one waits for the earlier one only" "$(ahead_of "$TP2")" "1"
check "the routine run waits for both" "$(ahead_of "$TO3")" "2"
rm -rf "$LOCK.queue"

# A dead priority waiter is skipped and cleared like a dead ordinary one, from
# EITHER side of the reader's own ticket, since a priority ticket counts from
# behind it.
waiter; OD=$WAITER_PID
sleep 60 & PDOOMED=$!
TOD=$(join_as "$OD")
TPD=$(join_priority_as "$PDOOMED")
kill "$PDOOMED"; wait "$PDOOMED" 2>/dev/null
check "a dead merge verification does not hold up a routine run" "$(ahead_of "$TOD")" "0"
check "and its ticket is cleared" "$(gone_or_there "$LOCK.queue/$TPD")" "gone"
rm -rf "$LOCK.queue"

# THE ANTI STARVATION BOUND. A routine run that has waited
# LOCK_QUEUE_PRIORITY_BOUND_SECONDS (600 by default) is served in plain arrival
# order again, ahead of every merge verification that arrived after it, so a
# stream of merges can delay a routine run by at most the bound and never starve
# it (L1012). Written by hand as an old reader would write it, since an old
# reader's ticket is exactly the one this protects.
check "the bound is ten minutes unless set" "${LOCK_QUEUE_PRIORITY_BOUND_SECONDS:-unset}" "600"
waiter; OLD_ENOUGH=$WAITER_PID
waiter; NOT_YET=$WAITER_PID
waiter; PB=$WAITER_PID
TOLD=$(hand_ticket "$OLD_ENOUGH" 605 "")
TNOT=$(hand_ticket "$NOT_YET" 595 "")
TPB=$(join_priority_as "$PB")
check "a merge verification waits for a routine run past the bound, and only that one" \
    "$(ahead_of "$TPB")" "1"
check "the routine run past the bound has nobody ahead" "$(ahead_of "$TOLD")" "0"
check "the one short of the bound waits for it and the merge verification" "$(ahead_of "$TNOT")" "2"
rm -rf "$LOCK.queue"

# The bound is read at each reading rather than fixed, so the same queue reads
# differently under a different bound, which proves the number is the one
# consulted.
waiter; OSHORT=$WAITER_PID
waiter; PSHORT=$WAITER_PID
TOSHORT=$(hand_ticket "$OSHORT" 30 "")
TPSHORT=$(join_priority_as "$PSHORT")
check "under the default bound a routine run 30s old waits for a merge verification" \
    "$(ahead_of "$TOSHORT")" "1"
LOCK_QUEUE_PRIORITY_BOUND_SECONDS=20
check "under a 20s bound the same run has waited long enough" "$(ahead_of "$TOSHORT")" "0"
check "and the merge verification waits for it" "$(ahead_of "$TPSHORT")" "1"
LOCK_QUEUE_PRIORITY_BOUND_SECONDS=600
rm -rf "$LOCK.queue"

# A priority waiter past the bound is still a priority waiter: two of them keep
# arrival order.
waiter; PA1=$WAITER_PID
waiter; PA2=$WAITER_PID
TPA1=$(hand_ticket "$PA1" 900 ".priority")
TPA2=$(join_priority_as "$PA2")
check "an old merge verification is ahead of a new one" "$(ahead_of "$TPA2")" "1"
check "and has nobody ahead" "$(ahead_of "$TPA1")" "0"
rm -rf "$LOCK.queue"

# A lost priority ticket rejoins in its own class, or losing the ticket would
# quietly demote a merge verification behind every routine run.
waiter; PLOST=$WAITER_PID
LOCK_QUEUE_TICKET=""; lock_queue_join "$LOCK" "$PLOST" priority
rm -f "$LOCK.queue/$LOCK_QUEUE_TICKET"
lock_queue_ahead
check "a lost priority ticket rejoins as priority" \
    "$([[ "$LOCK_QUEUE_TICKET" =~ ^[0-9]+\.[0-9]+\.priority\.${PLOST}$ ]] && echo yes || echo no)" "yes"
lock_queue_leave
rm -rf "$LOCK.queue"

# Nothing but the literal word joins as priority, so a typo cannot quietly jump
# the queue.
waiter; TYPO=$WAITER_PID
check "an unknown class is refused" \
    "$(lock_queue_join "$LOCK" "$TYPO" urgent && echo joined || echo refused)" "refused"
check "and writes no ticket" "$(ls "$LOCK.queue" 2>/dev/null | wc -l | tr -d ' ')" "0"
LOCK_QUEUE_TICKET=""
rm -rf "$LOCK.queue"

harness_end
