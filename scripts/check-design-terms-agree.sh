#!/usr/bin/env python3
"""Refuse a design record whose two payment term lists have drifted apart.

    check-design-terms-agree.sh [clients file] [invoice file]

ovation#98 round D, ovation#111 round C. PRD 51h settled that a client's
STANDING terms are set on the Clients screen and never on an invoice, and that
an invoice's OWN due date is changed in its foot. Both offer the same four
terms, and in the product that is one constant: a client whose standing terms
offer 21 days, against an invoice screen that cannot produce one, is two
vocabularies for a single thing and the person meets whichever screen they
opened.

WHY IT IS TWO COPIES AT ALL. A design file must be one self contained document
that reaches outside itself never (ovation#114), so neither file can load a
shared list, and each carries its own. Two copies of one list with nothing
comparing them is L370, and it has already gone wrong in this folder once: a
rule was fixed in `rules/time-field.js` and left stale in the design file that
carries a copy of it, and the suite stayed green because the suite reads
`rules/`. `check-design-rules-inline.sh` is the answer to that one; this is the
same answer for the terms.

THE CLAIM THIS DEFENDS WAS MADE WHILE THE DESIGN WAS BEING CHOSEN. Round D's
readout told Dan the two lists are read from one place so they can never come
to offer different terms. That was not true on the day it was said, because
nothing compared them, and a constraint recorded only as a sentence is enforced
by nothing (L407).

IT COMPARES THE LIST, IN ORDER. Two files holding the same four terms in a
different order are not the same list to the person reading them: they are
choosing from a menu, and the order is what they scan. So the order is part of
the claim rather than a detail (L228).

IT READS THE DECLARATIONS, NOT THE RENDERING, and that is a deliberate limit
rather than an oversight. What is drawn is covered by the checks that render:
this one exists to catch the two constants drifting, which is a source fault and
is invisible in a rendering of either file ALONE, since each looks perfectly
correct on its own.

Exit codes, one per outcome (L11):

    0  the two lists agree
    1  they disagree, and it says which term and which file
    2  it could not measure: a file it cannot read, or one declaring no terms
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DEFAULTS = [os.path.join(ROOT, "docs/design/clients.html"),
            os.path.join(ROOT, "docs/design/invoice.html")]

# The two files declare the same list in two shapes, because they need different
# things from it: the Clients screen shows a label, the invoice screen also has
# to turn each term into a date. So the LABELS are what is compared, and each
# shape is read by its own pattern rather than by one loose pattern that would
# have to accept both and would then accept a third nobody intended.
SHAPES = [
    # var TERMS = ["On receipt", "7 days", "14 days", "30 days"];
    re.compile(r'var\s+TERMS\s*=\s*\[\s*((?:"[^"]*"\s*,?\s*)+)\]\s*;'),
    # var TERMS = [["On receipt", 0], ["7 days", 7], ...];
    re.compile(r'var\s+TERMS\s*=\s*\[\s*((?:\[\s*"[^"]*"\s*,\s*-?\d+\s*\]\s*,?\s*)+)\]\s*;'),
]

LABEL = re.compile(r'"([^"]*)"')


def terms_in(path):
    """The ordered labels this file offers, or a reason it could not be read."""
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as why:
        return None, "cannot read %s: %s" % (path, why.strerror or why)

    for shape in SHAPES:
        found = shape.search(text)
        if found:
            return LABEL.findall(found.group(1)), None
    return None, "%s declares no payment terms this can read" % path


def main(argv):
    paths = argv[1:] or DEFAULTS
    if len(paths) != 2:
        print("usage: check-design-terms-agree.sh [clients file] [invoice file]")
        return 2

    lists = []
    for path in paths:
        terms, why = terms_in(path)
        if terms is None:
            print("CANNOT MEASURE: %s" % why)
            return 2
        if not terms:
            print("CANNOT MEASURE: %s declares no payment terms" % path)
            return 2
        lists.append(terms)

    left, right = lists
    if left == right:
        print("PASS: both files offer the same %d terms, in order: %s"
              % (len(left), ", ".join(left)))
        return 0

    # WHICH TERM, AND WHICH FILE. "They differ" sends whoever reads this back to
    # diffing two 2,000 line files by hand.
    print("REFUSED: the two design files do not offer the same payment terms.")
    for path, mine, theirs in ((paths[0], left, right), (paths[1], right, left)):
        only = [t for t in mine if t not in theirs]
        if only:
            print("  only in %s: %s" % (os.path.basename(path), ", ".join(only)))
    if sorted(left) == sorted(right):
        print("  same terms, different order:")
        print("    %s: %s" % (os.path.basename(paths[0]), ", ".join(left)))
        print("    %s: %s" % (os.path.basename(paths[1]), ", ".join(right)))
    print("  PRD 51h makes these one list. Change both, or neither.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
