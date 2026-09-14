#!/bin/bash
# The suite for scripts/check-clients-screen-draws.sh.
#
# ovation#98 settled that the name list keeps its held money figure everywhere
# except on the row whose box is open beside it. That rule depends on the
# SELECTION, and the file's repaint did not touch the rows at all, so the way to
# get it wrong is not to write it wrongly but to write it in the one place a
# reader would look: where the row is built. That version draws correctly on
# load and never again, and it is the first mutation below.
#
# NAMING WHICH CLAIM FIRED IS THE POINT. A defect large enough to break the page
# makes every claim fail at once and is indistinguishable from the one that
# should have (L154), so each mutation asserts the EXACT set of claims that
# failed, not merely that something did.
#
# IT NEEDS A BROWSER, and cannot pretend otherwise. With none it reports CANNOT
# MEASURE and exits 2, rather than running zero assertions and reading as a pass
# (L98, L411).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "Clients screen rendering checks" 53

TARGET="scripts/check-clients-screen-draws.sh"
require_target "$TARGET"
DESIGN="docs/design/clients.html"
require_target "$DESIGN"
harness_temp_dir WORK

# The check answers 3 when it has nothing to render in. Established first, or
# every assertion below measures the absence of a browser rather than a defect.
# The status is captured on its own line: written as `if ! cmd; then [ "$?" = 3 ]`
# the `$?` is the NEGATION's status and the branch could never be taken.
"./$TARGET" >/dev/null 2>&1
BROWSER_PROBE=$?
if [ "$BROWSER_PROBE" = "3" ]; then
    harness_cannot_measure \
        "no headless browser, so nothing can be rendered and no claim here proves anything" \
        "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER"
fi

# EDIT IN PLACE, PORTABLY. `sed -i ''` is the BSD form and GNU sed reads the
# empty string as a FILE, so the intended edit silently never happens on Linux
# (L434). Writing to a temp file and moving it is both dialects' behaviour.
sed_in_place() {
    local file="$1" expression="$2" tmp
    tmp="$(mktemp)" || return 1
    sed "$expression" "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$file"
}

mutate() {
    # $1 the copy, $2 sed expression, $3 what the edit must have left behind
    cp "$DESIGN" "$1" || return 1
    sed_in_place "$1" "$2"
    grep -c "$3" "$1"
}

failed_claims() {
    "./$TARGET" "$1" 2>&1 | sed -n 's/^  FAIL \([^:]*\):.*/\1/p' | sort | tr '\n' ';'
}

status_on() {
    "./$TARGET" "$1" >/dev/null 2>&1
    printf '%s' "$?"
}

# ---------------------------------------------------------------------------
# The real file, which is what proves the claims are not simply always failing.
# ---------------------------------------------------------------------------
"./$TARGET" > "$WORK/healthy.txt" 2>&1
check "the committed design file passes" "$?" "0"
check "and it says how many claims it actually measured" \
    "$(grep -c 'claims about what this file draws held' "$WORK/healthy.txt")" "1"
HEALTHY_CLAIMS="$(grep -c '^  ok  ' "$WORK/healthy.txt")"
check "with every claim in it measured" "$([ "$HEALTHY_CLAIMS" -ge 14 ] && echo all)" "all"

# ---------------------------------------------------------------------------
# 1. THE RULE WRITTEN ONLY WHERE THE ROW IS BUILT. Taking the refill out of the
#    repaint is the defect this check exists for: the source still carries the
#    rule, every reading of it is correct, and the screen is right until the
#    first press.
# ---------------------------------------------------------------------------
STALE="$WORK/stale.html"
check "the repaint's refill is where the mutation expects it" \
    "$(mutate "$STALE" 's/      fillRow(n, byName\[n.dataset.client\]);//' 'classList.toggle("sel"')" "1"
check "a repaint that never redraws the rows is refused" "$(status_on "$STALE")" "1"
check "and the claims that fired are the two about pressing" \
    "$(failed_claims "$STALE")" \
    "pressing a holder takes the figure off ITS row and leaves the others;pressing another holder moves the figure off it and back onto the one left;"

# ---------------------------------------------------------------------------
# 2. THE RULE INVERTED: the figure drawn ONLY on the selected row. It is the
#    same one line, written the other way round, and it breaks all FOUR claims
#    about the rows rather than the two that mutation 1 breaks, which is what
#    tells the two apart: a rule written in the wrong place fails only after a
#    press, and a rule written backwards is wrong from the first paint.
# ---------------------------------------------------------------------------
INVERTED="$WORK/inverted.html"
check "the rule's condition is where the mutation expects it" \
    "$(mutate "$INVERTED" 's/if (k.h \&\& !QUIET \&\& k.c !== chosen) {/if (k.h \&\& !QUIET \&\& k.c === chosen) {/' 'k.c === chosen) {')" "1"
check "a list that marks only the selected client is refused" "$(status_on "$INVERTED")" "1"
check "and every claim about the rows fires, not only the ones about a press" \
    "$(failed_claims "$INVERTED")" \
    "pressing a client holding nothing leaves every figure drawn;pressing a holder takes the figure off ITS row and leaves the others;pressing another holder moves the figure off it and back onto the one left;with a client holding nothing selected, every holder carries its figure;"

# ---------------------------------------------------------------------------
# 3. THE FIGURE GONE FROM EVERY ROW, which is the option Dan rejected. It has to
#    be refused rather than pass quietly, because a check about where a figure is
#    NOT is otherwise satisfied by a file that draws it nowhere (L98).
# ---------------------------------------------------------------------------
BARE="$WORK/bare.html"
check "the rule's condition is where this mutation expects it too" \
    "$(mutate "$BARE" 's/if (k.h \&\& !QUIET \&\& k.c !== chosen) {/if (false) {/' 'if (false) {')" "1"
check "a list with no held figures at all is refused" "$(status_on "$BARE")" "1"
check "and the claim that fired is the one about the load state" \
    "$(failed_claims "$BARE" | cut -d';' -f1)" \
    "pressing a client holding nothing leaves every figure drawn"

# ---------------------------------------------------------------------------
# 4. THE BOX GONE. What the row gives up has to be stated somewhere, so the
#    claim that the selected client's own box still names the money is what
#    makes the rule a MOVE rather than a deletion.
# ---------------------------------------------------------------------------
NOBOX="$WORK/nobox.html"
check "the box's label is where the mutation expects it" \
    "$(mutate "$NOBOX" 's/el("div", "mlabel", "Money held")/el("div", "mlabel", "")/' 'el("div", "mlabel", "")')" "1"
check "a screen that drops the money box is refused" "$(status_on "$NOBOX")" "1"
# THREE claims fire and that is the right answer, not noise. The faces and the
# arrivals are read from the box labelled Money held (ovation#186), so a box that
# lost its label is a box those two claims cannot find either, and each says so
# rather than passing over it (L98).
check "and the claims that fired all read the box" \
    "$(failed_claims "$NOBOX")" "a single arrival is never broken down, and a balance of two is;the held money value is in the mono tabular face and the referral credit in the body face;the selected holder's own box still states the money;"

# ---------------------------------------------------------------------------
# THE REST OF THE SCREEN (ovation#186, ovation#209). Eight rounds of decisions
# on this file were measured by hand on the day and by nothing since. Each claim
# below gets the defect that would have shipped past it, and each case renders
# ONCE and reads both the status and the claims that fired from that one run,
# because a planted file rendered twice is a browser start that proves nothing
# new (L298).
# ---------------------------------------------------------------------------
judge() {
    # $1 the copy. Leaves the exit status in JUDGED_STATUS and the failed claims,
    # sorted and joined, in JUDGED_CLAIMS.
    "./$TARGET" "$1" > "$1.out" 2>&1
    JUDGED_STATUS=$?
    JUDGED_CLAIMS="$(sed -n 's/^  FAIL \([^:]*\):.*/\1/p' "$1.out" | sort | tr '\n' ';')"
}

plant() {
    # $1 case name, $2 sed expression, $3 what the edit must have left behind,
    # $4 the refusal's description, $5 the exact claims expected to fire
    local copy="$WORK/$1.html"
    check "the code the '$1' defect edits is where it expects" "$(mutate "$copy" "$2" "$3")" "1"
    judge "$copy"
    check "$4" "$JUDGED_STATUS" "1"
    check "and only the claim it breaks fires ($1)" "$JUDGED_CLAIMS" "$5"
}

# 6. THE TWO BALANCES DRAWN ALIKE (PRD 14f). The credit loses the class that
#    sets it in the body face, so it inherits the money face: the source still
#    reads as two boxes and the figures are identical.
plant "one-face" \
    's/el("div", "mval notmoney", k.r)/el("div", "mval", k.r)/' '"mval", k.r)' \
    "referral credit drawn in the money face is refused" \
    "the held money value is in the mono tabular face and the referral credit in the body face;"

# 7. A SINGLE ARRIVAL BROKEN DOWN (PRD 14l). One row restating the figure the box
#    already shows, which is the same number twice.
plant "single-listed" \
    's/  if (came.length === 1) {/  if (false) {/' 'if (false) {' \
    "a single arrival listed under its own total is refused" \
    "a single arrival is never broken down, and a balance of two is;"

# 8. THE TERMS VALUE THAT OPENS NOTHING (PRD 51j). A value that is a button and
#    draws no list reads as a control and does nothing.
plant "terms-closed" \
    's/  if (TERMS_OPEN) {/  if (false) {/' 'if (false) {' \
    "a payment terms value that opens nothing is refused" \
    "choosing a term changes the value, closes the list and keeps the selected client;the payment terms value opens the four terms;"

# 9. A CHOICE THAT LEAVES THE LIST STANDING over the facts it just changed.
plant "terms-stay-open" \
    's/TERM = t; TERMS_OPEN = false; draw();/TERM = t; draw();/' 'TERM = t; draw();' \
    "a term list left open after a choice is refused" \
    "choosing a term changes the value, closes the list and keeps the selected client;"

# 10. A CHOICE THAT LOSES THE CLIENT. Choosing redraws the whole screen, so a
#     selection that is reset on redraw changes the terms of one client and puts
#     you back on another, which is the fault a person meets after the press.
plant "terms-lose-client" \
    's/^  tbar.append(el("h4", null, "Clients")/  chosen = SELECTED; tbar.append(el("h4", null, "Clients")/' \
    'chosen = SELECTED; tbar' \
    "a term choice that drops the selected client is refused" \
    "choosing a term changes the value, closes the list and keeps the selected client;"

# 11. A QUANTITY OF NOTHING DRAWN (round 4). A credit box drawn for a client who
#     has no credit, which is an empty figure under a real label.
plant "empty-credit" \
    's/    if (k.r) {/    if (true) {/' 'if (true) {' \
    "a referral credit box drawn with nothing in it is refused" \
    "a quantity of nothing is not drawn on the clients screen or the rail;"

# 11b. A FIGURE THAT IS NOT A NUMBER. A credit drawn from a field that does not
#      exist reads `undefined`, and a scan asking only whether a figure is ZERO
#      waves it through, because NaN loses every comparison it is in (L50).
plant "unparsed-figure" \
    's/el("div", "mval notmoney", k.r)/el("div", "mval notmoney", String(k.credit))/' 'String(k.credit)' \
    "a figure that does not parse is refused rather than read as not zero" \
    "a quantity of nothing is not drawn on the clients screen or the rail;"

# 12. THE SAME RULE ON A SETTLED DAY: the rail's held money line drawn at zero,
#     which is `Money held 0.00`, the sentence Dan ruled out in round 2.
plant "held-at-zero" \
    's/if (heldTotal > 0) {/if (heldTotal >= 0) {/' 'heldTotal >= 0' \
    "a held money line drawn at zero on a settled day is refused" \
    "a quantity of nothing is not drawn on the clients screen or the rail;"

# 13. A ROSTER SECTION COUNTING ZERO (ovation#209, PRD 5a). The address section
#     drawn unconditionally, which is what the file did until the day the live
#     export's one broken address was fixed at source.
plant "zero-section" \
    's/  if (bad.length > 0) {/  if (true) {/' 'if (true) {' \
    "a roster section with no rows under it is refused" \
    "a roster section with nothing in it is not drawn;"

# 14. THE NUMBER IT STARTED WITH, COUNTED TWICE. A client missing a tax status
#     AND holding a broken address is one client in the pass, and adding the two
#     section counts states 26 for 25.
plant "started-double" \
    's/"Started with " + settle.length + " of "/"Started with " + (untaxed.length + bad.length) + " of "/' \
    'untaxed.length + bad.length' \
    "a pass that counts one client twice is refused" \
    "the roster pass reports the number it started with;"

# 15. THE ROSTER THAT NEVER LEAVES THE RAIL, which is a place saying zero.
plant "roster-stays" \
    's/if (rosterCount() > 0 || onRoster) items.push/if (true) items.push/' 'if (true) items.push' \
    "a roster still in the rail on a settled day is refused" \
    "on a settled day the roster is gone from the rail;"

# 16. THE ROSTER THAT VANISHES UNDERNEATH YOU, the other half of the same line:
#     answering the last question takes the place you are standing in away.
plant "roster-vanishes" \
    's/if (rosterCount() > 0 || onRoster) items.push/if (rosterCount() > 0) items.push/' \
    'if (rosterCount() > 0) items.push' \
    "a roster that leaves the rail while you stand on it is refused" \
    "standing on the roster as it empties keeps it, saying nothing is left;"

# ---------------------------------------------------------------------------
# 5. A BROWSER THAT IS NOT THERE (ovation#214). The probe at the top of this file
#    covers a machine with no browser at all; this is the other way it can go
#    wrong, a browser NAMED and absent, and the two took different messages. Every
#    other rendering check prints CANNOT MEASURE here and this one printed a bare
#    sentence, so a run that measured nothing read like one that found nothing
#    (L11, L98).
# ---------------------------------------------------------------------------
check "a browser that is named and not there answers cannot measure" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "3"
check "and it says so in the words the other rendering checks use" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" "./$TARGET" 2>&1 | grep -ci 'cannot measure')" "1"

harness_end
