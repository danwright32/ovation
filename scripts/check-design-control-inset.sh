#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a design file whose control does not keep its container's inset.

    check-design-control-inset.sh [design file ...]

ovation#625. Dan, 2026-09-29, on the ovation#489 round: the chosen type's
chooser sat against the left edge of its table cell, its rounded border
touching the column's edge. He made it a standing rule rather than a one off
fix: A CONTROL INSIDE A TABLE CELL OR PANEL KEEPS THE SAME INSET FROM THE
CONTAINER'S EDGE AS THE OTHER CONTROLS THERE. docs/design/README.md records it
and PRD 48c states it for the app.

AN INSET CANNOT BE READ FROM A STYLESHEET. It is the container's padding, the
control's margin, the control's own padding when it draws no box, and whether a
tint reaches past the columns, and the fault Dan saw was a row that gave its
controls 8px above and below and none at the sides. Only a rendering has it, so
this renders every design file and measures.

WHAT IS MEASURED, and each part was chosen against a case the committed record
already draws:

  * THE EDGE IS ONE ANYBODY CAN SEE. A container's side is an edge when the
    container paints a surface there, a background that differs from what is
    behind it, a shadow, or a border on that side. A column edge nothing paints
    is not seen, and a field drawing only a rule beneath it has no left edge, so
    a control is measured from the nearest ancestor whose side IS painted. That
    is the row Dan's chooser sat in: its tint was the edge.
  * THE CONTROL IS WHAT IS SEEN OF IT. One that paints a box, and every text
    field, is measured by its box; a borderless word is measured by its words,
    because its padding is invisible. A shaded row that fills its whole list is
    a list row rather than a control against an edge, so it is measured by its
    label, which is what keeps the inset its neighbours' labels keep.
  * A CONTROL IS COMPARED ONLY ON A SIDE IT IS PUSHED AGAINST. At every level
    from the control up to the container, its margin edge has to meet its
    parent's content edge, so that what lies between it and the edge is
    padding, border and margin, which is what an inset is made of. Any gap is
    something else: the due date in `Dated 29 Aug, due 12 Sep` has words
    between it and the foot's left edge, and a value followed by an empty
    stretch of row has free space an alignment left. Neither distance is an
    inset anybody chose. A side along which a container scrolls is not counted
    at all, because where the control sits then depends on the scroll.

WHAT IS REFUSED:

  1. A CONTROL AT ZERO, on any side it is against: touching the edge, or past it.
  2. CONTROLS IN ONE CONTAINER AT DIFFERENT INSETS, compared across the SIDES:
     each control is compared on every side, left or right, it is pushed
     against, and every such inset measured from one container must agree
     within 1px, so a foot whose Cancel sits 24px in and whose Send sits 20px
     in is refused although each is alone on its side. Top and bottom are held to the first rule only, because in a
     row of controls of different heights the vertical inset is set by the
     alignment, and comparing it would refuse every baseline aligned foot.

AT BOTH WIDTHS THE APP IS USED AT: in a 1440px page, where the window is drawn
at its declared width, and again with the window at the app's own minimum, read
from Ovation/App/OvationWindow.swift through lib/design_render.py exactly as
check-design-draws.sh reads it, because that is the half screen Dan works at and
a control squeezed to its edge only there would pass the first.

IN EVERY STATE ONE PRESS REACHES, since the fault lived in a row that exists
only after `Add a line`: the page at rest, and then each control pressed from
rest in a page of its own, as scripts/check-design-draws.sh presses them and
with the same list, so no measurement depends on what another pressed. A state
two presses deep is not reached here; docs/design/README.md's `Drawn:` claims
reach those, and are judged by check-design-decisions-drawn.sh.

ONLY THE APP'S SCREEN IS MEASURED, everything inside `.screen` except its menu
bar. The switches above a design file's window are the record's, not the
app's, and the menu bar is the system's, drawn at the system's insets. A file
drawing no screen, the invoice PDF, is counted and said.

A KNOWN DIFFERENCE CAN BE EXEMPTED, and only by naming the issue that ends it.
scripts/design-inset-exemptions.tsv holds one line per control, five tab
separated columns: the design file, the container and the control each as
`tag.class.class`, the issue, and the reason. An exempt control is left out of
its container's comparison and nothing else: a control at zero is the fault
itself and no line excuses it. A line naming no issue or no reason is refused
(L65, L233), and so is a line that covered nothing in a file this run measured,
because an exemption that outlives its fix reads as a decision for ever (L346).

IT NEVER QUOTES THE PAGE. A control's words on the Clients screen are a
client's name, so controls are named by their classes and their place in the
page, and states by the number of the control pressed (docs/PRIVACY-FLOOR.md).

Exit codes, one per outcome (L11):

    0  every control measured keeps its container's inset
    1  one does not, or an exemption is wrong
    2  nothing could be measured, which is not a pass, or no minimum window
       could be read
    3  no browser, so nothing could be rendered at all

Seams, shared with the other design checks where they exist:

    OVATION_DESIGN_ROOT       the design record to read
    OVATION_HEADLESS_BROWSER  the browser to render in
    OVATION_INSET_EXEMPTIONS  the exemptions file
    OVATION_WINDOW_SOURCE     the Swift file the minimum window width is read from
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_inline import html_files  # noqa: E402
from design_render import (CannotMeasure, NoMinimumWindow, PRESS_THEN_REPORT,  # noqa: E402
                           minimum_window, open_browser, press_only)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")
EXEMPTIONS = (os.environ.get("OVATION_INSET_EXEMPTIONS")
              or os.path.join(REPO, "scripts", "design-inset-exemptions.tsv"))

WINDOW = "1440,1200"
# Two insets closer than this are one inset. A word's box is measured to a
# fraction of a pixel and two faces round differently, so an exact comparison
# would refuse what nobody can see; the differences this exists for are 4px
# and more.
TOLERANCE = 1.0
# At or below this a control is at the edge.
AT_EDGE = 0.5

# What is MEASURED: every control, text fields included, since a field can sit
# against an edge as much as a button can.
MEASURED = 'button, [role="button"], summary, input, select, textarea'

PROBE = r"""
<script>
__PRESS_THEN_REPORT__
window.addEventListener("load", function () {
  var MEASURED = '__MEASURED__';
  var SIDES = ["Left", "Right", "Top", "Bottom"];
  var result = { controls: [], holders: {}, pressed: null };
  function rgba(s) {
    var m = String(s).match(/[\d.]+/g);
    if (!m || m.length < 3) return [0, 0, 0, 0];
    return [+m[0], +m[1], +m[2], m.length > 3 ? +m[3] : 1];
  }
  function same(a, b) {
    return Math.abs(a[0] - b[0]) < 1 && Math.abs(a[1] - b[1]) < 1 &&
           Math.abs(a[2] - b[2]) < 1 && Math.abs(a[3] - b[3]) < 0.01;
  }
  function behind(e) {
    for (var p = e; p; p = p.parentElement) {
      var c = rgba(getComputedStyle(p).backgroundColor);
      if (c[3] > 0) return c;
    }
    return [255, 255, 255, 1];
  }
  /* A SURFACE is a background unlike what is behind it, or a shadow: every side
     of it is an edge. A border is an edge on its own side only. */
  function surface(e) {
    var s = getComputedStyle(e), c = rgba(s.backgroundColor);
    return (c[3] > 0 && !same(c, e.parentElement ? behind(e.parentElement) : [255, 255, 255, 1])) ||
           (s.boxShadow && s.boxShadow !== "none");
  }
  function edge(e, side) {
    if (surface(e)) return true;
    var s = getComputedStyle(e);
    return parseFloat(s["border" + side + "Width"]) > 0 && s["border" + side + "Style"] !== "none" &&
           rgba(s["border" + side + "Color"])[3] > 0;
  }
  function paints(e) { return SIDES.some(function (k) { return edge(e, k); }); }
  function shown(e) {
    var r = e.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    for (var p = e; p; p = p.parentElement) {
      var s = getComputedStyle(p);
      if (s.visibility === "hidden" || s.display === "none" || parseFloat(s.opacity) === 0) return false;
    }
    return true;
  }
  function words(root) {
    var out = [], walk = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), n;
    while ((n = walk.nextNode())) {
      if (!n.textContent.trim() || !shown(n.parentElement)) continue;
      var range = document.createRange();
      range.selectNodeContents(n);
      [].forEach.call(range.getClientRects(), function (r) { if (r.width > 0 && r.height > 0) out.push(r); });
    }
    return out;
  }
  function union(rects) {
    if (!rects.length) return null;
    var u = { left: 1e9, top: 1e9, right: -1e9, bottom: -1e9 };
    rects.forEach(function (r) {
      u.left = Math.min(u.left, r.left); u.top = Math.min(u.top, r.top);
      u.right = Math.max(u.right, r.right); u.bottom = Math.max(u.bottom, r.bottom);
    });
    return u;
  }
  function drawnThings(root) {
    var rects = words(root);
    [].forEach.call(root.querySelectorAll("*"), function (k) {
      if (shown(k) && (paints(k) || /^(IMG|SVG|CANVAS|IFRAME)$/i.test(k.tagName))) rects.push(k.getBoundingClientRect());
    });
    return rects;
  }
  function holder(c, side) {
    for (var p = c.parentElement; p && p !== document.body; p = p.parentElement) {
      if (edge(p, side)) return p;
    }
    return null;
  }
  function inner(p, side) {
    var r = p.getBoundingClientRect(), b = parseFloat(getComputedStyle(p)["border" + side + "Width"]) || 0;
    return side === "Left" ? r.left + b : side === "Right" ? r.right - b : side === "Top" ? r.top + b : r.bottom - b;
  }
  function contentEdge(e, side) {
    var r = e.getBoundingClientRect(), s = getComputedStyle(e);
    var inward = (parseFloat(s["border" + side + "Width"]) || 0) + (parseFloat(s["padding" + side]) || 0);
    return side === "Left" ? r.left + inward : side === "Right" ? r.right - inward :
           side === "Top" ? r.top + inward : r.bottom - inward;
  }
  function marginEdge(e, side) {
    var r = e.getBoundingClientRect(), m = parseFloat(getComputedStyle(e)["margin" + side]) || 0;
    return side === "Left" ? r.left - m : side === "Right" ? r.right + m :
           side === "Top" ? r.top - m : r.bottom + m;
  }
  /* PUSHED TO THAT SIDE, rather than merely having nothing beside it. At every
     level from the control up to the container, the element's margin edge meets
     its parent's content edge: what lies between the control and the edge is
     then paddings, borders and margins, which are what an inset is made of. Any
     gap is free space an alignment left, a value followed by an empty stretch of
     row, and that distance is not an inset anybody chose. A control measured by
     its words is also asked whether the words meet its own content edge. */
  function outward(side, near, far) {
    return side === "Left" || side === "Top" ? near - far : far - near;
  }
  function pushed(c, p, side, seen, byWords) {
    if (byWords) {
      var at = side === "Left" ? seen.left : side === "Right" ? seen.right : side === "Top" ? seen.top : seen.bottom;
      if (outward(side, at, contentEdge(c, side)) > 1) return false;
    }
    for (var e = c; e && e !== p; e = e.parentElement) {
      var parent = e.parentElement;
      if (!parent) return false;
      if (outward(side, marginEdge(e, side), contentEdge(parent, side)) > 1) return false;
    }
    return true;
  }
  function scrolls(c, p, axis) {
    for (var q = c.parentElement; q; q = q.parentElement) {
      var s = getComputedStyle(q), o = axis === "x" ? s.overflowX : s.overflowY;
      if ((o === "auto" || o === "scroll") &&
          (axis === "x" ? q.scrollWidth > q.clientWidth + 1 : q.scrollHeight > q.clientHeight + 1)) return true;
      if (q === p) break;
    }
    return false;
  }
  function describe(e) {
    var classes = typeof e.className === "string" ? e.className.trim() : "";
    return e.tagName.toLowerCase() + (classes ? "." + classes.split(/\s+/).join(".") : "");
  }
  var ids = new Map();
  function idOf(p) {
    if (!ids.has(p)) { ids.set(p, ids.size + 1); result.holders[ids.get(p)] = describe(p); }
    return ids.get(p);
  }
  function measure() {
    var scope = document.querySelector(".screen");
    result.windowed = !!document.querySelector(".win");
    if (!scope) { result.noscreen = true; return; }
    var all = [].slice.call(scope.querySelectorAll(MEASURED));
    all.forEach(function (c, place) {
      if (c.closest(".menubar") || !shown(c)) return;
      var hold = {};
      SIDES.forEach(function (k) { hold[k] = holder(c, k); });
      var field = /^(INPUT|SELECT|TEXTAREA)$/.test(c.tagName);
      var byWords = !(paints(c) || field);
      var seen = byWords ? union(drawnThings(c)) : c.getBoundingClientRect();
      if (!seen) return;
      var row = false;
      if (!byWords && !field && hold.Left && hold.Right &&
          seen.left - inner(hold.Left, "Left") <= 0.5 && inner(hold.Right, "Right") - seen.right <= 0.5) {
        row = true;
        var label = union(words(c));
        if (label) { seen = label; byWords = true; }
      }
      var sides = {};
      SIDES.forEach(function (k) {
        var p = hold[k];
        if (!p) return;
        if (scrolls(c, p, k === "Left" || k === "Right" ? "x" : "y")) return;
        var e = inner(p, k);
        var d = k === "Left" ? seen.left - e : k === "Right" ? e - seen.right : k === "Top" ? seen.top - e : e - seen.bottom;
        sides[k] = { inset: Math.round(d * 10) / 10, holder: idOf(p), pushed: pushed(c, p, k, seen, byWords) };
      });
      result.controls.push({ control: describe(c), place: place + 1, row: row, sides: sides });
    });
  }
  ovationPressThenReport(result, measure);
});
</script>
""".replace("__MEASURED__", MEASURED).replace("__PRESS_THEN_REPORT__", PRESS_THEN_REPORT)


def read_exemptions(path, faults):
    """The exemption lines, each a dict, and a fault for each line that is wrong."""
    rows = []
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except FileNotFoundError:
        return rows
    except OSError as why:
        faults.append("the exemptions file %s could not be read: %s" % (path, why.strerror or why))
        return rows
    for number, raw in enumerate(lines, 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        cells = raw.split("\t")
        cells += [""] * (5 - len(cells))
        name, holder, control, issue, reason = (cell.strip() for cell in cells[:5])
        if not (name and holder and control):
            faults.append("exemptions line %d does not name a file, a container and a control" % number)
            continue
        if not issue.startswith("ovation#") or not issue[len("ovation#"):].isdigit():
            faults.append("exemptions line %d names no issue that ends it, and an exemption "
                          "with no issue is never ended (L65)" % number)
            continue
        if not reason:
            faults.append("exemptions line %d gives no reason (L233)" % number)
            continue
        rows.append({"line": number, "file": name, "holder": holder, "control": control,
                     "issue": issue, "used": False})
    return rows


def judge_state(name, state, report, exemptions, found):
    """Record every control at zero and every container whose controls differ.

    `found` maps each fault, worded WITHOUT the state it was seen in, to the
    states it was seen in: the rail is chrome and is drawn in every state, so a
    fault in it would otherwise be said once per press. A control is named by
    its classes and the side measured, never by its place in the page, which
    moves from one state to the next."""
    holders = report.get("holders") or {}
    groups = {}
    for entry in report.get("controls") or []:
        sides = entry.get("sides") or {}
        for side in ("Left", "Right", "Top", "Bottom"):
            measured = sides.get(side)
            if measured and measured["inset"] <= AT_EDGE:
                said = ("%s: %s sits %gpx from the %s edge of %s, and a control keeps an inset "
                        "from its container's edge"
                        % (name, entry["control"], max(measured["inset"], 0), side.lower(),
                           holders.get(str(measured["holder"]), "its container")))
                found.setdefault(said, []).append(state)
        for side in ("Left", "Right"):
            measured = sides.get(side)
            if not measured or not measured.get("pushed"):
                continue
            groups.setdefault(measured["holder"], []).append(
                (entry["control"], "%s's %s at %gpx" % (entry["control"], side.lower(),
                                                        measured["inset"]), measured["inset"]))
    for holder, members in sorted(groups.items()):
        container = holders.get(str(holder), "a container")
        insets = [inset for _, _, inset in members]
        if max(insets) - min(insets) <= TOLERANCE:
            continue
        kept = []
        for control, label, inset in members:
            covering = [row for row in exemptions if row["file"] == name
                        and row["holder"] == container and row["control"] == control]
            for row in covering:
                row["used"] = True
            if not covering:
                kept.append((label, inset))
        if kept and max(i for _, i in kept) - min(i for _, i in kept) > TOLERANCE:
            said = ("%s: the controls in %s sit at different insets from its edges, %s"
                    % (name, container, ", ".join(label for label, _ in sorted(set(kept)))))
            found.setdefault(said, []).append(state)


def main():
    try:
        session = open_browser()
    except CannotMeasure as why:
        print("CANNOT MEASURE: %s" % why)
        return 3

    paths = sys.argv[1:]
    if not paths:
        try:
            paths = [os.path.join(ROOT, n) for n in html_files(os.listdir(ROOT))]
        except OSError as why:
            print("CANNOT MEASURE: no design record at %s: %s" % (ROOT, why.strerror or why))
            return 2

    try:
        minimum = minimum_window()
    except NoMinimumWindow as err:
        print("USED WRONGLY: %s. Every window is measured again at the app's own minimum, "
              "read from that file, so there is nothing to draw it at." % err)
        return 2

    faults, found = [], {}
    exemptions = read_exemptions(EXEMPTIONS, faults)
    measured_files, screenless = [], []
    tally = {"measurements": 0, "states": 0}
    controls = 0

    def every_state(path, name, window, preamble, where):
        """Render the page at rest and after each press, judge each, and return
        how many controls the busiest state held, or None when it could not render."""
        per_state = []
        rest = None
        which = -1
        while rest is None or which < (rest.get("there") or 0):
            press = press_only(which)
            state = where + ("at rest" if which < 0 else "after pressing control %d" % (which + 1))
            try:
                report = session.render(path, PROBE, window=window, preamble=preamble + press)
            except CannotMeasure as why:
                print("CANNOT MEASURE: %s %s could not be rendered: %s" % (name, state, why))
                return None
            if rest is None:
                rest = report
            which += 1
            if report.get("threw"):
                faults.append("%s %s: the probe threw: %s" % (name, state, report["threw"]))
                continue
            tally["states"] += 1
            tally["measurements"] += len(report.get("controls") or [])
            per_state.append(len(report.get("controls") or []))
            judge_state(name, state, report, exemptions, found)
        return rest, (max(per_state) if per_state else 0)

    for path in paths:
        name = os.path.basename(path)
        try:
            first = session.render(path, PROBE, window=WINDOW)
        except CannotMeasure as why:
            print("CANNOT MEASURE: %s could not be rendered: %s" % (name, why))
            return 3
        if first.get("noscreen"):
            screenless.append(name)
            continue
        measured_files.append(name)
        done = every_state(path, name, WINDOW, "", "")
        if done is None:
            return 3
        controls += done[1]
        # AND AGAIN IN THE APP'S MINIMUM WINDOW, the half screen Dan works at,
        # the way check-design-draws.sh draws it: the page is given room for the
        # window, and the window its minimum width. A control squeezed to its
        # edge only there passes every rendering at the declared width.
        if first.get("windowed"):
            done = every_state(path, name, "%d,1200" % (minimum + 200),
                               "<style>.win { --win-width: %dpx !important; }</style>" % minimum,
                               "in the %d point minimum window, " % minimum)
            if done is None:
                return 3

    for row in exemptions:
        if row["file"] in measured_files and not row["used"]:
            faults.append("exemptions line %d is stale: %s's %s in %s differs from nothing in "
                          "any state measured, so %s can be closed and the line deleted"
                          % (row["line"], row["file"], row["control"], row["holder"], row["issue"]))

    for said, seen_in in found.items():
        others = len(seen_in) - 1
        faults.append("%s, %s%s" % (said, seen_in[0],
                                     " and in %d other state(s)" % others if others else ""))
    if faults:
        print("REFUSED: %d fault(s) in how the design files' controls keep their inset." % len(faults))
        for fault in faults:
            print("  FAIL %s." % fault)
        return 1

    measurements, states = tally["measurements"], tally["states"]
    if not measurements:
        print("CANNOT MEASURE: no control inside a container was measured in %d design "
              "file(s), so nothing was judged, and that reads exactly like everything passing "
              "(L98)." % len(paths))
        return 2

    print("OK: %d control(s) keep their container's inset: %d measurement(s) across %d "
          "state(s), rest and every press at both widths, in %d design file(s)."
          % (controls, measurements, states, len(measured_files)))
    for row in exemptions:
        if row["used"]:
            print("    exempted until %s: %s's %s in %s." % (row["issue"], row["file"],
                                                            row["control"], row["holder"]))
    for name in screenless:
        print("    %s draws no app screen, so it holds no control to measure." % name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
