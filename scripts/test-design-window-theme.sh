#!/bin/bash
# The suite for scripts/check-design-window-theme.sh.
#
# Twice on 2026-09-29 a design file let the record PAGE's own theme reach into
# the app it draws: review-send.html's message editor and its title bar text
# took the page's dark tokens and went dark on dark when the page was read in
# dark mode. The app is pinned to light (ovation#479), so nothing inside the
# screen may change with the page around it. The check renders every file in
# both page themes and requires what the screen paints to be identical.
#
# THE COMMITTED RECORD IS RUN FIRST (L1), and every other case is a page built
# to differ from its control in one way.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design window theme tests" 22

TARGET="scripts/check-design-window-theme.sh"
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
judge() {
    rendered_run "$1" env OVATION_DESIGN_ROOT="$1" \
        OVATION_THEME_EXEMPTIONS="${2:-$WORK/no-exemptions.tsv}" "./$TARGET"
    OUT="$(cat "$1.out")"
}
says() { case "$OUT" in *"$2"*) check "$1" "yes" "yes" ;; *) check "$1" "$OUT" "should say: $2" ;; esac; }

# A record page with a light and a dark theme of its own, drawing one screen.
# $2 is extra CSS, $3 the screen's body, $4 anything after the screen.
page() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<HTML
<!doctype html>
<meta charset="utf-8">
<style>
  :root { --page-ink: #1A1B1C; --page-panel: #FFFFFF; }
  :root[data-theme="dark"] { --page-ink: #ECEDEE; --page-panel: #1C1D1F; }
  body { margin: 0; color: var(--page-ink); background: var(--page-panel); font: 14px/1.3 sans-serif; }
  .screen { background: #CFC9C1; padding: 20px; }
  .win { background: #FBF4EF; padding: 12px; }
  $2
</style>
<p>The record's own prose, which follows the page's theme.</p>
<div class="screen"><div class="win">$3</div></div>
${4:-}
HTML
}

# 1. THE COMMITTED RECORD PASSES, and says what it compared.
rendered_run "$WORK/committed" "./$TARGET"; OUT="$(cat "$WORK/committed.out")"
check_rendered_status "every committed screen paints the same in both page themes" "$WORK/committed" "0"
says "it says how many states it compared" "state(s)"

# 2. TEXT THAT INHERITS THE PAGE'S INK IS REFUSED. This is the title bar's fault:
#    nothing in the screen named a page token, it simply never set its own.
A="$WORK/inherits"; page "$A/inherits.html" '' '<span class="title">Review and send</span>'
judge "$A"
check_rendered_status "text inside the screen that inherits the page's ink is refused" "$A" "1"
says "it names the file" "inherits.html"
says "it names the element by its class" "span.title"
says "and says it is the text that changed" "text"

# 3. THE SAME SCREEN SETTING ITS OWN INK PASSES. The control for 2 (L159).
B="$WORK/own"; page "$B/own.html" '.win { color: #1A1B1C; }' '<span class="title">Review and send</span>'
judge "$B"
check_rendered_status "a screen that sets its own ink passes in both themes" "$B" "0"

# 4. A SURFACE PAINTED FROM A PAGE TOKEN IS REFUSED. The message editor's fault.
C="$WORK/surface"; page "$C/surface.html" '.win { color: #1A1B1C; } .edit { background: var(--page-panel); border: 1px solid #E0D0C4; }' \
    '<textarea class="edit">Hello</textarea>'
judge "$C"
check_rendered_status "a field painted from a page token is refused" "$C" "1"
says "and it names the background" "background"

# 5. A LEAK REACHED ONLY BY A PRESS IS REFUSED.
D="$WORK/pressed"; page "$D/pressed.html" '.win { color: #1A1B1C; } .panel { display: none; background: var(--page-panel); } .panel.open { display: block; }' \
    '<button id="open">Open</button><div class="panel">A panel</div>' \
    '<script>document.getElementById("open").addEventListener("click", function () { document.querySelector(".panel").classList.add("open"); });</script>'
judge "$D"
check_rendered_status "a page token reached only after a press is refused" "$D" "1"
says "and it says which press reached it" "after pressing control 1"

# 6. THE PAGE ITSELF MAY FOLLOW ITS THEME. Only the screen is judged.
E="$WORK/pageonly"; page "$E/pageonly.html" '.win { color: #1A1B1C; } .note { color: var(--page-ink); }' \
    '<span>fixed</span>' '<p class="note">a page note in the page theme</p>'
judge "$E"
check_rendered_status "the record page following its own theme outside the screen passes" "$E" "0"

# 7. AN EXEMPTION NAMING ITS ISSUE COVERS AN ELEMENT, AND SAYS SO.
printf 'inherits.html\tspan.title\tovation#9999\tBeing fixed on its own branch.\n' > "$WORK/one.tsv"
judge "$A" "$WORK/one.tsv"
check_rendered_status "a difference its exemption names passes" "$A" "0"
says "and the pass names the issue it waits on" "ovation#9999"

# 8. A STALE EXEMPTION IS REFUSED (L346).
printf 'own.html\tspan.title\tovation#9999\tBeing fixed on its own branch.\n' > "$WORK/stale.tsv"
judge "$B" "$WORK/stale.tsv"
check_rendered_status "an exemption covering nothing is refused" "$B" "1"
says "and it says it is stale" "stale"

# 9. AN EXEMPTION NAMING NO ISSUE IS REFUSED (L65).
printf 'inherits.html\tspan.title\t\tBeing fixed.\n' > "$WORK/noissue.tsv"
judge "$A" "$WORK/noissue.tsv"
check_rendered_status "an exemption naming no issue is refused" "$A" "1"
says "and it says the issue is missing" "no issue"

# 10. NOTHING TO COMPARE IS NOT A PASS.
F="$WORK/empty"; mkdir -p "$F"
judge "$F"
check_rendered_status "a record with no design file cannot be measured" "$F" "2"

# 11. IT NEVER QUOTES THE PAGE (docs/PRIVACY-FLOOR.md).
P="$WORK/private"; page "$P/private.html" '' '<span class="who">Somebody Private</span>'
judge "$P"
check_rendered_status "a leaking element carrying a person's name is refused like any other" "$P" "1"
check "and the refusal does not repeat its words" "$(grep -c 'Somebody Private' "$P.out")" "0"

harness_end
