#!/bin/bash
# Assert what the BUILT PRODUCTS actually are, not what the configuration asked
# for, for EVERY configuration Ovation ships.
#
# A value your configuration SETS is only in force if nothing downstream
# recomputes it. A framework or toolchain deriving the same value from other
# inputs overwrites yours silently, and the line goes on reading as protection
# while protecting nothing (L188). So every assertion here reads a signed bundle
# on disk.
#
# THIS SUITE TAKES NO ARGUMENT, AND THAT IS THE FIX FOR ovation#25.
#
# It used to read the configuration from $1 and default to Debug.
# scripts/run-tests.sh finds its suites by glob and runs each with no arguments,
# so the RELEASE assertions never ran in the suite and never ran in the pre push
# gate. They are the ones that caught a real security defect hours earlier
# (ovation#9), found only because the suite was invoked BY HAND during the fix,
# and nothing would have found it again. Meanwhile "built bundle identity tests"
# appeared in every green run, so a reader concluded the shipping bundle was
# checked: a check's name is not a statement of its coverage, and the gap stays
# invisible precisely because a green tick with the right name is already on the
# board (L413, L400, L98).
#
# A suite that takes no parameter cannot run in a default mode. That is why the
# repair is to remove the parameter rather than to teach the runner a convention,
# and scripts/test-run-tests.sh now refuses any suite that reintroduces one, so
# the fix is to the class rather than to this instance (L30).
#
# The judgements themselves live in scripts/lib/bundle-identity-checks.sh, one
# implementation for both configurations rather than a second copy for Release
# (L370), and scripts/test-bundle-identity-checks.sh drives that implementation
# through its failure cases, which this suite can never do: both bundles on this
# machine are currently correct, and a guard only ever seen to pass has not been
# seen to work (L1).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
. "$(dirname "$0")/lib/built-product.sh"
. "$(dirname "$0")/lib/bundle-identity-checks.sh"

CONFIGURATIONS="Debug Release"

# The declared total is DERIVED, never written out a second time. Two numbers
# that have to agree drift, and the one that drifts is the declaration nobody
# re-reads (L70). A short run is refused by the harness before any verdict is
# printed (L288), so this is what keeps a silently dropped configuration from
# reading as a pass.
NCONFIGS=0
for _c in $CONFIGURATIONS; do NCONFIGS=$((NCONFIGS+1)); done
harness_begin "built bundle identity tests (${CONFIGURATIONS// /, })" \
    "$((NCONFIGS * $(bundle_identity_checks_count)))"

require_target "project.yml"

# ---------------------------------------------------------------------------
# EVERY configuration must be present BEFORE any assertion runs, so that a
# missing Debug product cannot hide whatever Release would have said.
#
# Locating the product and refusing when it is absent both live in
# scripts/lib/built-product.sh, where the reasoning behind the refusal is
# recorded. They moved there for ovation#18, when a second suite began reading
# the built product: copying the code that APPLIES a rule is how two suites end
# up disagreeing about what "the product is missing" means (L370, L263).
# ---------------------------------------------------------------------------
for CONFIG in $CONFIGURATIONS; do
    built_product_require "$CONFIG" "$(built_product_path "$CONFIG")/Ovation.app"
done

# ---------------------------------------------------------------------------
# WHAT THIS SUITE DOES NOT COVER, stated rather than left to be assumed from its
# name (L400).
#
# It judges the bundles ON DISK, so it is only ever as current as the last
# build. A configuration change made without a rebuild is invisible here.
#
# An mtime comparison was written first and MEASURED, and it does not work in
# either direction. scripts/test-project-configuration.sh regenerates the
# .xcodeproj on every run, so project.pbxproj is newer than every build within
# seconds of a suite passing; and an incremental build that correctly relinks
# nothing leaves the executable's mtime unchanged, so a genuinely current
# product reads as stale for ever and the only remedy is a clean build. A guard
# that is red on a healthy tree is one people learn to skip (L378), and the
# proxy fails in the green direction too, so it was removed rather than tuned.
#
# The honest cover for that gap is the OTHER side of the pair: asserting the
# same security properties against the RESOLVED BUILD SETTINGS, which are always
# current and need no build. Those assertions do not exist yet
# (ENABLE_HARDENED_RUNTIME, CODE_SIGN_IDENTITY, CODE_SIGN_INJECT_BASE_ENTITLEMENTS
# and the per configuration entitlements file are all unasserted today), and
# they are filed rather than written here, because a guard whose two sides come
# from one reading can only prove that reading is self consistent (L70) and
# these two must stay genuinely independent.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Now judge them. Every configuration, through one implementation.
# ---------------------------------------------------------------------------
for CONFIG in $CONFIGURATIONS; do
    APP="$(built_product_path "$CONFIG")/Ovation.app"
    SIG="$(codesign -d --verbose=2 "$APP" 2>&1)"
    ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - 2>/dev/null)"
    bundle_identity_checks "$CONFIG" "$SIG" "$ENTS"
done

harness_end
