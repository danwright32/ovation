#!/usr/bin/env python3
"""Refuse a model type that the store's schema does not know about.

ovation#60. `OvationSchema.models` is the one list of what the store holds, and
SwiftData does not complain about a type missing from it. It simply has no table
for that type, so the first symptom is a fetch that quietly returns nothing, at
whatever distance from the omission (L96, L98).

WHY A SCAN RATHER THAN CARE. A guard driven by a hand written registry checks
only what the registry lists, so anything missing from it is exempt from the very
check meant to catch it. This derives the SUBJECTS from the sources, by finding
every `@Model` declaration in the app, and holds the list to them (L247).

THE NAMING RULE IT RESTS ON. A persisted type is a `final class` carrying the
`@Model` macro, and it is registered by writing `<Type>.self` in the schema file.
Both are mechanical, so the scan is exact rather than heuristic.

NOTHING SCANNED IS NOT A PASS (L98). A scan finding no models at all has stopped
working rather than found a clean tree, because there are ten.

Seams: OVATION_SCHEMA_SCAN_ROOT and OVATION_SCHEMA_FILE.

Exit codes, one per outcome (L11):
    0  every model type is in the schema
    1  a model type is not in the schema, so the store has no table for it
    2  nothing was scanned, or the schema file itself is not there
    3  the schema names a type that no longer exists in the sources
"""
import os
import re
import sys

# @Model, then the class declaration it sits above, with anything (attributes,
# comments, blank lines) in between.
DECLARATION = re.compile(r"@Model\b[\s\S]{0,400}?\bclass\s+([A-Za-z_][A-Za-z0-9_]*)")
REGISTRATION = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\.self\b")
# The SUBJECT is the models array, not the file. ovation#105 added
# OvationSchemaV1.self and OvationMigrationPlan.self to the schema file, and
# reading every `X.self` in it treated both as registered model types with no
# @Model declaration anywhere, so the guard called a correct schema stale. A
# match found by loose spelling picks up what was never a subject (L100).
MODELS_ARRAY = re.compile(
    r"\bmodels\s*:\s*\[\s*any\s+PersistentModel\.Type\s*\]\s*=\s*\[(.*?)\]",
    re.DOTALL)


def swift_files(root):
    found = []
    for directory, _, filenames in os.walk(root):
        for filename in sorted(filenames):
            if filename.endswith(".swift"):
                found.append(os.path.join(directory, filename))
    return sorted(found)


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = os.environ.get("OVATION_SCHEMA_SCAN_ROOT") or os.path.join(repo_root, "Ovation")
    schema_file = os.environ.get("OVATION_SCHEMA_FILE") or os.path.join(
        root, "Persistence", "OvationSchema.swift")

    if not os.path.isdir(root):
        print(f"CANNOT SCAN: {root} is not a directory, so nothing was checked.")
        return 2
    if not os.path.isfile(schema_file):
        print(f"CANNOT SCAN: the schema is not at {schema_file}.")
        print("             Without it there is nothing to hold the models to.")
        return 2

    with open(schema_file, "r", encoding="utf-8", errors="replace") as handle:
        schema_text = handle.read()

    arrays = MODELS_ARRAY.findall(schema_text)
    if not arrays:
        print(f"CANNOT SCAN: no models array found in {schema_file}.")
        print("             That is not a pass: the guard has lost the one list")
        print("             it holds the sources to, so it can no longer measure.")
        return 2
    registered = set()
    for body in arrays:
        registered.update(REGISTRATION.findall(body))

    declared = {}
    for path in swift_files(root):
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        for match in DECLARATION.finditer(text):
            name = match.group(1)
            line = text.count("\n", 0, match.start()) + 1
            declared.setdefault(name, (os.path.relpath(path, root), line))

    if not declared:
        print(f"CANNOT SCAN: no @Model types found under {root}.")
        print("             That is not a pass: there are ten, so a scan finding")
        print("             none has stopped working rather than found a clean tree.")
        return 2

    missing = sorted(name for name in declared if name not in registered)
    if missing:
        print("UNREGISTERED: a model type is not in the store's schema, so it has no table.")
        for name in missing:
            path, line = declared[name]
            print(f"  {path}:{line}: {name}")
        print("Add it to OvationSchema.models. SwiftData does not report this:")
        print("the first symptom is a fetch that returns nothing.")
        return 1

    # The other direction. A schema naming a type that no longer exists is a
    # different fault with a different remedy, so it gets its own code and its
    # own sentence (L11).
    stale = sorted(name for name in registered
                   if name not in declared and name[:1].isupper()
                   and name not in {"Schema", "ModelConfiguration", "ModelContainer"})
    if stale:
        print("STALE: the schema names a type the sources no longer declare.")
        for name in stale:
            print(f"  {name}")
        return 3

    print(f"OK: {len(declared)} model type(s), every one in the store's schema.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
