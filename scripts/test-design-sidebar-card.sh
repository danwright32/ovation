#!/bin/bash
# The suite for scripts/check-design-sidebar-card.sh.
#
# ovation#188. The sidebar rail is chrome, the same panel on every screen, and
# four files each build their own copy of it in their own script. On 2026-09-10
# two of them drew five lines and two drew four, and had done for three days,
# with every check in the repository green: the shell stylesheet was identical in
# all four the whole time, because what disagreed was MARKUP.
#
# EVERY CASE BELOW IS BUILT RATHER THAN COPIED, except the first. A synthetic
# pair is two files that differ in exactly one way, which is what an assertion
# about a comparison needs; damaging the real record instead would move several
# things at once and the refusal could not be attributed.
#
# THE REAL RECORD IS STILL RUN, first, because a check that refuses everything
# passes every mutation test ever written for it (L1).
#
# IT NEEDS A BROWSER, and cannot pretend otherwise. With none it reports CANNOT
# MEASURE and exits 2, rather than running zero assertions and reading as a pass
# (L98, L411).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design sidebar card tests" 41

TARGET="scripts/check-design-sidebar-card.sh"
require_target "$TARGET"
harness_temp_dir WORK

# The check answers 3 when it has nothing to render in, and that is established
# FIRST, or every assertion below would be measuring the absence of a browser
# rather than the presence of a defect. The status is captured on its own line:
# written as `if ! cmd; then [ "$?" = 3 ]` the `$?` is the negation's status.
OVATION_DESIGN_ROOT="$WORK/nothing-here" "./$TARGET" >/dev/null 2>&1
BROWSER_PROBE=$?
if [ "$BROWSER_PROBE" = "3" ]; then
    harness_cannot_measure \
        "no headless browser, so nothing can be rendered and no claim here proves anything" \
        "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER"
fi

run_on() { OVATION_DESIGN_ROOT="$1" "./$TARGET" 2>&1; }
status_on() {
    OVATION_DESIGN_ROOT="$1" "./$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

# A rail, built from the same geometry shell/window.css uses, so the edge claim
# below is measuring the real relationship rather than a made up one: the card
# is 3px of margin, 1px of border and 11px of padding, and the held line is 3px
# of margin and 12px of padding, which puts both on 15px from each side.
#
# THE SETTLED DAY (ovation#193). Every rail file carries a day switch, because
# every real one does and the check refuses a rail it cannot settle. Pressing it
# draws what clients.html's settled day draws: no counts, `Nothing waiting`, and
# no held money line. It names the day it moves to in `data-day`, the hook the
# check presses. Each line below is one thing a case removes with sed, so a case
# changes exactly one behaviour of the switch.
DAY_SWITCH='<button type="button" data-day="quiet" onclick="settle(this)">A settled day</button>
<script>
function settle(b) {
  var card = document.querySelector(".card");
  Array.prototype.forEach.call(card.querySelectorAll(".ln"), function (n) { n.remove(); });
  var q = document.createElement("div"); q.className = "quiet"; q.textContent = "Nothing waiting"; card.appendChild(q);
  var held = document.querySelector(".railheld"); if (held) { held.remove(); }
  b.setAttribute("data-day", "busy");
}
</script>'

# $1 file, $2 the card's lines as HTML, $3 the held line's HTML
rail_file() {
    cat > "$1" <<HTML
<meta charset="utf-8">
<style>
.side { width: 208px; }
.card { margin: 2px 3px 10px; padding: 10px 11px; border: 1px solid #62554D; }
.card .ln { display: flex; justify-content: space-between; }
.railheld { display: flex; justify-content: space-between; margin: -6px 3px 12px; padding: 0 12px; }
</style>
$DAY_SWITCH
<div class="screen"><div class="win"><nav class="side">
  <div class="card"><div class="hd">Needs you</div>
$2
  </div>
$3
</nav></div></div>
HTML
}

# Edit one fixture in place, portably: `sed -i ''` is BSD only (L434).
edit_fixture() {
    # $1 file, $2 sed expression
    sed "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

FOUR='    <div class="ln"><span>To send</span><b>4</b></div>
    <div class="ln"><span>To chase</span><b>2</b></div>'
FIVE="$FOUR"'
    <div class="ln"><span>Money held</span><b>3</b></div>'
HELD='  <div class="railheld"><span>Money held</span><b>1,837.50</b></div>'
HELD_LINE="$HELD"

# ovation#198. A rail PLUS the rows the card claims to roll up, each stamped with
# the card line it was counted into. $1 file, $2 the card's lines, $3 the rows.
rollup_file() {
    cat > "$1" <<HTML
<meta charset="utf-8">
<style>
.side { width: 208px; }
.card { margin: 2px 3px 10px; padding: 10px 11px; border: 1px solid #62554D; }
.card .ln { display: flex; justify-content: space-between; }
.railheld { display: flex; justify-content: space-between; margin: -6px 3px 12px; padding: 0 12px; }
</style>
$DAY_SWITCH
<div class="screen"><div class="win"><nav class="side">
  <div class="card"><div class="hd">Needs you</div>
$2
  </div>
$HELD_LINE
</nav>
<div class="scroll">
$3
</div>
</div></div>
HTML
}

# ---------------------------------------------------------------------------
# The committed record, which is the case that proves the check is not simply
# always refusing.
# ---------------------------------------------------------------------------
"./$TARGET" > "$WORK/healthy.txt" 2>&1
check "the committed design record passes" "$?" "0"
check "and it says how many rails it actually compared" \
    "$(grep -c 'OK: one rail across [0-9]* design file' "$WORK/healthy.txt")" "1"
check "and it names the file that draws no app window rather than passing over it" \
    "$(grep -c 'draws no app window, by its own declaration' "$WORK/healthy.txt")" "1"
check "and it compared the rails on a settled day as well as on a day with work" \
    "$(grep -c '^OK: .* and one on a settled day' "$WORK/healthy.txt")" "1"

# ---------------------------------------------------------------------------
# THE FAULT, exactly as it shipped: one file gains a line during a round about
# its own screen, and every file goes on rendering.
# ---------------------------------------------------------------------------
DRIFTED="$WORK/drifted"
mkdir -p "$DRIFTED"
rail_file "$DRIFTED/invoice-list.html" "$FOUR" "$HELD"
rail_file "$DRIFTED/clients.html" "$FIVE" "$HELD"
check "a card that gained a line in one file only is refused" "$(status_on "$DRIFTED")" "1"
check "and the refusal says the rail disagrees with itself" \
    "$(run_on "$DRIFTED" | grep -c 'THE SIDEBAR RAIL DISAGREES WITH ITSELF')" "1"
check "and it names both files, so neither is assumed to be the right one" \
    "$(run_on "$DRIFTED" | grep -c 'drawn by clients.html')" "1"
check "and it says what the line that differs actually reads" \
    "$(run_on "$DRIFTED" | grep -c '^  Needs you: .*Money held 3')" "1"

# The same pair agreeing, which is what proves the refusal above was about the
# difference and not about the fixture.
AGREED="$WORK/agreed"
mkdir -p "$AGREED"
rail_file "$AGREED/invoice-list.html" "$FOUR" "$HELD"
rail_file "$AGREED/clients.html" "$FOUR" "$HELD"
check "the same pair drawing the same card passes" "$(status_on "$AGREED")" "0"

# A held line in one file and not the other is the same class of fault and has
# to be caught by the same comparison, or the line ovation#187 settled drifts
# exactly the way the fifth count did.
HALFHELD="$WORK/half-held"
mkdir -p "$HALFHELD"
rail_file "$HALFHELD/invoice-list.html" "$FOUR" "$HELD"
rail_file "$HALFHELD/clients.html" "$FOUR" ""
check "a held money line drawn in one file only is refused" "$(status_on "$HALFHELD")" "1"
check "and the refusal says which rail has no held line" \
    "$(run_on "$HALFHELD" | grep -c '^  Needs you: .*no held line')" "1"

# ---------------------------------------------------------------------------
# The geometry, which no source reading can check: both boxes are declared
# correctly and their numbers only have to ADD UP to the same place.
# ---------------------------------------------------------------------------
OFFEDGE="$WORK/off-edge"
mkdir -p "$OFFEDGE"
rail_file "$OFFEDGE/invoice-list.html" "$FOUR" "$HELD"
rail_file "$OFFEDGE/clients.html" "$FOUR" "$HELD"
# 24px of padding instead of 12 puts the label 12px in and the figure 12px short,
# which is the size of the drift that put a discount off the shared edge twice.
sed 's/padding: 0 12px/padding: 0 24px/' "$OFFEDGE/clients.html" > "$OFFEDGE/clients.tmp" \
    && mv "$OFFEDGE/clients.tmp" "$OFFEDGE/clients.html"
check "the padding is where the mutation expects it" \
    "$(grep -c 'padding: 0 24px' "$OFFEDGE/clients.html")" "1"
check "a held line off the card's edges is refused" "$(status_on "$OFFEDGE")" "1"
check "and the refusal names the file and how far off it is" \
    "$(run_on "$OFFEDGE" | grep -c 'clients.html: the held money line is 12px off')" "1"
check "and it does not accuse the file that is on the edges" \
    "$(run_on "$OFFEDGE" | grep -c 'invoice-list.html: the held money line')" "0"

# ---------------------------------------------------------------------------
# A file that draws the window and no card at all. Absence is its own fault and
# is not the same event as a card that disagrees (L11).
# ---------------------------------------------------------------------------
NOCARD="$WORK/no-card"
mkdir -p "$NOCARD"
rail_file "$NOCARD/invoice-list.html" "$FOUR" "$HELD"
printf '<meta charset="utf-8">\n<div class="screen"><div class="win"><nav class="side"></nav></div></div>\n' \
    > "$NOCARD/clients.html"
check "a file that draws the window and no card is refused" "$(status_on "$NOCARD")" "1"
check "and the refusal names the file with no card" \
    "$(run_on "$NOCARD" | grep -c 'clients.html: NO CARD, and it carries window.css')" "1"

# ---------------------------------------------------------------------------
# Nothing to compare is not a pass. A comparison with one subject reports
# exactly what perfect agreement reports (L98).
# ---------------------------------------------------------------------------
LONELY="$WORK/lonely"
mkdir -p "$LONELY"
rail_file "$LONELY/invoice-list.html" "$FOUR" "$HELD"
check "one rail on its own cannot be compared with anything" "$(status_on "$LONELY")" "2"
check "and it says so rather than reporting one rail as agreement" \
    "$(run_on "$LONELY" | grep -c 'CANNOT COMPARE')" "1"

# A record where every file declares it draws no window measures nothing at all,
# and the declaration must not turn into a way of passing.
DECLARED="$WORK/declared"
mkdir -p "$DECLARED"
printf '<meta charset="utf-8">\n<!-- NOT SHELLED: window.css, this is paper and draws no app window. -->\n<p>x</p>\n' \
    > "$DECLARED/invoice-pdf.html"
printf '<meta charset="utf-8">\n<!-- NOT SHELLED: window.css, this is paper too. -->\n<p>x</p>\n' \
    > "$DECLARED/statement.html"
check "a record whose files all draw no window cannot be compared" \
    "$(status_on "$DECLARED")" "2"

# ---------------------------------------------------------------------------
# Used wrongly, and pointed at nothing.
# ---------------------------------------------------------------------------
check "a file that is not there is refused rather than passed" \
    "$("./$TARGET" "$WORK/no-such-file.html" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "and a browser that is not there answers cannot measure" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "3"

# ---------------------------------------------------------------------------
# THE CARD IS A ROLLUP AND ITS FIGURES ARE COUNTED (ovation#198, PRD 46a). The
# check above proves the four files draw the SAME card; nothing proved any of
# those figures agreed with the screen it sits on. That is the fault Dan found on
# 2026-09-10 in this very file: a band saying 2 above a list that did not hold 2.
#
# EACH ROW CARRIES THE LINE IT WAS COUNTED INTO, so the comparison is between two
# readings of one derivation rather than between the checker's idea of the
# mapping and the file's (L107).
# ---------------------------------------------------------------------------
ROLL_OK='    <div class="ln"><span>To send</span><b>2</b></div>'
ROLL_ROWS='  <div class="row" data-cardline="To send">one</div>
  <div class="row" data-cardline="To send">two</div>'

GOOD="$WORK/rollup-good"; mkdir -p "$GOOD"
rollup_file "$GOOD/invoice-list.html" "$ROLL_OK" "$ROLL_ROWS"
rollup_file "$GOOD/clients.html" "$ROLL_OK" "$ROLL_ROWS"
check "a card figure that matches the rows it counts passes" "$(status_on "$GOOD")" "0"
check "and it says how many lines it was able to judge against rows" \
    "$(run_on "$GOOD" | grep -c 'rolled up')" "1"

# The same pair with the figure moved by one, which is the whole job.
ROLL_BAD='    <div class="ln"><span>To send</span><b>3</b></div>'
BAD="$WORK/rollup-bad"; mkdir -p "$BAD"
rollup_file "$BAD/invoice-list.html" "$ROLL_BAD" "$ROLL_ROWS"
rollup_file "$BAD/clients.html" "$ROLL_BAD" "$ROLL_ROWS"
check "a card figure that does not match the rows it counts is refused" "$(status_on "$BAD")" "1"
# BOTH files carry the fault, because the pair has to agree with each other for
# the rail comparison to get out of the way, so BOTH are named. Naming only one
# would leave the reader assuming the other is the correct copy.
check "and it names the line, the figure and the rows actually drawn" \
    "$(run_on "$BAD" | grep -c "To send.*says 3.*2 row")" "2"
# The FAULT line, not every line naming the file: since ovation#193 each file is
# listed twice, once per day, so a bare count of its name measures the listing.
check "and it names the file the disagreement is in" \
    "$(run_on "$BAD" | grep -c 'invoice-list.html: To send says 3')" "1"

# A LINE WITH NO ROWS IN THIS FILE IS NOT A PASS AND NOT A FAILURE. `Receipts to
# file` counts the other half of the product, which has no screen in this record,
# so it can only be reported as unjudged (L98).
UNJUDGED='    <div class="ln"><span>To send</span><b>2</b></div>
    <div class="ln"><span>Receipts to file</span><b>7</b></div>'
NONE="$WORK/rollup-unjudged"; mkdir -p "$NONE"
rollup_file "$NONE/invoice-list.html" "$UNJUDGED" "$ROLL_ROWS"
rollup_file "$NONE/clients.html" "$UNJUDGED" "$ROLL_ROWS"
check "a card line with no rows in the file does not refuse" "$(status_on "$NONE")" "0"
check "and the count of lines it could not judge is printed rather than left silent" \
    "$(run_on "$NONE" | grep -c 'could not be judged')" "1"

# ---------------------------------------------------------------------------
# THE SETTLED DAY (ovation#193). The rail is chrome, so whatever the settled day
# looks like it looks like that on every screen, and until this only one of the
# four files could draw it at all. The comparison above ran only in the state
# each file opens in, so it could not see the settled rails disagreeing, or a
# settled rail still carrying a quantity of nothing (PRD 46b).
# ---------------------------------------------------------------------------

# The pair drifting ONLY on the settled day: identical on the day with work, so
# every case above passes it.
QUIETDRIFT="$WORK/quiet-drift"; mkdir -p "$QUIETDRIFT"
rail_file "$QUIETDRIFT/invoice-list.html" "$FOUR" "$HELD"
rail_file "$QUIETDRIFT/clients.html" "$FOUR" "$HELD"
edit_fixture "$QUIETDRIFT/clients.html" 's/"Nothing waiting"/"Nothing to do"/'
run_on "$QUIETDRIFT" > "$WORK/quiet-drift.txt"; QUIETDRIFT_STATUS=$?
check "rails that agree with work waiting and disagree when settled are refused" "$QUIETDRIFT_STATUS" "1"
check "and the refusal says it is the settled day that disagrees" \
    "$(grep -c 'THE SIDEBAR RAIL DISAGREES WITH ITSELF ON A SETTLED DAY' "$WORK/quiet-drift.txt")" "1"
check "and it names the file drawing the other one" \
    "$(grep -c 'drawn by clients.html' "$WORK/quiet-drift.txt")" "1"

# A settled day that still draws the held money line, in BOTH files, so the two
# agree with each other and only the rule can refuse it.
QUIETHELD="$WORK/quiet-held"; mkdir -p "$QUIETHELD"
rail_file "$QUIETHELD/invoice-list.html" "$FOUR" "$HELD"
rail_file "$QUIETHELD/clients.html" "$FOUR" "$HELD"
edit_fixture "$QUIETHELD/invoice-list.html" 's/if (held) { held.remove(); }//'
edit_fixture "$QUIETHELD/clients.html" 's/if (held) { held.remove(); }//'
run_on "$QUIETHELD" > "$WORK/quiet-held.txt"; QUIETHELD_STATUS=$?
check "a settled day still drawing the held money line is refused, even where the files agree" \
    "$QUIETHELD_STATUS" "1"
check "and the refusal says the settled day still draws a quantity" \
    "$(grep -c 'THE SETTLED DAY STILL DRAWS A QUANTITY' "$WORK/quiet-held.txt")" "1"
check "and it names the held line in each file" \
    "$(grep -c ': the settled day still draws the held money line' "$WORK/quiet-held.txt")" "2"

# A settled day that keeps the counts, which is a switch doing nothing to them.
QUIETCOUNTS="$WORK/quiet-counts"; mkdir -p "$QUIETCOUNTS"
rail_file "$QUIETCOUNTS/invoice-list.html" "$FOUR" "$HELD"
rail_file "$QUIETCOUNTS/clients.html" "$FOUR" "$HELD"
edit_fixture "$QUIETCOUNTS/invoice-list.html" '/n.remove(); });$/d'
edit_fixture "$QUIETCOUNTS/clients.html" '/n.remove(); });$/d'
run_on "$QUIETCOUNTS" > "$WORK/quiet-counts.txt"; QUIETCOUNTS_STATUS=$?
check "a settled day that keeps its counts is refused" "$QUIETCOUNTS_STATUS" "1"
check "and it says how many counts are still drawn" \
    "$(grep -c ': the settled day still draws 2 count(s)' "$WORK/quiet-counts.txt")" "2"

# A settled card that says NOTHING. A card drawing nothing on the healthy day is
# indistinguishable from one that failed to draw (round 3, Z3).
QUIETMUTE="$WORK/quiet-mute"; mkdir -p "$QUIETMUTE"
rail_file "$QUIETMUTE/invoice-list.html" "$FOUR" "$HELD"
rail_file "$QUIETMUTE/clients.html" "$FOUR" "$HELD"
edit_fixture "$QUIETMUTE/invoice-list.html" 's/q.textContent = "Nothing waiting"; //'
edit_fixture "$QUIETMUTE/clients.html" 's/q.textContent = "Nothing waiting"; //'
run_on "$QUIETMUTE" > "$WORK/quiet-mute.txt"; QUIETMUTE_STATUS=$?
check "a settled card that says nothing at all is refused" "$QUIETMUTE_STATUS" "1"
check "and it says the card is silent rather than calling it agreement" \
    "$(grep -c ': the settled card says nothing at all' "$WORK/quiet-mute.txt")" "2"

# A file with no way to reach a settled day is refused and NAMED, because the
# settled rail is otherwise simply never compared in it (L98).
NODAY="$WORK/no-day"; mkdir -p "$NODAY"
rail_file "$NODAY/invoice-list.html" "$FOUR" "$HELD"
rail_file "$NODAY/clients.html" "$FOUR" "$HELD"
edit_fixture "$NODAY/clients.html" 's/ data-day="quiet"//'
run_on "$NODAY" > "$WORK/no-day.txt"; NODAY_STATUS=$?
check "a file whose rail cannot be put in a settled day is refused" "$NODAY_STATUS" "1"
check "and the refusal names that file" \
    "$(grep -c 'clients.html: NO SETTLED DAY, no control' "$WORK/no-day.txt")" "1"

harness_end
