#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Say how close the real launch backups have come to their deadline.

    report-launch-backups.sh

ovation#557. The launch backup's deadline (ovation#507) grows with what it
copies, from allowances in Ovation/Backup/LaunchBackupOutcome.swift that were
calibrated on a synthetic 300MB folder, never on Dan's real backups. Past the
deadline a launch that would upgrade the store refuses to open (ovation#505). So
every launch backup now appends one line to launch-backups.jsonl in the data
folder, and this is its reader: the place the allowances are re-judged from.
Stored data needs a reader (L46).

WHAT IS JUDGED IS THE WHOLE COPY ALONE. Only a `taken` line timed a backup
that was written and verified. A backup already taken that day did almost
nothing, and one that refused or failed stopped early, so counting either as a
backup would report more headroom than there is (L331). They are counted beside
it, by outcome, so the population the figure comes from is stated (L629).

A LAUNCH THAT GAVE UP IS SAID OUT LOUD. Its elapsed time is the deadline, not a
measurement of the copy, which may still have been running, so it is not folded
into the share: it is the finding itself, a folder the allowances did not cover.

READ ONLY. It opens the record, reads it and prints; it writes nothing anywhere.

Seam: OVATION_LAUNCH_BACKUP_RECORD, the record to read. The default is the one
the installed (Release) Ovation writes. Its suite names a throwaway copy on every
case, so no test reads Dan's record (L2).

Exit codes, one per outcome (L11):
    0  the record was read and reported, including one holding no whole copy yet
    2  nothing could be judged: no record, a record that could not be read, or one
       in which no line decoded
"""
import json
import os
import sys
from datetime import datetime

DEFAULT = os.path.expanduser(
    "~/Library/Application Support/Ovation/launch-backups.jsonl")
RECORD = os.environ.get("OVATION_LAUNCH_BACKUP_RECORD") or DEFAULT

# The outcomes LaunchBackupTiming.Outcome writes, in the words a reader wants.
OUTCOMES = {
    "taken": "took a whole copy",
    "alreadyTakenToday": "found that day's backup already taken",
    "folderUnreachable": "could not read the backup folder",
    "refused": "were refused by the backup",
    "failed": "failed for another reason",
    "gaveUp": "gave up at the deadline",
}
REQUIRED = ("at", "elapsedMilliseconds", "deadlineMilliseconds", "outcome")


def cannot_measure(why):
    print("CANNOT MEASURE: " + why)
    print("    Nothing was judged. This is not a report of healthy backups.")
    sys.exit(2)


def read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            lines = [line for line in handle.read().splitlines() if line.strip()]
    except FileNotFoundError:
        cannot_measure("there is no launch backup record at " + path + ".\n"
                       "    No launch has backed up since ovation#557 shipped, or the "
                       "installed Ovation predates it.")
    except OSError as error:
        cannot_measure("the record at " + path + " could not be read: " + str(error) + ".")

    timings, skipped, reasons = [], 0, []
    for line in lines:
        try:
            timing = json.loads(line)
        except ValueError:
            skipped += 1
            reasons.append("not JSON")
            continue
        reason = refusal(timing)
        if reason:
            skipped += 1
            reasons.append(reason)
            continue
        timings.append(timing)
    if not timings:
        cannot_measure("the record at " + path + " holds " + str(len(lines))
                       + " line(s) and none of them could be read as a launch backup.")
    return timings, skipped, reasons


def whole_number(value):
    """An integer, and not a boolean, which Python counts as one."""
    return isinstance(value, int) and not isinstance(value, bool)


def refusal(timing):
    """Why a decoded line is not a launch backup, naming the field, or None.

    EVERY FIELD THE REPORT USES IS TYPE CHECKED HERE, not only the ones it
    divides by. A line whose keys were all present with one of the wrong type
    passed and then crashed the report, and a check that confirms a key EXISTS
    says nothing about whether it can be used. The Swift reader refuses the same
    lines by decoding into typed fields (LaunchBackupTiming), so the two agree.
    """
    if not isinstance(timing, dict):
        return "the line is not an object"
    for key in REQUIRED:
        if key not in timing:
            return key + " is not there"
    if not isinstance(timing["at"], str):
        return "at is not a date"
    if timing["outcome"] not in OUTCOMES:
        return "outcome is not one Ovation writes"
    for key in ("elapsedMilliseconds", "deadlineMilliseconds"):
        if not whole_number(timing[key]) or timing[key] < 0:
            return key + " is not a whole number of milliseconds"
    if timing["deadlineMilliseconds"] == 0:
        return "deadlineMilliseconds is not a whole number of milliseconds above zero"
    # The size is written as a pair or not at all, so half of one is damage.
    if ("files" in timing) != ("bytes" in timing):
        return ("files" if "files" not in timing else "bytes") + " is not there beside its pair"
    for key in ("files", "bytes"):
        if key in timing and (not whole_number(timing[key]) or timing[key] < 0):
            return key + " is not a whole number"
    return None


def day(timing):
    try:
        return datetime.strptime(timing["at"], "%Y-%m-%dT%H:%M:%SZ").strftime("%Y-%m-%d")
    except ValueError:
        return timing["at"]


def size(timing):
    if "files" in timing and "bytes" in timing:
        return "{} files, {:,} bytes".format(timing["files"], timing["bytes"])
    return "size not measured"


def main():
    timings, skipped, reasons = read(RECORD)
    print("Launch backups recorded in " + RECORD + ": " + str(len(timings)))
    for outcome, words in OUTCOMES.items():
        count = sum(1 for t in timings if t["outcome"] == outcome)
        if count:
            print("    {} {}".format(count, words))
    if skipped:
        # The first reason is named, so a writer that changed a field's type is
        # found from this line rather than from a count alone.
        print("    and {} line(s) that could not be read, which are not counted ({}{})".format(
            skipped, reasons[0],
            "" if skipped == 1 else ", and " + str(skipped - 1) + " more"))

    whole = [t for t in timings if t["outcome"] == "taken"]
    if whole:
        tightest = max(whole, key=lambda t: t["elapsedMilliseconds"] / t["deadlineMilliseconds"])
        share = 100 * tightest["elapsedMilliseconds"] / tightest["deadlineMilliseconds"]
        print("Tightest whole copy: {:.1f}% of its deadline ({} ms of {} ms), {}, on {}.".format(
            share, tightest["elapsedMilliseconds"], tightest["deadlineMilliseconds"],
            size(tightest), day(tightest)))
    else:
        print("No launch has taken a whole copy yet, so there is no headroom to judge.")

    gave_up = [t for t in timings if t["outcome"] == "gaveUp"]
    if gave_up:
        newest = gave_up[-1]
        print("GAVE UP: {} launch(es) stopped waiting at the deadline, most recently on {} "
              "({}, {} ms deadline).".format(len(gave_up), day(newest), size(newest),
                                             newest["deadlineMilliseconds"]))
        print("    The allowances in Ovation/Backup/LaunchBackupOutcome.swift did not cover "
              "that folder, or the folder was slow that day.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
