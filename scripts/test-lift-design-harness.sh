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
harness_begin "design harness lift tests" 125

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
# 4b. A MOVE IN THE STYLESHEET (ovation#560). Every round of ovation#110 moved a
#     stylesheet rule, and each one was a hand built frame embedding the whole
#     design file, because this tool moved builder values only. A move naming a
#     `rule` and a `property` is a stylesheet move: the declaration becomes a
#     custom property with the file's own value as its fallback, and buildScreen
#     sets it on the screen it builds, so two options drawn side by side cannot
#     reach each other's value.
# ---------------------------------------------------------------------------
RULEMOVE='{"field": "rowPad", "rule": ".row", "property": "padding", "holds": "4px", "values": ["4px", "14px"]}'
spec_for "$WORK/rule.json" "standin.html" "moves=[$RULEMOVE]"
RULEOUT="$WORK/ruleout"
check_exit "a move naming a stylesheet rule lifts" 0 lift "$WORK/rule.json" "$RULEOUT"
check "the declaration it names now reads a custom property, the file's value its fallback" \
    "$(grep -c '^\.row { padding: var(--lift-rowPad, 4px); }$' "$RULEOUT/screen.css")" "1"
check "and buildScreen sets that property on the screen it builds, from the variant" \
    "$(grep -c 'built.style.setProperty("--lift-rowPad", String(variant.rowPad))' "$RULEOUT/builder.js")" "1"
check "no builder variable is declared for it: the one line naming it is the one setting it" \
    "$(grep -c 'rowPad' "$RULEOUT/builder.js")" "1"
check "the lift says it moved one declaration in the stylesheet" \
    "$(says "$(run "$WORK/rule.json" "$RULEOUT")" "moves        variant.rowPad through --lift-rowPad, 1 declaration(s) in the stylesheet")" "yes"

# A PAGE RULE CAN BE MOVED AND RETARGETED IN ONE LIFT. The move is made on the
# selector as the design file writes it, before the retarget renames it, so a
# round on the typography the screen inherits from `body` names `body`.
spec_for "$WORK/rule-body.json" "standin.html" \
    'moves=[{"field": "size", "rule": "body", "property": "font-size", "holds": "20px", "values": ["20px", "15px"]}]'
check_exit "a move in a rule that is retargeted onto the screen lifts" \
    0 lift "$WORK/rule-body.json" "$WORK/rulebody"
check "and the retargeted rule carries the moved declaration" \
    "$(grep -c '^\.screen { font-family: ui-monospace, monospace; font-size: var(--lift-size, 20px);' "$WORK/rulebody/screen.css")" "1"

spec_for "$WORK/rule-noprop.json" "standin.html" \
    'moves=[{"field": "rowPad", "rule": ".row", "values": ["4px", "14px"], "holds": "4px"}]'
check_exit "a stylesheet move naming no property is refused as a spec" \
    4 lift "$WORK/rule-noprop.json" "$WORK/out"
spec_for "$WORK/rule-var.json" "standin.html" \
    'moves=[{"field": "rowPad", "rule": ".row", "property": "padding", "variable": "ROW_PAD", "holds": "4px", "values": ["4px", "14px"]}]'
check_exit "and one naming a builder variable too, which it would never declare" \
    4 lift "$WORK/rule-var.json" "$WORK/out"
spec_for "$WORK/rule-field.json" "standin.html" \
    'moves=[{"field": "row pad", "rule": ".row", "property": "padding", "holds": "4px", "values": ["4px", "14px"]}]'
check_exit "and one whose field cannot name a custom property" \
    4 lift "$WORK/rule-field.json" "$WORK/out"

spec_for "$WORK/rule-norule.json" "standin.html" \
    'moves=[{"field": "rowPad", "rule": ".nothing", "property": "padding", "holds": "4px", "values": ["4px", "14px"]}]'
check_exit "a stylesheet move naming a rule the stylesheet does not have is refused" \
    6 lift "$WORK/rule-norule.json" "$WORK/out"
check "and it says the rule is not there, naming the selector" \
    "$(says "$(run "$WORK/rule-norule.json" "$WORK/out")" "no rule in standin.html has the selector '.nothing'")" "yes"
spec_for "$WORK/rule-nodecl.json" "standin.html" \
    'moves=[{"field": "rowPad", "rule": ".row", "property": "margin", "holds": "4px", "values": ["4px", "14px"]}]'
check_exit "one naming a property the rule does not declare is refused" \
    6 lift "$WORK/rule-nodecl.json" "$WORK/out"
spec_for "$WORK/rule-noval.json" "standin.html" \
    'moves=[{"field": "rowPad", "rule": ".row", "property": "padding", "holds": "9px", "values": ["4px", "14px"]}]'
check_exit "one whose rule declares the property with another value is refused" \
    6 lift "$WORK/rule-noval.json" "$WORK/out"
check "and it counts what the rule does declare, without printing a value" \
    "$(says "$(run "$WORK/rule-noval.json" "$WORK/out")" "declares padding 1 time(s), none of them with the value the move says it holds")" "yes"

TAKENPROP="$WORK/takenprop.html"
python3 - "$STANDIN" "$TAKENPROP" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
mark = ".rail { width: 80px; }"
assert mark in text, "the plant matched nothing, so this case proves nothing"
open(sys.argv[2], "w", encoding="utf-8").write(
    text.replace(mark, ".rail { width: 80px; --lift-rowPad: 1px; }", 1))
PY
spec_for "$WORK/takenprop.json" "takenprop.html" "moves=[$RULEMOVE]"
check_exit "one whose custom property the stylesheet already uses is refused" \
    6 lift "$WORK/takenprop.json" "$WORK/out"

# ---------------------------------------------------------------------------
# 4c. THE FRAME MODE (ovation#560). Every round of ovation#110 was a hand built
#     frame embedding the committed file, and three faults shipped through it
#     into switchers and were found only by looking: the embedded page's own
#     closing script tag ended the builder early and left an empty frame, a load
#     time scroll that did not happen in Dan's Chrome showed the page's intro
#     instead of the window, and an option's stated measurement did not match
#     what it drew. So the frame is a mode of this tool, and each of the three is
#     planted below and has to be refused by name.
#
#     The stand in carries what makes each fault possible: a script (so a
#     closing tag), a tall intro ABOVE the window (so a frame that shows the top
#     of the page shows the wrong thing), and a window wider than the stage the
#     check draws it on (so the frame has to scale, and the caption has a number
#     to get wrong).
# ---------------------------------------------------------------------------
FSTANDIN="$WORK/framed.html"
cat > "$FSTANDIN" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>A framed stand in</title>
<style>
body { margin: 0; font-family: ui-monospace, monospace; font-size: 16px; background: #DDDDDD; }
.intro { height: 700px; padding: 40px; }
.win { width: 640px; margin: 0 60px 80px; background: #FFFFFF; border-radius: 10px; }
.row { padding: 4px; }
.head { font-size: 20px; }
</style>
</head>
<body>
<div class="intro"><h1>Everything above the window</h1><p>An intro a frame must not show.</p></div>
<div id="stage"></div>
<script>
function draw() {
  var win = document.createElement("div");
  win.className = "win";
  var head = document.createElement("div");
  head.className = "head";
  head.textContent = "Needs you";
  win.append(head);
  ["First", "Second", "Third"].forEach(function (w) {
    var r = document.createElement("div");
    r.className = "row";
    r.textContent = w;
    win.append(r);
  });
  document.getElementById("stage").replaceChildren(win);
}
draw();
</script>
</body>
</html>
HTML

frame_spec() {
    local into="$1" source="$2"
    shift 2
    python3 - "$into" "$source" "$@" <<'PY'
import json, sys
spec = {
    "mode": "frame",
    "source": sys.argv[2],
    "window": ".win",
    "moves": [{"field": "rowPad", "rule": ".row", "property": "padding", "holds": "4px",
               "values": ["4px", "14px"]}],
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

FSPEC="$WORK/framed.json"
frame_spec "$FSPEC" "framed.html"
FOUT="$WORK/frameout"
check_exit "a frame lift writes the harness" 0 lift "$FSPEC" "$FOUT"
check "both files it names are there" \
    "$([ -f "$FOUT/screen.css" ] && [ -f "$FOUT/builder.js" ] && echo both || echo missing)" "both"
check "the builder defines buildScreen exactly once" \
    "$(grep -c '^function buildScreen(variant) {$' "$FOUT/builder.js")" "1"
# THE FIRST FAULT, AS TEXT: a builder is inlined in a script element, and any
# closing tag inside it ends that element. The design file carries one of its
# own, so the embedded page must carry none that the HTML parser can read.
check "the embedded page carries no closing tag a script element would end at" \
    "$(grep -c '</' "$FOUT/builder.js")" "0"
check "and the stylesheet move is made in the embedded page" \
    "$(grep -c 'var(--lift-rowPad, 4px)' "$FOUT/builder.js")" "1"
check "the lift says what it framed" \
    "$(says "$(run "$FSPEC" "$FOUT")" "framed       .win")" "yes"

frame_spec "$WORK/frame-nopatch.json" "framed.html" 'moves=[{"field": "word", "values": ["A", "B"]}]'
check_exit "a move the round's own script would carry, with no script named, is refused" \
    4 lift "$WORK/frame-nopatch.json" "$WORK/out"
printf 'document.querySelector(".head").textContent = "Fixed";\n' > "$WORK/deaf.js"
frame_spec "$WORK/frame-deaf.json" "framed.html" 'patch="deaf.js"' \
    'moves=[{"field": "word", "values": ["A", "B"]}]'
check_exit "a round script that never reads the field it is said to move is refused" \
    6 lift "$WORK/frame-deaf.json" "$WORK/out"
printf 'var s = "</script>"; LIFT_VARIANT.word;\n' > "$WORK/closes.js"
frame_spec "$WORK/frame-closes.json" "framed.html" 'patch="closes.js"' \
    'moves=[{"field": "word", "values": ["A", "B"]}]'
check_exit "a round script holding a closing script tag is refused, since it runs inside one" \
    6 lift "$WORK/frame-closes.json" "$WORK/out"
frame_spec "$WORK/frame-window.json" "framed.html" 'window=""'
check_exit "a frame whose window selector is empty is refused as a spec" \
    4 lift "$WORK/frame-window.json" "$WORK/out"

# ---------------------------------------------------------------------------
# Everything below renders. With no browser there is no answer to give, and
# giving one would be a green tick over an unrun check.
# ---------------------------------------------------------------------------
harness_require_browser \
    "no headless browser, so no lift can be rendered beside the file it came from" \
    "npx playwright install chromium" \
    python3 "$TARGET" --check "$SPEC" "$OUT"

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

# ovation#560. THE SAME PROOF FOR A STYLESHEET MOVE, and it has to judge what is
# DRAWN. The move itself writes the custom property onto the screen's own style
# attribute, so markup compared whole would differ for every value even when the
# declaration it feeds is overridden and nothing on screen moves; the proof must
# not count its own mechanism. And a colour moves no box and no word, so the
# proof has to compare computed style as well, or a real colour round would be
# refused as inert.
RULESAYS="$(run --check "$WORK/rule.json" "$RULEOUT")"
check_exit "a stylesheet move's harness draws the design file's screen" \
    0 lift --check "$WORK/rule.json" "$RULEOUT"
check "and the move is proved to move the screen" \
    "$(says "$RULESAYS" "MOVES: variant.rowPad draws 2 different screens")" "yes"
check_exit "a move in a retargeted page rule is proved to move it too" \
    0 lift --check "$WORK/rule-body.json" "$WORK/rulebody"

spec_for "$WORK/rule-colour.json" "standin.html" \
    'moves=[{"field": "tint", "rule": ".screen", "property": "background", "holds": "#EEEEEE", "values": ["#EEEEEE", "#333333"]}]'
python3 "$TARGET" "$WORK/rule-colour.json" "$WORK/rulecolour" >/dev/null 2>&1
check_exit "a colour, which moves no box and no word, is proved to move the screen" \
    0 lift --check "$WORK/rule-colour.json" "$WORK/rulecolour"

OVERRIDDEN="$WORK/overridden.html"
python3 - "$STANDIN" "$OVERRIDDEN" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
mark = ".rail { width: 80px; }"
assert mark in text, "the plant matched nothing, so this case proves nothing"
open(sys.argv[2], "w", encoding="utf-8").write(
    text.replace(mark, mark + "\n.screen .row { padding: 4px; }", 1))
PY
spec_for "$WORK/overridden.json" "overridden.html" "moves=[$RULEMOVE]"
python3 "$TARGET" "$WORK/overridden.json" "$WORK/overriddenout" >/dev/null 2>&1
OVERSAYS="$(run --check "$WORK/overridden.json" "$WORK/overriddenout")"
check "a declaration another rule overrides still draws option 1 faithfully" \
    "$(says "$OVERSAYS" "SAME:")" "yes"
check_exit "but moving it is refused as inert, whatever its own attribute says" \
    8 lift --check "$WORK/overridden.json" "$WORK/overriddenout"
check "and the cause it names is the one a stylesheet move has" \
    "$(says "$OVERSAYS" "a later or more specific rule")" "yes"

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
check_exit "and with no browser to render in, nothing is measured" \
    3 env OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" python3 "$TARGET" --check "$SPEC" "$OUT"

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

# ovation#560 ON A COMMITTED FILE. A colour moves no word and no box, so this is
# the computed style half of the proof carrying the claim on a screen somebody
# will actually run a round on. (A move on .railname was tried first and refused
# as inert, correctly: this fixture draws no rail entry that carries one.)
python3 - "$WORK/list.json" "$WORK/weight.json" <<'PY'
import json, sys
spec = json.load(open(sys.argv[1], encoding="utf-8"))
spec["moves"] = [{"field": "saidInk", "rule": ".said", "property": "color",
                  "holds": "var(--faint)", "values": ["var(--faint)", "#B00020"]}]
json.dump(spec, open(sys.argv[2], "w", encoding="utf-8"), indent=1)
PY
check_exit "a stylesheet move on the committed invoice list lifts" \
    0 lift "$WORK/weight.json" "$WORK/weight"
check_exit "and is proved faithful and moving" 0 lift --check "$WORK/weight.json" "$WORK/weight"

check_exit "a harness page in quirks mode is caught, which is ovation#194" \
    1 env OVATION_HARNESS_QUIRKS=1 python3 "$TARGET" --check "$WORK/pdf.json" "$PDF"

# ---------------------------------------------------------------------------
# 7. THE FRAME, RENDERED (ovation#560). --check inlines the builder in a page's
#    script element the way the switcher does, draws each option on a stage
#    narrower than the window, and judges the drawing from the page: where the
#    window lands inside the frame, and whether the caption's width and scale are
#    the ones the drawing has. Each of the three faults is then planted in a copy
#    of the written builder and has to be refused by name.
# ---------------------------------------------------------------------------
frame_spec "$FSPEC" "framed.html" 'stage=480'
python3 "$TARGET" "$FSPEC" "$FOUT" >/dev/null 2>&1
FSAYS="$(run --check "$FSPEC" "$FOUT")"
check_exit "the frame it just wrote draws the design file's window" 0 lift --check "$FSPEC" "$FOUT"
check "and the window it frames is the one the design file draws" "$(says "$FSAYS" "SAME:")" "yes"
check "the caption states the window's true width and the scale it is drawn at" \
    "$(says "$FSAYS" "FRAMED: the caption says 640 points at 71%, and the drawing is 640 points at 71%")" "yes"
check "and the stylesheet move is proved to move the window" \
    "$(says "$FSAYS" "MOVES: variant.rowPad draws 2 different screens")" "yes"

plant_frame() {
    local into="$1" old="$2" new="$3"
    mkdir -p "$into"
    cp "$FOUT/screen.css" "$into/screen.css"
    python3 - "$FOUT/builder.js" "$into/builder.js" "$old" "$new" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
old, new = sys.argv[3], sys.argv[4]
assert old in text, "the plant matched nothing, so this case proves nothing"
open(sys.argv[2], "w", encoding="utf-8").write(text.replace(old, new))
PY
}

# FAULT ONE: the embedded page's closing tag, unescaped, ends the builder's
# script and the switcher draws an empty frame.
plant_frame "$WORK/unescaped" '<\/' '</'
check_exit "a builder whose embedded page ends its script early is refused" \
    9 lift --check "$FSPEC" "$WORK/unescaped"
check "and it says the frame would be empty, and why" \
    "$(says "$(run --check "$FSPEC" "$WORK/unescaped")" "ended the script it is inlined in")" "yes"

# FAULT TWO: a frame that shows the top of the page shows the intro, not the
# window. The frame has to place the window by measuring it, never by scrolling.
plant_frame "$WORK/unplaced" '" translate(" + (-left) + "px, " + (-top) + "px)"' '""'
check_exit "a frame that shows the top of the page instead of the window is refused" \
    9 lift --check "$FSPEC" "$WORK/unplaced"
check "and it says the frame shows something other than the window" \
    "$(says "$(run --check "$FSPEC" "$WORK/unplaced")" "shows something other than the window")" "yes"
SCROLLS="$WORK/scrolls.html"
python3 - "$FSTANDIN" "$SCROLLS" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
mark = "draw();\n</script>"
assert mark in text, "the plant matched nothing, so this case proves nothing"
open(sys.argv[2], "w", encoding="utf-8").write(
    text.replace(mark, "draw();\nwindow.scrollTo(0, 500);\n</script>", 1))
PY
frame_spec "$WORK/scrolls.json" "scrolls.html" 'stage=480'
python3 "$TARGET" "$WORK/scrolls.json" "$WORK/scrollsout" >/dev/null 2>&1
check_exit "a design file that scrolls itself at load is framed on its window all the same" \
    0 lift --check "$WORK/scrolls.json" "$WORK/scrollsout"

# FAULT THREE: a stated measurement the drawing does not have. The caption is
# read beside an independent measurement of the frame, width and scale both.
plant_frame "$WORK/wrongwidth" '"The window is " + Math.round(r.width)' '"The window is " + LIFT_VIEWPORT'
check_exit "a caption stating a width the window does not have is refused" \
    9 lift --check "$FSPEC" "$WORK/wrongwidth"
check "and it names both numbers, the caption's and the drawing's" \
    "$(says "$(run --check "$FSPEC" "$WORK/wrongwidth")" "the caption says 1440 points at 71%, and the drawing is 640 points at 71%")" "yes"
plant_frame "$WORK/wrongscale" '" points wide, drawn here at " + Math.round(s * 100)' '" points wide, drawn here at " + 100'
check_exit "a caption stating a scale the drawing is not at is refused" \
    9 lift --check "$FSPEC" "$WORK/wrongscale"

frame_spec "$WORK/frame-nowin.json" "framed.html" 'window=".nothing"' 'stage=480'
python3 "$TARGET" "$WORK/frame-nowin.json" "$WORK/framenowin" >/dev/null 2>&1
check_exit "a window selector matching nothing in the design file is refused" \
    9 lift --check "$WORK/frame-nowin.json" "$WORK/framenowin"
check "and it says how many matched" \
    "$(says "$(run --check "$WORK/frame-nowin.json" "$WORK/framenowin")" "0 element(s) in the framed page match .nothing")" "yes"

FOVER="$WORK/frame-over.html"
python3 - "$FSTANDIN" "$FOVER" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
mark = ".head { font-size: 20px; }"
assert mark in text, "the plant matched nothing, so this case proves nothing"
open(sys.argv[2], "w", encoding="utf-8").write(text.replace(mark, mark + "\n.win .row { padding: 4px; }", 1))
PY
frame_spec "$WORK/frame-over.json" "frame-over.html" 'stage=480'
python3 "$TARGET" "$WORK/frame-over.json" "$WORK/frameoverout" >/dev/null 2>&1
check_exit "a framed stylesheet move another rule overrides is refused as inert" \
    8 lift --check "$WORK/frame-over.json" "$WORK/frameoverout"

printf 'document.querySelector(".head").textContent = LIFT_VARIANT.word || "Needs you";\n' > "$WORK/word.js"
frame_spec "$WORK/frame-word.json" "framed.html" 'patch="word.js"' 'stage=480' \
    'moves=[{"field": "word", "values": ["Needs you", "Waiting on you"]}]'
python3 "$TARGET" "$WORK/frame-word.json" "$WORK/frameword" >/dev/null 2>&1
check_exit "a round script that reads its field moves the window, and the frame proves it" \
    0 lift --check "$WORK/frame-word.json" "$WORK/frameword"

# THE COMMITTED INVOICE LIST, framed, which is what the rounds of ovation#110
# built by hand. A colour moves no word and no box.
python3 - "$WORK/frame-list.json" "$PWD/docs/design/invoice-list.html" <<'PY'
import json, sys
json.dump({
    "mode": "frame",
    "source": sys.argv[2],
    "window": ".win",
    "moves": [{"field": "saidInk", "rule": ".said", "property": "color",
               "holds": "var(--faint)", "values": ["var(--faint)", "#B00020"]}],
    "same": {"tolerance": 0, "ignore": []}
}, open(sys.argv[1], "w", encoding="utf-8"), indent=1)
PY
check_exit "the committed invoice list frames" 0 lift "$WORK/frame-list.json" "$WORK/framelist"
check_exit "and its frame draws its window, placed and captioned truly, and the move moves it" \
    0 lift --check "$WORK/frame-list.json" "$WORK/framelist"

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
