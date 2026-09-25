#!/bin/bash
# The suite for scripts/lift-design-harness.sh.
#
# ovation#196. What has to be right about this tool is the FAITHFULNESS answer.
# Lifting a screen out of a design file is a text edit that always produces
# something that renders, so a lift that lost the screen's typography, its box
# model or its colour still looks finished, and the round that follows judges a
# screen the product will never draw. Every case below therefore drives one
# outcome and asserts it by name, and the two that matter most PLANT a loss and
# require the check to find it (L1).
#
# THE STAND IN CARRIES THE REFUSALS, THE COMMITTED FILES CARRY THE PROOF. A
# fixture design file, built here, is what the refusals are driven against, so a
# case can be shaped to produce exactly one of them; the real lift is then run
# against docs/design/invoice-pdf.html and docs/design/invoice-list.html, which
# is the claim anybody actually relies on. A tool proved only against a fixture
# is one shaped to the fixture.
#
# NOTHING HERE TOUCHES THE COMMITTED FILES. Every lift writes into a throwaway
# directory, every damaged copy is a copy, and the last case reads the two design
# files back and asserts they are byte for byte what they were (L2, L5).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design harness lift tests" 72

TARGET="scripts/lift-design-harness.sh"
require_target "$TARGET"
require_target "docs/design/invoice-pdf.html"
require_target "docs/design/invoice-list.html"
harness_temp_dir WORK

BEFORE="$(shasum -a 256 docs/design/invoice-pdf.html docs/design/invoice-list.html)"

run() { python3 "$TARGET" "$@" 2>&1; }
lift() { python3 "$TARGET" "$@"; }
says() { grep -qF "$2" <<< "$1" && echo yes || echo no; }

# ---------------------------------------------------------------------------
# The stand in design file. It is a design file in miniature: a page whose own
# `body` rule sets the typography the screen silently inherits, a screen with a
# rail in it, a labelled fixture list, a builder and the file's own mounting
# code below it.
# ---------------------------------------------------------------------------
STANDIN="$WORK/standin.html"
cat > "$STANDIN" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>A stand in design file</title>
<style>
body { font-family: ui-monospace, monospace; font-size: 20px; line-height: 2; }
.screen { width: 300px; background: #EEEEEE; }
.row { padding: 4px; }
.rail { width: 80px; }
</style>
</head>
<body>
<h1>A stand in</h1>
<div id="stage"></div>
<script>
var FIXTURES = [
  { label: "One", heading: "First" },
  { label: "Two", heading: "Second" }
];
function el(t, c, x) {
  var n = document.createElement(t);
  if (c) { n.className = c; }
  if (x !== undefined) { n.textContent = x; }
  return n;
}
function buildThing(f) {
  var screen = el("div", "screen");
  screen.append(el("div", "row", "Needs you"));
  screen.append(el("div", "row", f.heading));
  screen.append(el("div", "rail", "a rail"));
  return screen;
}
var stage = document.getElementById("stage");
function draw() { stage.replaceChildren(buildThing(FIXTURES[0])); }
draw();
</script>
</body>
</html>
HTML

# A spec, written from a template so a case can change ONE field and nothing
# else. The source is substituted rather than typed, so no case can point at a
# file it did not mean to.
spec_for() {
    local into="$1" source="$2"
    shift 2
    python3 - "$into" "$source" "$@" <<'PY'
import json, sys
spec = {
    "source": sys.argv[2],
    "screen": ".screen",
    "fixtures": "FIXTURES",
    "label": "label",
    "screen_from": "buildThing(fixture)",
    "option_one": "One",
    "builder_ends_before": 'var stage = document.getElementById("stage");',
    "page_rules": {"body": ".screen"},
    "moves": [{"field": "heading", "variable": "CARD_HEADING", "holds": '"Needs you"',
               "values": ["Needs you", "Waiting on you"]}],
    "same": {"tolerance": 0, "ignore": []}
}
for change in sys.argv[3:]:
    key, value = change.split("=", 1)
    if value == "__DROP__":
        spec.pop(key, None)
    else:
        spec[key] = json.loads(value)
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(spec, handle, indent=1)
PY
}

SPEC="$WORK/standin.json"
spec_for "$SPEC" "standin.html"

# ---------------------------------------------------------------------------
# 1. USED WRONGLY, and a spec that cannot be believed. These are told apart
#    because a spec with a typo in it and a spec that is not there need
#    different remedies (L11).
# ---------------------------------------------------------------------------
check_exit "no arguments at all is used wrongly" 2 lift
check "and it prints what it takes" "$(says "$(run)" "lift-design-harness.sh <spec.json> <out-dir>")" "yes"
check_exit "a spec that is not there is used wrongly" 2 lift "$WORK/no-such.json" "$WORK/out"

printf 'not json at all\n' > "$WORK/broken.json"
check_exit "a spec that is not JSON is refused as a spec" 4 lift "$WORK/broken.json" "$WORK/out"

spec_for "$WORK/no-screen.json" "standin.html" "screen=__DROP__"
check_exit "a spec missing a field is refused" 4 lift "$WORK/no-screen.json" "$WORK/out"
check "and the missing field is named" \
    "$(says "$(run "$WORK/no-screen.json" "$WORK/out")" "missing a field: screen")" "yes"

spec_for "$WORK/no-moves.json" "standin.html" "moves=[]"
check_exit "a harness that moves nothing is refused" 4 lift "$WORK/no-moves.json" "$WORK/out"
check "and it says why, because every option would draw the same screen" \
    "$(says "$(run "$WORK/no-moves.json" "$WORK/out")" "draws every option identically")" "yes"

spec_for "$WORK/bad-var.json" "standin.html" \
    'moves=[{"field": "heading", "variable": "not a name", "holds": "\"Needs you\"", "values": ["A", "B"]}]'
check_exit "a variable JavaScript cannot declare is refused" 4 lift "$WORK/bad-var.json" "$WORK/out"

# ovation#407. A move has to say which values the round gives it, because the only
# way to prove a moved value MOVES something is to draw each one. Fewer than two,
# or two the same, is a round with no question in it.
spec_for "$WORK/no-values.json" "standin.html" \
    'moves=[{"field": "heading", "variable": "CARD_HEADING", "holds": "\"Needs you\""}]'
check_exit "a move that names no values is refused" 4 lift "$WORK/no-values.json" "$WORK/out"
check "and the refusal names what is missing" \
    "$(says "$(run "$WORK/no-values.json" "$WORK/out")" "move 1 must list the values")" "yes"
spec_for "$WORK/one-value.json" "standin.html" \
    'moves=[{"field": "heading", "variable": "CARD_HEADING", "holds": "\"Needs you\"", "values": ["Needs you"]}]'
check_exit "a move with one value is refused" 4 lift "$WORK/one-value.json" "$WORK/out"
spec_for "$WORK/twin-values.json" "standin.html" \
    'moves=[{"field": "heading", "variable": "CARD_HEADING", "holds": "\"Needs you\"", "values": ["A", "A"]}]'
check_exit "a move whose values repeat one is refused" 4 lift "$WORK/twin-values.json" "$WORK/out"

spec_for "$WORK/bad-tol.json" "standin.html" 'same={"tolerance": "loose", "ignore": []}'
check_exit "a tolerance that is not a whole number of pixels is refused" \
    4 lift "$WORK/bad-tol.json" "$WORK/out"

# ---------------------------------------------------------------------------
# 2. THE DESIGN FILE'S SHAPE. A marker matching nothing would lift the whole
#    script, mounting code and all, and one matching twice would cut at
#    whichever came first with nothing saying a choice had been made (L100).
# ---------------------------------------------------------------------------
spec_for "$WORK/nowhere.json" "standin.html" 'builder_ends_before="var nothing = 1;"'
check_exit "a line the builder ends before that is on no line is refused" \
    5 lift "$WORK/nowhere.json" "$WORK/out"
check "and it says how many lines carried it" \
    "$(says "$(run "$WORK/nowhere.json" "$WORK/out")" "is on 0 line(s)")" "yes"

TWICE="$WORK/twice.html"
python3 - "$STANDIN" "$TWICE" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
mark = 'var stage = document.getElementById("stage");'
assert text.count(mark) == 1, "the fixture change matched nothing, so this case tests nothing"
open(sys.argv[2], "w", encoding="utf-8").write(text.replace(mark, mark + "\n" + mark, 1))
PY
spec_for "$WORK/twice.json" "twice.html"
check_exit "one that is on two lines is refused too" 5 lift "$WORK/twice.json" "$WORK/out"

TWOSTYLES="$WORK/twostyles.html"
python3 - "$STANDIN" "$TWOSTYLES" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
assert "</style>" in text, "the fixture change matched nothing"
open(sys.argv[2], "w", encoding="utf-8").write(
    text.replace("</style>", "</style>\n<style>.late { color: red; }</style>", 1))
PY
spec_for "$WORK/twostyles.json" "twostyles.html"
check_exit "a design file carrying two stylesheets is refused" \
    5 lift "$WORK/twostyles.json" "$WORK/out"

NOSCRIPT="$WORK/noscript.html"
python3 - "$STANDIN" "$NOSCRIPT" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
out = re.sub(r"<script>.*</script>", "", text, flags=re.S)
assert "<script" not in out, "the fixture change left a script behind"
open(sys.argv[2], "w", encoding="utf-8").write(out)
PY
spec_for "$WORK/noscript.json" "noscript.html"
check_exit "a design file with no script at all is refused" \
    5 lift "$WORK/noscript.json" "$WORK/out"

# ---------------------------------------------------------------------------
# 3. THE LIFT'S OWN REFUSALS. Each of these is a step the spec asked for that
#    took no effect, and a step that took no effect still reads as taken.
# ---------------------------------------------------------------------------
spec_for "$WORK/norule.json" "standin.html" 'page_rules={"nav.side": ".screen"}'
check_exit "a page rule matching no rule in the stylesheet is refused" \
    6 lift "$WORK/norule.json" "$WORK/out"
check "and it says the inheritance is still lost" \
    "$(says "$(run "$WORK/norule.json" "$WORK/out")" "is still lost")" "yes"

spec_for "$WORK/nostrip.json" "standin.html" 'strip=["var nothing = 1;"]'
check_exit "a stripped line matching nothing is refused" \
    6 lift "$WORK/nostrip.json" "$WORK/out"

spec_for "$WORK/nomove.json" "standin.html" \
    'moves=[{"field": "heading", "variable": "CARD_HEADING", "holds": "\"Not in the builder\"", "values": ["A", "B"]}]'
check_exit "a moved value that is not in the builder is refused" \
    6 lift "$WORK/nomove.json" "$WORK/out"

spec_for "$WORK/taken.json" "standin.html" \
    'moves=[{"field": "heading", "variable": "buildThing", "holds": "\"Needs you\"", "values": ["A", "B"]}]'
check_exit "a move whose variable name the builder already uses is refused" \
    6 lift "$WORK/taken.json" "$WORK/out"

ALREADY="$WORK/already.html"
python3 - "$STANDIN" "$ALREADY" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
mark = "function buildThing(f) {"
assert mark in text, "the fixture change matched nothing"
open(sys.argv[2], "w", encoding="utf-8").write(
    text.replace(mark, "function buildScreen() { return null; }\n" + mark, 1))
PY
spec_for "$WORK/already.json" "already.html"
check_exit "a builder that already defines buildScreen is refused" \
    6 lift "$WORK/already.json" "$WORK/out"

# ---------------------------------------------------------------------------
# 4. WHAT THE LIFT WRITES. Read from the files, because the tool's own summary
#    is a claim about them rather than the thing anybody uses.
# ---------------------------------------------------------------------------
OUT="$WORK/out"
check_exit "the lift writes the harness" 0 lift "$SPEC" "$OUT"
check "both files it names are there" \
    "$([ -f "$OUT/screen.css" ] && [ -f "$OUT/builder.js" ] && echo both || echo missing)" "both"
check "the lifted builder carries none of the file's own mounting code" \
    "$(grep -c 'getElementById' "$OUT/builder.js")" "0"
check "nor the draw the file wires to it" "$(grep -c 'function draw()' "$OUT/builder.js")" "0"
check "the page's own rule is retargeted onto the screen" \
    "$(grep -c '^\.screen { font-family: ui-monospace' "$OUT/screen.css")" "1"
check "and the page selector it came from is gone" \
    "$(grep -c '^body {' "$OUT/screen.css")" "0"
check "the moved value is a variable, declared once above the builder" \
    "$(grep -c '^var CARD_HEADING = "Needs you";$' "$OUT/builder.js")" "1"
check "and buildScreen sets it from the variant" \
    "$(grep -c 'variant.heading !== undefined' "$OUT/builder.js")" "1"
check "buildScreen refuses a label that is not on exactly one fixture" \
    "$(grep -c 'found.length !== 1' "$OUT/builder.js")" "1"

# STRIP IS FOR THE MOUNTING CODE ABOVE THE CUT, which is the shape a file whose
# fixtures are declared below its own mounting has: cutting high enough to keep
# them keeps the mounting too, and this is what takes it back out.
STRIPPED="$WORK/stripped"
spec_for "$WORK/strip.json" "standin.html" \
    'builder_ends_before="draw();"' \
    'strip=["var stage = document.getElementById(\"stage\");", "function draw() { stage.replaceChildren(buildThing(FIXTURES[0])); }"]'
check_exit "a strip line that is there takes it out" 0 lift "$WORK/strip.json" "$STRIPPED"
check "and the mounting code really is gone" \
    "$(grep -c 'getElementById\|replaceChildren' "$STRIPPED/builder.js")" "0"
check "a cut that high still leaves a builder to lift" \
    "$(grep -c '^function buildThing(f) {$' "$STRIPPED/builder.js")" "1"

# ---------------------------------------------------------------------------
# Everything below renders. With no browser there is no answer to give, and
# giving one would be a green tick over an unrun check.
# ---------------------------------------------------------------------------
python3 "$TARGET" --check "$SPEC" "$OUT" >/dev/null 2>&1
PROBE=$?
if [ "$PROBE" = "3" ]; then
    harness_cannot_measure \
        "no headless browser, so no lift can be rendered beside the file it came from" \
        "npx playwright install chromium"
fi

# ---------------------------------------------------------------------------
# 5. THE FAITHFULNESS CHECK, on the stand in. The pair that matters is here:
#    the SAME builder, lifted with the page's rule retargeted and without it,
#    and the check has to tell them apart. Without the retarget the screen
#    draws in the browser's default face, and it still looks like a screen,
#    which is the whole reason this tool exists.
# ---------------------------------------------------------------------------
check_exit "the lift it just wrote draws the same screen" 0 lift --check "$SPEC" "$OUT"
check "and it says how much it compared" \
    "$(says "$(run --check "$SPEC" "$OUT")" "element(s), tag, classes and box")" "yes"

LOST="$WORK/lost"
spec_for "$WORK/lost.json" "standin.html" "page_rules={}"
check_exit "a lift that retargets nothing is written all the same" 0 lift "$WORK/lost.json" "$LOST"
check_exit "and the check finds the screen drawn differently" 1 lift --check "$WORK/lost.json" "$LOST"
check "it says DIFFERS rather than refusing for some other reason" \
    "$(says "$(run --check "$WORK/lost.json" "$LOST")" "DIFFERS:")" "yes"
DIFFOUT="$(run --check "$WORK/lost.json" "$LOST")"
check "and every line of the difference names an element and its box, on both sides" \
    "$(printf '%s\n' "$DIFFOUT" | grep -cE \
        '^    the (design file|harness) +[a-z]+[.a-z0-9-]* at [^,]+, x -?[0-9]+, y -?[0-9]+, [0-9]+ by [0-9]+$')" \
    "$(printf '%s\n' "$DIFFOUT" | grep -c '^    the ')"
check "and it names the remedy, which is the retarget" \
    "$(says "$(run --check "$WORK/lost.json" "$LOST")" "page_rules")" "yes"

# ---------------------------------------------------------------------------
# ovation#407. A MOVED VALUE THAT MOVES NOTHING. The faithfulness check above
# draws option 1, where the moved value still holds its original, so it is blind
# by construction to a value the builder never reads while it builds: a value
# baked into a literal the script evaluates ONCE, at load. That is how a round on
# the invoice list drew one screen twice under a readout naming two words. The
# stand in below reads its heading out of such a literal; the lift still
# succeeds, the faithfulness check still says SAME, and --check has to refuse.
# The live stand in is the positive control, in the same fixture (L159).
# ---------------------------------------------------------------------------
check "a move the builder reads while it builds is proved to move the screen" \
    "$(says "$(run --check "$SPEC" "$OUT")" "MOVES: variant.heading draws 2 different screens")" "yes"

INERT="$WORK/inert.html"
python3 - "$STANDIN" "$INERT" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
old = 'screen.append(el("div", "row", "Needs you"));'
assert text.count(old) == 1, "the plant matched nothing, so this case proves nothing"
text = text.replace(old, 'screen.append(el("div", "row", AT_LOAD[0]));', 1)
mark = "var FIXTURES = ["
assert text.count(mark) == 1, "the plant matched nothing, so this case proves nothing"
text = text.replace(mark, 'var AT_LOAD = ["Needs you"];\n' + mark, 1)
open(sys.argv[2], "w", encoding="utf-8").write(text)
PY
spec_for "$WORK/inert.json" "inert.html"
INERTOUT="$WORK/inertout"
check_exit "a value held in a literal built at load still lifts" 0 lift "$WORK/inert.json" "$INERTOUT"
INERTSAYS="$(run --check "$WORK/inert.json" "$INERTOUT")"
check "and still draws option 1 the way the design file does" "$(says "$INERTSAYS" "SAME:")" "yes"
check_exit "but --check refuses it, because its values draw one screen" \
    8 lift --check "$WORK/inert.json" "$INERTOUT"
check "it names the move and the values that drew the same screen" \
    "$(says "$INERTSAYS" "INERT: variant.heading draws the same screen for values 1 and 2")" "yes"
check "and it names the cause to look for" "$(says "$INERTSAYS" "evaluated once, when the script loads")" "yes"
check "it never prints a value, so no fixture's wording reaches the terminal" \
    "$(grep -c 'Waiting on you' <<< "$INERTSAYS")" "0"

spec_for "$WORK/nolabel.json" "standin.html" 'option_one="Three"'
check_exit "an option 1 label on no fixture cannot be read" \
    7 lift --check "$WORK/nolabel.json" "$OUT"
check "and it says how many carried it" \
    "$(says "$(run --check "$WORK/nolabel.json" "$OUT")" "0 of the 2 fixtures")" "yes"

BOTH="$WORK/both.html"
python3 - "$STANDIN" "$BOTH" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
mark = '{ label: "Two", heading: "Second" }'
assert mark in text, "the fixture change matched nothing"
open(sys.argv[2], "w", encoding="utf-8").write(
    text.replace(mark, '{ label: "One", heading: "Second" }', 1))
PY
spec_for "$WORK/both.json" "both.html"
BOTHOUT="$WORK/bothout"
python3 "$TARGET" "$WORK/both.json" "$BOTHOUT" >/dev/null 2>&1
check_exit "an option 1 label on two fixtures cannot be read either" \
    7 lift --check "$WORK/both.json" "$BOTHOUT"

spec_for "$WORK/manyscreens.json" "standin.html" 'screen=".row"'
check_exit "a screen selector matching several elements cannot be read" \
    7 lift --check "$WORK/manyscreens.json" "$OUT"

spec_for "$WORK/ignorenothing.json" "standin.html" 'same={"tolerance": 0, "ignore": [".no-such-class"]}'
check_exit "an ignore selector matching nothing in either rendering is refused" \
    7 lift --check "$WORK/ignorenothing.json" "$OUT"
check "and it says an exemption matching nothing still reads as one" \
    "$(says "$(run --check "$WORK/ignorenothing.json" "$OUT")" "still reads as a deliberate")" "yes"

spec_for "$WORK/ignorerail.json" "standin.html" 'same={"tolerance": 0, "ignore": [".rail"]}'
check_exit "an ignore selector that matches leaves the rest compared" \
    0 lift --check "$WORK/ignorerail.json" "$OUT"
check "and the run says what it ignored, so a loosened rule is never silent" \
    "$(says "$(run --check "$WORK/ignorerail.json" "$OUT")" "ignoring     .rail")" "yes"

check_exit "a check with no harness written is used wrongly" \
    2 lift --check "$SPEC" "$WORK/never-written"
check "and with no browser to render in, nothing is measured" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" python3 "$TARGET" --check "$SPEC" "$OUT" \
        >/dev/null 2>&1; printf '%s' "$?")" "3"

# ---------------------------------------------------------------------------
# 6. THE COMMITTED DESIGN FILES. A tool proved only against a fixture is one
#    shaped to the fixture, so the real claim is made against two files that
#    mount themselves differently, draw different screens and differ in what a
#    variant moves.
# ---------------------------------------------------------------------------
PDF="$WORK/pdf"
python3 - "$WORK/pdf.json" "$PWD/docs/design/invoice-pdf.html" <<'PY'
import json, sys
json.dump({
    "source": sys.argv[2],
    "screen": ".page",
    "fixtures": "FIXTURES",
    "screen_from": "buildPage(fixture)",
    "option_one": "Ordinary",
    "builder_ends_before": 'var bar = document.getElementById("fixbar");',
    "page_rules": {"body": ".page"},
    "moves": [{"field": "dueLabel", "variable": "DUE_LABEL", "holds": '"Amount due"',
               "values": ["Amount due", "Balance due"]}],
    "same": {"tolerance": 0, "ignore": []}
}, open(sys.argv[1], "w", encoding="utf-8"), indent=1)
PY
check_exit "the invoice PDF design lifts" 0 lift "$WORK/pdf.json" "$PDF"
check_exit "and the harness draws the screen it draws" 0 lift --check "$WORK/pdf.json" "$PDF"

LIST="$WORK/list"
python3 - "$WORK/list.json" "$PWD/docs/design/invoice-list.html" <<'PY'
import json, sys
json.dump({
    "source": sys.argv[2],
    "screen": ".screen",
    "fixtures": '[{ label: "A day with work waiting", layout: "" }]',
    "screen_from": "windowFor(fixture.layout)",
    "option_one": "A day with work waiting",
    "builder_ends_before":
        'function drawList() { document.getElementById("stage").replaceChildren(windowFor("")); }',
    "page_rules": {"body": ".screen"},
    "moves": [{"field": "cardHeading", "variable": "CARD_HEADING", "holds": '"Needs you"',
               "values": ["Needs you", "Waiting on you"]}],
    "same": {"tolerance": 0, "ignore": []}
}, open(sys.argv[1], "w", encoding="utf-8"), indent=1)
PY
check_exit "the invoice list design lifts too" 0 lift "$WORK/list.json" "$LIST"
check_exit "and its harness draws the screen it draws" 0 lift --check "$WORK/list.json" "$LIST"

# ONE RULE DROPPED FROM THE LIFTED COPY. This is the loss the tool exists to
# catch, staged on a real file: the stylesheet still parses, the builder still
# runs, and the screen still renders.
DROPPED="$WORK/dropped"
mkdir -p "$DROPPED"
cp "$LIST/builder.js" "$DROPPED/builder.js"
python3 - "$LIST/screen.css" "$DROPPED/screen.css" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
old = ".screen {\n  background: var(--page-bg); color: var(--page-ink);"
assert old in text, "the plant matched nothing, so this case proves nothing"
open(sys.argv[2], "w", encoding="utf-8").write(
    text.replace(old, ".no-such-thing {\n  background: var(--page-bg); color: var(--page-ink);", 1))
PY
check_exit "one rule dropped from the lifted stylesheet is caught" \
    1 lift --check "$WORK/list.json" "$DROPPED"
check "and the element it names is one a person can find in the screen" \
    "$(run --check "$WORK/list.json" "$DROPPED" | grep -c '^    the design file  div.screen at the screen')" "1"

# THE DOCUMENT MODE, which is what ovation#194 turned out to be: two renderings
# of the same markup differing by a few pixels in one row, with the lift
# innocent. The seam composes the harness page with no doctype, so the fault can
# be produced on purpose rather than waited for.
# ovation#407 ON THE FILE IT HAPPENED IN. The round for ovation#129 moved an
# action's words, and invoice-list.html then held its rows in a literal built at
# load. It now builds them in groupsFor() on every draw, so the same move on the
# committed file is proved to move the screen, and a copy with the literal put
# back is refused: the pair is one fixture with and without the fault.
python3 - "$WORK/action.json" "$PWD/docs/design/invoice-list.html" <<'PY'
import json, sys
json.dump({
    "source": sys.argv[2],
    "screen": ".screen",
    "fixtures": '[{ label: "A day with work waiting", layout: "" }]',
    "screen_from": "windowFor(fixture.layout)",
    "option_one": "A day with work waiting",
    "builder_ends_before":
        'function drawList() { document.getElementById("stage").replaceChildren(windowFor("")); }',
    "page_rules": {"body": ".screen"},
    "moves": [{"field": "action", "variable": "ACTION_WORDS", "holds": '"Add tax status"',
               "values": ["Add tax status", "Open client"]}],
    "same": {"tolerance": 0, "ignore": []}
}, open(sys.argv[1], "w", encoding="utf-8"), indent=1)
PY
python3 "$TARGET" "$WORK/action.json" "$WORK/action" >/dev/null 2>&1
check_exit "the round that went wrong, on the committed file, moves the screen" \
    0 lift --check "$WORK/action.json" "$WORK/action"
AGAIN="$WORK/list-at-load.html"
python3 - docs/design/invoice-list.html "$AGAIN" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
head, tail = "function groupsFor() { return [", "\n]; }\n"
assert text.count(head) == 1, "the plant matched nothing, so this case proves nothing"
at = text.index(head)
end = text.index(tail, at)
text = (text[:at] + "var GROUPS_AT_LOAD = [" + text[at + len(head):end]
        + "\n];\nfunction groupsFor() { return GROUPS_AT_LOAD; }\n" + text[end + len(tail):])
open(sys.argv[2], "w", encoding="utf-8").write(text)
PY
python3 - "$WORK/action.json" "$WORK/action-at-load.json" "$AGAIN" <<'PY'
import json, sys
spec = json.load(open(sys.argv[1], encoding="utf-8"))
spec["source"] = sys.argv[3]
json.dump(spec, open(sys.argv[2], "w", encoding="utf-8"), indent=1)
PY
python3 "$TARGET" "$WORK/action-at-load.json" "$WORK/action-at-load" >/dev/null 2>&1
check_exit "and with its rows back in a literal built at load, the same round is refused" \
    8 lift --check "$WORK/action-at-load.json" "$WORK/action-at-load"

check "a harness page in quirks mode is caught, which is ovation#194" \
    "$(OVATION_HARNESS_QUIRKS=1 python3 "$TARGET" --check "$WORK/pdf.json" "$PDF" \
        >/dev/null 2>&1; printf '%s' "$?")" "1"

check "and every one of those runs left the committed design files untouched" \
    "$(shasum -a 256 docs/design/invoice-pdf.html docs/design/invoice-list.html)" "$BEFORE"

# ovation#414. EVERY COMMITTED DESIGN FILE CAN BE LIFTED, said now rather than in the
# middle of wanting a round. The lift appends a `buildScreen(variant)` and refuses a
# file that already defines one, correctly, and nothing said so until somebody tried:
# invoice.html was found that way during ovation#322, and clients.html and
# review-send.html carried the same name (ovation#341). The reserved name is the one
# refusal a scan can see; this asks it of every file rather than the one being lifted.
RESERVED="$(grep -lE '\bfunction[[:space:]]+buildScreen\b' docs/design/*.html 2>/dev/null || true)"
[ -z "$RESERVED" ] || printf '    defines buildScreen: %s\n' $RESERVED >&2
check "no committed design file defines the name the lift appends, so every one can have a round" \
    "$(grep -c . <<< "$RESERVED" || true)" "0"

harness_end
