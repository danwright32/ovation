#!/usr/bin/env python3
"""Refuse a design record whose sidebar rail disagrees with itself.

    check-design-sidebar-card.sh [design file ...]

ovation#188. The card is CHROME: the same panel, with the same lines, on every
screen the app draws. Nothing compared the copies, and on 2026-09-10 they had
been apart for three days without a single check going red. `clients.html` and
`invoice.html` drew five lines and `invoice-list.html` and `review-send.html`
drew four, because the fifth was added in a round about the Clients screen and
the round's own file was the only one edited. Each file renders, each looks
settled on its own, and the disagreement exists only BETWEEN them, which is the
one place nobody reads (L605, L613).

`check-design-shell-inline.sh` is the neighbour and it cannot see this. It
compares each file's copy of the shell STYLESHEET, and the lines are markup: the
four copies of `window.css` were identical the whole time the cards disagreed.

WHAT IT ASSERTS, and each is one thing the drift actually did:

  1. every file that draws an app window draws the card
  2. the card's heading is the same words in every file
  3. the card's lines, labels and figures both, are the same list in every file
  4. the rail's held money line is present in the same files and reads the same
  5. in each file, that line's label starts where the card's labels start and
     its figure ends where the card's figures end

FIVE IS GEOMETRY AND IT IS HERE ON PURPOSE. The held line sits OUTSIDE the card
(ovation#187), so its 3px margin and 12px padding have to add up to the card's
3px margin, 1px border and 11px padding. Two numbers that happen to agree are
not an alignment, and the only way to know they still do is to render it and
measure both.

WHICH FILES ARE EXPECTED TO DRAW ONE is the file's own declaration, never a list
of names kept here (L362). A file that draws no app window already says so, in
its own words, by declaring `NOT SHELLED: window.css` with the reason, and that
declaration is read from the same helper the shell check reads it with, so the
two cannot come to disagree about which files draw a window (L370).

Exit codes, one per outcome (L11):

    0  every rail agrees, and every held line sits on the card's edges
    1  the rails disagree, or a held line is off the card's edges
    2  fewer than two rails were rendered, which is not a pass: nothing was
       compared, and a comparison with one subject reports exactly what perfect
       agreement reports (L98)
    3  no browser, so nothing could be rendered at all

IT NAMES LABELS AND FIGURES AND NEVER A CLIENT. Both are chrome we wrote. The
rail carries no client name today and this prints to a terminal, so the rule in
docs/PRIVACY-FLOOR.md is kept rather than relied upon to stay true by accident.

Seams, shared with the other design checks rather than invented again:

    OVATION_DESIGN_ROOT       the design record to read
    OVATION_HEADLESS_BROWSER  the browser to render in
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_inline import declared_parts, html_files  # noqa: E402
from design_render import CannotMeasure, NO_BROWSER, find_browser, render  # noqa: E402

# The probe reads the rail back out of the RENDERING, never the source. What
# went wrong was a list built in JavaScript, in four places, and the geometry it
# also measures cannot be read off a stylesheet at all.
PROBE = r"""
<script>
(function () {
  function edges(label, figure) {
    return [Math.round(label.getBoundingClientRect().left * 100) / 100,
            Math.round(figure.getBoundingClientRect().right * 100) / 100];
  }
  var report = {card: null, heading: null, lines: [], held: null,
                cardEdges: null, heldEdges: null};
  var card = document.querySelector(".card");
  if (card) {
    report.card = true;
    var head = card.querySelector(".hd");
    report.heading = head ? head.textContent.trim() : null;
    var lines = card.querySelectorAll(".ln");
    for (var i = 0; i < lines.length; i++) {
      var label = lines[i].querySelector("span");
      var figure = lines[i].querySelector("b");
      report.lines.push([label ? label.textContent.trim() : null,
                         figure ? figure.textContent.trim() : null]);
      if (label && figure) { report.cardEdges = edges(label, figure); }
    }
  }
  var held = document.querySelector(".railheld");
  if (held) {
    var heldLabel = held.querySelector("span");
    var heldFigure = held.querySelector("b");
    report.held = [heldLabel ? heldLabel.textContent.trim() : null,
                   heldFigure ? heldFigure.textContent.trim() : null];
    if (heldLabel && heldFigure) { report.heldEdges = edges(heldLabel, heldFigure); }
  }
  var out = document.createElement("pre");
  out.id = "ovation-probe";
  out.textContent = JSON.stringify(report);
  document.body.appendChild(out);
})();
</script>
"""

# What counts as the same edge. Sub pixel differences are what a browser's own
# rounding produces on identical boxes; anything a person could see is far
# larger than this, and the fault this exists to catch moved a figure by 12px.
EDGE_TOLERANCE = 0.5

# The declaration a file makes when it draws no app window at all.
WINDOW_PART = "window.css"


def rail_of(report):
    """The rail as one comparable value: heading, lines, and the held line."""
    return (report.get("heading"),
            tuple(tuple(pair) for pair in report.get("lines") or []),
            tuple(report["held"]) if report.get("held") else None)


def say(rail):
    heading, lines, held = rail
    drawn = ", ".join("%s %s" % (label, figure) for label, figure in lines)
    return "%s: %s%s" % (heading, drawn or "no lines",
                         "; held line %s %s" % held if held else "; no held line")


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(repo_root, "docs", "design")

    try:
        browser = find_browser()
    except CannotMeasure as err:
        print("CANNOT MEASURE: %s" % err)
        return 3
    if browser is None:
        print(NO_BROWSER)
        return 3

    given = sys.argv[1:]
    if given:
        paths = given
    else:
        if not os.path.isdir(root):
            print(f"CANNOT SCAN: {root} is not a directory, so nothing was compared.")
            print("             That is not a pass. Point OVATION_DESIGN_ROOT at the record.")
            return 2
        paths = [os.path.join(root, name) for name in html_files(os.listdir(root))]

    rails, no_card, edges_off, skipped = {}, [], [], []
    for path in paths:
        name = os.path.basename(path)
        if not os.path.isfile(path):
            print(f"CANNOT SCAN: {name} is not there, so nothing was rendered from it.")
            return 2
        with open(path, encoding="utf-8", errors="replace") as handle:
            declared = declared_parts(handle.read())
        if WINDOW_PART in declared:
            skipped.append(name)
            print(f"  {name}: draws no app window, by its own declaration")
            continue

        try:
            report = render(browser, path, PROBE)
        except CannotMeasure as err:
            print("CANNOT MEASURE: %s: %s" % (name, err))
            return 3

        if not report.get("card"):
            no_card.append(name)
            print(f"  {name}: NO CARD")
            continue

        rails[name] = rail_of(report)
        print("  %s: %s" % (name, say(rails[name])))

        # The held line's own edges against the card's, inside this one file.
        # Nothing else measures it: both boxes are declared correctly and the
        # numbers only have to ADD UP to the same place.
        card_edges = report.get("cardEdges")
        held_edges = report.get("heldEdges")
        if report.get("held") and card_edges and held_edges:
            off = [round(held_edges[i] - card_edges[i], 2) for i in (0, 1)]
            if abs(off[0]) > EDGE_TOLERANCE or abs(off[1]) > EDGE_TOLERANCE:
                edges_off.append((name, "the held money line is %spx off the card's left "
                                        "edge and %spx off its right" % (off[0], off[1])))
        elif report.get("held"):
            edges_off.append((name, "the held money line could not be measured against the card"))

    # A FILE THAT DRAWS NO CARD IS ANSWERED FIRST, and before the count below,
    # because it REMOVES a subject from the comparison: reporting it as "fewer
    # than two rails to compare" would name the shortage and never the file that
    # caused it, and the remedy for the two is not the same (L11).
    if no_card:
        print("")
        print("A DESIGN FILE THAT DRAWS THE APP WINDOW AND NO CARD: %d file(s)."
              % len(no_card))
        for name in no_card:
            print("  %s: NO CARD, and it carries window.css rather than declaring it does not"
                  % name)
        print("")
        print("The card is part of the rail, so every screen has one. A file that")
        print("genuinely draws no app window says so in its own words, by declaring")
        print("NOT SHELLED: window.css with the reason, which is what invoice-pdf.html")
        print("does.")
        return 1

    if len(rails) < 2:
        print(f"CANNOT COMPARE: {len(rails)} rail(s) rendered, out of {len(paths)} "
              f"file(s) given and {len(skipped)} that draw no window.")
        print("                A comparison needs two subjects. With fewer, this")
        print("                reports exactly what perfect agreement reports, which")
        print("                is the one thing a checker may never do (L98).")
        return 2

    agreed = set(rails.values())
    if len(agreed) > 1:
        print("")
        print("THE SIDEBAR RAIL DISAGREES WITH ITSELF: %d different rails across %d "
              "design file(s)." % (len(agreed), len(rails)))
        for rail in sorted(agreed, key=say):
            drawn_by = sorted(name for name, seen in rails.items() if seen == rail)
            print("  %s" % say(rail))
            print("      drawn by %s" % ", ".join(drawn_by))
        print("")
        print("The rail is chrome: the same panel on every screen. Each file builds")
        print("its own copy in its own script, so a line added during a round about")
        print("one screen is added to one file, and every file goes on rendering.")
        print("Put the same lines in every file above, or the first time 4 on one")
        print("screen is compared with 5 on the next it reads as a defect in the")
        print("counts rather than in the record.")
        return 1

    if edges_off:
        print("")
        print("THE HELD MONEY LINE IS OFF THE CARD'S EDGES: %d file(s)." % len(edges_off))
        for name, why in edges_off:
            print("  %s: %s" % (name, why))
        print("")
        print("It sits outside the card, so its margin and padding have to add up")
        print("to the card's margin, border and padding on both sides. They agree by")
        print("construction in shell/window.css; a file drawing it somewhere else in")
        print("the rail, or wrapping it in anything, breaks that.")
        return 1

    print("OK: one rail across %d design file(s), %s. %d file(s) draw no app window."
          % (len(rails), say(next(iter(agreed))), len(skipped)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
