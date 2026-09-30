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
field that sets it.

A MOVE CAN BE A STYLESHEET RULE INSTEAD (ovation#560). Every round of ovation#110
moved a CSS value, and because this tool moved builder values only, each was a
hand built frame embedding the whole design file, which shipped three faults
into switchers that were found only by looking. A move naming a `rule` and a
`property` has no `variable`:

      {"field": "rowPad", "rule": ".row", "property": "padding",
       "holds": "4px", "values": ["4px", "14px"]}

The declaration is rewritten as `padding: var(--lift-rowPad, 4px)`, so a variant
naming no value draws the design file's own, and buildScreen sets
`--lift-rowPad` on the screen it builds. ON THE SCREEN, never in a stylesheet of
the option's own, so two options drawn at once under one switcher cannot reach
each other's value. The rule is matched whole as the design file writes it,
BEFORE any page rule is retargeted, so a round on what the screen inherits from
`body` names `body`. A rule that is not there, a property it never declares, a
declaration holding another value than `holds`, and a custom property name the
stylesheet already uses are each a refusal, because each reads as a step taken.

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
the built element's markup, its text and attributes included, every element's
computed style, and every element's tag, classes and box: a word changed inside
a fixed width box moves no box, a width changed through a class moves no text,
and a colour moves neither, so any one alone would pass a move another can see.
The markup is read with the lift's own `--lift-` properties taken off, because a
stylesheet move writes one onto the screen for every value, and counting it
would prove a move overridden by a later rule moves something (L63). A stylesheet
move is refused this way when a later or more specific rule wins, which is the
fault it most often has. The values are compared, never printed: a
refusal names them by their place in the list.

THE FRAME MODE (ovation#560). A round that reshapes a screen from inside, a
search that narrows a whole list or a band that collapses, is drawn more
honestly by the design file itself than by a lifted builder. So a spec whose
`mode` is "frame" writes a builder that draws the committed file in a frame,
showing only its window:

    {
      "mode":    "frame",
      "source":  "invoice-list.html",
      "window":  ".win",            the one element the frame shows (default)
      "patch":   "round.js",        optional: the round's own script, run in the
                                    frame after the file's, reading LIFT_VARIANT
      "stage":   900,               the stage width --check draws it on (default)
      "viewport": 1440,             the frame's page width (default)
      "moves":  [{"field": "rowPad", "rule": ".row", "property": "padding",
                  "holds": "4px", "values": ["4px", "14px"]},
                 {"field": "mode", "values": ["narrow", "flat"]}],
      "same":   {"tolerance": 0, "ignore": []}
    }

A move with a rule is a stylesheet move as above, set on the frame's own root,
and a move without one is carried by `patch`, which has to name
LIFT_VARIANT.<field>. Every round of ovation#110 built this frame by hand, and
three faults shipped through the hand built ones into switchers; each is now
the frame's to prevent and --check's to refuse, exit 9: the embedded page is
written with every `</` escaped, so its own closing script tag cannot end the
switcher's script and leave an empty frame; the frame is as tall as its page
and moved by the window's MEASURED place, so it never depends on a scroll at
load and cannot show the page's intro instead; and the caption, the window's
width and the scale it is drawn at, is written from what was measured in the
switcher's own page, and --check reads it beside an independent measurement of
the same drawing, rounded the way the caption rounds. The frame is pinned to
the top of the stage, which the switcher otherwise centres it on, and it is
fitted again whenever its stage changes size, so an option built while hidden
is measured when it is shown; --check draws on a stage that centres as the
switcher's does and on one hidden and then shown, and refuses both faults. A
builder that cannot run is told apart from one cut short by a closing tag.
--check also compares the framed window with the design
file's own, element by element, and proves every move's values draw different
windows, as for a lifted builder.

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
    9  --check on a frame, and the frame draws wrongly: its builder ends the
       script it is inlined in (an empty frame), or could not run at all, which
       is said apart; it draws no window; it shows something other than the
       window; it leaves empty stage above the window; it is wider than its
       stage, or never fitted when a hidden stage is shown; or its caption
       states a width or a scale the drawing does not have

Seams: OVATION_HEADLESS_BROWSER, OVATION_HARNESS_QUIRKS (compose the harness
page with NO doctype, so the document mode difference of ovation#194 can be
produced on purpose; it can only ever make this refuse, never pass).
"""
import json
import math
import os
import re
import shutil
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

FRAME_REQUIRED = ["source", "moves"]
# The fields only one mode reads. A spec carrying the other mode's is refused.
LIFT_ONLY = ["screen", "fixtures", "label", "screen_from", "option_one",
             "builder_ends_before", "strip", "page_rules", "variant"]
FRAME_ONLY = ["window", "patch", "stage", "viewport"]
# The frame is drawn at the width the rendering checks draw every design file at,
# so the window it shows is laid out as the checks see it, and judged on a stage
# narrower than most windows, so the scale and its caption are always exercised.
FRAME_DEFAULTS = {"stage": 900, "viewport": 1440}

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

    # THE FRAME MODE (ovation#560) needs only the file and what it moves: the
    # screen is the design file's own window, drawn by the design file's own
    # scripts inside a frame, so there is no builder to cut and no fixture to pick.
    framing = spec.get("mode") == "frame"
    if "mode" in spec and not framing:
        raise Refusal(BAD_SPEC, "the spec's mode is %r, and the one mode there is is "
                                "\"frame\"; leave it out for a lifted builder"
                      % (spec["mode"],))
    # A FIELD THE MODE DOES NOT USE IS REFUSED BY NAME. Carried quietly, a lifted
    # builder's `screen` in a frame spec, or a frame's `stage` in a lift spec,
    # reads as a setting that did something (L11).
    foreign = sorted(key for key in spec
                     if key in (LIFT_ONLY if framing else FRAME_ONLY))
    if foreign:
        raise Refusal(BAD_SPEC,
                      "the spec is for %s, and carries %s it does not use: %s."
                      % ("a frame" if framing else "a lifted builder",
                         "a field" if len(foreign) == 1 else "fields", ", ".join(foreign)),
                      "Remove %s, or %s." % ("it" if len(foreign) == 1 else "them",
                                              "drop \"mode\": \"frame\" to lift a builder"
                                              if framing else
                                              "set \"mode\": \"frame\" to frame the file"))
    missing = [key for key in (FRAME_REQUIRED if framing else REQUIRED) if key not in spec]
    if missing:
        raise Refusal(BAD_SPEC,
                      "the spec is missing %s: %s." % (
                          "a field" if len(missing) == 1 else "fields",
                          ", ".join(missing)),
                      "Run this with no arguments for the shape of a spec.")
    for key in (("source", "window") if framing else
                ("source", "screen", "fixtures", "screen_from", "option_one",
                 "builder_ends_before")):
        if key == "window":
            spec.setdefault("window", ".win")
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
        # A MOVE NAMING A RULE IS A STYLESHEET MOVE (ovation#560), and its shape
        # is its own: a rule and a property say where it is, and a builder
        # variable would be declared and never read, so naming one is refused
        # rather than quietly ignored.
        in_styles = "rule" in move
        # IN A FRAME, A MOVE THAT IS NOT A RULE IS CARRIED BY THE ROUND'S OWN
        # SCRIPT, `patch`, which runs inside the frame after the design file's
        # and reads LIFT_VARIANT. It names only its field and values: there is
        # no builder in which a value could be replaced.
        by_patch = framing and not in_styles
        if by_patch and not spec.get("patch"):
            raise Refusal(BAD_SPEC,
                          "move %d names no stylesheet rule, so in a frame it can only be "
                          "carried by the round's own script, and the spec names no patch."
                          % (index + 1),
                          "Name a rule and a property, or a patch that reads "
                          "LIFT_VARIANT.%s." % move.get("field", "<field>"))
        needed = ("field", "rule", "property", "holds") if in_styles \
            else ("field",) if by_patch else ("field", "variable", "holds")
        for key in needed:
            if not isinstance(move.get(key), str) or not move[key].strip():
                raise Refusal(BAD_SPEC, "move %d has no %s, so nothing says what it moves "
                                        "or what it moves it from" % (index + 1, key))
        if in_styles:
            if "variable" in move:
                raise Refusal(BAD_SPEC,
                              "move %d names a stylesheet rule and a builder variable, and a "
                              "stylesheet move declares no variable: the builder would never "
                              "read it." % (index + 1),
                              "Drop the variable; the move is named by its field.")
            # THE FIELD NAMES THE CUSTOM PROPERTY, --lift-<field>, and is read in
            # the builder as variant.<field>, so it has to be both.
            if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", move["field"]):
                raise Refusal(BAD_SPEC, "move %d names the field %r, which cannot name a "
                                        "custom property and a variant field both"
                              % (index + 1, move["field"]))
        elif by_patch:
            # A MOVE THE ROUND'S SCRIPT CARRIES HAS NO VARIABLE AND NOTHING IT
            # HOLDS: there is no builder to declare the one in or replace the
            # other in, so naming either is refused rather than dropped.
            named = [key for key in ("variable", "holds") if key in move]
            if named:
                raise Refusal(BAD_SPEC,
                              "move %d is carried by the round's script and names a %s, "
                              "which a frame has nowhere to put: there is no builder."
                              % (index + 1, " and a ".join(named)),
                              "Name a rule and a property to move a stylesheet value, or "
                              "only a field and its values for the round's script.")
            if not re.match(r"^[A-Za-z_$][A-Za-z0-9_$]*$", move["field"]):
                raise Refusal(BAD_SPEC, "move %d names the field %r, which the round's "
                                        "script could not read as LIFT_VARIANT.%s"
                              % (index + 1, move["field"], move["field"]))
        elif not re.match(r"^[A-Za-z_$][A-Za-z0-9_$]*$", move["variable"]):
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
    spec["framing"] = framing
    if framing:
        for key, low, high in (("stage", 200, 4000), ("viewport", 400, 4000)):
            value = spec.get(key, FRAME_DEFAULTS[key])
            if not isinstance(value, int) or isinstance(value, bool) or not low <= value <= high:
                raise Refusal(BAD_SPEC, "the spec's %s must be a whole number of points "
                                        "from %d to %d, and it is %r" % (key, low, high, value))
            spec[key] = value
        patch = spec.get("patch")
        if patch is not None and (not isinstance(patch, str) or not patch.strip()):
            raise Refusal(BAD_SPEC, "the spec's patch must name a script file, and it is %r"
                          % (patch,))
        spec["patch_path"] = (os.path.join(os.path.dirname(os.path.abspath(path)), patch)
                              if patch else None)
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


def custom_property(move):
    """The custom property a stylesheet move is carried by, derived from its
    field so the builder and the stylesheet cannot name two different ones."""
    return "--lift-" + move["field"]


def declarations(css, open_brace):
    """(start, end, property, value start, value end) for each declaration in
    the rule whose block opens at `open_brace`, and where the block closes.

    Split at the semicolons that sit outside quotes, comments and parentheses,
    because a `url(data:...;base64,...)` carries one and a split through it
    would read half a value as a property."""
    found, i, n = [], open_brace + 1, len(css)
    start, paren = i, 0

    def close(at):
        text = css[start:at]
        colon = text.find(":")
        if colon > 0 and text[:colon].strip():
            found.append((start, at, text[:colon].strip().lower(),
                          start + colon + 1, at))

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
        if c == "(":
            paren += 1
        elif c == ")":
            paren -= 1
        elif c == ";" and paren == 0:
            close(i)
            start = i + 1
        elif c == "}" and paren == 0:
            close(i)
            return found, i
        i += 1
    return found, n


def move_rules(css, moves, name):
    """Turn each stylesheet move's declaration into a custom property, with the
    design file's own value as its fallback (ovation#560).

    THE FALLBACK IS THE FILE'S VALUE, so a harness drawn with no variant draws
    exactly what the design file draws, and the faithfulness check judges the
    lift rather than the move. The property is SET ON THE BUILT SCREEN by
    buildScreen, never in a stylesheet of its own, so two options drawn at once
    under one switcher cannot take each other's value.

    Each step that takes no effect is its own refusal, because each reads as
    taken: a rule that is not there, a property that rule never declares, and a
    declaration holding some other value than the one the spec says it moves
    from. Values are never printed, only counted (docs/PRIVACY-FLOOR.md)."""
    counted = {}
    for move in [m for m in moves if "rule" in m]:
        prop = custom_property(move)
        # THE WHOLE NAME, never a substring: --lift-rowPadding is not
        # --lift-rowPad, and a stylesheet carrying one, or an earlier move
        # writing one, must not block a move for the other.
        if re.search(re.escape(prop) + r"(?![A-Za-z0-9_-])", css):
            raise Refusal(LIFT_REFUSED,
                          "move %r would be carried by %s, and %s's stylesheet already "
                          "uses that name, so the lift would change what it means."
                          % (move["field"], prop, name))
        wanted = " ".join(move["rule"].split())
        rules = [s for s in selector_spans(css, name) if " ".join(s[2].split()) == wanted]
        if not rules:
            raise Refusal(LIFT_REFUSED,
                          "no rule in %s has the selector %r, so move %r would move nothing."
                          % (name, move["rule"], move["field"]),
                          "The selector is matched whole, as the design file writes it, "
                          "before any page rule is retargeted.")
        property_name = move["property"].strip().lower()
        holds = " ".join(move["holds"].split())
        edits, declared = [], 0
        for _start, brace, _text in rules:
            for _d0, _d1, prop_name, v0, v1 in declarations(css, brace)[0]:
                if prop_name != property_name:
                    continue
                declared += 1
                value = css[v0:v1]
                important = re.search(r"\s*!\s*important\s*$", value, re.I)
                core = value[:important.start()] if important else value
                if " ".join(core.split()) != holds:
                    continue
                lead = len(core) - len(core.lstrip())
                edits.append((v0 + lead, v0 + len(core.rstrip()),
                              "var(%s, %s)" % (prop, core.strip())))
        if not edits:
            raise Refusal(LIFT_REFUSED,
                          "the rule %r in %s declares %s %d time(s), none of them with the "
                          "value the move says it holds, so move %r would move nothing."
                          % (move["rule"], name, property_name, declared, move["field"]),
                          "The value is compared whole, with its spacing ignored and any "
                          "!important left where it is.")
        for start, end, replacement in sorted(edits, reverse=True):
            css = css[:start] + replacement + css[end:]
        counted[move["field"]] = len(edits)
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
    for move in [m for m in moves if "rule" not in m]:
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
        if "rule" not in move:
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
        "  var built = (%s);" % spec["screen_from"],
    ]
    # A STYLESHEET MOVE IS SET ON THE SCREEN ITSELF (ovation#560), and only when
    # the variant names it, so a variant naming none draws the declaration's
    # own fallback, which is the design file's value.
    for move in spec["moves"]:
        if "rule" in move:
            lines.append("  if (variant.%s !== undefined) { built.style.setProperty(%s, "
                         "String(variant.%s)); }"
                         % (move["field"], json.dumps(custom_property(move)), move["field"]))
    lines += [
        "  return built;",
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

    # THE STYLESHEET MOVES ARE MADE BEFORE THE RETARGET, on the selectors as the
    # design file writes them, so a round on what the screen inherits from
    # `body` names `body` and not whatever the lift renamed it to.
    css, moved_rules = move_rules(one_style_block(text, name), spec["moves"], name)
    css, retargeted = retarget(css, spec["page_rules"], name)
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
    moved.update(moved_rules)

    head = ["/* Lifted from %s by scripts/lift-design-harness.sh (ovation#196)." % name,
            "   Do not edit by hand: re-run the lift, and --check says when this is no",
            "   longer the screen the design file draws.",
            "",
            "   WHAT THIS ROUND MOVES. Each variable below is a value the design file",
            "   hard codes. buildScreen puts the variant's own value in its place, and",
            "   falls back to what the design file holds when the variant names none.",
            "   A stylesheet move has no variable here: buildScreen sets its custom",
            "   property on the screen it builds (ovation#560). */"]
    for move in spec["moves"]:
        if "rule" not in move:
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
/* WHAT A MOVE IS JUDGED BY, beside the boxes (ovation#407, ovation#560): the
   built screen's markup and every element's computed style.

   The markup is read from a COPY with the lift's own custom properties taken
   off, because a stylesheet move writes its value onto the screen's style
   attribute and markup compared whole would differ for every value even where
   another rule overrides the declaration and nothing on screen moves. The proof
   must not count its own mechanism (L63).

   Computed style is there because a colour or a weight moves no box and no
   word, so boxes and markup alone would refuse a real colour round as inert.
   Custom properties are left out of it for the same reason as above, and the
   ::before and ::after of each element are read too, since a rule on one of
   those is a rule the screen draws. Each element's style is reduced to a hash
   in the page, because the whole of it runs to megabytes on a real screen. */
function ovationLook(root) {
  var copy = root.cloneNode(true);
  [copy].concat(Array.prototype.slice.call(copy.querySelectorAll("[style]"))).forEach(function (node) {
    if (!node.style) { return; }
    for (var i = node.style.length - 1; i >= 0; i--) {
      var name = node.style[i];
      if (name.indexOf("--lift-") === 0) { node.style.removeProperty(name); }
    }
    if (node.getAttribute("style") === "") { node.removeAttribute("style"); }
  });
  /* Two FNV-1a hashes with different seeds, 64 bits between them. */
  function hash(text) {
    var a = 0x811c9dc5, b = 0x01000193 ^ text.length;
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i);
      a = Math.imul(a ^ c, 16777619);
      b = Math.imul(b ^ c, 2246822519);
    }
    return (a >>> 0).toString(16) + ":" + (b >>> 0).toString(16);
  }
  function styleOf(node, pseudo) {
    var s = getComputedStyle(node, pseudo), out = [];
    for (var i = 0; i < s.length; i++) {
      if (s[i].indexOf("--") !== 0) { out.push(s[i] + ":" + s.getPropertyValue(s[i])); }
    }
    return out.join(";");
  }
  var styles = [root].concat(Array.prototype.slice.call(root.querySelectorAll("*"))).map(function (node) {
    return hash([styleOf(node, null), styleOf(node, "::before"), styleOf(node, "::after")].join("|"));
  });
  return { markup: copy.outerHTML, styles: styles };
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
    if (%(markup)s) {
      var look = ovationLook(built);
      report.markup = look.markup;
      report.styles = look.styles;
    }
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
            drawn.append(json.dumps([report.get("markup"), report.get("styles"),
                                     report["rows"]]))
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
    try:
        return judge_lift(spec, session, holder, styles_at, builder_at, name)
    finally:
        shutil.rmtree(holder, ignore_errors=True)


def judge_lift(spec, session, holder, styles_at, builder_at, name):
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
            print("MOVES: variant.%s draws %d different screens for its %d values, markup, "
                  "computed style and box." % (move["field"], count, count))
            continue
        inert = True
        print("INERT: variant.%s draws the same screen for values %d and %d, so a round "
              "moving it would offer a choice between copies of one screen."
              % (move["field"], first, second))
        if "rule" in move:
            print("    The declaration %s feeds is not the one the screen draws. The usual "
                  "cause is a later or more specific rule setting %s on the same "
                  "elements, or a rule that matches nothing inside the screen."
                  % (custom_property(move), move["property"]))
            print("    Move the declaration that wins, which the browser's inspector "
                  "names for the element, or name the rule it is written in.")
            continue
        if "variable" not in move:
            print("    The round's script does not change what the frame draws for "
                  "LIFT_VARIANT.%s. The usual cause is a script that reads the field and "
                  "then draws the same thing whatever it holds, or one whose change the "
                  "design file's own drawing undoes afterwards." % move["field"])
            continue
        print("    The builder does not read %s while it builds the screen. The usual "
              "cause is a literal evaluated once, when the script loads, that already "
              "holds the original value by the time buildScreen assigns the variable."
              % move["variable"])
        print("    Build that literal in a function called on every draw, as "
              "invoice-list.html's groupsFor() does, or move a value the builder does "
              "read.")
    return INERT if inert else WRITTEN


# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# The frame mode (ovation#560).
#
# A round whose variable is not a value in one builder, a search that reshapes
# the whole list or a band that collapses, is easier to draw by letting the
# design file draw itself and changing it from inside. Every round of ovation#110
# did exactly that, by hand, with an iframe embedding the committed file, and
# three faults shipped through the hand built frames into switchers and were
# found only by looking:
#
#   AN EMPTY FRAME. The embedded page was pasted into the builder as a string,
#   and its own closing script tag ended the switcher's script element early.
#   So every closing tag in the embedded page is written `<\/`, which a script
#   reads as the same character and the HTML parser does not read as a tag.
#
#   THE INTRO INSTEAD OF THE WINDOW. The frame scrolled to the window at load,
#   and in Dan's Chrome the scroll did not happen, so the frame showed the top of
#   the page. So the frame never scrolls: it is made as tall as the whole page,
#   so there is nothing to scroll, and the window is MEASURED where it lies and
#   the frame moved so that it sits at the clip's corner.
#
#   A MEASUREMENT THAT DID NOT MATCH THE DRAWING. A number was written into the
#   round by hand and the option drew something else. So the caption is written
#   by the frame from what it measured in the switcher's own page, the window's
#   width and the scale it is drawn at, and --check reads the caption beside an
#   independent measurement of the same drawing.
#
# The variant reaches the frame as LIFT_VARIANT, in a script appended after the
# design file's own, which sets each stylesheet move's custom property on the
# frame's root and then runs the round's own script, `patch`. Each option is its
# own frame, so an option's stylesheet can never reach another's.
# ---------------------------------------------------------------------------

FRAME = 9

FRAME_STYLES = """/* Written by scripts/lift-design-harness.sh in its frame mode (ovation#560).
   Do not edit by hand: re-run the lift. */
/* PINNED TO THE TOP OF THE STAGE (approved by Dan, 2026-09-29). The switcher
   centres whatever is on its stage with auto margins, which suits a screen
   switched between options of different heights, and left a framed window
   halfway down the page under about 250 points of empty stage. So the frame's
   top margin is 0 and only the sides and foot stay automatic; it is declared
   after the switcher's own rule and of the same weight, so it wins by order. */
.lift-frame { margin: 0 auto auto; display: flex; flex-direction: column; gap: 8px; }
.lift-frame-cap { margin: 0; font-size: 12px; line-height: 1.4; color: #6E6259; }
.lift-frame[data-state="failed"] .lift-frame-cap { color: #A4262C; font-weight: 600; }
.lift-frame-clip { position: relative; overflow: hidden; width: 0; height: 0; }
.lift-frame-clip iframe { position: absolute; left: 0; top: 0; border: 0;
  transform-origin: 0 0; background: transparent; }
"""

# WHAT THE FRAME DOES, as the script every frame builder carries. It holds no
# closing tag of any kind: the tag it appends to close its own style and script
# is written `<\/`, so the file can be inlined in a script element whole.
FRAME_RUNTIME = r"""
/* THE FRAME (ovation#560). buildScreen(variant) returns a box holding a caption
   and a clipped frame. The frame draws the design file itself, with the
   variant applied from inside it; once it has loaded and its fonts are in, the
   window is measured where it lies, the frame is made as tall as the page so
   nothing in it can scroll, and it is moved and scaled so the window sits at
   the clip's corner at the stage's width. The caption states the width and the
   scale that were just measured, so it cannot state a number the drawing does
   not have.

   Three states, told apart on the box's data-state and in the caption:
   loading, drawn, and failed, the last with the reason, including a frame that
   has not drawn ten seconds after it was put on a page. */
var LIFT_MARGIN = 16;
var LIFT_WAIT_MS = 10000;
var LIFT_FRAME_CSS = "html, body { background: transparent !important; }"
  + " html { overflow: hidden !important; }";

function liftFrameSay(box, state, words) {
  box.setAttribute("data-state", state);
  box._cap.textContent = words;
}

function liftFramePage(variant, bare) {
  var lines = ["var LIFT_VARIANT = " + JSON.stringify(variant) + ";"];
  LIFT_RULE_MOVES.forEach(function (move) {
    if (variant[move.field] !== undefined) {
      lines.push("document.documentElement.style.setProperty(" + JSON.stringify(move.property)
        + ", " + JSON.stringify(String(variant[move.field])) + ");");
    }
  });
  if (!bare) { lines.push(LIFT_PATCH); }
  var script = lines.join("\n").replace(/<\//g, "<\\/");
  return LIFT_PAGE + "<style>" + LIFT_FRAME_CSS + "<\/style><script>" + script + "<\/script>";
}

function liftFrameFit(box) {
  var fr = box._frame, doc = null;
  try { doc = fr.contentDocument; } catch (e) { doc = null; }
  if (!doc || !doc.body) {
    liftFrameSay(box, "failed", "The frame could not be read, so the window cannot be placed or measured.");
    return;
  }
  var wins = doc.querySelectorAll(LIFT_WINDOW);
  if (wins.length !== 1) {
    liftFrameSay(box, "failed", wins.length + " element(s) in the framed page match " + LIFT_WINDOW
      + ", and exactly one has to, so no window is drawn.");
    return;
  }
  /* As tall as the page, so there is nothing left to scroll: the window's place
     is read from layout, never from wherever a scroll at load did or did not
     leave it. */
  fr.style.height = Math.ceil(Math.max(doc.documentElement.scrollHeight, doc.body.scrollHeight)) + "px";
  var r = wins[0].getBoundingClientRect();
  var left = r.left - LIFT_MARGIN, top = r.top - LIFT_MARGIN;
  var w = r.width + 2 * LIFT_MARGIN, h = r.height + 2 * LIFT_MARGIN;
  var stage = box.parentElement, avail = 0;
  if (stage) {
    var cs = getComputedStyle(stage);
    avail = stage.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
  }
  liftFrameWatchStage(box);
  /* A STAGE WITH NO WIDTH IS ONE NOT SHOWN YET, and a scale read from it would
     be a guess stated as a measurement. The frame waits, and the watch on the
     stage fits it the moment the stage has a width. */
  if (!(avail > 0)) {
    liftFrameSay(box, "waiting", "Waiting for the stage to be shown before measuring the window.");
    return;
  }
  var s = Math.min(1, avail / w);
  box._clip.style.width = Math.floor(w * s) + "px";
  box._clip.style.height = Math.ceil(h * s) + "px";
  fr.style.transform = "scale(" + s + ")" + " translate(" + (-left) + "px, " + (-top) + "px)";
  liftFrameSay(box, "drawn", "The window is " + Math.round(r.width) + " points wide, drawn here at " + Math.round(s * 100) + "%.");
}

/* THE STAGE IS WATCHED, not read once. A switcher can build every option at
   once and show one, and an option drawn while hidden, or on a stage whose
   width changes, is fitted again whenever the stage it is on changes size,
   so its scale and caption are always the stage's current ones. */
function liftFrameWatchStage(box) {
  if (typeof ResizeObserver !== "function") { return; }
  var stage = box.parentElement;
  if (box._watched === stage) { return; }
  if (!box._watch) {
    box._watch = new ResizeObserver(function () {
      var state = box.getAttribute("data-state");
      if (state === "drawn" || state === "waiting") { liftFrameFit(box); }
    });
  }
  if (box._watched) { box._watch.unobserve(box._watched); }
  box._watched = stage;
  if (stage) { box._watch.observe(stage); }
}

function liftFrameLoaded(box) {
  liftFrameFit(box);
  var doc = null;
  try { doc = box._frame.contentDocument; } catch (e) { doc = null; }
  if (doc && doc.fonts && doc.fonts.ready) {
    doc.fonts.ready.then(function () {
      if (box.getAttribute("data-state") !== "failed") { liftFrameFit(box); }
      box.setAttribute("data-settled", "yes");
    });
  } else {
    box.setAttribute("data-settled", "yes");
  }
}

window.addEventListener("resize", function () {
  Array.prototype.forEach.call(document.querySelectorAll(".lift-frame"), function (box) {
    if (box.getAttribute("data-state") === "drawn") { liftFrameFit(box); }
  });
});

/* `bare` draws the design file with no round script, which is what --check
   compares against the design file itself. */
function liftFrame(variant, bare) {
  variant = variant || {};
  var box = document.createElement("div");
  box.className = "lift-frame";
  var cap = document.createElement("p");
  cap.className = "lift-frame-cap";
  var clip = document.createElement("div");
  clip.className = "lift-frame-clip";
  var fr = document.createElement("iframe");
  fr.setAttribute("title", "The window" + (variant.name ? ", " + variant.name : ""));
  fr.setAttribute("scrolling", "no");
  fr.style.width = LIFT_VIEWPORT + "px";
  fr.style.height = "900px";
  box._cap = cap;
  box._clip = clip;
  box._frame = fr;
  liftFrameSay(box, "loading", "Drawing the window.");
  fr.setAttribute("srcdoc", liftFramePage(variant, bare));
  fr.addEventListener("load", function () { liftFrameLoaded(box); });
  clip.append(fr);
  box.append(cap, clip);
  /* A frame that never loads must not read as one still loading. The clock
     starts when the box is SHOWN, never before: a switcher builds every option
     at once and shows one, so an option waiting unseen costs nothing, no timer
     and no poll. An intersection observer is told when the box first has a
     place on screen, which is exactly when its frame starts to load, and it is
     let go once the frame has drawn or failed. */
  if (typeof IntersectionObserver === "function") {
    var clock = null;
    var seen = new IntersectionObserver(function (entries) {
      if (box.getAttribute("data-state") !== "loading") { seen.disconnect(); return; }
      if (clock !== null || !entries.some(function (e) { return e.isIntersecting; })) { return; }
      clock = setTimeout(function () {
        seen.disconnect();
        if (box.getAttribute("data-state") === "loading") {
          liftFrameSay(box, "failed", "The window has not drawn after " + (LIFT_WAIT_MS / 1000)
            + " seconds. Reload the page to try again.");
        }
      }, LIFT_WAIT_MS);
    });
    seen.observe(box);
  }
  return box;
}

function buildScreen(variant) {
  return liftFrame(variant, false);
}
"""


def for_script(text):
    """A string a script element can carry whole: a JSON string literal with
    every `</` written `<\\/` and every `<!--` written `<\\!--`. A script reads
    both escapes as the characters they stand for, and the HTML parser sees
    neither, so no closing tag inside can end the element early and no comment
    opener can change how the parser reads the rest (the empty frame)."""
    return json.dumps(text).replace("</", "<\\/").replace("<!--", "<\\!--")


def lift_frame(spec):
    """The frame's builder and stylesheet, with a report of what moved."""
    path = spec["source_path"]
    name = os.path.basename(path)
    if not os.path.isfile(path):
        raise Refusal(USED_WRONGLY, "the design file the spec names is not there: %s" % path)
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    # THE STYLESHEET MOVES ARE MADE IN THE EMBEDDED PAGE, with the same rule and
    # the same refusals as a lifted builder's, so a declaration becomes
    # var(--lift-<field>, <the file's value>) and a frame given no value draws
    # the file as it stands.
    inner = one_style_block(text, name)
    moved_css, moved = move_rules(inner, spec["moves"], name)
    begin = re.search(r"<style\b[^>]*>", text, re.I).end()
    text = text[:begin] + moved_css + text[begin + len(inner):]

    patch = ""
    if spec.get("patch_path"):
        if not os.path.isfile(spec["patch_path"]):
            raise Refusal(USED_WRONGLY, "the round's script the spec names is not there: %s"
                          % spec["patch_path"])
        with open(spec["patch_path"], encoding="utf-8") as handle:
            patch = handle.read()
        if "</script" in patch.lower():
            raise Refusal(LIFT_REFUSED,
                          "the round's script %s holds a closing script tag, and it runs "
                          "inside a script element in the frame, so the tag would end it "
                          "there and the rest would be drawn as text."
                          % os.path.basename(spec["patch_path"]),
                          "Write it as \"<\\/script>\" inside the string.")
    for move in [m for m in spec["moves"] if "rule" not in m]:
        field = move["field"]
        # A FIELD THE SCRIPT NEVER NAMES IS A MOVE NOTHING CARRIES. This is the
        # cheap half; --check draws each value, which is the half that proves it.
        if not re.search(r"LIFT_VARIANT(\.%s\b|\[\s*[\"']%s[\"']\s*\])"
                         % (re.escape(field), re.escape(field)), patch):
            raise Refusal(LIFT_REFUSED,
                          "the round's script never reads LIFT_VARIANT.%s, so move %r would "
                          "draw every option the same." % (field, field))
        moved[field] = 1

    rule_moves = [{"field": m["field"], "property": custom_property(m)}
                  for m in spec["moves"] if "rule" in m]
    builder = "\n".join([
        "/* Framed from %s by scripts/lift-design-harness.sh (ovation#560)." % name,
        "   Do not edit by hand: re-run the lift, and --check says when the frame no",
        "   longer draws the window the design file draws. */",
        "var LIFT_PAGE = %s;" % for_script(text),
        "var LIFT_PATCH = %s;" % for_script(patch),
        "var LIFT_WINDOW = %s;" % for_script(spec["window"]),
        "var LIFT_VIEWPORT = %d;" % spec["viewport"],
        "var LIFT_RULE_MOVES = JSON.parse(%s);" % for_script(json.dumps(rule_moves)),
    ]) + "\n" + FRAME_RUNTIME
    return FRAME_STYLES, builder, moved


def write_frame(spec, out_dir):
    styles, builder, moved = lift_frame(spec)
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
    print("WROTE: %s and %s in %s, framing %s." % (STYLES, BUILDER, out_dir, name))
    print("  framed       %s, the design file drawing itself in a frame %d points wide"
          % (spec["window"], spec["viewport"]))
    for move in spec["moves"]:
        if "rule" in move:
            print("  moves        variant.%s through %s, %d declaration(s) in the stylesheet"
                  % (move["field"], custom_property(move), moved[move["field"]]))
        else:
            print("  moves        variant.%s through the round's script, as LIFT_VARIANT.%s"
                  % (move["field"], move["field"]))
    print("  next         --check draws the frame in a page the way the switcher does, and "
          "judges where the window lands and what its caption says.")
    return WRITTEN


def compose_host(styles, builder, stage, into):
    """The page --check draws the frame in, built the way the switcher builds its
    own: the builder inlined WHOLE in a script element, with no refusal first,
    because the empty frame is found by what that inlining does, and a stage of
    a fixed width for the frame to scale to."""
    # THE STAGE LAYS ITS CONTENT OUT AS THE SWITCHER'S DOES: a flex box taller
    # than a small frame, whose children take automatic margins, so a frame that
    # does not pin itself to the top is centred here exactly as it is there.
    # Its rule is a class and a child, the same weight as the switcher's own
    # `.dr-stage > *`, and declared BEFORE the frame's stylesheet as that one is,
    # so the frame's pin wins or loses here exactly as it does there.
    # Errors the builder raises while it loads are collected by a script ahead
    # of it, so a builder that cannot run is told apart from one cut short.
    page = ("<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
            "<title>The framed harness</title>\n"
            "<style>body { margin: 0; padding: 24px; background: #F4F1EC; }\n"
            ".lift-host-stage { display: flex; box-sizing: border-box; width: %dpx; "
            "min-height: 1100px; padding: 24px; }\n"
            ".lift-host-stage > * { margin: auto; flex: none; }</style>\n" % (stage + 48) +
            "<style>\n" + styles + "\n</style>\n"
            "<script>window.LIFT_ERRORS = []; window.addEventListener(\"error\", "
            "function (e) { window.LIFT_ERRORS.push(String(e.message)); });</script>\n"
            "</head>\n<body>\n<div class=\"lift-host-stage\" id=\"lift-stage\"></div>\n"
            "<script id=\"lift-builder\">\n" + builder +
            "\n</script>\n</body>\n</html>\n")
    with open(into, "w", encoding="utf-8") as handle:
        handle.write(page)
    return into


def probe_frame(spec, variant, bare, reveal=False):
    """Put one option's box on the stage, wait until it has drawn or failed, and
    measure the window INSIDE the frame, in the page the frame was drawn in:
    its elements, its markup and style, where it lands in the clip and at what
    scale, independently of anything the frame's own code worked out, and the
    caption it wrote."""
    return """
<script>
(function () {
  %(measure)s
  var IGNORE = %(ignore)s;
  function finish(report) {
    var pre = document.createElement("pre");
    pre.id = "ovation-probe";
    pre.textContent = JSON.stringify(report);
    document.body.appendChild(pre);
  }
  try {
    /* CUT SHORT, THEN BROKEN, in that order. A closing tag in the embedded page
       ends the builder's script element before its last function, so the
       element's own text is missing the runtime; that is asked first, because
       the half page that spills out as markup raises errors of its own. A
       builder that is whole and raised an error as it loaded could not run,
       even when its functions exist: declarations are hoisted, so a throw at
       load leaves buildScreen defined over constants that were never set. */
    var whole = (document.getElementById("lift-builder").text || "")
      .indexOf("function buildScreen(") !== -1;
    if (!whole) { finish({ frame_fault: "unescaped" }); return; }
    if (window.LIFT_ERRORS.length
        || typeof liftFrame !== "function" || typeof buildScreen !== "function") {
      finish({ frame_fault: "unrunnable", said: window.LIFT_ERRORS.join("; ") });
      return;
    }
    ovationCheckSelectors(IGNORE);
    var stage = document.getElementById("lift-stage");
    var reveal = %(reveal)s;
    if (reveal) { stage.style.display = "none"; }
    var box = liftFrame(%(variant)s, %(bare)s);
    stage.appendChild(box);
    var began = Date.now();
    (function wait() {
      var state = box.getAttribute("data-state");
      if (reveal && box.getAttribute("data-settled") === "yes") {
        /* Shown only once it has loaded and settled hidden, as a switcher's
           hidden option is when its tab is pressed. */
        reveal = false;
        stage.style.display = "";
        setTimeout(wait, 150);
        return;
      }
      if (reveal || (state !== "failed" && (box.getAttribute("data-settled") !== "yes"
          || state === "waiting"))) {
        if (Date.now() - began > %(wait)d) {
          finish(state === "waiting"
            ? { frame_fault: "waiting", said: box.querySelector(".lift-frame-cap").textContent }
            : { error: "the frame had not drawn after %(wait)d ms" });
          return;
        }
        setTimeout(wait, 50);
        return;
      }
      try {
        var said = box.querySelector(".lift-frame-cap").textContent;
        if (state !== "drawn") { finish({ frame_fault: "failed", said: said }); return; }
        var frame = box.querySelector("iframe");
        var win = frame.contentDocument.querySelector(%(window)s);
        var w = win.getBoundingClientRect();
        var f = frame.getBoundingClientRect();
        var c = box.querySelector(".lift-frame-clip").getBoundingClientRect();
        var sr = stage.getBoundingClientRect(), scs = getComputedStyle(stage);
        var stageTop = sr.top + parseFloat(scs.paddingTop);
        var stageWidth = stage.clientWidth - parseFloat(scs.paddingLeft) - parseFloat(scs.paddingRight);
        var scale = f.width / frame.offsetWidth;
        var report = ovationMeasure(win, IGNORE);
        var look = ovationLook(win);
        report.markup = look.markup;
        report.styles = look.styles;
        report.caption = said;
        report.width = w.width;
        report.scale = scale;
        report.placed = {
          left: f.left + w.left * scale - c.left,
          top: f.top + w.top * scale - c.top,
          right: c.right - (f.left + w.right * scale),
          bottom: c.bottom - (f.top + w.bottom * scale),
          margin: LIFT_MARGIN * scale
        };
        var winTop = f.top + w.top * scale;
        report.above = winTop - stageTop;
        report.above_allowed = (c.top - stageTop) - (box.getBoundingClientRect().top - stageTop)
          + LIFT_MARGIN * scale;
        report.overflow = c.width - stageWidth;
        finish(report);
      } catch (e) { finish({ error: String((e && e.message) || e) }); }
    })();
  } catch (e) { finish({ error: String((e && e.message) || e) }); }
})();
</script>
""" % {"measure": MEASURE, "ignore": json.dumps(spec["ignore"]),
       "variant": json.dumps(variant), "bare": "true" if bare else "false",
       "window": json.dumps(spec["window"]), "wait": FRAME_WAIT_MS,
       "reveal": "true" if reveal else "false"}


def probe_frame_design(spec):
    """The window where the design file draws it, measured once its fonts are
    in, which is when the frame measures too."""
    return """
<script>
(function () {
  %(measure)s
  var IGNORE = %(ignore)s;
  function finish(report) {
    var pre = document.createElement("pre");
    pre.id = "ovation-probe";
    pre.textContent = JSON.stringify(report);
    document.body.appendChild(pre);
  }
  function measure() {
    try {
      ovationCheckSelectors(IGNORE);
      var here = document.querySelectorAll(%(window)s);
      if (here.length !== 1) {
        throw new Error(here.length + " element(s) match the window selector " + %(window)s
          + ", and exactly one has to.");
      }
      finish(ovationMeasure(here[0], IGNORE));
    } catch (e) { finish({ error: String((e && e.message) || e) }); }
  }
  if (document.fonts && document.fonts.ready) { document.fonts.ready.then(measure); }
  else { measure(); }
})();
</script>
""" % {"measure": MEASURE, "ignore": json.dumps(spec["ignore"]),
       "window": json.dumps(spec["window"])}


FRAME_WAIT_MS = 12000


def js_round(value):
    """Math.round, half up, the rounding the frame's caption uses."""
    return int(math.floor(value + 0.5))
CAPTION = re.compile(r"The window is (\d+) points wide, drawn here at (\d+)%\.")


def read_frame(session, page, probe, what):
    """One drawing of the frame, with its two refusals said in their own words
    before anything else reads the report."""
    report = session.render(page, probe, budget=FRAME_WAIT_MS + 3000)
    if isinstance(report, dict) and report.get("frame_fault") == "unescaped":
        raise Refusal(FRAME,
                      "the builder ended the script it is inlined in before it defined "
                      "buildScreen, so a switcher inlining it would draw an empty frame.",
                      "Its embedded page carries a closing tag the HTML parser reads as the "
                      "end of the script; every one has to be written <\\/ inside the string.")
    if isinstance(report, dict) and report.get("frame_fault") == "unrunnable":
        raise Refusal(FRAME,
                      "the builder could not run: %s. It is whole in the page, so this is "
                      "not the closing tag fault; it failed to parse or threw as it loaded."
                      % (report.get("said") or "no error was reported"))
    if isinstance(report, dict) and report.get("frame_fault") == "waiting":
        raise Refusal(FRAME,
                      "%s was never fitted once its stage had a width, and its caption "
                      "still says: %s" % (what, report.get("said", "nothing")),
                      "A frame has to be fitted again when the stage it is on changes "
                      "size, or an option drawn while hidden stays unmeasured when shown.")
    if isinstance(report, dict) and report.get("frame_fault") == "failed":
        raise Refusal(FRAME, "%s drew no window, and its caption says: %s"
                      % (what, report.get("said", "nothing")))
    if not isinstance(report, dict):
        raise Refusal(UNREADABLE, "%s's probe wrote something that is not a report" % what)
    if report.get("error") is not None:
        raise Refusal(UNREADABLE, "%s could not be read: %s" % (what, report["error"]),
                      "Nothing was compared.")
    if not isinstance(report.get("rows"), list) or not report["rows"]:
        raise Refusal(UNREADABLE, "%s's probe measured no elements at all" % what)
    # EVERY NUMBER A FAULT IS JUDGED BY MUST BE ONE. A value the page could not
    # compute arrives as null, and a comparison against it would either crash
    # or, worse, quietly pass (L50).
    numbers = [report.get(key) for key in ("width", "scale", "above", "above_allowed",
                                           "overflow")]
    numbers += list((report.get("placed") or {}).values()) or [None]
    if any(isinstance(n, bool) or not isinstance(n, (int, float)) for n in numbers):
        raise Refusal(UNREADABLE, "%s measured a place or a size that is not a number, so "
                                  "nothing about where it is drawn can be judged." % what)
    return report


def frame_faults(report, what):
    """What is wrong with one drawing, as sentences: where the window landed,
    and whether the caption states the numbers the drawing has."""
    faults = []
    if report["above"] > report["above_allowed"] + 4:
        faults.append("UNPINNED: %s leaves %d points of empty stage above the window, where "
                      "its caption and margin take %d, so the window sits down the page "
                      "rather than at the top of the stage."
                      % (what, js_round(report["above"]), js_round(report["above_allowed"])))
    if report["overflow"] > 1:
        faults.append("OVERFLOWS: %s is drawn %d points wider than the stage it is on, "
                      "which is a frame fitted to a stage it was not measured on."
                      % (what, js_round(report["overflow"])))
    placed = report["placed"]
    at = placed["margin"]
    if (abs(placed["left"] - at) > 1 or abs(placed["top"] - at) > 1
            or placed["right"] < -1 or placed["bottom"] < -1):
        faults.append("MISPLACED: %s shows something other than the window: the window "
                      "starts %d points right and %d points down in the clip, and runs %d "
                      "past its right edge and %d past its foot, where it should start at "
                      "the margin, %d, and run past neither."
                      % (what, round(placed["left"]), round(placed["top"]),
                         max(0, -round(placed["right"])), max(0, -round(placed["bottom"])),
                         round(at)))
    # THE CAPTION'S OWN ROUNDING, half up as a browser script rounds, never
    # Python's half to even, or a true caption of 641 for 640.5 reads as false.
    drawn = (js_round(report["width"]), js_round(report["scale"] * 100))
    said = CAPTION.search(report.get("caption") or "")
    stated = (int(said.group(1)), int(said.group(2))) if said else None
    if stated != drawn:
        faults.append("MISCAPTIONED: in %s the caption says %s, and the drawing is %d points "
                      "at %d%%. A caption stating a number the drawing does not have is the "
                      "readout disagreeing with the picture."
                      % (what, "%d points at %d%%" % stated if stated else "no measurement",
                         drawn[0], drawn[1]))
    return faults


def check_frame(spec, out_dir):
    styles_at = os.path.join(out_dir, STYLES)
    builder_at = os.path.join(out_dir, BUILDER)
    for path in (styles_at, builder_at):
        if not os.path.isfile(path):
            raise Refusal(USED_WRONGLY,
                          "there is no %s in %s, so there is no frame to judge."
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

    # THE PAGE IS A COPY OF THE DESIGN FILE, so it is removed on every way out,
    # a refusal included, rather than left in the temporary folder per run.
    holder = tempfile.mkdtemp(prefix="ovation-frame-")
    try:
        return judge_frame(spec, session, holder, styles_at, builder_at, name)
    finally:
        shutil.rmtree(holder, ignore_errors=True)


def judge_frame(spec, session, holder, styles_at, builder_at, name):
    page = compose_host(open(styles_at, encoding="utf-8").read(),
                        open(builder_at, encoding="utf-8").read(),
                        spec["stage"], os.path.join(holder, "frame.html"))
    try:
        with session:
            bare = read_frame(session, page, probe_frame(spec, {}, True), "the bare frame")
            shown = read_frame(session, page, probe_frame(spec, {}, True, reveal=True),
                               "the bare frame drawn on a hidden stage and then shown")
            design = read_report(session, spec["source_path"], probe_frame_design(spec), name)
            faithful = not differences(design["rows"], bare["rows"], spec["tolerance"])[0]
            drawings = [("the bare frame", bare),
                        ("the bare frame drawn on a hidden stage and then shown", shown)]
            moved = []
            if faithful:
                for move in spec["moves"]:
                    drawn = []
                    for index, value in enumerate(move["values"]):
                        what = "the frame with value %d of variant.%s" % (index + 1, move["field"])
                        report = read_frame(session, page,
                                            probe_frame(spec, {move["field"]: value}, False),
                                            what)
                        drawings.append((what, report))
                        drawn.append(json.dumps([report.get("markup"), report.get("styles"),
                                                 report["rows"]]))
                    twin = None
                    for later in range(len(drawn)):
                        for earlier in range(later):
                            if twin is None and drawn[earlier] == drawn[later]:
                                twin = (earlier + 1, later + 1)
                    moved.append((move, len(drawn)) + (twin or (None, None)))
    except CannotMeasure as err:
        raise Refusal(NO_BROWSER, str(err))

    unused = [s for s in spec["ignore"]
              if not design["ignored"].get(s) and not bare["ignored"].get(s)]
    if unused:
        raise Refusal(UNREADABLE,
                      "%d ignore selector(s) matched nothing in either rendering: %s."
                      % (len(unused), ", ".join(unused)),
                      "An exemption that matches nothing still reads as a deliberate "
                      "one, so this is refused rather than passed.")

    print("  design file  %s, its window is %s" % (name, spec["window"]))
    print("  frame        %s and %s, inlined in a page's script as the switcher inlines "
          "them, on a stage %d points wide" % (STYLES, BUILDER, spec["stage"]))
    print("  comparing    tag, classes and box, %d element(s) against %d, tolerance %dpx"
          % (len(design["rows"]), len(bare["rows"]), spec["tolerance"]))

    faults, stopped = differences(design["rows"], bare["rows"], spec["tolerance"])
    if faults:
        print("DIFFERS: the frame does not draw the window %s draws." % name)
        for kind, a, b in faults[:8]:
            print("  %s" % kind)
            print("    the design file  %s, %s" % (name_of(a), boxes_of(a)))
            print("    the frame        %s" % ("draws no element there at all" if b is None
                                               else "%s, %s" % (name_of(b), boxes_of(b))))
        return DIFFERS
    print("SAME: the frame draws the window %s draws, %d element(s), tag, classes and box."
          % (name, len(design["rows"])))

    wrong = [line for what, report in drawings for line in frame_faults(report, what)]
    if wrong:
        for line in wrong:
            print(line)
        return FRAME
    print("FRAMED: the caption says %d points at %d%%, and the drawing is %d points at %d%%, "
          "with the window at the clip's margin, in all %d drawing(s)."
          % (js_round(bare["width"]), js_round(bare["scale"] * 100),
             js_round(bare["width"]), js_round(bare["scale"] * 100), len(drawings)))
    return report_moves(moved)


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
        if "rule" in move:
            print("  moves        variant.%s through %s, %d declaration(s) in the stylesheet"
                  % (move["field"], custom_property(move), moved[move["field"]]))
        else:
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
    if spec["framing"]:
        return check_frame(spec, rest[1]) if checking else write_frame(spec, rest[1])
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
