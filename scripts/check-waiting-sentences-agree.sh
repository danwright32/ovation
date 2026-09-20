#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Hold the app's refusal sentences to the design record's own words.

    check-waiting-sentences-agree.sh [waiting.js] [ReviewGate.swift]

ovation#117, PRD 51b. `docs/design/rules/waiting.js` is where the vocabulary for
what an invoice is waiting on was settled with Dan, and it says so itself: the
reason and the two sentences that carry it come from one place "so the screen
cannot say one thing where the figure is drawn and a different thing under the
main action". The app then carries its own copy in `ReviewGate.sentence`, because
Swift cannot read a JavaScript rule, and two copies of one vocabulary with
nothing comparing them is the drift that file exists to prevent (L26, L370).

IT HAD ALREADY GROWN. `waiting.js` carried five tips and `ReviewGate` carried one
of them, the tax status, typed in by hand. ovation#43 added a second and
ovation#117 adds three more, so the number of hand copies went from one to five
in two changes with nothing able to say they still agreed.

WHAT IS COMPARED IS THE LITERAL TEXT WITH ITS INTERPOLATION MASKED. Both sides
build the duration sentence from a constant rather than typing the number, which
is right, and they spell that differently: `" + CAP_HOURS + "` in JavaScript and
`\\(ShootDuration.cap...)` in Swift. Each is reduced to a single placeholder, so
the guard compares the words and leaves each language to say its own constant.
The VALUE behind those constants is held together by `ShootDurationTests`, which
reads the design's own cases, so it is not this guard's question.

ONE DIRECTION, DELIBERATELY. Every tip in the design must appear in the app. The
app may carry sentences the design has none for, and four of them do: the two
Settings refusals and the two about money are not states of waiting and
`waiting.js` has never had a word for them. A guard demanding the reverse would
be demanding the design grow entries for refusals that are not its subject.

Exit codes, one per outcome (L11):

    0  every tip in the design record appears in the app, word for word
    1  at least one tip has no match in the app
    2  nothing could be compared: a file missing, or either side holding no
       sentences at all, which is not a pass
"""
import os
import re
import sys

TIP = re.compile(r'\btip:\s*("(?:[^"\\]|\\.)*"(?:\s*\+\s*(?:[A-Za-z_][A-Za-z0-9_]*|"(?:[^"\\]|\\.)*")\s*)*)')
SWIFT_RETURN = re.compile(r'\breturn\s+("(?:[^"\\]|\\.)*"(?:\s*\n?\s*\+\s*"(?:[^"\\]|\\.)*")*)')
PLACEHOLDER = "␣"


def js_sentence(expression):
    """The words of a JavaScript string expression, with any name masked."""
    parts, out = [p.strip() for p in split_plus(expression)], []
    for part in parts:
        if part.startswith('"') and part.endswith('"'):
            out.append(unescape(part[1:-1]))
        else:
            out.append(PLACEHOLDER)
    return "".join(out)


def swift_sentence(expression):
    """The same for Swift, whose interpolation sits INSIDE the quotes."""
    out = []
    for part in split_plus(expression):
        part = part.strip()
        if not (part.startswith('"') and part.endswith('"')):
            return None
        out.append(unescape(part[1:-1]))
    joined = "".join(out)
    return re.sub(r"\\\([^)]*\)", PLACEHOLDER, joined)


def split_plus(expression):
    """Split on `+` at the top level, never inside a string."""
    parts, buffer, in_string, escaped = [], "", False, False
    for character in expression:
        if in_string:
            buffer += character
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
            buffer += character
        elif character == "+":
            parts.append(buffer)
            buffer = ""
        else:
            buffer += character
    parts.append(buffer)
    return parts


def unescape(text):
    return text.replace('\\"', '"').replace("\\\\", "\\")


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    design = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        repo_root, "docs", "design", "rules", "waiting.js")
    app = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        repo_root, "Ovation", "Document", "ReviewGate.swift")

    for path in (design, app):
        if not os.path.isfile(path):
            print(f"CANNOT COMPARE: {path} is not a file, so nothing was compared.")
            print("                That is not a pass.")
            return 2

    tips = [js_sentence(match) for match in TIP.findall(read(design))]
    said = [swift_sentence(match) for match in SWIFT_RETURN.findall(read(app))]
    said = [sentence for sentence in said if sentence]

    if not tips:
        print(f"CANNOT COMPARE: no tips found in {os.path.basename(design)}.")
        print("                A comparison with nothing to compare reports exactly")
        print("                what perfect agreement reports (L98).")
        return 2
    if not said:
        print(f"CANNOT COMPARE: no sentences found in {os.path.basename(app)}.")
        return 2

    missing = [tip for tip in tips if tip not in said]
    if missing:
        print("DRIFTED: the app does not say what the design record says.")
        for tip in missing:
            print(f"  {tip}")
        print(f"  {len(tips)} tip(s) in the design, {len(said)} sentence(s) in the app.")
        print("  The design record is where the wording was settled with Dan, so the")
        print("  app is what moves. Copy it exactly, or change the design first.")
        return 1

    print(f"PASS: all {len(tips)} design tip(s) are said word for word by the app,")
    print(f"      which carries {len(said)} sentence(s) in all.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
