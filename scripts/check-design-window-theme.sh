#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a design file whose app screen changes with the record page's theme.

    check-design-window-theme.sh [design file ...]

A design file is two things on one page: the record, prose and switches that
follow the reader's light or dark setting through the page's own `--page-*`
tokens, and the app's screen, which does not. The app is pinned to light
(ovation#479), so nothing drawn inside `.screen` may change when the page
around it does. Twice on 2026-09-29 it did: review-send.html's message editor
was painted from `--page-panel` and its title bar's words inherited the page's
ink, so read in dark mode the screen showed dark words on a dark field. Neither
named a token anywhere a search for the screen's rules would look: the title
bar set no colour at all, and inherited the page's.

SO IT IS MEASURED, NOT READ. A search of the source for `--page-` inside the
screen's rules cannot see inheritance, which is the fault that happened. Each
file is rendered with the page forced to its light theme and again forced to
its dark one, and what the screen PAINTS is compared element by element: every
background that is not transparent, every border that is drawn, every shadow,
and the ink of every element that holds words of its own or is a field. A
colour nothing paints with, the ink of a box holding no words, is left out,
since two themes may differ there without anybody seeing it.

IN EVERY STATE ONE PRESS REACHES, the page at rest and each control pressed from
rest in a page of its own, with the list check-design-draws.sh presses, because
a sheet or a panel appears only after a press.

A KNOWN LEAK CAN BE EXEMPTED only by naming the issue that ends it, in
scripts/design-theme-exemptions.tsv: four tab separated columns, the design
file, the element as `tag.class.class`, the issue, and the reason. A line with
no issue or no reason is refused (L65, L233), and so is one that covered
nothing in a file this run compared (L346).

IT NEVER QUOTES THE PAGE: elements are named by their classes and states by
the number of the control pressed (docs/PRIVACY-FLOOR.md).

Exit codes, one per outcome (L11):

    0  every screen paints the same in both page themes
    1  one does not, or an exemption is wrong
    2  no design file drew a screen, which is not a pass
    3  no browser, so nothing could be rendered at all

Seams, shared with the other design checks where they exist:

    OVATION_DESIGN_ROOT       the design record to read
    OVATION_HEADLESS_BROWSER  the browser to render in
    OVATION_THEME_EXEMPTIONS  the exemptions file
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_inline import html_files  # noqa: E402
from design_render import CannotMeasure, PRESS_THEN_REPORT, open_browser, press_only  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")
EXEMPTIONS = (os.environ.get("OVATION_THEME_EXEMPTIONS")
              or os.path.join(REPO, "scripts", "design-theme-exemptions.tsv"))

WINDOW = "1440,1200"
THEMES = ("light", "dark")

PROBE = r"""
<script>
__PRESS_THEN_REPORT__
window.addEventListener("load", function () {
  var result = { painted: [], pressed: null };
  function visible(colour) {
    var m = String(colour).match(/[\d.]+/g);
    return !!m && (m.length < 4 || +m[3] > 0);
  }
  function own(e) {
    var classes = typeof e.className === "string" ? e.className.trim() : "";
    return e.tagName.toLowerCase() + (classes ? "." + classes.split(/\s+/).join(".") : "");
  }
  /* An element with no class of its own is named inside the nearest one that
     has one, so an exemption for it cannot cover every bare span in the file. */
  function describe(e) {
    if (typeof e.className === "string" && e.className.trim()) return own(e);
    for (var p = e.parentElement; p; p = p.parentElement) {
      if (typeof p.className === "string" && p.className.trim()) return own(p) + " " + own(e);
    }
    return own(e);
  }
  function measure() {
    var scope = document.querySelector(".screen");
    if (!scope) { result.noscreen = true; return; }
    [scope].concat([].slice.call(scope.querySelectorAll("*"))).forEach(function (e) {
      /* Only what is drawn: an element with no box, or hidden, paints nothing
         whatever its rules say, and is judged in the state that draws it. */
      if (!e.getClientRects().length || getComputedStyle(e).visibility === "hidden") return;
      var s = getComputedStyle(e), paint = {};
      if (visible(s.backgroundColor)) paint.background = s.backgroundColor;
      ["Top", "Right", "Bottom", "Left"].forEach(function (k) {
        if (parseFloat(s["border" + k + "Width"]) > 0 && s["border" + k + "Style"] !== "none") {
          paint["border " + k.toLowerCase()] = s["border" + k + "Color"];
        }
      });
      if (s.boxShadow && s.boxShadow !== "none") paint.shadow = s.boxShadow;
      var words = [].some.call(e.childNodes, function (n) { return n.nodeType === 3 && n.textContent.trim(); });
      if (words || /^(INPUT|TEXTAREA|SELECT)$/.test(e.tagName)) paint.text = s.color;
      result.painted.push({ element: describe(e), paint: paint });
    });
  }
  ovationPressThenReport(result, measure);
});
</script>
""".replace("__PRESS_THEN_REPORT__", PRESS_THEN_REPORT)


def read_exemptions(path, faults):
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
        cells += [""] * (4 - len(cells))
        name, element, issue, reason = (cell.strip() for cell in cells[:4])
        if not (name and element):
            faults.append("exemptions line %d does not name a file and an element" % number)
        elif not issue.startswith("ovation#") or not issue[len("ovation#"):].isdigit():
            faults.append("exemptions line %d names no issue that ends it, and an exemption "
                          "with no issue is never ended (L65)" % number)
        elif not reason:
            faults.append("exemptions line %d gives no reason (L233)" % number)
        else:
            rows.append({"line": number, "file": name, "element": element, "issue": issue,
                         "used": False})
    return rows


def theme_preamble(theme):
    return "<script>document.documentElement.setAttribute(\"data-theme\", \"%s\");</script>" % theme


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

    faults, found = [], {}
    exemptions = read_exemptions(EXEMPTIONS, faults)
    compared, screenless = [], []
    states = elements = 0
    for path in paths:
        name = os.path.basename(path)
        which, there = -1, None
        while there is None or which < there:
            press = press_only(which)
            state = "at rest" if which < 0 else "after pressing control %d" % (which + 1)
            reports = {}
            for theme in THEMES:
                try:
                    reports[theme] = session.render(path, PROBE, window=WINDOW,
                                                    preamble=theme_preamble(theme) + press)
                except CannotMeasure as why:
                    print("CANNOT MEASURE: %s %s in the %s theme could not be rendered: %s"
                          % (name, state, theme, why))
                    return 3
            light, dark = reports["light"], reports["dark"]
            if there is None:
                there = light.get("there") or 0
            which += 1
            if light.get("noscreen"):
                screenless.append(name)
                break
            if light.get("threw") or dark.get("threw"):
                faults.append("%s %s: the probe threw: %s"
                              % (name, state, light.get("threw") or dark.get("threw")))
                continue
            if name not in compared:
                compared.append(name)
            states += 1
            ones, others = light.get("painted") or [], dark.get("painted") or []
            if len(ones) != len(others):
                faults.append("%s %s: the screen draws %d element(s) in the light page and %d in "
                              "the dark one" % (name, state, len(ones), len(others)))
                continue
            elements += len(ones)
            for one, other in zip(ones, others):
                changed = sorted(key for key in set(one["paint"]) | set(other["paint"])
                                 if one["paint"].get(key) != other["paint"].get(key))
                if not changed:
                    continue
                covering = [row for row in exemptions
                            if row["file"] == name and row["element"] == one["element"]]
                for row in covering:
                    row["used"] = True
                if covering:
                    continue
                said = ("%s: %s paints its %s differently when the page is dark, so the page's "
                        "theme reaches into the app's screen"
                        % (name, one["element"], " and ".join(changed)))
                found.setdefault(said, []).append(state)

    for row in exemptions:
        if row["file"] in compared and not row["used"]:
            faults.append("exemptions line %d is stale: %s's %s paints the same in both themes "
                          "in every state compared, so the line can be deleted and %s checked"
                          % (row["line"], row["file"], row["element"], row["issue"]))
    for said, seen_in in found.items():
        others = len(seen_in) - 1
        faults.append("%s, %s%s" % (said, seen_in[0],
                                     " and in %d other state(s)" % others if others else ""))

    if faults:
        print("REFUSED: %d fault(s) where a design file's screen follows the page's theme."
              % len(faults))
        for fault in faults:
            print("  FAIL %s." % fault)
        return 1

    if not states:
        print("CANNOT MEASURE: no design file drew an app screen, out of %d given, so nothing "
              "was compared, and that reads exactly like everything passing (L98)." % len(paths))
        return 2

    print("OK: every screen paints the same in the light and dark page: %d element "
          "reading(s) across %d state(s), rest and every press, in %d design file(s)."
          % (elements, states, len(compared)))
    for row in exemptions:
        if row["used"]:
            print("    exempted until %s: %s's %s." % (row["issue"], row["file"], row["element"]))
    for name in sorted(set(screenless)):
        print("    %s draws no app screen, so it has nothing to compare." % name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
