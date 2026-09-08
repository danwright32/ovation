#!/usr/bin/env python3
"""Refuse a design file whose copy of a rule has drifted from rules/.

ovation#111. `docs/design/rules/` holds the invoice screen's rules as executable
functions with their cases. `scripts/test-design-rules.sh` runs them and they
pass, and `docs/design/README.md` says they exist "so whoever ports this to Swift
has something to port AGAINST".

THE DESIGN FILE DOES NOT LOAD THEM. It cannot: ovation#114 requires each design
file to be one self contained document that reaches outside itself never, so a
`<script src="rules/duration.js">` is refused by the guard beside this one. The
design file therefore carries its own copy of every rule it runs, and two copies
of one rule with nothing comparing them is L370.

IT HAD ALREADY GONE WRONG. Commit a12b32a fixed a real defect in `typeDigit`: the
buffer was joined to the new digit and compared against the segment's maximum,
and where the buffer was not digits `parseInt` gives NaN, `NaN > max` is false,
so the guard that resets an illegal value never fired. That fix landed in
`rules/time-field.js` and a case was added for it. The identical copy inside
`docs/design/invoice-being-priced.html` was left untouched. The suite went on
passing, because the suite reads `rules/`. The screen the design record IS still
held the defect, and nothing anywhere could have said so.

HOW IT COMPARES. Each rule file is normalized to its lines with comments removed
and whitespace collapsed, and that sequence must appear inside a design file as a
CONTIGUOUS RUN. Not as lines that all occur somewhere: a check written as several
conditions over one body of text is satisfied by several unrelated places in it
(L178), and a rule whose lines are present but interleaved with others is a rule
the design file does not actually run. Comments are stripped because the design
file rewraps them when the rule is pasted into its script, and a comparison that
broke on that could only ever match by luck.

Outcomes, one per rule file, each with its own wording because distinct causes
need distinct messages (L11):

    INLINED         the rule appears verbatim in at least one design file
    DRIFTED         a design file carries part of the rule and then disagrees
    NOT INLINE      no design file carries any of it
    NOT RENDERED    the rule says, in its own words, that no screen runs it

NOT RENDERED IS THE RULE'S OWN DECLARATION, not a list of exempt filenames kept
here. A file naming its exceptions stops covering the moment a second case
satisfies the same reason (L362), so the escape is a line in the rule file
reading `NOT RENDERED:` followed by why. `rules/money.js` is in that state today:
it holds the discount and referral credit arithmetic that PRD 5.4a and 5.8
settled, and no screen draws either yet.

Exit codes, so a caller can tell the outcomes apart without parsing text:

    0  every rule is inlined verbatim or declares why it is not rendered
    1  at least one rule has DRIFTED or is NOT INLINE
    2  nothing could be compared, which is not a pass

NOTHING TO COMPARE IS NOT A PASS. A checker that goes green because it found no
rules, or no design files, reports exactly what a record in perfect agreement
reports (L98).

IT NAMES THE LINE NUMBER AND NEVER QUOTES THE LINE. An earlier version printed
the rule's own text back, which read as the more helpful refusal and is the one
thing here that prints file CONTENT rather than a filename. docs/PRIVACY-FLOOR.md
says scripts return counts, ids, paths and field names, and Dan reads anything
else on his own screen. scripts/test-output-privacy.sh caught it by putting a
name inside the rule, and the refusal is still actionable: it says which rule,
which design file, and which line of the rule the copy stopped matching at.

Seam, shared with scripts/check-design-self-contained.sh rather than invented
again, so one variable moves the whole design record for a test (L2):

    OVATION_DESIGN_ROOT   the design record to read
"""
import os
import re
import sys

DECLARES_UNRENDERED = "NOT RENDERED:"


def strip_comments(text):
    """Block and line comments out, so rewrapping prose cannot fail a match.

    String literals are left alone rather than parsed: a rule file is code we
    wrote, and the alternative is a JavaScript tokenizer whose own bugs would be
    reported as design drift.
    """
    text = re.sub(r"/\*.*?\*/", "\n", text, flags=re.S)
    return re.sub(r"(^|\s)//[^\n]*", r"\1", text)


def significant_lines(text):
    """The comparable shape of a file: its code lines, whitespace collapsed."""
    lines = []
    for raw in strip_comments(text).splitlines():
        collapsed = " ".join(raw.split())
        if collapsed:
            lines.append(collapsed)
    return lines


def longest_run(rule_lines, file_lines):
    """How many of the rule's lines appear contiguously, at best, in the file.

    Returns the length of the longest prefix of `rule_lines` that occurs as a
    contiguous run anywhere in `file_lines`. len(rule_lines) means the whole rule
    is carried verbatim; zero means none of it is there at all.
    """
    best = 0
    for start in range(len(file_lines)):
        if file_lines[start] != rule_lines[0]:
            continue
        run = 0
        while (run < len(rule_lines)
               and start + run < len(file_lines)
               and file_lines[start + run] == rule_lines[run]):
            run += 1
        if run > best:
            best = run
        if best == len(rule_lines):
            break
    return best


def unrendered_reason(text):
    for raw in text.splitlines():
        if DECLARES_UNRENDERED in raw:
            said = raw.split(DECLARES_UNRENDERED, 1)[1]
            return " ".join(said.replace("*/", " ").split())
    return None


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(repo_root, "docs", "design")

    if not os.path.isdir(root):
        print(f"CANNOT SCAN: {root} is not a directory, so nothing was compared.")
        print("             That is not a pass. Point OVATION_DESIGN_ROOT at the record.")
        return 2

    rules_dir = os.path.join(root, "rules")
    rule_files = []
    if os.path.isdir(rules_dir):
        rule_files = sorted(f for f in os.listdir(rules_dir) if f.endswith(".js"))
    if not rule_files:
        print(f"CANNOT SCAN: no rules under {rules_dir}.")
        print("             That is not a pass: a comparison with nothing to compare")
        print("             reports exactly what perfect agreement reports.")
        return 2

    designs = {}
    for filename in sorted(os.listdir(root)):
        if filename.lower().endswith((".html", ".htm")):
            path = os.path.join(root, filename)
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                designs[filename] = significant_lines(handle.read())
    if not designs:
        print(f"CANNOT SCAN: no design files under {root} to compare the rules against.")
        print("             That is not a pass either, and it is a different cause from")
        print("             a record holding no rules.")
        return 2

    inlined, unrendered, faults = [], [], []
    for name in rule_files:
        with open(os.path.join(rules_dir, name), "r", encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        reason = unrendered_reason(text)
        if reason is not None:
            unrendered.append((name, reason))
            continue

        rule_lines = significant_lines(text)
        if not rule_lines:
            faults.append((name, "NOT INLINE", "the rule file holds no code at all", None))
            continue

        best_file, best_run = None, 0
        for design, file_lines in designs.items():
            run = longest_run(rule_lines, file_lines)
            if run > best_run:
                best_file, best_run = design, run
            if best_run == len(rule_lines):
                break

        if best_run == len(rule_lines):
            inlined.append((name, best_file))
        elif best_run == 0:
            faults.append((name, "NOT INLINE",
                           "no design file carries any of it, so no screen runs this rule",
                           None))
        else:
            faults.append((name, "DRIFTED",
                           f"{best_file} carries it as far as line {best_run + 1} "
                           f"of {len(rule_lines)} and then disagrees", None))

    for name, design in inlined:
        print(f"  {name}: inlined verbatim in {design}")
    for name, reason in unrendered:
        print(f"  {name}: NOT RENDERED, {reason}")
    for name, kind, why, _detail in faults:
        print(f"  {name}: {kind}, {why}")

    if faults:
        drifted = sum(1 for f in faults if f[1] == "DRIFTED")
        missing = len(faults) - drifted
        parts = []
        if drifted:
            parts.append(f"{drifted} drifted")
        if missing:
            parts.append(f"{missing} carried by no design file")
        print(f"RULES AND DESIGN DISAGREE: {', '.join(parts)}, "
              f"out of {len(rule_files)} checked.")
        print("A design file cannot load rules/, so it carries its own copy, and the")
        print("suite reads rules/. A correction made to one copy and not the other")
        print("leaves the suite green while the screen behaves differently, which is")
        print("what happened in a12b32a. Paste the rule back into the design file, or")
        print("say in the rule why no screen runs it.")
        return 1

    print(f"OK: {len(rule_files)} rule file(s) checked against "
          f"{len(designs)} design file(s), {len(unrendered)} declared unrendered.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
