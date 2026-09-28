#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a problem kind that the app declares and never raises.

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

EVERY DECLARED KIND, NOT ONLY THE MATCHED ONES (ovation#583). The rule above
held only kinds something compares against, and two backup retention kinds,
`archiveCouldNotBeRemoved` and `retentionCouldNotRun`, were declared for
ovation#227, named in the rail foot's table, compared against by nothing and
raised by nothing. So a retention failure passed in silence and this check had
nothing to say, because it never looked at them (L90, L13). A declared kind
nothing produces is either dead code or a failure nobody hears, and neither is
visible from the declaration (L29). So every DECLARED kind must be used, with a
kind that is also matched on named at each place it is matched.

A KIND AS A DICTIONARY KEY IS NOT A USE (ovation#99). The rail's foot names every
kind in one table, `.name: "Short name"`, and a table naming every kind would
count every kind as raised, which silences this check for all of them at once.
So a dictionary KEY is read as a key, never as the kind happening.

A KEY IS NARROWER THAN "A NAME AND A COLON". The true branch of a ternary,
`missing ? .name : .other`, and a switch label, `case .name:` or `case .a, .name:`,
are followed by a colon too; the first is a genuine raise and the second was
always counted as a use, so neither may be discounted. A key is a name followed
by a colon that opens its line or follows `[` or a `,`, on a line that is not a
case label.

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
    0  every problem kind the app declares is used somewhere, outside a comparison
    1  a declared problem kind is raised nowhere, named where it is declared and
       wherever it is matched on
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
KEY_AFTER = re.compile(r"\s*:")
KEY_BEFORE = re.compile(r"(?:^|[\[,])\s*$")
CASE_LABEL = re.compile(r"^\s*case\b")


def is_dictionary_key(code, match):
    """Whether this `.name` is a dictionary literal's key, `.name: value`, rather
    than a ternary's branch or a case label, which are followed by a colon too."""
    if not KEY_AFTER.match(code, match.end()):
        return False
    line_start = code.rfind("\n", 0, match.start()) + 1
    before = code[line_start:match.start()]
    if CASE_LABEL.match(before):
        return False
    return KEY_BEFORE.search(before) is not None

EXPLANATION = (
    "problem kind matched and never raised: code that resolves, filters or counts "
    "a kind believes the kind happens. Nothing in the app produces this one, so "
    "that code does nothing while reading as working (ovation#262). Raise the kind "
    "where its condition occurs, or delete the code that waits for it."
)


DECLARED_EXPLANATION = (
    "problem kind declared and never raised: a kind exists to name a condition, and "
    "nothing in the app produces this one, so either it is dead or its condition "
    "happens in silence (ovation#583). Raise the kind where its condition occurs, or "
    "delete the declaration."
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
    # Where each kind is declared, so a refusal can point at it.
    declared_at = {}
    for relative, code in sorted(sources.items()):
        for match in DECLARATION.finditer(code):
            declared.add(match.group(1))
            declared_at.setdefault(
                match.group(1), (relative, code.count("\n", 0, match.start()) + 1))
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
            if is_dictionary_key(code, match):
                continue
            if any(start <= match.start(1) < end for start, end in comparison_names):
                continue
            used.add(name)

    unraised = sorted(declared - used)
    if unraised:
        print(f"FOUND: {len(unraised)} declared problem kind(s) raised nowhere, "
              f"in {len(sources)} scanned file(s).")
        for name in unraised:
            relative, line = declared_at[name]
            print(f"  {relative}:{line}: {name} (declared here, raised nowhere)")
        matched_unraised = [entry for entry in compared if entry[2] not in used]
        for relative, line, name in matched_unraised:
            print(f"  {relative}:{line}: {name} (matched here, raised nowhere)")
        print(EXPLANATION if matched_unraised else DECLARED_EXPLANATION)
        return 1

    matched = len({entry[2] for entry in compared})
    print(f"OK: scanned {len(sources)} Swift file(s) under {root}: {len(declared)} problem "
          f"kind(s) declared, every one raised somewhere; {matched} of them matched on.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
