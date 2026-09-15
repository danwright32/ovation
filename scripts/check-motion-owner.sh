#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse an animation written anywhere but the one file that owns motion.

    check-motion-owner.sh [--list]

ovation#124. The invoice screen settled Ovation's first animation, a 280ms slide
on `cubic-bezier(.32,.72,0,1)`, and nothing recorded how movement works. Both
halves of that gap are now closed: the design record's Motion section says what
the transitions are, and `Ovation/Roster/OvationMotion.swift` holds the durations,
the curve and the reading of the environment's `accessibilityReduceMotion`.

THIS IS THE HALF THAT MAKES THE COMPONENT TRUE. A rule saying "go through the
component" lives in a document and is followed by whoever read it (L27), and a
behaviour every call site has to opt into cannot be enforced by asking (L621). So
the tree is scanned and an animation outside the owner is a refusal.

REDUCE MOTION IS WHY THIS ONE IS WORTH A SCANNER AND THE PALETTE IS NOT. A colour
written by hand is visible to anybody who looks at the screen. A transition that
skipped the reduce motion answer looks perfect to everybody who could report it:
the person who asked their Mac to reduce motion is not the person building the
screen, and no test they run goes red. The failure is silent by construction,
which is the shape a guard exists for.

TWO FINDINGS, NOT ONE, because distinct causes need distinct messages (L11). An
animation written on a screen is one mistake. A screen reading
`accessibilityReduceMotion` for itself is a different one: it is how a second,
quieter answer to the same question gets written, and the two then disagree about
one transition with each call site reading as correct alone (L83).

A REFUSAL WITH NO REMEDY IS NOT A GUARD (L54, L109). Everything refused here has
a route through the component: `.ovationMotion(_:value:)` for a change that
follows a value, and `@Environment(\\.ovationMotion)` with `run(_:_:)` for a
change a press makes. So the rule costs a call site nothing but the spelling.

THE OWNER IS A SUBJECT, NOT AN EXEMPTION, and that is the difference between this
and an allowlist. `check-forbidden-constructs.sh` rules a construct OUT and its
allowlist is a concession, deliberately empty. Here the construct is ruled IN, in
exactly one place, so the owner is named rather than excused, and an owner that is
absent or that holds no motion is a refusal of its own: a scanner that finds no
animation anywhere because the component was deleted reports precisely what a
clean tree reports (L98).

WHAT COUNTS AS WRITING MOTION is a token in code rather than in a comment or a
string, matched at a word boundary, so `withAnimationDisabled` is not
`withAnimation` and a line explaining the rule is not the rule's first violation
(L245, L361). The comment stripping and string blanking belong to
check-forbidden-constructs.sh and are loaded rather than copied: two copies of the
parts most easily got subtly wrong is not consolidation (L370).

The known gap, stated rather than discovered: a screen could animate through a
helper of its own that this list does not name, for instance by building an
`Animation` value in some other way and passing it about. The alternative to that
is a Swift parser, and the tokens below are every way SwiftUI actually offers.

WHAT IT NEVER PRINTS: the source line. The file, the line number and the
construct only. A comment on an animation line is as good a place for a client's
name as any other (L222).

Seams: OVATION_MOTION_SCAN_ROOT, OVATION_MOTION_OWNER.

Exit codes, one per outcome (L11):
    0  motion is written in the owner and nowhere else
    1  an animation, or the reduce motion answer, is written outside it
    2  nothing was scanned: no root, or no Swift files under it
    3  the owner is not there, or holds no motion, so nothing was being owned
"""
import importlib.machinery
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Loaded rather than copied (L370): one comment stripper, one string blanker.
_constructs = importlib.machinery.SourceFileLoader(
    "forbidden_constructs", os.path.join(HERE, "check-forbidden-constructs.sh")).load_module()

# The file that owns motion, relative to the scan root.
DEFAULT_OWNER = os.path.join("Roster", "OvationMotion.swift")

# Every way SwiftUI offers to start an animation. The suite drives this list
# rather than restating it, so a token added here is exercised without anybody
# remembering to come back, and a construct cannot be forbidden by a rule nothing
# tests (L41, L217).
MOTION_TOKENS = (
    "withAnimation",
    "withTransaction",
    "animation",
    "transition",
    "matchedGeometryEffect",
    "phaseAnimator",
    "keyframeAnimator",
    "contentTransition",
)

# The setting itself. Its own finding, with its own sentence.
SETTING_TOKENS = ("accessibilityReduceMotion",)

MOTION_PATTERN = re.compile(r"\b(" + "|".join(MOTION_TOKENS) + r")\s*\(")
SETTING_PATTERN = re.compile(r"\b(" + "|".join(SETTING_TOKENS) + r")\b")

MOTION_BECAUSE = (
    "motion written outside the component: Ovation has one slide and one fade, "
    "280ms on cubic-bezier(.32,.72,0,1) and 120ms linear, and one place that "
    "knows whether the person asked their Mac to reduce motion (ovation#124). A "
    "transition written here answers that question for itself, or forgets it, and "
    "nobody who could report it can see the difference. Use "
    "`.ovationMotion(_:value:)`, or `@Environment(\\.ovationMotion)` and "
    "`run(_:_:)` for a change a press makes."
)
SETTING_BECAUSE = (
    "the reduce motion answer read outside the component: OvationMotion reads it "
    "so that one place decides what reduced motion means, and a second reader is "
    "a second answer that drifts from the first while both read as correct "
    "(ovation#124, L83). Ask the component for the animation instead."
)


def code_of(path):
    """The file's code with comments removed and string contents blanked, so a
    construct named in prose or spelled inside a sentence is not a use of it."""
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    return _constructs.blank_strings(
        "\n".join(text for _, text in _constructs.strip_comments(lines)))


def findings_in(code):
    """(line number, construct, which rule) for everything this file writes."""
    found = []
    for pattern, rule in ((MOTION_PATTERN, "motion"), (SETTING_PATTERN, "setting")):
        for match in pattern.finditer(code):
            found.append((code.count("\n", 0, match.start()) + 1, match.group(1), rule))
    return sorted(found)


def main(argv):
    if "--list" in argv:
        for token in MOTION_TOKENS + SETTING_TOKENS:
            print(token)
        return 0

    repo_root = os.path.dirname(HERE)
    root = os.environ.get("OVATION_MOTION_SCAN_ROOT") or os.path.join(repo_root, "Ovation")
    owner = os.environ.get("OVATION_MOTION_OWNER") or DEFAULT_OWNER

    if not os.path.isdir(root):
        print(f"CANNOT SCAN: {root} is not a directory, so nothing was checked.")
        print("             That is not a pass. Point OVATION_MOTION_SCAN_ROOT at the sources.")
        return 2

    sources = {}
    for directory, _, filenames in os.walk(root):
        for filename in sorted(filenames):
            if filename.endswith(".swift"):
                path = os.path.join(directory, filename)
                sources[os.path.relpath(path, root)] = code_of(path)

    if not sources:
        print(f"CANNOT SCAN: no Swift files under {root}.")
        print("             That is not a pass: a scanner with nothing to read reports")
        print("             exactly what a clean tree does.")
        return 2

    # THE OWNER IS CHECKED BEFORE THE TREE IS JUDGED. Without it there is no
    # component, so every screen is correct by having nothing to go through, and
    # this check passes hardest when the thing it defends has been deleted (L98).
    if owner not in sources:
        print(f"CANNOT SCAN: {owner}, the file that owns motion, is not there under {root}.")
        print("             Nothing was being owned, so a tree with no animation in it")
        print("             cannot be told from one that lost its component (ovation#124).")
        return 3
    if not findings_in(sources[owner]):
        print(f"CANNOT SCAN: {owner} holds no motion at all.")
        print("             It is the file every screen is made to go through, so an empty")
        print("             one means the motion moved and this check is defending nothing.")
        return 3

    findings = []
    for relative, code in sorted(sources.items()):
        if relative == owner:
            continue
        for line, token, rule in findings_in(code):
            findings.append((relative, line, token, rule))

    if findings:
        print(f"FOUND: motion written outside {owner}, in {len(sources)} scanned file(s).")
        for relative, line, token, rule in findings:
            print(f"  {relative}:{line}: {token}")
        # A sentence per rule that actually fired. A rule nobody tripped says
        # nothing, and two different mistakes are two findings (L11).
        if any(rule == "motion" for _, _, _, rule in findings):
            print(MOTION_BECAUSE)
        if any(rule == "setting" for _, _, _, rule in findings):
            print(SETTING_BECAUSE)
        print(f"{len(findings)} occurrence(s).")
        return 1

    print(f"OK: scanned {len(sources)} Swift file(s) under {root}: motion is written "
          f"in {owner} and nowhere else.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
