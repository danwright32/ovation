#!/usr/bin/env python3
"""Refuse an invoice design file that DRAWS something wrong.

    check-invoice-screen-draws.sh [design file]

ovation#141 says it outright: nothing measures what a design file actually
draws. Every other check on these files reads their SOURCE, so it can see that a
rule is declared and never that the rule put the thing in the wrong place. Round
A of ovation#111 found three faults in one afternoon that no source reading
could have caught, and each of the claims below is the fingerprint of one of
them:

  1. The first line's amount was the LINES TOTAL rather than its own figure.
     The two are the same number while an invoice can only carry one line, so
     the defect could not exist until a second line was added, and then a 375.00
     line read as 450.00 with a 75.00 line beneath it (L101).
  2. The Edit menu opened 46px to the LEFT of Edit, under File, because it was
     positioned by a constant the menu bar's wording had moved out from under.
     A menu drawn in the wrong place still draws, so nothing reported it.
  3. Choosing something in that menu left it standing, covering the invoice it
     had just changed.

IT RENDERS THE FILE AND READS THE RESULT BACK. It drives the screen the way a
person does, by pressing what is on it, rather than asserting about the source,
because the source was correct in all three cases above.

IT REFUSES TO GUESS WHEN IT CANNOT MEASURE. With no headless browser it exits 3
and says so, rather than exiting 0, because "every claim held" and "nothing was
checked" must never be the same answer (L98).

Exit codes: 0 every claim held, 1 a claim failed, 2 used wrongly, 3 cannot
measure. Set OVATION_HEADLESS_BROWSER to name the browser binary.
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FILE = os.path.join(REPO, "docs/design/invoice.html")

# Where playwright puts the headless shell. Named as a glob rather than a pinned
# version, because the version moves with whatever last installed it and a check
# that goes quiet after an upgrade is worse than one that is not there.
BROWSER_GLOBS = [
    os.path.expanduser("~/Library/Caches/ms-playwright/chromium_headless_shell-*/"
                       "chrome-headless-shell-mac-arm64/chrome-headless-shell"),
    os.path.expanduser("~/Library/Caches/ms-playwright/chromium-*/"
                       "chrome-mac/Chromium.app/Contents/MacOS/Chromium"),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
]

# The probe. It runs INSIDE the rendered page and reports what the page drew.
#
# IT REACHES FOR THE PAGE'S OWN ensureIssued() rather than typing into the time
# fields. Typing would test the time field, which has its own suite, and would
# make every claim below depend on it: a broken time field would then report as
# a broken line table, which is two situations with one message (L11).
PROBE = r"""
<script>
window.addEventListener("load", function () {
  var result = { claims: {}, notes: [], errors: [] };
  function claim(name, ok, saw) {
    result.claims[name] = { ok: !!ok, saw: saw };
  }
  try {
    var verdict = document.getElementById("verdict");
    claim("the page's own rule suites pass",
          verdict && /^All \d+ cases pass/.test(verdict.textContent),
          verdict ? verdict.textContent.slice(0, 70) : "no verdict element");

    /* ---- the Edit menu ---- */
    var edit = Array.prototype.filter.call(
      document.querySelectorAll(".menubar [role=button]"),
      function (s) { return s.textContent === "Edit"; })[0];
    if (!edit) {
      claim("the Edit menu opens under Edit", false, "no Edit item in the menu bar");
      claim("choosing something closes the menu", false, "no Edit item in the menu bar");
    } else {
      edit.click();
      var menu = document.querySelector(".menu");
      if (!menu) {
        claim("the Edit menu opens under Edit", false, "pressing Edit drew no menu");
        claim("choosing something closes the menu", false, "pressing Edit drew no menu");
      } else {
        var item = Array.prototype.filter.call(
          document.querySelectorAll(".menubar [role=button]"),
          function (s) { return s.textContent === "Edit"; })[0];
        var offset = Math.round(menu.getBoundingClientRect().left
                                - item.getBoundingClientRect().left);
        /* macOS hangs a menu on its own item, a few pixels left of the word to
           allow for the highlight. Twelve is generous and still catches the
           46px this check was written for. */
        claim("the Edit menu opens under Edit", Math.abs(offset) <= 12,
              "the menu's left edge is " + offset + "px from Edit's");

        var wired = Array.prototype.filter.call(
          document.querySelectorAll(".menu div"),
          function (d) { return /^Add a discount$/.test(d.textContent); })[0];
        if (!wired) {
          claim("choosing something closes the menu", false,
                "the menu has no 'Add a discount' to choose");
        } else {
          wired.click();
          claim("choosing something closes the menu",
                !document.querySelector(".menu"),
                document.querySelector(".menu") ? "the menu is still open" : "it closed");
        }
      }
    }

    /* ---- the line table, on an invoice that has been priced ---- */
    ensureIssued();
    redraw();

    var word = document.querySelector(".laddbtn");
    claim("a draft offers a way to add a line", !!word,
          word ? word.textContent : "nothing on the lines to press");
    if (word) {
      word.click();
      var chooser = document.querySelector(".typebtn");
      claim("the new row asks for a service type", !!chooser,
            chooser ? chooser.textContent : "no chooser in the new row");
      if (chooser) {
        chooser.click();
        var list = document.querySelector(".typelist");
        var names = list ? Array.prototype.map.call(list.querySelectorAll("button"),
                                                   function (b) { return b.textContent; }) : [];
        claim("the service types are offered", names.length >= 2, names.join(", "));
        if (list) {
          list.querySelectorAll("button")[1].click();
          var field = document.querySelector(".lamt");
          claim("the new row takes an amount", !!field,
                field ? "an amount field" : "no amount field");
          if (field) {
            claim("the amount asserts no figure it was not given",
                  !field.placeholder || !/\d/.test(field.placeholder),
                  "placeholder: " + JSON.stringify(field.placeholder));
            field.value = "75";
            field.dispatchEvent(new Event("blur"));
          }
        }
      }
    }

    var rows = document.querySelectorAll(".lrow");
    var texts = Array.prototype.map.call(rows, function (r) {
      return Array.prototype.map.call(r.children, function (c) {
        return c.textContent.trim();
      }).join(" | ");
    });
    result.notes = texts;
    claim("the added line is on the invoice", rows.length === 2, texts.join("  //  "));

    /* THE FIRST LINE SHOWS ITS OWN AMOUNT. Its hours times its rate, read off
       the row itself, so this cannot be satisfied by agreeing with a total that
       is also wrong. */
    if (rows.length === 2) {
      var cells = rows[0].children;
      var hours = parseFloat(cells[1].textContent.replace(/,/g, ""));
      var rate = parseFloat(cells[2].textContent.replace(/,/g, ""));
      var shown = parseFloat(cells[3].textContent.replace(/,/g, ""));
      claim("the first line shows its own amount, not the lines total",
            Math.abs(shown - hours * rate) < 0.005,
            hours + " x " + rate + " should be " + (hours * rate).toFixed(2)
              + ", the row says " + shown.toFixed(2));
    }

    /* EVERY FIGURE KEEPS ONE RIGHT EDGE, which is what the totals were measured
       twice to protect and what a widened row silently breaks. */
    var edges = {};
    Array.prototype.forEach.call(
      document.querySelectorAll(".lrow .fig:last-child, .sline .fig"),
      function (f) {
        var right = Math.round(f.getBoundingClientRect().right);
        edges[right] = (edges[right] || 0) + 1;
      });
    claim("every figure keeps one right edge", Object.keys(edges).length === 1,
          JSON.stringify(edges));

    /* Nothing may overflow the invoice sideways (L76, L566). */
    var inv = document.querySelector(".inv");
    claim("the invoice does not cut off its own side",
          inv && inv.scrollWidth <= inv.clientWidth + 1,
          inv ? (inv.scrollWidth - inv.clientWidth) + "px over" : "no invoice drawn");
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
    print("check-invoice-screen-draws: " + message, file=sys.stderr)
    sys.exit(code)


def find_browser():
    named = os.environ.get("OVATION_HEADLESS_BROWSER", "").strip()
    if named:
        if not os.path.isfile(named):
            fail("OVATION_HEADLESS_BROWSER names %s, which is not there" % named, 3)
        return named
    for pattern in BROWSER_GLOBS:
        found = sorted(glob.glob(pattern))
        if found:
            return found[-1]
    return None


def render(browser, path):
    with open(path, encoding="utf-8") as handle:
        page = handle.read()
    holder = tempfile.mkdtemp(prefix="ovation-draws-")
    probed = os.path.join(holder, "probed.html")
    with open(probed, "w", encoding="utf-8") as handle:
        handle.write(page + PROBE)
    try:
        done = subprocess.run(
            [browser, "--headless", "--disable-gpu", "--virtual-time-budget=6000",
             "--window-size=1440,1200", "--dump-dom", "file://" + probed],
            capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as err:
        fail("the browser could not render the page: %s" % err, 3)
    found = re.search(r'<pre id="ovation-probe">(.*?)</pre>', done.stdout, re.S)
    if not found:
        fail("the page rendered but the probe wrote nothing, so nothing was measured "
             "(browser exit %d)" % done.returncode, 3)
    body = found.group(1).replace("&quot;", '"').replace("&lt;", "<")
    body = body.replace("&gt;", ">").replace("&amp;", "&")
    try:
        return json.loads(body)
    except ValueError as err:
        fail("the probe's report could not be read: %s" % err, 3)


def main(argv):
    if len(argv) > 2:
        fail(__doc__.strip().splitlines()[2].strip())
    path = argv[1] if len(argv) == 2 else DEFAULT_FILE
    if not os.path.isfile(path):
        fail("the design file is not there: %s" % path)

    browser = find_browser()
    if browser is None:
        print("CANNOT MEASURE: no headless browser found. This check renders the design "
              "file and reads back what it drew, so with nothing to render it in there "
              "is no answer to give, and reporting one would be a green tick over an "
              "unrun check.")
        print("  Install one with: npx playwright install chromium")
        print("  Or name one:      OVATION_HEADLESS_BROWSER=/path/to/chrome")
        return 3

    report = render(browser, path)
    claims = report.get("claims", {})
    if not claims:
        fail("the probe reported no claims at all, so nothing was measured", 3)

    print("Rendered %s in %s" % (os.path.relpath(path, REPO), os.path.basename(browser)))
    broken = []
    for name, outcome in claims.items():
        mark = "ok  " if outcome.get("ok") else "FAIL"
        print("  %s %s: %s" % (mark, name, outcome.get("saw")))
        if not outcome.get("ok"):
            broken.append(name)
    for line in report.get("errors", []):
        print("  FAIL " + line)
        broken.append(line)

    if broken:
        print("\nREFUSED: %d of %d claims about what this file DRAWS did not hold."
              % (len(broken), len(claims)))
        return 1
    print("\nOK: all %d claims about what this file draws held." % len(claims))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
