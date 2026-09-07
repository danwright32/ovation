#!/usr/bin/env python3
"""Assert that a test run wrote nothing to Ovation's real data.

ovation#58, plan 1.9. Every live resolver refuses under a disposable launch, and
`scripts/check-isolation-floor.sh` refuses a resolver that is not registered.
Both of those read the CODE. This one measures the DISK.

WHY BOTH. A regression guard must assert the quantity it exists to protect,
never a proxy for it (L63). "Every resolver returns nil in this process" is a
proxy: a test that builds its own path, or a dependency constructed at a call
site, reaches the real folder without going through any resolver at all. What
this issue is actually about is that NOTHING LANDS THERE, so that is what is
measured, by fingerprinting the paths before and after a run.

WHAT IS WATCHED, and what deliberately is not. The watched set is what OVATION
writes: its store and write ahead log, the problems journal, the documents
folder, and the whole Debug tree.

`booking-queue` and `booking-queue.debug` are NOT watched. DOWNBEAT writes them,
and a booking Dan commits while a suite runs would be attributed to the suite. A
before and after comparison of shared state attributes every change it sees to
whatever it was bracketing, so on a store with a second legitimate writer it
accuses rather than finds (L375).

`custody/` is not watched for the same reason: those files are Dan's, placed by
hand, and a comparison cannot tell his hand from a test's.

THE OTHER FALSE ACCUSATION, stated in the message rather than left to be
puzzled over: running the app while the suite runs changes the Debug tree
legitimately. The refusal says so, so the reader can tell that case from a test
having reached live data.

Seam: OVATION_LIVE_DATA_ROOT.

    snapshot <file>   record the fingerprint
    compare <file>    re-read and refuse on any difference

Exit codes, one per outcome (L11):
    0  nothing changed
    1  something changed, and it is named
    2  the command or the fingerprint file is not usable
"""
import json
import os
import sys

# Relative to the Application Support root. Each is a file or a directory.
WATCHED = (
    "Ovation/Ovation.store",
    "Ovation/Ovation.store-wal",
    "Ovation/Ovation.store-shm",
    "Ovation/problems.jsonl",
    "Ovation/documents",
    "Ovation-Debug",
)


def fingerprint(root):
    """A stable description of the watched set: what exists, how big, when."""
    entries = {}
    for relative in WATCHED:
        path = os.path.join(root, relative)
        if os.path.isfile(path):
            stat = os.stat(path)
            entries[relative] = f"file {stat.st_size} {stat.st_mtime_ns}"
        elif os.path.isdir(path):
            # Size and time rather than a content hash: the question here is
            # whether anything changed, not whether it is corrupt, and the
            # documents folder is checked for content by its own verifier.
            inner = []
            for directory, _, filenames in os.walk(path):
                for filename in sorted(filenames):
                    full = os.path.join(directory, filename)
                    stat = os.stat(full)
                    inner.append(
                        f"{os.path.relpath(full, path)} {stat.st_size} {stat.st_mtime_ns}")
            entries[relative] = "dir " + "|".join(sorted(inner))
        else:
            entries[relative] = "absent"
    return entries


def main(argv):
    if len(argv) != 2 or argv[0] not in ("snapshot", "compare"):
        print("usage: check-live-data-untouched.sh snapshot|compare <fingerprint file>")
        return 2

    command, store = argv
    root = os.environ.get("OVATION_LIVE_DATA_ROOT") or os.path.join(
        os.path.expanduser("~"), "Library", "Application Support")

    current = fingerprint(root)

    if command == "snapshot":
        try:
            with open(store, "w", encoding="utf-8") as handle:
                json.dump({"root": root, "entries": current}, handle)
        except OSError as error:
            print(f"CANNOT MEASURE: the fingerprint could not be written to {store}: {error}")
            return 2
        print(f"OK: recorded {len(current)} watched path(s) under {root}.")
        return 0

    try:
        with open(store, "r", encoding="utf-8") as handle:
            before = json.load(handle)
    except (OSError, ValueError) as error:
        # A missing fingerprint means the run was never bracketed, which is not
        # the same as nothing having changed (L98).
        print(f"CANNOT MEASURE: no usable fingerprint at {store}: {error}")
        print("                The run was never bracketed, so nothing was measured.")
        return 2

    if before.get("root") != root:
        print("CANNOT MEASURE: the fingerprint was taken under a different root.")
        print(f"                before: {before.get('root')}")
        print(f"                now:    {root}")
        return 2

    changed = [name for name, value in current.items()
               if before.get("entries", {}).get(name) != value]
    if changed:
        print("LIVE DATA CHANGED while the tests ran. That is not a pass.")
        for name in changed:
            print(f"  {name}")
        print("Either a test reached live data, or Ovation itself was running at the time.")
        print("If the app was open, that explains a change under Ovation-Debug and nothing else.")
        return 1

    print(f"OK: {len(current)} watched path(s) unchanged across the run.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
