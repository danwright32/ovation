#!/bin/bash
# Build one configuration of the app. Split out so scripts/build-products.sh can
# be driven with a stand-in, and so the real xcodebuild invocation lives in one
# place rather than being written out per caller.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="${1:-}"
[ -n "$CONFIG" ] || { echo "build-one-configuration.sh needs a configuration" >&2; exit 2; }
xcodebuild -project "${REPO_ROOT}/Ovation.xcodeproj" -scheme Ovation \
    -configuration "$CONFIG" -destination 'platform=macOS' build
