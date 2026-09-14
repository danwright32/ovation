#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a problem kind that the app matches on and never raises.

ovation#262. `backupFolderNotChosen` was declared, documented as the standing
condition a launch with no backup folder raises, and resolved in two places:
when a folder is chosen, and when a launch takes a backup. NOTHING RAISED IT. A
launch with no folder threw a write failure instead, which became
`backupCouldNotBeWritten`, and nothing resolves that kind, so the notice raised
on a first launch stayed open after the folder was chosen and after backups
worked. Both resolutions acted on a kind that never occurred, and every test
passed, because each one raised the kind by hand before resolving it (L90, L46).

THE RULE IS THE REASON, not the one kind (L362). Code that matches on a kind, to
resolve it, filter it or count it, is code that believes the kind happens. When
nothing in the app ever produces that kind, the matching code does nothing while
reading as working. So every problem kind the app compares against must also be
USED somewhere else in the app.

WHAT COUNTS AS A USE, stated so it can be argued with: any `.name` of a declared
problem kind outside a `kind ==` or `kind !=` comparison, in code rather than in a
comment or a string. That is deliberately loose. A kind can be raised through a
tuple a helper returns, which `StoreLaunchSequence.backupCondition(for:)` does,
and requiring the literal `kind: .name` would call every one of those unraised.
The looseness costs a false negative: a kind mentioned in some other expression
passes without being raised. That is accepted rather than a Swift parser.

ITS SUBJECTS ARE DERIVED, never listed (L96, L247). Kinds are declared as
`static let name = ProblemKind("...")` in more than one file, extensions in the
roster and export code included, so declarations are collected from the tree.

TESTS ARE NOT SCANNED. A test raising a kind by hand before resolving it is
exactly how this went unseen, so it cannot count as the kind happening.

WHAT IT NEVER PRINTS: a source line. File names, line numbers and kind names only
(L222).

NOTHING SCANNED IS NOT A PASS (L98).

Seams: OVATION_KINDS_SCAN_ROOT.

Exit codes, one per outcome (L11):
    0  every problem kind the app matches on is also used somewhere else
    1  a problem kind is matched on and never raised
    2  nothing was scanned: no root, no Swift files, or no problem kinds declared
"""
import importlib.machinery
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# The comment stripping and string blanking belong to
# check-forbidden-constructs.sh, loaded rather than copied: two copies of the
# parts most easily got subtly wrong is not consolidation (L370).
_constructs = importlib.machinery.SourceFileLoader(
    "forbidden_constructs", os.path.join(HERE, "check-forbidden-constructs.sh")).load_module()

DECLARATION = re.compile(r"\bstatic\s+let\s+([A-Za-z_]\w*)\s*=\s*ProblemKind\s*\(")
COMPARISON = re.compile(r"\bkind\s*[!=]=\s*\.([A-Za-z_]\w*)\b")
DOTTED = re.compile(r"\.([A-Za-z_]\w*)\b")

EXPLANATION = (
    "problem kind matched and never raised: code that resolves, filters or counts "
    "a kind believes the kind happens. Nothing in the app produces this one, so "
    "that code does nothing while reading as working (ovation#262). Raise the kind "
    "where its condition occurs, or delete the code that waits for it."
)


def code_of(path):
    """The file's code with comments removed and string contents blanked, so a
    name in prose or in a sentence is not a use, and every offset still lines up."""
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    return _constructs.blank_strings(
        "\n".join(text for _, text in _constructs.strip_comments(lines)))


def main():
    root = os.environ.get("OVATION_KINDS_SCAN_ROOT") or os.path.join(os.path.dirname(HERE), "Ovation")
    if not os.path.isdir(root):
        print(f"CANNOT SCAN: {root} is not a directory, so nothing was checked.")
        print("             That is not a pass. Point OVATION_KINDS_SCAN_ROOT at the sources.")
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

    declared = set()
    for code in sources.values():
        declared.update(DECLARATION.findall(code))
    if not declared:
        print(f"CANNOT SCAN: no problem kinds are declared under {root}.")
        print("             With nothing to hold the comparisons to, nothing was checked.")
        return 2

    compared = []
    used = set()
    for relative, code in sorted(sources.items()):
        comparison_names = []
        for match in COMPARISON.finditer(code):
            comparison_names.append(match.span(1))
            if match.group(1) in declared:
                line = code.count("\n", 0, match.start()) + 1
                compared.append((relative, line, match.group(1)))
        for match in DOTTED.finditer(code):
            name = match.group(1)
            if name not in declared:
                continue
            if any(start <= match.start(1) < end for start, end in comparison_names):
                continue
            used.add(name)

    unraised = [entry for entry in compared if entry[2] not in used]
    if unraised:
        names = sorted({entry[2] for entry in unraised})
        print(f"FOUND: {len(names)} problem kind(s) matched on and never raised, "
              f"in {len(sources)} scanned file(s).")
        for relative, line, name in unraised:
            print(f"  {relative}:{line}: {name} (matched here, raised nowhere)")
        print(EXPLANATION)
        return 1

    matched = len({entry[2] for entry in compared})
    print(f"OK: scanned {len(sources)} Swift file(s) under {root}: {matched} problem "
          f"kind(s) matched on, every one raised somewhere.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
