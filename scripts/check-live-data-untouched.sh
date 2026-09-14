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

THE OTHER FALSE ACCUSATION IS THE INSTALLED APP (ovation#266). Since 2026-09-13
the Release build lives in /Applications and is in daily use, and merely having
it open, or quitting it, changes `Ovation.store-shm`. The refusal used to say a
running app "explains a change under Ovation-Debug and nothing else", which was
true while only Debug builds ran and became wrong the day the Release build was
installed: it sent the reader to the wrong cause (L11, L375).

So whether the installed app is running is RECORDED at snapshot and read again
at compare, identified by its EXECUTABLE PATH rather than its name, because a
Debug build run from Xcode is also called Ovation and writes somewhere else. A
change while it was running at either end cannot be told from a test having
written there, so it is still not a pass, but it is its own outcome: it says the
app was running and names what changed, rather than accusing the suite. A
change with the app closed at both ends is refused as a leak exactly as before,
and a process list that could not be read is never taken to mean closed (L98).

Its known gap, stated rather than discovered: an app opened AND quit entirely
between the two ends is not seen, and its change reads as a leak.

Seams: OVATION_LIVE_DATA_ROOT, and OVATION_LIVE_DATA_PROCESS_LIST, a command
printing one executable path per line in place of `ps -A -o comm=`, so the suite
never has to launch or quit anything.

    snapshot <file>   record the fingerprint
    compare <file>    re-read and refuse on any difference

Exit codes, one per outcome (L11):
    0  nothing changed
    1  something changed with the installed app closed at both ends, or with
       whether it was running unreadable, and it is named
    2  the command or the fingerprint file is not usable
    3  something changed while the installed app was running at either end, so
       the change cannot be attributed, and it is named
"""
import json
import os
import subprocess
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


# The installed Release build, by the path of the executable itself. Matched as
# the WHOLE line, so a Debug copy under DerivedData, which is also called Ovation,
# is never taken for it.
INSTALLED_APP = "/Applications/Ovation.app/Contents/MacOS/Ovation"

# A process listing that hangs is not an answer, so it has a deadline (L110).
PROCESS_LIST_SECONDS = 30


def installed_app_running():
    """True or False, or None when the process list could not be read.

    None is kept apart from False on purpose: a lookup that failed has not shown
    the app was closed, and treating it as closed would put the accusation back
    on the suite for a reason nobody measured (L98)."""
    injected = os.environ.get("OVATION_LIVE_DATA_PROCESS_LIST")
    command = [injected] if injected else ["ps", "-A", "-o", "comm="]
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=PROCESS_LIST_SECONDS)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return any(line.strip() == INSTALLED_APP for line in result.stdout.splitlines())


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
    running_now = installed_app_running()

    if command == "snapshot":
        try:
            with open(store, "w", encoding="utf-8") as handle:
                json.dump({"root": root, "entries": current,
                           "installed_app_running": running_now}, handle)
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
        # A fingerprint written before ovation#266 has no record, which is the
        # same fact as a lookup that failed: nothing showed the app was closed.
        running_before = before.get("installed_app_running")
        if running_before is True or running_now is True:
            print("LIVE DATA CHANGED while the installed app was running, so the change")
            print("cannot be attributed to the tests or cleared of them. That is not a pass.")
            for name in changed:
                print(f"  {name}")
            if running_before is True and running_now is True:
                when = "at the start and at the end of the run"
            elif running_before is True:
                when = "at the start of the run, and not at the end"
            else:
                when = "at the end of the run, and not at the start"
            print(f"The installed app ({INSTALLED_APP}) was running {when}.")
            print("Quit it and run again: a change with it closed at both ends is a leak.")
            return 3

        print("LIVE DATA CHANGED while the tests ran. That is not a pass.")
        for name in changed:
            print(f"  {name}")
        if running_before is None or running_now is None:
            print("Whether the installed app was running could not be read at one end of the")
            print("run, so it cannot be ruled out. Nothing measured shows it was closed.")
        else:
            print("The installed app was not running at the start or at the end of the run.")
            print("So a test reached live data, or a Debug build run from Xcode wrote to")
            print("Ovation-Debug while the tests ran.")
        return 1

    print(f"OK: {len(current)} watched path(s) unchanged across the run.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
