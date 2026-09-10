#!/usr/bin/env python3
"""Refuse a second hand rolled copy of a component the design record shares.

    check-design-shared-components.sh [design file ...]

ovation#149. Rounds A to D of ovation#111 produced one popup list, `.poplist`,
used twice: the service types hang off a line's description cell and the due
date's terms hang off the foot. It was built as TWO, `.typelist` and `.duelist`,
and merged in the same change rather than left as a cleanup.

The component shipped without the guard that keeps it the only one. A shared
component created to end N copies converts the site in front of whoever built it
and leaves the rest standing, and the next screen either copies it by eye or
invents its own (L613). The receipts queue (ovation#100), the review and send
screen (ovation#101) and the Clients screen (ovation#98) are all still to be
drawn, and each of them will want a short list of choices.

A RULE IN THE RECORD WOULD BE FOLLOWED BY WHOEVER READ IT (L27), which is why
this is a scan.

HOW A COMPONENT IS RECOGNISED. Not by its name, which is the thing a second copy
changes, but by its SHAPE: for the popup list, a class that positions itself
absolutely and has rules for the choices inside it. That is what a hand rolled
copy would have to declare in order to work at all, whatever it called itself.
Measured across the committed record on 2026-09-09: exactly one class matches,
and it is `.poplist`.

THE TABLE IS THE DATA AND IT IS NOT EMPTY. A guard whose list of subjects starts
empty ships inert, and an empty list is a legitimate value meaning "no
components are shared", so nothing can tell the two apart (L543). It starts with
the one component that exists.

Exit codes, one per outcome (L11):

    0  every design file uses the shared component and defines no second one
    1  a second implementation of a shared component is declared
    2  nothing was scanned, which is not a pass

Seam: OVATION_DESIGN_ROOT.
"""
import glob
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs/design")

STYLE_BLOCK = re.compile(r"<style\b[^>]*>(.*?)</style>", re.S | re.I)
SCRIPT_BLOCK = re.compile(r"<script\b[^>]*>.*?</script>", re.S | re.I)
CSS_COMMENT = re.compile(r"/\*.*?\*/", re.S)
RULE = re.compile(r"([^{}]+)\{([^{}]*)\}")

# One entry per component the record shares. Each names the class that owns it,
# and the SHAPE by which a second copy is recognised whatever it calls itself.
SHARED = [
    {
        "what": "a popup list of choices",
        "owner": "poplist",
        "declares": ("position: absolute",),
        "holds": ("button", "li", "a"),
        "why": ("Rounds A to D of ovation#111 built two of these, `.typelist` "
                "and `.duelist`, and merged them into `.poplist` in the same "
                "change. Three screens still to be drawn each want a short list "
                "of choices."),
    },
]


def stylesheets(text):
    """The page's own stylesheets, with script bodies removed first so a second
    document carried inside a string is not read as this page's CSS."""
    scriptless = SCRIPT_BLOCK.sub(" ", text)
    return CSS_COMMENT.sub(" ", "\n".join(STYLE_BLOCK.findall(scriptless)))


def rules(css):
    for found in RULE.finditer(css):
        selector = " ".join(found.group(1).split())
        if selector.startswith("@"):
            continue
        yield selector, " ".join(found.group(2).split())


def implementations(text, component):
    """Every class in this file that is shaped like the component."""
    css = stylesheets(text)
    positioned, holding = {}, {}
    for selector, body in rules(css):
        squashed = body.replace(" ", "")
        for owner in re.findall(r"(?:^|,\s*)\.([A-Za-z][\w-]*)", selector):
            if any(d.replace(" ", "") in squashed for d in component["declares"]):
                positioned[owner] = selector
        match = re.match(r"^\.([A-Za-z][\w-]*)\s+(\w+)", selector)
        if match and match.group(2) in component["holds"]:
            holding.setdefault(match.group(1), selector)
    return sorted(set(positioned) & set(holding))


def main(argv):
    files = argv[1:]
    if not files:
        files = sorted(glob.glob(os.path.join(DEFAULT_ROOT, "*.html")))
        if not files:
            print("CANNOT MEASURE: no design file under %s, so nothing was "
                  "scanned and a pass here would be a green tick over an unrun "
                  "check." % DEFAULT_ROOT)
            return 2
    for path in files:
        if not os.path.isfile(path):
            print("CANNOT MEASURE: no such design file: %s" % path)
            return 2
    if not SHARED:
        print("CANNOT MEASURE: no component is declared shared, so this scanned "
              "for nothing. An empty list is a legitimate value meaning no "
              "component is shared, and it must not report the same thing.")
        return 2

    found = 0
    faults = []
    for path in files:
        text = open(path, encoding="utf-8").read()
        name = os.path.basename(path)
        for component in SHARED:
            here = implementations(text, component)
            for owner in here:
                if owner == component["owner"]:
                    found += 1
                else:
                    faults.append((name, component, owner))

    for name, component, owner in faults:
        print("  %s: `.%s` is %s and is not the shared one, `.%s`."
              % (name, owner, component["what"], component["owner"]))
        print("     %s" % component["why"])
    if faults:
        print("REFUSED: %d second implementation(s) of a shared component, "
              "across %d design file(s). Use the shared one, or, if this really "
              "is a different thing, give it a shape that says so."
              % (len(faults), len(files)))
        return 1
    print("OK: %d design file(s) scanned for %d shared component(s), %d use(s) "
          "of the shared one and no second implementation."
          % (len(files), len(SHARED), found))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
