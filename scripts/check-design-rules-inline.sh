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

HOW IT COMPARES is in scripts/lib/design_inline.py, which this and
scripts/check-design-shell-inline.sh (ovation#120) both read. It normalizes a
source to its code lines and requires them inside a design file as a CONTIGUOUS
RUN. That reasoning was written here first and moved when the shell became the
second subject, because sharing the data while copying the code that applies it
is not consolidation (L370).

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

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_inline import comparable_tokens, html_files, longest_run, significant_lines  # noqa: E402

DECLARES_UNRENDERED = "NOT RENDERED:"


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
    for filename in html_files(os.listdir(root)):
        path = os.path.join(root, filename)
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            raw = handle.read()
            designs[filename] = (significant_lines(raw), comparable_tokens(raw))
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

        # TWO READINGS OF THE SAME COPY, and the pair is what tells the causes
        # apart (ovation#144, L11). The first is the code alone, which is what
        # this guard has always compared. The second includes what the rule SAYS
        # about itself, because a rule file's comment is where the decision, its
        # measurement and the person who made it are recorded, and the guard used
        # to enforce the code being identical while letting the reasoning
        # diverge. Compared on its own the second reading answers "no design file
        # carries any of it" for a rule whose first line is a comment somebody
        # reworded, which is the wrong diagnosis for a rule that is inlined and
        # running.
        rule_code = significant_lines(text)
        rule_tokens = comparable_tokens(text)
        if not rule_code:
            faults.append((name, "NOT INLINE", "the rule file holds no code at all", None))
            continue

        best_file, best_run, best_tokens = None, 0, 0
        for design, (file_code, file_tokens) in designs.items():
            run = longest_run(rule_code, file_code)
            if run > best_run:
                best_file, best_run = design, run
                best_tokens = longest_run(rule_tokens, file_tokens)
            if best_run == len(rule_code) and best_tokens == len(rule_tokens):
                break

        if best_run == len(rule_code) and best_tokens == len(rule_tokens):
            inlined.append((name, best_file))
        elif best_run == len(rule_code):
            faults.append((name, "REASONING DRIFTED",
                           f"{best_file} runs this rule's code exactly and does not "
                           f"say the same thing about it. The comment is where the "
                           f"decision and its measurement are recorded, so the two "
                           f"copies now give different reasons for one rule", None))
        elif best_run == 0:
            faults.append((name, "NOT INLINE",
                           "no design file carries any of it, so no screen runs this rule",
                           None))
        else:
            faults.append((name, "DRIFTED",
                           f"{best_file} carries it as far as line {best_run + 1} "
                           f"of {len(rule_code)} and then disagrees", None))

    for name, design in inlined:
        print(f"  {name}: inlined verbatim in {design}")
    # THE REASON IS NOT ECHOED, for the reason given in the shell guard beside
    # this one (ovation#120): it is prose from a file we wrote, and this prints
    # to a terminal, so it is content rather than a filename. Required, never
    # repeated.
    for name, _reason in unrendered:
        print(f"  {name}: NOT RENDERED, with its reason given in the rule file")
    for name, kind, why, _detail in faults:
        print(f"  {name}: {kind}, {why}")

    if faults:
        drifted = sum(1 for f in faults if f[1] == "DRIFTED")
        reworded = sum(1 for f in faults if f[1] == "REASONING DRIFTED")
        missing = len(faults) - drifted - reworded
        parts = []
        if drifted:
            parts.append(f"{drifted} drifted")
        if reworded:
            parts.append(f"{reworded} saying something different about the same code")
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
