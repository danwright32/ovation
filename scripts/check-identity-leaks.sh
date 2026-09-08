#!/usr/bin/env python3
"""Refuse if a real client, venue or vendor identity appears anywhere in the tree.

ovation#5. The repository is PUBLIC for the whole build and Ovation's entire
subject matter is real people and real businesses.

THE DESIGN THIS DELIBERATELY DOES NOT COPY. The port source's guard reads its
needles from a machine local list. On this Mac that list did not exist, so it
reported `noList`, examined nothing, and a real venue name sat in four test files
the whole time (L217). Here the needles are DERIVED from the populations that
actually exist at this phase, and an empty derivation is a REFUSAL.

WHAT IT NEVER DOES: print a name. Its output goes into transcripts, terminal
scrollback and the end of turn review, by a route no file scanner inspects
(L222). Counts, paths and field names only. Anything that has to be read by eye,
Dan reads on his own screen.

IT WALKS THE DIRECTORY, not `git ls-files`. The highest risk content on this disk
is exactly what .gitignore excludes, and overture#3161 records the shape: an
ignore entry meaning "per machine" read by a guard as "do not look" (L250, L234).

MATCHING IS ON WORD BOUNDARIES, measured rather than assumed. A trial run over
this repository's six tracked files on 2026-09-05 matched exactly once: a six
character single word client display name that is also an ordinary English word,
inside a sentence about something else. A substring match over needles derived
from real business names WILL over match, and an over match reads exactly like
the feature working (L104). A multi word name is matched as a phrase, because
half a name is not the name.
"""
import json
import os
import re
import sys

EXPORT = os.environ.get("OVATION_GUARD_EXPORT",
                        os.path.expanduser("~/Library/Application Support/Overture/downbeat-export.json"))
CUSTODY = os.environ.get("OVATION_GUARD_CUSTODY_DIR",
                         os.path.expanduser("~/Library/Application Support/Ovation/custody"))
SCAN_ROOT = os.environ.get("OVATION_GUARD_SCAN_ROOT",
                           os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Directories a recursive walk must never descend into, BY NAME. A nested
# checkout holds a full second copy of everything.
SKIP_DIRS = {".git", "worktrees", "node_modules", "DerivedData", "build", ".build"}

# Binary and generated shapes there is no point reading.
SKIP_SUFFIXES = (".png", ".jpg", ".jpeg", ".pdf", ".zip", ".store", ".xcuserstate")

# A PLACEHOLDER IS NOT AN IDENTITY.
#
# Found on the guard's first real run against Dan's data. It refused on PRD.md,
# twice on one line, and the needle was "TBD": one of the nineteen real bookings
# carries venueName "TBD" because its venue is not decided yet, and the PRD says
# TBD twice in ordinary prose meaning exactly that.
#
# This is the RULE rather than an exemption naming that file (L362). A
# placeholder is a value the data uses to mean "not set". It identifies nobody,
# it is by construction an ordinary word or abbreviation, and searching for it
# can only ever produce noise, in every file, for ever.
#
# Dropped needles are COUNTED AND REPORTED, so a run whose needle set was thinned
# by this cannot read as a run that searched for everything (L98).
PLACEHOLDERS = {
    "tbd", "t.b.d.", "tba", "n/a", "na", "none", "null", "nil", "unknown",
    "unnamed", "untitled", "test", "example", "placeholder", "-", "?", "??",
    "pending", "not set", "no venue", "to be decided", "to be confirmed",
}


def needles_from_export(path, source_name, problems):
    """Client, venue and booking identities out of one export shaped file."""
    out = set()
    if not os.path.exists(path):
        return out
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        # An unreadable source is its own outcome. It is NOT zero needles, and it
        # is NOT a pass: reporting either would let a source that silently stopped
        # being readable look like a source with nothing in it (L98, L11).
        problems.append("%s could not be read (%s)" % (source_name, type(exc).__name__))
        return out
    for c in data.get("clients", []) or []:
        for key in ("displayName",):
            v = (c.get(key) or "").strip()
            if v:
                out.add(v)
        for key in ("contractEmail", "email"):
            v = (c.get(key) or "").strip()
            if "@" in v:
                out.add(v)
                domain = v.split("@", 1)[1].strip()
                # The domain without its public suffix is the business name, and
                # it is what turns up in prose and in test fixtures.
                if domain:
                    out.add(domain)
    for v_ in data.get("venues", []) or []:
        n = (v_.get("name") or "").strip()
        if n:
            out.add(n)
    for b in data.get("bookings", []) or []:
        for key in ("clientDisplayName", "venueName", "shootName"):
            v = (b.get(key) or "").strip()
            if v:
                out.add(v)
    return out


def build_matcher(needles):
    """One regex per needle, anchored on word boundaries.

    A multi word name is matched as a PHRASE with flexible whitespace, so a line
    break inside it still matches, and so that half a name never does.
    """
    matchers = []
    for n in sorted(needles):
        parts = [re.escape(p) for p in n.split()]
        if not parts:
            continue
        body = r"\s+".join(parts)
        # SPECIFICITY COMES FROM ONE OF TWO THINGS, and this is the rule the
        # measured false positive forced.
        #
        # A MULTI WORD name, or one carrying an @ or a dot, is specific enough on
        # its own, so it matches case insensitively: "brightwater chorale" in
        # lowercase prose is still that client.
        #
        # A SINGLE WORD name matches CASE SENSITIVELY. Real business names are
        # capitalised and ordinary prose is not, so "Stored" as a client name is
        # caught where it stands as a name and ignored in "the value is stored".
        # Measured on this repository 2026-09-05: a six character single word
        # client name matched once inside a sentence about something else, and a
        # case insensitive rule would fire on it for ever (L104).
        #
        # THE COST, STATED RATHER THAN DISCOVERED: a single word name at the
        # start of a sentence is capitalised too, so that one case can still fire.
        # That is the direction to fail in, and the guard prints paths rather than
        # names so a false positive costs a glance and never a disclosure.
        specific = len(parts) > 1 or "@" in n or "." in n
        flags = re.IGNORECASE if specific else 0
        matchers.append((n, re.compile(r"(?<![0-9A-Za-z])" + body + r"(?![0-9A-Za-z])",
                                       flags)))
    return matchers


def main():
    problems = []
    needles = set()
    needles |= needles_from_export(EXPORT, "the live export", problems)

    if os.path.isdir(CUSTODY):
        for name in sorted(os.listdir(CUSTODY)):
            if name.endswith(".json"):
                needles |= needles_from_export(os.path.join(CUSTODY, name),
                                               "a custody snapshot", problems)
    elif os.environ.get("OVATION_GUARD_CUSTODY_DIR"):
        pass  # a deliberately absent custody dir in a test is not a problem

    # TWO KINDS OF CANNOT MEASURE, AND THEY ARE NOT THE SAME EVENT (ovation#135).
    #
    # Both sources live OUTSIDE the repository. A machine that has NEITHER, a
    # fresh clone, a second Mac, a CI runner, cannot answer this and never could.
    # A machine that HAS one and cannot read it has something wrong with it.
    # Those were one outcome, and the gate turned both into "a real identity
    # appears in the tree. Push refused.", which is a refusal nobody can act on
    # and the shape that teaches people to reach for an override (L11, L148).
    #
    # 2 says nothing here could ever have answered, and a gate may allow the push
    # while naming what went unchecked. 4 says this machine had what it needed
    # and the answer still could not be got, which a gate refuses. Each has its
    # own sentence, because two outcomes given one wording are one outcome
    # however different their exit codes are (L260).
    export_present = os.path.exists(EXPORT)
    custody_present = os.path.isdir(CUSTODY)

    if not export_present and not custody_present:
        print("CANNOT MEASURE: no needle source exists on this machine.")
        print("    the live export is not at: " + EXPORT)
        print("    the custody directory is not at: " + CUSTODY)
        print("    Nothing was verified, and nothing here ever could have been.")
        print("    This machine never held the sources, so this is not evidence")
        print("    of a clean tree and not a fault in the tree either.")
        return 2

    # An absent live export on a machine that HOLDS custody data is this second
    # case, not the first. Until now it passed: the needles came from custody
    # alone and a smaller population found nothing, which is what a clean tree
    # looks like (L98).
    if not export_present:
        problems.append("the live export is not at the configured path")

    if problems:
        print("CANNOT MEASURE: a needle source is present here and could not be read.")
        for p in problems:
            print("    " + p)
        print("    Nothing was verified. The sources are on this machine, so this")
        print("    is a fault here rather than a machine that never had them.")
        print("    This is not a pass.")
        return 4

    dropped = sorted(n for n in needles if n.strip().lower() in PLACEHOLDERS)
    needles = {n for n in needles if n.strip().lower() not in PLACEHOLDERS}
    if dropped:
        print("Dropped %d placeholder value(s) that identify nobody." % len(dropped))

    if not needles:
        print("REFUSED: no needles could be derived, so nothing was searched for.")
        print("    Sources consulted: the live export, the custody snapshots.")
        print("    A guard with nothing to look for examines everything and finds")
        print("    nothing, which is indistinguishable from a clean tree.")
        return 3

    matchers = build_matcher(needles)

    files = 0
    hits = {}
    for root, dirs, filenames in os.walk(SCAN_ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith("agent-")]
        for fn in filenames:
            if fn.endswith(SKIP_SUFFIXES):
                continue
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, SCAN_ROOT)
            try:
                with open(full, encoding="utf-8", errors="ignore") as fh:
                    text = fh.read()
            except Exception:
                continue
            files += 1
            count = 0
            for _name, rx in matchers:
                found = len(rx.findall(text))
                count += found
            if count:
                hits[rel] = count

    print("Derived %d needle(s) from the export and custody snapshots." % len(needles))
    print("Examined %d file(s) under %s." % (files, SCAN_ROOT))

    if hits:
        print()
        print("REFUSED: a real identity appears in %d file(s)." % len(hits))
        print("    Paths and counts only. The names themselves are NOT printed:")
        print("    this output reaches transcripts and scrollback (L222).")
        for rel in sorted(hits):
            print("    %s  (%d occurrence(s))" % (rel, hits[rel]))
        return 1

    print("No derived identity appears anywhere under the scan root.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
