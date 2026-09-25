#!/bin/bash
# Ported-From: danwright32/downbeat scripts/test-lock-queue.sh @ 3c30b3f17c6c89841d09a70a7a6b5fa40b5144a3
#
# Tests the arrival order queue in lib/lock-queue.sh (downbeat#524).
#
# The same cases as Downbeat's suite for its copy, because the two copies must
# agree in behaviour and a case one side has and the other lacks is where they
# would drift apart unseen.
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
harness_begin "lock queue tests" 19

TARGET="scripts/lib/lock-queue.sh"
require_target "$TARGET"
# shellcheck source=lib/lock-queue.sh
. "./$TARGET"

harness_temp_dir WORK
SLEEPERS=""
harness_on_exit 'for pid in $SLEEPERS; do kill "$pid" 2>/dev/null; done'
LOCK="$WORK/lock"

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

harness_end
