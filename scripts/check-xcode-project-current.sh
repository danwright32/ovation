#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a generated Xcode project that does not list the Swift files on disk.

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

AND THE PACKAGES BLOCK, against the project's XCRemoteSwiftPackageReference
entries (ovation#419). A `packages:` entry is a project.yml change that is not a
file set change, so every check above passes it while no machine that already
holds a generated project ever builds it. Compared by REPOSITORY URL, which is
the one field both sides carry, with a trailing `.git` ignored because each side
keeps the spelling it was handed.

AND WHICH TARGET LINKS WHICH PACKAGE, each target's `- package:` entries against
its packageProductDependencies. Adding a package to a SECOND target is the other
half of ovation#424's shape, and the package list alone cannot see it, because
the package is already there.

WHAT IT DOES NOT SEE, said rather than left to be assumed from its name (L400).
A Swift file excluded from EVERY target by project.yml would read as missing
from the project; the one exclude today removes a file from the pure test target
while the app target still lists it. It does not compare `- sdk:` or `- target:`
dependencies and it does not read build settings: those are held by
scripts/test-project-configuration.sh, which REGENERATES the project first and
reads the resolved values, so it answers a different question and answers it
only when that suite runs. And it does not see which target a SWIFT FILE belongs
to, only that the project lists the file at all.

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
       file on disk, no Swift reference read from the project, or a package
       declared or held that this could not read a URL for. A reader that read
       nothing is not a verdict about the project (L98)
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
# Inside the top level `packages:` block: a package's own name is a key with
# nothing after the colon, and its repository is the indented `url:` under it.
# `from:` and `branch:` carry a value, so neither can match the name line.
PACKAGE_NAME = re.compile(r"""^\s{2}([A-Za-z0-9_.\-]+):\s*$""")
PACKAGE_URL = re.compile(r"""^\s{3,}url:\s*["']?([^"'#\s]+)["']?\s*$""")
REPOSITORY_URL = re.compile(r'\brepositoryURL\s*=\s*("(?:[^"\\]|\\.)*"|[^;]+);')
PACKAGE_REFERENCE = re.compile(r'\bisa\s*=\s*XCRemoteSwiftPackageReference\s*;')
# A target's own name inside project.yml's `targets:` block, and the package a
# target names under its `dependencies:`. `- sdk:` and `- target:` are the other
# two kinds and neither can match, which case 22 of the suite holds it to.
TARGET_NAME = re.compile(r'^\s{2}([A-Za-z0-9_.\-]+):\s*$')
TARGET_PACKAGE = re.compile(r'^\s*-\s*package:\s*["\']?([^"\'#\s]+)["\']?\s*$')
NATIVE_TARGET = re.compile(r'\bisa\s*=\s*PBXNativeTarget\s*;')
OBJECT_NAME = re.compile(r'^\s*name\s*=\s*("(?:[^"\\]|\\.)*"|[^;]+);')
PRODUCTS_OPEN = re.compile(r'^\s*packageProductDependencies\s*=\s*\(')
PRODUCT_ENTRY = re.compile(r'^\s*[0-9A-Fa-f]+\s*/\*\s*(.+?)\s*\*/\s*,')
OBJECT_CLOSE = re.compile(r'^\t\t\};')
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


def declared_packages(spec):
    """(names, urls) from project.yml's packages block, in the order declared.

    Returned as two lists rather than one mapping because they are counted
    against each other: a package entry this read no URL for is a package it
    cannot compare, which is its own outcome rather than an absence."""
    names, urls = [], []
    inside = False
    with open(spec, encoding="utf-8") as fh:
        for line in fh:
            stripped = line.strip()
            if not inside:
                inside = line.startswith("packages:")
                continue
            if not stripped or stripped.startswith("#"):
                continue
            if not line[0].isspace():
                break
            match = PACKAGE_NAME.match(line)
            if match:
                names.append(match.group(1))
                continue
            match = PACKAGE_URL.match(line)
            if match:
                urls.append(match.group(1))
    return names, urls


def declared_target_packages(spec):
    # {target name: [package product, ...]} from project.yml's targets block.
    #
    # Only `- package:` entries. An `- sdk:` or `- target:` dependency is a
    # different kind and is not compared, which the docstring states rather
    # than leaving it to be inferred from the name (L400).
    wanted = collections.defaultdict(list)
    inside = False
    target = None
    with open(spec, encoding="utf-8") as fh:
        for line in fh:
            stripped = line.strip()
            if not inside:
                inside = line.startswith("targets:")
                continue
            if not stripped or stripped.startswith("#"):
                continue
            if not line[0].isspace():
                break
            match = TARGET_NAME.match(line)
            if match:
                target = match.group(1)
                continue
            match = TARGET_PACKAGE.match(line)
            if match and target:
                wanted[target].append(match.group(1))
    return wanted


def held_target_packages(project_file):
    # ({target name: [package product, ...]}, count of entries not readable).
    #
    # The product name is read from the comment xcodegen writes beside each id,
    # because the id alone is a pointer and following it is a second pass over
    # the same file. An entry with no comment is COUNTED rather than skipped: a
    # reader that silently drops what it cannot parse reports the target as
    # holding less than it does, which reads exactly like drift (L98).
    held = {}
    unreadable = 0
    in_target = False
    in_products = False
    name = None
    products = []
    with open(project_file, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if NATIVE_TARGET.search(line):
                in_target = True
                name, products = None, []
                continue
            if not in_target:
                continue
            if in_products:
                if line.strip().startswith(")"):
                    in_products = False
                    continue
                match = PRODUCT_ENTRY.match(line)
                if match:
                    products.append(match.group(1))
                elif line.strip():
                    unreadable += 1
                continue
            if PRODUCTS_OPEN.match(line):
                in_products = True
                continue
            if name is None:
                match = OBJECT_NAME.match(line)
                if match:
                    value = match.group(1).strip()
                    if value.startswith('"'):
                        value = value[1:-1].replace('\\"', '"')
                    name = value
            if OBJECT_CLOSE.match(line):
                if name is not None:
                    held[name] = products
                in_target = False
    return held, unreadable


def held_packages(project_file):
    """(reference count, urls) from the generated project's package references."""
    count = 0
    urls = []
    with open(project_file, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if PACKAGE_REFERENCE.search(line):
                count += 1
            match = REPOSITORY_URL.search(line)
            if match:
                url = match.group(1).strip()
                if url.startswith('"'):
                    url = url[1:-1].replace('\\"', '"')
                urls.append(url)
    return count, urls


def same_repository(url):
    """One spelling for one repository, so .git and a trailing slash are not a
    second package. Case is left alone: a path can be case sensitive."""
    url = url.strip().rstrip("/")
    if url.endswith(".git"):
        url = url[: -len(".git")]
    return url


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

    # THE FILE SET VERDICT COMES FIRST, and the order is the decision rather than
    # a detail. The package readers below can answer "could not be read" on a
    # project file that is stale in files too, and a could not measure over a
    # real, nameable staleness is the less actionable of the two while both have
    # the same remedy. ovation#206's contract is that this exits 1 and names the
    # files, so the class it was written for keeps its own verdict.
    if unlisted_names or gone_names:
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

    declared_names, declared_urls = declared_packages(spec)
    if len(declared_urls) < len(declared_names):
        refuse(3, "REFUSED: project.yml declares %d package%s but this could read a URL for"
               % (len(declared_names), "" if len(declared_names) == 1 else "s"),
               "         only %d of them, so the packages could not be compared. A package" % len(declared_urls),
               "         named with `github:` or `path:` rather than `url:` is this reader's",
               "         gap, not a stale project. Nothing was compared.")

    reference_count, held_urls = held_packages(project_file)
    if reference_count != len(held_urls):
        refuse(3, "REFUSED: the generated project holds %d package reference%s and this could"
               % (reference_count, "" if reference_count == 1 else "s"),
               "         read a repository URL from only %d, so it could not be read." % len(held_urls),
               "         That is a project file this cannot read, not a package that is",
               "         missing. Nothing was compared.")

    declared_set = collections.Counter(same_repository(u) for u in declared_urls)
    held_set = collections.Counter(same_repository(u) for u in held_urls)
    unbuilt = sorted((declared_set - held_set).elements())
    orphaned = sorted((held_set - declared_set).elements())

    wanted_membership = declared_target_packages(spec)
    held_membership, unreadable_entries = held_target_packages(project_file)
    if unreadable_entries:
        refuse(3, "REFUSED: %d package product entr%s in the generated project could not be"
               % (unreadable_entries, "y" if unreadable_entries == 1 else "ies"),
               "         read, so which target holds which package could not be read. That",
               "         is a project file this cannot read, not a target missing a package.",
               "         Nothing was compared.")
    if wanted_membership and not held_membership:
        refuse(3, "REFUSED: project.yml gives %d target%s a package dependency and no target"
               % (len(wanted_membership), "" if len(wanted_membership) == 1 else "s"),
               "         could be read from the generated project, so which target holds",
               "         which package could not be read. Nothing was compared.")

    wrong_membership = []
    for target in sorted(set(wanted_membership) | set(held_membership)):
        wanted = collections.Counter(wanted_membership.get(target, []))
        actually = collections.Counter(held_membership.get(target, []))
        for product in sorted((wanted - actually).elements()):
            wrong_membership.append("%s should link %s and does not" % (target, product))
        for product in sorted((actually - wanted).elements()):
            wrong_membership.append("%s links %s, which project.yml does not give it" % (target, product))

    if unbuilt or orphaned or wrong_membership:
        lines = ["REFUSED: the generated project does not hold the packages project.yml",
                 "         declares, so the build resolves a different dependency set than",
                 "         this tree declares, and fails with an error about a missing module."]
        lines += listed("declared in project.yml, not in the project", unbuilt)
        lines += listed("in the project, not declared in project.yml", orphaned)
        lines += listed("linked by the wrong target", wrong_membership)
        lines += ["         Regenerate it, then run again:",
                  "         " + REMEDY]
        print("\n".join(lines))
        return 1

    packages = ("and holds the %d package%s project.yml declares"
                % (len(declared_set), "" if len(declared_set) == 1 else "s")
                if declared_set else "and neither declares nor holds a package")
    print("OK: the generated project lists all %d Swift files under %s, %s."
          % (len(on_disk), ", ".join(directories), packages))
    return 0


if __name__ == "__main__":
    sys.exit(main())
