#!/bin/bash
# Build BOTH configurations, once, through the test runner and outside the
# sibling test locks, which a build does not need (ovation#302).
#
# ovation#28. scripts/test-built-bundle-identity.sh judges the built bundles and
# refuses when a configuration has no product. That is correct on Dan's Mac,
# where both are always there, and wrong on a fresh runner, where a missing build
# is the normal state and the refusal would stop every run with a message about a
# missing Release product rather than about the change.
#
# DAN'S DECISION, 2026-09-06: CI BUILDS BOTH. The alternative was to skip the
# build dependent suites on CI, which would leave the shipping build's bundle
# assertions running on exactly one machine, and those are the assertions that
# caught a real security defect in ovation#9. So there has to be one command CI
# can call before the suite, and this is it:
#
#     bash scripts/build-products.sh && bash scripts/run-tests.sh
#
# It is also the command a PERSON needs. Assembling it by hand happened
# repeatedly through Phase 0, re-deriving the same incantation each time, which
# is precisely the thing that belongs in one place (L41).
#
# BOTH BUILDS ARE ONE COMMAND handed to run-tests.sh, with its shell suites turned
# off because there are none to run here. Going through the runner gives the
# builds what every build there gets: a project made when there is none and
# registered as being read, so a regeneration cannot rewrite it underneath them
# (ovation#299), the project currency check, and the live data bracket.
#
# NO SIBLING LOCK IS TAKEN, AND THAT IS MEASURED RATHER THAN INHERITED
# (ovation#302). This header used to say both builds ran under the sibling test
# locks. Since ovation#271 the command it hands over runs as the runner's PURE
# command, before and outside both locks, and with no hosted command the runner
# takes no lock at all, so the claim was untrue. The question is then whether a
# build needs them, and ovation#271's measurement on this Mac answers it for the
# Debug build: its unlocked Ovation runs spent 38.9 percent of their time building
# the Debug app and hosted tests, and 38.3 percent building the pure suite, beside
# Overture's tests, and none of Overture's 21 failures landed in either. Every one
# landed while Ovation's hosted suite was TESTING, ordering windows front. Downbeat
# ran 10 rounds beside Ovation with no failure. A build opens no window and moves
# no focus.
#
# WHAT WAS NOT MEASURED, said rather than implied: the Release build on its own.
# It differs from the Debug build in optimisation, so in how long it keeps cores
# busy, and load from any source was already shown to raise an Overture crash
# that also happens alone (overture#3874). The pure suite runs unlocked under the
# same cost by decision, so a build taking locks the pure suite does not would be
# a rule about load applied to one case of it. If siblings' suites start failing
# under Ovation's builds, this is the premise to re-measure, with the harness
# recorded on ovation#271.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATIONS="${OVATION_BUILD_CONFIGURATIONS:-Debug Release}"
RUNNER="${OVATION_BUILD_RUNNER:-${REPO_ROOT}/scripts/run-tests.sh}"

# The build command receives the configuration as its first argument. Injectable
# so scripts/test-build-products.sh can measure the ORCHESTRATION without paying
# for two real builds; the default is the real thing.
if [ -n "${OVATION_BUILD_COMMAND:-}" ]; then
    BUILD_COMMAND="$OVATION_BUILD_COMMAND"
else
    BUILD_COMMAND="${REPO_ROOT}/scripts/lib/build-one-configuration.sh"
fi

# One command that builds every configuration in order and reports WHICH one
# failed. "The build failed" sends somebody to look at both (L11).
INNER=""
for CONFIG in $CONFIGURATIONS; do
    step="echo '==> Building ${CONFIG}'; \"${BUILD_COMMAND}\" ${CONFIG} || { echo \"BUILD FAILED: the ${CONFIG} configuration did not build.\" >&2; exit 1; }"
    if [ -z "$INNER" ]; then INNER="$step"; else INNER="${INNER}; ${step}"; fi
done

echo "Building ${CONFIGURATIONS// / and }."

# THE SKIP SEAM IS CLEARED, NOT INHERITED (ovation#22). It tells the runner not
# to do the xcodebuild work, which is exactly the work this script exists to do,
# and it is an environment variable, so anything running under a shell that has
# it set would get a script reporting both configurations built while building
# neither (L169, L439).
#
# AND SO IS THE HOSTED COMMAND (ovation#302). Inherited, it would make the runner
# take both sibling locks after the builds and run somebody else's hosted command
# under them, which this script was never asked to do.
OVATION_UNLOCKED_COMMAND=true OVATION_TEST_COMMAND="$INNER" \
    env -u OVATION_SKIP_XCODE_PHASE -u OVATION_HOSTED_TEST_COMMAND "$RUNNER"
STATUS=$?

# JUDGED BY THE EXIT CODE, never by a line of output (L184). A non zero status
# here is either a build that failed or a runner that refused before building,
# and the runner has already said which on stderr. Both mean the products are not
# ready, and neither may report as ready.
if [ "$STATUS" -ne 0 ]; then
    echo "Not all products were built. Nothing here is ready to be judged." >&2
    exit "$STATUS"
fi

echo "${CONFIGURATIONS// / and } are built and ready for scripts/run-tests.sh."
exit 0
