#!/bin/bash
# The suite for scripts/measure-booking-export.py.
#
# ovation#121. This script exists because the numbers the design record argues
# from could not be produced again, so what has to be right about it is the
# ARITHMETIC and the refusals, and neither can be checked against the real
# export: a suite that read Dan's file would be asserting about his business
# rather than about this script, and would change every time he takes a booking
# (L2, L48). Every case below is a fixture whose answers are known by
# construction.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "booking export measurement tests" 26

TARGET="scripts/measure-booking-export.py"
require_target "$TARGET"
harness_temp_dir WORK

# The hash check is the first thing this script does, so every case has to get
# past it. The fixture's own hash is computed rather than written down, which is
# also what proves the check is comparing the FILE and not a constant.
run_on() {
    python3 "$TARGET" "$1" "$(shasum -a 256 "$1" | cut -d' ' -f1)" 2>&1
}
status_on() {
    run_on "$1" >/dev/null 2>&1
    printf '%s' "$?"
}
says() { run_on "$1" | sed -n "s/^ *$2 *//p" | head -1; }

# A booking of a stated length, in whole seconds from a fixed instant.
export_with() {
    # $1 destination, $2 the bookings array, $3 the clients array
    cat > "$1" <<JSON
{ "version": 3, "exportedAt": "2026-08-29T15:07:27Z",
  "blockedDates": ["2026-12-25"],
  "venues": [{"id": "v1", "name": "A hall"}],
  "bookings": $2,
  "clients": $3 }
JSON
}

ONE_HOUR='{"id":"b1","startsAt":"2026-10-25T19:00:00Z","endsAt":"2026-10-25T20:00:00Z"}'
TWO_HOUR='{"id":"b2","startsAt":"2026-10-26T19:00:00Z","endsAt":"2026-10-26T21:00:00Z"}'
BROKEN='{"id":"b3","startsAt":"not an instant","endsAt":"nor this"}'

# ---------------------------------------------------------------------------
# The arithmetic that the record's headline number is.
# ---------------------------------------------------------------------------
SHAPE="$WORK/shape.json"
export_with "$SHAPE" "[$ONE_HOUR,$ONE_HOUR,$ONE_HOUR,$TWO_HOUR]" '[]'
check "an export of known bookings is measured" "$(status_on "$SHAPE")" "0"
check "and the one hour share is the share of the readable ones" \
    "$(says "$SHAPE" 'exactly one hour')" "3   75%"
check "and the shortest is reported" "$(says "$SHAPE" 'shortest')" "1.00 hours"
check "and the longest" "$(says "$SHAPE" 'longest')" "2.00 hours"
check "and the count of bookings" "$(says "$SHAPE" 'bookings')" "4"

# AN UNREADABLE PAIR IS NEVER A ZERO LENGTH SHOOT. Scored as zero it would sit
# in the denominator and move the share the record cites (L11).
WITHBAD="$WORK/withbad.json"
export_with "$WITHBAD" "[$ONE_HOUR,$ONE_HOUR,$ONE_HOUR,$BROKEN]" '[]'
check "an unreadable pair of instants is not counted as a shoot" \
    "$(says "$WITHBAD" 'exactly one hour')" "3   100%"
check "and it is reported rather than swallowed" \
    "$(says "$WITHBAD" 'instants that could not be read')" "1"
check "and the readable count says how many it actually had" \
    "$(says "$WITHBAD" 'readable')" "3 of 4"

# ---------------------------------------------------------------------------
# The address figures, which are PRD 37c and PRD 38a.
# ---------------------------------------------------------------------------
ADDRS="$WORK/addrs.json"
export_with "$ADDRS" "[$ONE_HOUR]" '[
  {"id":"c1","email":"a@example.com","contractEmail":"a@example.com"},
  {"id":"c2","email":"b@example.com","contractEmail":""},
  {"id":"c3","email":"c@example.com","contractEmail":"c@example.com, d@example.com"},
  {"id":"c4","email":"e@example.com","contractEmail":"call the office first"}
]'
check "an override equal to the main address is counted as a copy" \
    "$(says "$ADDRS" 'overrides copying the main')" "1 of 4"
check "an empty override is its own count" \
    "$(says "$ADDRS" 'overrides that are empty')" "1 of 4"
check "several addresses in one field is one client, not two values" \
    "$(says "$ADDRS" 'clients giving several addresses')" "1 of 4"
check "and a value that is not an address at all is one client" \
    "$(says "$ADDRS" 'clients whose value is not one')" "1 of 4"
check "while a client with a main address is never counted as missing one" \
    "$(says "$ADDRS" 'clients with no main address')" "0 of 4"

NOMAIN="$WORK/nomain.json"
export_with "$NOMAIN" "[$ONE_HOUR]" '[{"id":"c1","email":"","contractEmail":""}]'
check "a client with no main address is counted" \
    "$(says "$NOMAIN" 'clients with no main address')" "1 of 1"

# ---------------------------------------------------------------------------
# THE FIGURES IT CANNOT PRODUCE ARE SAID EVERY RUN, not only when asked. Left
# silent they would look as reproducible as the ones above (L316, L98).
# ---------------------------------------------------------------------------
check "every run says which cited figures this export cannot answer" \
    "$(run_on "$SHAPE" | grep -c 'WHAT THIS EXPORT CANNOT ANSWER')" "1"
check "and names the tax status by the figure the record cites" \
    "$(run_on "$SHAPE" | grep -c '6 of 31')" "1"

# ---------------------------------------------------------------------------
# THE HASH IS VERIFIED AT READ TIME, which docs/CUSTODY.md requires of every
# read of a custody file.
# ---------------------------------------------------------------------------
check "an export whose hash is not the recorded one is refused" \
    "$(python3 "$TARGET" "$SHAPE" 0000000000000000000000000000000000000000000000000000000000000000 \
        >/dev/null 2>&1; printf '%s' "$?")" "3"
check "and the refusal is told apart from every other outcome" \
    "$(python3 "$TARGET" "$SHAPE" 0000000000000000000000000000000000000000000000000000000000000000 2>&1 \
        | grep -c 'SHA-256 is not the one recorded')" "1"
check "and it prints both hashes so the difference is actionable" \
    "$(python3 "$TARGET" "$SHAPE" 0000000000000000000000000000000000000000000000000000000000000000 2>&1 \
        | grep -cE '^  (recorded|found) ')" "2"

# ---------------------------------------------------------------------------
# NOTHING TO MEASURE IS NOT A PASS, and each way of having nothing is its own
# outcome (L98, L11).
# ---------------------------------------------------------------------------
check "an export that is not there is refused" \
    "$(python3 "$TARGET" "$WORK/nowhere.json" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "and says so rather than reporting zeroes" \
    "$(python3 "$TARGET" "$WORK/nowhere.json" 2>&1 | grep -c 'CANNOT MEASURE')" "1"

EMPTY="$WORK/empty.json"
export_with "$EMPTY" '[]' '[]'
check "an export holding nothing cannot measure" "$(status_on "$EMPTY")" "1"
check "and is told apart from an export that is absent" \
    "$(run_on "$EMPTY" | grep -c 'holds no booking and no client')" "1"

BROKENFILE="$WORK/broken.json"
printf 'not json at all\n' > "$BROKENFILE"
check "an export that is not readable JSON cannot measure" \
    "$(status_on "$BROKENFILE")" "1"
check "and its message names that cause rather than the empty one" \
    "$(run_on "$BROKENFILE" | grep -c 'could not be read')" "1"

check "called with no argument it says how to call it" \
    "$(python3 "$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "2"

harness_end
