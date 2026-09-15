#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Write invoice-pdf.html back into review-send.html's embedded page.

    write-design-embedded-page.sh [--check]

ovation#167. The remedy scripts/check-design-embedded-page.sh names. A guard that
finds drift and leaves the remedy to hand copying makes the next drift a matter
of whoever is tired, and a remedy nothing executes is never tested (L406), so
this is run by its suite, test-write-design-embedded-page.sh.

It builds the page through scripts/lib/design_embedded.py, the same definition
the checker judges by, and rewrites only the one line holding PDF_PAGE. The
host's own preview invoice is taken from the page already there and kept.

Exit codes, one per outcome (L11):

    0  the embedded page is in step, whether or not anything was written
    1  an anchor is lost, so nothing was written
    2  used wrongly, or there is nothing to write
    3  --check only: the page has drifted and would be rewritten

It never prints the page, only file names and what could not be found.

Seam: OVATION_DESIGN_ROOT.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_embedded import HOST, judge  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")


def main(argv):
    if argv not in ([], ["--check"]):
        print("usage: write-design-embedded-page.sh [--check]")
        return 2
    check_only = argv == ["--check"]
    state, sentence, new_text = judge(ROOT)
    if state == "in step":
        print("IN STEP: " + sentence + ". Nothing to write.")
        return 0
    if state == "nothing":
        print("NOTHING TO WRITE: " + sentence + ".")
        return 2
    if state == "refused":
        print("REFUSED: " + sentence + ". Nothing was written.")
        return 1
    if check_only:
        print("DRIFTED: " + sentence + ". Run without --check to write it.")
        return 3
    with open(os.path.join(ROOT, HOST), "w", encoding="utf-8") as fh:
        fh.write(new_text)
    print("WROTE: %s now carries %s as it stands." % (HOST, "invoice-pdf.html"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
