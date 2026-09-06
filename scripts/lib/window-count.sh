#!/bin/bash
# How many windows does the process with this pid have open?
#
# BY PID, never by application name: two copies of an app with the same name can
# be running, and the wrong one has been acted on in this estate before.
#
# Quartz would be the direct way to ask, and pyobjc is not installed on this Mac
# (measured 2026-09-06), so this asks System Events, which needs Automation
# permission. A refusal there prints nothing and the caller reads that as zero
# windows, which is the safe direction: it reports a launch as not having shown a
# window rather than passing one that showed none.
set -uo pipefail
PID="${1:-}"
[ -n "$PID" ] || { echo 0; exit 0; }
osascript -e "tell application \"System Events\" to count windows of (first process whose unix id is ${PID})" 2>/dev/null || echo 0
