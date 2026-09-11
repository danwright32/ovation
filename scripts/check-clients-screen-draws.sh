#!/usr/bin/env python3
"""Refuse a Clients design file that DRAWS the held money figure wrongly.

    check-clients-screen-draws.sh [design file]

ovation#98, settled 2026-09-10: the name list keeps its held money figure on
every client that has one EXCEPT the client whose box is open beside it, so the
same client's money is never stated twice at once. `check-invoice-screen-draws`
is the neighbour and this is the same argument: every other check on these files
reads their SOURCE, and a rule about what is drawn WHEN SOMETHING IS PRESSED
cannot be seen there at all.

IT IS A RULE ABOUT A PRESS, WHICH IS WHY IT NEEDS A BROWSER. The file's own
repaint used to touch only the selection class and the detail pane, never the
rows, so a first implementation of this rule draws correctly on load and then
never again: the figure stays missing from whoever was selected when the page
opened and stays present on whoever you actually click. That version passes
every reading of the source and every claim that does not press anything, and
it is exactly the version this check plants in its own suite.

WHAT IT CLAIMS, and each is one way the rule can be got wrong:

  1. With a client holding nothing selected, which is the state the file opens
     in, every holder carries its figure.
  2. Pressing a holder takes the figure off ITS row and leaves the others alone.
  3. Pressing another holder moves it: the newly selected row loses the figure
     and the one just left gets it back.
  4. Pressing a client that holds NO money leaves all three figures drawn, which
     is the claim that catches a repaint hiding the figure on every row.
  5. The selected holder's own box still states the money, so what the row gave
     up is stated exactly once rather than nowhere.

EVERY CLAIM ABOUT A SELECTED HOLDER IS MADE AFTER A PRESS, never on load. The
file opens on a client who holds nothing, so on load the selected row has no
figure to give up and the rule's own case has not arisen: a claim made there
would pass on a file that has never implemented it (L98).

WHICH CLIENTS HOLD MONEY IS READ FROM THE PAGE'S OWN DATA, never from the marks
on screen, because a file drawing no figure anywhere would otherwise satisfy
every claim about where figures are not (L98).

IT REFUSES TO GUESS WHEN IT CANNOT MEASURE. With no headless browser it exits 3
and says so, rather than exiting 0, because "every claim held" and "nothing was
checked" must never be the same answer.

Exit codes: 0 every claim held, 1 a claim failed, 2 used wrongly, 3 cannot
measure. Set OVATION_HEADLESS_BROWSER to name the browser binary.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_render import CannotMeasure, NO_BROWSER, find_browser, render  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FILE = os.path.join(REPO, "docs/design/clients.html")

PROBE = r"""
<script>
window.addEventListener("load", function () {
  var result = { claims: {}, notes: [], errors: [] };
  function claim(name, ok, saw) { result.claims[name] = { ok: !!ok, saw: saw }; }

  function rows() {
    var out = {};
    Array.prototype.forEach.call(document.querySelectorAll(".names .nrow"), function (n) {
      out[n.dataset.client] = {
        node: n,
        selected: n.classList.contains("sel"),
        figure: n.querySelector(".nheld") ? n.querySelector(".nheld").textContent.trim() : null
      };
    });
    return out;
  }

  /* The clients that hold money, from the page's own data rather than from what
     it drew: a file drawing no figure at all must not satisfy claims about where
     figures are absent. */
  function holders() {
    return (typeof HELD === "undefined" ? [] : HELD).map(function (k) { return k.c; });
  }

  function describe(map, who) {
    return who.map(function (c) {
      var r = map[c];
      if (!r) return c + ": NO ROW";
      return c + ": " + (r.figure || "no figure") + (r.selected ? " (selected)" : "");
    }).join("; ");
  }

  try {
    var who = holders();
    if (who.length < 2) {
      result.errors.push("the file's own data lists " + who.length +
        " client(s) holding money, and this rule cannot be measured under two");
    } else {
      /* ---- 1, the state the file OPENS in, which is a client holding nothing ---- */
      var onLoad = rows();
      var openSelection = Object.keys(onLoad).filter(function (c) { return onLoad[c].selected; });
      var missingOnLoad = who.filter(function (c) {
        return !onLoad[c] || onLoad[c].figure === null;
      });
      claim("with a client holding nothing selected, every holder carries its figure",
            missingOnLoad.length === 0 && openSelection.length === 1 &&
            who.indexOf(openSelection[0]) === -1,
            describe(onLoad, who) + " | selected: " + (openSelection.join(",") || "none"));

      /* THE RULE'S OWN CASE HAS TO BE REACHED BY PRESSING. The file opens on a
         client who holds nothing, so on load the selected row has no figure to
         give up and every claim about the selected holder is true of a case that
         did not arise (L98). Everything below is measured after pressing one. */
      var first = who[0], second = who[1];
      onLoad[first].node.click();
      var held = rows();
      var others = who.filter(function (c) { return c !== first; });
      claim("pressing a holder takes the figure off ITS row and leaves the others",
            held[first] && held[first].figure === null && held[first].selected &&
            others.every(function (c) { return held[c] && held[c].figure !== null; }),
            describe(held, who));

      /* ---- the box still says it, for the holder now selected ---- */
      var boxLabel = document.querySelector(".mlabel");
      var box = document.querySelector(".mval");
      claim("the selected holder's own box still states the money",
            !!(box && boxLabel && /Money held/.test(boxLabel.textContent) &&
               /\d/.test(box.textContent)),
            box && boxLabel ? boxLabel.textContent.trim() + " " + box.textContent.trim()
                            : "no money box drawn");

      /* ---- pressing another holder moves it ---- */
      held[second].node.click();
      var moved = rows();
      claim("pressing another holder moves the figure off it and back onto the one left",
            moved[second] && moved[second].figure === null &&
            moved[first] && moved[first].figure !== null,
            describe(moved, who));

      /* ---- pressing a client with no money leaves every figure drawn ---- */
      var poor = Object.keys(moved).filter(function (c) { return who.indexOf(c) === -1; })[0];
      if (!poor) {
        result.errors.push("every client in the fixture holds money, so the claim about " +
                           "pressing one that holds nothing cannot be measured");
      } else {
        moved[poor].node.click();
        var third = rows();
        var missing = who.filter(function (c) { return !third[c] || third[c].figure === null; });
        claim("pressing a client holding nothing leaves every figure drawn",
              missing.length === 0,
              describe(third, who) + " | pressed: " + poor);
      }
    }
  } catch (err) {
    result.errors.push("THREW " + (err && err.message));
  }
  var out = document.createElement("pre");
  out.id = "ovation-probe";
  out.textContent = JSON.stringify(result);
  document.body.prepend(out);
});
</script>
"""


def fail(message, code=2):
    print("check-clients-screen-draws: " + message, file=sys.stderr)
    sys.exit(code)


def main(argv):
    if len(argv) > 2:
        fail(__doc__.strip().splitlines()[2].strip())
    path = argv[1] if len(argv) == 2 else DEFAULT_FILE
    if not os.path.isfile(path):
        fail("the design file is not there: %s" % path)

    try:
        browser = find_browser()
    except CannotMeasure as err:
        # IN THE WORDS, not only in the exit code (ovation#214). This branch used
        # to print a bare sentence while its four sibling rendering checks all
        # print CANNOT MEASURE, so a reader of the output could not tell a run
        # that measured nothing from one that measured and found nothing (L11,
        # L98). The code was always 3; only the sentence was missing.
        print("CANNOT MEASURE: %s" % err)
        return 3
    if browser is None:
        print(NO_BROWSER)
        return 3

    try:
        report = render(browser, path, PROBE)
    except CannotMeasure as err:
        # IN THE WORDS, not only in the exit code (ovation#214). This branch used
        # to print a bare sentence while its four sibling rendering checks all
        # print CANNOT MEASURE, so a reader of the output could not tell a run
        # that measured nothing from one that measured and found nothing (L11,
        # L98). The code was always 3; only the sentence was missing.
        print("CANNOT MEASURE: %s" % err)
        return 3
    claims = report.get("claims", {})
    errors = report.get("errors", [])
    if not claims and not errors:
        fail("the probe reported no claims at all, so nothing was measured", 3)

    print("Rendered %s in %s" % (os.path.relpath(path, REPO), os.path.basename(browser)))
    broken = []
    for name, outcome in claims.items():
        mark = "ok  " if outcome.get("ok") else "FAIL"
        print("  %s %s: %s" % (mark, name, outcome.get("saw")))
        if not outcome.get("ok"):
            broken.append(name)
    for line in errors:
        print("  FAIL " + line)
        broken.append(line)

    if broken:
        print("\nREFUSED: %d of %d claims about what this file DRAWS did not hold."
              % (len(broken), len(claims) + len(errors)))
        return 1
    print("\nOK: all %d claims about what this file draws held." % len(claims))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
