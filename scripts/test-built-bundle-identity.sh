#!/bin/bash
# Assert what the BUILT PRODUCT actually is, not what the configuration asked
# for.
#
# A value your configuration SETS is only in force if nothing downstream
# recomputes it. A framework or toolchain deriving the same value from other
# inputs overwrites yours silently, and the line goes on reading as protection
# while protecting nothing (L188). So every assertion here reads the signed
# bundle on disk.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"

CONFIG="${1:-Debug}"
harness_begin "built bundle identity tests ($CONFIG)" 3
# Ask with the SAME scheme the build used. Querying by target alone resolves a
# different build location than a scheme build writes to, so the path would be
# correct-looking and empty, and this check would refuse on every run for a
# reason that has nothing to do with the bundle (L156).
APP="$(xcodebuild -project Ovation.xcodeproj -scheme Ovation -configuration "$CONFIG" \
    -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
    | awk '$1 == "BUILT_PRODUCTS_DIR" && $2 == "=" { print $3; exit }')/Ovation.app"

if [ ! -d "$APP" ]; then
    harness_cannot_measure "no built product at $APP" \
        "build it first: xcodebuild -project Ovation.xcodeproj -scheme Ovation -destination 'platform=macOS' build"
fi

SIG="$(codesign -d --verbose=2 "$APP" 2>&1)"

# The Debug suffix is the entire isolation mechanism behind plan 1.1: macOS keys
# the data directory, the TCC grants and the Gmail login to this string. Assert
# it on the SIGNED bundle, because that is the identity the system will use.
IDENT="$(printf '%s' "$SIG" | awk -F= '/^Identifier=/ { print $2 }')"
EXPECTED_ID="com.danwright.ovation"
[ "$CONFIG" = "Debug" ] && EXPECTED_ID="com.danwright.ovation.debug"
check "the signed bundle carries the $CONFIG identity" "$IDENT" "$EXPECTED_ID"

# Hardened runtime, asserted PER CONFIGURATION, because the two differ and only
# one of them ships.
#
# Measured 2026-09-05 on the signed bundles, not on the build setting, because a
# value the configuration sets is only in force if nothing downstream recomputes
# it (L188):
#
#     Release  flags=0x10002(adhoc,runtime)   hardened runtime IS in force
#     Debug    flags=0x2(adhoc)               it is not
#
# The Debug case is deliberate and is not a defect: hardened runtime blocks a
# debugger attaching, so Xcode drops it for a Debug ad hoc build. Asserting it
# there would be asserting that debugging is broken.
#
# What ships is Release, and Release has it. Both are pinned here so that a
# change to either is a deliberate, visible edit rather than something noticed
# later on a signed artifact nobody looked at.
if [ "$CONFIG" = "Release" ]; then
    check "hardened runtime is in force on the configuration that ships" \
        "$(printf '%s' "$SIG" | grep -c 'runtime')" "1"
else
    check "hardened runtime is off in Debug, deliberately, so a debugger can attach" \
        "$(printf '%s' "$SIG" | grep -c 'runtime')" "0"
fi

# Signing is still ad hoc in BOTH, which is what ovation#9 replaces with a stable
# self signed identity. That issue is about FOLDER GRANTS, not about hardened
# runtime: an ad hoc build mints a new code identity on every install, and TCC
# grants are keyed to that identity, so a granted folder is re prompted after
# every rebuild. Plan 1.8 asks Dan for a backup folder, so #9 lands first.
#
# WHEN THIS GOES RED: that is ovation#9 having worked. Update it in the same
# commit that ships the identity (L373), rather than leaving a test asserting a
# world that no longer exists.
check "signing is still ad hoc, which ovation#9 replaces" \
    "$(printf '%s' "$SIG" | grep -c 'adhoc')" "2"

harness_end
