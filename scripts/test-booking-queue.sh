#!/bin/bash
# The booking handoff queue, read from OVATION's side.
#
# ovation#3 step 4, and the entry criterion for the `Downbeat booking queue
# consumer` milestone. Downbeat writes one `<booking-uuid>.json` per committed
# booking into a directory retention never sweeps, because the export file is a
# snapshot of current state and a booking that came and went while Ovation was
# closed is a shoot that is never invoiced.
#
# THE WHOLE POINT IS THAT AN EMPTY ANSWER IS NOT A GOOD ONE. A drain that
# reports success when it found nothing to drain is indistinguishable from one
# that saw everything succeed (L98), and Downbeat's own CONTRACT.md already says
# an empty bookings array cannot be told apart from the data being lost. So
# "there is no queue directory" and "the queue directory is empty" are two
# different sentences here, and neither is a pass.
#
# The record shape is Downbeat's `BookingHandoffRecord`, read on 2026-09-06:
# `version` (3, shared with the export so two numbers cannot drift), the ISO8601
# `committedAt`, `booking`, `client`, and an OPTIONAL `venue` which is absent for
# an ad hoc venue that has no roster entry.
#
# Every case runs against a THROWAWAY directory. Nothing here touches the real
# queue, which is live data Ovation will one day invoice from (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "booking queue reader tests" 25

TARGET="scripts/check-booking-queue.sh"
require_target "$TARGET"
harness_temp_dir WORK

UUID_A="B1D4F0E2-8C3A-4F1B-9E77-0A2C6D5E4F31"
UUID_B="7A2E9C10-4B6D-4E88-A3F5-C1094D7E2B60"

# The name is REQUIRED, and that is not defensiveness for its own sake. An empty
# $1 makes this `rm -rf "$WORK/"`, which takes every other case's fixture with
# it, and `set -u` does not catch it because an empty parameter is set (L5). The
# harness guards $WORK itself for the same reason; this guards the half it
# cannot see.
queue() {
    [ -n "${1:-}" ] || { echo "REFUSED: queue() needs a name"; exit 1; }
    local d="$WORK/$1"
    [ -n "${WORK:-}" ] || { echo "REFUSED: no temp directory"; exit 1; }
    rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"
}

# Shaped from Downbeat's BookingHandoffRecord, with a deliberately fictional
# client so that no real name is ever written into this repository (L155).
record_file() {
    # record_file <dir> <uuid> <version> <omit-field or -> <with-venue yes/no>
    local dir="$1" id="$2" version="$3" omit="$4" venue="$5" parts=()
    [ "$omit" = "version" ]     || parts+=("\"version\":$version")
    [ "$omit" = "committedAt" ] || parts+=("\"committedAt\":\"2026-09-06T15:00:00Z\"")
    [ "$omit" = "booking" ]     || parts+=("\"booking\":{\"id\":\"$id\",\"day\":\"2026-10-25\"}")
    [ "$omit" = "client" ]      || parts+=("\"client\":{\"displayName\":\"Zzyzx Fictional Ensemble\"}")
    [ "$venue" = "yes" ]        && parts+=("\"venue\":{\"name\":\"Nowhere Hall\"}")
    local IFS=,
    printf '{%s}\n' "${parts[*]}" > "$dir/$id.json"
}

run_check() { OVATION_BOOKING_QUEUE="$1" "./$TARGET" 2>&1; }
status_of() { run_check "$1" >/dev/null 2>&1; printf '%s' "$?"; }
says() { if printf '%s' "$1" | grep -qF "$2"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. NOTHING TO READ. Two different causes, two different sentences, and NEITHER
#    is a pass. This is the state the real queue is in today.
# ---------------------------------------------------------------------------
check "a queue directory that does not exist cannot be measured" \
    "$(status_of "$WORK/never-created")" "2"
OUT_NONE="$(run_check "$WORK/never-created")"
check "and it says the directory is absent rather than that it was empty" \
    "$(says "$OUT_NONE" "has never")" "yes"

EMPTY="$(queue empty)"
check "a queue directory that exists and is empty cannot be measured either" \
    "$(status_of "$EMPTY")" "2"
OUT_EMPTY="$(run_check "$EMPTY")"
check "and THAT says it is empty, which is a different fact" \
    "$(says "$OUT_EMPTY" "empty")" "yes"
check "the two causes do not share one message" \
    "$([ "$OUT_NONE" = "$OUT_EMPTY" ] && echo same || echo different)" "different"

# ---------------------------------------------------------------------------
# 2. A REAL RECORD. This is what step 4 of ovation#3 is waiting to see.
# ---------------------------------------------------------------------------
ONE="$(queue one)"; record_file "$ONE" "$UUID_A" 3 - yes
check "one well formed record is a pass" "$(status_of "$ONE")" "0"
OUT_ONE="$(run_check "$ONE")"
check "and it reports how many it found" "$(says "$OUT_ONE" "1 record")" "yes"

TWO="$(queue two)"; record_file "$TWO" "$UUID_A" 3 - yes; record_file "$TWO" "$UUID_B" 3 - no
check "two records are counted as two" "$(says "$(run_check "$TWO")" "2 record")" "yes"
check "and a record with no venue is fine, because an ad hoc venue has no roster entry" \
    "$(status_of "$TWO")" "0"

# ---------------------------------------------------------------------------
# 3. THE PRIVACY FLOOR. These records carry the client and venue names that were
#    true when the shoot was booked. A guard that scans the repository cannot see
#    what a tool PRINTS, and printed output reaches scrollback and transcripts by
#    a route that guard never inspects (L222).
# ---------------------------------------------------------------------------
check "no client name reaches the output" "$(says "$OUT_ONE" "Zzyzx")" "no"
check "no venue name reaches the output" "$(says "$OUT_ONE" "Nowhere Hall")" "no"

# ---------------------------------------------------------------------------
# 4. BLOCKED: a record is there and is wrong. Ovation would invoice from these,
#    so a record it cannot read is worse than one that is absent: the shoot
#    happened and the file says it was handed over.
# ---------------------------------------------------------------------------
BAD="$(queue malformed)"; printf 'not json at all\n' > "$BAD/$UUID_A.json"
check "a record that is not JSON is BLOCKED, never skipped" "$(status_of "$BAD")" "1"

V2="$(queue oldversion)"; record_file "$V2" "$UUID_A" 2 - yes
check "a record BELOW the accepted minimum is BLOCKED" "$(status_of "$V2")" "1"
check "and it names the version it found" "$(says "$(run_check "$V2")" "2")" "yes"
check "and the minimum it wanted, because that is the half that says what to do" \
    "$(says "$(run_check "$V2")" "3")" "yes"

# ---------------------------------------------------------------------------
# THE FLOOR IS A MINIMUM, AND IT COMES FROM THE PUBLISHED DECLARATION
# (ovation#33). This reader used to require an EXACT version, which is the gate
# shape that turns Downbeat's next additive bump into a total outage: every
# record refused, and a queue nothing drains looks exactly like a quiet week
# (L255, L98).
#
# The number is read from `integration/downbeat-handoff-accepted-versions.json`,
# the same file Downbeat's push gate reads and the same one `HandoffRecord`'s
# behaviour test ties the decoder to. One derivation, so this reader and the
# decoder cannot come to different answers about the same file (L70, L263).
V4="$(queue newversion)"; record_file "$V4" "$UUID_A" 4 - yes
check "a record ABOVE the minimum is a PASS, which is the whole point of a floor" \
    "$(status_of "$V4")" "0"

V3="$(queue atthefloor)"; record_file "$V3" "$UUID_A" 3 - yes
check "and the minimum itself is still accepted" "$(status_of "$V3")" "0"

# A DECLARATION IT CANNOT READ IS NOT A PASS. The floor is the whole judgement,
# so a reader that fell back to a built in number would answer confidently from a
# constant nobody published, and the two would drift with nothing reporting it
# (L98, L11).
MISSING_DECL="$WORK/no-declaration.json"
rm -f "$MISSING_DECL"
check "a missing declaration cannot be measured, rather than defaulting" \
    "$(OVATION_HANDOFF_DECLARATION="$MISSING_DECL" run_check "$V3" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "and it says which file it could not read" \
    "$(says "$(OVATION_HANDOFF_DECLARATION="$MISSING_DECL" run_check "$V3")" "no-declaration.json")" "yes"

BAD_DECL="$WORK/malformed-declaration.json"
printf 'not json\n' > "$BAD_DECL"
check "a declaration that is present and malformed cannot be measured either" \
    "$(OVATION_HANDOFF_DECLARATION="$BAD_DECL" run_check "$V3" >/dev/null 2>&1; printf '%s' "$?")" "2"

for field in committedAt booking client; do
    D="$(queue "missing-$field")"; record_file "$D" "$UUID_A" 3 "$field" yes
    check "a record with no $field is BLOCKED" "$(status_of "$D")" "1"
done

# ---------------------------------------------------------------------------
# 5. WHAT IS AND IS NOT A RECORD. Ovation drains by the uuid filename, so a
#    stray .json is not something to skip quietly: it is either a record whose
#    name is wrong or a file nobody meant to put there, and both need saying.
#    Files that are not .json at all (a .DS_Store) are the finder's litter and
#    are genuinely not the queue's business.
# ---------------------------------------------------------------------------
LITTER="$(queue litter)"; record_file "$LITTER" "$UUID_A" 3 - yes; printf '\0' > "$LITTER/.DS_Store"
check "a .DS_Store beside a good record does not spoil the run" "$(status_of "$LITTER")" "0"

STRAY="$(queue stray)"; record_file "$STRAY" "$UUID_A" 3 - yes
printf '{"version":3}\n' > "$STRAY/notes.json"
check "a .json whose name is not a booking id is BLOCKED rather than ignored" \
    "$(status_of "$STRAY")" "1"

harness_end
