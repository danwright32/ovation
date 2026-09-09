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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUEUE="${OVATION_BOOKING_QUEUE:-${HOME}/Library/Application Support/Ovation/booking-queue}"
DECLARATION="${OVATION_HANDOFF_DECLARATION:-${REPO_ROOT}/integration/downbeat-handoff-accepted-versions.json}"

cannot_measure() {
    echo "CANNOT MEASURE: $1"
    [ "${2:-}" = "" ] || echo "    $2"
    echo "    Nothing was verified. This is not a pass."
    exit 2
}

# THE FLOOR IS A MINIMUM AND IT IS READ, NEVER TYPED HERE (ovation#33). This used
# to require an EXACT version, which is the gate shape that turns Downbeat's next
# additive bump into a total outage: every record refused, and a queue nothing
# drains looks exactly like a quiet week (L255, L98).
#
# It comes from the same published declaration Downbeat's push gate reads and
# `HandoffRecord`'s behaviour test ties the decoder to, so this reader and the
# decoder cannot answer differently about one file. A second copy of the number
# here would be a second definition that drifts, and the one that drifted would
# be believed (L70, L263).
#
# A DECLARATION IT CANNOT READ IS CANNOT MEASURE, never a fallback to a built in
# number: the floor is the whole judgement, so a reader that guessed would answer
# confidently from a constant nobody published.
if [ ! -f "$DECLARATION" ]; then
    cannot_measure "the accepted versions declaration is not there" \
        "expected $DECLARATION, which is what states the oldest handoff format Ovation reads"
fi

MINIMUM_VERSION="$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(1)
lo = d.get("minimumVersion") if isinstance(d, dict) else None
if not isinstance(lo, int) or isinstance(lo, bool):
    raise SystemExit(1)
print(lo)
' "$DECLARATION" 2>/dev/null)" || MINIMUM_VERSION=""

if [ -z "$MINIMUM_VERSION" ]; then
    cannot_measure "the accepted versions declaration states no usable minimum" \
        "$DECLARATION is there and could not be read as JSON holding an integer minimumVersion"
fi

# READ WITH python3 RATHER THAN plutil (ovation#152). It used `plutil -convert`
# and `plutil -extract`, which exist only on macOS, so every record read as
# unreadable on a Linux runner and five cases of this check's own suite failed
# there while passing here. Measured on CI rather than guessed: that job is what
# ovation#152 added to find out.
#
# The note plutil earned is kept, because it is about plutil rather than about
# this file: `plutil -lint` reports "Unexpected character {" on JSON that
# `plutil -extract` reads without complaint (measured 2026-09-06), so the tool
# named for the job was the wrong one even on the platform that has it.
#
# python3 is already required by this repository's other guards, and it is the
# same reader the declaration below is parsed with, so there is one JSON reader
# here rather than two that can disagree.
readable_json() {
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1
}
# One top level field, printed raw, or nothing when it is absent. A container
# (an object or an array) prints a non empty marker rather than its contents,
# because every caller here only asks whether it is THERE and printing a client
# object would put names into output that reaches transcripts (L222).
field() {
    python3 - "$1" "$2" <<'PYFIELD' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except Exception:
    raise SystemExit(1)
if not isinstance(data, dict) or sys.argv[2] not in data:
    raise SystemExit(0)
value = data[sys.argv[2]]
if isinstance(value, (dict, list)):
    print("present")
elif isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    raise SystemExit(0)
else:
    print(value)
PYFIELD
}

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
    # Absent, not a number, or below the floor. Told apart, because the remedies
    # differ: a record with no version is not a handoff record at all, while an
    # older one is a Downbeat that has not been upgraded (L11).
    if [ -z "$version" ]; then
        note "$stem does not say which format version it is"
        continue
    fi
    if ! printf '%s' "$version" | grep -qE '^[0-9]+$'; then
        note "$stem states a format version that is not a number"
        continue
    fi
    if [ "$version" -lt "$MINIMUM_VERSION" ]; then
        note "$stem is format version ${version}, and Ovation reads ${MINIMUM_VERSION} and above"
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

echo "PASS: the queue holds ${RECORDS} record(s), every one readable at version ${MINIMUM_VERSION} or above"
exit 0
