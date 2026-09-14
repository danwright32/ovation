#!/usr/bin/env python3
"""Refuse a generated Xcode project that does not list the Swift files on disk.

ovation#206. project.yml lists DIRECTORIES and the generated Ovation.xcodeproj
lists FILES, so a Swift file added after the project was generated is invisible
to every build until somebody regenerates by hand. `lib/ensure-xcode-project.sh`
deliberately only CREATES a project where there is none, so it never notices,
and nothing else looked.

IT BIT ON 2026-09-10 while building ovation#162: YearEndExportCommand.swift was
written, the build failed with `cannot find 'YearEndExportCommand' in scope`
from a file that plainly referenced it, and the cause was the project rather
than the code. That error names the wrong subject, so the diagnosis starts in
the wrong place (L11). This names the right one, and the command that fixes it.

WHAT IS COMPARED. Every Swift file ON DISK under the source directories
project.yml names, against every Swift file REFERENCE in the generated
project.pbxproj. On disk rather than tracked in git, because the incident was a
file written and built before anything was committed, and regeneration reads the
directories, not the index. Both directions: a file the project does not list is
not compiled, and a file the project lists that is gone fails the build with
another message about the wrong thing.

BY NAME, COUNTED. The project file lists a reference by its file name inside a
tree of groups, so names are compared, and compared as counts: two files called
the same thing in two directories are two references, and a project listing one
of them is stale.

WHAT IT DOES NOT SEE, said rather than left to be assumed from its name (L400).
A Swift file excluded from EVERY target by project.yml would read as missing
from the project; the one exclude today removes a file from the pure test target
while the app target still lists it. And it compares file SETS, never build
settings or target membership.

WHERE IT RUNS. The push gate, in seconds and before the suite, which is where a
person meets it; and scripts/run-tests.sh, before either Swift suite is built
from the project, so a direct run meets it too. Both run this one script, so the
two cannot disagree about what "current" means (L70).

Seams: OVATION_REPO_ROOT, OVATION_XCODE_PROJECT.

Exit codes, one per outcome (L11):
    0  the project lists every Swift file on disk, and nothing else
    1  it does not, and the files are named, both ways
    2  there is no generated project, or no project file inside it, so nothing
       can be stale: the next run generates one from these directories
    3  nothing could be compared: no project.yml, no source directory, no Swift
       file on disk, or no Swift reference read from the project. A reader that
       read nothing is not a verdict about the project (L98)
"""
import collections
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.environ.get("OVATION_REPO_ROOT") or os.path.dirname(HERE)
PROJECT = os.environ.get("OVATION_XCODE_PROJECT") or os.path.join(REPO_ROOT, "Ovation.xcodeproj")
REMEDY = "bash scripts/regenerate-xcode-project.sh"

# A `- path: X` item, which in project.yml is a target's source. An `excludes`
# item is a bare string and a dependency is `- sdk:`, `- target:` or
# `- package:`, so neither can match.
SOURCE_PATH = re.compile(r"""^\s*-\s*path:\s*["']?([^"'#\s]+)["']?\s*$""")
FILE_REFERENCE = re.compile(r'isa = PBXFileReference;.*?\bpath = ("(?:[^"\\]|\\.)*"|[^;]+);')

# More than this many names in one direction is a project that predates a large
# change, and the rest of the list adds nothing a person can act on.
SHOWN = 20


def refuse(code, *lines):
    print("\n".join(lines))
    sys.exit(code)


def source_directories(spec):
    found = []
    with open(spec, encoding="utf-8") as fh:
        for line in fh:
            match = SOURCE_PATH.match(line)
            if match and match.group(1) not in found:
                found.append(match.group(1))
    return [d for d in found if os.path.isdir(os.path.join(REPO_ROOT, d))]


def swift_files_on_disk(directories):
    paths = set()
    for directory in directories:
        for root, dirs, files in os.walk(os.path.join(REPO_ROOT, directory)):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for name in files:
                if name.endswith(".swift") and not name.startswith("."):
                    paths.add(os.path.relpath(os.path.join(root, name), REPO_ROOT))
    return sorted(paths)


def swift_references(project_file):
    names = []
    with open(project_file, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            match = FILE_REFERENCE.search(line)
            if not match:
                continue
            path = match.group(1)
            if path.startswith('"'):
                path = path[1:-1].replace('\\"', '"')
            if path.endswith(".swift"):
                names.append(os.path.basename(path))
    return names


def listed(label, items):
    lines = ["    %s: %s" % (label, item) for item in items[:SHOWN]]
    if len(items) > SHOWN:
        lines.append("    and %d more" % (len(items) - SHOWN))
    return lines


def main():
    spec = os.path.join(REPO_ROOT, "project.yml")
    if not os.path.isfile(spec):
        refuse(3, "REFUSED: there is no project.yml at %s, so there are no source" % REPO_ROOT,
               "         directories to compare the project against. Nothing was checked.")

    directories = source_directories(spec)
    if not directories:
        refuse(3, "REFUSED: project.yml names no source directory that exists, so there",
               "         is nothing to compare the project against. Nothing was checked.")

    project_file = os.path.join(PROJECT, "project.pbxproj")
    if not os.path.isdir(PROJECT) or not os.path.isfile(project_file):
        refuse(2, "CANNOT MEASURE: there is no generated project file at %s," % project_file,
               "    so none can be stale. The next run generates one from project.yml.",
               "    Nothing was compared. This is not a pass.")

    on_disk = swift_files_on_disk(directories)
    if not on_disk:
        refuse(3, "REFUSED: no Swift files were found under %s, so a comparison" % ", ".join(directories),
               "         would pass on nothing. Nothing was checked.")

    references = swift_references(project_file)
    if not references:
        refuse(3, "REFUSED: no Swift file references could be read from %s," % project_file,
               "         while %d Swift files are on disk. That is a project file this" % len(on_disk),
               "         cannot read, not a verdict that it is stale. Nothing was checked.")

    disk_names = collections.Counter(os.path.basename(p) for p in on_disk)
    project_names = collections.Counter(references)
    unlisted_names = disk_names - project_names
    gone_names = project_names - disk_names

    if not unlisted_names and not gone_names:
        print("OK: the generated project lists all %d Swift files under %s."
              % (len(on_disk), ", ".join(directories)))
        return 0

    unlisted = [p for p in on_disk if os.path.basename(p) in unlisted_names]
    gone = sorted(gone_names.elements())
    lines = ["REFUSED: the generated project does not list the Swift files on disk, so a",
             "         build compiles a different set of files than this tree holds, and",
             "         fails, when it does, with an error about the code instead of this."]
    lines += listed("on disk, not in the project", unlisted)
    lines += listed("in the project, not on disk", gone)
    lines += ["         Regenerate it, then run again:",
              "         " + REMEDY]
    print("\n".join(lines))
    return 1


if __name__ == "__main__":
    sys.exit(main())
