#!/bin/bash
# The suite for scripts/check-live-data-untouched.sh.
#
# ovation#58, plan 1.9. Every case runs against a THROWAWAY Application Support
# root through the script's own seam, so the suite that checks the guard against
# live data never touches live data itself (L2). The real root is exercised once,
# because a seam that hides the real path from every test leaves it untested
# (L246).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "live data guard tests" 16

TARGET="scripts/check-live-data-untouched.sh"
require_target "$TARGET"
harness_temp_dir WORK

ROOT="$WORK/support"
mkdir -p "$ROOT/Ovation" "$ROOT/Ovation-Debug"

run() { OVATION_LIVE_DATA_ROOT="$ROOT" "./$TARGET" "$@" 2>&1; }
status() { OVATION_LIVE_DATA_ROOT="$ROOT" "./$TARGET" "$@" >/dev/null 2>&1; printf '%s' "$?"; }

# An untouched run.
check "a snapshot of an empty root succeeds" "$(status snapshot "$WORK/f1.json")" "0"
check "and comparing it straight back passes" "$(status compare "$WORK/f1.json")" "0"
check "and it says how many paths it watched" \
    "$(run compare "$WORK/f1.json" | grep -c 'watched path')" "1"

# A test that wrote to the real store.
run snapshot "$WORK/f2.json" >/dev/null
printf 'a store a test created\n' > "$ROOT/Ovation/Ovation.store"
check "a file appearing under the watched set is REFUSED" \
    "$(status compare "$WORK/f2.json")" "1"
check "and the refusal names the path that changed" \
    "$(run compare "$WORK/f2.json" | grep -c 'Ovation/Ovation.store')" "1"
check "and it names the other explanation, so a false accusation is diagnosable" \
    "$(run compare "$WORK/f2.json" | grep -c 'app was open')" "1"

# A file that CHANGED rather than appeared.
run snapshot "$WORK/f3.json" >/dev/null
printf 'a store a test then grew\n\n' > "$ROOT/Ovation/Ovation.store"
check "a file changing size is refused" "$(status compare "$WORK/f3.json")" "1"

# A file that went away.
run snapshot "$WORK/f4.json" >/dev/null
rm "$ROOT/Ovation/Ovation.store"
check "a watched file DISAPPEARING is refused too" "$(status compare "$WORK/f4.json")" "1"

# Inside a watched directory.
mkdir -p "$ROOT/Ovation/documents/ab"
run snapshot "$WORK/f5.json" >/dev/null
printf 'a receipt a test wrote\n' > "$ROOT/Ovation/documents/ab/abc.pdf"
check "a file appearing inside a watched directory is refused" \
    "$(status compare "$WORK/f5.json")" "1"

# THE TWO DELIBERATE EXCLUSIONS. Downbeat writes the queue and Dan places the
# custody files, so attributing either to the suite would accuse the wrong
# writer (L375).
run snapshot "$WORK/f6.json" >/dev/null
mkdir -p "$ROOT/Ovation/booking-queue" "$ROOT/Ovation/custody"
printf '{"version":3}\n' > "$ROOT/Ovation/booking-queue/a-booking.json"
printf 'a custody note\n' > "$ROOT/Ovation/custody/note.txt"
check "a booking Downbeat wrote during the run is NOT blamed on the suite" \
    "$(status compare "$WORK/f6.json")" "0"

# NOTHING MEASURED IS NOT A PASS (L98).
check "comparing with no fingerprint refuses rather than passing" \
    "$(status compare "$WORK/never-written.json")" "2"
check "and says the run was never bracketed" \
    "$(run compare "$WORK/never-written.json" | grep -c 'never bracketed')" "1"
printf 'not json at all' > "$WORK/f7.json"
check "an unreadable fingerprint refuses" "$(status compare "$WORK/f7.json")" "2"

# A fingerprint from a different root cannot answer for this one.
run snapshot "$WORK/f8.json" >/dev/null
check "a fingerprint taken under another root is refused, not compared" \
    "$(OVATION_LIVE_DATA_ROOT="$WORK/elsewhere" "./$TARGET" compare "$WORK/f8.json" \
        >/dev/null 2>&1; printf '%s' "$?")" "2"

check "an unknown command is refused" "$(status wibble "$WORK/f1.json")" "2"

# The real root, once (L246).
REAL="$WORK/real.json"
"./$TARGET" snapshot "$REAL" >/dev/null 2>&1
check "the real Application Support root can be fingerprinted and compared" \
    "$("./$TARGET" compare "$REAL" >/dev/null 2>&1; printf '%s' "$?")" "0"

harness_end
