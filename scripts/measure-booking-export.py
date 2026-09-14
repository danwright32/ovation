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

    PRD 5, PRD 5a          how many clients carry a recorded tax status, and
                            how that splits into exempt and not exempt

WHAT IT CANNOT PRODUCE, said out loud rather than left looking reproducible.
ONE figure the record cites is not in this file and not in any other committed
source: how much money is held on a client. A number nobody can reproduce is a
defect rather than a fact, so the run says so every time rather than only when
somebody asks.

THE TAX STATUS USED TO BE ON THAT LIST AND WAS NEVER MISSING (ovation#215). This
docstring and the run both said the export has no field for a client's tax
status, and the suite asserted that sentence was printed, so three places agreed
with each other and none of them with the file. `isTaxExempt` was there the whole
time, on 6 of 31 clients, which is exactly the figure the record said could not
be re-derived, and Downbeat publishes it in its own CONTRACT.md. A claim that
something cannot be measured must come from attempting the measurement (L460).

THE LIVE EXPORT, TOO, WHEN IT IS PASSED (ovation#216). The snapshot is what the
cited figures must stay reproducible against, so it stays the subject of every
run. But it is frozen, and the file Ovation actually reads at launch is the live
one Downbeat rewrites on every launch, so a run can also be given that file with
`--live` and reports, figure by figure, where the two DISAGREE. It is verified by
SHAPE rather than by hash, because a file that legitimately changes can never
carry a recorded one: the shape is the one `Ovation/Domain/DownbeatExport.swift`
decodes, so a live file this refuses is one the app would refuse too. It is never
read unless its path is passed, so no suite can reach the real one by omission
(L2), and a run given none says so, so a snapshot only run is never read as having
looked at what the app reads (L98).

PRINTS COUNTS AND SHARES ONLY. Never a client, a venue, a shoot or a hosting
site. This file carries all four in plain text and the repository is public
(docs/PRIVACY-FLOOR.md). The comparison adds field NAMES and counts of ids, never
an id or a value.

IT VERIFIES THE HASH AT READ TIME, not only when the file was recorded, because
that is what docs/CUSTODY.md requires of every read of a custody file, and a
figure derived from a file that has changed underneath the record is worse than
no figure.

Exit codes, one per outcome (L11):

    0  measured, and the live export too when one was passed
    1  the file is there and could not be measured
    2  used wrongly, or the file is not there
    3  the file is there and its hash is not the one recorded
    4  the snapshot was measured and the live export could not be: absent,
       unreadable, or not the shape Ovation reads

Usage: measure-booking-export.py <downbeat-export.json> [expected-sha256] [--live <live-export.json>]
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

# THE SHAPE OVATION DECODES, from `Ovation/Domain/DownbeatExport.swift`: a whole
# number version no lower than its `minimumVersion`, an `exportedAt` its ISO 8601
# decoder accepts (which takes no fractional seconds), and clients carrying a
# UUID id, a name and both addresses, with `isTaxExempt` optional. This is a
# second statement of that decoder, so it is written to be read against it line
# for line, and a change there is a change here.
MINIMUM_VERSION = 2
INSTANT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})$")
UUID = re.compile(r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")
CLIENT_STRINGS = ("displayName", "email", "contractEmail")
FIELD_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9]{0,39}$")


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


def figures(export):
    """Every figure this script reports, in print order.

    ONE MEASUREMENT FOR BOTH FILES. The snapshot and the live export are
    measured by this one function, so a difference the comparison reports is a
    difference in the FILES and never in two ways of counting (L70, L263).

    Each entry is (section, label, value). A label of None is a sentence rather
    than a figure, printed as it stands and never compared."""
    out = []
    bookings = export.get("bookings") or []
    clients = export.get("clients") or []
    venues = export.get("venues") or []

    section = "EXPORT"
    out.append((section, "version", "%s" % export.get("version")))
    out.append((section, "bookings", "%d" % len(bookings)))
    out.append((section, "clients", "%d" % len(clients)))
    out.append((section, "venues", "%d" % len(venues)))
    out.append((section, "blocked dates", "%d" % len(export.get("blockedDates") or [])))

    lengths, unreadable = [], 0
    for booking in bookings:
        span = seconds_between(booking.get("startsAt"), booking.get("endsAt"))
        if span is None:
            unreadable += 1
        else:
            lengths.append(span)
    section = "HOW LONG A COMMITTED BOOKING RUNS"
    if lengths:
        exactly = sum(1 for s in lengths if s == ONE_HOUR)
        out.append((section, "readable", "%d of %d" % (len(lengths), len(bookings))))
        out.append((section, "exactly one hour",
                    "%d   %.0f%%" % (exactly, 100.0 * exactly / len(lengths))))
        out.append((section, "shortest", "%.2f hours" % (min(lengths) / ONE_HOUR)))
        out.append((section, "longest", "%.2f hours" % (max(lengths) / ONE_HOUR)))
    else:
        out.append((section, None,
                    "none carried a readable pair of instants, so nothing was measured"))
    out.append((section, "instants that could not be read", "%d" % unreadable))

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
    section = "WHERE AN INVOICE WOULD BE SENT (PRD 37c, PRD 38a)"
    of = len(clients)
    out.append((section, "clients with no main address", "%d of %d" % (main_missing, of)))
    out.append((section, "overrides that are empty", "%d of %d" % (empty_override, of)))
    out.append((section, "overrides copying the main", "%d of %d" % (copy_override, of)))
    out.append((section, "clients giving several addresses", "%d of %d" % (several, of)))
    out.append((section, "clients whose value is not one", "%d of %d" % (not_an_address, of)))

    # THE TAX STATUS, MEASURED RATHER THAN DECLARED ABSENT (ovation#215). The
    # record said this export carries no field for it, and printed that sentence
    # here on every run, while `isTaxExempt` sat in the client shape Downbeat
    # publishes in its own CONTRACT.md. A claim that something cannot be measured
    # has to come from attempting the measurement, or nothing downstream ever
    # contradicts it (L460).
    #
    # THREE STATES, NOT TWO. Absent is a real answer meaning nobody has ever
    # recorded one, and folding it into "not exempt" would report a client as
    # confirmed taxable on the strength of a missing key (L257, PRD 5).
    exempt = sum(1 for c in clients if c.get("isTaxExempt") is True)
    not_exempt = sum(1 for c in clients if c.get("isTaxExempt") is False)
    never = sum(1 for c in clients if c.get("isTaxExempt") is None)
    section = "CLIENT TAX STATUS (PRD 5, PRD 5a)"
    out.append((section, "clients carrying a recorded status", "%d of %d" % (exempt + not_exempt, of)))
    out.append((section, "recorded as exempt", "%d of %d" % (exempt, of)))
    out.append((section, "recorded as not exempt", "%d of %d" % (not_exempt, of)))
    out.append((section, "clients with no recorded status", "%d of %d" % (never, of)))

    behaviours = collections.Counter()
    for client in clients:
        behaviours[len(client.get("specialBehaviors") or [])] += 1
    section = "SPECIAL BEHAVIOURS PER CLIENT"
    for count in sorted(behaviours):
        out.append((section, "clients holding %d" % count, "%d" % behaviours[count]))
    return out


def report(measured):
    section = None
    for where, label, value in measured:
        if where != section:
            print("%s%s" % ("" if section is None else "\n", where))
            section = where
        if label is None:
            print("  %s" % value)
        else:
            print("  %-34s %s" % (label, value))


def shape_refusal(export):
    """Why a live export is not the shape Ovation reads, or None when it is.

    NAMED BY POSITION, NEVER BY NAME. A client that fails is "client 3", because
    its display name is exactly what may not be printed (docs/PRIVACY-FLOOR.md)."""
    if not isinstance(export, dict):
        return "it is not a JSON object"
    version = export.get("version")
    if not isinstance(version, int) or isinstance(version, bool):
        return "it carries no whole number version"
    if version < MINIMUM_VERSION:
        return "version %d is below the floor of %d" % (version, MINIMUM_VERSION)
    if not isinstance(export.get("exportedAt"), str) or not INSTANT.match(export["exportedAt"]):
        return "it carries no readable exportedAt instant"
    clients = export.get("clients")
    if not isinstance(clients, list):
        return "clients is not a list"
    for number, client in enumerate(clients, 1):
        if not isinstance(client, dict):
            return "client %d is not an object" % number
        if not isinstance(client.get("id"), str) or not UUID.match(client["id"]):
            return "client %d has no UUID id" % number
        for field in CLIENT_STRINGS:
            if not isinstance(client.get(field), str):
                return "client %d has no string %s" % (number, field)
        if "isTaxExempt" in client and not isinstance(client["isTaxExempt"], bool):
            return "client %d has an isTaxExempt that is neither true nor false" % number
    for key in ("bookings", "venues", "blockedDates"):
        if key in export and not isinstance(export[key], list):
            return "%s is not a list" % key
    return None


def keys_of(rows):
    names = set()
    for row in rows:
        if isinstance(row, dict):
            names |= set(row.keys())
    return names


def compare(snapshot, live):
    """Where the live export and the snapshot DISAGREE, figure by figure.

    Counts and field names only: an id that is in one file and not the other is
    counted and never printed, because the count is the finding and the id is a
    handle on a client."""
    print("\nLIVE AGAINST SNAPSHOT (ovation#216)")
    ours = [(label, value) for _, label, value in figures(snapshot) if label]
    theirs = dict((label, value) for _, label, value in figures(live) if label)
    labels = [label for label, _ in ours] + [l for l in theirs if l not in dict(ours)]
    ours = dict(ours)
    differ = 0
    for label in labels:
        a, b = ours.get(label, "none"), theirs.get(label, "none")
        if a != b:
            differ += 1
            print("  %-34s snapshot %-10s live %s" % (label, a, b))

    elsewhere = 0
    for noun, key in (("booking", "bookings"), ("client", "clients")):
        mine = {r.get("id") for r in snapshot.get(key) or [] if isinstance(r, dict)}
        yours = {r.get("id") for r in live.get(key) or [] if isinstance(r, dict)}
        elsewhere += len(yours - mine) + len(mine - yours)
        print("  %-40s %d" % ("%s ids only in the live export" % noun, len(yours - mine)))
        print("  %-40s %d" % ("%s ids only in the snapshot" % noun, len(mine - yours)))

    shapes = (("top level", [snapshot], [live]),
              ("client", snapshot.get("clients") or [], live.get("clients") or []),
              ("booking", snapshot.get("bookings") or [], live.get("bookings") or []),
              ("venue", snapshot.get("venues") or [], live.get("venues") or []))
    for noun, mine, yours in shapes:
        a, b = keys_of(mine), keys_of(yours)
        for side, extra in (("the live export", b - a), ("the snapshot", a - b)):
            if not extra:
                continue
            elsewhere += len(extra)
            named = sorted(k for k in extra if FIELD_NAME.match(k))
            odd = len(extra) - len(named)
            said = ", ".join(named) + ("%s%d key(s) not shaped like a field name"
                                       % (", " if named else "", odd) if odd else "")
            print("  %-40s %s" % ("%s fields only in %s" % (noun, side), said))

    if differ or elsewhere:
        print("  %d figure(s) differ, and %d id(s) or field(s) are in one file and "
              "not the other" % (differ, elsewhere))
    else:
        print("  no figure differs, and no id or field is in one and not the other")


def main(argv):
    args = list(argv[1:])
    live = None
    if "--live" in args:
        at = args.index("--live")
        if at + 1 >= len(args) or args[at + 1].startswith("--"):
            print(__doc__.strip().splitlines()[-1])
            return 2
        live = args[at + 1]
        del args[at:at + 2]
    if len(args) not in (1, 2):
        print(__doc__.strip().splitlines()[-1])
        return 2
    path = args[0]
    if not os.path.isfile(path):
        print("CANNOT MEASURE: no export at %s. That is not a pass: every "
              "figure below would otherwise be missing rather than zero." % path)
        return 2

    expected = args[1] if len(args) == 2 else RECORDED
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

    if not (export.get("bookings") or []) and not (export.get("clients") or []):
        print("CANNOT MEASURE: the export holds no booking and no client, so "
              "nothing was measured. An empty export and a healthy one must not "
              "report the same thing.")
        return 1

    report(figures(export))

    # SAID EVERY RUN, not only when somebody asks. A figure the record cites with
    # no committed source at all would otherwise look as reproducible as the ones
    # above (L316, L98).
    #
    # THE TAX STATUS WAS ON THIS LIST AND SHOULD NEVER HAVE BEEN. It is measured
    # above, from the field that was here the whole time (ovation#215, L460), so
    # what is left here is the one figure that genuinely is not in any source.
    print("\nWHAT THIS EXPORT CANNOT ANSWER")
    print("  money held on a client: this export carries nothing about payments")
    print("  and the FreshBooks export is invoices rather than clients, so that")
    print("  figure cannot be re-derived from any committed source.")

    if live is None:
        print("\nLIVE EXPORT NOT MEASURED: no --live path was given, so every figure "
              "above describes the snapshot and none describes the file Ovation "
              "reads at launch (docs/CUSTODY.md records where that is).")
        return 0

    # THE SNAPSHOT'S FIGURES STAND WHATEVER HAPPENS HERE. They were printed
    # above, so a live file that cannot be measured costs only the comparison,
    # and says so under its own exit code rather than as a snapshot failure (L11).
    if not os.path.isfile(live):
        print("\nCANNOT MEASURE THE LIVE EXPORT: no file at %s. The snapshot's "
              "figures above stand; how the file Ovation reads differs from them "
              "is unknown." % live)
        return 4
    try:
        with open(live, encoding="utf-8") as handle:
            current = json.load(handle)
    except (ValueError, OSError) as err:
        # The error's TYPE, never its message: a decoding message can quote the
        # text it choked on, and that text is somebody's name.
        print("\nCANNOT MEASURE THE LIVE EXPORT: it could not be read as JSON (%s)."
              % type(err).__name__)
        return 4
    refusal = shape_refusal(current)
    if refusal:
        print("\nCANNOT MEASURE THE LIVE EXPORT: %s, so it is not the shape Ovation "
              "reads (Ovation/Domain/DownbeatExport.swift)." % refusal)
        return 4
    compare(export, current)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
