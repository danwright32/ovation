#!/usr/bin/env python3
"""Hold `OvationMigrationPlan.schemas` and its `stages` in step.

ovation#119. `stages` is `[]` and `schemas` names one version. Both are correct
today and exactly one of them is silently wrong the moment somebody adds a
second version.

WHAT GOES WRONG, AND HOW QUIETLY. SwiftData's lightweight migration handles a
purely additive change and does not handle several other shapes. Measured on this
OS in `SchemaMigrationTests`: an added optional field carries every row forward,
and dropping a required field keeps the rows and removes the column. Neither
needs a stage. A renamed property, a changed type or a new required relationship
DO, and without one SwiftData does not refuse. It opens a store that looks fine
and the data is gone, against PRD 5.30's promise that Ovation deletes nothing
automatically, ever.

WHY A GUARD RATHER THAN CARE. Nothing else in the repository can tell that a
stage is missing, because an empty `stages` is the correct value right up until
it is not. A guard shipped deliberately inactive needs the thing that activates
it filed in the same breath, or the day it matters is the day nobody remembers
why it was empty (L65).

IT IS VACUOUS TODAY AND SAYS SO. With one version there is no chain, and a check
that finds one version and exits green is indistinguishable from one that
verified a chain (L98). The two cases have different sentences.

THE SUBJECTS ARE DERIVED FROM THE SOURCE, never from a list beside it, the same
way check-schema-registered.sh derives its models. A guard driven by a hand
written registry checks only what the registry lists (L96, L247).

Seam: OVATION_SCHEMA_FILE.

Exit codes, one per outcome (L11):
    0  the versions and the stages are in step
    1  a consecutive pair of versions has no stage carrying a store across it
    2  nothing could be read: no file, no plan, or no versions in it
    3  a stage names a pair that is not a step in the chain
"""
import os
import re
import sys

PLAN = re.compile(r"\benum\s+OvationMigrationPlan\b")
SCHEMAS = re.compile(r"\bschemas\s*:\s*\[\s*any\s+VersionedSchema\.Type\s*\]")
STAGES = re.compile(r"\bstages\s*:\s*\[\s*MigrationStage\s*\]")
TYPE_SELF = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\.self\b")
# Each stage names its two ends. Read as an ordered stream of labelled versions
# rather than by matching a whole call, because a custom stage carries closures
# between them and a single expression regex would stop matching the day one
# appears.
ENDPOINT = re.compile(r"\b(fromVersion|toVersion)\s*:\s*([A-Za-z_][A-Za-z0-9_]*)\.self\b")


def bracketed_after(text, start, opener="[", closer="]"):
    """The contents of the first bracketed group at or after `start`.

    A brace matcher rather than a regex because the stages list is a list of
    calls that will one day carry closures, arrays and dictionaries inside it,
    and a non greedy regex stops at the first inner closer while a greedy one
    runs to the end of the file. Both fail silently, in opposite directions.
    """
    opened = text.find(opener, start)
    if opened < 0:
        return None
    depth = 0
    for index in range(opened, len(text)):
        if text[index] == opener:
            depth += 1
        elif text[index] == closer:
            depth -= 1
            if depth == 0:
                return text[opened + 1:index]
    return None


def stage_pairs(body):
    """The (from, to) pairs a stages list names, in the order written.

    An endpoint without its partner is reported as a pair with a None in it
    rather than dropped, so a stage naming only one end is refused rather than
    quietly reducing the count and reading as a stage that is simply absent.
    """
    found = []
    pending = {}
    for kind, name in ENDPOINT.findall(body):
        if kind in pending:
            found.append((pending.get("fromVersion"), pending.get("toVersion")))
            pending = {}
        pending[kind] = name
        if "fromVersion" in pending and "toVersion" in pending:
            found.append((pending["fromVersion"], pending["toVersion"]))
            pending = {}
    if pending:
        found.append((pending.get("fromVersion"), pending.get("toVersion")))
    return found


def describe(pair):
    return f"{pair[0] or '(nothing)'} to {pair[1] or '(nothing)'}"


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    schema_file = os.environ.get("OVATION_SCHEMA_FILE") or os.path.join(
        repo_root, "Ovation", "Persistence", "OvationSchema.swift")

    if not os.path.isfile(schema_file):
        print(f"CANNOT SCAN: the schema is not at {schema_file}.")
        print("             Without it there is no plan to hold to its versions.")
        return 2

    with open(schema_file, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    if not PLAN.search(text):
        print(f"CANNOT SCAN: no OvationMigrationPlan found in {schema_file}.")
        print("             That is not a pass: the guard has lost its subject,")
        print("             so it can no longer measure anything at all.")
        return 2

    schemas_at = SCHEMAS.search(text)
    if not schemas_at:
        print(f"CANNOT SCAN: OvationMigrationPlan names no schemas list in {schema_file}.")
        return 2
    versions = TYPE_SELF.findall(bracketed_after(text, schemas_at.end()) or "")
    if not versions:
        print(f"CANNOT SCAN: the plan's schemas list is empty in {schema_file}.")
        print("             That is not a pass: a plan carrying no version at all")
        print("             cannot migrate anything, and there is at least one.")
        return 2

    stages_at = STAGES.search(text)
    # An ABSENT stages list is not the same as an empty one, but SwiftData
    # defaults it, so both mean no stage is declared. They are one outcome here
    # and the refusal below reads the same for either.
    pairs = stage_pairs(bracketed_after(text, stages_at.end()) or "") if stages_at else []

    steps = list(zip(versions, versions[1:]))

    uncovered = [step for step in steps if step not in pairs]
    unexpected = [pair for pair in pairs if pair not in steps]

    # THE WRONG STAGE IS REPORTED BEFORE THE MISSING ONE, and the order is the
    # whole difference between a useful message and a misleading one. A stage
    # that jumps a version, or is written backwards, leaves its step uncovered
    # TOO, so both are true at once. Reporting "no stage carries this" while a
    # stage naming those very versions sits three lines away sends the reader to
    # write a second one. The remedies are opposite as well, correcting a stage
    # against writing one, which is why they are two outcomes rather than one
    # (L11).
    if unexpected:
        print("UNEXPECTED STAGE: a stage names a pair that is not a step in the chain.")
        for pair in unexpected:
            print(f"  {describe(pair)}")
        print("The steps the schemas list actually asks for are:")
        for step in steps:
            carried = "" if step in pairs else "   <- no stage carries this one"
            print(f"  {describe(step)}{carried}")
        print("A stage jumping a version, or written in the wrong direction, carries")
        print("no store anywhere while reading as though it does.")
        return 3

    if uncovered:
        print("UNCOVERED: a step between two schema versions has no migration stage.")
        for step in uncovered:
            print(f"  {describe(step)}")
        print(f"{len(versions)} version(s) in schemas, {len(pairs)} stage(s) declared,")
        print(f"{len(steps)} step(s) to carry.")
        print("SwiftData does not refuse a missing stage: it opens a store that looks fine,")
        print("and a renamed property, a changed type or a new required relationship is")
        print("gone from it. PRD 5.30: Ovation deletes nothing automatically, ever.")
        print("Add the stage in the same change as the version.")
        return 1

    if len(versions) == 1:
        print(f"OK: 1 schema version ({versions[0]}), so there is no chain to check yet.")
        print("    No stage is required and none is declared. This checked a chain of")
        print("    length zero, which is not the same as having verified one.")
        return 0

    print(f"OK: {len(versions)} schema versions, {len(pairs)} stage(s), every step covered.")
    for step in steps:
        print(f"    {describe(step)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
