#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a design record whose measurement markings are wrong, and report the unmarked.

    check-design-measurements-marked.sh

ovation#201. `docs/design/README.md` argues from measured numbers: a row stays
318px, five figures share a right edge at 1246px, a screen is identical at 1440,
1280, 1180 and 1024, the rail palettes cleared 4.5 to 1 on 72 pairs worst 4.83, a
third statebar cost 40px above the window. They are what makes the record an
argument rather than an assertion. SOME OF THEM ARE ASSERTED BY A CHECK AND MOST
ARE NOT, and on the page the two look exactly alike: a number nothing owns goes
stale the first time the thing it measures changes, silently, and the passing
check beside it makes the unowned sentence read as more trusted rather than less
(L210).

THE TWO MARKINGS, and they are the record's own voice rather than a notation:

    `asserted by <script>`   a number a CHECK owns. It names the check, so the
                             reader can go and see what is actually enforced.
    `measured <YYYY-MM-DD>`  a number nothing owns. It says it was measured once,
                             and which day, so the reader knows how old it is.

Each is one inline code span, which the record already uses for every script name
and every `ovation#N`, so it is unobtrusive where it is read and unambiguous
where it is parsed. A MARKING COVERS ITS OWN PARAGRAPH, the blank line separated
block it sits in. That is a DECLARED shape rather than a guessed one: splitting
prose into sentences is a guess about punctuation, and a guard that guesses is
one whose refusals cannot be trusted (the same reason check-design-record-open.sh
reads list items rather than sentences).

WHAT IT REFUSES, and what it only REPORTS, is the whole design of this check and
it is deliberate.

IT REFUSES A MARKING THAT IS WRONG. A marking naming a script that is not there,
or a script no inventory watches, or a day nobody can read, is worse than no
marking at all: it is a citation the reader follows and comes away believing.

IT DOES NOT REFUSE AN UNMARKED NUMBER. It COUNTS them and says where they are.
A sweep that refused until all of them carried a marking would be unlandable on
the day it shipped, and the way it would actually be answered is by marking
numbers to silence it, which is worse than the gap it was aimed at. So the gap is
made visible and countable instead, and it is expected to shrink one settled
question at a time.

WHAT THAT GIVES UP, said here rather than left to be discovered, because a check
that examined almost nothing must never read as one that passed (L98, L400):

  * A NUMBER CAN STILL BE WRONG. Nothing here re-measures anything. A marking
    says which check to go and read, or which day somebody looked; it never says
    that what they found is still true. `asserted by` is the stronger of the two
    only because the named check runs.
  * A MARKING CAN NAME THE WRONG CHECK. It is proved to name a check that EXISTS
    and is WATCHED, never that the check asserts the number beside it. That
    cannot be read out of prose, and guessing at it would be a refusal nobody
    could trust.
  * THE DATE IS NOT JUDGED FOR AGE, and a day in the future is not refused. A
    marking two years old and one written today read alike here. An age rule
    needs a clock, and a clock in a push gate turns a green tree red with no
    commit in between (L538).
  * ONLY THE README IS READ. The design files carry measured numbers in their own
    prose too, and none of it is counted here. That is a gap rather than a
    finding: this check would report zero over those files whether they were
    fully marked or had never heard of the convention.
  * THE UNMARKED COUNT IS OVER A DEFINED POPULATION, not over "measurements",
    which nothing can recognise. It counts a run of digits in the record's prose,
    leaving out what a reader never re-measures: anything inside a code span, a
    date, an `ovation#N`, a `PRD` number, an `L<n>` lesson reference, a numbered
    list marker, a line reference after a colon and a requirement sub-reference
    like 46b. So it over counts a round number written in an argument and under
    counts a measurement written in words. It is a yardstick for the gap closing,
    never a census.

IT NEVER QUOTES THE RECORD'S PROSE. The inside of a marking comes out of
docs/design/README.md, which is where a client's name would sit, so a marking
wearing the shape of a day or of a script name is said back whole and anything
else is described by its length instead (docs/PRIVACY-FLOOR.md, L222). Everything
else it prints is a line number, a count, a script name and a path.

Outcomes, one per marking, each said differently because distinct causes need
distinct messages (L11):

    OWNED            names a check that is there and is in the inventory
    MEASURED         names a day that reads as a date
    NO SUCH SCRIPT   names a script that is not under scripts/
    NOT REGISTERED   names a script that is there and is in no inventory row
    UNREADABLE DATE  names a day that is not YYYY-MM-DD

Exit codes:

    0  every marking points at something real
    1  at least one marking is wrong
    2  nothing could be read: no record, no inventory, or a record carrying no
       marking at all, which is not a pass
    3  used wrongly

Seams:

    OVATION_DESIGN_ROOT    the design record to read
    OVATION_SCRIPTS_ROOT   the scripts directory the markings point into, which
                           also holds lib/script-roles.tsv
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")
README = os.path.join(ROOT, "README.md")
SCRIPTS = os.environ.get("OVATION_SCRIPTS_ROOT") or os.path.join(REPO, "scripts")
ROLES = os.path.join(SCRIPTS, "lib", "script-roles.tsv")

# The exit codes above, named so a refusal cannot be raised with the wrong one.
CLEAN, WRONG, CANNOT_MEASURE, USED_WRONGLY = 0, 1, 2, 3

# THE MARKINGS, READ AS CODE SPANS. Both are matched inside backticks rather than
# in running prose, so an ordinary sentence naming a check is not read as a
# marking of its own (L135). An EXAMPLE of the convention IS read as one, and that
# is accepted rather than worked around: an example has to name a real check and a
# real day to be worth writing, so it cannot be a marking that is wrong.
OWNED = re.compile(r"`asserted by ([^`]+)`")
DATED = re.compile(r"`measured ([^`]+)`")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

MONTH_LENGTHS = (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)

# WHAT MAY BE SAID BACK, and this is the privacy floor rather than tidiness. The
# inside of a marking is PROSE out of the design record, and the record's prose is
# where a client's name would sit, so a refusal that quoted whatever it found
# would put it in a terminal and from there into a transcript
# (docs/PRIVACY-FLOOR.md, L222). A day and a script name have narrow shapes, so a
# marking wearing either is quoted whole and everything else is described by its
# length instead. check-design-rules-inline.sh names a line and never quotes it
# for the same reason.
SAYABLE_DAY = re.compile(r"^[0-9-]{1,32}$")
SAYABLE_NAME = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


def sayable(said, shape, what):
    """A marking's inside, quoted when its shape makes that safe and counted when not."""
    if shape.match(said):
        return said
    return "%d character(s) that are not %s" % (len(said), what)


def reads_as_a_day(said):
    """Whether a marking's day is a date a reader can act on.

    FEBRUARY IS GIVEN 29 DAYS WHATEVER THE YEAR, on purpose. The question here is
    whether the marking can be READ, not whether that leap year existed, and a
    rule that refused one day every four years would be a refusal nobody could
    reproduce on the day they hit it.
    """
    if not DATE.match(said):
        return False
    year, month, day = (int(part) for part in said.split("-"))
    if not 1 <= month <= 12:
        return False
    return 1 <= day <= MONTH_LENGTHS[month - 1] and year >= 1


def registered(names):
    """The scripts lib/script-roles.tsv lists, by their path relative to scripts/.

    READ FROM THE INVENTORY RATHER THAN FROM THE DIRECTORY, because the question
    a marking raises is not whether a file exists but whether anything WATCHES it:
    a check in the tree and in no inventory row is one the push gate, the
    workflows and the privacy suite are all blind to (ovation#86).
    """
    found = set()
    for line in names:
        if line.startswith("#") or not line.strip():
            continue
        found.add(line.split("\t")[0].strip())
    return found


# WHAT IS NOT A MEASUREMENT. Each of these is a number a reader follows rather
# than re-measures, so counting it would bury the real gap under citations. The
# order matters: the code spans go first, because every other pattern below would
# otherwise match inside one.
NOT_A_MEASUREMENT = (
    re.compile(r"`[^`\n]*`"),
    re.compile(r"\b\d{4}-\d{2}-\d{2}\b"),
    re.compile(r"ovation#\d+"),
    re.compile(r"\bPRD\s+\d+[a-zA-Z0-9.]*"),
    re.compile(r"\bL\d+\b"),
    re.compile(r"(?m)^\s*\d+\.\s"),
    re.compile(r"\b\d+[a-zA-Z]\b"),
    re.compile(r"\b[A-Za-z]\d+\b"),
    re.compile(r"(?<=:)\d+\b"),
)
DIGITS = re.compile(r"\d[\d,]*(?:\.\d+)?")


def blanked(text):
    """The record's prose with everything a reader never re-measures taken out.

    BLANKED RATHER THAN REMOVED, so every offset still names the line it was on.
    A pass that shortened the text would report the right count against the wrong
    lines, which is a report nobody can act on (L80).
    """
    for pattern in NOT_A_MEASUREMENT:
        text = pattern.sub(lambda m: " " * len(m.group(0)), text)
    return text


def paragraphs(text):
    """(first line number, the paragraph's text) for each blank line separated block.

    THE PARAGRAPH IS THE DECLARED SHAPE A MARKING COVERS. It is what Markdown
    itself separates, so the check and the reader agree about where one argument
    ends, with nothing guessed about sentences or punctuation.
    """
    out, start, held = [], None, []
    lines = text.split("\n")
    for n, line in enumerate(lines):
        if line.strip():
            if start is None:
                start = n + 1
            held.append(line)
            continue
        if start is not None:
            out.append((start, "\n".join(held)))
            start, held = None, []
    if start is not None:
        out.append((start, "\n".join(held)))
    return out


def main(argv):
    if len(argv) > 1:
        print(__doc__.strip().split("\n")[2])
        return USED_WRONGLY
    if not os.path.isfile(README):
        print("CANNOT MEASURE: no %s, so nothing was read. That is not a pass."
              % README)
        return CANNOT_MEASURE
    with open(README, encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    blocks = paragraphs(text)
    markings = []
    for first, body in blocks:
        for kind, pattern in (("OWNED", OWNED), ("MEASURED", DATED)):
            for found in pattern.finditer(body):
                line = first + body.count("\n", 0, found.start())
                markings.append((kind, found.group(1).strip(), line, first))
    if not markings:
        print("CANNOT MEASURE: %s carries no marking at all, so this compared "
              "nothing. A record nobody has marked and a record whose markings "
              "are all sound must not report the same." % README)
        return CANNOT_MEASURE

    # THE INVENTORY IS ONLY NEEDED WHEN SOMETHING NAMES A SCRIPT, and it is read
    # before any verdict rather than per marking, so a record whose inventory is
    # missing cannot be half judged.
    watched = None
    if any(kind == "OWNED" for kind, _, _, _ in markings):
        if not os.path.isfile(ROLES):
            print("CANNOT MEASURE: no %s, so nothing could say whether the "
                  "check a marking names is watched by anything. That is not a "
                  "pass." % ROLES)
            return CANNOT_MEASURE
        with open(ROLES, encoding="utf-8", errors="replace") as handle:
            watched = registered(handle.read().split("\n"))

    marked_from = set(first for _, _, _, first in markings)

    wrong = []
    for kind, said, line, _ in sorted(markings, key=lambda m: m[2]):
        if kind == "MEASURED":
            if reads_as_a_day(said):
                print("  MEASURED line %d, measured %s, and nothing asserts it"
                      % (line, said))
            else:
                wrong.append(line)
                print("  UNREADABLE DATE line %d: this marking says it was measured on "
                      "%s, which is not a day written YYYY-MM-DD, so nothing can "
                      "tell how old the number is"
                      % (line, sayable(said, SAYABLE_DAY, "digits and hyphens")))
            continue
        name = sayable(said, SAYABLE_NAME, "a script name")
        # THE SHAPE IS TESTED BEFORE THE DISK IS TOUCHED, so nothing the record's
        # prose happens to hold can be turned into a path and asked about.
        if not SAYABLE_NAME.match(said) or not os.path.isfile(os.path.join(SCRIPTS, said)):
            wrong.append(line)
            print("  NO SUCH SCRIPT line %d: this marking says the number is asserted "
                  "by %s, and there is no such script under %s, so the reader is sent "
                  "to nothing" % (line, name, SCRIPTS))
        elif said not in watched:
            wrong.append(line)
            print("  NOT REGISTERED line %d: this marking names %s, which is in the "
                  "tree and in no row of %s, so nothing runs it and the number is "
                  "owned by a check that never fires" % (line, name, ROLES))
        else:
            print("  OWNED    line %d, asserted by %s" % (line, said))

    # THE REPORT, AND IT IS PRINTED WHATEVER THE VERDICT ABOVE WAS. A refusal
    # that swallowed the count would hide the gap on exactly the runs where
    # somebody already has the record open (L98).
    counted, places = 0, []
    for first, body in blocks:
        if first in marked_from:
            continue
        here = len(DIGITS.findall(blanked(body)))
        if here:
            counted += here
            places.append((first, here))
    for first, here in places:
        print("  unmarked  line %d, %d number(s) with nothing behind them"
              % (first, here))
    print("UNMARKED: %d number(s) in %d paragraph(s) of %s that no marking covers."
          % (counted, len(places), os.path.basename(README)))
    print("          Reported, never refused: a sweep that refused until every one "
          "of them was marked would be answered by marking them to silence it.")

    if wrong:
        print("REFUSED: %d marking(s) of the %d in %s point at something that is not "
              "there. A marking the reader follows and finds nothing at is worse "
              "than no marking at all."
              % (len(wrong), len(markings), os.path.basename(README)))
        return WRONG
    print("OK: read %d marking(s) in %s and every one of them points at something "
          "real." % (len(markings), os.path.basename(README)))
    return CLEAN


if __name__ == "__main__":
    sys.exit(main(sys.argv))
