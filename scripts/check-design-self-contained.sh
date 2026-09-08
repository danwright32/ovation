#!/usr/bin/env python3
"""Refuse a design file that reaches outside itself.

ovation#114. `docs/design/README.md` states, as the reason the design record is
durable, that the design files make ZERO network requests: the typefaces are
embedded as base64 so a file "renders identically with no internet, forever".
That was true when it was written and nothing enforced it.

A `<link>` to Google Fonts added by anyone, at any point, would make the claim
false with no symptom whatsoever. The file goes on rendering perfectly on a
machine with a network, and only fails years later, offline, which is precisely
the scenario the embedding exists for. A documented claim with no test behind it
is a claim nobody is checking (L32).

WHY IT IS WORTH MORE THAN THE ONE FILE IT STARTS ON. The design record is the
artefact the whole design process produces, and its value is that it outlives
whatever rendered it. There are five such files today and at least three more
coming (ovation#100, ovation#101, ovation#131).

TWO THINGS ARE REFUSED, and they are different failures with the same remedy.
A NETWORK reference stops the file rendering offline. A reference to another
FILE, even a local one, stops it being ONE file: the record is a single document
that opens in any browser from anywhere, and a design file that needs a sibling
on disk is no longer that. Anything shared between design files (ovation#120)
therefore has to be inlined when the file is built, not linked at render time.

THE SUBTLETY THAT WOULD OTHERWISE BITE. A base64 font payload contains long runs
that look like protocol relative URLs, so a naive search for `//` matches
thousands of times inside a perfectly healthy file. Every needle below therefore
contains a character that is NOT in the base64 alphabet (`A-Za-z0-9+/=`): a
quote, a bracket, an `@` or a `:` in a scheme. That is what makes the scan exact
rather than heuristic, and it is the reason the needles are shaped as they are.

WHAT IS NOT SCANNED, with the reason, because an exclusion carrying none is
indistinguishable from an oversight (L233):
    README.md    prose ABOUT the record rather than part of it, and prose
                 legitimately cites a URL.
    *.png        binary, and an image carries no references of its own.

NOTHING SCANNED IS NOT A PASS (L98). There are fifteen scannable files today, so a
scan finding none has stopped working rather than found a clean tree.

Seam: OVATION_DESIGN_ROOT.

Exit codes, one per outcome (L11):
    0  every design file is self contained
    1  a design file reaches outside itself
    2  nothing was scanned: no directory, or no files under it
"""
import os
import re
import sys

# A URL bearing attribute. The quote is what makes this safe inside a base64
# payload: `src=` can occur there by chance, `src="` cannot, because a quote is
# not in the base64 alphabet.
ATTRIBUTE = re.compile(
    r"""\b(src|href|data|srcset|poster|xlink:href)\s*=\s*(["'])(.*?)\2""",
    re.IGNORECASE | re.DOTALL)
# CSS. `(` and `@` are both outside the base64 alphabet.
CSS_URL = re.compile(r"""\burl\(\s*(["']?)([^)'"]*)\1\s*\)""", re.IGNORECASE)
CSS_IMPORT = re.compile(r"@import\b", re.IGNORECASE)
# Things that fetch from script. Each needle carries a bracket or a space, so
# none can occur inside a base64 run.
FETCHERS = (
    ("fetch(", "fetch()"),
    ("XMLHttpRequest", "XMLHttpRequest"),
    ("new Worker(", "a web worker"),
    ("new SharedWorker(", "a shared worker"),
    ("importScripts(", "importScripts()"),
    ("navigator.sendBeacon", "sendBeacon()"),
    ("new EventSource(", "an event source"),
    ("new WebSocket(", "a web socket"),
    ("serviceWorker.register", "a service worker"),
)

# A value that fetches nothing and needs nothing on disk.
INLINE_SCHEMES = ("data:", "#", "about:blank", "javascript:void")

SCANNABLE = (".html", ".htm", ".css", ".js", ".svg")
NOT_SCANNED = {"README.md"}


def is_inline(value):
    value = value.strip()
    if value == "":
        return True
    return any(value.lower().startswith(scheme) for scheme in INLINE_SCHEMES)


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def findings_in(text):
    """Every place this file reaches outside itself, as (line, what, why)."""
    found = []
    for match in ATTRIBUTE.finditer(text):
        value = match.group(3)
        if is_inline(value):
            continue
        found.append((line_of(text, match.start()),
                      f"{match.group(1).lower()}=", classify(value)))
    for match in CSS_URL.finditer(text):
        value = match.group(2)
        if is_inline(value):
            continue
        found.append((line_of(text, match.start()), "url()", classify(value)))
    for match in CSS_IMPORT.finditer(text):
        found.append((line_of(text, match.start()), "@import",
                      "pulls in another stylesheet at render time"))
    for needle, name in FETCHERS:
        start = 0
        while True:
            at = text.find(needle, start)
            if at < 0:
                break
            found.append((line_of(text, at), name, "makes a request at render time"))
            start = at + len(needle)
    return sorted(found)


def classify(value):
    """WHY this reference is a problem, which is not the same in both cases."""
    lowered = value.strip().lower()
    if lowered.startswith(("http://", "https://", "//", "ftp:")):
        return "reaches the network, so the file stops rendering offline"
    return "names another file, so the file is no longer one self contained document"


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(repo_root, "docs", "design")

    if not os.path.isdir(root):
        print(f"CANNOT SCAN: {root} is not a directory, so nothing was checked.")
        print("             That is not a pass. Point OVATION_DESIGN_ROOT at the record.")
        return 2

    scanned = 0
    findings = []
    for directory, _, filenames in os.walk(root):
        for filename in sorted(filenames):
            if filename in NOT_SCANNED:
                continue
            if not filename.lower().endswith(SCANNABLE):
                continue
            path = os.path.join(directory, filename)
            relative = os.path.relpath(path, root)
            scanned += 1
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                text = handle.read()
            for line, what, why in findings_in(text):
                findings.append((relative, line, what, why))

    if scanned == 0:
        print(f"CANNOT SCAN: no design files under {root}.")
        print("             That is not a pass: a scanner with nothing to read reports")
        print("             exactly what a self contained record does.")
        return 2

    if findings:
        print(f"NOT SELF CONTAINED: {len(findings)} reference(s) "
              f"in {scanned} scanned file(s).")
        for relative, line, what, why in findings:
            print(f"  {relative}:{line}: {what}  {why}")
        print("The design record is durable because each file is one document that opens")
        print("in any browser with no network, forever. A typeface is embedded as base64")
        print("rather than linked for exactly this reason, and anything shared between")
        print("design files is inlined when the file is built, never linked at render")
        print("time. Nothing here fails visibly on a machine with a network, which is")
        print("why it is checked rather than looked at.")
        return 1

    print(f"OK: scanned {scanned} design file(s) under {root}, "
          "every one self contained.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
