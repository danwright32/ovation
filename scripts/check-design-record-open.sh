#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a design record that calls a CLOSED issue still open.

    check-design-record-open.sh

ovation#172. `docs/design/README.md` has one section that carries STATUS rather
than decisions, "What is still open", and it is the first thing anyone reads
when picking up design work. It went on naming the review and send screen
(ovation#101) and the invoice screen (ovation#111) as "not designed yet" after
both were settled, closed, and recorded further down the same file: the invoice
screen's record starts at line 374 of the very file that said it did not exist.

A file believed without being re-checked is the shape L244 exists for, and the
project's own memory note is written to hold no status for exactly this reason.
The same drift put a false claim into an issue body: ovation#98 opened with
"Clients has never been designed" while `clients.html` sat in the same folder
with five settled rounds in the README.

SO THE SENTENCE IS DERIVED FROM THE TRACKER, not maintained beside it (L41).
Every `ovation#N` in that section is asked whether it is still open, and one
that is closed is a refusal naming the line it is on.

AND EACH DESIGN FILE'S OWN LIST, the same way (ovation#200). Three files carry a
list about themselves and nothing checked any of them; one was false on the day
that issue was filed, saying money held against a client had no surface on the
invoice list, which two requirements had made untrue the same day. They carried
three different headings, so nothing could even find them all, and they now
carry one: `What is deliberately still open` (L118). A file that carries none is
NAMED rather than passed over, because invoice.html and invoice-pdf.html keep
their records in the README and having none is correct there, while a file that
LOST its list looks exactly the same (L98).

EVERY ENTRY NAMES WHAT IT HANGS ON (ovation#204). The entry that caused
ovation#200 named no issue at all, so nothing could ever re-check it. Requiring a
citation was first held back because splitting prose into entries is a guess about
markup, and a guard that guesses cannot be trusted; so the entries now have a
DECLARED shape instead of a guessed one. A design file's open list is one list item
per entry, every item names an `ovation#N` or a `PRD` number, prose outside any
item is refused as not an entry, and a heading with no items under it is refused
as empty rather than read as nothing being open.

AND THE OTHER DIRECTION (ovation#195). Everything above asks whether an issue the
section NAMES is still open. Nothing asked whether an issue that is open and
waiting on Dan is NAMED, and on the day that was measured the section listed
three while seven design decisions of the same kind were open elsewhere; the
check was green throughout, correctly, because it answered the only question it
asked. A list verified in one direction reads as verified (L178).

The handle is Dan's decision of 2026-09-29: a dedicated `design-decision` label,
applied deliberately to an issue that is a design decision waiting on him. Not
`ui-ux`, because not every such issue is a decision, and not a milestone, which
sweeps in implementation. Every open issue carrying the label must be named in
the README's `What is still open` section, and one that is not is MISSING. Named
only inside a design file's own list does not count: the README's section is the
one read as THE list.

WHAT THAT CANNOT SEE, said rather than assumed: a decision nobody labelled is as
invisible as before. The label is the whole mechanism, so applying it is part of
opening such an issue.

AN EMPTY LIST IS A LEGITIMATE STATE. It was first written as CANNOT MEASURE, on
the reasoning that a renamed label and a tracker with nothing waiting look the
same (L543). On 2026-09-29 Dan settled every open design question and the label
came off all seven issues, so nothing waiting is a real day and must pass. It is
SAID rather than passed silently, and a label list that could not be READ is
still CANNOT MEASURE, because a failure and an empty answer are different things.

AND THE HEALTHY DAY IS STATED, NOT INFERRED. A section naming no issue is still
CANNOT MEASURE, because an emptied section reads exactly like a finished one,
unless it carries the one declared sentence `Nothing is waiting on Dan.` (L610).
With it, the section is a claim this can check: it passes while no open issue
carries the label, and any labelled issue is MISSING from it.

WHAT IT STILL CANNOT CATCH. An entry that stops being true while citing a
requirement that has since been corrected to say the opposite still passes: a
citation says what to re-read, not that anybody did.

IT IS NOT A PUSH GATE, and that is deliberate. It asks GitHub, so on a machine
with no network, no `gh`, or no credentials it can prove nothing, and a gate
that refuses every push from such a machine is one people learn to skip (L376,
L571). It runs in CI, where the token is, and by hand.

THE STATE READER IS A SEAM FROM THE DAY THIS WAS WRITTEN, because a test that
reached the real tracker would be asserting about the backlog rather than about
this check, and would fail the day an issue is closed (L2, L291).

Outcomes, one per issue, each said differently because distinct causes need
distinct messages (L11):

    OPEN          the tracker says it is open, so the sentence is true
    CLOSED        the tracker says it is closed, and the section still names it
    UNKNOWN       nothing could be learned about it, which is not a pass
    MISSING       it carries the design-decision label, is open, and the
                  section does not name it (ovation#195)

And, for each design file's own list, read from the file alone:

    UNCITED       a list item names no ovation#N and no PRD number
    NOT AN ENTRY  prose in the list that is not inside a list item
    EMPTY         the heading is there and no item is under it

Exit codes:

    0  every issue the section names is open
    1  at least one is closed, a labelled decision is missing from the
       section, or a design file's list has an uncited item, prose outside
       an item, or no items
    2  the section, an issue's state, or the labelled list could not be
       read, or nothing carries the label: not a pass
    3  used wrongly

Seams:

    OVATION_DESIGN_ROOT          the design record to read
    OVATION_ISSUE_STATE_COMMAND  a command taking an issue number and printing
                                 OPEN or CLOSED, defaulting to the gh CLI
    OVATION_DECISION_LIST_COMMAND  a command printing the number of every open
                                 issue carrying the design-decision label, one
                                 per line, defaulting to the gh CLI
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_inline import html_files  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")
README = os.path.join(ROOT, "README.md")
SECTION = "## What is still open"
# The one sentence a section naming no issue declares the healthy day with.
NOTHING_WAITING = "Nothing is waiting on Dan."
DEFAULT_COMMAND = "gh issue view {n} --json state --jq .state"
ISSUE = re.compile(r"ovation#(\d+)")
# ovation#195. The label Dan chose, and the lookup that lists what carries it.
# The limit is far above any real count, and a list that reaches it is refused
# below rather than read as complete (L211).
DECISION_LABEL = "design-decision"
DECISION_LIMIT = 500
DEFAULT_DECISION_COMMAND = ("gh issue list --label %s --state open --limit %d "
                            "--json number --jq '.[].number'" % (DECISION_LABEL, DECISION_LIMIT))


def section_lines(text):
    """(line number, line) for the status section, or None when it is absent.

    THE SECTION IS FOUND BY ITS HEADING AND ENDS AT THE NEXT ONE OF THE SAME
    LEVEL, so a subsection inside it is included and the next chapter is not.
    A missing heading is its own outcome rather than an empty section, because
    a renamed heading would otherwise read as a record with nothing open in it
    (L98).
    """
    lines = text.split("\n")
    start = None
    for n, line in enumerate(lines):
        if line.strip() == SECTION:
            start = n
            break
    if start is None:
        return None
    out = []
    for n in range(start + 1, len(lines)):
        if lines[n].startswith("## "):
            break
        out.append((n + 1, lines[n]))
    return out


# ovation#200. Each design file carries its own list of what it does not answer,
# and nothing checked those. They carried three different headings until this
# shipped, so nothing could even find them all; they now carry one (L118).
#
# ONE HEADING, FOUND BY ITS OWN LEVEL. The section ends at the next heading of
# the same level or higher, so a subsection inside it is included and the next
# chapter is not, which is what `section_lines` does for the record above.
FILE_SECTION = "What is deliberately still open"
FILE_HEADING = re.compile(r"<h([1-6])[^>]*>\s*" + re.escape(FILE_SECTION) + r"\s*</h\1>",
                          re.I)
ANY_HEADING = re.compile(r"<h([1-6])[^>]*>", re.I)

# THE LIST ALSO ENDS AT THE SCRIPT, and this is not belt and braces. These files
# put the open list LAST in their prose, with no further heading after it, so a
# section that ended only at the next heading ran to the end of the file and
# swallowed every `ovation#` in two thousand lines of JavaScript comments. Its
# first run accused nine citations, and every one of them was a script comment
# correctly recording a settled decision. The list is prose; a script is not.
SCRIPT = re.compile(r"<script\b", re.I)


def file_section_lines(text):
    """(line number, line) for a design file's own open list, or None when it has none.

    A FILE THAT CARRIES NONE IS NOT A FAULT. invoice.html keeps its record in the
    README rather than in itself, so having none is correct there. It is reported
    by name instead, because a file that LOST its list looks exactly the same
    (L98).
    """
    lines = text.split("\n")
    start = level = None
    for n, line in enumerate(lines):
        found = FILE_HEADING.search(line)
        if found:
            start, level = n, int(found.group(1))
            break
    if start is None:
        return None
    out = []
    for n in range(start + 1, len(lines)):
        nxt = ANY_HEADING.search(lines[n])
        if nxt and int(nxt.group(1)) <= level:
            break
        if SCRIPT.search(lines[n]):
            break
        out.append((n + 1, lines[n]))
    return out


# ovation#204. The entries of a design file's open list, by their declared shape.
ITEM = re.compile(r"<li\b[^>]*>(.*?)</li\s*>", re.I | re.S)
ANY_TAG = re.compile(r"<[^>]+>")
REQUIREMENT = re.compile(r"\bPRD\s+\d")


def entry_faults(lines):
    """Faults in a design file's open list, as (kind, line number) pairs.

    THE SHAPE IS DECLARED, NOT GUESSED: one list item per entry. An item citing
    neither an issue nor a requirement is UNCITED, at the line the item starts on.
    Text outside every item is NOT AN ENTRY, at the line it starts on, because an
    entry written as a paragraph is one this check cannot see and the rule would
    then pass it by not reading it (L98). A list with no items is EMPTY, which is
    a heading left behind rather than a record with nothing open.
    """
    if not lines:
        return [("EMPTY", None)]
    first = lines[0][0]
    text = "\n".join(line for _, line in lines)

    def line_at(offset):
        return first + text.count("\n", 0, offset)

    faults = []
    items = list(ITEM.finditer(text))
    for item in items:
        body = item.group(1)
        if not (ISSUE.search(body) or REQUIREMENT.search(body)):
            faults.append(("UNCITED", line_at(item.start())))
    # PROSE, NOT MARKUP. The section runs to the next heading or the script, so it
    # carries the tags that CLOSE the section around it, and those are not entries
    # anybody wrote. Every tag is blanked and what is left is the text a reader
    # sees: an entry written as a paragraph survives this, and `</section>` does
    # not. Blanked rather than removed so the offsets still name the right line.
    outside = ITEM.sub(lambda m: " " * len(m.group(0)), text)
    outside = ANY_TAG.sub(lambda m: " " * len(m.group(0)), outside)
    for loose in re.finditer(r"\S", outside):
        faults.append(("NOT AN ENTRY", line_at(loose.start())))
        break
    if not items and not faults:
        faults.append(("EMPTY", None))
    return faults


def state_of(number, command):
    """OPEN, CLOSED, or None when nothing could be learned.

    A FAILED LOOKUP IS NEVER READ AS OPEN. No network, no credentials and a
    deleted issue all land here, and each of them would otherwise be reported
    as the sentence being true.
    """
    try:
        done = subprocess.run(command.format(n=number), shell=True,
                              capture_output=True, text=True, timeout=30)
    except (subprocess.SubprocessError, OSError):
        return None
    if done.returncode != 0:
        return None
    said = done.stdout.strip().upper()
    if said in ("OPEN", "CLOSED"):
        return said
    return None


def labelled_decisions(command):
    """The open issues carrying the label, as a sorted list, or None.

    NONE MEANS NOTHING WAS LEARNED, never an empty list: a command that failed,
    answered something that is not issue numbers, or reached the limit. An HTTP
    error printed where numbers were expected is the shape this refuses (L215).
    """
    try:
        done = subprocess.run(command, shell=True, capture_output=True, text=True,
                              timeout=60)
    except (subprocess.SubprocessError, OSError):
        return None
    if done.returncode != 0:
        return None
    lines = [l.strip() for l in done.stdout.splitlines() if l.strip()]
    if any(not l.isdigit() for l in lines):
        return None
    if len(lines) >= DECISION_LIMIT:
        return None
    return sorted({int(l) for l in lines})


def main(argv):
    if len(argv) > 1:
        print(__doc__.strip().split("\n")[2])
        return 3
    if not os.path.isfile(README):
        print("CANNOT MEASURE: no %s, so nothing was read. That is not a pass."
              % README)
        return 2
    found = section_lines(open(README, encoding="utf-8").read())
    if found is None:
        print("CANNOT MEASURE: %s has no `%s` heading. A renamed heading and a "
              "record with nothing open in it are different things and must not "
              "report the same." % (README, SECTION))
        return 2

    seen = {}
    for line_no, line in found:
        for number in ISSUE.findall(line):
            seen.setdefault(int(number), []).append(("the design record", line_no))
    says_nothing_waiting = any(NOTHING_WAITING.lower() in line.lower()
                               for _, line in found)
    if not seen and not says_nothing_waiting:
        print("CANNOT MEASURE: the `%s` section names no issue and does not say `%s`, "
              "so this compared nothing. A section emptied by mistake and a record "
              "with nothing waiting must not report the same." % (SECTION, NOTHING_WAITING))
        return 2

    # ovation#200. The same question, asked of each design file's own list.
    with_list, without_list, shaped = [], [], []
    for name in sorted(html_files(os.listdir(ROOT))):
        with open(os.path.join(ROOT, name), encoding="utf-8", errors="replace") as handle:
            lines = file_section_lines(handle.read())
        if lines is None:
            without_list.append(name)
            continue
        with_list.append(name)
        for kind, line_no in entry_faults(lines):
            shaped.append((kind, name, line_no))
        for line_no, line in lines:
            for number in ISSUE.findall(line):
                seen.setdefault(int(number), []).append((name, line_no))
    for name in with_list:
        print("  %s carries its own `%s` list" % (name, FILE_SECTION))
    for name in without_list:
        print("  %s carries no `%s` list, and keeps its record elsewhere"
              % (name, FILE_SECTION))

    # READ FROM THE FILES ALONE, so these need no tracker and are said first.
    for kind, name, line_no in shaped:
        if kind == "UNCITED":
            print("  UNCITED      line %d of %s: this entry names no ovation#N and no PRD "
                  "number, so nothing can ever re-check it" % (line_no, name))
        elif kind == "NOT AN ENTRY":
            print("  NOT AN ENTRY line %d of %s: prose in the open list that is not inside "
                  "a list item, so it is not read as an entry at all" % (line_no, name))
        else:
            print("  EMPTY        %s: the open list heading has no item under it; remove "
                  "the heading or write the entry" % name)

    command = os.environ.get("OVATION_ISSUE_STATE_COMMAND") or DEFAULT_COMMAND
    closed, unknown, open_count = [], [], 0
    for number in sorted(seen):
        places = ", ".join("line %d of %s" % (line_no, where)
                           for where, line_no in seen[number])
        said = state_of(number, command)
        if said == "OPEN":
            open_count += 1
            print("  OPEN    ovation#%d, named on %s" % (number, places))
        elif said == "CLOSED":
            closed.append(number)
            print("  CLOSED  ovation#%d, named on %s, in a list that says what is "
                  "still open" % (number, places))
        else:
            unknown.append(number)
            print("  UNKNOWN ovation#%d, named on %s: nothing could be learned "
                  "about it" % (number, places))

    # ovation#195. The other direction: every open decision waiting on Dan is
    # named in the README's section. Only the README's own lines count.
    in_record = {number for number, places in seen.items()
                 if any(where == "the design record" for where, _ in places)}
    decisions = labelled_decisions(os.environ.get("OVATION_DECISION_LIST_COMMAND")
                                   or DEFAULT_DECISION_COMMAND)
    missing = []
    if decisions is None:
        print("  CANNOT MEASURE: the open issues carrying the %s label could not be "
              "listed, so whether the section names every one was not compared"
              % DECISION_LABEL)
    elif not decisions:
        print("  No open issue carries the %s label, so no design decision is waiting "
              "on Dan." % DECISION_LABEL)
    else:
        for number in decisions:
            if number in in_record:
                print("  NAMED   ovation#%d carries the %s label and the section names it"
                      % (number, DECISION_LABEL))
            else:
                missing.append(number)
                print("  MISSING ovation#%d carries the %s label and the `%s` section "
                      "does not name it. Name it there, or take the label off if it "
                      "is not a decision waiting on Dan" % (number, DECISION_LABEL, SECTION))

    if closed or shaped or missing:
        if missing:
            print("REFUSED: %d open issue(s) carrying the %s label are missing from the "
                  "design record's `%s` section, which is read as the list of what is "
                  "outstanding." % (len(missing), DECISION_LABEL, SECTION))
        if closed:
            print("REFUSED: %d of %d issue(s) the design record calls still open "
                  "are closed. Correct the sentence, or reopen the issue."
                  % (len(closed), len(seen)))
        if shaped:
            # A FAULT IN THE FILE OUTRANKS A LOOKUP THAT FAILED, because it was
            # measured without the tracker and is true whatever the tracker says.
            print("REFUSED: %d entr%s in the design files' open lists cannot be "
                  "re-checked. Each is one list item naming an ovation#N or a PRD number."
                  % (len(shaped), "y" if len(shaped) == 1 else "ies"))
        return 1
    if decisions is None:
        print("CANNOT MEASURE: the other direction was not compared: whether every "
              "open issue carrying the %s label is named in the section is unknown. "
              "That is not a pass." % DECISION_LABEL)
        return 2
    if unknown:
        print("CANNOT MEASURE: %d of %d issue(s) could not be looked up, so "
              "this proved nothing about them. That is not a pass: a lookup "
              "that failed and an issue that is open must not read the same."
              % (len(unknown), len(seen)))
        return 2
    if not seen:
        print("OK: the design record says nothing is waiting on Dan, and no open issue "
              "carries the %s label." % DECISION_LABEL)
        print("    %d design file(s) carry their own list, %d keep their record elsewhere."
              % (len(with_list), len(without_list)))
        return 0
    print("OK: every one of the %d issue(s) the design record and its files call "
          "still open is open." % open_count)
    print("    %d design file(s) carry their own list, %d keep their record elsewhere."
          % (len(with_list), len(without_list)))
    if decisions:
        print("    And all %d open issue(s) carrying the %s label are named in the section."
              % (len(decisions), DECISION_LABEL))
    else:
        print("    And no open issue carries the %s label." % DECISION_LABEL)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
