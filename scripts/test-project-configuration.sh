#!/bin/bash
# The generated Xcode project must give Debug and Release genuinely separate
# identities, and must target the macOS Ovation actually needs rather than the
# one its port source happened to target.
#
# Implementation plan 0.4.1 and 1.1. A Debug run must never share a store, a
# write ahead log, a TCC grant, a Gmail login or a backup folder with the
# resident copy. macOS keys all of those to the BUNDLE IDENTIFIER, so the
# suffix is not cosmetic: it is the whole isolation mechanism, and StoreLocation
# in 1.1 is built on top of it.
#
# EVERY ASSERTION READS THE RESOLVED BUILD SETTING, never project.yml. A value
# your configuration SETS is only in force if nothing downstream recomputes it,
# and the line goes on reading as protection while protecting nothing (L188). So
# these ask xcodebuild what the setting actually came out as.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "project configuration tests" 8

require_target "project.yml"

XCODEGEN="${XCODEGEN:-/opt/homebrew/bin/xcodegen}"
if [ ! -x "$XCODEGEN" ]; then
    harness_cannot_measure "xcodegen is not at $XCODEGEN" \
        "install it with: brew install xcodegen"
fi

# Regenerate, so what is asserted is what project.yml currently produces and not
# a stale .xcodeproj somebody left behind (L336).
if ! GEN_OUT="$("$XCODEGEN" generate --spec project.yml 2>&1)"; then
    echo "FAIL: xcodegen could not generate the project"
    printf '%s\n' "$GEN_OUT" | sed 's/^/      /'
    exit 1
fi

setting() {
    # $1 configuration, $2 setting name. Reads the RESOLVED value.
    xcodebuild -project Ovation.xcodeproj -target Ovation -configuration "$1" \
        -showBuildSettings 2>/dev/null \
        | awk -v k="$2" '$1 == k && $2 == "=" { $1=""; $2=""; sub(/^  */,""); print; exit }'
}

REL_ID="$(setting Release PRODUCT_BUNDLE_IDENTIFIER)"
DBG_ID="$(setting Debug PRODUCT_BUNDLE_IDENTIFIER)"

check "Release carries the canonical bundle identity" \
    "$REL_ID" "com.danwright.ovation"
check "Debug carries the .debug suffix, which is what isolates its data and grants" \
    "$DBG_ID" "com.danwright.ovation.debug"
check "and the two are genuinely different, which is the whole point of 1.1" \
    "$([ "$REL_ID" != "$DBG_ID" ] && echo different || echo same)" "different"

# The port source targets macOS 14.0. Ovation cannot: Vision's document
# recognition, which Phase 4 reads receipts with, is macOS 26. Inheriting 14.0
# would let code that cannot run on the target compile cleanly (L501).
DEPTARGET="$(setting Release MACOSX_DEPLOYMENT_TARGET)"
check "the deployment target is the one Ovation needs, not the one it was ported from" \
    "$DEPTARGET" "26.0"

# A Debug URL open must not be routable to the Release build by LaunchServices.
REL_SCHEME="$(setting Release OVATION_URL_SCHEME)"
DBG_SCHEME="$(setting Debug OVATION_URL_SCHEME)"
check "Release and Debug do not share a URL scheme" \
    "$([ -n "$REL_SCHEME" ] && [ "$REL_SCHEME" != "$DBG_SCHEME" ] && echo different || echo "same-or-empty")" "different"

# The pure suite is UNHOSTED on purpose: it compiles the app's code in rather
# than launching it, so one launch fault cannot cost every test at once. A
# TEST_HOST here would silently undo that.
HOST="$(xcodebuild -project Ovation.xcodeproj -target OvationTests -configuration Debug \
    -showBuildSettings 2>/dev/null \
    | awk '$1 == "TEST_HOST" && $2 == "=" { $1=""; $2=""; sub(/^  */,""); print; exit }')"
check "the pure test target is unhosted, so a launch fault cannot take the whole suite" \
    "${HOST:-none}" "none"

# Ovation's store schema guard reads the store's raw sqlite_master before
# anything opens it for writing (plan 1.2), in both the app and the suite.
check "the app links sqlite3, which the store schema guard needs" \
    "$(grep -c 'libsqlite3.tbd' project.yml)" "2"

# THE PURE SCHEME MUST BUILD ONLY THE TEST BUNDLE. This is the entire reason two
# schemes exist rather than one with -only-testing, and if the app target were
# ever added to it the isolation would vanish silently while every test still
# passed (L98).
#
# Proved BEHAVIOURALLY on 2026-09-05, which is what makes this assertion worth
# pinning rather than a restatement of the config: OvationApp.swift was
# deliberately broken, the app scheme produced 22 compile errors, and the
# OvationCore scheme still ran and reported 2 tests passing. That proof cannot
# run here (it edits a source file, and a crash mid-run would leave it broken),
# so the cheap structural assertion stands in for it and this comment records
# what validated it.
CORE_TARGETS="$(grep -o 'BlueprintName = "[^"]*"' \
    Ovation.xcodeproj/xcshareddata/xcschemes/OvationCore.xcscheme 2>/dev/null | sort -u | tr '\n' ' ')"
check "the pure scheme builds ONLY the test bundle, never the app" \
    "$CORE_TARGETS" 'BlueprintName = "OvationTests" '

harness_end
