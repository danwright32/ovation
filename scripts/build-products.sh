#!/bin/bash
# Build BOTH configurations, once, under the sibling test locks.
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
# repeatedly through Phase 0, re-deriving the same lock incantation each time,
# which is precisely the thing that belongs in one place (L41).
#
# THE LOCKS ARE TAKEN ONCE, FOR BOTH BUILDS. Taking them per configuration means
# releasing in between, and a sibling that takes them in that gap makes the
# second build wait all over again. So both builds are handed to run-tests.sh as
# a single locked command, with its unlocked phase turned off because there are
# no shell suites to run here.
#
# WHY IT GOES THROUGH run-tests.sh AT ALL, rather than taking the locks itself:
# that locking is subtle, it is already tested by scripts/test-run-tests.sh, and
# a second implementation of it is a second thing to keep correct (L263, L370).
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

echo "Building ${CONFIGURATIONS// / and } under the sibling test locks."

OVATION_UNLOCKED_COMMAND=true OVATION_TEST_COMMAND="$INNER" "$RUNNER"
STATUS=$?

# JUDGED BY THE EXIT CODE, never by a line of output (L184). A non zero status
# here is either a build that failed or a runner that could not take the locks,
# and the runner has already said which on stderr. Both mean the products are not
# ready, and neither may report as ready.
if [ "$STATUS" -ne 0 ]; then
    echo "Not all products were built. Nothing here is ready to be judged." >&2
    exit "$STATUS"
fi

echo "${CONFIGURATIONS// / and } are built and ready for scripts/run-tests.sh."
exit 0
