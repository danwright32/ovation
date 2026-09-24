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
harness_begin "design harness lift tests" 58

TARGET="scripts/lift-design-harness.sh"
require_target "$TARGET"
require_target "docs/design/invoice-pdf.html"
require_target "docs/design/invoice-list.html"
harness_temp_dir WORK

BEFORE="$(shasum -a 256 docs/design/invoice-pdf.html docs/design/invoice-list.html)"

run() { python3 "$TARGET" "$@" 2>&1; }
status() { python3 "$TARGET" "$@" >/dev/null 2>&1; printf '%s' "$?"; }
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
    "moves": [{"field": "heading", "variable": "CARD_HEADING", "holds": '"Needs you"'}],
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
check "no arguments at all is used wrongly" "$(status)" "2"
check "and it prints what it takes" "$(says "$(run)" "lift-design-harness.sh <spec.json> <out-dir>")" "yes"
check "a spec that is not there is used wrongly" "$(status "$WORK/no-such.json" "$WORK/out")" "2"

printf 'not json at all\n' > "$WORK/broken.json"
check "a spec that is not JSON is refused as a spec" "$(status "$WORK/broken.json" "$WORK/out")" "4"

spec_for "$WORK/no-screen.json" "standin.html" "screen=__DROP__"
check "a spec missing a field is refused" "$(status "$WORK/no-screen.json" "$WORK/out")" "4"
check "and the missing field is named" \
    "$(says "$(run "$WORK/no-screen.json" "$WORK/out")" "missing a field: screen")" "yes"

spec_for "$WORK/no-moves.json" "standin.html" "moves=[]"
check "a harness that moves nothing is refused" "$(status "$WORK/no-moves.json" "$WORK/out")" "4"
check "and it says why, because every option would draw the same screen" \
    "$(says "$(run "$WORK/no-moves.json" "$WORK/out")" "draws every option identically")" "yes"

spec_for "$WORK/bad-var.json" "standin.html" \
    'moves=[{"field": "heading", "variable": "not a name", "holds": "\"Needs you\""}]'
check "a variable JavaScript cannot declare is refused" "$(status "$WORK/bad-var.json" "$WORK/out")" "4"

spec_for "$WORK/bad-tol.json" "standin.html" 'same={"tolerance": "loose", "ignore": []}'
check "a tolerance that is not a whole number of pixels is refused" \
    "$(status "$WORK/bad-tol.json" "$WORK/out")" "4"

# ---------------------------------------------------------------------------
# 2. THE DESIGN FILE'S SHAPE. A marker matching nothing would lift the whole
#    script, mounting code and all, and one matching twice would cut at
#    whichever came first with nothing saying a choice had been made (L100).
# ---------------------------------------------------------------------------
spec_for "$WORK/nowhere.json" "standin.html" 'builder_ends_before="var nothing = 1;"'
check "a line the builder ends before that is on no line is refused" \
    "$(status "$WORK/nowhere.json" "$WORK/out")" "5"
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
check "one that is on two lines is refused too" "$(status "$WORK/twice.json" "$WORK/out")" "5"

TWOSTYLES="$WORK/twostyles.html"
python3 - "$STANDIN" "$TWOSTYLES" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
assert "</style>" in text, "the fixture change matched nothing"
open(sys.argv[2], "w", encoding="utf-8").write(
    text.replace("</style>", "</style>\n<style>.late { color: red; }</style>", 1))
PY
spec_for "$WORK/twostyles.json" "twostyles.html"
check "a design file carrying two stylesheets is refused" \
    "$(status "$WORK/twostyles.json" "$WORK/out")" "5"

NOSCRIPT="$WORK/noscript.html"
python3 - "$STANDIN" "$NOSCRIPT" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
out = re.sub(r"<script>.*</script>", "", text, flags=re.S)
assert "<script" not in out, "the fixture change left a script behind"
open(sys.argv[2], "w", encoding="utf-8").write(out)
PY
spec_for "$WORK/noscript.json" "noscript.html"
check "a design file with no script at all is refused" \
    "$(status "$WORK/noscript.json" "$WORK/out")" "5"

# ---------------------------------------------------------------------------
# 3. THE LIFT'S OWN REFUSALS. Each of these is a step the spec asked for that
#    took no effect, and a step that took no effect still reads as taken.
# ---------------------------------------------------------------------------
spec_for "$WORK/norule.json" "standin.html" 'page_rules={"nav.side": ".screen"}'
check "a page rule matching no rule in the stylesheet is refused" \
    "$(status "$WORK/norule.json" "$WORK/out")" "6"
check "and it says the inheritance is still lost" \
    "$(says "$(run "$WORK/norule.json" "$WORK/out")" "is still lost")" "yes"

spec_for "$WORK/nostrip.json" "standin.html" 'strip=["var nothing = 1;"]'
check "a stripped line matching nothing is refused" \
    "$(status "$WORK/nostrip.json" "$WORK/out")" "6"

spec_for "$WORK/nomove.json" "standin.html" \
    'moves=[{"field": "heading", "variable": "CARD_HEADING", "holds": "\"Not in the builder\""}]'
check "a moved value that is not in the builder is refused" \
    "$(status "$WORK/nomove.json" "$WORK/out")" "6"

spec_for "$WORK/taken.json" "standin.html" \
    'moves=[{"field": "heading", "variable": "buildThing", "holds": "\"Needs you\""}]'
check "a move whose variable name the builder already uses is refused" \
    "$(status "$WORK/taken.json" "$WORK/out")" "6"

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
check "a builder that already defines buildScreen is refused" \
    "$(status "$WORK/already.json" "$WORK/out")" "6"

# ---------------------------------------------------------------------------
# 4. WHAT THE LIFT WRITES. Read from the files, because the tool's own summary
#    is a claim about them rather than the thing anybody uses.
# ---------------------------------------------------------------------------
OUT="$WORK/out"
check "the lift writes the harness" "$(status "$SPEC" "$OUT")" "0"
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
check "a strip line that is there takes it out" "$(status "$WORK/strip.json" "$STRIPPED")" "0"
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
check "the lift it just wrote draws the same screen" "$(status --check "$SPEC" "$OUT")" "0"
check "and it says how much it compared" \
    "$(says "$(run --check "$SPEC" "$OUT")" "element(s), tag, classes and box")" "yes"

LOST="$WORK/lost"
spec_for "$WORK/lost.json" "standin.html" "page_rules={}"
check "a lift that retargets nothing is written all the same" "$(status "$WORK/lost.json" "$LOST")" "0"
check "and the check finds the screen drawn differently" "$(status --check "$WORK/lost.json" "$LOST")" "1"
check "it says DIFFERS rather than refusing for some other reason" \
    "$(says "$(run --check "$WORK/lost.json" "$LOST")" "DIFFERS:")" "yes"
DIFFOUT="$(run --check "$WORK/lost.json" "$LOST")"
check "and every line of the difference names an element and its box, on both sides" \
    "$(printf '%s\n' "$DIFFOUT" | grep -cE \
        '^    the (design file|harness) +[a-z]+[.a-z0-9-]* at [^,]+, x -?[0-9]+, y -?[0-9]+, [0-9]+ by [0-9]+$')" \
    "$(printf '%s\n' "$DIFFOUT" | grep -c '^    the ')"
check "and it names the remedy, which is the retarget" \
    "$(says "$(run --check "$WORK/lost.json" "$LOST")" "page_rules")" "yes"

spec_for "$WORK/nolabel.json" "standin.html" 'option_one="Three"'
check "an option 1 label on no fixture cannot be read" \
    "$(status --check "$WORK/nolabel.json" "$OUT")" "7"
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
check "an option 1 label on two fixtures cannot be read either" \
    "$(status --check "$WORK/both.json" "$BOTHOUT")" "7"

spec_for "$WORK/manyscreens.json" "standin.html" 'screen=".row"'
check "a screen selector matching several elements cannot be read" \
    "$(status --check "$WORK/manyscreens.json" "$OUT")" "7"

spec_for "$WORK/ignorenothing.json" "standin.html" 'same={"tolerance": 0, "ignore": [".no-such-class"]}'
check "an ignore selector matching nothing in either rendering is refused" \
    "$(status --check "$WORK/ignorenothing.json" "$OUT")" "7"
check "and it says an exemption matching nothing still reads as one" \
    "$(says "$(run --check "$WORK/ignorenothing.json" "$OUT")" "still reads as a deliberate")" "yes"

spec_for "$WORK/ignorerail.json" "standin.html" 'same={"tolerance": 0, "ignore": [".rail"]}'
check "an ignore selector that matches leaves the rest compared" \
    "$(status --check "$WORK/ignorerail.json" "$OUT")" "0"
check "and the run says what it ignored, so a loosened rule is never silent" \
    "$(says "$(run --check "$WORK/ignorerail.json" "$OUT")" "ignoring     .rail")" "yes"

check "a check with no harness written is used wrongly" \
    "$(status --check "$SPEC" "$WORK/never-written")" "2"
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
    "moves": [{"field": "dueLabel", "variable": "DUE_LABEL", "holds": '"Amount due"'}],
    "same": {"tolerance": 0, "ignore": []}
}, open(sys.argv[1], "w", encoding="utf-8"), indent=1)
PY
check "the invoice PDF design lifts" "$(status "$WORK/pdf.json" "$PDF")" "0"
check "and the harness draws the screen it draws" "$(status --check "$WORK/pdf.json" "$PDF")" "0"

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
    "moves": [{"field": "cardHeading", "variable": "CARD_HEADING", "holds": '"Needs you"'}],
    "same": {"tolerance": 0, "ignore": []}
}, open(sys.argv[1], "w", encoding="utf-8"), indent=1)
PY
check "the invoice list design lifts too" "$(status "$WORK/list.json" "$LIST")" "0"
check "and its harness draws the screen it draws" "$(status --check "$WORK/list.json" "$LIST")" "0"

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
check "one rule dropped from the lifted stylesheet is caught" \
    "$(status --check "$WORK/list.json" "$DROPPED")" "1"
check "and the element it names is one a person can find in the screen" \
    "$(run --check "$WORK/list.json" "$DROPPED" | grep -c '^    the design file  div.screen at the screen')" "1"

# THE DOCUMENT MODE, which is what ovation#194 turned out to be: two renderings
# of the same markup differing by a few pixels in one row, with the lift
# innocent. The seam composes the harness page with no doctype, so the fault can
# be produced on purpose rather than waited for.
check "a harness page in quirks mode is caught, which is ovation#194" \
    "$(OVATION_HARNESS_QUIRKS=1 python3 "$TARGET" --check "$WORK/pdf.json" "$PDF" \
        >/dev/null 2>&1; printf '%s' "$?")" "1"

check "and every one of those runs left the committed design files untouched" \
    "$(shasum -a 256 docs/design/invoice-pdf.html docs/design/invoice-list.html)" "$BEFORE"

harness_end
