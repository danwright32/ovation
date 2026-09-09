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

A VERSION MUST DESCRIBE ITS OWN SHAPE (ovation#134). `OvationSchemaV1.models`
read `OvationSchema.models`, which is the list of what the app holds RIGHT NOW.
At one version those are the same sentence; the day a version 2 exists, version 1
silently describes version 2's models, both versions are the same shape, and any
migration stage between them has nothing to carry. check-migration-stages.sh
cannot see it, because it compares the LIST of versions and both claims about
their contents come from one expression (L70).

So each version holds its own list, and the NEWEST one is held to the app. An
older version's shorter list is not a fault: it is the entire point of a version.

Exit codes, one per outcome (L11):
    0  every model type is in the schema, and the newest version describes it
    1  a model type is not in the schema, so the store has no table for it
    2  nothing was scanned, or the schema file itself is not there
    3  the schema names a type that no longer exists in the sources
    4  a version delegates its model list instead of holding one
    5  the newest version's list and the app's models disagree
    6  a version states no model list this can read, so nothing was checked
    7  a versioned schema exists that this cannot place, so it went unchecked
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

# A versioned schema, and the body it claims. The version NUMBER is read from the
# type's own name rather than from the `Schema.Version` inside it, because the
# name is what every other version refers to and a mismatch between the two is
# its own fault for a different guard.
VERSION_ENUM = re.compile(
    r"\benum\s+(OvationSchemaV(\d+))\s*:\s*VersionedSchema\b")
# EVERY conformer, whatever it is called. Versions are found by their name above,
# so one named any other way would be invisible and every check would pass by
# never looking at it. This is what makes that a refusal rather than a silence,
# and it is the third time in one guard that a search missing its subject had to
# be turned into an outcome (L98, L96).
ANY_VERSIONED = re.compile(
    r"\benum\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*VersionedSchema\b")
# The computed form a version's list takes: `models: [...] { ... }` rather than
# the stored `= [...]` the app's own list uses. Two forms rather than one because
# they are two different statements: what the store holds today, and what a
# version claimed.
VERSION_MODELS_HEAD = re.compile(
    r"\bmodels\s*:\s*\[\s*any\s+PersistentModel\.Type\s*\]\s*")


def version_claim(body):
    """What a version says it holds, read exactly rather than by pattern.

    The expression can be written two ways, `{ [ ... ] }` and `= [ ... ]`, and a
    regex that assumes one silently skips the other. That happened while this was
    being written: the list was moved to the app's own form, the search missed,
    and every version check passed in silence (L98). So the opening delimiter is
    read and its match is counted to.

    Returns the expression text, or None when the version states no list at all.
    """
    head = VERSION_MODELS_HEAD.search(body)
    if head is None:
        return None
    rest = body[head.end():]
    if not rest:
        return None
    if rest[0] == "=":
        opener, closer, start = "[", "]", rest.find("[")
        if start < 0:
            return None
    elif rest[0] == "{":
        opener, closer, start = "{", "}", 0
    else:
        return None
    depth = 0
    for index in range(start, len(rest)):
        if rest[index] == opener:
            depth += 1
        elif rest[index] == closer:
            depth -= 1
            if depth == 0:
                return rest[start:index + 1]
    return None


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

    # ------------------------------------------------------------------
    # THE VERSIONS (ovation#134).
    # ------------------------------------------------------------------
    versions = []
    for match in VERSION_ENUM.finditer(schema_text):
        name, number = match.group(1), int(match.group(2))
        body = schema_text[match.end():]
        # The version's own body, ending where the next version begins.
        following = VERSION_ENUM.search(body)
        if following:
            body = body[:following.start()]
        versions.append((number, name, body))

    recognised = {name for _, name, _ in versions}
    unrecognised = sorted(name for name in ANY_VERSIONED.findall(schema_text)
                          if name not in recognised)
    if unrecognised:
        print("UNRECOGNISED: a versioned schema this guard cannot place.")
        for name in unrecognised:
            print(f"  {name}")
        print("  Versions are found by their name, which is how the newest one is")
        print("  known. One named otherwise is not checked at all, and a check")
        print("  that never looked is not a check that passed. Name it")
        print("  OvationSchemaV<n>, or teach this guard the other scheme.")
        return 7

    if versions:
        versions.sort()
        for number, name, body in versions:
            claim = version_claim(body)
            if claim is None:
                # NOT A SKIP, and its own outcome. A version that does not say
                # what it holds cannot be read as one that agrees, and this is a
                # different fault from one that says it by pointing at the app's
                # list, which is why it does not share that code (L11, L260).
                print(f"UNREADABLE: {name} does not state a model list this can read.")
                print("  A version says what it holds as")
                print("    static var models: [any PersistentModel.Type] { [ ... ] }")
                print("  and one that says it another way has not been checked at all.")
                return 6
            if "OvationSchema.models" in claim:
                print("DELEGATED: a version does not describe its own shape.")
                print(f"  {name} reads OvationSchema.models, which is what the app")
                print("  holds RIGHT NOW rather than what that version held.")
                print("  At one version those are the same sentence. At two, this")
                print("  version silently describes the newer one's models, both")
                print("  are the same shape, and a stage between them carries")
                print("  nothing. Give it its own list.")
                return 4

        newest_number, newest_name, newest_body = versions[-1]
        claim = version_claim(newest_body)
        if claim is not None:
            claimed = set(REGISTRATION.findall(claim))
            adrift = sorted(name for name in declared if name not in claimed)
            if adrift:
                print(f"ADRIFT: {newest_name} does not describe what the app holds.")
                for name in adrift:
                    path, line = declared[name]
                    print(f"  {path}:{line}: {name}")
                print("Two answers, and the sources cannot tell which is yours:")
                print(f"  If a store carrying {newest_name} has NEVER been written")
                print("  to disk, this type is part of that first shape: add it to")
                print(f"  {newest_name}.models.")
                print(f"  If a store carrying {newest_name} HAS been written, that")
                print("  shape is fixed and this is a change to it: add the next")
                print("  version with its own list, and a stage carrying data into")
                print("  it (scripts/check-migration-stages.sh holds you to that).")
                return 5

    print(f"OK: {len(declared)} model type(s), every one in the store's schema.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
