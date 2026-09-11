#!/usr/bin/env python3
"""Refuse a PRD citation that names a requirement which is not there.

    check-prd-citations.sh [tree root]

ovation#199. The design record, the design files, the plan, the source and the
issues cite PRD requirements several hundred times, in two forms: `PRD 5.14a`,
section qualified, and `PRD 14a`, which resolves to section 5 because the
numbered requirements sit under `## 5. What Ovation must do`. Nothing verified
that any of them named a requirement that exists.

A WRONG CITATION IS INVISIBLE, AND WORSE THAN A DANGLING LINK. A reader follows
it, finds a number, and reads whatever is at it, coming away believing the
requirement says something.

WHAT THIS CANNOT CATCH, SAID HERE BECAUSE THE DIFFERENCE IS THE WHOLE VALUE. A
citation that resolves to a REAL requirement saying something else passes. That
is the fault that actually happened on 2026-09-10: ovation#190 said PRD 5.14a
makes unused held money owed back, 14a says nothing of the kind, and the claim
was copied from the issue into a new requirement and into the design record
before anybody read 14a. All three were corrected in place, and this check would
have passed every one of them. Existence is checkable; agreement is not.

BOTH FORMS ARE ACCEPTED rather than the repo being swept to one. Dan's call on
2026-09-10: the sweep is a large mechanical diff for a readability gain, and the
check does not need it.

A CONTINUATION IN A LIST IS A CITATION. The one real defect in the tree was
written as a section qualifier followed by `and` and a second number, and a check
reading only the token after the word PRD would have had its first half fixed and
left the second dangling with nothing able to say so. So `and` and comma separated tokens after a citation are resolved
too. That is deliberately generous: it is the reason `PRD 5.5, 5.5b and 5.5c`
costs three resolutions rather than one.

ONE ENUMERATION PATH. Files come from `git ls-files`, always, so the path that
ships is the path a fixture drives. A root that is not a git work tree is CANNOT
MEASURE rather than a walk of the directory, because a second enumeration leaves
the real one exercised only by the committed tree (L101).

NO FILE IN THIS TREE MAY SPELL A BROKEN CITATION, this one and the suites
included, because the scan cannot tell a line that NAMES a bad citation from one
that MAKES one. That is the check working rather than a defect in it: it is the
same shape as a style gate that cannot tell the line banning a character from the
line using it. A file that has to demonstrate a broken citation composes the word
and the number instead of writing them adjacent. The alternative, an exemption
list, would be a hand written registry that silently excuses whatever nobody
remembered to add, which is the one file the check exists for (L96, L448).

THREE THINGS THAT ARE NOT A PASS, each with its own message, because a check
that cannot distinguish them reports a broken scan as a clean one (L11, L98):
a PRD it cannot read, a PRD declaring no requirements at all, and a tree in which
it found no citations to resolve.

Exit codes, one per outcome:

    0  every citation found resolves to a requirement that exists
    1  at least one does not, and it says which, in which file, on which line
    2  it could not measure: no PRD, no requirements in it, no citations found,
       a root it cannot enumerate, or a tracked file it could not open, whose
       citations therefore went unchecked
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# A section heading, `## 5. What Ovation must do`.
SECTION = re.compile(r'^##\s+(\d+)\.')

# A requirement label at the start of a line, `14a.`, `3.`, `52g.`, `5a0.`.
#
# THE TRAILING DIGITS ARE NOT DECORATION. `5a0` is a real requirement, and a
# pattern reading a number then letters stops before the 0, resolves a citation
# of `PRD 5a0` to `5a`, and reports a requirement that is there as missing. The
# throwaway parser written while measuring this issue did exactly that and named
# 5a0 as the first dangling citation in the repository.
LABEL = re.compile(r'^(\d+[a-z]*\d*)\.\s')

# One citation token, optionally qualified by its section: `5.14a`, `14a`, `9.3`.
TOKEN = r'(?:(\d+)\.)?(\d+[a-z]*\d*)'

# `PRD` then a token, then any number of `, ` or ` and ` separated further
# tokens. The separator is matched before the token so that a full stop ending a
# sentence cannot join two citations.
CITATION = re.compile(r'\bPRD\s+' + TOKEN + r'((?:\s*,\s*|\s+and\s+)' + TOKEN + r')*')
CONTINUATION = re.compile(r'(?:\s*,\s*|\s+and\s+)' + TOKEN)

# The section a bare token belongs to. The numbered requirements are section 5's
# list, so `PRD 14a` and `PRD 5.14a` are the same citation written two ways.
BARE_SECTION = "5"


def requirements(path):
    """Every requirement label the PRD declares, by section, or a reason it could not be read."""
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as why:
        return None, "cannot read %s: %s" % (path, why.strerror or why)

    found = {}
    section = None
    for line in text.split("\n"):
        heading = SECTION.match(line)
        if heading:
            section = heading.group(1)
            continue
        label = LABEL.match(line)
        if label and section is not None:
            found.setdefault(section, set()).add(label.group(1))

    if not found:
        return None, "%s declares no numbered requirements this can resolve against" % path
    return found, None


def tracked_files(root):
    """Every file git tracks under root, or a reason it could not be listed."""
    try:
        listing = subprocess.run(["git", "ls-files", "-z"], cwd=root,
                                 capture_output=True)
    except OSError as why:
        return None, "cannot run git in %s: %s" % (root, why)
    if listing.returncode != 0:
        return None, ("%s is not a git work tree, so its files cannot be enumerated"
                      % root)
    names = [n for n in listing.stdout.decode("utf-8", "replace").split("\0") if n]
    if not names:
        return None, "git tracks no files in %s" % root
    return names, None


def citations_in(text):
    """Every (section, item, line number) this text cites."""
    found = []
    for number, line in enumerate(text.split("\n"), 1):
        for match in CITATION.finditer(line):
            found.append((match.group(1) or BARE_SECTION, match.group(2), number))
            rest = match.group(3)
            if rest:
                for more in CONTINUATION.finditer(rest):
                    found.append((more.group(1) or BARE_SECTION, more.group(2), number))
    return found


def main(argv):
    root = os.path.abspath(argv[1]) if len(argv) > 1 else ROOT

    declared, why = requirements(os.path.join(root, "PRD.md"))
    if declared is None:
        print("CANNOT MEASURE: %s" % why)
        return 2

    names, why = tracked_files(root)
    if names is None:
        print("CANNOT MEASURE: %s" % why)
        return 2

    total = 0
    not_text = 0
    unopenable = []
    dangling = []
    for name in names:
        path = os.path.join(root, name)
        try:
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
        except UnicodeDecodeError:
            # NOT TEXT. An icon or a font carries no citations, and skipping it
            # is the right answer rather than a gap.
            not_text += 1
            continue
        except OSError as why:
            # COULD NOT BE OPENED, which is a different fact and a fault: git
            # says the file is here and this could not read it, so its citations
            # went unchecked. Folding it in with the binaries above made a
            # permission fault and a PNG the same event (L11).
            unopenable.append((name, why.strerror or str(why)))
            continue
        for section, item, line in citations_in(text):
            total += 1
            if item not in declared.get(section, ()):
                dangling.append((name, line, section, item))

    # A SCAN THAT MATCHED NOTHING IS NOT A CLEAN TREE. Every citation in the
    # repository disappearing and the pattern silently ceasing to match produce
    # the same silence, and the second is the one worth hearing about.
    if total == 0:
        print("CANNOT MEASURE: no PRD citations were found in the %d files git tracks"
              % len(names))
        print("    Either nothing cites the PRD, or this stopped matching them.")
        return 2

    # A FILE GIT TRACKS THAT COULD NOT BE OPENED IS REPORTED ON EVERY PATH, and
    # it is reported BEFORE the verdict on the citations, because whatever it
    # holds went unchecked and a verdict that did not say so would be a claim
    # about the whole tree made from part of it.
    if unopenable:
        print("CANNOT MEASURE: %d file(s) git tracks could not be opened, so their"
              % len(unopenable))
        print("                citations went unchecked either way.")
        for name, why in unopenable:
            print("  %s: %s" % (name, why))
        return 2

    if dangling:
        print("REFUSED: %d of the %d PRD citations in this tree name a requirement that is not there."
              % (len(dangling), total))
        for name, line, section, item in dangling:
            print("  %s:%d cites PRD %s.%s, and section %s has no requirement %s"
                  % (name, line, section, item, section, item))
        print("  A reader follows a wrong citation, finds a number, and believes")
        print("  whatever is at it. Correct the citation, or the PRD.")
        return 1

    sections = ", ".join(sorted(declared, key=int))
    print("PASS: all %d PRD citations in %d tracked files resolve."
          % (total, len(names)))
    print("      %d requirements declared across sections %s."
          % (sum(len(v) for v in declared.values()), sections))
    if not_text:
        print("      %d file(s) were not text and were not scanned." % not_text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
