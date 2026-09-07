#!/bin/bash
# The judgements Ovation makes about the ICON inside a built, signed bundle.
# One implementation, answering for every configuration.
#
# ovation#18. project.yml set ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon while
# no asset catalog existed anywhere in the repository. The build did not warn,
# so the only symptom was a blank generic icon in the Dock, in the app switcher
# and in Finder. A configuration line that claims something untrue, enforced by
# nothing, is the defect class L407 is about.
#
# WHY THIS READS THE BUILT PRODUCT AND NOT THE BUILD SETTING. Reading the
# setting would not have caught it: the setting was present and correct the
# whole time while the thing it named did not exist (L188). Only the compiled
# bundle can answer whether an icon actually shipped.
#
# WHY THERE ARE THREE JUDGEMENTS AND NOT ONE. Each of the three ways this can be
# broken leaves the other two looking correct, and each has a different cause and
# a different fix, so each gets its own message rather than one shared verdict
# (L11).
#
#   1. The catalog compiled but stamped no icon name into Info.plist, so
#      LaunchServices has nothing to look up.
#   2. Info.plist names an icon file that is not in the bundle. The name reads
#      as correct in every plist dump; only the filesystem disagrees.
#   3. Both are present but the compiled catalog holds no large representation,
#      which is what a placeholder or a half written .appiconset produces. macOS
#      falls back to a blurred upscale, which looks like a rendering problem
#      rather than a missing asset, so nothing about the symptom points at the
#      cause.
#
# JUDGEMENT 3 READS Assets.car, NOT AppIcon.icns, AND THAT WAS MEASURED RATHER
# THAN ASSUMED. The obvious reading is the largest representation inside the
# .icns, and it is WRONG: it reports 256 on a completely healthy bundle. Checked
# on 2026-09-07 against Safari, Notes, Downbeat and Overture, every one of them
# reports `sips -g pixelWidth` of 256 on its AppIcon.icns while carrying a
# multi megabyte Assets.car beside it. The .icns is a compatibility fallback
# that modern actool caps; the artwork macOS actually draws lives in the
# compiled catalog. A guard must assert the quantity it exists to protect, never
# a proxy for it (L63), and this proxy fails in the RED direction on every
# correct build, which is the kind of guard people learn to skip (L378).
#
# THE FUNCTION TAKES MEASUREMENTS, NOT A PATH. It is handed the three readings
# rather than the bundle, so scripts/test-bundle-icon-checks.sh can stage every
# failure case without a build. The real suite does the reading and feeds it
# genuine values on every run, so the interface is exercised for real and not
# only against text written beside the test (L52).
#
# Usage, from a suite that has already sourced the test harness:
#
#     . "$(dirname "$0")/lib/bundle-icon-checks.sh"
#     bundle_icon_checks Release "$icon_name" "$icns_present" "$largest_px"
#
# It runs exactly `bundle_icon_checks_count` assertions through the harness's own
# `check`, so a caller declares its total as (number of configurations) times
# that count and the harness refuses a short run (L288).

# The macOS icon Ovation ships is drawn on a 1024 point canvas, which is the
# largest representation scripts/build-app-icon.sh produces and the one Finder's
# Get Info panel actually uses. Anything smaller as the LARGEST representation
# in the compiled catalog means the big sizes were never produced.
BUNDLE_ICON_LARGEST_PX=1024

# The name is not a free string. It is the value ASSETCATALOG_COMPILER_APPICON_NAME
# is set to in project.yml, and the two must agree or the catalog compiles an
# icon nothing looks up. Named here once so the suite and this judgement cannot
# drift apart (L70).
BUNDLE_ICON_NAME=AppIcon

# How many assertions one call makes. A caller derives its declared total from
# this rather than writing the number twice, because two numbers that must agree
# drift and the one that drifts is the declaration nobody re-reads (L70).
bundle_icon_checks_count() { printf '3'; }

bundle_icon_checks() {
    local config="$1" icon_name="$2" icns_present="$3" largest_px="$4"
    local i

    # An unknown configuration is REFUSED, not quietly judged as one of the
    # known ones. Defaulting is the defect ovation#25 removed from the sibling
    # library, so nothing here carries one (L320). It still runs the declared
    # number of assertions, so a caller's count stays honest while every one of
    # them says what went wrong (L11).
    case "$config" in
        Release|Debug) ;;
        *)
            for i in 1 2 3; do
                check "configuration '$config' is not one this suite can judge" \
                    "unknown configuration" "Debug or Release"
            done
            return 1
            ;;
    esac

    # 1. THE BUNDLE NAMES AN ICON AT ALL.
    #
    # Read off the BUILT Info.plist, never Ovation/Info.plist. The source plist
    # does not carry this key and never should: the asset catalog compiler
    # stamps CFBundleIconFile in during the build, from the catalog it actually
    # compiled. That is precisely why a source-side check cannot see this
    # failure (L188).
    check "the $config bundle names an app icon" \
        "$icon_name" "$BUNDLE_ICON_NAME"

    # 2. AND THE FILE IT NAMES IS ACTUALLY IN THERE.
    #
    # These are two different failures with two different fixes. A plist naming
    # a file that is not in Contents/Resources reads as correct in every dump of
    # the plist, and the bundle is a blank icon in the Dock (L100).
    check "and the $config bundle actually contains that icon file" \
        "$icns_present" "yes"

    # 3. AND THE COMPILED CATALOG HOLDS THE FULL SIZE ARTWORK.
    #
    # A catalog carrying only small representations passes both checks above and
    # still looks wrong: macOS upscales the largest it can find, so Get Info and
    # the large Finder sizes show a soft, blurred icon. That symptom reads as a
    # bad export rather than as a missing asset, so it is asserted rather than
    # left to be noticed (L11).
    #
    # Measured out of Assets.car, for the reason recorded in this file's header:
    # the same reading taken off AppIcon.icns says 256 on every healthy Mac app
    # ever shipped, Apple's included.
    check "and the $config catalog carries the full ${BUNDLE_ICON_LARGEST_PX}px artwork" \
        "$largest_px" "$BUNDLE_ICON_LARGEST_PX"
}
