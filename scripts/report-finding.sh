#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Report a finding on the tracker once, and stop reporting it when it is over.

    report-finding.sh stands   --title T --body-file NEW --comment-file AGAIN
                               [--milestone M] [--label L]... [--verdict-file V]
    report-finding.sh recurred --title T --comment-file AGAIN
    report-finding.sh cleared  --title T --comment-file CLOSING

ovation#339. Two workflows reported a finding the same way, and both carried the
whole mechanism inside a YAML step: the lookup, the comment, the creation with
its labels and milestone, and the close. So it only ever ran on a runner, nothing
could judge it before it shipped, and the two copies could drift with nobody
re-reading either (L370, L263).

IT IS THE HALF THAT DECIDES WHETHER A FINDING IS SEEN AT ALL, which is why it is
worth a script and a suite of its own. Every way it breaks is silent in the
direction that loses the report: a lookup that matches nothing files a SECOND
issue beside the first (L393), a title that stops matching duplicates the finding
for ever, and a close that never fires leaves a finished finding reading as
outstanding, which teaches everyone to skim the next one (L269).

THE SCRIPT OWNS THE MECHANISM, NEVER THE WORDS. The title, the body, the labels
and the milestone stay with the caller that composed them, because they are what
that finding is about and this knows nothing about any of them.

THE BODY COMES FROM A FILE, and that is not a preference. The first version of
the liveness workflow put its verdict into a `--body "..."` inside a YAML block
scalar, and the unindented lines of that string ENDED the block: the workflow
failed to parse, ran NO jobs at all, and reported a failure with no log to read.
A run with zero jobs is what an invalid workflow file looks like. So this takes
paths, never text, and refuses a path it cannot read before it writes anything.

THE MATCH IS EXACT, THE LOOKUP IS NOT. `gh issue list --search "in:title ..."`
is a search: it returns issues whose titles merely RESEMBLE the marker, and
commenting on one of those would leave this finding unreported for ever while
somebody else's issue collected the comments. So the rows are filtered here on
the title being equal, and the filter lives in this script rather than in a `jq`
expression inside a workflow, so that a suite can drive it.

AND MANY MATCHES IS ITS OWN REFUSAL, never the first one (L521). Two open issues
carrying one marker title means an earlier run already duplicated the finding.
Acting on whichever the search returned first would hide exactly the fault this
script exists to prevent, so it refuses and names both, and a person merges them.

IT PRINTS NUMBERS, NOT THE WORDS THE CALLER COMPOSED. This repository is public
on purpose, so a workflow log is a published document (docs/PRIVACY-FLOOR.md),
and the title and the body are text a caller could put anything into. An issue
number names the finding exactly and carries nothing (L15). What `gh` itself
prints is left alone and goes straight to the log, because a refusal whose
diagnosis was captured and thrown away leaves pressing the button again as the
only way to learn anything (L148).

EVERY OUTCOME HAS ITS OWN EXIT CODE, INCLUDING THE FOUR THAT ARE NOT FAULTS, so
a caller must enumerate the codes it accepts rather than testing for zero (L184).
Both workflows do, in one line each, and that line is the only thing either of
them still has to know about this.

SAID ONCE PER VERDICT, NEVER ONCE PER RUN (ovation#512). `stands` commented
every time its caller ran while the finding stood, and on 2026-09-23 that put
five identical comments on ovation#376, whose 53 comments by then carried four
distinct verdicts. A thread of repeats buries the one comment that says
something new and teaches a reader to skip all of them (L36).

So a caller may pass `--verdict-file`: the measurement the finding is about,
separate from the words around it. Everything this writes is then stamped with a
fingerprint of that verdict, a hidden HTML comment carrying its sha256, and
before commenting on an issue already open it reads the thread and comments only
when the NEWEST fingerprint on it differs.

A FINGERPRINT RATHER THAN THE TEXT, because the caller's words around the
verdict carry a date and differ on every run, and cutting the verdict back out
of them would make this depend on how each caller lays its comment out, which is
the words this script does not own.

THE NEWEST STAMPED ONE, not the last comment. A verdict that goes A, B and back
to A is a change on the third run, so an older A must not silence it; and a
person's comment under the finding carries no stamp, so writing "looking into
it" does not make the next run repeat what was last said. A thread written
before the stamp existed carries none at all, and is commented on once more,
stamped, which is the one comment the change costs.

A THREAD THAT COULD NOT BE READ IS CANNOT ASK, never a guess: reading it as
carrying no verdict repeats, which is the fault this fixes, and reading it as
carrying this one loses a change (L214).

Exit codes, one per outcome, each with its own sentence (L11):

    0  OPENED            no open issue carried the marker title, so one was filed
    1  COMMENTED         exactly one did, so it was commented on rather than
                         duplicated
    2  CLOSED            exactly one did, so it was closed with the comment
    3  NOTHING TO CLOSE  none did, so there was nothing to close. Not a fault:
                         it is what a condition that never fired looks like
    4  MANY              more than one open issue carries the marker title, so an
                         earlier run already duplicated the finding
    5  CANNOT ASK        the lookup itself failed or could not be read, so
                         nothing is known and nothing was written
    6  COULD NOT SAY IT  the lookup answered and the write failed, so the finding
                         was measured and nobody was told
    7  USED WRONGLY      a missing argument, an unreadable file, or an option the
                         command has no use for
    8  NOTHING OPEN      `recurred` found no open issue carrying the title, and
                         that command may not file one, so nobody was told
    9  UNCHANGED         `stands --verdict-file` found exactly one open issue and
                         its newest verdict is this one, so nothing was written.
                         Not a fault: it is what a finding that still stands
                         looks like on every run after it was said
   10  BROKE             something failed that none of the outcomes above
                         names. Python exits 1 on an uncaught exception, and
                         1 is COMMENTED, which every `stands` caller accepts,
                         so a script that broke halfway read as a finding
                         said. This code is accepted by no caller

Seam:

    OVATION_GH  the command that talks to the tracker, defaulting to `gh`. It is
                a seam from the day this was written, because a suite that could
                only pass by reaching the real tracker would be asserting about
                the backlog rather than about this script, and would file real
                issues while doing it (L2, L291).
"""
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

OPENED, COMMENTED, CLOSED, NOTHING_TO_CLOSE = 0, 1, 2, 3
MANY, CANNOT_ASK, COULD_NOT_SAY_IT, USED_WRONGLY = 4, 5, 6, 7
NOTHING_OPEN, UNCHANGED, BROKE = 8, 9, 10

# THE STAMP. An HTML comment, so GitHub renders nothing for it, and the name of
# this script in it, so it cannot be mistaken for anything a person wrote.
STAMP = "<!-- report-finding verdict %s -->"
STAMP_FOUND = re.compile(r"<!-- report-finding verdict ([0-9a-f]{64}) -->")

# HOW MANY THE LOOKUP MAY RETURN. `gh issue list` pages at 30 by default, and a
# ceiling that silently truncates would turn "many" into "one" on a tracker that
# had drifted far enough for it to matter most.
LOOKUP_LIMIT = "100"

USAGE = [
    "    report-finding.sh stands   --title T --body-file NEW --comment-file AGAIN",
    "                               [--milestone M] [--label L]... [--verdict-file V]",
    "    report-finding.sh recurred --title T --comment-file AGAIN",
    "    report-finding.sh cleared  --title T --comment-file CLOSING",
]


def used_wrongly(said):
    print("USED WRONGLY: %s." % said)
    for line in USAGE:
        print(line)
    return USED_WRONGLY


def gh_command():
    """The tracker command, split as a shell would split it.

    Split rather than taken whole so a suite can point the seam at an
    interpreter and a file, and a plain `gh` still works untouched.
    """
    return shlex.split(os.environ.get("OVATION_GH") or "gh")


def ask(arguments):
    """Run the tracker command and capture its stdout, or None if it could not run.

    STDERR IS LEFT ALONE and goes to this run's own log, so `gh`'s diagnosis of
    its own failure is readable by whoever opens the run (L148). Only stdout is
    captured, because that is the answer this script has to parse.
    """
    try:
        return subprocess.run(gh_command() + arguments, stdout=subprocess.PIPE,
                              text=True, timeout=120)
    except (subprocess.SubprocessError, OSError):
        return None


def tell(arguments):
    """Run a tracker command that WRITES. True when it succeeded.

    Nothing is captured at all: what `gh` prints about an issue it created or
    commented on is the caller's receipt and belongs in the log.
    """
    try:
        return subprocess.run(gh_command() + arguments, timeout=120).returncode == 0
    except (subprocess.SubprocessError, OSError):
        return False


def open_issues_titled(title):
    """The numbers of the open issues whose title EQUALS this, or None.

    None means the question could not be answered, which is never the same as
    the answer being none: reading a failed lookup as "no such issue" files a
    duplicate beside the one already open (L214, L393). A row that matches by
    title and carries no usable number lands there too, because dropping it would
    turn two matches into one and take the MANY refusal away.
    """
    done = ask(["issue", "list", "--state", "open",
                "--search", 'in:title "%s"' % title,
                "--json", "number,title", "--limit", LOOKUP_LIMIT])
    if done is None or done.returncode != 0:
        return None
    try:
        rows = json.loads(done.stdout or "")
    except ValueError:
        return None
    if not isinstance(rows, list):
        return None
    numbers = []
    for row in rows:
        if not isinstance(row, dict) or row.get("title") != title:
            continue
        number = row.get("number")
        if not isinstance(number, int) or isinstance(number, bool):
            return None
        numbers.append(number)
    return numbers


def newest_verdict(number):
    """The fingerprint of the newest verdict on this issue's thread, "" when the
    thread carries none, or None when the thread could not be read.

    Comments newest first, then the body, and the LAST stamp inside whichever
    text carries one, so the answer is what this script said most recently.
    """
    done = ask(["issue", "view", str(number), "--json", "body,comments"])
    if done is None or done.returncode != 0:
        return None
    try:
        issue = json.loads(done.stdout or "")
    except ValueError:
        return None
    if not isinstance(issue, dict) or not isinstance(issue.get("comments"), list):
        return None
    texts = [issue.get("body")]
    for comment in issue["comments"]:
        if not isinstance(comment, dict):
            return None
        texts.append(comment.get("body"))
    for text in reversed(texts):
        if not isinstance(text, str):
            return None
        stamps = STAMP_FOUND.findall(text)
        if stamps:
            return stamps[-1]
    return ""


def stamped(path, fingerprint, made):
    """A copy of the caller's file with the stamp on its last line, or the
    caller's own path when there is no verdict to stamp. Every copy is added to
    `made` so the caller removes it."""
    if not fingerprint:
        return path
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    handle, copy = tempfile.mkstemp(suffix=".md")
    made.append(copy)
    with os.fdopen(handle, "w", encoding="utf-8") as out:
        out.write(text.rstrip("\n") + "\n\n" + STAMP % fingerprint + "\n")
    return copy


def read_arguments(argv):
    """(command, options) or (None, the sentence saying what was wrong).

    AN ABSENT ARGUMENT IS NEVER GIVEN A DEFAULT. A finding reported under a title
    nobody chose is one no later run will ever match again, so every required
    value is refused rather than invented (L168), and an option the command has
    no use for is refused rather than ignored (L320).
    """
    if len(argv) < 2:
        return None, "no command was given"
    command = argv[1]
    if command not in ("stands", "recurred", "cleared"):
        return None, "there is no `%s` command" % command
    options = {"title": None, "body-file": None, "comment-file": None,
               "milestone": None, "labels": [], "verdict-file": None}
    takes = {"stands": ["--title", "--body-file", "--comment-file", "--milestone", "--label",
                        "--verdict-file"],
             "recurred": ["--title", "--comment-file"],
             "cleared": ["--title", "--comment-file"]}[command]
    rest = argv[2:]
    while rest:
        name = rest[0]
        if name not in takes:
            if name in ("--title", "--body-file", "--comment-file", "--milestone", "--label",
                        "--verdict-file"):
                return None, "`%s` takes no %s" % (command, name)
            return None, "there is no %s option" % name
        if len(rest) < 2:
            return None, "%s was given no value" % name
        value = rest[1]
        rest = rest[2:]
        if name == "--label":
            options["labels"].append(value)
        else:
            options[name[2:]] = value
    for name in ("title", "comment-file"):
        if not options[name]:
            return None, "no --%s was given" % name
    if command == "stands" and not options["body-file"]:
        return None, "no --body-file was given, and a finding filed with no body says nothing"
    for name in ("body-file", "comment-file", "verdict-file"):
        path = options[name]
        if path and not os.path.isfile(path):
            return None, "the --%s is not a file" % name
    # AN EMPTY VERDICT IS REFUSED rather than fingerprinted: it would compare
    # equal to every other empty one, and a caller whose measurement printed
    # nothing has not measured the thing this finding is about.
    if options["verdict-file"] and os.path.getsize(options["verdict-file"]) == 0:
        return None, "the --verdict-file is empty"
    return command, options


def fingerprint_of(path):
    if not path:
        return ""
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def main(argv):
    command, options = read_arguments(argv)
    if command is None:
        return used_wrongly(options)

    numbers = open_issues_titled(options["title"])
    if numbers is None:
        print("CANNOT ASK: the tracker could not be asked whether this finding is "
              "already open, so nothing was written. A lookup that failed and a "
              "tracker holding no such issue must not read the same: acting on the "
              "second would file a duplicate beside the first.")
        return CANNOT_ASK
    if len(numbers) > 1:
        print("MANY: %d open issues carry this marker title, ovation#%s. An earlier "
              "run has already duplicated this finding, and acting on whichever the "
              "search returned first would hide that. Nothing was written. Close all "
              "but one by hand, and this reports on that one from the next run."
              % (len(numbers), ", ovation#".join(str(n) for n in numbers)))
        return MANY

    # A CALLER THAT MAY NOT OPEN AN ISSUE AT ALL (ovation#332). `stands` files one
    # when none is open, which is right for a condition a workflow measures and
    # nobody has asked about. A RECURRENCE COUNT is the other shape: the issue
    # that carries it is opened deliberately, by a person, and each occurrence is
    # one more comment on it. An automated write that opens an issue on a public
    # tracker is Dan's decision rather than this script's, and he made it on
    # 2026-09-15.
    #
    # NOTHING OPEN IS ITS OWN OUTCOME, never a quiet success: a recurrence
    # measured and reported to nobody is the silent loss this exists to prevent
    # (L98, L11).
    if command == "recurred":
        if not numbers:
            print("NOTHING OPEN: no open issue carries this finding, and this "
                  "command may not file one, so nobody was told about this "
                  "occurrence. Open the issue that is to carry it, or call "
                  "`stands` instead.")
            return NOTHING_OPEN
        if not tell(["issue", "comment", str(numbers[0]),
                     "--body-file", options["comment-file"]]):
            print("COULD NOT SAY IT: ovation#%d carries this finding and the "
                  "comment recording this occurrence could not be added. It was "
                  "measured and nobody was told." % numbers[0])
            return COULD_NOT_SAY_IT
        print("COMMENTED: ovation#%d carries this finding, so this occurrence was "
              "added to it." % numbers[0])
        return COMMENTED

    if command == "stands":
        made = []
        try:
            return stands(options, numbers, made)
        finally:
            for path in made:
                os.unlink(path)

    return cleared(options, numbers)


def stands(options, numbers, made):
    fingerprint = fingerprint_of(options["verdict-file"])
    if numbers:
        if fingerprint:
            newest = newest_verdict(numbers[0])
            if newest is None:
                print("CANNOT ASK: ovation#%d carries this finding and its thread "
                      "could not be read, so whether this verdict was already said "
                      "is not known and nothing was written." % numbers[0])
                return CANNOT_ASK
            if newest == fingerprint:
                print("UNCHANGED: ovation#%d already says this verdict, so nothing "
                      "was written." % numbers[0])
                return UNCHANGED
        if not tell(["issue", "comment", str(numbers[0]),
                     "--body-file", stamped(options["comment-file"], fingerprint, made)]):
            print("COULD NOT SAY IT: ovation#%d carries this finding and the "
                  "comment saying it is still true could not be added. The "
                  "finding was measured and nobody was told." % numbers[0])
            return COULD_NOT_SAY_IT
        print("COMMENTED: ovation#%d already carries this finding, so it was "
              "commented on rather than duplicated." % numbers[0])
        return COMMENTED
    create = ["issue", "create", "--title", options["title"],
              "--body-file", stamped(options["body-file"], fingerprint, made)]
    if options["milestone"]:
        create += ["--milestone", options["milestone"]]
    for label in options["labels"]:
        create += ["--label", label]
    if not tell(create):
        print("COULD NOT SAY IT: no open issue carries this finding and one "
              "could not be filed. The finding was measured and nobody was told.")
        return COULD_NOT_SAY_IT
    print("OPENED: no open issue carried this finding, so one was filed. It is "
          "commented on rather than duplicated from here on.")
    return OPENED


def cleared(options, numbers):
    if not numbers:
        print("NOTHING TO CLOSE: no open issue carries this finding, so there was "
              "nothing to close. That is what a condition which never fired looks "
              "like, and it is not a fault.")
        return NOTHING_TO_CLOSE
    with open(options["comment-file"], encoding="utf-8") as handle:
        comment = handle.read()
    if not tell(["issue", "close", str(numbers[0]), "--comment", comment]):
        print("COULD NOT SAY IT: this finding is over and ovation#%d could not be "
              "closed. A finding left open after it stops being true reads as "
              "outstanding." % numbers[0])
        return COULD_NOT_SAY_IT
    print("CLOSED: this finding is over, so ovation#%d was closed with the comment "
          "saying why." % numbers[0])
    return CLOSED


def guarded(argv):
    """main, with every failure it did not name turned into BROKE.

    The traceback still goes to the log, because it is the diagnosis (L148); only
    the exit code changes, so no caller can read a crash as one of its successes.
    """
    try:
        return main(argv)
    except Exception:  # noqa: BLE001, deliberately every unnamed failure
        import traceback
        traceback.print_exc()
        print("BROKE: this failed in a way none of its outcomes names, so nothing it "
              "may have done is known. It exits 10, which no caller accepts, rather "
              "than 1, which reads as a comment made.")
        return BROKE


if __name__ == "__main__":
    sys.exit(guarded(sys.argv))
