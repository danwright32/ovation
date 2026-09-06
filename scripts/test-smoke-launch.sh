#!/bin/bash
# The launch smoke check must tell apart every way a launch can fail, and must
# never act on a process it did not start.
#
# ovation#20. Nothing verifies that Ovation opens. It compiles, and its test
# suite is deliberately built so that it never launches the app: proved on
# 2026-09-05 when OvationApp.swift was broken on purpose, the app scheme produced
# 22 compile errors, and the OvationCore scheme still ran and reported 2 tests
# passing. That design is right, and its cost is that a fault stopping the app
# opening is invisible to every check here (L3).
#
# NOTHING IN THIS SUITE LAUNCHES ANYTHING. The launch, the process lookup, the
# window count and the quit are all seams, so every outcome is staged instantly
# and the suite never opens a window, never steals focus, and cannot leave a
# stray process behind (L2, L291). The real defaults are exercised by running
# scripts/smoke-launch.sh itself, which is a deliberate act rather than something
# a push does.
#
# THE POLL INTERVAL IS A SEAM FROM THE DAY IT IS WRITTEN, not a retrofit. A hard
# coded delay makes every test that crosses this loop wait for real (L524, L290),
# and the cases below cross it constantly.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "launch smoke check tests" 18

TARGET="scripts/smoke-launch.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A staged world, driven by files rather than by real processes.
#
#   pids     one line per running instance, empty for none
#   windows  the window count the running instance reports
#   quit     what the quit command was asked to act on
#   dieafter when set, the instance disappears after that many pid lookups
STATE="$WORK/state"; mkdir -p "$STATE"

reset_state() {
    : > "$STATE/pids"; : > "$STATE/windows"; : > "$STATE/quit"; : > "$STATE/lookups"
    rm -f "$STATE/dieafter" "$STATE/launched"
}

cat > "$WORK/launch" <<'EOF'
#!/bin/bash
echo launched >> "$STATE/launched"
cat "$STATE/pids_on_launch" > "$STATE/pids" 2>/dev/null || true
EOF
cat > "$WORK/pids" <<'EOF'
#!/bin/bash
echo x >> "$STATE/lookups"
if [ -f "$STATE/dieafter" ]; then
    n="$(wc -l < "$STATE/lookups" | tr -d ' ')"
    if [ "$n" -gt "$(cat "$STATE/dieafter")" ]; then exit 0; fi
fi
cat "$STATE/pids" 2>/dev/null || true
EOF
cat > "$WORK/windows" <<'EOF'
#!/bin/bash
cat "$STATE/windows" 2>/dev/null || echo 0
EOF
# The body is INDENTED, and that is not a style choice. scripts/test-run-tests.sh
# refuses any suite that reads its own $1 at the top level, because the runner's
# glob can only invoke a suite one way (ovation#25). A stub written here with an
# unindented $1 trips that guard even though the $1 belongs to the stub, which is
# the same self-match that caught the offender fixture in that suite (L245).
cat > "$WORK/quit" <<'EOF'
#!/bin/bash
  echo "$1" >> "$STATE/quit"
  : > "$STATE/pids"
EOF
chmod +x "$WORK/launch" "$WORK/pids" "$WORK/windows" "$WORK/quit"

run_smoke() {
    STATE="$STATE" \
    OVATION_SMOKE_APP="$WORK/Fake.app" \
    OVATION_SMOKE_LAUNCH_CMD="$WORK/launch" \
    OVATION_SMOKE_PIDS_CMD="$WORK/pids" \
    OVATION_SMOKE_WINDOWS_CMD="$WORK/windows" \
    OVATION_SMOKE_QUIT_CMD="$WORK/quit" \
    OVATION_SMOKE_POLL="0.02" \
    OVATION_SMOKE_TIMEOUT="${TIMEOUT_OVERRIDE:-1}" \
        "./$TARGET" 2>&1
}
# ONE RUN PER SCENARIO. Written first as two calls, one for the output and one
# for the status, which made the staged world accumulate: the quit tally came
# back doubled and the failure was in this file rather than in the script under
# test. A scenario that has side effects must be driven once and asked twice.
smoke() { SMOKE_OUT="$(run_smoke)"; SMOKE_ST=$?; }
says() { if printf '%s' "$1" | grep -qiF "$2"; then echo yes; else echo no; fi; }

mkdir -p "$WORK/Fake.app/Contents/MacOS"; : > "$WORK/Fake.app/Contents/MacOS/Ovation"

# ---------------------------------------------------------------------------
# 1. CANNOT MEASURE. Nothing was learned about whether the app opens.
# ---------------------------------------------------------------------------
reset_state
SMOKE_OUT="$(OVATION_SMOKE_APP="$WORK/NotBuilt.app" \
    OVATION_SMOKE_LAUNCH_CMD="$WORK/launch" OVATION_SMOKE_PIDS_CMD="$WORK/pids" \
    OVATION_SMOKE_WINDOWS_CMD="$WORK/windows" OVATION_SMOKE_QUIT_CMD="$WORK/quit" \
    STATE="$STATE" "./$TARGET" 2>&1)"; SMOKE_ST=$?
check "with no built product it cannot be measured" "$SMOKE_ST" "2"
check "and it names the command that would build it" "$(says "$SMOKE_OUT" "xcodebuild")" "yes"
check "and it launched nothing" "$([ -f "$STATE/launched" ] && echo launched || echo no)" "no"

# ALREADY RUNNING. It refuses rather than acting on a process it did not start.
# Quitting one it found would be quitting Dan's running copy, which is exactly
# the mistake that once quit a live app in this estate.
reset_state
printf '4242\n' > "$STATE/pids"
smoke
check "an instance already running cannot be measured" "$SMOKE_ST" "2"
check "and it says one is already running" "$(says "$SMOKE_OUT" "already running")" "yes"
check "and it did not quit the process it found" \
    "$(wc -l < "$STATE/quit" | tr -d ' ')" "0"

# ---------------------------------------------------------------------------
# 2. THE LAUNCH FAILURES, each named, because they need different work (L11).
# ---------------------------------------------------------------------------
reset_state; : > "$STATE/pids_on_launch"
smoke
check "an app that never starts is a failure" "$SMOKE_ST" "1"
check "and it is reported as never having started" "$(says "$SMOKE_OUT" "never started")" "yes"

# Started, then gone before a window. A crash at launch, which is the exact
# fault the unhosted suite cannot see.
reset_state; printf '4242\n' > "$STATE/pids_on_launch"; printf '0\n' > "$STATE/windows"
printf '2\n' > "$STATE/dieafter"
smoke
check "an app that starts and then exits is a failure" "$SMOKE_ST" "1"
check "and that is NOT reported as never having started" \
    "$(says "$SMOKE_OUT" "never started")" "no"
check "it is reported as having exited" "$(says "$SMOKE_OUT" "exited")" "yes"

# Alive, no window. The process is up and nothing is on screen.
reset_state; printf '4242\n' > "$STATE/pids_on_launch"; printf '0\n' > "$STATE/windows"
smoke
check "an app that opens no window is a failure" "$SMOKE_ST" "1"
check "and it says no window appeared" "$(says "$SMOKE_OUT" "no window")" "yes"
check "and it still quit what it started, rather than leaving it running" \
    "$(grep -c '4242' "$STATE/quit")" "1"

# Two windows. PRD 41b and plan 1.13: a second window puts up a second copy of
# every launch notice, and dismissing one leaves the other standing (L238).
reset_state; printf '4242\n' > "$STATE/pids_on_launch"; printf '2\n' > "$STATE/windows"
smoke
check "more than one window is a failure" "$SMOKE_ST" "1"
check "and it says how many it found" "$(says "$SMOKE_OUT" "2 windows")" "yes"

# ---------------------------------------------------------------------------
# 3. THE PASS, and what it is allowed to rest on.
# ---------------------------------------------------------------------------
reset_state; printf '4242\n' > "$STATE/pids_on_launch"; printf '1\n' > "$STATE/windows"
smoke
check "one window, still alive, is a pass" "$SMOKE_ST" "0"
check "and it quit exactly the process it started, by that pid" \
    "$(tr -d ' \n' < "$STATE/quit")" "4242"

harness_end
