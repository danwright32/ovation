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

Usage: check-collisions.py <settled.css> <round.css> [--reuse a,b,c]
"""
import re, sys

def classes(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return set(re.findall(r"\.([A-Za-z][A-Za-z0-9_-]*)", text))

def main(argv):
    if len(argv) < 3:
        print("usage: check-collisions.py <settled.css> <round.css> [--reuse a,b,c]")
        return 2
    settled, own = argv[1], argv[2]
    reuse = set()
    if "--reuse" in argv:
        reuse = {c.strip() for c in argv[argv.index("--reuse") + 1].split(",") if c.strip()}
    a = classes(open(settled).read())
    b = classes(open(own).read())
    clash = sorted((a & b) - reuse)
    if clash:
        print("COLLISION: these class names are already defined in the settled stylesheet,")
        print("so the settled rules reach the round's own elements:")
        for c in clash:
            print("  ." + c)
        print("\nRename them, or declare them with --reuse if the inheritance is deliberate.")
        return 1
    print("no collisions (%d classes in the round, %d deliberate reuses)" % (len(b), len(reuse)))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
