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
harness_begin "built bundle identity tests ($CONFIG)" 5
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

# THE SIGNING IDENTITY, now that ovation#9 has been run.
#
# INVERTED 2026-09-06, in the same change that consumed the old assertion (L373).
# This suite used to PIN ad hoc signing, deliberately, and said in its own
# comment that going red would mean ovation#9 had worked. Dan ran
# scripts/setup-signing.sh, "Ovation Local Signing" is in his login keychain
# alongside the three siblings' identities, and project.yml now points at it. A
# test left asserting the old world goes permanently red for a reason that looks
# exactly like a real defect.
#
# Why it matters, restated so nobody relaxes it later: ad hoc signing mints a NEW
# code identity on every install, and macOS keys folder permission grants to that
# identity. PRD 5.29 has Ovation writing backups to a folder Dan chooses, and
# plan 1.8 is where it first asks. A backup feature that re-asks after every
# rebuild is one he stops trusting, and those backups are the only copy of a
# seven year tax record.
check "the bundle is signed with Ovation's own stable identity" \
    "$(printf '%s' "$SIG" | grep -c 'Authority=Ovation Local Signing')" "1"
check "and it is NOT ad hoc signed any more" \
    "$(printf '%s' "$SIG" | grep -c 'Signature=adhoc')" "0"

# HARDENED RUNTIME, RE-MEASURED AFTER THE IDENTITY CHANGE rather than assumed to
# be unaffected by it, which is exactly what the previous version of this suite
# said to do (L188). It changed: under ad hoc signing Debug had no runtime flag
# at all, and with a real identity BOTH configurations carry it.
check "hardened runtime is in force" \
    "$(printf '%s' "$SIG" | grep -c 'runtime')" "1"

# AND THE ENTITLEMENT THAT DECIDES WHETHER IT MEANS ANYTHING.
#
# `com.apple.security.get-task-allow` lets any process attach a debugger and read
# the app's memory. With it present, hardened runtime is declared and its main
# protection is switched off, so reading the flag alone says the app is protected
# when it is not (L188).
#
# Debug NEEDS it, or Xcode cannot attach and debugging is broken.
# Release MUST NOT HAVE IT. Ovation will hold Gmail refresh tokens carrying send
# and modify rights on Dan's mailbox, and seven years of tax records.
#
# Found 2026-09-06, the moment the stable identity landed: Xcode was adding it to
# BOTH, because a self signed identity with no provisioning profile is treated as
# a development signing setup.
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - 2>/dev/null)"
if [ "$CONFIG" = "Release" ]; then
    check "the shipping build does NOT let a debugger attach" \
        "$(printf '%s' "$ENTS" | grep -c 'get-task-allow')" "0"
else
    check "the debug build DOES let a debugger attach, or Xcode cannot debug it" \
        "$(printf '%s' "$ENTS" | grep -c 'get-task-allow')" "1"
fi

harness_end
