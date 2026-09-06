#!/bin/bash
# What is actually in the booking handoff queue, read from Ovation's side.
#
# ovation#3 step 4, and the entry criterion for the `Downbeat booking queue
# consumer` milestone. Downbeat writes one `<booking-uuid>.json` per committed
# booking into a directory `BookingRetention` never sweeps. The export file is a
# snapshot of CURRENT state and retention deletes a booking seven days after its
# shoot, so a shoot that came and went while Ovation was closed would otherwise
# never be invoiced, with nothing anywhere reporting it.
#
# AN EMPTY ANSWER IS NOT A GOOD ANSWER. Reporting success on an empty queue is
# indistinguishable from reporting that everything was handled (L98), and
# Downbeat's own CONTRACT.md already says an empty bookings array cannot be told
# apart from the data being lost. So this has three outcomes:
#
#   0  PASS           at least one record is present and every one is readable
#   1  BLOCKED        something is in the queue that Ovation could not invoice
#   2  CANNOT MEASURE there is nothing to read, for a named reason
#
# "The directory has never been created" and "the directory is empty" are
# different sentences, because they need different actions: the first means
# Downbeat has never queued anything from this build, the second means it has and
# something already drained it.
#
# PRIVACY FLOOR. Every record carries the client and venue names that were true
# when the shoot was booked, deliberately, so an unconsumed record still resolves
# correctly months later. None of that is printed. This says counts, versions,
# field names and booking ids, which are opaque. A guard that scans the
# REPOSITORY cannot see what a tool prints, and printed output reaches terminal
# scrollback and transcripts by a route that guard never inspects (L222).
set -uo pipefail

QUEUE="${OVATION_BOOKING_QUEUE:-${HOME}/Library/Application Support/Ovation/booking-queue}"
WANT_VERSION="${OVATION_HANDOFF_VERSION:-3}"

cannot_measure() {
    echo "CANNOT MEASURE: $1"
    [ "${2:-}" = "" ] || echo "    $2"
    echo "    Nothing was verified. This is not a pass."
    exit 2
}

# Reading a JSON file is done by CONVERTING it. `plutil -lint` reports
# "Unexpected character {" on JSON that `plutil -extract` reads without
# complaint, measured 2026-09-06, so the tool named for the job is the wrong one.
readable_json() { plutil -convert xml1 -o /dev/null -- "$1" >/dev/null 2>&1; }
field() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

if [ ! -d "$QUEUE" ]; then
    cannot_measure "the queue directory has never been created" \
        "Downbeat creates it on the first booking it commits, so nothing has been handed over yet"
fi

# The queue holds one file per booking, named for its id. The reconciliation
# ledger deliberately lives BESIDE this directory rather than in it, so nothing
# in here is expected to be anything but a record.
RECORDS=0
PROBLEMS=""
note() { PROBLEMS="${PROBLEMS}    $1"$'\n'; }

shopt -s nullglob dotglob
for f in "$QUEUE"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"

    # Not JSON at all is the finder's litter, not the queue's business. Judged
    # by the extension rather than by a list of names to skip, because a skip
    # list only ever excludes what somebody remembered (L96).
    case "$name" in
        *.json) ;;
        *) continue ;;
    esac

    stem="${name%.json}"
    if ! printf '%s' "$stem" | grep -qiE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
        # Named rather than skipped. Ovation drains by the booking id in the
        # filename, so this is either a record whose name is wrong or a file
        # nobody meant to leave here, and a drain that quietly ignores it would
        # leave a real shoot uninvoiced with nothing said (L98).
        note "$name is not named for a booking id, so nothing will ever drain it"
        continue
    fi

    RECORDS=$((RECORDS+1))

    if ! readable_json "$f"; then
        note "$stem is not readable as JSON, so the booking it holds cannot be invoiced"
        continue
    fi

    version="$(field "$f" version)"
    if [ "$version" != "$WANT_VERSION" ]; then
        note "$stem is format version ${version:-absent}, not ${WANT_VERSION}"
        continue
    fi

    # `venue` is deliberately NOT required: it is absent for an ad hoc venue,
    # which has no roster entry to carry, and booking.venueName is the whole
    # answer in that case. Requiring it here would refuse a legitimate record.
    for required in committedAt booking client; do
        if [ -z "$(field "$f" "$required")" ]; then
            note "$stem has no '$required' field"
        fi
    done
done
shopt -u nullglob dotglob

if [ -n "$PROBLEMS" ]; then
    echo "BLOCKED: the queue holds ${RECORDS} record(s) Ovation could not all read"
    printf '%s' "$PROBLEMS"
    echo "    A record that is present and unreadable is worse than one that is absent:"
    echo "    the shoot happened, and the file says it was handed over."
    exit 1
fi

if [ "$RECORDS" -eq 0 ]; then
    cannot_measure "the queue directory exists and is empty" \
        "Downbeat has queued bookings here before and something has drained them, or none has been committed since it was created"
fi

echo "PASS: the queue holds ${RECORDS} record(s), every one readable at version ${WANT_VERSION}"
exit 0
