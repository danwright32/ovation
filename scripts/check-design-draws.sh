#!/usr/bin/env python3
"""Refuse a design file that DRAWS badly, at every width it has to survive.

    check-design-draws.sh [design file ...]

ovation#141. The design record was checked for source properties and no
rendered ones: one check asserts a file reaches outside itself never, one
asserts its copy of each rule matches `rules/`, one runs 150 executable cases
about durations and money. Every one of them reads TEXT. So the class of fault a
design record exists to catch was the class nothing could see, and on 2026-09-08
alone five were found by a person looking:

  * the screen deleted its own right hand side. At a 1100px window the stage
    squeezed the 1120px screen to 1002, the 1064px window overflowed by 62px,
    `overflow: hidden` cut those off, and the page reported no horizontal
    scroll. Found because Dan could not see the history pane in a round about
    the history pane.
  * an elapsed time under an hour read `0h 40m`. No fixture had ever been under
    an hour.
  * a history entry wrapped to three lines at the pane width of the day.
  * the discount's figure landed 24px off the shared right edge, twice.
  * a sidebar rendered fully transparent.

`check-invoice-screen-draws.sh` came out of the same week and is the other half:
it DRIVES one file the way a person does, pressing what is on it, and its claims
are about that screen. This one asserts what is true of EVERY design file, at
more than one window width, and it is the widths that matter: a list judged at
one size is half judged, and the record's own rule asks for production scale and
a laptop window.

PROPERTIES, NEVER SNAPSHOTS. A recorded image defends whatever it recorded,
including a broken state caused by a dependency the harness never fed it (L84).

WHAT IT ASSERTS, and each was seen to fail on a planted defect before it was
believed (L1):

  1. THE CONSOLE IS SILENT. A page that threw on the way up renders as a blank
     white sheet that reads as a layout problem, with the real cause in a place
     nothing here was looking (L219). The catcher is installed BEFORE the page's
     own scripts, because a probe appended to the file is not running yet when
     the page throws.
  2. THE PAGE DREW SOMETHING. A file that produced almost no elements is a
     failure to render, and without this every other claim below passes
     vacuously over an empty page (L98).
  3. NOTHING IS CLIPPED UNREACHABLY. For every element that hides its overflow,
     its content must fit, or the page itself must scroll far enough to reach
     what is past the edge. This is fault one above, exactly.
  4. THE PAGE DOES NOT SCROLL SIDEWAYS. A design record is read by scrolling
     down; content off the right hand edge with nothing at rest saying it
     continues is the fault L76 names.
  5. EVERY FIGURE IN ONE MONEY BLOCK SHARES ONE RIGHT EDGE. The record has
     already had to fix this twice, and it is checked wherever a file draws more
     than one `.fig` inside one block rather than being asserted about a
     particular screen.
  6. THE PAGE RENDERS IN STANDARDS MODE. A file with no doctype is rendered in
     quirks mode, which lays out a line box by different rules, so a record whose
     files disagree about the mode cannot be compared with itself. The MODE is
     asserted rather than the declaration, because a file can carry the string
     and still land in quirks.
  7. NO INVOICE IS DRAWN TWICE IN ONE LIST. A group that copies its rows rather
     than moving them draws each of them twice, every row reads as correct on
     its own, and the fault exists only in the list as a whole. Numbered rows
     only, since `draft` is legitimately repeated.
  8. DELIBERATELY ABSENT, and recorded rather than left to be rediscovered. A
     claim that the app window is drawn at its DECLARED width cannot be written
     from a rendering: `getComputedStyle(el).width` returns the USED width, so a
     window squeezed by its stage reports the squeezed number as its
     declaration, the two always agree, and the claim can never fail. A check
     that has never once been able to fail is not measuring anything (L557,
     L1). The fault it was aimed at, the 1120px screen squeezed to 1002 inside a
     1100px window, is claim 3: the content went off the edge and `overflow:
     hidden` cut it off.

IT REFUSES TO GUESS WHEN IT CANNOT MEASURE. With no headless browser it exits 3
and says so, rather than exiting 0, because "every claim held" and "nothing was
checked" must never be the same answer (L98).

Exit codes: 0 every claim held, 1 a claim failed, 2 used wrongly, 3 cannot
measure.

Seams: OVATION_DESIGN_ROOT, OVATION_HEADLESS_BROWSER, and
OVATION_DESIGN_WIDTHS, a comma separated list of window widths.
"""
import glob
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_render import CannotMeasure, NO_BROWSER, find_browser, render  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs/design")

# THE WIDTHS ARE STATED, and both of them are a real machine rather than a round
# number: 1440 is the window these files were designed in, and 1280 is the
# narrowest laptop Dan opens them on. A single width is what let the invoice list
# ship cutting off its own side.
DEFAULT_WIDTHS = "1440,1280"

# The page must produce at least this many elements to be judged at all. It is a
# floor on "did anything render", not a measure of the design: the smallest of
# these files draws over a hundred.
DREW_SOMETHING = 40

PREAMBLE = r"""
<script>
/* Installed BEFORE the page's own scripts, which is the only place an error
   thrown during load can be caught. */
window.__ovationConsole = [];
window.addEventListener("error", function (e) {
  window.__ovationConsole.push("error: " + (e.message || "an error with no message"));
});
window.addEventListener("unhandledrejection", function (e) {
  window.__ovationConsole.push("unhandled rejection");
});
["error", "warn"].forEach(function (level) {
  var was = console[level];
  console[level] = function () {
    window.__ovationConsole.push(level + ": " + Array.prototype.join.call(arguments, " "));
    return was.apply(console, arguments);
  };
});
</script>
"""

PROBE = r"""
<script>
window.addEventListener("load", function () {
  var result = { claims: {} };
  function claim(name, ok, saw) { result.claims[name] = { ok: !!ok, saw: saw }; }
  function box(e) { return e.getBoundingClientRect(); }

  try {
    /* 1. THE CONSOLE IS SILENT. */
    var said = (window.__ovationConsole || []).map(function (m) {
      /* A CONSOLE MESSAGE IS THE ONLY THING HERE THAT CAN CARRY PAGE CONTENT,
         since every other `saw` string is a class name, a tag or a pixel count.
         It is capped so a page that logged a record cannot empty it into a
         terminal, and it is a diagnosis rather than a dump: what is wanted is
         the type of the error and where it came from
         (docs/PRIVACY-FLOOR.md, L222). */
      return String(m).slice(0, 120);
    });
    window.__ovationSaid = said;
    claim("the console said nothing", said.length === 0,
          said.length ? said.slice(0, 3).join(" // ") : "nothing was logged");

    /* 2. THE PAGE DREW SOMETHING. */
    var all = document.querySelectorAll("body *");
    claim("the page drew something", all.length >= window.__ovationFloor,
          all.length + " element(s), floor is " + window.__ovationFloor);

    /* 3. NOTHING IS CLIPPED UNREACHABLY.

       MEASURED IN RECTS, NOT IN scrollWidth, and the difference decides whether
       this claim is worth anything. `scrollWidth` is the untransformed layout
       width, so the review screen's preview, which is the 816px invoice page
       drawn at 47%, reported 438px of hidden content while every pixel of it is
       on screen. A bounding rect accounts for the transform, so it measures
       what a person can actually see.

       AGAINST THE NEAREST CLIPPING ANCESTOR, and only that one. Content an
       inner container has already cut off cannot escape to be cut again by an
       outer one, so judging every element against every clipping ancestor above
       it reports the same pixel several times and, worse, reports it against a
       box it was never laid out in: the invoice screen's history pane parks
       itself flush with the window's right edge, which is 28px inside the
       stage, so the outer box turned a correctly parked pane into a 272px
       fault.

       PARKED OFF TO THE SIDE IS NOT CUT OFF either. Something that starts at or
       past its container's right edge is entirely outside it, which is how that
       pane waits until it is opened. The fault this claim is for is the PARTIAL
       one: content that starts inside and ends outside, so a person sees most
       of it and cannot reach the rest. That is exactly what happened at a
       1100px window, where the 1064px window overflowed by 62px and the page
       reported no horizontal scroll.

       AN ELLIPSIS IS NOT CLIPPING. A cell that truncates its text draws the
       ellipsis, which is a visible mark saying the content continues, and it is
       what the design chose. Rects exclude it for free: the text is a text
       node, so no child ELEMENT sticks out of the parent that hides it.

       A CONTAINER THAT SCROLLS ITSELF is not one of these: `clipper` stops at
       the first `auto` or `scroll` ancestor and answers that nothing clips,
       because the content is reachable. An earlier version instead let a HIDDEN
       container off whenever its scrollWidth exceeded its clientWidth, which is
       the definition of the fault: it exempted every single case this claim
       exists for, and the planted defect that should have caught it passed. */
    function clipper(node) {
      for (var p = node.parentElement; p; p = p.parentElement) {
        var cs = getComputedStyle(p);
        if (cs.overflowX === "hidden" || cs.overflowX === "clip") return p;
        if (cs.overflowX === "auto" || cs.overflowX === "scroll") return null;
      }
      return null;
    }
    var clipped = [];
    Array.prototype.forEach.call(all, function (kid) {
      var k = box(kid);
      if (k.width === 0 && k.height === 0) return;
      var e = clipper(kid);
      if (!e) return;
      var mine = box(e);
      if (k.left >= mine.right - 1) return;
      var over = Math.round(k.right - mine.right);
      if (over > 1) {
        clipped.push((e.className || e.tagName) + " cuts " + over + "px off "
                     + (kid.className || kid.tagName));
      }
    });
    claim("nothing hides content there is no way to reach", clipped.length === 0,
          clipped.length ? clipped.slice(0, 4).join(" // ") : "no clipped element");

    /* 4. THE PAGE DOES NOT SCROLL SIDEWAYS. */
    var doc = document.documentElement;
    claim("the page does not scroll sideways",
          doc.scrollWidth <= doc.clientWidth + 1,
          doc.scrollWidth + "px of content in a " + doc.clientWidth + "px page");

    /* 5. EVERY FIGURE IN ONE MARKED BLOCK SHARES ONE RIGHT EDGE.

       THE BLOCK IS MARKED, not guessed. A harness that walked up to the nearest
       ancestor holding two figures grouped three separate blocks of the invoice
       screen into one and reported three right edges as a fault, which is the
       check being wrong rather than the screen. So a file that wants this says
       so: `data-one-edge` on the container whose figures must line up, holding
       the selector for the figures themselves, or empty for `.fig`. The two
       files that draw money name different classes for the same thing, so a
       harness that knew only one of them would be silently checking one file.

       THE COUNT IS PRINTED even when it holds, because a file that stopped
       marking anything would otherwise report exactly what a file whose figures
       all line up reports (L98). */
    var blocks = document.querySelectorAll("[data-one-edge]");
    var offenders = [], groups = 0;
    Array.prototype.forEach.call(blocks, function (owner) {
      var figs = owner.querySelectorAll(owner.getAttribute("data-one-edge") || ".fig");
      if (figs.length < 2) return;
      groups++;
      /* WITHIN A PIXEL, not identical. The same page rendered on macOS and on
         Linux rounds a right edge differently by a fraction, and this check
         runs on both (ovation#160); a fraction is not a misalignment anybody
         can see. The faults this claim is for were 24px. */
      var uniq = {}, lo = Infinity, hi = -Infinity;
      Array.prototype.forEach.call(figs, function (f) {
        var r = Math.round(box(f).right);
        uniq[r] = 1;
        if (r < lo) lo = r;
        if (r > hi) hi = r;
      });
      var edges = Object.keys(uniq);
      if (hi - lo > 1) {
        offenders.push((owner.className || owner.tagName) + ": "
                       + edges.join(", "));
      }
    });
    result.edgeGroups = groups;
    claim("every figure in a block that says its figures line up does",
          offenders.length === 0,
          offenders.length ? offenders.join(" // ")
                           : groups + " marked block(s) of figures");

    /* 9. THE PAGE RENDERS IN STANDARDS MODE (ovation#194).

       A file with no doctype is rendered in QUIRKS mode by every browser, and
       three of the five design files had none until 2026-09-10 while two had
       one. The two modes lay out a line box by different rules: in the invoice
       screen's history pane the same markup, the same stylesheet and every
       computed property identical measured 37.95px in one mode and 41.06px in
       the other. Nothing here could see it, and any check that renders a file
       and compares it against anything else was measuring the mode as well as
       the design.

       IT ASSERTS THE MODE, NOT THE TEXT. A file can carry the declaration and
       still land in quirks mode, so what is read back is what the browser
       actually did (L63). */
    claim("the page renders in standards mode",
          document.compatMode === "CSS1Compat",
          document.compatMode + (document.compatMode === "BackCompat"
            ? ", which is quirks mode: this file declares no doctype" : ""));

    /* 8. NO INVOICE IS DRAWN TWICE IN ONE LIST (ovation#190).

       A group that COPIES its rows rather than moving them draws each of them
       twice. Every row still reads as correct on its own, every rule about rows
       still holds, and the fault exists only in the list as a whole, which is
       the one place nobody reads (L605). It reached Dan in a design round on
       2026-09-10, two invoices drawn twice under a header saying 2, and nothing
       here could see it.

       ONLY A NUMBERED ROW COUNTS. `draft` is what an unissued invoice draws in
       that column and there are legitimately many of them; the claim is about
       an invoice NUMBER, which is unique by construction (PRD 5.19).

       IT RUNS BEFORE ANY CONTROL IS PRESSED, because pressing legitimately
       changes what a list holds. And it reports how many numbered rows it
       found, so a file with no list at all says so rather than reading like a
       list that passed (L98). */
    var seenNumbers = {}, drawnTwice = [];
    Array.prototype.forEach.call(document.querySelectorAll(".scroll .row .num"),
      function (cell) {
        var value = (cell.textContent || "").trim();
        if (!/^[0-9]+$/.test(value)) return;
        if (seenNumbers[value] && drawnTwice.indexOf(value) === -1) drawnTwice.push(value);
        seenNumbers[value] = 1;
      });
    claim("no invoice is drawn twice in one list", drawnTwice.length === 0,
          drawnTwice.length ? "drawn twice: " + drawnTwice.join(", ")
                            : Object.keys(seenNumbers).length + " numbered row(s), each once");

    /* 7. AND IT STAYS SILENT WHEN THE PAGE IS DRIVEN.

       A design file shows one state at rest and carries several: the invoice
       PDF holds six fixtures behind six buttons, and the fixture a page happens
       to open on is the only one every check has ever seen. That is how
       ovation#170 survived: `invoice-pdf.html` threw on any line carrying an
       explicitly empty hours value, the page rendered as a blank white sheet,
       and the only fixture with such a line was three buttons away.

       SO EVERY CONTROL IS PRESSED, in one render, and the console is read
       again. The console only, deliberately: pressing a control legitimately
       opens menus and panels that sit outside their container, so re-checking
       the layout here would refuse a screen for doing what it is for. What
       cannot be legitimate is throwing.

       THE COUNT IS REPORTED, because a page whose controls stopped being
       buttons would otherwise report exactly what a page that survived every
       press reports (L98). */
    var controls = document.querySelectorAll(
      'button, [role="button"], summary, input[type="checkbox"], input[type="radio"]');
    var pressed = 0;
    Array.prototype.forEach.call(controls, function (c) {
      try { c.click(); pressed++; } catch (e) {
        window.__ovationConsole.push("pressing a control threw: " + e);
      }
    });
    result.pressed = pressed;
    var after = (window.__ovationConsole || []).map(function (m) {
      return String(m).slice(0, 120);
    });
    claim("the console is still silent after every control has been pressed",
          after.length === 0,
          after.length ? after.slice(0, 3).join(" // ")
                       : pressed + " control(s) pressed, nothing logged");
  } catch (err) {
    result.threw = String(err);
  }

  var pre = document.createElement("pre");
  pre.id = "ovation-probe";
  pre.textContent = JSON.stringify(result);
  document.body.appendChild(pre);
});
</script>
"""


def widths():
    said = os.environ.get("OVATION_DESIGN_WIDTHS") or DEFAULT_WIDTHS
    out = []
    for piece in said.split(","):
        piece = piece.strip()
        if not piece:
            continue
        try:
            out.append(int(piece))
        except ValueError:
            return None
    return out or None


def main(argv):
    files = argv[1:]
    if not files:
        files = sorted(glob.glob(os.path.join(DEFAULT_ROOT, "*.html")))
        if not files:
            print("CANNOT MEASURE: no design file under %s, so nothing was "
                  "rendered and a pass here would be a green tick over an "
                  "unrun check." % DEFAULT_ROOT)
            return 2
    for path in files:
        if not os.path.isfile(path):
            print("CANNOT MEASURE: no such design file: %s" % path)
            return 2

    at = widths()
    if at is None:
        print("USED WRONGLY: OVATION_DESIGN_WIDTHS must be a comma separated "
              "list of window widths in pixels.")
        return 2

    try:
        browser = find_browser()
    except CannotMeasure as err:
        print("CANNOT MEASURE: %s" % err)
        return 3
    if not browser:
        print(NO_BROWSER)
        return 3

    floor = int(os.environ.get("OVATION_DESIGN_DREW_FLOOR") or DREW_SOMETHING)
    prologue = "<script>window.__ovationFloor = %d;</script>" % floor
    held = failed = edge_groups = pressed = 0
    for path in files:
        name = os.path.basename(path)
        for width in at:
            try:
                report = render(browser, path, PROBE,
                                window="%d,1200" % width,
                                preamble=PREAMBLE + prologue)
            except CannotMeasure as err:
                print("CANNOT MEASURE: %s at %dpx: %s" % (name, width, err))
                return 3
            if report.get("threw"):
                print("  FAIL %s at %dpx: the probe itself threw: %s"
                      % (name, width, report["threw"]))
                failed += 1
                continue
            edge_groups += report.get("edgeGroups") or 0
            pressed += report.get("pressed") or 0
            claims = report.get("claims") or {}
            if not claims:
                print("CANNOT MEASURE: %s at %dpx reported no claim at all, "
                      "which is not a pass." % (name, width))
                return 3
            for label in sorted(claims):
                answer = claims[label]
                if answer["ok"]:
                    held += 1
                else:
                    failed += 1
                    print("  FAIL %s at %dpx: %s: %s"
                          % (name, width, label, answer["saw"]))

    if not held and not failed:
        print("CANNOT MEASURE: nothing was claimed about any file, so this "
              "compared nothing.")
        return 3
    if failed:
        print("REFUSED: %d of %d claim(s) about what these files DRAW did not "
              "hold, across %d file(s) at %s."
              % (failed, held + failed, len(files),
                 " and ".join("%dpx" % w for w in at)))
        return 1
    # THE EDGE CLAIM SAYS HOW MUCH IT JUDGED, because it is the one claim here
    # that only applies where a file asks for it, and a record that stopped
    # marking its money blocks would otherwise report exactly what a record
    # whose figures all line up reports (L98, L543).
    print("OK: all %d claim(s) about what %d design file(s) draw held, at %s. "
          "%d marked block(s) of figures were judged and %d control(s) pressed "
          "across those renders."
          % (held, len(files), " and ".join("%dpx" % w for w in at),
             edge_groups, pressed))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
