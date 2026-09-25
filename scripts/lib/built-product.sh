#!/bin/bash
# How Ovation's shell suites LOCATE a built bundle, and how they refuse when one
# is not there. One implementation, answering for every suite that reads a
# built product.
#
# ovation#18. scripts/test-built-bundle-identity.sh owned both of these inline.
# A second suite that reads the built product (the app icon one) would have
# copied them, and copying the code that APPLIES a rule while sharing nothing is
# how two suites end up disagreeing about what "the product is missing" means
# (L370, L263).
#
# Usage, from a suite that has already sourced the test harness:
#
#     . "$(dirname "$0")/lib/built-product.sh"
#     APP="$(built_product_path Release)/Ovation.app"
#     built_product_require Release "$APP"

# Ask with the SAME scheme the build used. Querying by target alone resolves a
# different build location than a scheme build writes to, so the path would be
# correct-looking and empty, and the caller would refuse on every run for a
# reason that has nothing to do with the bundle (L156).
built_product_path() {
    xcodebuild -project Ovation.xcodeproj -scheme Ovation -configuration "$1" \
        -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
        | awk '$1 == "BUILT_PRODUCTS_DIR" && $2 == "=" { print $3; exit }'
}

# THE DECISION, MADE BY DAN ON 2026-09-06 (ovation#25): a missing product
# REFUSES, and the refusal blocks the push. It does not skip the configuration
# and it does not build it here.
#
# Skipping was rejected because it leaves the shipping build's assertions
# satisfiable by never building Release, which is the defect ovation#25 exists to
# remove (L98). Building was rejected because it would put an xcodebuild run
# inside the UNLOCKED phase of scripts/run-tests.sh, where it could corrupt a
# sibling app's build, and because a build can park for minutes on the keychain
# dialog in ovation#24 with nothing saying so (L110).
#
# CANNOT MEASURE keeps its own exit code, so it cannot be mistaken for a pass
# (L11, L260), and it names the exact command that fixes it, because a remedy
# nobody can run leaves the reader facing the same refusal with no way out
# (L148, L406).
built_product_require() {
    local config="$1" app="$2" reason code
    # The remedy names the command that fixes BOTH configurations, not just this
    # one. A refusal here almost always means neither has been built (a fresh
    # clone, cleared DerivedData, or a runner), so a remedy naming one leaves the
    # reader to hit the same wall again on the next configuration (L148, L406).
    # It comes from built_product_remedy, so the push gate and these suites give
    # the same advice for the same outcome (L70).
    reason="$(built_product_absence "$config" "$app")"
    code=$?
    case "$code" in
        0) ;;
        1) harness_cannot_measure "$reason" "build it first: $(built_product_remedy 1)" ;;
        2) harness_cannot_measure "$reason" "rebuild it: $(built_product_remedy 2)" ;;
        3) harness_cannot_measure "$reason" "generate the project and build: $(built_product_remedy 3)" ;;
        *) harness_cannot_measure "$reason" "regenerate the project and build: $(built_product_remedy "$code")" ;;
    esac
}

# THE CONFIGURATIONS A BUNDLE SUITE JUDGES, named once (ovation#273). The push
# gate asks whether each is built before it runs anything, and a gate reading a
# different list from the suites it is predicting would refuse, or pass, a
# different question (L70).
BUILT_PRODUCT_CONFIGURATIONS="Debug Release"

# WHAT "BUILT" MEANS, and the ONE place it is decided (ovation#273). The bundle
# suites refuse through `built_product_require` above, and the push gate refuses
# up front through this, before the shell suites, the sibling locks and both
# Swift suites have been paid for. Two copies of the test would let the early
# refusal and the late one disagree, and the disagreement would be found as a
# push waved on to a refusal minutes later, or refused for nothing (L70, L667).
#
# Prints nothing and answers 0 when the bundle is built. Otherwise prints the
# reason and answers 1 for no bundle at all, 2 for a bundle with no executable,
# 3 for no project to ask where the bundle is, and 4 for a project that did not
# say, because each wants different words of remedy.
#
# THE LOCATION IS ASKED OF THE PROJECT, AND AN UNANSWERED QUESTION IS NOT A PLACE
# (ovation#309). With no generated project, built_product_path answers nothing,
# and every caller appends /Ovation.app to that nothing. This used to report no
# product at "/Ovation.app", a location it never looked at, which hid the real
# cause (L11). The optional third argument is the project that was asked, from the
# caller that asked it; it defaults to the one built_product_path asks, relative
# to the top of the tree where the suites run.
built_product_absence() {
    local config="$1" app="$2" project="${3:-Ovation.xcodeproj}"
    if [ -z "${app%/Ovation.app}" ]; then
        # A DIRECTORY HOLDING NOTHING BUT THE COMMITTED PACKAGE RESOLUTION IS NO
        # PROJECT (ovation#421): a fresh clone has exactly that, and a build is
        # what fixes it. The same rule as xcode_project_present in
        # ensure-xcode-project.sh, written out here because this file is copied
        # alone into the suites' throwaway trees.
        local resolved_in="project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        if [ ! -d "$project" ] || { [ -f "$project/$resolved_in" ] \
            && [ -z "$(find "$project" -type f ! -path "$project/$resolved_in" -print 2>/dev/null | head -1)" ]; }; then
            printf 'there is no Xcode project at %s to ask where the %s product is' "$project" "$config"
            return 3
        fi
        printf '%s did not say where the %s product is' "$project" "$config"
        return 4
    fi
    if [ ! -d "$app" ]; then
        printf 'there is no %s product at %s' "$config" "$app"
        return 1
    fi
    if [ ! -f "$app/Contents/MacOS/Ovation" ]; then
        printf 'the %s bundle has no executable inside it' "$config"
        return 2
    fi
    return 0
}

# THE COMMAND THAT FIXES EACH OUTCOME ABOVE, named once (ovation#309), so the push
# gate and the bundle suites cannot give different advice for one fault (L70). No
# project is fixed by building, because build-products.sh makes a project where
# there is none before it builds. A project that answers nothing is broken or
# stale, and building from it will not help, so it is regenerated first.
built_product_remedy() {
    case "$1" in
        3) printf 'bash scripts/build-products.sh   (it generates the project, then builds Debug and Release)' ;;
        4) printf 'bash scripts/regenerate-xcode-project.sh --wait 3600, then bash scripts/build-products.sh' ;;
        *) printf 'bash scripts/build-products.sh   (builds Debug and Release)' ;;
    esac
}
