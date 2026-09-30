#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a settled design decision that its own file cannot draw.

    check-design-decisions-drawn.sh

ovation#197. Twice on 2026-09-10 the state a design round was judging could not
be drawn by the file it belonged to. `clients.html` opened on a client holding
no money, so the rule about the held figure had no case until a press, and
`invoice-list.html` had no client with two open invoices, which is the whole
subject of PRD 14j. Both were found by a person building a harness. Every other
check on these files asserts things about what IS drawn, so a state that is
never drawn is invisible to all of them, and the gap is silent in exactly the
direction that reads as health.

DAN CHOSE THE SHAPE ON 2026-09-29: a claim per decision. Each settled decision
in docs/design/README.md names the file and the presses that show it, and this
renders that and refuses when it does not draw. The other shape, each file
declaring the states it can reach, was the hand kept list the issue warned goes
stale, and a list derived from a file's switches would have caught neither of
the two faults it was filed for, because both were about what the fixtures
REACH rather than what the switches declare.

A CLAIM IS ONE LINE OF THE RECORD, in the record's own voice, and the code spans
are what is parsed:

    Drawn: `invoice.html` pressing `sent` then `2 invoices open` shows `.held`.
    Drawn: `clients.html` shows `.row .fig` reading `500.00`.

`pressing` is optional and takes presses in order, each the exact words of one
drawn element, pressed where they sit; the click reaches whatever control holds
them. Words on more than one element are refused rather than the first being
pressed (L521), and `words @ selector` presses the one inside that part of the
page. `shows` is a CSS selector at least one element of which must be DRAWN,
with a box, visible and not transparent, after the last press. `reading`
additionally asks that one of them carries those words. Each press is made from
the page at rest, in a page of its own, so no claim measures what another
pressed.

WHICH DECISION A CLAIM BELONGS TO is the heading it sits under. A DECISION is a
heading carrying `settled <YYYY-MM-DD>`, which is how every settled decision in
the record is already headed, and its section runs to the next heading of the
same level or higher. A claim under another heading does not satisfy it.

WHAT IS REFUSED, AND WHAT IS ONLY COUNTED, and the line between them is the
DATE IN THE HEADING. Dan asked that the rule bind decisions recorded from now
on, not demand a backfill of the whole record in one change. So a decision
settled AFTER 2026-09-29, the day this shipped, is refused when it carries no
claim, and one settled on or before that day is listed by line under a count
that can be seen to shrink. Every claim that IS written is rendered and judged,
whatever its decision's date: a wrong claim is worse than none, since it reads
as proof.

WHAT THAT GIVES UP, said here so a pass is never read as more than it is (L400):

  * A CLAIM PROVES ITS STATE CAN BE DRAWN, never that the drawing is right. It
    says the fixture reaches the state the decision is about; whether the
    state looks as settled is still the other checks' and Dan's.
  * A DECISION WRITTEN WITHOUT `settled <date>` in its heading is not seen. The
    README says how a decision is headed, and this reads that form only.
  * A CLAIM CAN NAME A STATE BESIDE THE ONE ITS DECISION IS ABOUT. Nothing here
    can read prose well enough to say a claim is the right one.

IT NEVER QUOTES THE RECORD. A press is a fixture's words, which on the Clients
screen are a client's name, so a refusal names the line, the press by its place
and the file, and never the words (docs/PRIVACY-FLOOR.md).

Exit codes, one per outcome (L11):

    0  every claim drew, and every decision settled after 2026-09-29 has one
    1  a claim did not draw, could not be read, or a new decision has none
    2  no record, or no claim in it, so nothing was rendered, which is not a pass
    3  no browser, so nothing could be rendered at all

Seams, shared with the other design checks:

    OVATION_DESIGN_ROOT       the design record to read, README.md and its files
    OVATION_HEADLESS_BROWSER  the browser to render in
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_render import CannotMeasure, open_browser  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")

# THE DAY THE RULE BEGAN. A decision settled after it owes a claim; one settled on
# it or before is counted. It is the day ovation#197 shipped, and it is a date in
# the heading rather than a line number or a list of the old decisions' names,
# because a list of names is the hand kept register that goes stale (L41), and a
# line number moves the first time anything above it is edited.
CLAIMS_REQUIRED_AFTER = "2026-09-29"

HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
DECISION = re.compile(r"\bsettled (\d{4}-\d{2}-\d{2})\b")
CLAIM_START = "Drawn:"
CLAIM = re.compile(r"^Drawn: `([^`]+)`"
                   r"(?: pressing (`[^`]+`(?: then `[^`]+`)*))?"
                   r" shows `([^`]+)`"
                   r"(?: reading `([^`]+)`)?\.?\s*$")
PRESS = re.compile(r"`([^`]+)`")
# A file name is said back only when it is shaped like one; anything else a claim
# names is described, for the reason the header gives.
SAFE_FILE = re.compile(r"^[A-Za-z0-9._-]+\.html?$")

PROBE = r"""
<script>
window.addEventListener("load", function () {
  var claim = window.__ovationClaim, report = { presses: [], stopped: null };
  /* Case is the stylesheet's rather than the words', so it is not compared: a
     label drawn in capitals by `text-transform` is still the label written. */
  function norm(s) { return String(s || "").replace(/\s+/g, " ").trim().toLowerCase(); }
  function drawn(e) {
    var r = e.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    for (var p = e; p; p = p.parentElement) {
      var s = getComputedStyle(p);
      if (s.display === "none" || s.visibility === "hidden" || parseFloat(s.opacity) === 0) return false;
    }
    return true;
  }
  /* The INNERMOST drawn elements whose whole words are these, so a button holding
     a span is found once, by its span, and the click still reaches the button. */
  function find(words, scope) {
    var roots = scope ? [].slice.call(document.querySelectorAll(scope)) : [document.body];
    var hits = [];
    roots.forEach(function (root) {
      [].forEach.call(root.querySelectorAll("*"), function (e) {
        if (e.closest("#ovation-probe") || hits.indexOf(e) >= 0) return;
        if (norm(e.innerText) === norm(words) && drawn(e)) hits.push(e);
      });
    });
    return hits.filter(function (e) {
      return !hits.some(function (o) { return o !== e && e.contains(o); });
    });
  }
  function finish() {
    var all = [].slice.call(document.querySelectorAll(claim.shows));
    var shown = all.filter(drawn);
    report.matched = all.length;
    report.drawn = shown.length;
    if (claim.reading !== null) {
      report.reads = shown.some(function (e) { return norm(e.innerText).indexOf(norm(claim.reading)) >= 0; });
    }
    var out = document.createElement("pre");
    out.id = "ovation-probe";
    out.textContent = JSON.stringify(report);
    document.body.appendChild(out);
  }
  function press(i) {
    if (i >= claim.presses.length) { finish(); return; }
    var hits;
    try { hits = find(claim.presses[i].words, claim.presses[i].scope); }
    catch (e) { report.threw = String(e).slice(0, 120); hits = []; }
    report.presses.push({ found: hits.length });
    if (hits.length !== 1) { report.stopped = i; finish(); return; }
    hits[0].click();
    setTimeout(function () { press(i + 1); }, 30);
  }
  try { press(0); } catch (e) { report.threw = String(e).slice(0, 120); finish(); }
});
</script>
"""


def read_record(path):
    """The decisions, the claims and the unreadable claim lines, by line number."""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    headings = []
    for number, line in enumerate(lines, 1):
        found = HEADING.match(line)
        if found:
            headings.append((number, len(found.group(1)), found.group(2)))
    decisions = []
    for index, (number, level, text) in enumerate(headings):
        settled = DECISION.search(text)
        if not settled:
            continue
        end = len(lines) + 1
        for later, later_level, _ in headings[index + 1:]:
            if later_level <= level:
                end = later
                break
        decisions.append({"line": number, "date": settled.group(1), "end": end})
    claims, unreadable = [], []
    for number, line in enumerate(lines, 1):
        if not line.startswith(CLAIM_START):
            continue
        found = CLAIM.match(line)
        if not found:
            unreadable.append(number)
            continue
        presses = []
        for said in PRESS.findall(found.group(2) or ""):
            words, _, scope = said.partition(" @ ")
            presses.append({"words": " ".join(words.split()), "scope": scope.strip() or None})
        claims.append({"line": number, "file": found.group(1), "presses": presses,
                       "shows": found.group(3), "reading": found.group(4)})
    return decisions, claims, unreadable


def named(file):
    return file if SAFE_FILE.match(file) else "the file it names"


def judge(session, claim):
    """None when the claim drew, or the sentence saying why it did not."""
    path = os.path.join(ROOT, claim["file"])
    if not os.path.isfile(path):
        return "names %s, which is not a design file here" % named(claim["file"])
    report = session.render(path, PROBE, preamble="<script>window.__ovationClaim = %s;</script>"
                            % json.dumps({"presses": claim["presses"], "shows": claim["shows"],
                                          "reading": claim["reading"]}).replace("</", "<\\/"))
    where = named(claim["file"])
    if report.get("threw"):
        return "could not be judged in %s: the page threw %s" % (where, report["threw"])
    if report.get("stopped") is not None:
        which = report["stopped"]
        found = report["presses"][which]["found"]
        return ("press %d of %d found %d element(s) in %s carrying its words, and a press "
                "must find exactly one, so the state was never reached"
                % (which + 1, len(claim["presses"]), found, where))
    presses = len(claim["presses"])
    after = "after %d press(es)" % presses if presses else "at rest"
    if not report.get("drawn"):
        return ("in %s %s, its selector matched %d element(s) and drew none"
                % (where, after, report.get("matched") or 0))
    if claim["reading"] is not None and not report.get("reads"):
        return ("in %s %s, what its selector drew does not read the words the claim names"
                % (where, after))
    return None


def main():
    # THE BROWSER IS ASKED FOR FIRST, as every rendering check does, so a machine
    # with none answers 3 whatever else is wrong.
    try:
        session = open_browser()
    except CannotMeasure as why:
        print("CANNOT MEASURE: %s" % why)
        return 3

    record = os.path.join(ROOT, "README.md")
    try:
        decisions, claims, unreadable = read_record(record)
    except OSError as why:
        print("CANNOT MEASURE: no design record at %s: %s" % (record, why.strerror or why))
        return 2

    faults = []
    for number in unreadable:
        faults.append((number, "starts `%s` and cannot be read as a claim. A claim is "
                               "Drawn: `file` pressing `words` then `words` shows `selector` "
                               "reading `words`, the last two parts optional" % CLAIM_START))

    drew = 0
    for claim in claims:
        try:
            why = judge(session, claim)
        except CannotMeasure as err:
            print("CANNOT MEASURE: the claim on line %d could not be rendered: %s"
                  % (claim["line"], err))
            return 3
        if why:
            faults.append((claim["line"], why))
        else:
            drew += 1

    owing, older = [], []
    for decision in decisions:
        if any(decision["line"] < c["line"] < decision["end"] for c in claims):
            continue
        if decision["date"] > CLAIMS_REQUIRED_AFTER:
            owing.append(decision)
        else:
            older.append(decision)
    for decision in owing:
        faults.append((decision["line"], "is a decision settled %s and names no state that "
                                         "draws it. Every decision settled after %s carries "
                                         "a `Drawn:` line under its heading"
                       % (decision["date"], CLAIMS_REQUIRED_AFTER)))

    if faults:
        print("REFUSED: %d thing(s) in docs/design/README.md do not show what they claim."
              % len(faults))
        for number, why in sorted(faults):
            print("  FAIL line %d: %s." % (number, why))
        return 1

    if not claims:
        print("CANNOT MEASURE: the record carries no `Drawn:` claim at all, so nothing was "
              "rendered, and a run that judged nothing reads exactly like one that judged "
              "everything (L98).")
        return 2

    print("OK: %d claim(s) drawn, across %d decision(s) in the record."
          % (drew, len(decisions)))
    if older:
        print("    %d older decision(s), settled on or before %s, still carry no claim: %s."
              % (len(older), CLAIMS_REQUIRED_AFTER,
                 ", ".join("line %d" % d["line"] for d in older)))
    else:
        print("    0 older decision(s) carry no claim: every decision in the record says "
              "where it is drawn.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
