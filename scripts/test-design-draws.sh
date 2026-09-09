#!/bin/bash
# The suite for scripts/check-design-draws.sh.
#
# ovation#141. Every claim in that harness is about a fault that once shipped,
# and a guard is only real once it has been seen to fail (L1). So each case here
# plants ONE defect in a copy of a committed design file and asserts that the
# claim written for it, and no other, is the one that fires: a defect large
# enough to break everything makes every claim fail and is indistinguishable
# from the one that should have (L154).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design rendering checks" 28

TARGET="scripts/check-design-draws.sh"
require_target "$TARGET"
require_target "docs/design/invoice-pdf.html"
harness_temp_dir WORK

# The check answers 3 when it has nothing to render in, and that is the first
# thing to establish: every assertion below would otherwise be measuring the
# absence of a browser rather than the presence of a defect. The status is
# captured on its own line, because `if ! cmd` makes `$?` the negation's status.
python3 "$TARGET" docs/design/invoice-pdf.html >/dev/null 2>&1
BROWSER_PROBE=$?
if [ "$BROWSER_PROBE" = "3" ]; then
    harness_cannot_measure \
        "no headless browser, so nothing can be rendered and no claim here proves anything" \
        "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER"
fi

# ONE WIDTH FOR THE PLANTED CASES, so a mutation reports one failure rather than
# one per width and the count below stays readable. The committed record is run
# at both, which is the run that matters.
one() { OVATION_DESIGN_WIDTHS=1440 python3 "$TARGET" "$1" 2>&1; }
one_status() { one "$1" >/dev/null 2>&1; printf '%s' "$?"; }
fired() { one "$1" | sed -n 's/^  FAIL [^:]*: \([^:]*\): .*/\1/p' | sort -u | tr '\n' ';'; }

mutate() {
    # $1 destination, $2 sed expression, $3 a pattern the result must contain.
    # A mutation that matched NOTHING leaves a healthy file and every claim
    # holds, which reads exactly like a guard that works (L100).
    sed "$2" docs/design/"$4" > "$1"
    grep -c "$3" "$1"
}

# ---------------------------------------------------------------------------
# The committed record, which is the case that proves the claims are not simply
# always failing.
# ---------------------------------------------------------------------------
python3 "$TARGET" > "$WORK/healthy.txt" 2>&1
check "the committed design record passes at both widths" "$?" "0"
check "and the verdict names both widths" \
    "$(grep -c '1440px and 1280px' "$WORK/healthy.txt")" "1"
check "and says how many marked blocks of figures it judged" \
    "$(grep -c 'marked block(s) of figures were judged' "$WORK/healthy.txt")" "1"
check "and how many controls it pressed" \
    "$(grep -c 'control(s) pressed across those renders' "$WORK/healthy.txt")" "1"
HEALTHY="$(sed -n 's/^OK: all \([0-9]*\) claim.*/\1/p' "$WORK/healthy.txt")"
check "with more than one claim in it" \
    "$([ "${HEALTHY:-0}" -ge 20 ] && echo many)" "many"

# ---------------------------------------------------------------------------
# 1. THE CONSOLE, when the page throws while it is being DRIVEN. This is
#    ovation#170 exactly: a line carrying an explicitly empty hours value made
#    the invoice PDF render as a blank white sheet, and the only fixture with
#    such a line was three buttons from the one the page opens on.
# ---------------------------------------------------------------------------
THREW="$WORK/threw.html"
check "the hours guard is where the mutation expects it" \
    "$(mutate "$THREW" 's|r.append(mk("td", "r", l.hours == null ? "" : hours(l.hours)));|r.append(mk("td", "r", l.hours !== undefined ? hours(l.hours) : ""));|' 'hours(l.hours) : ""' invoice-pdf.html)" "1"
check "a page that throws while being driven is refused" "$(one_status "$THREW")" "1"
check "and the claim that fired names the console under driving" \
    "$(fired "$THREW")" "the console is still silent after every control has been pressed;"

# ---------------------------------------------------------------------------
# 2. THE CONSOLE AT REST, which is a different claim and needs the catcher
#    installed BEFORE the page's own scripts.
# ---------------------------------------------------------------------------
NOISY="$WORK/noisy.html"
check "the page's opening script is where the mutation expects it" \
    "$(mutate "$NOISY" 's|<body>|<body><script>console.error("something the page said");</script>|' 'something the page said' invoice-pdf.html)" "1"
check "a page that logs an error at rest is refused" "$(one_status "$NOISY")" "1"
check "and the at rest console claim is one of the ones that fired" \
    "$(one "$NOISY" | grep -c 'the console said nothing')" "1"

# ---------------------------------------------------------------------------
# 3. CONTENT CUT OFF WITH NO WAY TO REACH IT. The fault that deleted the invoice
#    screen's right hand side: a stage narrower than the window it holds.
# ---------------------------------------------------------------------------
CUT="$WORK/cut.html"
check "the screen's width is where the mutation expects it" \
    "$(mutate "$CUT" 's|^\.screen { width: 1120px;|.screen { width: 820px;|' 'width: 820px' invoice.html)" "1"
check "a screen that cuts off what it holds is refused" "$(one_status "$CUT")" "1"
check "and the claim that fired names the unreachable content" \
    "$(one "$CUT" | grep -c 'nothing hides content there is no way to reach')" "1"

# ---------------------------------------------------------------------------
# 4. A PAGE THAT SCROLLS SIDEWAYS.
# ---------------------------------------------------------------------------
WIDE="$WORK/wide.html"
check "the page body is where the mutation expects it" \
    "$(mutate "$WIDE" 's|<body>|<body><div style="width:3000px;height:4px"></div>|' 'width:3000px' invoice-pdf.html)" "1"
check "a page that scrolls sideways is refused" "$(one_status "$WIDE")" "1"
check "and the claim that fired names the sideways scroll" \
    "$(one "$WIDE" | grep -c 'the page does not scroll sideways')" "1"

# ---------------------------------------------------------------------------
# 5. A FIGURE OFF THE SHARED RIGHT EDGE, which the record has had to fix twice.
# ---------------------------------------------------------------------------
EDGE="$WORK/edge.html"
check "the money row is where the mutation expects it" \
    "$(mutate "$EDGE" 's|r.append(mk("span", "num", v));|r.append(mk("span", "num", v)); if (k === "Subtotal") r.lastChild.style.marginRight = "24px";|' 'marginRight' invoice-pdf.html)" "1"
check "a figure off the shared right edge is refused" "$(one_status "$EDGE")" "1"
check "and the claim that fired names the right edge" \
    "$(fired "$EDGE")" "every figure in a block that says its figures line up does;"

# ---------------------------------------------------------------------------
# 6. A PAGE THAT DREW ALMOST NOTHING. Without this every claim above passes
#    vacuously over an empty page, which is the shape L98 exists for.
# ---------------------------------------------------------------------------
EMPTY="$WORK/empty.html"
printf '<!doctype html>\n<html><head><title>x</title></head><body><p>one</p></body></html>\n' > "$EMPTY"
check "a page that drew almost nothing is refused" "$(one_status "$EMPTY")" "1"
check "and the claim that fired says so" \
    "$(one "$EMPTY" | grep -c 'the page drew something')" "1"

# ---------------------------------------------------------------------------
# NOTHING TO MEASURE IS NOT A PASS, and each way of having nothing is its own
# outcome (L98, L11).
# ---------------------------------------------------------------------------
check "a named file that is not there is refused, never skipped" \
    "$(python3 "$TARGET" "$WORK/nowhere.html" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "and it says which file" \
    "$(python3 "$TARGET" "$WORK/nowhere.html" 2>&1 | grep -c 'no such design file')" "1"
check "an empty design root cannot measure" \
    "$(OVATION_DESIGN_ROOT="$WORK/nothing-here" python3 "$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "a width list that is not a list of widths is used wrongly" \
    "$(OVATION_DESIGN_WIDTHS='wide' python3 "$TARGET" docs/design/invoice-pdf.html >/dev/null 2>&1; printf '%s' "$?")" "2"
check "a browser that is not there cannot measure, and is not a pass" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" python3 "$TARGET" \
        docs/design/invoice-pdf.html >/dev/null 2>&1; printf '%s' "$?")" "3"
check "and says so rather than reporting health" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" python3 "$TARGET" \
        docs/design/invoice-pdf.html 2>&1 | grep -c 'CANNOT MEASURE')" "1"

harness_end
