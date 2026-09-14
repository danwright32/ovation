#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Write the text the invoice PDF design draws, and say when it is stale.

    build-invoice-pdf-text.sh [--check]

ovation#167. The app renders the invoice PDF in Swift, and the settled page is
docs/design/invoice-pdf.html. A test asserting the two agree has to READ the
designed artifact rather than a rule somebody believes produced it (L638), so
this renders the design's six fixture invoices in a browser and commits what
they draw, every label, figure and line, to docs/design/invoice-pdf.expected.json.
The app's document tests read that file.

A derived file committed beside its source is a standing claim that it is
current (L422). `--check` renders the design again and compares what it DRAWS
with what the file holds, never the file with itself, so a design edited without
re-running this, and a figure edited by hand in the file, are both STALE.

WHAT IS COMPARED IS THE MEANING, NOT THE BYTES. The fixtures' rows are compared
after parsing, so the wording of this file's own `about` note, or the spacing of
the JSON, can change without anything reading as a changed design (L405).

EACH ROW IS WRITTEN ON ONE LINE, so a changed figure is a one line difference a
person can read in review, rather than a value three lines below its label.

Exit codes, one per outcome (L11):

    0  written, or --check and the file holds what the design draws
    1  --check and the file is stale, or was never written
    2  used wrongly, or there is no design file to render
    3  cannot measure: no headless browser
    4  the design page could not be read: its script threw, or a fixture or the
       page builder is missing, so nothing was written or compared

It prints file names, fixture names and counts, never a figure or a line of the
page, and the fixtures carry invented names only (docs/PRIVACY-FLOOR.md).

Seams: OVATION_DESIGN_ROOT, OVATION_HEADLESS_BROWSER.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_render import CannotMeasure, open_browser  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")
SOURCE = "invoice-pdf.html"
EXPECTED = "invoice-pdf.expected.json"
KEYS = ["label", "head", "strip", "title", "columns", "items", "money", "foot"]
ABOUT = ("The text docs/design/invoice-pdf.html draws for each of its fixture invoices, "
         "written by scripts/build-invoice-pdf-text.sh and read by the app's document "
         "tests (ovation#167). Do not edit by hand: re-run the script, and "
         "--check says when this is no longer what the design draws.")

# The probe runs after the page's own script, so FIXTURES and buildPage exist if
# the page built itself. It builds each fixture's page and reads the text back
# out of the elements the builder made, which is what a client would read.
PROBE = r"""
<script>
(function () {
  function text(node) { return node ? node.textContent.replace(/\s+/g, " ").trim() : ""; }
  var report;
  try {
    if (typeof FIXTURES === "undefined" || !FIXTURES.length) { throw new Error("the page defines no FIXTURES"); }
    if (typeof buildPage !== "function") { throw new Error("the page defines no buildPage"); }
    report = { fixtures: FIXTURES.map(function (f) {
      var page = buildPage(f);
      var due = page.querySelector(".due");
      return {
        label: f.label,
        head: { label: text(due && due.querySelector(".lbl")),
                amount: text(due && due.querySelector(".big")),
                due: text(due && due.querySelector(".muted")) },
        strip: Array.prototype.map.call(page.querySelectorAll(".strip > div"), function (d) {
          return [text(d.children[0]), text(d.children[1])];
        }),
        title: text(page.querySelector(".doctitle")),
        columns: Array.prototype.map.call(page.querySelectorAll("table.items th"), text),
        items: Array.prototype.map.call(page.querySelectorAll("table.items tbody tr"), function (r) {
          var cells = r.querySelectorAll("td");
          return [text(r.querySelector(".desc")), text(r.querySelector(".sub2")),
                  text(cells[1]), text(cells[2]), text(cells[3])];
        }),
        money: Array.prototype.map.call(page.querySelectorAll(".money .row"), function (r) {
          var spans = r.querySelectorAll("span");
          return [text(spans[0]), text(spans[1])];
        }),
        foot: Array.prototype.map.call(page.querySelectorAll(".foot > div"), function (d) {
          return [text(d.querySelector(".lbl")), Array.prototype.map.call(d.querySelectorAll("p"), text)];
        })
      };
    }) };
  } catch (e) {
    report = { error: String(e && e.message || e) };
  }
  var pre = document.createElement("pre");
  pre.id = "ovation-probe";
  pre.textContent = JSON.stringify(report);
  document.body.appendChild(pre);
})();
</script>
"""


def serialise(fixtures):
    """The file, with every row on one line."""
    out = ["{",
           '  "about": %s,' % json.dumps(ABOUT, ensure_ascii=False),
           '  "source": "docs/design/%s",' % SOURCE,
           '  "fixtures": [']
    for index, fixture in enumerate(fixtures):
        parts = []
        for key in KEYS:
            value = fixture[key]
            if isinstance(value, list) and value:
                inner = ",\n".join("        " + json.dumps(row, ensure_ascii=False) for row in value)
                parts.append("      %s: [\n%s\n      ]" % (json.dumps(key), inner))
            else:
                parts.append("      %s: %s" % (json.dumps(key), json.dumps(value, ensure_ascii=False)))
        out.append("    {")
        out.append(",\n".join(parts))
        out.append("    }" + ("," if index < len(fixtures) - 1 else ""))
    out.extend(["  ]", "}"])
    return "\n".join(out) + "\n"


def rows_in(fixtures):
    return sum(len(f["strip"]) + len(f["items"]) + len(f["money"]) + len(f["foot"]) for f in fixtures)


def first_difference(held, drawn):
    """Which fixture and which part first disagree, by name only."""
    if len(held) != len(drawn):
        return "the file holds %d fixture(s) and the design draws %d" % (len(held), len(drawn))
    for h, d in zip(held, drawn):
        for key in KEYS:
            if h.get(key) != d.get(key):
                return "the %s fixture's %s differs" % (d.get("label"), key)
    return "the fixtures differ"


def main(argv):
    if argv not in ([], ["--check"]):
        print("usage: build-invoice-pdf-text.sh [--check]")
        return 2
    check_only = argv == ["--check"]
    source = os.path.join(ROOT, SOURCE)
    expected = os.path.join(ROOT, EXPECTED)
    if not os.path.isfile(source):
        print("NOTHING TO RENDER: %s is not in %s, so nothing was written or compared." % (SOURCE, ROOT))
        return 2

    try:
        with open_browser() as session:
            report = session.render(source, PROBE)
    except CannotMeasure as err:
        print("CANNOT MEASURE: %s: %s" % (SOURCE, err))
        return 3

    if report.get("error") is not None or not isinstance(report.get("fixtures"), list):
        print("CANNOT READ: the design page %s could not be read: %s"
              % (SOURCE, report.get("error") or "the probe reported no fixtures"))
        print("    Nothing was written or compared.")
        return 4
    drawn = report["fixtures"]

    if not check_only:
        with open(expected, "w", encoding="utf-8") as handle:
            handle.write(serialise(drawn))
        print("WROTE: %s, the text of %d fixture(s), %d row(s)." % (EXPECTED, len(drawn), rows_in(drawn)))
        return 0

    if not os.path.isfile(expected):
        print("MISSING: %s has never been written, so there is nothing to compare with." % EXPECTED)
        print("    Write it with: scripts/build-invoice-pdf-text.sh")
        return 1
    try:
        held = json.load(open(expected, encoding="utf-8")).get("fixtures")
    except ValueError:
        held = None
    if held != drawn:
        reason = first_difference(held, drawn) if isinstance(held, list) else "the file cannot be read as fixtures"
        print("STALE: %s no longer holds the text the design draws: %s." % (EXPECTED, reason))
        print("    Re-write it with: scripts/build-invoice-pdf-text.sh")
        return 1
    print("CURRENT: %s holds the text of %d fixture(s), %d row(s), as the design draws them."
          % (EXPECTED, len(drawn), rows_in(drawn)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
