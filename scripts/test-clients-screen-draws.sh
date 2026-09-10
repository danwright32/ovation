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
harness_begin "Clients screen rendering checks" 15

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
check "with every claim in it measured" "$([ "$HEALTHY_CLAIMS" -ge 5 ] && echo all)" "all"

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
check "and the claim that fired names the box" \
    "$(failed_claims "$NOBOX")" "the selected holder's own box still states the money;"

harness_end
