#!/bin/bash
# The suite for scripts/check-design-control-inset.sh.
#
# ovation#625. Dan, 2026-09-29, on the ovation#489 round: the chosen type's
# chooser sat against the left edge of its cell, its border touching the
# column's edge. He made it a standing rule rather than a one off fix: a control
# inside a table cell or panel keeps the same inset from the container's edge as
# the other controls there. The check measures that in a rendering, because an
# inset is the sum of paddings, margins and a tint that may or may not reach
# past the columns, and no stylesheet states it.
#
# THE COMMITTED RECORD IS RUN FIRST, or a check that refuses everything passes
# every planted case (L1). Every other case is a page BUILT to differ from its
# control in one way, so a refusal has one possible cause.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design control inset tests" 36

TARGET="scripts/check-design-control-inset.sh"
require_target "$TARGET"
harness_temp_dir WORK
: > "$WORK/no-exemptions.tsv"

harness_require_browser \
    "no headless browser, so nothing can be rendered and no claim here proves anything" \
    "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER" \
    env OVATION_DESIGN_ROOT="$WORK/nothing-here" "./$TARGET"

OVATION_BROWSER_GLOBS="$WORK/no-browser-here/*" OVATION_HEADLESS_BROWSER= \
    OVATION_DESIGN_ROOT="$WORK/nothing-here" "./$TARGET" > "$WORK/no-browser.txt" 2>&1
check "with no browser to find, even a record that is not there answers cannot measure" \
    "$?:$(grep -c 'CANNOT MEASURE: no headless browser found' "$WORK/no-browser.txt")" "3:1"

. "$(dirname "$0")/lib/rendered-run.sh"
# $1 the case, $2 the exemptions file (none by default).
judge() {
    rendered_run "$1" env OVATION_DESIGN_ROOT="$1" \
        OVATION_INSET_EXEMPTIONS="${2:-$WORK/no-exemptions.tsv}" "./$TARGET"
    OUT="$(cat "$1.out")"
}
says() { case "$OUT" in *"$2"*) check "$1" "yes" "yes" ;; *) check "$1" "$OUT" "should say: $2" ;; esac; }

# A screen holding one painted panel, whose body is given. The page and the
# screen share a background, so the panel's edge is the only edge drawn.
screen() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<HTML
<!doctype html>
<meta charset="utf-8">
<style>
  body { margin: 0; background: #FFFFFF; font: 14px/1.3 sans-serif; }
  .screen { padding: 40px; }
  .panel { background: #E4DED6; width: 420px; display: flex; align-items: center; gap: 10px; }
  .bordered { border: 1px solid #8C7F73; background: #F4F1ED; padding: 2px 8px; font: inherit; }
  .word { border: 0; background: none; font: inherit; }
  .push { margin-left: auto; }
  $2
</style>
<div class="screen">$3</div>
${4:-}
HTML
}

# 1. THE COMMITTED RECORD PASSES, and says what it measured.
rendered_run "$WORK/committed" "./$TARGET"; OUT="$(cat "$WORK/committed.out")"
check_rendered_status "every control in the committed record keeps its container's inset" "$WORK/committed" "0"
says "it says how many controls it measured" "control(s)"
says "and in how many states, rest and every press" "state(s)"

# 2. A CONTROL FLUSH WITH ITS PANEL'S EDGE IS REFUSED. This is the fault Dan saw.
A="$WORK/flush"; screen "$A/flush.html" '.panel { padding: 12px 12px 12px 0; }' \
    '<div class="panel"><button class="bordered">Choose a type</button><button class="bordered push">Keep</button></div>'
judge "$A"
check_rendered_status "a control whose edge touches its panel's edge is refused" "$A" "1"
says "it names the file" "flush.html"
says "and says the control sits at the edge" "sits 0px from"
says "and names the container it sits in by its class" "div.panel"

# 3. THE SAME PANEL WITH THE INSET HELD IS NOT. The control for 2 and 4 (L159).
B="$WORK/held"; screen "$B/held.html" '.panel { padding: 12px; }' \
    '<div class="panel"><button class="bordered">Choose a type</button><button class="bordered push">Keep</button></div>'
judge "$B"
check_rendered_status "two controls at one inset from their panel pass" "$B" "0"
says "and it counts the controls it measured" "2 control(s)"

# 4. TWO CONTROLS AT DIFFERENT INSETS FROM ONE PANEL ARE REFUSED.
C="$WORK/differ"; screen "$C/differ.html" '.panel { padding: 12px 20px 12px 12px; }' \
    '<div class="panel"><button class="bordered">Choose a type</button><button class="bordered push">Keep</button></div>'
judge "$C"
check_rendered_status "controls held at different insets in one panel are refused" "$C" "1"
says "it names the one inset" "12px"
says "and the other" "20px"

# 5. A BORDERLESS CONTROL IS MEASURED BY ITS WORDS, which are all anybody sees of
#    it. Its box sits at 12 and its words at 20, beside a bordered one at 20, so
#    measuring the box would refuse this.
D="$WORK/words"; screen "$D/words.html" '.panel { padding: 12px 20px 12px 12px; } .word { padding: 0 8px; }' \
    '<div class="panel"><button class="word">Cancel</button><button class="bordered push">Send</button></div>'
judge "$D"
check_rendered_status "a borderless control is measured by its words, not its box" "$D" "0"

# 6. A CONTROL WITH SOMETHING DRAWN BETWEEN IT AND THE EDGE IS NOT AGAINST THAT
#    EDGE. `Due` sits at the edge here, so the date button's own distance from it
#    is not an inset at all.
E="$WORK/between"; screen "$E/between.html" '.panel { padding: 12px; }' \
    '<div class="panel"><span>Dated 29 Aug, due</span><button class="bordered">12 Sep</button><button class="bordered push">Review</button></div>'
judge "$E"
check_rendered_status "a control with words between it and the edge is not held to that edge" "$E" "0"

# 7. AN EDGE NOTHING PAINTS IS NOT AN EDGE. A field row drawing only a rule
#    beneath it has no left edge anybody can see, so a control at its left is
#    measured from the painted panel around it.
F="$WORK/unpainted"; screen "$F/unpainted.html" '.panel { padding: 12px; display: block; } .field { border-bottom: 1px solid #8C7F73; padding: 6px 0; }' \
    '<div class="panel"><div class="field"><button class="bordered">Add someone</button></div></div>'
judge "$F"
check_rendered_status "an edge only a rule beneath draws is not the control's edge" "$F" "0"

# 8. A ROW THAT FILLS ITS LIST IS MEASURED BY ITS LABEL. A selected entry shaded
#    edge to edge is a list row, and its label keeps the inset its neighbours'
#    labels keep.
G="$WORK/row"; screen "$G/row.html" '.panel { padding: 4px 0; display: flex; flex-direction: column; align-items: stretch; width: 160px; } .item { border: 0; background: none; font: inherit; text-align: left; padding: 5px 14px; } .item.on { background: #D5CBBF; }' \
    '<div class="panel"><button class="item">On receipt</button><button class="item on">14 days</button><button class="item">30 days</button></div>'
judge "$G"
check_rendered_status "a shaded row filling its list is measured by its label" "$G" "0"

# 9. A CONTROL TOUCHING ITS PANEL'S TOP IS REFUSED TOO. Only the sides are held
#    to one another, but no side may sit at nothing.
H="$WORK/top"; screen "$H/top.html" '.panel { padding: 0 12px 12px; align-items: flex-start; height: 60px; }' \
    '<div class="panel"><button class="bordered">Choose a type</button><button class="bordered push">Keep</button></div>'
judge "$H"
check_rendered_status "a control touching its panel's top edge is refused" "$H" "1"
says "and it says which edge" "top"

# 10. A STATE REACHED BY A PRESS IS MEASURED. The panel is not drawn until the
#     button above it is pressed, which is where the fault in ovation#489 lived.
I="$WORK/pressed"; screen "$I/pressed.html" '.panel { padding: 12px 12px 12px 0; display: none; } .panel.open { display: flex; }' \
    '<button class="word" id="opener">Add a line</button><div class="panel"><button class="bordered">Choose a type</button></div>' \
    '<script>document.getElementById("opener").addEventListener("click", function () { document.querySelector(".panel").classList.add("open"); });</script>'
judge "$I"
check_rendered_status "a flush control reached only by pressing something is refused" "$I" "1"
says "and it says the state was reached by a press" "after pressing control 1"

# 11. THE APP'S MENU BAR IS NOT JUDGED. It is the system's, drawn at the system's
#     own insets, and Ovation places nothing in it.
J="$WORK/menubar"; screen "$J/menubar.html" '.menubar { background: #EEECE8; display: flex; } .panel { padding: 12px; }' \
    '<div class="menubar"><span role="button" tabindex="0">Edit</span></div><div class="panel"><button class="bordered">Keep</button></div>'
judge "$J"
check_rendered_status "a control in the menu bar is not held to its insets" "$J" "0"

# 12. AN EXEMPTION NAMING ITS ISSUE COVERS A DIFFERENCE, AND SAYS SO.
printf 'differ.html\tdiv.panel\tbutton.bordered.push\tovation#9999\tA known difference, filed to be fixed.\n' > "$WORK/one.tsv"
judge "$C" "$WORK/one.tsv"
check_rendered_status "a difference its exemption names passes" "$C" "0"
says "and the pass says what was exempted, and under which issue" "ovation#9999"

# 13. AN EXEMPTION NEVER COVERS A CONTROL AT ZERO. A control touching its edge
#     is the fault itself, not a difference of opinion about an inset.
printf 'flush.html\tdiv.panel\tbutton.bordered\tovation#9999\tA known difference.\n' > "$WORK/zero.tsv"
judge "$A" "$WORK/zero.tsv"
check_rendered_status "an exemption does not cover a control at the edge" "$A" "1"

# 14. AN EXEMPTION THAT MATCHES NOTHING IS REFUSED, or it outlives its fix and
#     reads as a decision for ever (L346).
printf 'held.html\tdiv.panel\tbutton.bordered.push\tovation#9999\tA known difference.\n' > "$WORK/stale.tsv"
judge "$B" "$WORK/stale.tsv"
check_rendered_status "an exemption covering a difference that is not there is refused" "$B" "1"
says "and it says the exemption is stale" "stale"

# 15. AN EXEMPTION WITH NO ISSUE IS REFUSED: nothing would ever end it (L65).
printf 'differ.html\tdiv.panel\tbutton.bordered.push\t\tA known difference.\n' > "$WORK/noissue.tsv"
judge "$C" "$WORK/noissue.tsv"
check_rendered_status "an exemption naming no issue is refused" "$C" "1"
says "and it says the issue is missing" "no issue"

# 15b. A CONTROL SQUEEZED TO ITS EDGE ONLY AT HALF SCREEN IS REFUSED. The panel
#      loses its padding only in a narrow page, which is where the app's minimum
#      window is drawn, so a check measuring the declared width alone passes it.
Q="$WORK/narrow"; screen "$Q/narrow.html" '.panel { padding: 12px; } @media (max-width: 1100px) { .panel { padding-left: 0; } }' \
    '<div class="win"><div class="panel"><button class="bordered">Choose a type</button><button class="bordered push">Keep</button></div></div>'
judge "$Q"
check_rendered_status "a control that meets its edge only in the minimum window is refused" "$Q" "1"
says "and it says it was the minimum window" "minimum window"

# 15c. WITH NO MINIMUM TO READ IT IS USED WRONGLY, never a pass at some default.
rendered_run "$WORK/nominimum" env OVATION_DESIGN_ROOT="$B" OVATION_INSET_EXEMPTIONS="$WORK/no-exemptions.tsv" \
    OVATION_WINDOW_SOURCE="$WORK/no-minimum.swift" "./$TARGET"
check_rendered_status "a window source that says no minimum is refused as used wrongly" "$WORK/nominimum" "2"

# 16. A RECORD WITH NOTHING TO MEASURE CANNOT BE MEASURED.
K="$WORK/empty"; mkdir -p "$K"
judge "$K"
check_rendered_status "a record with no design file in it cannot be measured" "$K" "2"
says "and it says so rather than passing" "CANNOT MEASURE"

# 17. IT NEVER QUOTES THE PAGE. A control's words can be a client's name on the
#     Clients screen, so a refusal names controls by their classes.
P="$WORK/private"; screen "$P/private.html" '.panel { padding: 12px 12px 12px 0; }' \
    '<div class="panel"><button class="bordered">Somebody Private</button></div>'
judge "$P"
check_rendered_status "a flush control carrying a person's name is refused like any other" "$P" "1"
check "and the refusal does not repeat the words on it" "$(grep -c 'Somebody Private' "$P.out")" "0"

harness_end
