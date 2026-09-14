#!/bin/bash
# The suite for scripts/lib/rendered-run.sh.
#
# ovation#282. On 2026-09-13 the invoice screen suite failed once with
# `expected 'Outstanding is drawn heavier than Total;', got ''`, while the
# assertion one line above it, that the same damaged file was refused, passed.
# The suite had run the check TWICE, once for the exit status and once for the
# names of the claims, and thrown away everything the second run printed except
# lines matching one pattern. So whatever that run said, a CANNOT MEASURE, a
# probe that threw, a pass, was reduced to an empty string, and the one failure
# nobody could reproduce left nothing to diagnose it with. A sibling agent saw
# the same shape in the sidebar card suite on CI the same night.
#
# THE LIBRARY RUNS A RENDERED CHECK ONCE AND KEEPS WHAT IT SAID, so the status
# and the claims come from one run, and every assertion reading them explains a
# mismatch with what the check actually printed. These cases drive it with stub
# commands rather than a browser, because what is under test is what the suite
# does with a run's output, and a browser here would only make the cases slower
# and able to answer CANNOT MEASURE (L291).
#
# NOTHING AND SOMETHING NAMING NOTHING ARE DIFFERENT ANSWERS (L11, L98). A check
# that printed nothing at all never reached the page; one that printed a refusal
# naming no claim reached it and said something this suite did not recognise.
# Each gets its own sentence, carrying the exit status.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "rendered check run tests" 16

LIB="scripts/lib/rendered-run.sh"
require_target "$LIB"
. "$LIB"
harness_temp_dir WORK

CLAIMS='s/^  FAIL \([^:]*\):.*/\1/p'

# A stub standing in for a rendered check: prints the file named in $2 (or
# nothing) and exits $1.
stub() {
    # $1 path, $2 exit status, $3 what it prints (may be empty)
    printf '#!/bin/bash\nprintf %%s %q\nexit %s\n' "$3" "$2" > "$1"
    chmod +x "$1"
}

# ---------------------------------------------------------------------------
# 1. The status and the claims come from ONE run, whatever reads them later.
# ---------------------------------------------------------------------------
NAMED="$WORK/named.sh"
stub "$NAMED" 1 $'Rendered x\n  ok   one: fine\n  FAIL two: it broke\n  FAIL three: it broke too\n\nREFUSED: 2 of 3\n'
rendered_run "$WORK/named" "$NAMED"
check "the run leaves its exit status behind" "$RENDERED_STATUS" "1"
check "and the claims it names, sorted and joined" \
    "$(rendered_claims "$WORK/named" "$CLAIMS")" "three;two;"
check "and the status is still readable from inside a substitution" \
    "$(rendered_status "$WORK/named")" "1"

# A check counted as run once is run once: the stub records every start.
COUNTED="$WORK/counted.sh"
printf '#!/bin/bash\necho started >> %q\necho "  FAIL one: x"\nexit 1\n' "$WORK/starts" > "$COUNTED"
chmod +x "$COUNTED"
rendered_run "$WORK/counted" "$COUNTED"
rendered_claims "$WORK/counted" "$CLAIMS" > /dev/null
rendered_status "$WORK/counted" > /dev/null
rendered_said "$WORK/counted" > /dev/null
check "reading its status and claims starts the check exactly once" \
    "$(grep -c started "$WORK/starts")" "1"

# ---------------------------------------------------------------------------
# 2. NOTHING AT ALL. The run that reached no page.
# ---------------------------------------------------------------------------
SILENT="$WORK/silent.sh"
stub "$SILENT" 3 ""
rendered_run "$WORK/silent" "$SILENT"
SAID="$(rendered_claims "$WORK/silent" "$CLAIMS")"
check "a run that printed nothing names no claim, and says it printed nothing" \
    "$(printf '%s' "$SAID" | grep -c 'NO CLAIM NAMED: the check printed nothing at all')" "1"
check "and it carries the exit status" \
    "$(printf '%s' "$SAID" | grep -c 'exited 3')" "1"

# ---------------------------------------------------------------------------
# 3. SOMETHING, NAMING NO CLAIM. The run that reached the page and said a thing
#    the pattern did not recognise, which is the shape ovation#282 recorded: a
#    probe that threw prints `  FAIL THREW <message>` with no colon after the
#    name, and the claims pattern silently skips it.
# ---------------------------------------------------------------------------
THREW="$WORK/threw.sh"
stub "$THREW" 1 $'Rendered x\n  ok   one: fine\n  FAIL THREW Cannot read properties of null\n\nREFUSED: 1 of 1 claims\n'
rendered_run "$WORK/threw" "$THREW"
SAID="$(rendered_claims "$WORK/threw" "$CLAIMS")"
check "a run that printed a refusal naming no claim says so, not that it printed nothing" \
    "$(printf '%s' "$SAID" | grep -c 'NO CLAIM NAMED: the check exited 1 and printed 5 line(s) naming no claim')" "1"
check "and it quotes the line that failed, which is the diagnosis" \
    "$(printf '%s' "$SAID" | grep -c 'FAIL THREW Cannot read properties of null')" "1"
check "and the verdict line" \
    "$(printf '%s' "$SAID" | grep -c 'REFUSED: 1 of 1 claims')" "1"

CANNOT="$WORK/cannot.sh"
stub "$CANNOT" 3 $'CANNOT MEASURE: the browser returned no page at all (browser exit 0)\n'
rendered_run "$WORK/cannot" "$CANNOT"
check "a CANNOT MEASURE is quoted rather than reduced to an empty string" \
    "$(rendered_claims "$WORK/cannot" "$CLAIMS" | grep -c 'CANNOT MEASURE: the browser returned no page at all')" "1"

# WHAT IT QUOTES IS BOUNDED. A check that printed a page's worth of output must
# not bury the assertion that failed under it (L445), and a design file is where
# a real name could one day sit (docs/PRIVACY-FLOOR.md).
LONG="$WORK/long.sh"
stub "$LONG" 1 "$(for i in $(seq 1 200); do printf 'a line of output that goes on for a while, number %s\n' "$i"; done)"
rendered_run "$WORK/long" "$LONG"
check "and what it quotes from a long output is bounded" \
    "$([ "$(rendered_claims "$WORK/long" "$CLAIMS" | wc -c)" -le 600 ] && echo bounded || echo unbounded)" "bounded"

# ---------------------------------------------------------------------------
# 4. The assertions built on a run explain a mismatch with what it printed, and
#    are silent about a match. Each drives a throwaway suite as a subprocess,
#    because `check` decides a suite's verdict and a sourced copy would decide
#    this one's.
# ---------------------------------------------------------------------------
fixture_suite() {
    # $1 name, $2 the body run between harness_begin and harness_end
    cat > "$WORK/$1-suite.sh" <<SUITE
#!/bin/bash
cd "$PWD" || exit 1
. "$PWD/scripts/lib/test-harness.sh"
. "$PWD/$LIB"
harness_begin "fixture" 1
$2
harness_end
SUITE
    chmod +x "$WORK/$1-suite.sh"
    "$WORK/$1-suite.sh" 2>&1
}

OUT="$(fixture_suite status-mismatch "check_rendered_status 'the damaged file is refused' '$WORK/cannot' 1")"
check "a status that differs is a failed assertion that quotes what the check said" \
    "$(printf '%s' "$OUT" | grep -c "got '3, and the check said: CANNOT MEASURE: the browser returned no page at all")" "1"

OUT="$(fixture_suite status-match "check_rendered_status 'the damaged file is refused' '$WORK/named' 1")"; ST=$?
check "a status that matches passes and quotes nothing" \
    "$ST:$(printf '%s' "$OUT" | grep -c 'the check said')" "0:0"

OUT="$(fixture_suite count-mismatch "check_rendered_count 'it names the refusal' '$WORK/threw' 'THE SIDEBAR RAIL DISAGREES' 1")"
check "a count that differs quotes what the check said instead" \
    "$(printf '%s' "$OUT" | grep -c "got '0, and the check exited 1 and said: .*REFUSED: 1 of 1 claims")" "1"

OUT="$(fixture_suite count-match "check_rendered_count 'it does not accuse' '$WORK/threw' 'nobody accused' 0")"; ST=$?
check "a count that matches passes, a count of zero included" "$ST" "0"

# A run whose output file never came to exist is not a run that printed nothing:
# it is a suite reading a name it never passed to rendered_run, and it says so.
check "a claims read of a run that never happened is refused by name" \
    "$(rendered_claims "$WORK/never-run" "$CLAIMS" | grep -c 'NO RUN RECORDED')" "1"

harness_end
