#!/bin/bash
# The suite for scripts/check-design-decisions-drawn.sh.
#
# ovation#197. Twice on 2026-09-10 the state a design round was judging could
# not be drawn by the file it belonged to, and every check on these files
# asserts things about what IS drawn, so a state never drawn was invisible to
# all of them. Dan chose on 2026-09-29 to connect the two with a claim per
# decision: each settled decision names the file and the presses that show it,
# and the check renders that and refuses when it does not draw.
#
# THE COMMITTED RECORD IS RUN FIRST, or a check that refuses everything passes
# every planted case below (L1). Every other case is BUILT rather than damaged
# out of the real record, so each refusal has exactly one possible cause.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design decisions drawn tests" 36

TARGET="scripts/check-design-decisions-drawn.sh"
require_target "$TARGET"
harness_temp_dir WORK

harness_require_browser \
    "no headless browser, so nothing can be rendered and no claim here proves anything" \
    "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER" \
    env OVATION_DESIGN_ROOT="$WORK/nothing-here" "./$TARGET"

OVATION_BROWSER_GLOBS="$WORK/no-browser-here/*" OVATION_HEADLESS_BROWSER= \
    OVATION_DESIGN_ROOT="$WORK/nothing-here" "./$TARGET" > "$WORK/no-browser.txt" 2>&1
check "with no browser to find, even a record that is not there answers cannot measure" \
    "$?:$(grep -c 'CANNOT MEASURE: no headless browser found' "$WORK/no-browser.txt")" "3:1"

. "$(dirname "$0")/lib/rendered-run.sh"
judge() { rendered_run "$1" env OVATION_DESIGN_ROOT="$1" "./$TARGET"; OUT="$(cat "$1.out")"; }
says() { case "$OUT" in *"$2"*) check "$1" "yes" "yes" ;; *) check "$1" "$OUT" "should say: $2" ;; esac; }

# A design file with one hidden drawer that a press opens, and a switch row
# whose two buttons each carry the word `sent`, one of them inside `.bar`.
page() {
    mkdir -p "$1"
    cat > "$1/page.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<style>.drawer { display: none; } .drawer.open { display: block; height: 20px; }</style>
<div class="bar"><button id="open"><span>Open the drawer</span></button><button><span>sent</span><span>130 of 130</span></button></div>
<div class="other"><button><span>sent</span></button></div>
<div class="drawer">Held on the client 91.72</div>
<p class="rest">always drawn</p>
<script>
document.getElementById("open").addEventListener("click", function () {
  document.querySelector(".drawer").classList.add("open");
});
</script>
HTML
}

# A record whose one decision carries the claims given, one per argument.
record() {
    local dir="$1" date="$2"
    shift 2
    page "$dir"
    {
        printf '# The design record\n\n### The drawer, settled %s (ovation#1)\n\nWhy it opens.\n\n' "$date"
        for claim in "$@"; do printf '%s\n\n' "$claim"; done
        printf '## Something after it\n\nNot a decision.\n'
    } > "$dir/README.md"
}

# 1. THE COMMITTED RECORD PASSES, and says what it judged.
rendered_run "$WORK/committed" "./$TARGET"; OUT="$(cat "$WORK/committed.out")"
check_rendered_status "every claim in the committed record draws" "$WORK/committed" "0"
says "it says how many claims it drew" "claim(s) drawn"
says "and how many older decisions still carry no claim, rather than hiding them" "older decision(s)"

# 2. A CLAIM THAT DRAWS AFTER ITS PRESS PASSES. The control for every refusal
#    below: the same fixture, the only change the one each case names (L159).
A="$WORK/drawn"; record "$A" 2026-09-10 'Drawn: `page.html` pressing `Open the drawer` shows `.drawer` reading `91.72`.'
judge "$A"
check_rendered_status "a claim whose state draws after its press passes" "$A" "0"

# 3. THE SAME CLAIM WITHOUT THE PRESS IS REFUSED: the drawer is in the page and
#    not drawn, which is the whole difference this check exists to see.
B="$WORK/notdrawn"; record "$B" 2026-09-10 'Drawn: `page.html` shows `.drawer`.'
judge "$B"
check_rendered_status "a claim whose element is in the page but not drawn is refused" "$B" "1"
says "it names the line of the record the claim is on" "line 7"
says "and says nothing was drawn" "drew none"

# 4. A PRESS THAT FINDS NOTHING IS REFUSED, and it is not the element's fault.
C="$WORK/nopress"; record "$C" 2026-09-10 'Drawn: `page.html` pressing `Close the drawer` shows `.rest`.'
judge "$C"
check_rendered_status "a press whose words are on nothing is refused" "$C" "1"
says "and it says which press found nothing" "press 1 of 1 found 0"

# 5. A PRESS THAT FINDS TWO THINGS IS REFUSED rather than pressing the first
#    (L521): which one was meant is exactly what the claim failed to say.
D="$WORK/twopress"; record "$D" 2026-09-10 'Drawn: `page.html` pressing `sent` shows `.rest`.'
judge "$D"
check_rendered_status "a press whose words are on two things is refused" "$D" "1"
says "and it says how many it found" "press 1 of 1 found 2"

# 6. AND A SCOPE NAMES WHICH ONE, so the refusal above has a way out.
E="$WORK/scoped"; record "$E" 2026-09-10 'Drawn: `page.html` pressing `sent @ .bar` shows `.rest`.'
judge "$E"
check_rendered_status "a press scoped to one part of the page finds one thing and passes" "$E" "0"

# 7. DRAWN WITH THE WRONG WORDS IS REFUSED.
F="$WORK/reading"; record "$F" 2026-09-10 'Drawn: `page.html` pressing `Open the drawer` shows `.drawer` reading `500.00`.'
judge "$F"
check_rendered_status "a claim whose element draws with other words is refused" "$F" "1"
says "and it says the words were not there" "does not read"

# 8. A CLAIM NAMING A FILE THAT IS NOT THERE IS REFUSED, never skipped.
G="$WORK/nofile"; record "$G" 2026-09-10 'Drawn: `gone.html` shows `.rest`.'
judge "$G"
check_rendered_status "a claim naming a design file that is not there is refused" "$G" "1"
says "and it names the missing file" "gone.html"

# 9. A LINE THAT STARTS LIKE A CLAIM AND IS NOT ONE IS REFUSED, or a typo would
#    read as a claim to a person and as nothing to the check (L675).
H="$WORK/malformed"; record "$H" 2026-09-10 'Drawn: page.html shows .rest'
judge "$H"
check_rendered_status "a claim line the check cannot read is refused" "$H" "1"
says "and it says the line could not be read" "cannot be read"

# 10. A DECISION RECORDED AFTER THE CUTOFF WITH NO CLAIM IS REFUSED. This is the
#     rule itself: from 2026-09-30 every decision says where it is drawn.
I="$WORK/newbare"; record "$I" 2026-09-30
printf '### Another, settled 2026-09-10\n\nDrawn: `page.html` shows `.rest`.\n' >> "$I/README.md"
judge "$I"
check_rendered_status "a decision settled after the cutoff with no claim is refused" "$I" "1"
says "it names the decision's line" "line 3"
says "and the day that makes it owe one" "2026-09-30"

# 11. AN OLDER DECISION WITH NO CLAIM IS COUNTED, NOT REFUSED. Dan did not ask
#     for the whole record to be backfilled in one change, so the older ones are
#     reported by line, where the count can be seen to shrink (L98).
J="$WORK/oldbare"; record "$J" 2026-09-10
printf '### Another, settled 2026-09-11\n\nDrawn: `page.html` shows `.rest`.\n' >> "$J/README.md"
judge "$J"
check_rendered_status "an older decision with no claim is not refused" "$J" "0"
says "and it is listed by its line" "line 3"
says "under a count of the older decisions still owing one" "1 older decision(s)"

# 12. THE CUTOFF DAY ITSELF IS OLDER. Recorded on the day this shipped, before
#     the rule existed, so it is reported like the rest rather than refused.
K="$WORK/cutoffday"; record "$K" 2026-09-29
printf '### Another, settled 2026-09-11\n\nDrawn: `page.html` shows `.rest`.\n' >> "$K/README.md"
judge "$K"
check_rendered_status "a decision settled on the cutoff day itself is not refused" "$K" "0"

# 13. A CLAIM COUNTS FOR ITS OWN DECISION ONLY. One under the next heading does
#     not satisfy a decision above it, or one claim would cover a whole record.
L="$WORK/elsewhere"; record "$L" 2026-09-30
printf 'Drawn: `page.html` shows `.rest`.\n' >> "$L/README.md"
judge "$L"
check_rendered_status "a claim in another section does not satisfy a decision" "$L" "1"

# 13b. A SELECTOR THE BROWSER CANNOT READ IS REFUSED AS THE CLAIM'S FAULT, not
#      reported as a page that failed to render (L11).
S="$WORK/badselector"; record "$S" 2026-09-10 'Drawn: `page.html` shows `.drawer[`.'
judge "$S"
check_rendered_status "a claim whose selector cannot be read is refused" "$S" "1"
says "and it says the selector is the fault, on the claim's line" "line 7: names a selector the browser cannot read"
T2="$WORK/badscope"; record "$T2" 2026-09-10 'Drawn: `page.html` pressing `sent @ .bar[` shows `.rest`.'
judge "$T2"
check_rendered_status "a press scoped by a selector that cannot be read is refused" "$T2" "1"
says "and it names the press" "in the scope of press 1"

# 14. A RECORD WITH NO CLAIM AT ALL CANNOT BE MEASURED. Rendering nothing and
#     passing reads exactly like rendering everything and passing (L98).
M="$WORK/noclaims"; record "$M" 2026-09-10
judge "$M"
check_rendered_status "a record carrying no claim at all cannot be measured" "$M" "2"
says "and it says so rather than passing" "CANNOT MEASURE"

# 15. NO RECORD AT ALL CANNOT BE MEASURED EITHER.
N="$WORK/norecord"; mkdir -p "$N"
judge "$N"
check_rendered_status "a design root with no README cannot be measured" "$N" "2"

# 16. IT NEVER QUOTES THE RECORD. A press is a fixture's words, which on the
#     Clients screen are a client's name, so a refusal says which press rather
#     than what it said (docs/PRIVACY-FLOOR.md).
P="$WORK/private"; record "$P" 2026-09-10 'Drawn: `page.html` pressing `Somebody Private` shows `.rest`.'
judge "$P"
check_rendered_status "a press naming a person is refused like any other" "$P" "1"
check "and the refusal does not repeat the words it pressed" \
    "$(grep -c 'Somebody Private' "$P.out")" "0"

harness_end
