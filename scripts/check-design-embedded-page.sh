#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a review-send.html whose embedded invoice page has drifted from invoice-pdf.html.

ovation#167. review-send.html carries the whole invoice PDF design as one escaped
string and runs it in a frame, so what it previews is only the settled document
while the two agree. Measured on 2026-09-14 they did not: the copy was an older
page with the blank page bug ovation#170 fixed and a phone number the design had
dropped. The page is built by scripts/lib/design_embedded.py, the one definition
the writer uses too, and scripts/write-design-embedded-page.sh is the remedy.

Exit codes, one per outcome (L11):

    0  the embedded page is invoice-pdf.html as it stands
    1  it has drifted
    2  nothing could be compared: no host, no design, or no embedded page
    4  an anchor the page is built from is lost, so no page could be built

IT NEVER PRINTS THE PAGE, only file names and what could not be found
(docs/PRIVACY-FLOOR.md).

Seam: OVATION_DESIGN_ROOT.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_embedded import judge  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")


def main():
    state, sentence, _new_text = judge(ROOT)
    if state == "in step":
        print("IN STEP: " + sentence + ".")
        return 0
    if state == "drifted":
        print("DRIFTED: " + sentence + ".")
        print("    Run scripts/write-design-embedded-page.sh to write it back in step.")
        return 1
    if state == "nothing":
        print("CANNOT MEASURE: " + sentence + ". This is not a pass.")
        return 2
    print("REFUSED: " + sentence + ".")
    print("    Nothing was built, so nothing was compared.")
    return 4


if __name__ == "__main__":
    sys.exit(main())
