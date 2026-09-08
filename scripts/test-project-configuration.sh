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
harness_begin "project configuration tests" 24

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

# ---------------------------------------------------------------------------
# THE SIGNING RULES, ASSERTED FROM THE SETTINGS SIDE.
#
# ovation#26. scripts/test-built-bundle-identity.sh judges the BUILT bundles, so
# it is only ever as current as the last build: a configuration change made
# without a rebuild is invisible to it. Nothing asserted the settings themselves,
# so removing hardened runtime or pointing Release at the Debug entitlements went
# red nowhere until somebody happened to rebuild both configurations.
#
# THE TWO SIDES MUST STAY INDEPENDENT. One reads what the configuration SAYS and
# needs no build; the other reads what the toolchain PRODUCED. A guard whose two
# sides come from one reading can only prove that reading is self consistent,
# never that it is correct (L70), so these deliberately do not consult the
# bundle and the bundle suite deliberately does not consult these.
#
# An mtime comparison was tried first as the cover for staleness and MEASURED to
# fail in both directions; see the note in test-built-bundle-identity.sh. This is
# the honest cover instead.

# 1. HARDENED RUNTIME, on both. Without it the entitlement check below is
#    meaningless, because the runtime is what makes an entitlement a restriction
#    rather than a note.
check "Release declares the hardened runtime" \
    "$(setting Release ENABLE_HARDENED_RUNTIME)" "YES"
check "Debug declares the hardened runtime too" \
    "$(setting Debug ENABLE_HARDENED_RUNTIME)" "YES"

# 2. THE STABLE IDENTITY, and specifically NOT "-", which is ad hoc.
#
# Ad hoc signing mints a NEW code identity on every install and macOS keys folder
# permission grants to that identity, so an ad hoc build re-asks for access
# already granted after every rebuild. PRD 5.29 has Ovation writing dated backups
# to a folder Dan chooses, and those backups are the only copy of a seven year
# tax record (ovation#9).
for CONFIG in Release Debug; do
    check "$CONFIG signs with Ovation's own stable identity, not ad hoc" \
        "$(setting "$CONFIG" CODE_SIGN_IDENTITY)" "Ovation Local Signing"
done

# 3. BASE ENTITLEMENT INJECTION OFF, on both, and this is the setting whose
#    absence produced the real defect.
#
# An empty entitlements FILE was tried first and changed nothing: Xcode injects a
# base set on top of whatever the file says whenever it believes it is signing
# for development, and a self signed identity with no provisioning profile looks
# exactly like one. The file and this flag are ONE fact and both need asserting,
# because either alone reads as protection while protecting nothing (L188).
for CONFIG in Release Debug; do
    check "$CONFIG does not let Xcode inject its own base entitlements" \
        "$(setting "$CONFIG" CODE_SIGN_INJECT_BASE_ENTITLEMENTS)" "NO"
done

# 4. EACH CONFIGURATION POINTS AT ITS OWN FILE. Pointing Release at the Debug
#    file is a one word change that ships a debuggable shipping build.
REL_ENTS="$(setting Release CODE_SIGN_ENTITLEMENTS)"
DBG_ENTS="$(setting Debug CODE_SIGN_ENTITLEMENTS)"
check "Release points at the shipping entitlements file" \
    "$REL_ENTS" "Ovation/Ovation.entitlements"
check "Debug points at its own entitlements file" \
    "$DBG_ENTS" "Ovation/Ovation-Debug.entitlements"
check "and the two are genuinely different files" \
    "$([ "$REL_ENTS" != "$DBG_ENTS" ] && echo different || echo same)" "different"

# 5. AND WHAT THOSE FILES ACTUALLY SAY.
#
# Read by CONVERTING them rather than with `plutil -lint`, which reports
# "Unexpected character {" on JSON that plutil -extract reads without complaint,
# measured 2026-09-06. These are XML plists so lint would work, but the two
# readers are kept the same across this repository so nobody has to remember
# which file type takes which.
readable_plist() { plutil -convert xml1 -o /dev/null -- "$1" >/dev/null 2>&1; }
grants_debugger() {
    # Prints yes when the file grants get-task-allow, no when it does not.
    #
    # THE DOTS ARE ESCAPED, and that is not decoration. `plutil -extract` treats
    # `.` as a key path SEPARATOR, so the unescaped key is read as four nested
    # levels (com, then apple, then security, then get-task-allow) and reports
    # "invalid key path" on a file that plainly contains the key. Written
    # unescaped first and caught by this very assertion going red against the
    # Debug file on 2026-09-06: the file grants it, the built bundle carries it,
    # and only the reader was wrong. Unnoticed, it would have reported the
    # SHIPPING file as safe for the same wrong reason, which is the direction
    # that never gets investigated.
    if [ "$(plutil -extract 'com\.apple\.security\.get-task-allow' raw -o - "$1" 2>/dev/null)" = "true" ]; then
        echo yes
    else
        echo no
    fi
}

check "the shipping entitlements file is there and parses" \
    "$([ -f "$REL_ENTS" ] && readable_plist "$REL_ENTS" && echo readable || echo "missing-or-unreadable")" "readable"
check "the debug entitlements file is there and parses" \
    "$([ -f "$DBG_ENTS" ] && readable_plist "$DBG_ENTS" && echo readable || echo "missing-or-unreadable")" "readable"

# `com.apple.security.get-task-allow` lets ANY process attach a debugger and read
# the app's memory. Ovation will hold Gmail refresh tokens carrying send and
# modify rights on Dan's mailbox, and seven years of tax records.
check "the shipping entitlements file does NOT let a debugger attach" \
    "$(grants_debugger "$REL_ENTS")" "no"
# And the inverse is a real defect too: without it Xcode cannot attach and
# debugging is silently broken.
check "the debug entitlements file DOES, or Xcode cannot debug the app" \
    "$(grants_debugger "$DBG_ENTS")" "yes"

# 6. NO SEPARATE DEBUG DYLIB, and this one is a fix rather than a preference.
#
# Xcode's default splits Debug's code into `Ovation.debug.dylib` so previews and
# hot reload can work. Under the hardened runtime a loaded library must validate
# against the loading process's Team ID, and the self signed identity from
# ovation#9 has none, so dyld refused the dylib and the Debug build did not launch
# AT ALL from 2026-09-06 until ovation#30.
#
# Nothing caught it because each of the three settings is individually correct:
# both binaries were signed by the same identity, both reported
# `TeamIdentifier=not set`, and the built bundle suite passed throughout. It was
# found the first time anything launched the app (L417).
#
# Asserted from the settings rather than left to the launch smoke check, because
# that check is run deliberately and this must go red on a push.
# ovation#84. THE KEY THAT MUST STAY ABSENT, asserted rather than only explained
# in a comment. `LSMultipleInstancesProhibited` is how a second running copy
# would be refused BY THE SYSTEM, and plan 1.3 says explicitly not to use it: a
# running Debug app holding that lock makes the xctest host fail to launch, so
# the suite dies AFTER a full build, and Overture's own runner records that the
# misdiagnosis "sent hours of elimination in the wrong direction".
#
# The refusal lives in application code instead (Ovation/App/SecondInstance.swift),
# which is Downbeat's pattern rather than a workaround. A constraint recorded only
# as a comment beside the code is enforced by nothing while reading as binding
# (L407), and the cost of somebody adding this key is a build's worth of
# elimination in the wrong direction.
check "the project declares no LSMultipleInstancesProhibited anywhere" \
    "$(grep -c 'LSMultipleInstancesProhibited:' project.yml)" "0"
check "and the generated project carries none either" \
    "$(grep -c 'LSMultipleInstancesProhibited' Ovation.xcodeproj/project.pbxproj 2>/dev/null \
        || true)" "0"

check "Debug builds no separate debug dylib, which hardened runtime cannot load" \
    "$(setting Debug ENABLE_DEBUG_DYLIB)" "NO"

harness_end
