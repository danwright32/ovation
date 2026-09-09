#!/usr/bin/env python3
"""Measure the SHAPE of Dan's Downbeat export, for the design record.

ovation#121. Every number the design record and the PRD cite was produced by a
script written in a session scratchpad and deleted when the session ended, so
nothing could produce any of them again. `measure-invoice-history.py` closed
that for the FreshBooks invoices. This closes it for the OTHER source: the
Downbeat export, which is where the booking, client, address and venue figures
came from.

The numbers it re-derives, each cited in the record beside it:

    PRD 3, PRD 5.3a         16 of 19 committed bookings run exactly one hour
    PRD 37c                 all 31 clients have a main address, 1 override is
                            empty, the other 30 are an exact copy of the main
    PRD 38a                 1 of 31 carries two addresses in one field, on
                            purpose, and 1 of 31 carries something that is not
                            an address at all
    design README           31 clients, and how many hold a special behaviour

WHAT IT CANNOT PRODUCE, said out loud rather than left looking reproducible.
Two figures the record cites are NOT in this file and not in any other committed
source: how many clients carry a recorded tax status (the record says 6 of 31),
and how much money is held on a client. This export has no field for either. A
number nobody can reproduce is a defect rather than a fact, so the run says so
every time rather than only when somebody asks.

PRINTS COUNTS AND SHARES ONLY. Never a client, a venue, a shoot or a hosting
site. This file carries all four in plain text and the repository is public
(docs/PRIVACY-FLOOR.md).

IT VERIFIES THE HASH AT READ TIME, not only when the file was recorded, because
that is what docs/CUSTODY.md requires of every read of a custody file, and a
figure derived from a file that has changed underneath the record is worse than
no figure.

Exit codes, one per outcome (L11):

    0  measured
    1  the file is there and could not be measured
    2  used wrongly, or the file is not there
    3  the file is there and its hash is not the one recorded

Usage: measure-booking-export.py <downbeat-export.json> [expected-sha256]
"""
import collections
import hashlib
import json
import os
import re
import sys

# The recorded hash of the snapshot the figures in the record came from
# (docs/CUSTODY.md, downbeat-export-v3-2026-09-05.json). Passed in rather than
# read from the document, so a test can drive this with a file of its own.
RECORDED = "14a5b3ef98b69b2a6d7da387dd215415b7fcf844d2bbd4e7c144855947a719b6"

ONE_HOUR = 3600.0
# An address, judged the way PRD 38a judges one: something with an `@` and no
# spaces inside it. A value carrying several, comma separated, is a VALUE
# meaning all of them, so each part is judged on its own.
LOOKS_LIKE_AN_ADDRESS = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def digest(path):
    sha = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            sha.update(block)
    return sha.hexdigest()


def seconds_between(start, end):
    """The length of a booking, or None when either instant is unreadable.

    NEVER A ZERO STANDING IN FOR ONE. A booking whose instants cannot be parsed
    is counted as unreadable and reported, because scoring it as a zero length
    shoot would quietly move the one hour share (L11)."""
    from datetime import datetime
    try:
        a = datetime.fromisoformat(start.replace("Z", "+00:00"))
        b = datetime.fromisoformat(end.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None
    return (b - a).total_seconds()


def main(argv):
    if len(argv) not in (2, 3):
        print(__doc__.strip().splitlines()[-1])
        return 2
    path = argv[1]
    if not os.path.isfile(path):
        print("CANNOT MEASURE: no export at %s. That is not a pass: every "
              "figure below would otherwise be missing rather than zero." % path)
        return 2

    expected = argv[2] if len(argv) == 3 else RECORDED
    got = digest(path)
    if expected and got != expected:
        print("REFUSED: the export's SHA-256 is not the one recorded.")
        print("  recorded  %s" % expected)
        print("  found     %s" % got)
        print("  docs/CUSTODY.md requires the hash to be verified at read time. "
              "A figure derived from a file that changed underneath the record "
              "is worse than no figure.")
        return 3

    try:
        with open(path, encoding="utf-8") as handle:
            export = json.load(handle)
    except (ValueError, OSError) as err:
        print("CANNOT MEASURE: the export could not be read: %s" % err)
        return 1

    bookings = export.get("bookings") or []
    clients = export.get("clients") or []
    venues = export.get("venues") or []
    if not bookings and not clients:
        print("CANNOT MEASURE: the export holds no booking and no client, so "
              "nothing was measured. An empty export and a healthy one must not "
              "report the same thing.")
        return 1

    print("EXPORT")
    print("  version                    %s" % export.get("version"))
    print("  bookings                   %d" % len(bookings))
    print("  clients                    %d" % len(clients))
    print("  venues                     %d" % len(venues))
    print("  blocked dates              %d" % len(export.get("blockedDates") or []))

    lengths, unreadable = [], 0
    for booking in bookings:
        span = seconds_between(booking.get("startsAt"), booking.get("endsAt"))
        if span is None:
            unreadable += 1
        else:
            lengths.append(span)
    print("\nHOW LONG A COMMITTED BOOKING RUNS")
    if lengths:
        exactly = sum(1 for s in lengths if s == ONE_HOUR)
        print("  readable                   %d of %d" % (len(lengths), len(bookings)))
        print("  exactly one hour           %d   %.0f%%"
              % (exactly, 100.0 * exactly / len(lengths)))
        print("  shortest                   %.2f hours" % (min(lengths) / ONE_HOUR))
        print("  longest                    %.2f hours" % (max(lengths) / ONE_HOUR))
    else:
        print("  none carried a readable pair of instants, so nothing was measured")
    print("  instants that could not be read  %d" % unreadable)

    main_missing = empty_override = copy_override = 0
    several = not_an_address = 0
    for client in clients:
        primary = (client.get("email") or "").strip()
        override = (client.get("contractEmail") or "").strip()
        if not primary:
            main_missing += 1
        if not override:
            empty_override += 1
        elif override == primary:
            copy_override += 1
        # COUNTED PER CLIENT, NOT PER VALUE. Thirty of the thirty one carry an
        # override that is an exact copy of the main address, so counting both
        # fields reports every one of these twice: the first run said "2" where
        # PRD 38a says 1 of 31, and both were the same client.
        values = {v for v in (primary, override) if v}
        parts = [p.strip() for v in values for p in v.split(",") if p.strip()]
        if any(len([p for p in v.split(",") if p.strip()]) > 1 for v in values):
            several += 1
        if any(not LOOKS_LIKE_AN_ADDRESS.match(p) for p in parts):
            not_an_address += 1
    print("\nWHERE AN INVOICE WOULD BE SENT (PRD 37c, PRD 38a)")
    print("  clients with no main address     %d of %d" % (main_missing, len(clients)))
    print("  overrides that are empty         %d of %d" % (empty_override, len(clients)))
    print("  overrides copying the main       %d of %d" % (copy_override, len(clients)))
    print("  clients giving several addresses %d of %d" % (several, len(clients)))
    print("  clients whose value is not one   %d of %d"
          % (not_an_address, len(clients)))

    behaviours = collections.Counter()
    for client in clients:
        behaviours[len(client.get("specialBehaviors") or [])] += 1
    print("\nSPECIAL BEHAVIOURS PER CLIENT")
    for count in sorted(behaviours):
        print("  %2d   %4d" % (count, behaviours[count]))

    # SAID EVERY RUN, not only when somebody asks. Two figures the record cites
    # have no committed source at all, and a run that stayed silent about them
    # would leave them looking as reproducible as the ones above (L316, L98).
    print("\nWHAT THIS EXPORT CANNOT ANSWER")
    print("  a client's recorded tax status: there is no field for it here, so")
    print("  the record's \"6 of 31 carry one\" cannot be re-derived from any")
    print("  committed source. Same for money held on a client.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
