#!/bin/bash
# The shared test harness must count, must refuse when its target is absent, and
# must refuse a run that executed FEWER assertions than it declared.
#
# ovation#19. Three suites carried identical hand copied plumbing after one day,
# and Phase 0 will produce roughly a dozen. One implementation, so the refusals
# below cannot be forgotten in the twelfth suite (L370: sharing the data while
# copying the code that applies it is not consolidation).
#
# The assertion count is the part no suite had. A run is judged FIRST by the
# count it executed against the count expected, and only then by its failures,
# because a run that loses part of its work still prints a verdict and a check
# for zero failures catches none of it (L288).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
check() {
    if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else
        FAIL=$((FAIL+1)); echo "FAIL: $1"; echo "      expected '$3', got '$2'"; fi
}

HARNESS="scripts/lib/test-harness.sh"
if [ ! -f "$HARNESS" ]; then
    echo "FAIL: $HARNESS is missing, so nothing was checked"
    exit 1
fi

WORK="$(mktemp -d)"
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
    echo "FAIL: could not create a temp directory, so nothing was checked"
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT INT TERM

# Fixture suites are written to disk and run as SUBPROCESSES, because the
# harness's whole job is to decide an exit status, and a sourced copy would
# take this file down with it.
suite() { cat > "$WORK/$1.sh"; chmod +x "$WORK/$1.sh"; }
run()   { ( cd "$PWD" && "$WORK/$1.sh" 2>&1 ); }

# 1. A suite whose assertions all pass, and whose count matches what it declared.
suite allgood <<SUITE
#!/bin/bash
cd "$PWD" || exit 1
. "$PWD/$HARNESS"
harness_begin "all good" 2
check "one" "a" "a"
check "two" "b" "b"
harness_end
SUITE
OUT1="$(run allgood)"; ST1=$?
check "a fully passing suite exits 0" "$ST1" "0"
check "and says how many passed" "$(printf '%s' "$OUT1" | grep -c "2 passed, 0 failed")" "1"

# 2. A failing assertion must fail the run and name the difference.
suite onebad <<SUITE
#!/bin/bash
cd "$PWD" || exit 1
. "$PWD/$HARNESS"
harness_begin "one bad" 2
check "one" "a" "a"
check "the bad one" "actual-value" "expected-value"
harness_end
SUITE
OUT2="$(run onebad)"; ST2=$?
check "a suite with a failing assertion exits non zero" \
    "$([ "$ST2" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and names the assertion that failed" \
    "$(printf '%s' "$OUT2" | grep -c "the bad one")" "1"
check "and shows both values, not merely that it failed" \
    "$(printf '%s' "$OUT2" | grep -c "expected 'expected-value', got 'actual-value'")" "1"

# 3. THE ONE NO SUITE HAD. A run that executed fewer assertions than it declared
#    must be REFUSED, even though every assertion it did run passed. This is the
#    shape where a suite silently loses half its work and still reports success.
suite short <<SUITE
#!/bin/bash
cd "$PWD" || exit 1
. "$PWD/$HARNESS"
harness_begin "short run" 5
check "one" "a" "a"
check "two" "b" "b"
harness_end
SUITE
OUT3="$(run short)"; ST3=$?
check "a run that executed fewer assertions than declared is refused" \
    "$([ "$ST3" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names BOTH numbers, so the gap is readable" \
    "$(printf '%s' "$OUT3" | grep -c "2 of the 5")" "1"
check "and it does not report the run as passing" \
    "$(printf '%s' "$OUT3" | grep -c "0 failed$")" "0"

# 4. A run that executed MORE than declared is also refused. The count is a
#    contract in both directions: a suite that grew without its declaration
#    being updated is a suite nobody re-read.
suite over <<SUITE
#!/bin/bash
cd "$PWD" || exit 1
. "$PWD/$HARNESS"
harness_begin "over run" 1
check "one" "a" "a"
check "two" "b" "b"
harness_end
SUITE
OUT4="$(run over)"; ST4=$?
check "a run that executed MORE assertions than declared is refused too" \
    "$([ "$ST4" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# 5. The target refusal. Every suite so far opens with a variant of "the thing
#    under test is missing, so nothing was checked". A suite that finds nothing
#    to test must never exit 0 (L98), and one implementation means it cannot be
#    forgotten in the twelfth suite.
suite notarget <<SUITE
#!/bin/bash
cd "$PWD" || exit 1
. "$PWD/$HARNESS"
harness_begin "no target" 1
require_target "$WORK/does-not-exist"
check "never reached" "a" "a"
harness_end
SUITE
OUT5="$(run notarget)"; ST5=$?
check "a suite whose target is absent refuses" \
    "$([ "$ST5" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and says nothing was checked rather than reporting a pass" \
    "$(printf '%s' "$OUT5" | grep -c "nothing was checked")" "1"
check "and names the target it could not find" \
    "$(printf '%s' "$OUT5" | grep -c "does-not-exist")" "1"

# 6. A suite that declares a count and then DIES before harness_end must not be
#    read as success by anything that only looks for the word FAIL. This is the
#    crash case, and it is why the count exists at all.
suite dies <<SUITE
#!/bin/bash
cd "$PWD" || exit 1
. "$PWD/$HARNESS"
harness_begin "dies early" 3
check "one" "a" "a"
exit 0
SUITE
OUT6="$(run dies)"; ST6=$?
check "a suite that exits 0 before harness_end is still refused" \
    "$([ "$ST6" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it says the suite never reported" \
    "$(printf '%s' "$OUT6" | grep -c "never reported")" "1"

# 7. A SUITE THAT NEEDS ITS OWN CLEANUP MUST NOT LOSE THE CRASH GUARD.
#    Found while migrating the existing suites: two of them set their own
#    `trap ... EXIT` to remove a temp directory, which SILENTLY REPLACES the
#    harness's guard. Bash keeps one EXIT trap, so the last one registered wins,
#    and the suite would go back to reading as a pass when it died. The suite
#    still looks correct at every line, which is what makes it dangerous.
#
#    So cleanup is registered THROUGH the harness, and the guard runs it.
suite cleanup_and_die <<SUITE
#!/bin/bash
cd "$PWD" || exit 1
. "$PWD/$HARNESS"
harness_begin "cleanup and die" 3
touch "$WORK/sentinel-was-not-removed"
harness_on_exit 'rm -f "$WORK/sentinel-was-not-removed"'
check "one" "a" "a"
exit 0
SUITE
OUT7="$(run cleanup_and_die)"; ST7=$?
check "a suite that registers cleanup and dies is still refused" \
    "$([ "$ST7" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it still says the suite never reported" \
    "$(printf '%s' "$OUT7" | grep -c "never reported")" "1"
check "and the registered cleanup DID run" \
    "$([ -e "$WORK/sentinel-was-not-removed" ] && echo left-behind || echo removed)" "removed"

# 8. The same cleanup must also run on a NORMAL, passing end. Cleanup placed
#    only where things go wrong is reached only by the paths that fail (L515).
suite cleanup_and_pass <<SUITE
#!/bin/bash
cd "$PWD" || exit 1
. "$PWD/$HARNESS"
harness_begin "cleanup and pass" 1
touch "$WORK/sentinel-pass"
harness_on_exit 'rm -f "$WORK/sentinel-pass"'
check "one" "a" "a"
harness_end
SUITE
OUT8="$(run cleanup_and_pass)"; ST8=$?
check "a passing suite with cleanup still exits 0" "$ST8" "0"
check "and its cleanup ran on the success path too" \
    "$([ -e "$WORK/sentinel-pass" ] && echo left-behind || echo removed)" "removed"

# 9. CANNOT MEASURE MUST SURVIVE THE GUARD.
#    Also found while migrating. Two suites already refuse with exit 2 when the
#    thing they need is absent (no xcodegen, no built product), which is a
#    DIFFERENT outcome from a failed assertion and carries its own exit code so
#    a caller can tell them apart. Installing the crash guard silently turned
#    both into exit 1 with the words "never reported", which is the wrong cause
#    and the wrong code: two outcomes that had distinct messages and distinct
#    consequences collapsed into one (L11, L260).
suite cannot_measure <<SUITE
#!/bin/bash
cd "$PWD" || exit 1
. "$PWD/$HARNESS"
harness_begin "cannot measure" 3
harness_cannot_measure "xcodegen is not installed" "install it with: brew install xcodegen"
check "never reached" "a" "a"
harness_end
SUITE
OUT9="$(run cannot_measure)"; ST9=$?
check "cannot measure keeps its own exit code, distinct from a failure" "$ST9" "2"
check "and it says CANNOT MEASURE" \
    "$(printf '%s' "$OUT9" | grep -c "CANNOT MEASURE")" "1"
check "and it gives the reason it could not measure" \
    "$(printf '%s' "$OUT9" | grep -c "xcodegen is not installed")" "1"
check "and it carries the remedy, so the message is actionable" \
    "$(printf '%s' "$OUT9" | grep -c "brew install xcodegen")" "1"
check "and the crash guard does NOT overwrite it with never reported" \
    "$(printf '%s' "$OUT9" | grep -c "never reported")" "0"
check "and it never claims a pass" \
    "$(printf '%s' "$OUT9" | grep -c "passed, 0 failed")" "0"

echo "test harness tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
