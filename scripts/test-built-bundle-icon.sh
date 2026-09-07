#!/bin/bash
# Assert that the BUILT PRODUCTS actually carry Ovation's app icon, for EVERY
# configuration Ovation ships.
#
# ovation#18. project.yml:126 has set ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
# since the project was generated, and no asset catalog existed anywhere in the
# repository. The build did not warn. Nothing in the test suite looked. The only
# symptom was a blank generic icon in the Dock, in the app switcher and in
# Finder, which reads as something not finished yet rather than as a setting
# pointing at nothing.
#
# WHY THIS IS A SEPARATE SUITE FROM scripts/test-built-bundle-identity.sh.
# ovation#18's recorded direction was to add these assertions to that suite,
# which already reads the built product. That was not done, and the reason is
# the rule that suite's own header cites: a check's NAME is not a statement of
# its coverage, and a gap stays invisible precisely because a green tick with
# the right name is already on the board (L400). "Built bundle identity tests"
# names the security properties of the signature. Folding an icon assertion into
# it makes that name less true of what it runs, which is the direction that
# defect travels in. So the judgement lives beside it under its own name, and
# the part both suites genuinely share, finding the built product and refusing
# when it is not there, was extracted to scripts/lib/built-product.sh rather
# than copied (L370).
#
# THIS SUITE TAKES NO ARGUMENT. scripts/run-tests.sh finds its suites by glob
# and can only invoke each one ONE way, so a suite that takes a parameter runs
# for ever in its default mode while its other cases never run and its name
# still appears in every green report (L413). scripts/test-run-tests.sh refuses
# any suite that reintroduces one.
#
# The judgements themselves live in scripts/lib/bundle-icon-checks.sh, one
# implementation for both configurations rather than a second copy for Release
# (L370), and scripts/test-bundle-icon-checks.sh drives that implementation
# through its failure cases, which this suite can never do: once the icon ships,
# both bundles on this machine are correct, and a guard only ever seen to pass
# has not been seen to work (L1).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
. "$(dirname "$0")/lib/built-product.sh"
. "$(dirname "$0")/lib/bundle-icon-checks.sh"

CONFIGURATIONS="Debug Release"

# The declared total is DERIVED, never written out a second time. Two numbers
# that have to agree drift, and the one that drifts is the declaration nobody
# re-reads (L70). A short run is refused by the harness before any verdict is
# printed (L288), so this is what keeps a silently dropped configuration from
# reading as a pass.
NCONFIGS=0
for _c in $CONFIGURATIONS; do NCONFIGS=$((NCONFIGS+1)); done
harness_begin "built bundle icon tests (${CONFIGURATIONS// /, })" \
    "$((NCONFIGS * $(bundle_icon_checks_count)))"

require_target "project.yml"

# EVERY configuration must be present BEFORE any assertion runs, so that a
# missing Debug product cannot hide whatever Release would have said.
for CONFIG in $CONFIGURATIONS; do
    built_product_require "$CONFIG" "$(built_product_path "$CONFIG")/Ovation.app"
done

# ---------------------------------------------------------------------------
# WHAT THIS SUITE DOES NOT COVER, stated rather than left to be assumed from its
# name (L400).
#
# It judges the bundles ON DISK, so it is only ever as current as the last
# build. An asset catalog deleted without a rebuild is invisible here. That gap
# is the same one scripts/test-built-bundle-identity.sh records, and it has the
# same reason: every mtime based freshness proxy measured for it was red on a
# healthy tree in both directions (L414).
#
# It says nothing about what the icon LOOKS like. It cannot: a check that
# measures whether something was drawn is answered by whatever the renderer
# substituted for content it could not draw (L115). Whether the artwork is the
# right artwork is settled by Dan looking at it, and the record of that decision
# is docs/design/README.md, not this file.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Now judge them. Every configuration, through one implementation.
#
# All three readings come off the built bundle. None of them reads a build
# setting: the setting was present and correct for the entire time the defect
# existed, so a check that read it would have passed throughout (L188).
# ---------------------------------------------------------------------------
for CONFIG in $CONFIGURATIONS; do
    APP="$(built_product_path "$CONFIG")/Ovation.app"

    # The name the asset catalog compiler stamped in, if it stamped one. An
    # absent key reads as the empty string, which is a value the judgement
    # refuses, rather than as this reading having failed.
    ICON_NAME="$(plutil -extract CFBundleIconFile raw -o - "$APP/Contents/Info.plist" 2>/dev/null)"

    # Whether the file that name points at is actually in the bundle. macOS
    # tolerates the name with or without the extension, so both are accepted
    # here; what is being asserted is that SOMETHING is there to be loaded.
    ICNS_PRESENT=no
    for _candidate in "$APP/Contents/Resources/$ICON_NAME" "$APP/Contents/Resources/$ICON_NAME.icns"; do
        if [ -n "$ICON_NAME" ] && [ -f "$_candidate" ]; then
            ICNS_PRESENT=yes
            ICNS_PATH="$_candidate"
            break
        fi
    done

    # The largest AppIcon representation the COMPILED CATALOG holds.
    #
    # NOT the largest inside AppIcon.icns. That reading was written first and
    # measured, and it reports 256 on a completely healthy bundle: Safari,
    # Notes, Downbeat and Overture all do, because modern actool caps the .icns
    # as a compatibility fallback and puts the real artwork in Assets.car. A
    # guard must assert the quantity it protects rather than a proxy for it
    # (L63), and that proxy was red on every correct build.
    #
    # A bundle with no catalog has nothing to measure, so this stays 0 rather
    # than inheriting the previous configuration's reading, which would let a
    # broken Release be judged on Debug's artwork (L98).
    LARGEST_PX=0
    CAR="$APP/Contents/Resources/Assets.car"
    if [ -f "$CAR" ]; then
        # assetutil prints one record per rendition. Reading the maximum
        # PixelWidth of the AppIcon renditions answers exactly the question
        # being asked, rather than the count of them, which a half written
        # catalog also satisfies.
        LARGEST_PX="$(xcrun --sdk macosx assetutil --info "$CAR" 2>/dev/null \
            | python3 -c '
import json, sys
try:
    records = json.loads(sys.stdin.read())
except Exception:
    print(0); raise SystemExit
widths = [
    r["PixelWidth"] for r in records
    if isinstance(r, dict)
    and r.get("AssetType") == "Icon Image"
    and r.get("Name") == "AppIcon"
    and "PixelWidth" in r
]
print(max(widths) if widths else 0)
')"
        [ -n "$LARGEST_PX" ] || LARGEST_PX=0
    fi

    bundle_icon_checks "$CONFIG" "$ICON_NAME" "$ICNS_PRESENT" "$LARGEST_PX"
done

harness_end
