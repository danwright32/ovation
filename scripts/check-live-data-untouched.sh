#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Assert that a test run wrote nothing to Ovation's real data.

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
process list that could not be read is never taken to mean closed (L98).

A CHANGE THE INSTALLED APP EXPLAINS IS DAN'S OWN USE, AND DOES NOT FAIL THE RUN
(ovation#591). It used to be a refusal of its own, and on 2026-09-27 it refused
two runs before a push, each a twenty minute rerun, for nothing but Dan opening
Ovation: each store write fell in the same second as the app's last launch. Once
he uses it daily that is most pushes, and a guard that fails most pushes for the
person's own work is one people learn to route around (L36).

WHAT IT EXPLAINS IS NARROW, because the guard exists for the other case (L2):

  - only when the installed app RAN DURING THE RUN: open at the snapshot, open at
    the compare, or LAUNCHED after the snapshot, which is how an app opened and
    quit inside the run is seen. The launch is read from macOS's own record of
    the bundle, `kMDItemLastUsedDate` on /Applications/Ovation.app, the path and
    never the name, and a date that cannot be read is not evidence it ran;
  - and only under `Ovation/`, the folder it writes. It never writes
    `Ovation-Debug`, so a change there is refused whatever was open.

Anything the installed app does not explain is refused as a leak exactly as
before, and the refusal separates what it explained from what it did not.

WHAT THIS GIVES UP, stated rather than discovered: a test that leaked into
`Ovation/` in the same run as Dan used the app cannot be told from his use, and
passes with the note. That is the trade #591 chose; the note names every path
that changed, so it is visible in the log, and the resolvers and
`check-isolation-floor.sh` still refuse the leak in the code.

Seams: OVATION_LIVE_DATA_ROOT; OVATION_LIVE_DATA_PROCESS_LIST, a command printing
one executable path per line in place of `ps -A -o comm=`; and
OVATION_LIVE_DATA_LAST_USED, a command printing the installed app's last launch
the way `mdls -raw -name kMDItemLastUsedDate` does. With both, the suite never
has to launch or quit anything, or read when Dan last did.

OVATION_LIVE_DATA_BRACKET_LOG names a file each SNAPSHOT appends the root it
fingerprinted to, one line per bracket opened (ovation#570). It exists for the
runner's own suite, which drives dozens of inner runs that each open this
bracket, and until then left every one of them measuring Dan's real folder: an
open app then failed a case at random. The suite reads this log to prove no inner
run measured a real path, by where the snapshot looked rather than by which
variables a helper remembered to set (L322). A log that cannot be written is said
on stderr and never fails the snapshot, because the bracket is the real work.

A WATCHED FOLDER THAT CANNOT BE READ IS NOT AN EMPTY ONE (ovation#581). The walk
used to skip a directory it could not list, so a folder it was barred from read
as holding nothing at both ends and the run passed having measured nothing
there. Any watched path that cannot be read is now CANNOT MEASURE (L98).

    snapshot <file>   record the fingerprint
    compare <file>    re-read and refuse on any difference

Exit codes, one per outcome (L11):
    0  nothing changed
    1  something changed that the installed app does not explain, and it is named
    2  nothing was measured: the command, the fingerprint file, or a watched path
       is not usable
    3  something changed and ALL of it is explained by the installed app having
       run during the run: Dan's own use, named, and not a failure. The runner
       passes it with the note (ovation#591).
"""
import datetime
import json
import os
import subprocess
import sys
import time

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

# The bundle it is launched from, whose last launch macOS records (ovation#591).
INSTALLED_BUNDLE = "/Applications/Ovation.app"

# The one folder the installed app writes. It explains a change under this and
# nothing else: `Ovation-Debug` is the Debug build's.
INSTALLED_APP_WRITES = "Ovation/"

# A process listing that hangs is not an answer, so it has a deadline (L110).
PROCESS_LIST_SECONDS = 30


class CannotMeasure(Exception):
    """A watched path exists and could not be read, so nothing about it is known."""


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


def installed_app_last_launched():
    """The instant macOS last launched the installed bundle, as seconds since the
    epoch, "never" when it holds no such date, or None when it could not be read.

    Asked of the BUNDLE PATH, so a Debug build called Ovation is never taken for
    it. Asked only at the compare, because only the compare needs it."""
    injected = os.environ.get("OVATION_LIVE_DATA_LAST_USED")
    command = ([injected] if injected else
               ["mdls", "-raw", "-name", "kMDItemLastUsedDate", INSTALLED_BUNDLE])
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=PROCESS_LIST_SECONDS)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    said = result.stdout.strip()
    if said == "(null)":
        return "never"
    try:
        return datetime.datetime.strptime(said, "%Y-%m-%d %H:%M:%S %z").timestamp()
    except ValueError:
        return None


def when_it_ran(running_before, running_now, launched, taken_at):
    """How the installed app ran during the run, as a sentence ending, or None
    when nothing measured shows it did."""
    if running_before is True and running_now is True:
        return "was running at the start and at the end of the run."
    if running_before is True:
        return "was running at the start of the run, and not at the end."
    if running_now is True:
        return "was running at the end of the run, and not at the start."
    # Whole seconds on both sides: the launch date is recorded to the second, so
    # an app launched in the snapshot's own second still counts as inside.
    if (isinstance(launched, float) and isinstance(taken_at, (int, float))
            and launched >= int(taken_at)):
        stamp = datetime.datetime.fromtimestamp(launched).strftime("%H:%M:%S")
        return f"was launched during the run, at {stamp}, and had quit by the end."
    return None


def record_bracket(root):
    """Appends the root this snapshot measured to the bracket log, when one is
    named (ovation#570). Best effort and said, never the verdict."""
    log = os.environ.get("OVATION_LIVE_DATA_BRACKET_LOG")
    if not log:
        return
    try:
        with open(log, "a", encoding="utf-8") as handle:
            handle.write(root + "\n")
    except OSError as error:
        print(f"could not record this bracket's root in {log}: {error}", file=sys.stderr)


def fingerprint(root):
    """A stable description of the watched set: what exists, how big, when.

    ABSENT ONLY WHEN IT IS NOT THERE. `os.path.isfile` answers False for a path it
    could not stat, and `os.walk` skips a directory it could not list, so both
    used to turn "could not look" into "nothing there" (ovation#581). Any failure
    to read a path that exists raises CannotMeasure instead."""
    entries = {}
    for relative in WATCHED:
        path = os.path.join(root, relative)
        try:
            stat = os.stat(path)
        except FileNotFoundError:
            entries[relative] = "absent"
            continue
        except OSError as error:
            raise CannotMeasure(f"{relative}: {error.strerror}") from error
        if os.path.isdir(path):
            # Size and time rather than a content hash: the question here is
            # whether anything changed, not whether it is corrupt, and the
            # documents folder is checked for content by its own verifier.
            inner = []

            def refuse(error):
                raise CannotMeasure(
                    f"{os.path.relpath(error.filename, root)}: {error.strerror}") from error

            for directory, _, filenames in os.walk(path, onerror=refuse):
                for filename in sorted(filenames):
                    full = os.path.join(directory, filename)
                    try:
                        inner_stat = os.stat(full)
                    except FileNotFoundError:
                        continue
                    except OSError as error:
                        raise CannotMeasure(
                            f"{os.path.relpath(full, root)}: {error.strerror}") from error
                    inner.append(f"{os.path.relpath(full, path)} "
                                 f"{inner_stat.st_size} {inner_stat.st_mtime_ns}")
            entries[relative] = "dir " + "|".join(sorted(inner))
        else:
            entries[relative] = f"file {stat.st_size} {stat.st_mtime_ns}"
    return entries


def main(argv):
    if len(argv) != 2 or argv[0] not in ("snapshot", "compare"):
        print("usage: check-live-data-untouched.sh snapshot|compare <fingerprint file>")
        return 2

    command, store = argv
    root = os.environ.get("OVATION_LIVE_DATA_ROOT") or os.path.join(
        os.path.expanduser("~"), "Library", "Application Support")

    taken_at = time.time()
    try:
        current = fingerprint(root)
    except CannotMeasure as error:
        print(f"CANNOT MEASURE: a watched path under {root} could not be read, {error}.")
        print("                A path that cannot be read is not an empty one, so this")
        print("                bracket measured nothing there. That is not a pass.")
        return 2
    running_now = installed_app_running()

    if command == "snapshot":
        record_bracket(root)
        try:
            with open(store, "w", encoding="utf-8") as handle:
                json.dump({"root": root, "entries": current, "taken_at": taken_at,
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
        # Asked only when the ends did not already show the app open, since only
        # then can it change the answer.
        launched = None
        if running_before is not True and running_now is not True:
            launched = installed_app_last_launched()
        ran = when_it_ran(running_before, running_now, launched, before.get("taken_at"))

        explained = [name for name in changed if ran and name.startswith(INSTALLED_APP_WRITES)]
        unexplained = [name for name in changed if name not in explained]

        if not unexplained:
            print("LIVE DATA CHANGED, and the installed app ran during the run, so this is")
            print("your own use of Ovation and this run is not failed for it.")
            for name in explained:
                print(f"  {name}")
            print(f"The installed app ({INSTALLED_APP}) {ran}")
            print("Every change is in the folder that app writes. A test writing there in the")
            print("same run could not be told apart, so the paths are named here.")
            return 3

        print("LIVE DATA CHANGED while the tests ran. That is not a pass.")
        if explained:
            print("Explained by the installed app, which ran during the run:")
            for name in explained:
                print(f"  {name}")
            print("Not explained by the installed app, which never writes Ovation-Debug:")
        for name in unexplained:
            print(f"  {name}")
        if ran:
            print(f"The installed app ({INSTALLED_APP}) {ran}")
            print("So a test reached live data, or a Debug build run from Xcode wrote to")
            print("Ovation-Debug while the tests ran.")
        elif running_before is None or running_now is None:
            print("Whether the installed app was running could not be read at one end of the")
            print("run, so it cannot be ruled out. Nothing measured shows it was closed.")
        elif launched is None:
            print("When the installed app was last launched could not be read, so whether it")
            print("was opened and quit during the run is not known. It was not running at")
            print("the start or at the end of the run.")
        else:
            print("The installed app was not running at the start or at the end of the run, "
                  "and was not launched during it.")
            print("So a test reached live data, or a Debug build run from Xcode wrote to")
            print("Ovation-Debug while the tests ran.")
        return 1

    print(f"OK: {len(current)} watched path(s) unchanged across the run.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
