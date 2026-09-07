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
    local config="$1" app="$2"
    # The remedy names the command that fixes BOTH configurations, not just this
    # one. A refusal here almost always means neither has been built (a fresh
    # clone, cleared DerivedData, or a runner), so a remedy naming one leaves the
    # reader to hit the same wall again on the next configuration (L148, L406).
    local build_it="bash scripts/build-products.sh   (builds Debug and Release under the sibling locks)"

    if [ ! -d "$app" ]; then
        harness_cannot_measure "there is no $config product at $app" "build it first: $build_it"
    fi
    if [ ! -f "$app/Contents/MacOS/Ovation" ]; then
        harness_cannot_measure "the $config bundle has no executable inside it" \
            "rebuild it: $build_it"
    fi
}
