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
harness_begin "live data guard tests" 25

TARGET="scripts/check-live-data-untouched.sh"
require_target "$TARGET"
harness_temp_dir WORK

ROOT="$WORK/support"
mkdir -p "$ROOT/Ovation" "$ROOT/Ovation-Debug"

# THE PROCESS LIST IS INJECTED IN EVERY CASE (ovation#266). The check asks
# whether the installed app was running, and a case left to the real list would
# answer differently depending on whether Dan has Ovation open while the suite
# runs, which is a test about his afternoon (L284). A stub prints what
# `ps -A -o comm=` would, so no case launches or quits anything.
INSTALLED_EXE="/Applications/Ovation.app/Contents/MacOS/Ovation"
printf '#!/bin/bash\nprintf "/sbin/launchd\\n%s\\n"\n' "$INSTALLED_EXE" > "$WORK/ps-running"
# A Debug build run from DerivedData is not the installed app, and naming one
# here is what keeps the match on the whole executable path rather than the name.
printf '#!/bin/bash\nprintf "/sbin/launchd\\n/Users/x/DerivedData/Build/Products/Debug/Ovation.app/Contents/MacOS/Ovation\\n"\n' \
    > "$WORK/ps-not-running"
printf '#!/bin/bash\nexit 1\n' > "$WORK/ps-broken"
chmod +x "$WORK/ps-running" "$WORK/ps-not-running" "$WORK/ps-broken"

with_ps() {
    OVATION_LIVE_DATA_ROOT="$ROOT" OVATION_LIVE_DATA_PROCESS_LIST="$1" "./$TARGET" "${@:2}" 2>&1
}
with_ps_status() {
    OVATION_LIVE_DATA_ROOT="$ROOT" OVATION_LIVE_DATA_PROCESS_LIST="$1" "./$TARGET" "${@:2}" >/dev/null 2>&1
    printf '%s' "$?"
}
run() { with_ps "$WORK/ps-not-running" "$@"; }
status() { with_ps_status "$WORK/ps-not-running" "$@"; }

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
# The explanation this refusal used to give was true while only Debug builds ran
# and has been wrong since the Release build was installed: the installed app
# writes the Release folder, not Ovation-Debug, so it sent the reader to the wrong
# cause (ovation#266, L11). It is asserted gone rather than merely replaced.
check "and it no longer says a running app explains only a change under Ovation-Debug" \
    "$(run compare "$WORK/f2.json" | grep -c 'explains a change under Ovation-Debug and nothing else')" "0"

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

# ---------------------------------------------------------------------------
# THE INSTALLED APP (ovation#266). Since 2026-09-13 the Release build lives in
# /Applications and is in daily use, and merely having it open, or quitting it,
# changes Ovation.store-shm. The run for ovation#262 was refused for exactly
# that, and only a second run with the app confirmed closed showed no test had
# reached live data.
#
# A change while the app was running cannot be told from a test having written
# there, so it is still not a pass. It is its OWN outcome, saying so and naming
# what changed, rather than an accusation of the suite.
# ---------------------------------------------------------------------------
touch_shm() { printf 'shm %s\n' "$1" > "$ROOT/Ovation/Ovation.store-shm"; }

with_ps "$WORK/ps-running" snapshot "$WORK/app1.json" >/dev/null
touch_shm one
check "a change while the installed app was open is its own outcome, not a leak" \
    "$(with_ps_status "$WORK/ps-running" compare "$WORK/app1.json")" "3"
check "and it says the installed app was running, naming it by its executable path" \
    "$(with_ps "$WORK/ps-running" compare "$WORK/app1.json" \
        | grep -c "^The installed app ($INSTALLED_EXE) was running at the start and at the end of the run\.$")" "1"
check "and it names which watched path changed" \
    "$(with_ps "$WORK/ps-running" compare "$WORK/app1.json" | grep -c '^  Ovation/Ovation.store-shm$')" "1"

with_ps "$WORK/ps-running" snapshot "$WORK/app2.json" >/dev/null
touch_shm two
check "a change when the app was open at the start and quit before the end is the same outcome" \
    "$(with_ps_status "$WORK/ps-not-running" compare "$WORK/app2.json")" "3"

# THE SAME CHANGE WITH THE APP CLOSED AT BOTH ENDS IS STILL A LEAK. This is the
# half that keeps the new outcome from becoming a way to excuse a real one.
with_ps "$WORK/ps-not-running" snapshot "$WORK/app3.json" >/dev/null
touch_shm three
check "the same change with the installed app closed at both ends is still refused as a leak" \
    "$(with_ps_status "$WORK/ps-not-running" compare "$WORK/app3.json")" "1"
check "and that refusal says the installed app was not running at either end" \
    "$(with_ps "$WORK/ps-not-running" compare "$WORK/app3.json" \
        | grep -c '^The installed app was not running at the start or at the end of the run\.$')" "1"

# A process list that could not be read is not "the app was closed" (L98): the
# change stays a refusal, and the message says what could not be told.
with_ps "$WORK/ps-broken" snapshot "$WORK/app4.json" >/dev/null
touch_shm four
check "a change when whether the app was running could not be read is still refused" \
    "$(with_ps_status "$WORK/ps-broken" compare "$WORK/app4.json")" "1"
check "and it says the process list could not be read, rather than claiming the app was closed" \
    "$(with_ps "$WORK/ps-broken" compare "$WORK/app4.json" \
        | grep -c '^Whether the installed app was running could not be read')" "1"

with_ps "$WORK/ps-running" snapshot "$WORK/app5.json" >/dev/null
check "nothing changing while the app was open still passes" \
    "$(with_ps_status "$WORK/ps-running" compare "$WORK/app5.json")" "0"

# The real root, once (L246).
REAL="$WORK/real.json"
"./$TARGET" snapshot "$REAL" >/dev/null 2>&1
check "the real Application Support root can be fingerprinted and compared" \
    "$("./$TARGET" compare "$REAL" >/dev/null 2>&1; printf '%s' "$?")" "0"

harness_end
