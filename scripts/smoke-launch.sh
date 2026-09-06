#!/bin/bash
# Does the built app actually OPEN, and open exactly one window?
#
# ovation#20. Nothing verified this. Ovation compiles, and its test suite is
# deliberately built so that it never launches the app: on 2026-09-05
# OvationApp.swift was broken on purpose, the app scheme produced 22 compile
# errors, and the OvationCore scheme still ran and reported 2 tests passing. That
# split is right, ported from overture#1967 where one launch fault took 4,802
# tests at once. Its cost is that a fault stopping the app opening was invisible
# to every check in this repository. Built is not wired, and wired is not proven
# (L3).
#
# IT MATTERS MORE HERE THAN IN THE APP IT WAS PORTED FROM. Plan 1.13 raises at
# least six independent conditions at LAUNCH, several of them refusals whose
# whole purpose is to be seen. Ovation has more ways to fail at launch than
# Overture had, and had fewer ways to notice.
#
# THIS IS NOT A `test-*.sh` ON PURPOSE. scripts/run-tests.sh finds its suites by
# glob and every push runs them, and a push must not open a window on Dan's
# screen. This is run deliberately: after a build, or by hand. Its LOGIC is
# covered by scripts/test-smoke-launch.sh, which stages every outcome through the
# seams below and launches nothing.
#
# IT NEVER ACTS ON A PROCESS IT DID NOT START. If an instance is already running
# it refuses, rather than quitting whatever it found. A lookup by app NAME has
# quit a live app in this estate before, so the instance is identified by PID
# resolved from the built product's own executable path, and the only PID ever
# quit is one that appeared after this script launched it.
#
# IT WAITS ON CONDITIONS, never on a fixed sleep (L290). The poll interval and
# the deadline are seams from the day this was written, because a hard coded
# delay makes every test that crosses this loop wait for real (L524).
#
#   0  it opened, showed exactly one window, was still alive, and quit
#   1  it did not open, exited, showed no window, or showed more than one
#   2  nothing could be learned: no built product, or one was already running
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${OVATION_SMOKE_CONFIGURATION:-Debug}"
POLL="${OVATION_SMOKE_POLL:-0.25}"
TIMEOUT="${OVATION_SMOKE_TIMEOUT:-30}"

cannot_measure() {
    echo "CANNOT MEASURE: $1"
    [ "${2:-}" = "" ] || echo "    $2"
    echo "    Nothing was learned about whether the app opens. This is not a pass."
    exit 2
}
failed() {
    echo "LAUNCH FAILED: $1"
    [ "${2:-}" = "" ] || echo "    $2"
    exit 1
}

# The built product. Asked with the same scheme a build uses, because querying by
# target alone resolves a different location than a scheme build writes to, and
# the path would be correct-looking and empty (L156).
if [ -n "${OVATION_SMOKE_APP:-}" ]; then
    APP="$OVATION_SMOKE_APP"
else
    APP="$(xcodebuild -project "${REPO_ROOT}/Ovation.xcodeproj" -scheme Ovation \
        -configuration "$CONFIGURATION" -destination 'platform=macOS' \
        -showBuildSettings 2>/dev/null \
        | awk '$1 == "BUILT_PRODUCTS_DIR" && $2 == "=" { print $3; exit }')/Ovation.app"
fi

BUILD_IT="xcodebuild -project Ovation.xcodeproj -scheme Ovation -configuration ${CONFIGURATION} -destination 'platform=macOS' build"
[ -d "$APP" ] || cannot_measure "there is no ${CONFIGURATION} product at ${APP}" "build it first: ${BUILD_IT}"

EXE="${APP}/Contents/MacOS/Ovation"
[ -f "$EXE" ] || cannot_measure "the ${CONFIGURATION} bundle has no executable inside it" "rebuild it: ${BUILD_IT}"

# BY EXECUTABLE PATH, never by name. Two copies of an app called the same thing
# can be running at once, and the wrong one has been acted on before.
PIDS_CMD="${OVATION_SMOKE_PIDS_CMD:-pgrep -f ^${EXE}$}"
LAUNCH_CMD="${OVATION_SMOKE_LAUNCH_CMD:-open -a ${APP}}"
WINDOWS_CMD="${OVATION_SMOKE_WINDOWS_CMD:-${REPO_ROOT}/scripts/lib/window-count.sh}"
QUIT_CMD="${OVATION_SMOKE_QUIT_CMD:-${REPO_ROOT}/scripts/lib/quit-pid.sh}"

running_pids() { bash -c "$PIDS_CMD" 2>/dev/null | tr -d ' ' | grep -E '^[0-9]+$' || true; }

EXISTING="$(running_pids)"
if [ -n "$EXISTING" ]; then
    cannot_measure "an instance is already running at ${EXE}" \
        "this refuses rather than acting on a process it did not start; quit it and run again"
fi

echo "Launching the ${CONFIGURATION} build at ${APP}"
bash -c "$LAUNCH_CMD" >/dev/null 2>&1 || true

# Wait for it to APPEAR. Polled, never slept blind.
elapsed=0
PID=""
while :; do
    PID="$(running_pids | head -1)"
    [ -n "$PID" ] && break
    elapsed=$((elapsed+1))
    if [ "$elapsed" -gt "$((TIMEOUT * 4))" ]; then
        failed "the app never started" \
            "no process appeared at ${EXE} within ${TIMEOUT}s"
    fi
    sleep "$POLL"
done

echo "It started as pid ${PID}. Waiting for its window."

quit_it() { bash -c "$QUIT_CMD $PID" >/dev/null 2>&1 || true; }

# Wait for exactly one window, re-checking on every poll that it is still alive.
# An app that starts and then exits is a DIFFERENT failure from one that never
# started, and folding them would send somebody looking in the wrong place.
elapsed=0
WINDOWS=0
while :; do
    if [ -z "$(running_pids | grep -x "$PID" || true)" ]; then
        failed "the app started and then exited before showing a window" \
            "pid ${PID} is gone; this is a crash at launch, which is exactly what the unhosted test suite cannot see"
    fi
    WINDOWS="$(bash -c "$WINDOWS_CMD $PID" 2>/dev/null | tr -d ' \n')"
    case "$WINDOWS" in ''|*[!0-9]*) WINDOWS=0 ;; esac
    [ "$WINDOWS" -ge 1 ] && break
    elapsed=$((elapsed+1))
    if [ "$elapsed" -gt "$((TIMEOUT * 4))" ]; then
        quit_it
        failed "the app started and opened no window within ${TIMEOUT}s" \
            "pid ${PID} was alive throughout, so it is running and showing nothing"
    fi
    sleep "$POLL"
done

if [ "$WINDOWS" -ne 1 ]; then
    quit_it
    failed "the app opened ${WINDOWS} windows, and Ovation is single window on purpose" \
        "PRD 41b and plan 1.13: a flag on shared state is presented once per surface, so a second window shows a second copy of every launch notice and dismissing one leaves the other standing"
fi

# Still alive after the window appeared, so this is not a flash and a crash.
if [ -z "$(running_pids | grep -x "$PID" || true)" ]; then
    failed "the app exited immediately after opening its window" "pid ${PID} is gone"
fi

quit_it

# Report whether it actually went, rather than assuming the quit worked.
elapsed=0
while [ -n "$(running_pids | grep -x "$PID" || true)" ]; do
    elapsed=$((elapsed+1))
    if [ "$elapsed" -gt "$((TIMEOUT * 4))" ]; then
        echo "PASS: the ${CONFIGURATION} build opened one window as pid ${PID}."
        echo "    It did NOT quit when asked, and is still running. That is worth"
        echo "    knowing, and it is not a launch failure."
        exit 0
    fi
    sleep "$POLL"
done

echo "PASS: the ${CONFIGURATION} build opened exactly one window and quit cleanly (pid ${PID})."
exit 0
