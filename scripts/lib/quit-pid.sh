#!/bin/bash
# Ask the process with this pid to quit, then let the caller confirm it went.
#
# BY PID, and politely first. `kill -TERM` lets a SwiftUI app run its normal
# termination; this deliberately does NOT escalate to -9, because a smoke check
# that force kills would hide an app that refuses to quit, which is itself worth
# knowing.
set -uo pipefail
PID="${1:-}"
[ -n "$PID" ] || exit 0
kill -TERM "$PID" 2>/dev/null || true
