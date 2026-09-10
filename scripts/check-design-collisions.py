#!/usr/bin/env python3
"""Refuse a round whose own CSS reuses a class name the settled stylesheet
already defines.

This exists because the same fault shipped four times in one day: `.nrow` was
already the Clients names column, `.disc` was already the invoice list's
disclosure row, `* { box-sizing: border-box }` was left behind entirely, and
`.inv { flex: 1 }` did not survive a copy. Each was found by looking at a
rendering and wondering why a column was the wrong width.

A collision is not always wrong: reusing `.row` or `.titlebar` on purpose is how
a round inherits the settled design. So the round declares what it means to
reuse, and anything else is refused by name.

KEEP THE REUSE LIST SHORT AND MEAN EVERY ENTRY. A list long enough to cover
whatever the round happens to define stops refusing anything, and it does so
while still printing a reassuring line. Caught here on 2026-09-07: a
retrospective run passed five rounds against a 24 entry list, and the same runs
against an empty one showed the real overlap was seven names across all five,
every one of them a deliberate inheritance of the settled shell. The long list
had not been checked, it had merely been long.

Outcomes, one per cause, because a caller cannot act on a single failure code
that means four different things (L11):

    0  no collision, and it says how many classes it actually compared
    1  a class the settled sheet already defines is redefined and not declared
    2  used wrongly: not two stylesheets, or one of them is not there
    3  the reuse list has outlived what it excused

A REUSE ENTRY NAMING A CLASS NEITHER SHEET DEFINES IS A REFUSAL, not a harmless
extra. That is the long list this file's own header warns about, one entry at a
time: an exemption stops covering the moment nobody can say what it was for, and
a list that is never pruned stops refusing anything while still printing a
reassuring line (L96, L233).

A STYLESHEET THAT IS NOT THERE IS REFUSED, never read as an empty one. An empty
settled sheet collides with nothing, so a mistyped path reports a clean round,
which is exactly what a clean round reports (L98, L320).

Usage: check-design-collisions.py <settled.css> <round.css> [--reuse a,b,c]
"""
import os
import re
import sys


def classes(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return set(re.findall(r"\.([A-Za-z][A-Za-z0-9_-]*)", text))


def main(argv):
    if len(argv) < 3:
        print("usage: check-design-collisions.py <settled.css> <round.css> "
              "[--reuse a,b,c]")
        return 2
    settled, own = argv[1], argv[2]
    for path in (settled, own):
        if not os.path.isfile(path):
            print("CANNOT COMPARE: no stylesheet at %s." % path)
            print("  That is not a clean round. An absent sheet defines nothing,")
            print("  so it collides with nothing, and a mistyped path would report")
            print("  exactly what a round with no collisions reports.")
            return 2
    reuse = set()
    if "--reuse" in argv:
        at = argv.index("--reuse") + 1
        if at >= len(argv):
            print("usage: --reuse takes a comma separated list of class names")
            return 2
        reuse = {c.strip() for c in argv[at].split(",") if c.strip()}

    settled_classes = classes(open(settled, encoding="utf-8").read())
    round_classes = classes(open(own, encoding="utf-8").read())
    clash = sorted((settled_classes & round_classes) - reuse)
    if clash:
        print("COLLISION: these class names are already defined in the settled stylesheet,")
        print("so the settled rules reach the round's own elements:")
        for name in clash:
            print("  ." + name)
        print("\nRename them, or declare them with --reuse if the inheritance is deliberate.")
        return 1

    # THE LIST IS JUDGED TOO, and it is judged after the collisions rather than
    # before, so a round with a real collision is told about the collision
    # first: that is the one that stops it shipping.
    stale = sorted(reuse - (settled_classes & round_classes))
    if stale:
        print("STALE REUSE: these are declared as deliberate inheritance and are not")
        print("collisions at all, because at least one of the two sheets does not")
        print("define them:")
        for name in stale:
            print("  ." + name)
        print("\nDrop them. A list long enough to cover whatever the round happens to")
        print("define stops refusing anything while still printing a reassuring line,")
        print("and this file has already caught that once: five rounds passed against")
        print("a 24 entry list whose real overlap was seven names.")
        return 3

    print("no collisions: %d class(es) in the round against %d in the settled "
          "sheet, %d shared and every one of them declared."
          % (len(round_classes), len(settled_classes), len(reuse)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
