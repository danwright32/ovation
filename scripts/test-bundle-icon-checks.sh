#!/bin/bash
# The judgement the built bundle ICON suite makes, exercised WITHOUT a build.
#
# ovation#18. scripts/test-built-bundle-icon.sh can only assert what this
# machine's two bundles happen to be, and once the icon lands both are correct,
# so it can never demonstrate the function REFUSING anything. A guard that has
# only been seen to pass has not been seen to work (L1). Here every failure case
# is staged directly and costs nothing.
#
# THE THREE FAILURES ARE STAGED SEPARATELY ON PURPOSE. Each one leaves the other
# two looking correct, so a suite that only staged "no icon at all" would prove
# nothing about the two failures that actually reach a person: a plist naming a
# file that is not in the bundle, and an .icns holding only small
# representations. Both of those ship a bundle that passes every other check in
# the repository.
#
# THE FIXTURE VALUES ARE MEASURED, NOT INVENTED (L48). The passing case is what
# `plutil -p` and `assetutil --info` actually report for this repository's own
# Release bundle, read on 2026-09-07. The failing cases are that same reading
# with one value changed.
#
# THE 512 CASE IS NOT AN ARBITRARY SMALL NUMBER. 512 is what the catalog holds
# when the largest entry is missing from Contents.json, and it is the failure
# most likely to actually happen, because everything else about such a build is
# correct and the only symptom is a soft icon in Get Info.
#
# The real suite feeds this same function genuine readings off both built
# bundles on every run, so the interface is exercised for real rather than only
# against values written here (L52).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "bundle icon judgement tests" 14

TARGET="scripts/lib/bundle-icon-checks.sh"
require_target "$TARGET"
. "./$TARGET"

# Runs the judgement in a subshell so its verdicts are COUNTED rather than
# inherited: this suite has to observe the function failing without failing
# itself. Prints "<assertions run> <passed> <failed>".
outcome() {
    (
        PASS=0; FAIL=0; _HARNESS_RAN=0
        bundle_icon_checks "$1" "$2" "$3" "$4" >/dev/null 2>&1
        printf '%s %s %s' "$_HARNESS_RAN" "$PASS" "$FAIL"
    )
}

# ---------------------------------------------------------------------------
# The healthy bundle, in both configurations. Both must pass, because Debug is
# the build Dan actually looks at in the Dock while developing, and an icon that
# ships only in Release is one nobody sees until install day.
# ---------------------------------------------------------------------------
check "a Release bundle with a full size icon passes every judgement" \
    "$(outcome Release AppIcon yes 1024)" "3 3 0"
check "and so does a Debug bundle with ITS OWN one" \
    "$(outcome Debug AppIconDebug yes 1024)" "3 3 0"
# ovation#103. Debug carries a derived variant so a development run is
# distinguishable from the resident copy in the Dock, and the judgement knows
# which name belongs to which configuration. A Debug bundle naming the RELEASE
# icon is the variant having silently stopped being applied, and the symptom is
# two identical icons, which reads as normal (L188).
check "a Debug bundle naming the Release icon is refused" \
    "$(outcome Debug AppIcon yes 1024)" "3 2 1"

# ---------------------------------------------------------------------------
# SEEN TO FAIL 1: THE DEFECT AS IT ACTUALLY SHIPPED (ovation#18).
#
# No asset catalog existed, so the compiler stamped no icon name into
# Info.plist and put no .icns in Resources. The build did not warn. This is the
# state this repository was in from 2026-08-25 until the icon landed, and the
# ONLY symptom was a blank generic icon in the Dock.
# ---------------------------------------------------------------------------
check "a bundle with no icon at all is REFUSED" \
    "$(outcome Release '' no 0)" "3 0 3"
check "and it is refused in Debug too, not only in the shipping build" \
    "$(outcome Debug '' no 0)" "3 0 3"

# ---------------------------------------------------------------------------
# SEEN TO FAIL 2: THE PLIST NAMES A FILE THAT IS NOT IN THE BUNDLE.
#
# Every dump of Info.plist reads as correct. Only the filesystem disagrees, and
# nothing in the build reports it, so an operation that matched nothing reports
# success and the next step acts on a state nobody created (L100).
# ---------------------------------------------------------------------------
check "an icon NAMED but not present is REFUSED" \
    "$(outcome Release AppIcon no 0)" "3 1 2"
check "and the name being right is not enough on its own" \
    "$(outcome Release AppIcon no 1024)" "3 2 1"

# ---------------------------------------------------------------------------
# SEEN TO FAIL 3: THE ICON IS PRESENT BUT THE CATALOG HOLDS ONLY SMALL
# REPRESENTATIONS.
#
# This is the one that would otherwise ship. Both other judgements pass, the
# bundle carries a real .icns and a real Assets.car, and macOS simply upscales
# the largest representation it can find. The symptom is a soft, blurred icon in
# Get Info, which reads as a bad export rather than as a missing asset.
# ---------------------------------------------------------------------------
check "a catalog holding only small artwork is REFUSED" \
    "$(outcome Release AppIcon yes 512)" "3 2 1"
check "and one holding a single tiny representation is too" \
    "$(outcome Release AppIcon yes 32)" "3 2 1"

# ---------------------------------------------------------------------------
# SEEN TO FAIL 4: A DIFFERENT ICON NAME THAN THE ONE project.yml ASKS FOR.
#
# ASSETCATALOG_COMPILER_APPICON_NAME and the catalog's set name have to agree.
# When they do not, the catalog still compiles, the build still succeeds, and
# the icon it produced is one nothing looks up.
# ---------------------------------------------------------------------------
check "a bundle naming some other icon set is REFUSED" \
    "$(outcome Release Icon yes 1024)" "3 2 1"

# ---------------------------------------------------------------------------
# The declared count, and an unknown configuration.
# ---------------------------------------------------------------------------
check "the function reports how many judgements it makes" "$(bundle_icon_checks_count)" "3"
check "and a healthy Release runs exactly that many" \
    "$(outcome Release AppIcon yes 1024 | cut -d' ' -f1)" "3"
check "and a broken one runs exactly that many too, rather than stopping early" \
    "$(outcome Release '' no 0 | cut -d' ' -f1)" "3"

# An unknown configuration is refused rather than silently judged as one of the
# known ones (L320).
check "an unknown configuration is refused, never judged as Debug" \
    "$(outcome Staging AppIcon yes 1024 | awk '{print ($3 > 0) ? "refused" : "accepted"}')" "refused"

harness_end
