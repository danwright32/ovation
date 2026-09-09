#!/usr/bin/env python3
"""Refuse a design file that names a colour token where the token is not there.

ovation#120. The palette lived on `.win` until 2026-09-08, so every rule OUTSIDE
the app window resolved `var(--anything)` to nothing. The Edit chip in the menu
bar and the highlighted row in its menu both declare `background: var(--accent)`
and both computed to `rgba(0, 0, 0, 0)`, so neither had ever painted. The fix
landed in invoice.html and not in the two older files, which carried the fault
for as long as nothing compared them.

NO SOURCE READING CAN SEE IT. Both halves are present and both are spelled
correctly: one rule defines the token, another uses it. What is wrong is the
RELATIONSHIP between their two elements at render time. A token that is
referenced but never defined leaves no error and no mark, so the declaration goes
on reading as correct (L585), and the fault is that something is NOT drawn, which
is the hardest kind to see.

So this renders every design file and asks the elements themselves. For each
declaration reading `var(--token)`, every element that rule matches must have
that token resolve to a non empty value.

WHAT IT DOES NOT CATCH, measured rather than assumed, because a check is read as
covering whatever its name suggests (L400). It would NOT have caught the fault
above. Both files were rebuilt with the palette put back on `.win` and run
through this check, and both passed: in `invoice-list.html` because nothing
outside the window names a token at all, and in `invoice.html` because the Edit
chip that named `var(--accent)` is only in the DOM while the menu is OPEN, and a
page rendered at rest does not draw it. A rule matching no element resolves
nothing, which is why those are counted and printed rather than passed over in
silence: on 2026-09-09 that was 154 rules in invoice.html, and the chip was one of
them. Closing the gap means driving each file into the states it can be in before
measuring, which is ovation#141's territory rather than this file's.

WHAT IT DOES CATCH is every token named by a rule that is drawing RIGHT NOW and
cannot see its definition, which is the same fault on the surface a person is
actually looking at.

Outcomes, each with its own wording because distinct causes need distinct
messages (L11):

    RESOLVED         every element the rule matches can see the token
    UNRESOLVED       an element the rule matches sees nothing
    DRAWN BY NOTHING the rule matches no element, so it resolved nothing at all

DRAWN BY NOTHING IS REPORTED, NOT PASSED OVER. A rule matching no element
resolves no token and would otherwise read exactly like a rule whose tokens all
resolve (L98). It is not a refusal, because a design file legitimately carries
rules for states it is not currently showing, but it is said out loud, with a
count, so a file whose rules have quietly stopped matching anything is visible.

Exit codes, so a caller can tell the outcomes apart without parsing text:

    0  every reference resolved where it is used
    1  at least one reference resolved to nothing
    2  nothing could be compared, which is not a pass
    3  no headless browser, so nothing could be rendered at all

NOTHING TO MEASURE IS NOT A PASS, and the ways of having nothing are different
faults with different remedies: no design file at all, and a file naming no token
(L98, L11). Neither is reported as health.

IT NAMES THE SELECTOR AND THE TOKEN, NEVER THE CONTENT of the element. Both are
things we wrote in a stylesheet; the text inside an element is where a client
name would be, and this prints to a terminal (docs/PRIVACY-FLOOR.md).

Seams, shared with the other design checks rather than invented again (L2):

    OVATION_DESIGN_ROOT       the design record to read
    OVATION_HEADLESS_BROWSER  the browser to render in
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_inline import html_files  # noqa: E402
from design_render import CannotMeasure, NO_BROWSER, find_browser, render  # noqa: E402

# The probe. It runs INSIDE the rendered page, walks every stylesheet rule the
# page actually loaded, and asks each matched element what the token resolved to.
#
# IT READS THE LIVE CSSOM rather than the file's text, so it sees exactly the
# rules the browser applied, including any the browser dropped as unparseable,
# which a source reading would go on counting.
PROBE = r"""
<script>
window.addEventListener("load", function () {
  var report = {references: [], unresolved: [], unmatched: []};
  function walk(rules) {
    for (var i = 0; i < rules.length; i++) {
      var rule = rules[i];
      if (rule.cssRules && rule.cssRules.length) { walk(rule.cssRules); }
      if (!rule.style || !rule.selectorText) { continue; }
      /* THE RULE'S OWN TEXT, not its enumerated properties. A shorthand given a
         var(), `background: var(--accent)`, becomes a pending substitution value
         in the CSSOM and getPropertyValue answers the empty string for it, so
         enumerating properties finds the longhands and silently misses every
         shorthand. That is exactly the declaration the original fault was on. */
      var tokens = [];
      var found = (rule.style.cssText || "").match(/var\(\s*(--[A-Za-z0-9_-]+)/g) || [];
      for (var k = 0; k < found.length; k++) {
        var name = found[k].replace(/var\(\s*/, "");
        if (tokens.indexOf(name) === -1) { tokens.push(name); }
      }
      if (!tokens.length) { continue; }
      var matched;
      try { matched = document.querySelectorAll(rule.selectorText); }
      catch (e) { continue; }
      report.references.push([rule.selectorText, tokens.length, matched.length]);
      if (!matched.length) {
        report.unmatched.push([rule.selectorText, tokens.join(" ")]);
        continue;
      }
      for (var t = 0; t < tokens.length; t++) {
        for (var m = 0; m < matched.length; m++) {
          var seen = getComputedStyle(matched[m]).getPropertyValue(tokens[t]);
          if (seen.trim() === "") {
            report.unresolved.push([rule.selectorText, tokens[t]]);
            break;
          }
        }
      }
    }
  }
  for (var s = 0; s < document.styleSheets.length; s++) {
    try { walk(document.styleSheets[s].cssRules); } catch (e) { /* cross origin */ }
  }
  var out = document.createElement("pre");
  out.id = "ovation-probe";
  out.textContent = JSON.stringify(report);
  document.body.prepend(out);
});
</script>
"""


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

    if not os.path.isdir(root):
        print(f"CANNOT SCAN: {root} is not a directory, so nothing was rendered.")
        print("             That is not a pass. Point OVATION_DESIGN_ROOT at the record.")
        return 2

    names = html_files(os.listdir(root))
    if not names:
        print(f"CANNOT SCAN: no design file under {root} to render.")
        print("             That is not a pass: a check with nothing to look at reports")
        print("             exactly what a record in perfect health reports.")
        return 2

    total_refs, unresolved, unmatched = 0, [], []
    for name in names:
        try:
            report = render(browser, os.path.join(root, name), PROBE)
        except CannotMeasure as err:
            print("CANNOT MEASURE: %s: %s" % (name, err))
            return 3
        refs = report.get("references", [])
        total_refs += sum(int(r[1]) for r in refs)
        for selector, token in report.get("unresolved", []):
            unresolved.append((name, selector, token))
        for selector, tokens in report.get("unmatched", []):
            unmatched.append((name, selector, tokens))
        print("  %s: %d rule(s) name a token, %d reference(s) in them"
              % (name, len(refs), sum(int(r[1]) for r in refs)))

    for name, selector, tokens in unmatched:
        print("  %s: DRAWN BY NOTHING, `%s` names %s and matches no element"
              % (name, selector, tokens))

    if total_refs == 0:
        print("CANNOT SCAN: not one design file names a token, so nothing was resolved.")
        print("             That is a different fault from every token resolving, and")
        print("             reporting it as health is how a check goes green over a")
        print("             page it never looked at.")
        return 2

    if unresolved:
        for name, selector, token in unresolved:
            print("  %s: UNRESOLVED, `%s` names %s and the element cannot see it"
                  % (name, selector, token))
        print("A TOKEN NAMED WHERE IT IS NOT DEFINED: %d reference(s), out of %d "
              "checked across %d design file(s)." % (len(unresolved), total_refs, len(names)))
        print("The declaration is correct and the definition exists; they are simply")
        print("not on the same branch of the page, so the browser substitutes nothing")
        print("and the thing is not drawn. Move the definition onto an ancestor of")
        print("every element that names it, which for the app palette is `.screen`.")
        return 1

    print("OK: %d token reference(s) across %d design file(s), every one resolved where "
          "it is used, %d rule(s) drawn by nothing." % (total_refs, len(names), len(unmatched)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
