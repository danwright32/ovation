#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a chromeless button anywhere but the one style that gives it a hit area.

    check-whole-target.sh

ovation#615. A plain style button hit tests only what its label paints, so a
row with a clear background answers a click on its words and nothing to the
right of them. Dan met it in the rail on 2026-09-28, and the same dead space
could sit behind every one of the app's 21 plain buttons, of which only the
ones whose author happened to remember carried a content shape.

WHY A SCAN AND A STYLE, NOT A SCAN FOR THE SHAPE. Whether a given button's
label carries a content shape is a question about Swift's structure, and a
line scan reading for it would be satisfied by a shape anywhere near the button
rather than on its label (L135, L178). A behaviour each call site has to opt
into cannot be enforced by reading the call sites at all (L621). So the shape
lives in `WholeTarget`, which is the plain style with the label's content shape
added, and what this refuses is the one thing a site cannot do without to skip
it: naming a chromeless style itself (L613).

IT READS CALLS, NOT LINES (review of #644). The first version matched one line
at a time, so `.buttonStyle(` with its argument on the next line passed, and so
did `.borderless`, the other chromeless style, which hit tests the same way. A
guard matching one spelling of a construct is walked round by the next person to
write it differently (L247). So each file is read whole, with its comments and
string literals blanked out and its line breaks kept, and the patterns below
match across whitespace and line breaks. A match is reported at the line where
it starts.

WHAT COUNTS AS NAMING THE STYLE: `.buttonStyle(.plain)` and `.buttonStyle(
.borderless)` however they are spaced or broken across lines, the types
`PlainButtonStyle` and `BorderlessButtonStyle`, and `.plain as` or
`.borderless as`, which is the shorthand handed somewhere as a value.

NO SITE IS EXEMPT, and that was decided site by site rather than assumed: a
word meant to be pressed on the word has a label whose frame IS the word, so
the style costs it nothing. A future site that genuinely wants hit testing by
what is painted is a change to this file with its reason, not a quiet line.

COMMENTS AND STRINGS ARE NOT READ. Prose about the construct is not the
construct, and refusing it would refuse the explanation (L673).

THE ALLOWED LIST IS ONE FILE and it must still do the job, or every other file
is exempt by accident (L96, L98, L400).

Exit codes: 0 every chromeless button goes through the owner, 1 refused.
"""
import os
import re
import sys

# The tree to judge, overridable so the suite can drive this over a STAGED tree
# rather than only over the repository it lives in (L1, L2).
REPO_ROOT = os.environ.get("OVATION_REPO_ROOT") or os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))
OWNER = "Ovation/App/WholeTarget.swift"

CHROMELESS = re.compile(
    r"buttonStyle\(\s*\.(?:plain|borderless)\b"
    r"|\b(?:Plain|Borderless)ButtonStyle\b"
    r"|\.(?:plain|borderless)\s+as\b")
PLAIN_IN_OWNER = re.compile(r"buttonStyle\(\s*\.plain\b|\bPlainButtonStyle\b")

# Comments and string literals, in one alternation so a `//` inside a string is
# the string's and a quote inside a comment is the comment's. Multi line strings
# come first, because `"""` would otherwise read as an empty string and a quote.
PROSE = re.compile(r'"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|/\*[\s\S]*?\*/|//[^\n]*')


def blank(match):
    """Spaces for everything a match covered, line breaks kept, so offsets and
    line numbers stay where they were."""
    return re.sub(r"[^\n]", " ", match.group(0))


def code_of(text):
    return PROSE.sub(blank, text)


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def main():
    os.chdir(REPO_ROOT)
    if not os.path.isfile(OWNER):
        print("REFUSED: %s is not there, so this guard is checking nothing." % OWNER)
        print("    It names the one file allowed to use the plain button style.")
        return 1

    # The owner must still be the plain style WITH a content shape, or the guard
    # is sending every site to a style that no longer gives them one.
    owner = code_of(open(OWNER, encoding="utf-8", errors="replace").read())
    if not PLAIN_IN_OWNER.search(owner) or ".contentShape(" not in owner:
        print("REFUSED: %s no longer draws the plain style with a content shape on" % OWNER)
        print("         its label, so the style this guard sends every button to does not")
        print("         do what it is for, and every other file is now exempt by accident.")
        print("         Either the component moved or its job changed; say which, here.")
        return 1

    found = []
    for directory, _, filenames in os.walk("Ovation"):
        for filename in filenames:
            if not filename.endswith(".swift"):
                continue
            path = os.path.join(directory, filename)
            if path == OWNER:
                continue
            code = code_of(open(path, encoding="utf-8", errors="replace").read())
            for match in CHROMELESS.finditer(code):
                found.append((path, line_of(code, match.start())))

    if found:
        print("REFUSED: a chromeless button outside WholeTarget. A plain or borderless")
        print("         button hit tests only what its label paints, so a row with a clear")
        print("         background answers on its words and nowhere else (ovation#615).")
        for path, line in sorted(found):
            print("    %s:%d" % (path, line))
        print("         Use .buttonStyle(WholeTarget()), or WholeTarget(shape) where the")
        print("         label draws a shape of its own.")
        return 1

    print("OK: every chromeless button in the app's Swift takes its clicks across its label, "
          "through %s." % OWNER)
    return 0


if __name__ == "__main__":
    sys.exit(main())
