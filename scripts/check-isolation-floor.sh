#!/usr/bin/env python3
"""Refuse a live data resolver that the isolation floor does not know about.

ovation#58, plan 1.9. Every resolver that can reach live data already refuses on
its own under a disposable launch, which is the structural half: the wrong thing
cannot be written rather than being discouraged (L2, L196).

WHAT NO RESOLVER CAN DO IS NOTICE THAT A NEW ONE EXISTS. `LiveDataFloor` is the
register, and this is what makes the register true. A guard driven by a hand
written list checks only what the list names, so anything missing from it is
exempt from the very check meant to catch it, and the guard reports green while
blind (L96). This closes that by deriving the SUBJECTS from the sources and
holding the list to them (L247).

THE NAMING RULE IT RESTS ON. A resolver that answers "where does this live for a
real launch" is a static `live...` member. The scan finds every one of those in
the app sources and requires its name to appear in LiveDataFloor.swift.

The known limit, stated rather than discovered: it matches on the member NAME,
so two resolvers on different types sharing one name would both be satisfied by
a single registration. Registering by type as well would mean parsing Swift, and
the names are checked for uniqueness here instead, which catches exactly that.

NOTHING SCANNED IS NOT A PASS (L98). A scan that found no resolvers at all is a
scan that has stopped working, because there are four.

Seams: OVATION_FLOOR_SCAN_ROOT and OVATION_FLOOR_REGISTER.

Exit codes, one per outcome (L11):
    0  every live resolver is registered
    1  a resolver is not in the register
    2  nothing was scanned, or the register itself is not there
    3  two resolvers share one name, so one registration answers for both
"""
import os
import re
import sys

DECLARATION = re.compile(r"\bstatic\s+(?:func|var|let)\s+(live[A-Za-z0-9_]*)\b")


def swift_files(root):
    found = []
    for directory, _, filenames in os.walk(root):
        for filename in sorted(filenames):
            if filename.endswith(".swift"):
                found.append(os.path.join(directory, filename))
    return sorted(found)


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = os.environ.get("OVATION_FLOOR_SCAN_ROOT") or os.path.join(repo_root, "Ovation")
    register = os.environ.get("OVATION_FLOOR_REGISTER") or os.path.join(
        root, "App", "LiveDataFloor.swift")

    if not os.path.isdir(root):
        print(f"CANNOT SCAN: {root} is not a directory, so nothing was checked.")
        return 2
    if not os.path.isfile(register):
        print(f"CANNOT SCAN: the register is not at {register}.")
        print("             Without it there is nothing to hold the resolvers to.")
        return 2

    with open(register, "r", encoding="utf-8", errors="replace") as handle:
        register_text = handle.read()

    found = {}
    for path in swift_files(root):
        if os.path.abspath(path) == os.path.abspath(register):
            continue
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for number, line in enumerate(handle.read().splitlines(), start=1):
                code = line.split("//", 1)[0]
                for match in DECLARATION.finditer(code):
                    name = match.group(1)
                    found.setdefault(name, []).append(
                        (os.path.relpath(path, root), number))

    if not found:
        print(f"CANNOT SCAN: no live data resolvers found under {root}.")
        print("             That is not a pass: there are four, so a scan finding")
        print("             none has stopped working rather than found a clean tree.")
        return 2

    shared = {name: sites for name, sites in found.items() if len(sites) > 1}
    if shared:
        print("AMBIGUOUS: two resolvers share one name, so one registration answers for both.")
        for name, sites in sorted(shared.items()):
            places = ", ".join(f"{path}:{line}" for path, line in sites)
            print(f"  {name}: {places}")
        return 3

    missing = [(name, sites[0]) for name, sites in sorted(found.items())
               if f'name: "{name}"' not in register_text]
    if missing:
        print("UNREGISTERED: a resolver can reach live data and the floor does not know about it.")
        for name, (path, line) in missing:
            print(f"  {path}:{line}: {name}")
        print("Add it to LiveDataFloor.entries, with what it reaches in plain words.")
        print("The floor is extended explicitly by every milestone, never by whoever notices.")
        return 1

    print(f"OK: {len(found)} live data resolver(s), every one registered in the floor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
