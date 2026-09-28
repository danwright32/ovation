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
harness_begin "live data guard tests" 37

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

# WHEN THE INSTALLED APP WAS LAST LAUNCHED IS INJECTED TOO (ovation#591), for the
# same reason as the process list: the real answer is whenever Dan last opened
# Ovation. Each stub prints what `mdls -raw -name kMDItemLastUsedDate` would.
# "now" is computed when it is ASKED, which is at the compare, so it always falls
# after the snapshot: an app opened and quit inside the run.
printf '#!/bin/bash\nprintf "2020-01-01 00:00:00 +0000"\n' > "$WORK/used-long-ago"
printf '#!/bin/bash\ndate -u "+%%Y-%%m-%%d %%H:%%M:%%S +0000"\n' > "$WORK/used-now"
printf '#!/bin/bash\nprintf "(null)"\n' > "$WORK/used-never"
printf '#!/bin/bash\nexit 1\n' > "$WORK/used-broken"
chmod +x "$WORK/used-long-ago" "$WORK/used-now" "$WORK/used-never" "$WORK/used-broken"
# Every case asks the stub named here unless it names another.
USED="$WORK/used-long-ago"

with_ps() {
    OVATION_LIVE_DATA_ROOT="$ROOT" OVATION_LIVE_DATA_PROCESS_LIST="$1" \
        OVATION_LIVE_DATA_LAST_USED="$USED" "./$TARGET" "${@:2}" 2>&1
}
with_ps_status() {
    OVATION_LIVE_DATA_ROOT="$ROOT" OVATION_LIVE_DATA_PROCESS_LIST="$1" \
        OVATION_LIVE_DATA_LAST_USED="$USED" "./$TARGET" "${@:2}"
}
run() { with_ps "$WORK/ps-not-running" "$@"; }
status() { with_ps_status "$WORK/ps-not-running" "$@"; }

# An untouched run.
check_exit "a snapshot of an empty root succeeds" 0 status snapshot "$WORK/f1.json"
check_exit "and comparing it straight back passes" 0 status compare "$WORK/f1.json"
check "and it says how many paths it watched" \
    "$(run compare "$WORK/f1.json" | grep -c 'watched path')" "1"

# A test that wrote to the real store.
run snapshot "$WORK/f2.json" >/dev/null
printf 'a store a test created\n' > "$ROOT/Ovation/Ovation.store"
check_exit "a file appearing under the watched set is REFUSED" \
    1 status compare "$WORK/f2.json"
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
check_exit "a file changing size is refused" 1 status compare "$WORK/f3.json"

# A file that went away.
run snapshot "$WORK/f4.json" >/dev/null
rm "$ROOT/Ovation/Ovation.store"
check_exit "a watched file DISAPPEARING is refused too" 1 status compare "$WORK/f4.json"

# Inside a watched directory.
mkdir -p "$ROOT/Ovation/documents/ab"
run snapshot "$WORK/f5.json" >/dev/null
printf 'a receipt a test wrote\n' > "$ROOT/Ovation/documents/ab/abc.pdf"
check_exit "a file appearing inside a watched directory is refused" \
    1 status compare "$WORK/f5.json"

# THE TWO DELIBERATE EXCLUSIONS. Downbeat writes the queue and Dan places the
# custody files, so attributing either to the suite would accuse the wrong
# writer (L375).
run snapshot "$WORK/f6.json" >/dev/null
mkdir -p "$ROOT/Ovation/booking-queue" "$ROOT/Ovation/custody"
printf '{"version":3}\n' > "$ROOT/Ovation/booking-queue/a-booking.json"
printf 'a custody note\n' > "$ROOT/Ovation/custody/note.txt"
check_exit "a booking Downbeat wrote during the run is NOT blamed on the suite" \
    0 status compare "$WORK/f6.json"

# NOTHING MEASURED IS NOT A PASS (L98).
check_exit "comparing with no fingerprint refuses rather than passing" \
    2 status compare "$WORK/never-written.json"
check "and says the run was never bracketed" \
    "$(run compare "$WORK/never-written.json" | grep -c 'never bracketed')" "1"
printf 'not json at all' > "$WORK/f7.json"
check_exit "an unreadable fingerprint refuses" 2 status compare "$WORK/f7.json"

# A fingerprint from a different root cannot answer for this one.
run snapshot "$WORK/f8.json" >/dev/null
check_exit "a fingerprint taken under another root is refused, not compared" \
    2 env OVATION_LIVE_DATA_ROOT="$WORK/elsewhere" "./$TARGET" compare "$WORK/f8.json"

# A WATCHED FOLDER THAT CANNOT BE READ IS NOT AN EMPTY ONE (ovation#581). The walk
# used to skip a directory it could not list, so a documents folder it was barred
# from read as holding nothing, at both ends, and the run passed unmeasured (L98).
mkdir -p "$ROOT/Ovation/documents/barred"
chmod 000 "$ROOT/Ovation/documents/barred"
harness_on_exit "chmod 755 '$ROOT/Ovation/documents/barred' 2>/dev/null"
check_exit "a snapshot that cannot read a watched folder refuses rather than recording it" \
    2 status snapshot "$WORK/barred.json"
check "and it says it cannot measure, naming the folder" \
    "$(run snapshot "$WORK/barred.json" | grep -c '^CANNOT MEASURE: .*Ovation/documents/barred')" "1"
chmod 755 "$ROOT/Ovation/documents/barred"
rmdir "$ROOT/Ovation/documents/barred"

check_exit "an unknown command is refused" 2 status wibble "$WORK/f1.json"

# ---------------------------------------------------------------------------
# THE INSTALLED APP (ovation#266, ovation#591). Since 2026-09-13 the Release build
# lives in /Applications and is in daily use, and merely having it open, or
# quitting it, changes Ovation.store-shm.
#
# A change the installed app explains is DAN'S OWN USE, and it does not fail the
# run: on 2026-09-27 two pre-push runs were refused for exactly that, each a
# twenty minute rerun. It explains a change only under the folder it writes,
# Ovation/, and only when it ran during the run: open at either end, or launched
# after the snapshot. Anything else is still refused as a leak, which is the case
# this guard exists for (L2).
# ---------------------------------------------------------------------------
touch_shm() { printf 'shm %s\n' "$1" > "$ROOT/Ovation/Ovation.store-shm"; }

with_ps "$WORK/ps-running" snapshot "$WORK/app1.json" >/dev/null
touch_shm one
check_exit "a change while the installed app was open is Dan's own use, its own outcome" \
    3 with_ps_status "$WORK/ps-running" compare "$WORK/app1.json"
check "and it says the installed app was running, naming it by its executable path" \
    "$(with_ps "$WORK/ps-running" compare "$WORK/app1.json" \
        | grep -c "^The installed app ($INSTALLED_EXE) was running at the start and at the end of the run\.$")" "1"
check "and it names which watched path changed" \
    "$(with_ps "$WORK/ps-running" compare "$WORK/app1.json" | grep -c '^  Ovation/Ovation.store-shm$')" "1"
check "and it says the run is not failed for it" \
    "$(with_ps "$WORK/ps-running" compare "$WORK/app1.json" | grep -c 'use of Ovation and this run is not failed for it\.$')" "1"

with_ps "$WORK/ps-running" snapshot "$WORK/app2.json" >/dev/null
touch_shm two
check_exit "a change when the app was open at the start and quit before the end is the same outcome" \
    3 with_ps_status "$WORK/ps-not-running" compare "$WORK/app2.json"

# OPENED AND QUIT INSIDE THE RUN. The process list at the two ends cannot see it,
# and this is how the 2026-09-27 refusals looked: the store written in the same
# second as the app's last used date. macOS records that date on launch.
with_ps "$WORK/ps-not-running" snapshot "$WORK/app6.json" >/dev/null
touch_shm six
USED="$WORK/used-now"
check_exit "a change when the installed app was launched during the run, and quit, is Dan's own use" \
    3 with_ps_status "$WORK/ps-not-running" compare "$WORK/app6.json"
check "and it says the app was launched during the run" \
    "$(with_ps "$WORK/ps-not-running" compare "$WORK/app6.json" \
        | grep -c "^The installed app ($INSTALLED_EXE) was launched during the run, at ")" "1"
USED="$WORK/used-long-ago"

# THE SAME CHANGE WITH THE APP CLOSED AT BOTH ENDS, AND NOT LAUNCHED BETWEEN, IS
# STILL A LEAK. This is the half that keeps the new outcome from becoming a way to
# excuse a real one.
with_ps "$WORK/ps-not-running" snapshot "$WORK/app3.json" >/dev/null
touch_shm three
check_exit "the same change with the installed app closed throughout is still refused as a leak" \
    1 with_ps_status "$WORK/ps-not-running" compare "$WORK/app3.json"
check "and that refusal says the installed app did not run during the run" \
    "$(with_ps "$WORK/ps-not-running" compare "$WORK/app3.json" \
        | grep -c '^The installed app was not running at the start or at the end of the run, and was not launched during it\.$')" "1"
USED="$WORK/used-never"
check_exit "and so it is when macOS holds no launch date for the app at all" \
    1 with_ps_status "$WORK/ps-not-running" compare "$WORK/app3.json"
USED="$WORK/used-broken"
check_exit "and when the launch date could not be read, which is not evidence it ran" \
    1 with_ps_status "$WORK/ps-not-running" compare "$WORK/app3.json"
check "and that refusal says the launch date could not be read, rather than that it did not run" \
    "$(with_ps "$WORK/ps-not-running" compare "$WORK/app3.json" \
        | grep -c '^When the installed app was last launched could not be read')" "1"
USED="$WORK/used-long-ago"

# THE INSTALLED APP NEVER WRITES Ovation-Debug, so it explains nothing there, open
# or not. A change there while it ran is refused, and named as the one it does not
# explain.
with_ps "$WORK/ps-running" snapshot "$WORK/app7.json" >/dev/null
touch_shm seven
printf 'a debug store a test wrote\n' > "$ROOT/Ovation-Debug/Ovation.store"
check_exit "a change under Ovation-Debug while the installed app was open is still refused" \
    1 with_ps_status "$WORK/ps-running" compare "$WORK/app7.json"
check "and it names Ovation-Debug as the change the installed app does not explain" \
    "$(with_ps "$WORK/ps-running" compare "$WORK/app7.json" \
        | sed -n '/^Not explained by the installed app/,$p' | grep -c '^  Ovation-Debug$')" "1"
rm "$ROOT/Ovation-Debug/Ovation.store"

# A process list that could not be read is not "the app was closed" (L98): the
# change stays a refusal, and the message says what could not be told.
with_ps "$WORK/ps-broken" snapshot "$WORK/app4.json" >/dev/null
touch_shm four
check_exit "a change when whether the app was running could not be read is still refused" \
    1 with_ps_status "$WORK/ps-broken" compare "$WORK/app4.json"
check "and it says the process list could not be read, rather than claiming the app was closed" \
    "$(with_ps "$WORK/ps-broken" compare "$WORK/app4.json" \
        | grep -c '^Whether the installed app was running could not be read')" "1"

with_ps "$WORK/ps-running" snapshot "$WORK/app5.json" >/dev/null
check_exit "nothing changing while the app was open still passes" \
    0 with_ps_status "$WORK/ps-running" compare "$WORK/app5.json"

# THE ROOT EACH BRACKET MEASURED CAN BE READ BACK (ovation#570). The runner's own
# suite drives inner runs that each open this bracket, and it has to be able to
# prove none of them measured Dan's real folder, by where the snapshot actually
# looked rather than by which variables a helper remembered to set (L322). So a
# snapshot names its root in a log when one is named, and only a snapshot does:
# one line is one bracket opened.
BRACKETS="$WORK/brackets.log"
OVATION_LIVE_DATA_BRACKET_LOG="$BRACKETS" run snapshot "$WORK/log1.json" >/dev/null
check "a snapshot records the root it fingerprinted in the bracket log it is given" \
    "$(cat "$BRACKETS" 2>/dev/null)" "$ROOT"
OVATION_LIVE_DATA_BRACKET_LOG="$BRACKETS" run compare "$WORK/log1.json" >/dev/null
check "and a compare adds nothing, so each line is one bracket opened" \
    "$(wc -l < "$BRACKETS" 2>/dev/null | tr -d ' ')" "1"

# The real root, once (L246).
#
# WHETHER DAN IS USING OVATION IS NOT THIS SUITE'S TO SET (ovation#581, L411). With
# the installed app open its store changes under this case, which used to fail it
# at random. The question here is whether the real root can be fingerprinted and
# compared at all, and both "nothing changed" and "changed, and the installed app
# explains it" are answers to that. Anything else is a failure and keeps its words.
REAL="$WORK/real.json"
"./$TARGET" snapshot "$REAL" >/dev/null 2>&1
REAL_SAID="$("./$TARGET" compare "$REAL" 2>&1)"; REAL_STATUS=$?
case "$REAL_STATUS" in
    0) REAL_VERDICT="compared" ;;
    3) REAL_VERDICT="compared"
       echo "    (the real root changed under Dan's own use of the installed app, which it explains)" ;;
    *) REAL_VERDICT="exit $REAL_STATUS: $(head -n 12 <<< "$REAL_SAID")" ;;
esac
check "the real Application Support root can be fingerprinted and compared" \
    "$REAL_VERDICT" "compared"

harness_end
