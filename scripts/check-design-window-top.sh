#!/usr/bin/env python3
"""Refuse a design file whose window has slid too far down its page.

    check-design-window-top.sh [design file ...]

ovation#192. `invoice.html` carries a recorded decision about exactly this: two
prose blocks were cut from above the window because carrying all three took the
top of the design from 380px to 514px down the page on an 800px laptop window,
which is more than half the screen gone before the thing the page exists to
show. Nothing enforced it, so it drifted straight back.

IT COST A RED BUILD ON 2026-09-10. One extra row of state switches added about
40px above the window. Every check passed on Dan's Mac; on the Linux runner the
page renders taller, the due date terms opened below the fold, and
`check-invoice-screen-draws.sh` refused an unrelated claim, saying it could not
measure them. The refusal was correct and named the wrong subject, so the
diagnosis started in the wrong place.

WHAT IS MEASURED CANNOT BE READ FROM A STYLESHEET. The distance from the top of
the page to the top of the window is the sum of whatever masthead, prose, notice
and switches happen to sit above it, in whatever the browser makes of them at
that width. Only a rendering has it.

THE CEILING, AND WHERE ITS NUMBER COMES FROM. 460px on an 800px laptop window.
It is derived from the decision already in the record rather than invented here:
380px was the state that decision accepted and 514px the state it rejected as
more than half the screen. 460 sits between them, above where the invoice file
renders today, and refuses anything approaching the state already turned down.
It is a GROWTH guard: it says a page may not drift back to a shape that was
looked at and refused, not that any particular page is well composed.

WHICH FILES ARE EXPECTED TO DRAW A WINDOW is the file's own declaration, never a
list of names kept here (L362). A file that draws no app window already says so,
in its own words, by declaring `NOT SHELLED: window.css` with the reason, read
through the same helper the shell check and the sidebar check read it with, so
the three cannot come to disagree about which files draw a window (L370).

A STALE DECLARATION IS REFUSED RATHER THAN HONOURED. A file saying it draws no
window while drawing one would exempt itself from the very measurement, and an
exemption that outlives its reason reads as a considered decision and is never
revisited (L346).

AND A FILE WITH NEITHER IS REFUSED TOO. A page that stopped drawing its window
and says nothing about it would otherwise be measured as compliant, which is the
one thing a checker may never report (L98).

Exit codes, one per outcome (L11):

    0  every file that draws a window starts it above the ceiling
    1  at least one starts below it, or declares wrongly
    2  no design file could be measured, which is not a pass
    3  no browser, so nothing could be rendered at all

IT PRINTS FILE NAMES AND PIXELS AND NOTHING ELSE. Both are ours, and this prints
to a terminal, so docs/PRIVACY-FLOOR.md is kept rather than relied on to stay
true by accident.

Seams, shared with the other design checks rather than invented again:

    OVATION_DESIGN_ROOT       the design record to read
    OVATION_HEADLESS_BROWSER  the browser to render in
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_inline import declared_parts, html_files  # noqa: E402
from design_render import CannotMeasure, NO_BROWSER, find_browser, render  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")

# The laptop window the recorded decision was measured on. The width is the one
# the other rendering checks use; the HEIGHT is what the ceiling means, and it is
# 800 because that is the window the record's own 380 and 514 were taken in.
WINDOW = "1440,800"
LAPTOP_HEIGHT = 800
CEILING = 460

# The declaration a file makes when it draws no app window at all.
WINDOW_PART = "window.css"

PROBE = r"""
<script>
(function () {
  var report = {top: null};
  var screen = document.querySelector(".screen");
  if (screen) {
    var box = screen.getBoundingClientRect();
    report.top = Math.round(box.top + window.scrollY);
    report.height = Math.round(box.height);
  }
  var out = document.createElement("pre");
  out.id = "ovation-probe";
  out.textContent = JSON.stringify(report);
  document.body.appendChild(out);
})();
</script>
"""


def main():
    paths = sys.argv[1:]
    if not paths:
        try:
            paths = [os.path.join(ROOT, n) for n in html_files(os.listdir(ROOT))]
        except OSError as why:
            print("CANNOT MEASURE: no design record at %s: %s"
                  % (ROOT, why.strerror or why))
            return 2

    try:
        browser = find_browser()
    except CannotMeasure as why:
        print("CANNOT MEASURE: %s" % why)
        print("                %s" % NO_BROWSER)
        return 3

    measured = []
    skipped = []
    faults = []
    for path in paths:
        name = os.path.basename(path)
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                declares_no_window = WINDOW_PART in declared_parts(handle.read())
        except OSError as why:
            faults.append((name, "could not be read: %s" % (why.strerror or why)))
            continue

        try:
            report = render(browser, path, PROBE, window=WINDOW)
        except CannotMeasure as why:
            faults.append((name, "could not be rendered: %s" % why))
            continue

        top = report.get("top")
        if top is None:
            if declares_no_window:
                skipped.append(name)
            else:
                # NEITHER A WINDOW NOR A WORD ABOUT IT. Counting this as a pass
                # is how a page that stopped drawing its window reads as
                # compliant for ever.
                faults.append((name, "draws no app window and does not say so. A file "
                                     "that draws none declares `NOT SHELLED: %s` with "
                                     "its reason" % WINDOW_PART))
            continue

        if declares_no_window:
            faults.append((name, "declares `NOT SHELLED: %s` and draws a window %dpx "
                                 "down the page. The declaration is STALE, and it "
                                 "exempts this file from the measurement" % (WINDOW_PART, top)))
            continue

        measured.append((name, top, report.get("height")))

    if faults:
        print("REFUSED: %d design file(s) could not be judged as they stand." % len(faults))
        for name, why in faults:
            print("  %s: %s" % (name, why))
        return 1

    if not measured:
        print("CANNOT MEASURE: no design file drew an app window, out of %d given "
              "and %d that declare they draw none." % (len(paths), len(skipped)))
        print("                A run that judged nothing reports exactly what a run")
        print("                that judged everything reports (L98).")
        return 2

    over = [row for row in measured if row[1] > CEILING]
    if over:
        print("REFUSED: %d of %d design file(s) start their window more than %dpx "
              "down the page." % (len(over), len(measured), CEILING))
        for name, top, height in over:
            print("  %s: the window starts %dpx down, %dpx past the %dpx ceiling"
                  % (name, top, top - CEILING, CEILING))
        print("")
        print("Measured in a %s window, which is the laptop the recorded decision" % WINDOW)
        print("was taken in. 380px was the state that decision accepted and 514px")
        print("the state it rejected, as more than half the screen gone before the")
        print("thing the page exists to show. Move what sits above the window below")
        print("it, which is the decision invoice.html already carries.")
        return 1

    deepest = max(measured, key=lambda row: row[1])
    print("OK: %d design file(s) start their window within %dpx of the top, in a "
          "%dpx laptop window." % (len(measured), CEILING, LAPTOP_HEIGHT))
    print("    deepest is %s at %dpx. %d file(s) draw no app window."
          % (deepest[0], deepest[1], len(skipped)))
    for name in skipped:
        print("    %s draws no app window and says so." % name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
