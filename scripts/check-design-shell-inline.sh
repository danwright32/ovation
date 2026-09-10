#!/usr/bin/env python3
"""Refuse a design file whose copy of the shell has drifted from shell/.

ovation#120. `docs/design/shell/` holds the parts every design file shares: the
embedded typefaces, the record page the design is written on, and the macOS
window with its menu bar, espresso sidebar, title bar and palette.

THE DESIGN FILE DOES NOT LOAD THEM. It cannot: ovation#114 requires each design
file to be one self contained document that reaches outside itself never, so a
`<link href="shell/window.css">` is refused by the guard beside this one. Each
file therefore carries its own copy of every part it uses, and four copies of one
shell with nothing comparing them is L370.

IT HAD ALREADY GONE WRONG TWICE, in one session, and neither fault was visible
by looking. The whole screen rendered in the system typeface, because the settled
type lives on a `body` rule and the shell was lifted out without its page chrome;
every face still loaded and the page still looked finished. And `.nrow`, already
the Clients names column, was reused by the narrowed invoice list, so a bare rule
in the settled sheet reached rows it was never written for. Both were found by
looking at a rendering and wondering why something was the wrong width.

WHY BOTH HALVES SHIP TOGETHER. A shared file nobody is required to use is a
second copy waiting to happen (L613), so this guard is what makes the shell the
shell. Its sibling is scripts/check-design-collisions.py, which refuses a screen
that redefines a shell class rather than one that fails to carry it.

Outcomes, one per part per design file, each with its own wording because
distinct causes need distinct messages (L11):

    CARRIED         the file holds the part verbatim
    DRIFTED         the file holds part of it and then disagrees
    MISSING         the file holds none of it
    NOT SHELLED     the file says, in its own words, why it carries none of it
    STALE           the file says it carries none of it, and carries it anyway

NOT SHELLED IS THE FILE'S OWN DECLARATION, not a list of exempt filenames kept
here. A guard naming its exceptions stops covering the moment a second case
satisfies the same reason (L362), so the escape is a line in the design file
reading `NOT SHELLED: <part>,` followed by why. `invoice-pdf.html` is the case
today: it is paper, and it draws no app window at all.

STALE IS WHY THE DECLARATION IS NOT SIMPLY A SKIP. An exemption that outlives
its reason reads as a considered decision and is never revisited (L346), so a
file carrying a part it says it does not carry is refused rather than exempted.

Exit codes, so a caller can tell the outcomes apart without parsing text:

    0  every part is carried verbatim or declared, with its reason
    1  at least one copy has DRIFTED, is MISSING, or has a STALE declaration
    2  nothing could be compared, which is not a pass

NOTHING TO COMPARE IS NOT A PASS. A checker that goes green because it found no
shell, or no design files, reports exactly what a record in perfect agreement
reports (L98). The two ways of having nothing are different faults with different
remedies, so they are said differently.

IT NAMES THE LINE NUMBER AND NEVER QUOTES THE LINE, for the same reason its
sibling does: docs/PRIVACY-FLOOR.md says scripts return counts, ids, paths and
field names. The refusal is still actionable, because it says which file, which
part, and which line of the part the copy stopped matching at.

Seam, shared with scripts/check-design-self-contained.sh and
scripts/check-design-rules-inline.sh rather than invented again, so one variable
moves the whole design record for a test (L2):

    OVATION_DESIGN_ROOT   the design record to read
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_inline import (DECLARES_UNSHELLED, declared_parts, html_files,  # noqa: E402
                           longest_run, significant_lines)

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(repo_root, "docs", "design")

    if not os.path.isdir(root):
        print(f"CANNOT SCAN: {root} is not a directory, so nothing was compared.")
        print("             That is not a pass. Point OVATION_DESIGN_ROOT at the record.")
        return 2

    shell_dir = os.path.join(root, "shell")
    part_names = []
    if os.path.isdir(shell_dir):
        part_names = sorted(f for f in os.listdir(shell_dir)
                            if f.endswith((".css", ".js")))
    if not part_names:
        print(f"CANNOT SCAN: no shell parts under {shell_dir}.")
        print("             That is not a pass: a comparison with nothing to compare")
        print("             reports exactly what perfect agreement reports.")
        return 2

    designs = {}
    for name in html_files(os.listdir(root)):
        with open(os.path.join(root, name), "r", encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        designs[name] = (significant_lines(text), declared_parts(text))
    if not designs:
        print(f"CANNOT SCAN: no design file under {root} to compare the shell against.")
        print("             That is not a pass either, and it is a different cause from")
        print("             a record holding no shell.")
        return 2

    parts = {}
    for name in part_names:
        with open(os.path.join(shell_dir, name), "r", encoding="utf-8", errors="replace") as handle:
            parts[name] = significant_lines(handle.read())

    carried, per_file, declared, faults = 0, {}, [], []
    for design, (file_lines, declarations) in designs.items():
        per_file[design] = 0
        for part, part_lines in parts.items():
            if not part_lines:
                faults.append((design, part, "MISSING",
                               "the shell part holds no code at all"))
                continue

            run = longest_run(part_lines, file_lines)
            whole = run == len(part_lines)
            reason = declarations.get(part)

            if reason is not None and whole:
                faults.append((design, part, "STALE",
                               "it declares it carries none of this part, in the "
                               "file, and carries all of it"))
            elif reason is not None:
                declared.append((design, part, reason))
            elif whole:
                carried += 1
                per_file[design] += 1
            elif run == 0:
                faults.append((design, part, "MISSING",
                               "it carries none of this part and says nothing about why"))
            else:
                faults.append((design, part, "DRIFTED",
                               f"it carries the part as far as line {run + 1} "
                               f"of {len(part_lines)} and then disagrees"))

    # NAMED ONE BY ONE RATHER THAN COUNTED. A file that carries nothing and a
    # file that was never opened produce the same total, so the pass says which
    # files it actually compared (L98).
    for design in sorted(per_file):
        print(f"  {design}: carries {per_file[design]} of {len(parts)} verbatim")
    # THE REASON IS NOT ECHOED, only required. It is a sentence in a design file
    # and this guard prints to a terminal, so repeating it is the one thing here
    # that would print file CONTENT rather than a filename (docs/PRIVACY-FLOOR.md).
    # Caught by scripts/test-output-privacy.sh with a client name in the
    # declaration. The refusal stays actionable: it names the file and the part,
    # and the reason is in the file, where the person reading this can see it.
    for design, part, _reason in declared:
        print(f"  {design}: NOT SHELLED by {part}, with its reason given in the file")
    for design, part, kind, why in faults:
        print(f"  {design}: {part} {kind}, {why}")

    if faults:
        counts = {}
        for _design, _part, kind, _why in faults:
            counts[kind] = counts.get(kind, 0) + 1
        summary = ", ".join(f"{n} {kind.lower()}" for kind, n in sorted(counts.items()))
        print(f"THE SHELL AND THE DESIGN FILES DISAGREE: {summary}, out of "
              f"{len(parts)} shell part(s) against {len(designs)} design file(s).")
        print("A design file cannot load shell/, so it carries its own copy. A")
        print("correction made to one copy and not the others is invisible: every")
        print("file goes on rendering, and the fault is found by looking at a")
        print("screen and wondering why something is the wrong width.")
        print("")
        print("    scripts/write-design-shell.sh")
        print("")
        print("writes each part into every file that declares it, patching the")
        print("code lines and leaving the file's own comments where they are. It")
        print("is a real remedy rather than a sentence: this used to end with")
        print("\"paste the part back into the file\", nothing pasted, and keeping")
        print("five files in step was careful copying by whoever was on it")
        print("(ovation#177, L406). A file that should carry none of a part says")
        print("so in its own words instead, with the reason.")
        return 1

    print(f"OK: {len(parts)} shell part(s) checked against {len(designs)} design "
          f"file(s), {carried} carried verbatim, {len(declared)} declared unshelled.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
