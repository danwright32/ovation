#!/bin/bash
# The suite for scripts/check-invoice-screen-draws.sh.
#
# ovation#141. That check exists because three faults reached the settled invoice
# design and none of them could be seen in its source: the menu opened under the
# wrong word, it stayed open after a choice, and the first line reported the
# lines total as its own amount. So this suite damages a COPY of the real design
# file in exactly those three ways and asserts that the check refuses each one,
# BY NAME.
#
# NAMING WHICH CLAIM FIRED IS THE POINT. A defect large enough to break the page
# makes every claim fail at once and is indistinguishable from the one that
# should have (L154), so each mutation asserts its own claim failed AND that the
# others did not.
#
# IT NEEDS A BROWSER, and cannot pretend otherwise. With none it reports CANNOT
# MEASURE and exits 2, rather than running zero assertions and reading as a pass
# (L98, L411).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "invoice screen rendering checks" 23

TARGET="scripts/check-invoice-screen-draws.sh"
require_target "$TARGET"
DESIGN="docs/design/invoice.html"
require_target "$DESIGN"
harness_temp_dir WORK

# The check answers 3 when it has nothing to render in, and that is the first
# thing to establish: every assertion below would otherwise be measuring the
# absence of a browser rather than the presence of a defect.
#
# THE STATUS IS CAPTURED ON ITS OWN LINE. Written as `if ! cmd; then [ "$?" = 3 ]`
# the `$?` is the NEGATION's status, which is 0, so the branch could never be
# taken and the suite would report a missing browser as a failing design file.
# Prove this guard by running the suite with OVATION_HEADLESS_BROWSER naming a
# path that is not there: it must say CANNOT MEASURE and exit 2.
"./$TARGET" >/dev/null 2>&1
BROWSER_PROBE=$?
if [ "$BROWSER_PROBE" = "3" ]; then
    harness_cannot_measure \
        "no headless browser, so nothing can be rendered and no claim here proves anything" \
        "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER"
fi

# ---------------------------------------------------------------------------
# The real file, which is the case that proves the claims are not simply always
# failing. Every mutation below is judged against this.
# ---------------------------------------------------------------------------
"./$TARGET" > "$WORK/healthy.txt" 2>&1
check "the committed design file passes" "$?" "0"
check "and it says how many claims it actually measured" \
    "$(grep -c 'claims about what this file draws held' "$WORK/healthy.txt")" "1"
HEALTHY_CLAIMS="$(grep -c '^  ok  ' "$WORK/healthy.txt")"
check "with more than one claim in it" "$([ "$HEALTHY_CLAIMS" -ge 10 ] && echo many)" "many"

# ---------------------------------------------------------------------------
# Each mutation, and the ONE claim it must break.
#
# `broke_only` runs the check on a damaged copy and answers with the names of
# every claim that failed, so an assertion can require both that the right one
# fired and that nothing else did.
# ---------------------------------------------------------------------------
mutate() {
    # $1 the copy, $2 sed expression
    cp "$DESIGN" "$1" || return 1
    sed -i '' "$2" "$1"
    grep -c "$3" "$1"
}

failed_claims() {
    "./$TARGET" "$1" 2>&1 | sed -n 's/^  FAIL \([^:]*\):.*/\1/p' | sort | tr '\n' ';'
}

status_on() {
    "./$TARGET" "$1" >/dev/null 2>&1
    printf '%s' "$?"
}

# 1. THE MENU'S ANCHOR. Putting a large offset back on the menu reproduces the
#    46px drift that had it opening under File.
DRIFTED="$WORK/drifted.html"
check "the menu's anchor is where the mutation expects it" \
    "$(mutate "$DRIFTED" 's/\.menu { position: absolute; top: 100%; left: -7px;/.menu { position: absolute; top: 100%; left: -70px;/' 'left: -70px')" "1"
check "a menu that opens away from its item is refused" "$(status_on "$DRIFTED")" "1"
check "and the claim that fired names the menu's position" \
    "$(failed_claims "$DRIFTED")" "the Edit menu opens under Edit;"

# 2. THE MENU STAYING OPEN. Taking the close out of the item handler reproduces
#    a menu left standing over the invoice it just changed.
STICKY="$WORK/sticky.html"
check "the close is where the mutation expects it" \
    "$(mutate "$STICKY" 's/^        MENU_OPEN = false;$//' 'item\[1\]();')" "1"
check "a menu that stays open after a choice is refused" "$(status_on "$STICKY")" "1"
check "and the claim that fired names the menu closing" \
    "$(failed_claims "$STICKY")" "choosing something closes the menu;"

# 3. THE FIRST LINE'S AMOUNT. Putting the lines total back reproduces the row
#    that reported 450.00 for a 375.00 line.
SUMMED="$WORK/summed.html"
check "the amount is where the mutation expects it" \
    "$(mutate "$SUMMED" 's/  else amt.textContent = money(hours \* RATE);/  else amt.textContent = money(t.lines);/' 'money(t.lines);')" "1"
check "a first line reporting the lines total is refused" "$(status_on "$SUMMED")" "1"
check "and the claim that fired names the line's own amount" \
    "$(failed_claims "$SUMMED")" "the first line shows its own amount, not the lines total;"

# 4. THE PALETTE'S SCOPE. Putting the tokens back on the app window takes them
#    away from everything outside it, which is where the menu bar and its menu
#    live: both declare `background: var(--accent)` and both stop painting, with
#    no error anywhere and the declarations still reading as correct.
UNPAINTED="$WORK/unpainted.html"
check "the palette's block is where the mutation expects it" \
    "$(mutate "$UNPAINTED" 's/^\.screen {$/.win {/' '^\.win {$')" "2"
check "a palette that does not reach the menu bar is refused" "$(status_on "$UNPAINTED")" "1"
check "and the claims that fired name the two things that stop being drawn" \
    "$(failed_claims "$UNPAINTED")" \
    "the menu's highlighted row is painted;the open menu's chip in the menu bar is painted;"

# 5. THE ROW CLIPPING ITS OWN CONTROL. Taking the overflow rule off the row
#    being added puts the type list back inside a clipping box, where it is
#    present in the DOM and painted nowhere. This is the mutation that proves
#    the check measures PAINT rather than presence: every other claim about the
#    list still passes on this copy.
CLIPPED="$WORK/clipped.html"
# The needle here asserts the rule is GONE, since that is what this mutation
# does. A needle that merely appears somewhere in the file would be satisfied by
# the rule still standing.
check "the overflow rule is gone from the mutated copy" \
    "$(mutate "$CLIPPED" 's/^\.lrow\.newrow \.ldesc { overflow: visible; }$//' '^\.lrow\.newrow \.ldesc')" "0"
check "a list clipped away by its own cell is refused" "$(status_on "$CLIPPED")" "1"
check "and the claim that fired names the list not being painted" \
    "$(failed_claims "$CLIPPED")" "the list of types is painted where it sits;"

# 6. THE PANEL'S SECOND QUESTION GOING NOWHERE. Taking the prefill out leaves
#    the panel asking what a type usually charges and nothing reading the
#    answer, which is a field with a writer and no reader: it looks entirely
#    correct on screen, and the amount simply never arrives on the line.
DEAFPANEL="$WORK/deaf-panel.html"
check "the prefill is gone from the mutated copy" \
    "$(mutate "$DEAFPANEL" 's/^    field.value = money(ADDING.amount);$//' 'field.value = money(ADDING.amount)')" "0"
check "a panel whose answer nothing reads is refused" "$(status_on "$DEAFPANEL")" "1"
check "and the claim that fired names making a type" \
    "$(failed_claims "$DEAFPANEL")" "a type that does not exist yet can be made from here;"

# ---------------------------------------------------------------------------
# Used wrongly, and pointed at nothing.
# ---------------------------------------------------------------------------
check "a file that is not there is refused rather than passed" \
    "$(status_on "$WORK/no-such-file.html")" "2"
check "and a browser that is not there answers cannot measure" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "3"

harness_end
