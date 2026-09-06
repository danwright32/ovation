#!/bin/bash
# The one implementation of Ovation's shell test plumbing.
#
# ovation#19. Three suites carried identical hand copied copies of this after a
# single day of Phase 0, and a dozen more are coming. Sharing the code that
# APPLIES a rule is the part that matters: sharing only the data while copying
# the logic beside it is not consolidation, because the shared constant reads as
# the single source of truth and nobody asks whether the logic was duplicated
# (L370).
#
# Usage:
#
#     . "$(dirname "$0")/lib/test-harness.sh"
#     harness_begin "what this suite is about" <how many assertions it runs>
#     require_target "path/to/the/thing/under/test"
#     harness_on_exit 'rm -rf "$WORK"'   # never `trap ... EXIT` yourself
#     harness_cannot_measure "why" "remedy"   # exits 2: proved nothing either way
#     check "description" "$actual" "$expected"
#     harness_end
#
# Three refusals live here so that no suite can forget them.
#
# NOTHING TO TEST IS NOT A PASS. `require_target` refuses when the thing under
# test is absent, rather than running zero assertions and reporting success
# (L98). Every suite written so far opened with a hand copied variant of this,
# which is exactly the kind of thing the twelfth suite omits.
#
# A SHORT RUN IS NOT A PASS. Every suite DECLARES how many assertions it runs,
# and a run that executed a different number is refused before its verdict is
# printed. A run is judged first by the count it executed against the count
# expected, and only then by its failures, because a run that loses part of its
# work still prints a verdict and a check for zero failures catches none of it
# (L288). No suite had this.
#
# A SUITE THAT DIED IS NOT A PASS. An exit before `harness_end` is caught by an
# EXIT trap and refused, because a suite that crashes after its last passing
# assertion otherwise leaves output that reads exactly like success.
_HARNESS_NAME=""
_HARNESS_EXPECTED=0
_HARNESS_RAN=0
_HARNESS_ENDED=0
PASS=0
FAIL=0

# Cleanup a suite registers is run BY the guard, never by a second EXIT trap.
# Bash keeps exactly ONE EXIT trap, so a suite writing its own would silently
# replace the guard and go back to reading as a pass when it died. Every line of
# such a suite still looks correct, which is what makes it worth taking out of
# the suite's hands entirely.
_HARNESS_CLEANUPS=()

harness_on_exit() {
    _HARNESS_CLEANUPS+=("$1")
}

_harness_run_cleanups() {
    local c
    for c in ${_HARNESS_CLEANUPS+"${_HARNESS_CLEANUPS[@]}"}; do
        eval "$c" || true
    done
    _HARNESS_CLEANUPS=()
}

_harness_exit_guard() {
    local status=$?
    _harness_run_cleanups
    [ "$_HARNESS_ENDED" = "1" ] && return "$status"
    echo "REFUSED: the suite '$_HARNESS_NAME' never reported."
    echo "         It exited before harness_end, after $_HARNESS_RAN of its $_HARNESS_EXPECTED assertions."
    echo "         Output above this line may look like a pass. It is not one."
    exit 1
}

harness_begin() {
    _HARNESS_CLEANUPS=()
    _HARNESS_NAME="$1"
    _HARNESS_EXPECTED="$2"
    _HARNESS_RAN=0
    _HARNESS_ENDED=0
    PASS=0
    FAIL=0
    trap _harness_exit_guard EXIT
}

# The thing under test must exist. Absent is a refusal naming what was missing,
# never a run of zero assertions.
require_target() {
    if [ ! -e "$1" ]; then
        _HARNESS_ENDED=1
        echo "REFUSED: $1 is missing, so nothing was checked."
        exit 1
    fi
}

# CANNOT MEASURE is a THIRD outcome, not a failure and not a pass.
#
# A suite that cannot reach the thing it judges (no toolchain, no built product,
# a sibling repository absent) has proved nothing either way, and that is a
# different fact from an assertion failing. It keeps its own exit code, 2, so a
# caller can tell the two apart without parsing text, and the crash guard leaves
# it alone rather than replacing it with the wrong cause (L11, L260, L98).
#
# It takes a reason and, optionally, the remedy, because a refusal whose message
# does not say what to do leaves the reader facing the same command and no way
# to learn why it did nothing (L148).
harness_cannot_measure() {
    _HARNESS_ENDED=1
    echo "CANNOT MEASURE: $_HARNESS_NAME"
    echo "    $1"
    [ "${2:-}" = "" ] || echo "    $2"
    echo "    Nothing was verified. This is not a pass."
    exit 2
}

check() {
    _HARNESS_RAN=$((_HARNESS_RAN+1))
    if [ "$2" = "$3" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: $1"
        echo "      expected '$3', got '$2'"
    fi
}

harness_end() {
    _HARNESS_ENDED=1
    if [ "$_HARNESS_RAN" -ne "$_HARNESS_EXPECTED" ]; then
        echo "REFUSED: $_HARNESS_NAME executed $_HARNESS_RAN of the $_HARNESS_EXPECTED assertions it declares."
        if [ "$_HARNESS_RAN" -lt "$_HARNESS_EXPECTED" ]; then
            echo "         Part of this run did not happen. Its verdict is withheld."
        else
            echo "         Assertions were added without the declaration being updated."
        fi
        exit 1
    fi
    echo "$_HARNESS_NAME: $PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ] || exit 1
    exit 0
}
