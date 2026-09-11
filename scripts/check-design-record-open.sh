#!/usr/bin/env python3
"""Refuse a design record that calls a CLOSED issue still open.

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

WHAT IT STILL CANNOT CATCH, and this is the larger half. The lists are prose, so
what is checkable is what they CITE. An entry that quietly stops being true while
naming nothing, or while naming a requirement that has since been corrected to
say the opposite, passes. The entry that caused ovation#200 was one of those: it
named no issue at all. Requiring a citation per entry was considered and not
done here, because splitting prose into entries is a guess about markup, and a
guard that guesses is one whose refusals cannot be trusted.

IT IS NOT A PUSH GATE, and that is deliberate. It asks GitHub, so on a machine
with no network, no `gh`, or no credentials it can prove nothing, and a gate
that refuses every push from such a machine is one people learn to skip (L376,
L571). It runs in CI, where the token is, and by hand.

THE STATE READER IS A SEAM FROM THE DAY THIS WAS WRITTEN, because a test that
reached the real tracker would be asserting about the backlog rather than about
this check, and would fail the day an issue is closed (L2, L291).

Outcomes, one per issue, each said differently because distinct causes need
distinct messages (L11):

    OPEN      the tracker says it is open, so the sentence is true
    CLOSED    the tracker says it is closed, and the section still names it
    UNKNOWN   nothing could be learned about it, which is not a pass

Exit codes:

    0  every issue the section names is open
    1  at least one is closed
    2  the section, or an issue's state, could not be read: not a pass
    3  used wrongly

Seams:

    OVATION_DESIGN_ROOT          the design record to read
    OVATION_ISSUE_STATE_COMMAND  a command taking an issue number and printing
                                 OPEN or CLOSED, defaulting to the gh CLI
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
DEFAULT_COMMAND = "gh issue view {n} --json state --jq .state"
ISSUE = re.compile(r"ovation#(\d+)")


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
    if not seen:
        print("CANNOT MEASURE: the `%s` section names no issue, so this "
              "compared nothing." % SECTION)
        return 2

    # ovation#200. The same question, asked of each design file's own list.
    with_list, without_list = [], []
    for name in sorted(html_files(os.listdir(ROOT))):
        with open(os.path.join(ROOT, name), encoding="utf-8", errors="replace") as handle:
            lines = file_section_lines(handle.read())
        if lines is None:
            without_list.append(name)
            continue
        with_list.append(name)
        for line_no, line in lines:
            for number in ISSUE.findall(line):
                seen.setdefault(int(number), []).append((name, line_no))
    for name in with_list:
        print("  %s carries its own `%s` list" % (name, FILE_SECTION))
    for name in without_list:
        print("  %s carries no `%s` list, and keeps its record elsewhere"
              % (name, FILE_SECTION))

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

    if closed:
        print("REFUSED: %d of %d issue(s) the design record calls still open "
              "are closed. Correct the sentence, or reopen the issue."
              % (len(closed), len(seen)))
        return 1
    if unknown:
        print("CANNOT MEASURE: %d of %d issue(s) could not be looked up, so "
              "this proved nothing about them. That is not a pass: a lookup "
              "that failed and an issue that is open must not read the same."
              % (len(unknown), len(seen)))
        return 2
    print("OK: every one of the %d issue(s) the design record and its files call "
          "still open is open." % open_count)
    print("    %d design file(s) carry their own list, %d keep their record elsewhere."
          % (len(with_list), len(without_list)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
