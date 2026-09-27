#!/bin/bash
# The suite for scripts/check-design-dead-rules.sh.
#
# ovation#166 and ovation#148. A guard is only real once it has been seen to
# fail (L1), and this one DELETES things when it is believed, so the case that
# matters most is the one where it must stay silent: a rule for a state the page
# can only reach by being pressed. Every such class still has to be written as
# text somewhere in the script that applies it, and that is the whole reason the
# predicate reads string literals rather than the rendered DOM.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design dead rule tests" 29

TARGET="scripts/check-design-dead-rules.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_on() { OVATION_DESIGN_ROOT="$1" python3 "$TARGET" 2>&1; }
status_on() {
    OVATION_DESIGN_ROOT="$1" python3 "$TARGET"
}

root() { mkdir -p "$WORK/$1" && printf '%s' "$WORK/$1"; }

# ---------------------------------------------------------------------------
# The healthy file. Every class it declares is applied somewhere it can be.
# ---------------------------------------------------------------------------
CLEAN="$(root clean)"
cat > "$CLEAN/screen.html" <<'HTML'
<style>
.win { color: #111; }
.row { color: #222; }
.row .amt { color: #333; }
body { margin: 0; }
</style>
<div class="win"><div class="row"><span class="amt">1</span></div></div>
HTML
check_exit "a file whose every rule is applied passes" 0 status_on "$CLEAN"
check "and it says how many rules it judged" \
    "$(run_on "$CLEAN" | grep -c 'every one reachable')" "2"

# ---------------------------------------------------------------------------
# THE CASE THIS EXISTS FOR: a whole other screen's stylesheet, arrived by the
# file being copied from the last one.
# ---------------------------------------------------------------------------
COPIED="$(root copied)"
cat > "$COPIED/screen.html" <<'HTML'
<style>
.win { color: #111; }
.crow { color: #444; }
.cname { font-weight: 600; }
</style>
<div class="win">nothing else</div>
HTML
check_exit "a rule nothing can reach is refused" 1 status_on "$COPIED"
check "and it is named" "$(run_on "$COPIED" | grep -c '`.crow` cannot match')" "1"
check "and so is the class that cannot be reached" \
    "$(run_on "$COPIED" | grep -c '\.crow never named outside')" "1"
check "and the verdict counts them" \
    "$(run_on "$COPIED" | grep -c 'REFUSED: 2 of 3 rule')" "1"

# ---------------------------------------------------------------------------
# EVERY CLASS IN ONE SELECTOR, not merely one of them. This is the case that
# left half a deleted screen standing on the first attempt.
# ---------------------------------------------------------------------------
HALF="$(root half)"
cat > "$HALF/screen.html" <<'HTML'
<style>
.sel { background: #eee; }
.crow.sel { background: #ddd; }
.crow .n { color: #555; }
</style>
<div class="sel">n</div>
HTML
check_exit "a compound selector dies with the class that is gone" 1 status_on "$HALF"
check "and the surviving class alone does not rescue it" \
    "$(run_on "$HALF" | grep -c '`.crow.sel` cannot match')" "1"
check "nor does a descendant whose second word is used elsewhere" \
    "$(run_on "$HALF" | grep -c '`.crow .n` cannot match')" "1"
check "while the rule that IS applied survives" \
    "$(run_on "$HALF" | grep -c '`.sel` cannot match')" "0"

# ---------------------------------------------------------------------------
# A COMMA IS TWO SELECTORS. A rule is only dead when both halves are.
# ---------------------------------------------------------------------------
COMMA="$(root comma)"
cat > "$COMMA/screen.html" <<'HTML'
<style>
.here, .gone { color: #666; }
.gone, .alsogone { color: #777; }
</style>
<div class="here">x</div>
HTML
check "a selector list survives while one of its selectors can match" \
    "$(run_on "$COMMA" | grep -c '`.here, .gone` cannot match')" "0"
check "and dies when none of them can" \
    "$(run_on "$COMMA" | grep -c '`.gone, .alsogone` cannot match')" "1"

# ---------------------------------------------------------------------------
# A CLASS APPLIED ONLY BY SCRIPT IS ALIVE, including one for a state the page
# reaches only when something is pressed, which no render at rest would show.
# ---------------------------------------------------------------------------
BYSCRIPT="$(root byscript)"
cat > "$BYSCRIPT/screen.html" <<'HTML'
<style>
.open { display: block; }
.greyed { opacity: .4; }
.tip { color: #888; }
</style>
<div id="a"></div>
<script>
function el(t, c) { var n = document.createElement(t); if (c) n.className = c; return n; }
document.getElementById("a").className = "inv" + (waiting ? " greyed" : "");
document.querySelector(".open");
el("div", "tip");
</script>
HTML
check "a class the script applies is alive" \
    "$(run_on "$BYSCRIPT" | grep -c '`.greyed` cannot match')" "0"
check "so is one only ever handed to querySelector" \
    "$(run_on "$BYSCRIPT" | grep -c '`.open` cannot match')" "0"
check "so is one built by a helper" \
    "$(run_on "$BYSCRIPT" | grep -c '`.tip` cannot match')" "0"
check_exit "and the file passes" 0 status_on "$BYSCRIPT"

# ---------------------------------------------------------------------------
# PROSE AND COMMENTS DO NOT RESCUE A RULE. This is what let `.sheet` survive.
# ---------------------------------------------------------------------------
PROSE="$(root prose)"
cat > "$PROSE/screen.html" <<'HTML'
<style>
.win { color: #111; }
.sheet { position: absolute; }
</style>
<p>Round 1 rejected the option where the invoice is a sheet over the list.</p>
<div class="win">x</div>
<script>
/* The review sheet is a different screen, committed elsewhere. */
var x = 1;
</script>
HTML
check "a word in the record's prose does not keep a rule alive" \
    "$(run_on "$PROSE" | grep -c '`.sheet` cannot match')" "1"

# ---------------------------------------------------------------------------
# THE SHELL IS NOT THIS CHECK'S BUSINESS. A part is carried whole or not at all,
# so judging a rule inside one would order the opposite of what
# check-design-shell-inline.sh requires.
# ---------------------------------------------------------------------------
SHELLED="$(root shelled)"
mkdir -p "$SHELLED/shell"
cat > "$SHELLED/shell/window.css" <<'CSS'
.win { color: #111; }
.row { color: #222; }
CSS
cat > "$SHELLED/screen.html" <<'HTML'
<style>
.win { color: #111; }
.row { color: #222; }
.mine { color: #333; }
</style>
<div class="win">no row here</div>
HTML
check "a rule the file carries from the shell is left to the shell" \
    "$(run_on "$SHELLED" | grep -c '`.row` cannot match')" "0"
check "while the file's own dead rule is still refused" \
    "$(run_on "$SHELLED" | grep -c '`.mine` cannot match')" "1"
cat > "$SHELLED/screen.html" <<'HTML'
<style>
.win { color: #111; }
.row { color: #222; }
.mine { color: #333; }
</style>
<div class="win"><span class="mine">no row here</span></div>
HTML
check_exit "with its own rules all reachable the file passes" 0 status_on "$SHELLED"
check "and the verdict says how many rules it left to the shell" \
    "$(run_on "$SHELLED" | grep -c 'come verbatim from shell/')" "1"

# ---------------------------------------------------------------------------
# NOTHING SCANNED IS NOT A PASS, and each way of having nothing is its own
# outcome (L98, L11).
# ---------------------------------------------------------------------------
EMPTY="$(root empty)"
check_exit "an empty design root cannot measure" 2 status_on "$EMPTY"
check "and says so rather than reporting health" \
    "$(run_on "$EMPTY" | grep -c 'CANNOT MEASURE')" "1"

NOSTYLE="$(root nostyle)"
printf '<p>Just prose.</p>\n' > "$NOSTYLE/screen.html"
check_exit "a file with no stylesheet of its own cannot measure" 2 status_on "$NOSTYLE"
check "and its message names that cause rather than the empty one" \
    "$(run_on "$NOSTYLE" | grep -c 'carries no stylesheet of its own')" "1"

NOCLASS="$(root noclass)"
cat > "$NOCLASS/screen.html" <<'HTML'
<style>
body { margin: 0; }
h1 { font-size: 26px; }
</style>
<h1>An invoice</h1>
HTML
check_exit "a stylesheet naming no class at all cannot measure" 2 status_on "$NOCLASS"
check "and says which of the three empties it hit" \
    "$(run_on "$NOCLASS" | grep -c 'not one rule names a')" "1"

check_exit "a named file that is not there is refused, never skipped" \
    2 python3 "$TARGET" "$WORK/nowhere.html"

# ---------------------------------------------------------------------------
# THE COMMITTED RECORD ITSELF, which is the run the push gate makes.
# ---------------------------------------------------------------------------
check_exit "the committed design record passes" \
    0 python3 "$TARGET"

harness_end
