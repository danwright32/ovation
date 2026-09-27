#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a second chip treatment for the tax status question.

    check-one-tax-chip.sh

ovation#480, PRD 5a2. Two screens ask Dan the same question, "is this client
tax exempt", and until 2026-09-26 each drew its two answers its own way: the
roster pass with the Clients record's `.chip`, the invoice screen with the
invoice record's `.taxpick`. Dan chose by looking, with both drawn on both
screens in the real windows, and answered "Invoice chip". So there is one
component, `TaxAnswerChips`, and one look, `invoice.html`'s `.taxpick`.

A shared component that converts the sites in front of whoever built it and
leaves the next screen free to draw its own is not consolidation (L613). The
Clients screen's correction of a status (PRD 51j1) is the third place this
question is asked, and it is not built yet, so this is a scan rather than a
note. `scripts/check-one-action-word.sh` is the shape it follows.

TWO HALVES, because the question is drawn in two places.

IN THE APP'S SWIFT, a copy is recognised by what it has to do to exist at all:
draw the answers itself, which means a `ForEach` over a list of tax answers,
reached as `TaxStatus.answers`, `TaxStatus.allCases`, or a question's own
`answers`. Not by the chip's geometry, which other controls share on purpose
(the discount line and the payment sheet use the same rounded, ruled box), so a
guard keyed on it would accuse them and be learned to be skipped. The allowed
file is one, `TaxAnswerChips.swift`, and it must still draw the answers that
way itself, or the guard would be exempting a file that no longer does the job.

IN THE DESIGN RECORD, the look is `.taxpick`, owned by `invoice.html`, and any
other design file that carries it must carry its three rules (the chip, its
hover, its focus ring) exactly as the owner does, compared with spacing
normalised. And the roster's retired `.chip` may not come back as a rule in
any design file. That half IS keyed on a name, and says so: it is the name of
the treatment this decision retired, and a return under the same name is the
likeliest way for it to come back. Prose that merely mentions chips, such as
the invoice list's record of dropping its group chips, is a comment and is not
read.

Exit codes, one per outcome (L11):

    0  one chip, in the app and in the design record
    1  a second treatment, a drifted copy, or an owner that no longer carries
       the shape, which leaves every other file exempt by accident

Seam: OVATION_REPO_ROOT, so the suite drives this over staged trees (L1, L2).
"""
import glob
import os
import re
import sys

REPO = os.environ.get("OVATION_REPO_ROOT") or os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))
OWNER = "Ovation/Invoices/TaxAnswerChips.swift"
DESIGN_OWNER = "docs/design/invoice.html"

# A hand drawn pair: a ForEach over the tax answers, however they are reached.
DRAWS_ANSWERS = re.compile(
    r"ForEach\(\s*(?:TaxStatus\.(?:answers|allCases)\b|[A-Za-z_][\w.]*\.answers\b|answers\b)")

STYLE = re.compile(r"<style\b[^>]*>(.*?)</style>", re.S | re.I)
SCRIPT = re.compile(r"<script\b[^>]*>.*?</script>", re.S | re.I)
COMMENT = re.compile(r"/\*.*?\*/", re.S)
RULE = re.compile(r"([^{}]+)\{([^{}]*)\}")
CHIP_RULES = (".taxpick", ".taxpick:hover", ".taxpick:focus-visible")
RETIRED = re.compile(r"(?:^|[\s,>+~])\.chip(?![\w-])")


def css_rules(text):
    """Selector and body of every rule in the page's own stylesheets. Scripts are
    removed first, so a page carried inside a string is not read as this one."""
    css = COMMENT.sub(" ", "\n".join(STYLE.findall(SCRIPT.sub(" ", text))))
    for found in RULE.finditer(css):
        selector = " ".join(found.group(1).split())
        if selector.startswith("@"):
            continue
        yield selector, " ".join(found.group(2).replace(";", "; ").split()).rstrip("; ")


def chip_look(text):
    """The three rules of the chip, by selector, as this file writes them."""
    look = {}
    for selector, body in css_rules(text):
        for part in (p.strip() for p in selector.split(",")):
            if part in CHIP_RULES:
                look[part] = body
    return look


def read(rel):
    with open(os.path.join(REPO, rel), encoding="utf-8", errors="replace") as handle:
        return handle.read()


def main():
    faults = []

    # ------------------------------------------------------------- the app
    owner_path = os.path.join(REPO, OWNER)
    if not os.path.isfile(owner_path):
        print("REFUSED: %s is not there, so this guard is checking nothing." % OWNER)
        print("    It names the one file allowed to draw the tax status answers.")
        return 1
    if not DRAWS_ANSWERS.search(read(OWNER)):
        print("REFUSED: %s no longer draws the answers with a ForEach over them, so the" % OWNER)
        print("         shape this guard recognises is not there and every other file is")
        print("         now exempt by accident. Either the component moved or the idiom")
        print("         changed; say which, here.")
        return 1

    copies = []
    for path in sorted(glob.glob(os.path.join(REPO, "Ovation", "**", "*.swift"), recursive=True)):
        rel = os.path.relpath(path, REPO)
        if rel == OWNER:
            continue
        for number, line in enumerate(read(rel).splitlines(), 1):
            if DRAWS_ANSWERS.search(line.split("//", 1)[0]):
                copies.append("    %s:%d" % (rel, number))
    if copies:
        faults.append(["REFUSED: a second hand drawn chip for the tax status question.",
                       "         Its answers are TaxAnswerChips and nothing else, so the two",
                       "         screens asking it cannot drift apart again (ovation#480)."]
                      + copies
                      + ["         Use TaxAnswerChips(answers:press:) instead."])

    # ------------------------------------------------------ the design record
    owner_design = os.path.join(REPO, DESIGN_OWNER)
    look = chip_look(read(DESIGN_OWNER)) if os.path.isfile(owner_design) else {}
    missing = [r for r in CHIP_RULES if r not in look]
    if missing:
        print("REFUSED: %s does not define %s, so the look every other design file is"
              % (DESIGN_OWNER, ", ".join(missing)))
        print("         compared against is not there, and every copy is exempt by accident.")
        return 1

    drifted, retired = [], []
    for path in sorted(glob.glob(os.path.join(REPO, "docs", "design", "*.html"))):
        rel = os.path.relpath(path, REPO)
        name = os.path.basename(path)
        text = read(rel)
        for selector, _ in css_rules(text):
            if RETIRED.search(" " + selector):
                retired.append("    %s: %s" % (name, selector))
        if rel == DESIGN_OWNER:
            continue
        here = chip_look(text)
        if not here:
            continue
        for rule in CHIP_RULES:
            if here.get(rule) != look[rule]:
                drifted.append("    %s: %s is not %s's" % (name, rule, os.path.basename(DESIGN_OWNER)))
    if drifted:
        faults.append(["REFUSED: a design file draws the tax status chip differently from %s."
                       % os.path.basename(DESIGN_OWNER),
                       "         Carry its three rules exactly, or the two screens that ask the",
                       "         question look different again (ovation#480)."] + drifted)
    if retired:
        faults.append(["REFUSED: the roster's own chip, retired by ovation#480, is back as a rule.",
                       "         The tax status answers are drawn with .taxpick."] + retired)

    if faults:
        for block in faults:
            print("\n".join(block))
        return 1

    print("OK: one tax status chip. In the app it is %s; in the design record it is"
          % OWNER)
    print("    .taxpick, as %s defines it." % os.path.basename(DESIGN_OWNER))
    return 0


if __name__ == "__main__":
    sys.exit(main())
