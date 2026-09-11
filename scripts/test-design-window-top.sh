#!/bin/bash
# The suite for scripts/check-design-window-top.sh.
#
# ovation#192. `invoice.html` carries a recorded decision about exactly this:
# two prose blocks were cut from above the window because carrying all three
# took the top of the design from 380px to 514px down the page on an 800px
# laptop window, which is more than half the screen gone before the thing the
# page exists to show. Nothing enforced it.
#
# IT COST A RED BUILD ON 2026-09-10. One extra row of state switches added about
# 40px above the window. Every check passed on Dan's Mac; on the Linux runner
# the page renders taller, the due date terms opened below the fold, and
# check-invoice-screen-draws.sh refused an unrelated claim saying it could not
# measure them. The refusal was correct and named the wrong subject.
#
# THE MEASUREMENT IS THE TOP OF THE PAGE TO THE TOP OF THE WINDOW, which cannot
# be read from any stylesheet: it is the sum of whatever prose, headings and
# switches happen to sit above it.
#
# EVERY CASE IS BUILT rather than damaged out of the real record, except the
# first, because a synthetic page differs in exactly one way and a refusal can
# then be attributed. The real record is run first, or a check that refuses
# everything passes every mutation ever written for it (L1).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design window top tests" 15

TARGET="scripts/check-design-window-top.sh"
require_target "$TARGET"
harness_temp_dir WORK

# No browser is established FIRST, or every assertion below would be measuring
# the absence of a browser rather than the presence of a defect (L411).
OVATION_DESIGN_ROOT="$WORK/nothing-here" "./$TARGET" >/dev/null 2>&1
BROWSER_PROBE=$?
if [ "$BROWSER_PROBE" = "3" ]; then
    harness_cannot_measure \
        "no headless browser, so nothing can be rendered and no claim here proves anything" \
        "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER"
fi

run_on() { OVATION_DESIGN_ROOT="$1" "./$TARGET" 2>&1; }
status_on() { OVATION_DESIGN_ROOT="$1" "./$TARGET" >/dev/null 2>&1; printf '%s' "$?"; }

# A page whose window sits $2 pixels down, built from a spacer rather than real
# prose so the number under test is the only thing that varies.
window_file() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<HTML
<!doctype html>
<meta charset="utf-8">
<style>
  body { margin: 0; }
  .above { height: ${2}px; }
  .screen { width: 1120px; height: 400px; background: #CFC9C1; }
</style>
<div class="above">prose about the screen</div>
<div class="screen"><div class="win">the window</div></div>
HTML
}

# 1. THE COMMITTED RECORD PASSES. A suite that only ever runs against planted
#    defects never proves the check passes anything real.
OUT="$("./$TARGET" 2>&1)"; RC=$?
check "the committed design files are all above the ceiling" "$RC" "0"
case "$OUT" in
    *800*) check "it says which window height it measured against" "yes" "yes" ;;
    *) check "it says which window height it measured against" "$OUT" "should name the 800px window" ;;
esac

# 2. A WINDOW THAT STARTS TOO FAR DOWN IS REFUSED, and this is the whole job.
A="$WORK/toolow"; window_file "$A/deep.html" 700
check "a window past the ceiling is refused" "$(status_on "$A")" "1"
OUT="$(run_on "$A")"
case "$OUT" in
    *deep.html*) check "it names the file" "yes" "yes" ;;
    *) check "it names the file" "$OUT" "should say deep.html" ;;
esac
case "$OUT" in
    *700*) check "it names how far down the window actually starts" "yes" "yes" ;;
    *) check "it names how far down the window actually starts" "$OUT" "should say 700" ;;
esac
case "$OUT" in
    *460*) check "it names the ceiling it was judged against" "yes" "yes" ;;
    *) check "it names the ceiling it was judged against" "$OUT" "should say 460" ;;
esac

# 3. AND ONE INSIDE IT IS NOT. Without this the rule above is bought by refusing
#    every page, which passes any mutation ever written for it (L1).
B="$WORK/fine"; window_file "$B/shallow.html" 120
check "a window inside the ceiling passes" "$(status_on "$B")" "0"

# 4. THE EXEMPTION IS THE FILE'S OWN DECLARATION, read from the same helper the
#    shell check reads it with, never a list of names kept in the checker (L362).
C="$WORK/paper"; window_file "$C/screen.html" 120
cat > "$C/paper.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<!-- NOT SHELLED: window.css, it draws no app window, it is paper. -->
<div style="height:900px">a printed invoice, far down a long page</div>
HTML
check "a file declaring it draws no app window is not judged" "$(status_on "$C")" "0"
OUT="$(run_on "$C")"
case "$OUT" in
    *"no app window"*|*"draw no app window"*) check "and it SAYS it was not judged, rather than passing in silence" "yes" "yes" ;;
    *) check "and it SAYS it was not judged, rather than passing in silence" "$OUT" "should say the file draws no window" ;;
esac

# 5. A STALE DECLARATION IS REFUSED, not honoured. An exemption that outlives its
#    reason reads as a considered decision and is never revisited (L346), and
#    here it would exempt the one file whose window had slid down the page.
D="$WORK/stale"; mkdir -p "$D"
cat > "$D/stale.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<!-- NOT SHELLED: window.css, it draws no app window. -->
<style>.above { height: 700px; } .screen { height: 300px; }</style>
<div class="above">prose</div><div class="screen">but here is a window</div>
HTML
check "a file that says it draws no window and draws one is refused" "$(status_on "$D")" "1"
OUT="$(run_on "$D")"
case "$OUT" in
    *stale*|*STALE*) check "and the refusal names the declaration as the fault" "yes" "yes" ;;
    *) check "and the refusal names the declaration as the fault" "$OUT" "should name the stale declaration" ;;
esac

# 6. A FILE WITH NEITHER A WINDOW NOR A DECLARATION IS REFUSED. Silence there is
#    how a page that stopped drawing its window would read as compliant (L98).
E="$WORK/neither"; mkdir -p "$E"
printf '<!doctype html>\n<meta charset="utf-8">\n<p>no window, and nothing said about it</p>\n' \
    > "$E/silent.html"
check "a file with no window and no declaration is refused" "$(status_on "$E")" "1"

# 7. MEASURING NOTHING IS NOT A PASS. A record with no design files in it reports
#    exactly what a record in perfect health reports, unless it says so (L98).
F="$WORK/empty"; mkdir -p "$F"
check "a record holding no design files cannot be measured" "$(status_on "$F")" "2"
OUT="$(run_on "$F")"
case "$OUT" in
    *"CANNOT"*) check "and it says so rather than passing" "yes" "yes" ;;
    *) check "and it says so rather than passing" "$OUT" "should say it could not measure" ;;
esac

# 8. IT REPORTS HOW MANY IT MEASURED, so a run that judged one file and a run
#    that judged all of them are not the same line of output.
OUT="$(run_on "$B")"
case "$OUT" in
    *" 1 "*|*"1 file"*) check "it says how many files it measured" "yes" "yes" ;;
    *) check "it says how many files it measured" "$OUT" "should count the files measured" ;;
esac

harness_end
