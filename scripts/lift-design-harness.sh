#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Lift a committed design file into a design round's harness, and prove the lift.

    lift-design-harness.sh <spec.json> <out-dir>
    lift-design-harness.sh --check <spec.json> <out-dir>

ovation#196. A design round shows several versions of ONE screen under one
frame, and the screen is drawn by a builder the round's switcher calls. The
switcher itself is written by ~/.claude/skills/design-rounds/make-switcher.py.
THE STEP BEFORE IT had no tool at all: getting the screen out of the committed
design file and into a builder that stands on its own. It was done by hand twice
on 2026-09-10, for ovation#191 and ovation#98, the same four steps each time.

WHAT IT WRITES, into <out-dir>:

    screen.css   the design file's stylesheet, with the rules that belong to the
                 PAGE retargeted onto the screen
    builder.js   the design file's builder, its own mounting code and its state
                 switches removed, one variable per moved value, and a
                 buildScreen(variant) appended

Both are what make-switcher.py's spec names as `styles` and `builder`, so a
round costs a spec rather than an afternoon.

THE FOURTH STEP IS THE ONE WORTH KEEPING and the easiest to skip. Lifted code
loses whatever it was inheriting from the page it came from, and the loss is
SILENT, because the extracted copy still renders and still looks finished. A
screen whose typography came from the design file's `body` rule draws in the
browser's default face once it is somewhere else, and nothing says so. So
`--check` renders the design file and the harness in one browser and compares
option 1 element by element, tag, classes and box. That comparison is what found
ovation#194, where two renderings differed by 3px in one row and the cause was
the document mode rather than the lift.

THE HARNESS IS RENDERED IN A PAGE THE SCREEN HAS NEVER MET. The page `--check`
composes carries the lifted stylesheet, the lifted builder and one plain `body`
rule of its own, declared AFTER the stylesheet so that a page rule the lift left
behind loses to it exactly as it would lose to the switcher's chrome. Composing
a page with no rule at all would hide the fault this exists to find: the design
file's own `body` rule would simply style THAT body and reach the screen again
by inheritance, and the lift would measure as faithful while the screen still
depended on a page it is leaving.

AND IT DECLARES A DOCTYPE, which is not decoration: a page without one is in
quirks mode and lays the same markup out differently, which is exactly what
ovation#194 turned out to be (L451).

THE COMPARISON RULE IS A PARAMETER, NOT A CONSTANT. The two harnesses lifted so
far differ in what a variant may legitimately move: a rail that reflows, rows
that renumber. So the spec's `same` names the tolerance in pixels and the
selectors whose elements are not compared, and every run PRINTS both, because a
rule loosened where nobody can see it is a rule nobody re-examines (L523). An
`ignore` selector matching NOTHING is a refusal rather than a quiet pass: an
exemption that matches nothing still reads as a deliberate one (L100, L233).

THE SPEC, with `source` resolved against the spec file's own directory:

    {
      "source":  "invoice-pdf.html",       the committed design file
      "screen":  ".page",                  the one element that IS the screen
      "fixtures": "FIXTURES",              a JS expression for the fixture list
      "label":   "label",                  the field a fixture's label is in
      "screen_from": "buildPage(fixture)", a JS expression building the screen
      "option_one":  "Ordinary",           the label option 1 draws
      "variant":  {},                      option 1's own variant fields
      "builder_ends_before": "var bar = document.getElementById(\\"fixbar\\");",
      "strip":    ["var stage = document.getElementById(\\"stage\\");"],
      "page_rules": {"body": ".page"},     rules that are the page, retargeted
      "moves":  [{"field": "dueLabel", "variable": "DUE_LABEL",
                  "holds": "\\"Amount due\\"",
                  "values": ["Amount due", "Balance due"]}],
      "same":   {"tolerance": 0, "ignore": []}
    }

`builder_ends_before` is the design file's first line of its OWN mounting code,
and everything from it to the end of the script is left behind: the fixture bar,
the draw function and the event wiring. It is DECLARED rather than guessed,
because the five committed files each mount themselves differently and a tool
that guessed would cut a builder in half on the sixth (this is the same reason
check-design-record-open.sh reads a declared shape rather than a guessed one).
`strip` removes the mounting lines that sit ABOVE that point, each of which must
match at least one line or it is a refusal.

`moves` is what the round's one variable is. Each entry names a value the design
file HARD CODES in its builder, the variable that replaces it, and the variant
field that sets it. THEY ARE VALUES IN THE BUILDER, NEVER IN THE STYLESHEET, and
a round moving a CSS value is not something this does; it is said here so nobody
reads the silence as coverage.

`values` is what the round's options give that field, as the switcher's variants
carry it, at least two and all different (ovation#407). THEY ARE THERE SO
`--check` CAN PROVE THE MOVE MOVES SOMETHING. Replacing a value with a variable
only works if the builder READS the variable while it builds; a value sitting in
a literal the script evaluates once, at load (`var GROUPS = [ ... ]`), is already
inside that literal when buildScreen assigns the variable, so every option draws
the same screen. That is how a round on the invoice list offered a choice
between two copies of one screen on 2026-09-19, with the lift reporting success
and the faithfulness check reporting SAME, because that check draws option 1,
the one option where the moved value still holds its original and so the one
option that cannot see it (L101, L159). So after the faithfulness check `--check`
draws option 1's fixture once per value of each move, every other move left at
option 1, and refuses when two values draw the same screen. "The same screen" is
the built element's markup, its text and attributes included, and every
element's tag, classes and box: a word changed inside a fixed width box moves no
box, and a width changed through a class moves no text, so either alone would
pass a move the other can see. The values are compared, never printed: a
refusal names them by their place in the list.

WHAT IT PRINTS is file names, selectors, class names, counts and boxes. It never
prints a design file's text, so no fixture's wording can reach a terminal
(docs/PRIVACY-FLOOR.md), and the committed fixtures carry invented names anyway.

Exit codes, one per outcome (L11):

    0  the harness was written, or --check and it draws the same screen and
       every move's values draw different ones
    1  --check and the harness draws a DIFFERENT screen, named element by element
    2  used wrongly, or the spec, the design file or a written harness is not there
    3  cannot measure: no headless browser
    4  the spec could not be read: not JSON, a field missing, or a field that is
       not the shape the spec declares
    5  the design file's shape could not be found: no single stylesheet, no
       script, or the line the builder ends before is not there exactly once
    6  the lift refused: something the spec names matched nothing, or the lifted
       builder already defines buildScreen
    7  --check and a page could not be read: its probe reported an error, or an
       ignore selector matched nothing in either rendering
    8  --check and a move is INERT: two of its values draw the same screen, so a
       round moving it would offer a choice between copies of one screen

Seams: OVATION_HEADLESS_BROWSER, OVATION_HARNESS_QUIRKS (compose the harness
page with NO doctype, so the document mode difference of ovation#194 can be
produced on purpose; it can only ever make this refuse, never pass).
"""
import json
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_render import CannotMeasure, open_browser  # noqa: E402

STYLES = "screen.css"
BUILDER = "builder.js"

# The exit codes above, named so a refusal cannot be raised with the wrong one.
WRITTEN, DIFFERS, USED_WRONGLY = 0, 1, 2
NO_BROWSER, BAD_SPEC, BAD_SHAPE, LIFT_REFUSED, UNREADABLE, INERT = 3, 4, 5, 6, 7, 8


class Refusal(Exception):
    """A refusal carrying the code it must exit with, so the code and the
    sentence explaining it are written in one place and cannot drift apart."""

    def __init__(self, code, said, *more):
        super().__init__(said)
        self.code = code
        self.said = said
        self.more = list(more)


# ---------------------------------------------------------------------------
# The spec.
# ---------------------------------------------------------------------------

REQUIRED = ["source", "screen", "fixtures", "screen_from", "option_one",
            "builder_ends_before", "moves"]


def read_spec(path):
    if not os.path.isfile(path):
        raise Refusal(USED_WRONGLY, "the spec is not there: %s" % path)
    try:
        with open(path, encoding="utf-8") as handle:
            spec = json.load(handle)
    except ValueError as err:
        raise Refusal(BAD_SPEC, "the spec could not be read as JSON: %s (%s)" % (path, err))
    except OSError as err:
        raise Refusal(USED_WRONGLY, "the spec could not be opened: %s (%s)" % (path, err))
    if not isinstance(spec, dict):
        raise Refusal(BAD_SPEC, "the spec must be one JSON object, and %s holds a %s"
                      % (path, type(spec).__name__))

    missing = [key for key in REQUIRED if key not in spec]
    if missing:
        raise Refusal(BAD_SPEC,
                      "the spec is missing %s: %s." % (
                          "a field" if len(missing) == 1 else "fields",
                          ", ".join(missing)),
                      "Run this with no arguments for the shape of a spec.")
    for key in ("source", "screen", "fixtures", "screen_from", "option_one",
                "builder_ends_before"):
        if not isinstance(spec[key], str) or not spec[key].strip():
            raise Refusal(BAD_SPEC, "the spec's %s must be a sentence of text, and it is %r"
                          % (key, spec[key]))

    # A HARNESS THAT MOVES NOTHING DRAWS EVERY OPTION THE SAME, which is a round
    # with no question in it. It is refused here rather than discovered when the
    # switcher is open and two tabs are identical.
    moves = spec["moves"]
    if not isinstance(moves, list) or not moves:
        raise Refusal(BAD_SPEC,
                      "the spec's moves must be a list of at least one value the round "
                      "moves, and it is %r." % (moves,),
                      "A harness that moves nothing draws every option identically.")
    for index, move in enumerate(moves):
        if not isinstance(move, dict):
            raise Refusal(BAD_SPEC, "move %d is not an object" % (index + 1))
        for key in ("field", "variable", "holds"):
            if not isinstance(move.get(key), str) or not move[key].strip():
                raise Refusal(BAD_SPEC, "move %d has no %s, so nothing says what it moves "
                                        "or what it moves it from" % (index + 1, key))
        if not re.match(r"^[A-Za-z_$][A-Za-z0-9_$]*$", move["variable"]):
            raise Refusal(BAD_SPEC, "move %d names the variable %r, which is not a name "
                                    "JavaScript can declare" % (index + 1, move["variable"]))
        # THE VALUES THE ROUND GIVES IT, which is what --check draws to prove the
        # move moves anything (ovation#407). Two the same are one question asked
        # twice, and are compared as JSON so 1 and 1.0 are not told apart here
        # while the browser would draw them alike.
        values = move.get("values")
        if (not isinstance(values, list) or len(values) < 2
                or len({json.dumps(v, sort_keys=True) for v in values}) != len(values)):
            raise Refusal(BAD_SPEC,
                          "move %d must list the values the round's options give %s, at "
                          "least two and all different, and it lists %s."
                          % (index + 1, move["field"],
                             "none" if not isinstance(values, list)
                             else "%d, %d different" % (
                                 len(values),
                                 len({json.dumps(v, sort_keys=True) for v in values}))),
                          "--check draws each one to prove the move moves the screen; a "
                          "move nobody can prove moves anything is not a round.")

    for key, want in (("strip", list), ("page_rules", dict), ("variant", dict), ("same", dict)):
        if key in spec and not isinstance(spec[key], want):
            raise Refusal(BAD_SPEC, "the spec's %s must be a %s, and it is a %s"
                          % (key, "list" if want is list else "object",
                             type(spec[key]).__name__))
    same = spec.get("same") or {}
    tolerance = same.get("tolerance", 0)
    if not isinstance(tolerance, int) or isinstance(tolerance, bool) or tolerance < 0:
        raise Refusal(BAD_SPEC, "the spec's same.tolerance must be a whole number of "
                                "pixels, and it is %r" % (tolerance,))
    ignore = same.get("ignore", [])
    if not isinstance(ignore, list) or any(not isinstance(s, str) or not s.strip()
                                           for s in ignore):
        raise Refusal(BAD_SPEC, "the spec's same.ignore must be a list of selectors, and "
                                "it is %r" % (ignore,))

    spec["source_path"] = os.path.join(os.path.dirname(os.path.abspath(path)), spec["source"])
    spec["label"] = spec.get("label") or "label"
    spec["strip"] = spec.get("strip") or []
    spec["page_rules"] = spec.get("page_rules") or {}
    spec["variant"] = spec.get("variant") or {}
    spec["tolerance"] = tolerance
    spec["ignore"] = ignore
    return spec


# ---------------------------------------------------------------------------
# The stylesheet, and the rules that are the PAGE rather than the screen.
# ---------------------------------------------------------------------------

def one_style_block(text, name):
    """The design file's stylesheet. ONE BLOCK, OR A REFUSAL: every committed
    file carries exactly one, and a file carrying two would have half its rules
    lifted with nothing saying which half (L521)."""
    opens = [m for m in re.finditer(r"<style\b[^>]*>", text, re.I)]
    closes = [m for m in re.finditer(r"</style\s*>", text, re.I)]
    if len(opens) != 1 or len(closes) != 1:
        raise Refusal(BAD_SHAPE,
                      "%s carries %d <style> block(s) and %d closing tag(s), and a lift "
                      "needs exactly one of each. With two, half the rules would be "
                      "lifted and nothing would say which half."
                      % (name, len(opens), len(closes)))
    return text[opens[0].end():closes[0].start()]


def selector_spans(css, name):
    """(start, end, selector) for every rule in the stylesheet, at any depth.

    IT IS SCANNED RATHER THAN MATCHED WITH A PATTERN, because these stylesheets
    carry embedded typefaces: one `url(data:font/woff2;base64,...)` is hundreds
    of kilobytes on a single line, and a pattern over braces would be answered by
    whatever fell inside it. Comments and quoted strings are stepped over, an
    at-rule's own head is never offered as a selector, and a stylesheet whose
    braces do not balance is a refusal rather than a partial reading.
    """
    spans = []
    i, n, depth, start = 0, len(css), 0, 0
    while i < n:
        c = css[i]
        if c == "/" and css.startswith("/*", i):
            end = css.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        if c in "\"'":
            quote, i = c, i + 1
            while i < n and css[i] != quote:
                i += 2 if css[i] == "\\" else 1
            i += 1
            continue
        if c == "{":
            selector = css[start:i]
            if not selector.lstrip().startswith("@"):
                spans.append((start, i, selector))
            depth += 1
            i += 1
            start = i
            continue
        if c == "}":
            depth -= 1
            i += 1
            start = i
            continue
        if c == ";" and depth == 0:
            i += 1
            start = i
            continue
        i += 1
    if depth != 0:
        raise Refusal(BAD_SHAPE,
                      "%s's stylesheet could not be read as rules: its braces do not "
                      "balance, and a partial reading would retarget whatever happened "
                      "to parse." % name)
    return spans


def retarget(css, page_rules, name):
    """Rewrite the rules that belong to the PAGE so they reach the SCREEN.

    THIS IS THE STEP THE LIFT EXISTS FOR. A screen sitting inside a design file
    inherits its typography, its colour and its box model from rules written for
    the page around it, and those rules reach nothing once the screen is drawn
    anywhere else. The rule is moved rather than copied, and it stays where it
    was in the stylesheet, so everything declared after it still overrides it
    exactly as it did before.

    A selector naming no rule is a refusal: a retarget that matched nothing
    leaves the inheritance lost and reads as a step that was taken (L100).
    """
    spans = selector_spans(css, name)
    edits, counted = [], {}
    for selector, replacement in page_rules.items():
        if not isinstance(replacement, str) or not replacement.strip():
            raise Refusal(BAD_SPEC, "the page rule %r names no selector to retarget it "
                                    "onto" % selector)
        hits = 0
        for start, end, text in spans:
            if " ".join(text.split()) != " ".join(selector.split()):
                continue
            hits += 1
            # ONLY THE SELECTOR ITSELF IS REPLACED, so the whitespace the file
            # laid out around it survives and the lifted stylesheet still reads
            # like the one it came from.
            offset = len(text) - len(text.lstrip())
            edits.append((start + offset, start + offset + len(text.strip()), replacement))
        if hits == 0:
            raise Refusal(LIFT_REFUSED,
                          "no rule in %s has the selector %r, so retargeting it onto %r "
                          "moved nothing and whatever the screen inherited from it is "
                          "still lost." % (name, selector, replacement),
                          "The selector is matched whole: a rule written `%s, html` is "
                          "not the selector `%s`." % (selector, selector))
        counted[selector] = hits
    for start, end, replacement in sorted(edits, reverse=True):
        css = css[:start] + replacement + css[end:]
    return css, counted


# ---------------------------------------------------------------------------
# The builder.
# ---------------------------------------------------------------------------

def last_script(text, name):
    opens = [m for m in re.finditer(r"<script\b[^>]*>", text, re.I)]
    if not opens:
        raise Refusal(BAD_SHAPE, "%s carries no <script>, so there is no builder to lift."
                      % name)
    begin = opens[-1].end()
    close = re.search(r"</script\s*>", text[begin:], re.I)
    if not close:
        raise Refusal(BAD_SHAPE, "%s's last <script> is never closed, so where the "
                                 "builder ends cannot be read." % name)
    return text[begin:begin + close.start()]


def cut_at(lines, marker, name):
    """Everything above the design file's own mounting code.

    THE LINE IS DECLARED AND MUST BE THERE EXACTLY ONCE. Zero and several are
    told apart, because a marker matching nothing would silently lift the whole
    script, mounting code included, and one matching twice would cut at
    whichever came first with nothing saying a choice had been made (L100, L521).
    """
    wanted = marker.strip()
    at = [n for n, line in enumerate(lines) if line.strip() == wanted]
    if len(at) != 1:
        raise Refusal(BAD_SHAPE,
                      "the line the builder ends before is on %d line(s) of %s's script, "
                      "and it has to be on exactly one." % (len(at), name),
                      "It is compared whole, with the surrounding spaces ignored.")
    if at[0] == 0:
        raise Refusal(BAD_SHAPE, "the line the builder ends before is the script's first "
                                 "line, so there would be no builder at all.")
    return lines[:at[0]]


def strip_lines(lines, markers, name):
    """The mounting code and state switches that sit ABOVE the cut.

    Each marker must remove at least one line. A marker that removed none is a
    refusal, because the line it was written for is still in the builder and the
    spec reads as though it had been taken out (L100).
    """
    kept, counted = list(lines), {}
    for marker in markers:
        wanted = marker.strip()
        hits = [n for n, line in enumerate(kept) if line.strip() == wanted]
        if not hits:
            raise Refusal(LIFT_REFUSED,
                          "no line of %s's builder is %r, so stripping it took nothing "
                          "out and whatever it names is still in the lifted builder."
                          % (name, wanted))
        counted[wanted] = len(hits)
        kept = [line for n, line in enumerate(kept) if n not in set(hits)]
    return kept, counted


def apply_moves(body, moves, name):
    """One variable per value the round moves, declared above the lifted builder.

    The value is replaced WHERE THE DESIGN FILE HARD CODES IT, so every use of
    it moves together. A value that is not in the builder is a refusal: the
    variable would be declared, never read, and every option in the round would
    draw the same screen while the spec said otherwise (L100).
    """
    counted = {}
    for move in moves:
        variable, holds = move["variable"], move["holds"]
        hits = body.count(holds)
        if hits == 0:
            raise Refusal(LIFT_REFUSED,
                          "the value move %r says it moves is not in %s's builder, so the "
                          "variable would be declared and never read, and every option "
                          "would draw the same screen." % (move["field"], name))
        if re.search(r"\b%s\b" % re.escape(variable), body):
            raise Refusal(LIFT_REFUSED,
                          "move %r wants the variable %s, and %s's builder already uses "
                          "that name, so the lift would change what the existing one "
                          "means." % (move["field"], variable, name))
        body = body.replace(holds, variable)
        counted[move["field"]] = hits
    return body, counted


def build_screen(spec):
    """The one function every option in the round goes through.

    IT REFUSES A LABEL MATCHING ANYTHING BUT ONE FIXTURE, and that refusal is the
    point of it: a label matching none would draw an empty page, and an empty
    page in a switcher looks like a design finding rather than a mistake in the
    spec (L98, L521).
    """
    lines = [
        "",
        "/* buildScreen(variant): the one function every option in this round goes",
        "   through, so that everything held identical between options is structural",
        "   rather than a promise. It picks ONE fixture by its label and refuses any",
        "   other number: a label matching none would draw an empty page, and an empty",
        "   page under a switcher reads as a design finding rather than a mistake in",
        "   the spec. */",
        "function buildScreen(variant) {",
        "  variant = variant || {};",
    ]
    for move in spec["moves"]:
        lines.append("  %s = (variant.%s !== undefined) ? variant.%s : %s;"
                     % (move["variable"], move["field"], move["field"], move["holds"]))
    lines += [
        "  var fixtures = (%s);" % spec["fixtures"],
        "  var wanted = variant.%s;" % spec["label"],
        "  var found = [];",
        "  for (var i = 0; i < fixtures.length; i++) {",
        "    if (fixtures[i][%s] === wanted) { found.push(fixtures[i]); }"
        % json.dumps(spec["label"]),
        "  }",
        "  if (found.length !== 1) {",
        "    throw new Error(\"buildScreen: \" + found.length + \" of the \" + fixtures.length +",
        "      \" fixtures carry the label \" + JSON.stringify(wanted) +",
        "      \", and exactly one has to. A label matching none draws an empty page.\");",
        "  }",
        "  var fixture = found[0];",
        "  return (%s);" % spec["screen_from"],
        "}",
        "",
    ]
    return "\n".join(lines)


def lift(spec):
    """The lifted stylesheet and the lifted builder, with a report of what moved."""
    path = spec["source_path"]
    name = os.path.basename(path)
    if not os.path.isfile(path):
        raise Refusal(USED_WRONGLY, "the design file the spec names is not there: %s" % path)
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    css, retargeted = retarget(one_style_block(text, name), spec["page_rules"], name)
    body = last_script(text, name)
    kept = cut_at(body.split("\n"), spec["builder_ends_before"], name)
    kept, stripped = strip_lines(kept, spec["strip"], name)
    lifted = "\n".join(kept)

    if re.search(r"\bfunction\s+buildScreen\b", lifted):
        raise Refusal(LIFT_REFUSED,
                      "%s's builder already defines buildScreen, and this appends one, so "
                      "the lift would silently replace the file's own." % name,
                      "Strip the file's own definition, or rename it, before lifting.")

    lifted, moved = apply_moves(lifted, spec["moves"], name)

    head = ["/* Lifted from %s by scripts/lift-design-harness.sh (ovation#196)." % name,
            "   Do not edit by hand: re-run the lift, and --check says when this is no",
            "   longer the screen the design file draws.",
            "",
            "   WHAT THIS ROUND MOVES. Each variable below is a value the design file",
            "   hard codes. buildScreen puts the variant's own value in its place, and",
            "   falls back to what the design file holds when the variant names none. */"]
    for move in spec["moves"]:
        head.append("var %s = %s;" % (move["variable"], move["holds"]))
    head.append("")

    builder = "\n".join(head) + lifted + build_screen(spec)
    header = ("/* Lifted from %s by scripts/lift-design-harness.sh (ovation#196).\n"
              "   %s\n"
              "   Do not edit by hand: re-run the lift. */\n"
              % (name, "Retargeted onto the screen: "
                       + ", ".join("%s to %s" % (s, spec["page_rules"][s])
                                   for s in sorted(retargeted))
                 if retargeted else "No rule needed retargeting."))
    return header + css, builder, retargeted, stripped, moved


# ---------------------------------------------------------------------------
# The faithfulness check.
# ---------------------------------------------------------------------------

# ONE MEASUREMENT, INJECTED INTO BOTH PROBES. Two copies of it would be two
# definitions of what counts as the same screen, and the copy that fell behind
# would report a difference that was only in the measuring (L370, L70).
MEASURE = r"""
function ovationMeasure(root, ignore) {
  var base = root.getBoundingClientRect();
  var rows = [];
  var counted = {};
  ignore.forEach(function (selector) { counted[selector] = 0; });
  function box(node, path) {
    var r = node.getBoundingClientRect();
    return [path, node.tagName, node.getAttribute("class") || "",
            Math.round(r.x - base.x), Math.round(r.y - base.y),
            Math.round(r.width), Math.round(r.height)];
  }
  /* An ignored element takes its whole subtree with it, because a rail that
     reflows moves everything inside it and naming each one would be a list
     nobody could keep up to date. */
  function ignored(node) {
    var hit = false;
    ignore.forEach(function (selector) {
      if (node.matches(selector)) { counted[selector] = counted[selector] + 1; hit = true; }
    });
    return hit;
  }
  rows.push(box(root, ""));
  (function visit(node, path) {
    for (var i = 0; i < node.children.length; i++) {
      var child = node.children[i];
      if (ignored(child)) { continue; }
      var here = path + "/" + i;
      rows.push(box(child, here));
      visit(child, here);
    }
  })(root, "");
  return { rows: rows, ignored: counted };
}
/* AN IGNORE SELECTOR THE BROWSER CANNOT READ MUST NOT BE READ AS MATCHING
   NOTHING, so it is offered to the browser once, up front, inside the same try
   that reports every other fault (L215). */
function ovationCheckSelectors(ignore) {
  ignore.forEach(function (selector) { document.querySelector(selector); });
}
"""


def probe_for_design(spec):
    """Draw option 1 WHERE THE DESIGN FILE DRAWS ITS SCREEN, and measure it.

    The fixture is built by the file's own builder and put in the place of the
    screen already on the page, so it is measured under every rule, every
    inherited value and every ancestor the design file gives it. Measuring a
    detached element instead would compare the harness against something the
    design file never draws.
    """
    return """
<script>
(function () {
  %(measure)s
  var IGNORE = %(ignore)s;
  var report;
  try {
    ovationCheckSelectors(IGNORE);
    var fixtures = (%(fixtures)s);
    var wanted = %(option)s;
    var found = [];
    for (var i = 0; i < fixtures.length; i++) {
      if (fixtures[i][%(label)s] === wanted) { found.push(fixtures[i]); }
    }
    if (found.length !== 1) {
      throw new Error(found.length + " of the " + fixtures.length +
        " fixtures carry the label the spec calls option 1, and exactly one has to.");
    }
    var fixture = found[0];
    var here = document.querySelectorAll(%(screen)s);
    if (here.length !== 1) {
      throw new Error(here.length + " element(s) match the screen selector " +
        %(screen)s + ", and exactly one has to.");
    }
    var built = (%(screen_from)s);
    here[0].replaceWith(built);
    report = ovationMeasure(built, IGNORE);
  } catch (e) { report = { error: String((e && e.message) || e) }; }
  var pre = document.createElement("pre");
  pre.id = "ovation-probe";
  pre.textContent = JSON.stringify(report);
  document.body.appendChild(pre);
})();
</script>
""" % {"measure": MEASURE, "ignore": json.dumps(spec["ignore"]),
       "fixtures": spec["fixtures"], "option": json.dumps(spec["option_one"]),
       "label": json.dumps(spec["label"]), "screen": json.dumps(spec["screen"]),
       "screen_from": spec["screen_from"]}


def option_one(spec):
    variant = dict(spec["variant"])
    variant[spec["label"]] = spec["option_one"]
    return variant


def probe_for_harness(spec, variant=None, markup=False):
    """Draw one variant through the lifted buildScreen and measure it the same
    way, option 1 unless another is named. With `markup` the built element's
    markup is reported beside its boxes, for the proof that a move moves
    something, which has to see a word change inside a box that did not."""
    variant = option_one(spec) if variant is None else variant
    return """
<script>
(function () {
  %(measure)s
  var IGNORE = %(ignore)s;
  var report;
  try {
    ovationCheckSelectors(IGNORE);
    var built = buildScreen(%(variant)s);
    document.body.appendChild(built);
    report = ovationMeasure(built, IGNORE);
    if (%(markup)s) { report.markup = built.outerHTML; }
  } catch (e) { report = { error: String((e && e.message) || e) }; }
  var pre = document.createElement("pre");
  pre.id = "ovation-probe";
  pre.textContent = JSON.stringify(report);
  document.body.appendChild(pre);
})();
</script>
""" % {"measure": MEASURE, "ignore": json.dumps(spec["ignore"]),
       "variant": json.dumps(variant), "markup": "true" if markup else "false"}


# THE PAGE THE HARNESS IS DRAWN IN, and it is deliberately not the design file's.
#
# A screen lifted out of its own page has to carry its own typography, because
# the page it is going to is somebody else's. The rule below is declared AFTER
# the lifted stylesheet, so a `body` rule the lift left behind loses to it
# exactly as it would lose to the switcher's own chrome, and a screen still
# depending on one draws in this face instead of its own. That is the loss the
# whole tool exists to find, and composing a page with no rule at all would hide
# it: the lifted `body` rule would simply style THIS body and reach the screen
# again by inheritance.
#
# It is deliberately NOT a copy of the switcher's own chrome. A copy of another
# project's file maintained by hand here would drift, and what has to be true is
# that the screen depends on NO page rather than on that particular one (L41).
HARNESS_PAGE = """
/* The page the lifted screen is drawn in. Not the design file's page, and not
   the switcher's either: a screen that draws correctly under a page it has
   never met is one that carries its own typography. */
body { margin: 0; padding: 0; background: #FFFFFF; color: #000000;
       font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
"""


def compose(styles, builder, into):
    """The page the harness is rendered in.

    The doctype is not decoration: a page without one is in quirks mode and lays
    the same markup out differently, which is what ovation#194 turned out to be
    (L451).
    """
    for text, what, closer in ((styles, STYLES, "</style"), (builder, BUILDER, "</script")):
        if closer in text.lower():
            raise Refusal(LIFT_REFUSED,
                          "%s holds a %s>, which would end the block it is inlined in and "
                          "leave the rest of it drawn as text." % (what, closer))
    doctype = "" if os.environ.get("OVATION_HARNESS_QUIRKS", "").strip() else "<!doctype html>\n"
    page = (doctype + "<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
            "<title>The lifted harness</title>\n<style>\n" + styles + "\n</style>\n"
            "<style>" + HARNESS_PAGE + "</style>\n"
            "</head>\n<body>\n<script>\n" + builder + "\n</script>\n</body>\n</html>\n")
    with open(into, "w", encoding="utf-8") as handle:
        handle.write(page)
    return into


def name_of(row):
    """An element, said the way a person can find it: its tag, its classes and
    the child indexes that reach it from the screen's own root."""
    tag = row[1].lower()
    classes = "".join("." + c for c in row[2].split() if c)
    return "%s%s at %s" % (tag, classes, row[0] or "the screen's own root")


def boxes_of(row):
    return "x %d, y %d, %d by %d" % (row[3], row[4], row[5], row[6])


def differences(design, harness, tolerance):
    """Every element that differs, in the order they are drawn.

    A DIFFERENCE IN SHAPE STOPS THE WALK. Once the two trees disagree about
    which element is where, every row after it is being compared against a
    different element, and reporting those would bury the one fault under
    hundreds of consequences of it.
    """
    faults = []
    for index in range(min(len(design), len(harness))):
        a, b = design[index], harness[index]
        if a[0] != b[0] or a[1] != b[1] or a[2] != b[2]:
            faults.append(("DRAWS A DIFFERENT ELEMENT", a, b))
            return faults, True
        if any(abs(a[at] - b[at]) > tolerance for at in (3, 4, 5, 6)):
            faults.append(("DRAWS IT IN A DIFFERENT PLACE OR SIZE", a, b))
    if len(design) != len(harness):
        extra = design[len(harness):] if len(design) > len(harness) else harness[len(design):]
        faults.append(("DRAWN BY THE %s ONLY"
                       % ("DESIGN FILE" if len(design) > len(harness) else "HARNESS"),
                       extra[0], None))
    return faults, False


def read_report(session, path, probe, what):
    report = session.render(path, probe)
    if not isinstance(report, dict):
        raise Refusal(UNREADABLE, "%s's probe wrote something that is not a report" % what)
    if report.get("error") is not None:
        raise Refusal(UNREADABLE, "%s could not be read: %s" % (what, report["error"]),
                      "Nothing was compared.")
    if not isinstance(report.get("rows"), list) or not report["rows"]:
        raise Refusal(UNREADABLE, "%s's probe measured no elements at all" % what)
    return report


def prove_moves(session, spec, page):
    """Draw option 1's fixture once per value of each move, in a fresh page each,
    and return (field, count, first, second) for every move two of whose values
    drew the same screen, with (field, count, None, None) for every move whose
    values all differed.

    A FRESH PAGE PER VALUE, so a builder that keeps state between calls cannot
    make one value's drawing depend on the one before it. And the comparison is
    the WHOLE drawing, markup and boxes, never the value itself: what has to be
    proved is that the screen moved, not that the variable was assigned (L63).
    """
    answers = []
    for move in spec["moves"]:
        drawn = []
        for index, value in enumerate(move["values"]):
            variant = option_one(spec)
            variant[move["field"]] = value
            report = read_report(session, page, probe_for_harness(spec, variant, True),
                                 "the harness with value %d of variant.%s"
                                 % (index + 1, move["field"]))
            drawn.append(json.dumps([report.get("markup"), report["rows"]]))
        twin = None
        for later in range(len(drawn)):
            for earlier in range(later):
                if twin is None and drawn[earlier] == drawn[later]:
                    twin = (earlier + 1, later + 1)
        answers.append((move, len(drawn)) + (twin or (None, None)))
    return answers


def check(spec, out_dir):
    styles_at = os.path.join(out_dir, STYLES)
    builder_at = os.path.join(out_dir, BUILDER)
    for path in (styles_at, builder_at):
        if not os.path.isfile(path):
            raise Refusal(USED_WRONGLY,
                          "there is no %s in %s, so there is no harness to judge."
                          % (os.path.basename(path), out_dir),
                          "Write one with: scripts/lift-design-harness.sh <spec> <out-dir>")
    name = os.path.basename(spec["source_path"])
    if not os.path.isfile(spec["source_path"]):
        raise Refusal(USED_WRONGLY, "the design file the spec names is not there: %s"
                      % spec["source_path"])

    try:
        session = open_browser()
    except CannotMeasure as err:
        raise Refusal(NO_BROWSER, str(err))

    holder = tempfile.mkdtemp(prefix="ovation-harness-")
    page = compose(open(styles_at, encoding="utf-8").read(),
                   open(builder_at, encoding="utf-8").read(),
                   os.path.join(holder, "harness.html"))
    try:
        with session:
            design = read_report(session, spec["source_path"], probe_for_design(spec), name)
            harness = read_report(session, page, probe_for_harness(spec), "the harness")
            faithful = not differences(design["rows"], harness["rows"], spec["tolerance"])[0]
            # THE MOVES ARE PROVED ONLY ON A FAITHFUL LIFT. A lift that already
            # draws the wrong screen has one fault to report, and a proof run
            # over it would be a claim about a screen nobody meant (L475).
            moved = prove_moves(session, spec, page) if faithful else []
    except CannotMeasure as err:
        raise Refusal(NO_BROWSER, str(err))

    # AN EXEMPTION THAT MATCHED NOTHING IS NOT AN EXEMPTION. It reads as a
    # deliberate one on both sides, and the comparison it was loosening is
    # therefore not the comparison anybody thinks is running (L100, L233).
    unused = [s for s in spec["ignore"]
              if not design["ignored"].get(s) and not harness["ignored"].get(s)]
    if unused:
        raise Refusal(UNREADABLE,
                      "%d ignore selector(s) matched nothing in either rendering: %s."
                      % (len(unused), ", ".join(unused)),
                      "An exemption that matches nothing still reads as a deliberate "
                      "one, so this is refused rather than passed.")

    print("  design file  %s, option 1 is %r" % (name, spec["option_one"]))
    print("  harness      %s and %s, rendered in a page the screen has never met"
          % (STYLES, BUILDER))
    print("  comparing    tag, classes and box, %d element(s) against %d, tolerance %dpx"
          % (len(design["rows"]), len(harness["rows"]), spec["tolerance"]))
    if spec["ignore"]:
        for selector in spec["ignore"]:
            print("  ignoring     %s and everything inside it, %d in the design file and "
                  "%d in the harness" % (selector, design["ignored"].get(selector, 0),
                                         harness["ignored"].get(selector, 0)))
    else:
        print("  ignoring     nothing")

    faults, stopped = differences(design["rows"], harness["rows"], spec["tolerance"])
    if not faults:
        print("SAME: the harness draws the screen %s draws, %d element(s), tag, classes "
              "and box." % (name, len(design["rows"])))
        return report_moves(moved)

    print("DIFFERS: the harness does not draw the screen %s draws." % name)
    for kind, a, b in faults[:8]:
        print("  %s" % kind)
        print("    the design file  %s, %s" % (name_of(a), boxes_of(a)))
        if b is None:
            print("    the harness      draws no element there at all")
        else:
            print("    the harness      %s, %s" % (name_of(b), boxes_of(b)))
    if len(faults) > 8:
        print("  and %d more." % (len(faults) - 8))
    if stopped:
        print("    The walk stops at the first element the two draw differently: every "
              "element after it would be compared against a different one.")
    print("    A lift loses whatever the screen inherited from the page it came from, "
          "silently, because the lifted copy still renders. Retarget the page's rules "
          "onto the screen through the spec's page_rules.")
    return DIFFERS


def report_moves(moved):
    """What the proof of the moves found, one line per move (ovation#407)."""
    inert = False
    for move, count, first, second in moved:
        if first is None:
            print("MOVES: variant.%s draws %d different screens for its %d values, markup "
                  "and box." % (move["field"], count, count))
            continue
        inert = True
        print("INERT: variant.%s draws the same screen for values %d and %d, so a round "
              "moving it would offer a choice between copies of one screen."
              % (move["field"], first, second))
        print("    The builder does not read %s while it builds the screen. The usual "
              "cause is a literal evaluated once, when the script loads, that already "
              "holds the original value by the time buildScreen assigns the variable."
              % move["variable"])
        print("    Build that literal in a function called on every draw, as "
              "invoice-list.html's groupsFor() does, or move a value the builder does "
              "read.")
    return INERT if inert else WRITTEN


# ---------------------------------------------------------------------------

def write(spec, out_dir):
    styles, builder, retargeted, stripped, moved = lift(spec)
    try:
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, STYLES), "w", encoding="utf-8") as handle:
            handle.write(styles)
        with open(os.path.join(out_dir, BUILDER), "w", encoding="utf-8") as handle:
            handle.write(builder)
    except OSError as err:
        raise Refusal(USED_WRONGLY, "the harness could not be written into %s: %s"
                      % (out_dir, err))
    name = os.path.basename(spec["source_path"])
    print("WROTE: %s and %s in %s, lifted from %s."
          % (STYLES, BUILDER, out_dir, name))
    for selector in sorted(retargeted):
        print("  retargeted   %s onto %s, %d rule(s)"
              % (selector, spec["page_rules"][selector], retargeted[selector]))
    for marker in sorted(stripped):
        print("  stripped     %d line(s) of the file's own mounting code" % stripped[marker])
    for move in spec["moves"]:
        print("  moves        variant.%s through %s, %d place(s) in the builder"
              % (move["field"], move["variable"], moved[move["field"]]))
    print("  option 1     %r, picked by label, and buildScreen refuses any other count"
          % spec["option_one"])
    print("  next         --check renders both and compares, draws each move's values "
          "to prove they differ, then make-switcher.py turns these two files into the "
          "round's page.")
    return WRITTEN


def main(argv):
    checking = argv[:1] == ["--check"]
    rest = argv[1:] if checking else argv
    if len(rest) != 2:
        print(__doc__.strip())
        return USED_WRONGLY
    spec = read_spec(rest[0])
    return check(spec, rest[1]) if checking else write(spec, rest[1])


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print("REFUSED: %s" % refusal.said if refusal.code != NO_BROWSER
              else "CANNOT MEASURE: %s" % refusal.said)
        for line in refusal.more:
            print("    %s" % line)
        sys.exit(refusal.code)
