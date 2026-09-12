#!/usr/bin/env python3
"""Refuse an entry point that does not run the store launch sequence.

ovation#88. This guard exists because of exactly what it guards against.
`StoreSchemaGuard` was written and fully tested by ovation#52 and then called by
NOTHING for as long as it took somebody to notice, because ovation#52 said the
sequence belonged with the launch presenter and ovation#59 shipped without it.
The refusal that stops Core Data creating its tables inside another app's
database was inert, while reading, to anyone auditing this repository, exactly
like a live safeguard. Built is not wired, and wired is not proven (L3).

WHY A SCRIPT RATHER THAN A TEST. `OvationApp.swift` carries `@main` and is the
one file the pure test target cannot compile, by design (project.yml), so no test
in the suite can reach the wiring. A guard that cannot be written as a test is
the case where a scan is the only instrument there is, and its absence is what
let the first omission last (L621: a behaviour each call site must opt into
cannot be enforced by asking politely).

WHAT IT CHECKS, and deliberately no more. That the entry point CONSTRUCTS the
sequence and CALLS it. It cannot check that the order inside the sequence is
right, because that is `StoreLaunchSequenceTests`, and a scan that claimed to
verify the ordering would be claiming more than it measured (L11).

NOTHING SCANNED IS NOT A PASS (L98). An entry point file that is not there, or
that no longer carries @main, is its own refusal rather than a clean run.

Seams: OVATION_ENTRY_POINT.

Exit codes, one per outcome (L11):
    0  the entry point builds the sequence and runs it
    1  the entry point does not build it
    2  the entry point is not there, or does not carry @main
    3  it builds the sequence and never runs it, which is the shape of the
       original defect: the parts present and the protection absent
    4  it never checks for a second running copy, or checks and runs anyway
    5  it never takes the store the sequence opened, so the export control has
       nothing to run against and is a dead menu item
"""
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENTRY = os.environ.get("OVATION_ENTRY_POINT",
                       os.path.join(REPO_ROOT, "Ovation", "App", "OvationApp.swift"))

CONSTRUCTS = re.compile(r"\bStoreLaunchSequence\s*\(")
RUNS = re.compile(r"\.run\s*\(\s*now\s*:")
# ovation#84. The second copy check has the same shape of problem as the sequence
# itself: it lives in the one file no test can compile, and it is only a
# safeguard if the entry point both ASKS and HONOURS the answer.
ASKS_ABOUT_SECOND_COPY = re.compile(r"\bSecondInstance\.check\s*\(")
HONOURS_SECOND_COPY = re.compile(r"\bmayRun\b")
# ovation#162. The export control runs over the store this sequence opened, and
# `onOpened` is the only way it can have it: opening a second container would be
# a second writer over one file, which is what the check above exists to prevent.
# Without this wiring the menu item is there and does nothing, which is the same
# shape as building the sequence and never running it.
TAKES_THE_OPENED_STORE = re.compile(r"\.onOpened\s*=")
# ovation#246. The sequence now runs from a task once the window exists, so a
# launch can SAY what it is doing. Two things have to be true and neither is
# visible to any test, because this file is the one the pure target cannot
# compile:
#
#   it runs from a task     if it went back into init, the window would be absent
#                           again while it works, and a slow backup and an app
#                           that will not start would look identical (L98)
#   it runs ONCE            a re-entered launch opens a second container over one
#                           file, which is two writers: the exact thing the second
#                           copy check above exists to prevent (ovation#84)
RUNS_FROM_A_TASK = re.compile(r"\.task\s*\{")
RUNS_ONLY_ONCE = re.compile(r"\bhasLaunched\b")


def fail(code, message):
    print("check-launch-sequence-wired: " + message, file=sys.stderr)
    sys.exit(code)


def main():
    if not os.path.isfile(ENTRY):
        fail(2, "the entry point is not at %s, so nothing was checked. That is not "
                "a clean run: it means this guard has lost its subject." % ENTRY)

    with open(ENTRY, encoding="utf-8") as handle:
        source = handle.read()

    if "@main" not in source:
        fail(2, "%s carries no @main, so it is not the entry point any more and this "
                "guard is pointed at the wrong file." % ENTRY)

    # Comments are stripped first. A file that only MENTIONS the sequence in a
    # comment explaining why it does not run it would otherwise satisfy a guard
    # that cannot tell the line doing the thing from the line about it (L103).
    code = re.sub(r"//[^\n]*", "", source)

    if not CONSTRUCTS.search(code):
        fail(1, "%s never builds a StoreLaunchSequence. The store is opened without "
                "identifying it first, which is how Core Data creates its tables "
                "inside another app's database and reports nothing wrong." % ENTRY)

    if not RUNS.search(code):
        fail(3, "%s builds a StoreLaunchSequence and never calls run(now:). That is "
                "the exact shape of the defect this guard exists for: the parts "
                "present, the protection absent." % ENTRY)

    # ovation#84. Two copies over one store are two writers of Dan's invoices,
    # and every serialized writer Ovation has serializes within ONE process, so
    # nothing inside them can see a second one. ASKING is not enough: the answer
    # has to gate the sequence, because standing aside AFTER checkpointing,
    # backing up and opening is standing aside after doing the dangerous part.
    if not ASKS_ABOUT_SECOND_COPY.search(code):
        fail(4, "%s never asks SecondInstance.check whether another copy is running. "
                "Two copies over one store are two writers of the same invoices, and "
                "the serialized writers cannot see each other across processes." % ENTRY)

    if not HONOURS_SECOND_COPY.search(code):
        fail(4, "%s asks whether another copy is running and never reads the answer. "
                "The check is present and the protection is absent, which is the same "
                "shape as building the sequence and not running it." % ENTRY)

    if not TAKES_THE_OPENED_STORE.search(code):
        fail(5, "%s never takes the store the sequence opened, so nothing after launch "
                "can read it. The year end export control would be a menu item that "
                "does nothing, and opening a second container instead would be a "
                "second writer over one file." % ENTRY)

    if not RUNS_FROM_A_TASK.search(code):
        fail(6, "%s runs the launch sequence without a task, so it is back inside "
                "init and the window does not exist while it works. A slow backup "
                "and an app that will not start then look identical, and there is "
                "nowhere to say which it is (ovation#246)." % ENTRY)

    if not RUNS_ONLY_ONCE.search(code):
        fail(6, "%s runs the launch from a task and nothing stops it running twice. "
                "A second run opens a second container over one file, which is two "
                "writers of Dan's invoices: the thing the second copy check exists "
                "to prevent, arriving from inside one process (ovation#84)." % ENTRY)

    print("OK: the entry point builds the launch sequence, runs it once from a task, "
          "stands aside for a second running copy, and takes the store it opened.")


main()
