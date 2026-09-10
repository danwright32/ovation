#!/usr/bin/env python3
"""Report which of the plan's claims about the sibling repositories have drifted.

    check-plan-claims.sh

ovation#16. `docs/IMPLEMENTATION-PLAN.md` is built almost entirely on measured
facts about two other repositories that change daily, and the last milestone it
describes is months away. Nothing re-checked any of it. A recorded fact about
something living OUTSIDE this repository has no action inside it to hang a
re-read on, so it goes stale invisibly and its silence reads as an assurance
(L175, L244, L210).

Measured in one session on 2026-09-05, eight of its claims had already drifted,
and the two expensive ones were the entire premise of three plan steps: the
installed Overture was said to LACK the version gate fix and to be an older
commit, and the installed Downbeat was said to emit a version 2 export. Acting
on either would have meant reinstalling two working apps for no reason.

IT REPORTS, IT DOES NOT EDIT. A claim that has drifted needs a person to decide
what the correction is: the plan may be wrong, or the sibling may have
regressed, and only a reader can tell which.

NOTHING IS DERIVED TWICE. The citations and the literals that anchor them are
read out of the plan itself rather than kept in a table beside it, because a
list maintained next to the thing it describes is the drift this exists to find
(L41, L96). Adding a citation to the plan therefore adds it to this check, and
there is no second file anybody can forget.

HOW A CLAIM IS ANCHORED. Each citation sits in a row that also QUOTES what the
plan says is there. Those quoted literals are the anchor: the line number alone
is worthless, since a sibling's file moves under it constantly, so what is
checked is whether the quoted thing is still in the file and WHERE it is now.

AN AMBIGUOUS PATH IS REFUSED rather than guessed. `run-tests.sh` exists in
Ovation and in Downbeat, `build-install.sh` in all three, and a checker that
picked one would report confidently about a file the plan was not talking about
(L237, L320). The plan is expected to write a path that names its repository.

Outcomes, one per citation, each said differently because they need different
work (L11):

    HELD        the quoted literal is still inside the lines the plan cites
    MOVED       still there, at a different line, which the report names
    UNANCHORED  nothing in the row could be found in the file, so this citation
                was not checked either way
    ABSENT      the file the plan cites does not exist
    SHORT       the file exists and is shorter than the line cited
    AMBIGUOUS   the path resolves in more than one repository

WHY MOVED IS REPORTED AND NOT REFUSED, which is the one judgement here worth
arguing about. These are OTHER repositories and they change daily: a line number
in them is out of date within the week, permanently, and a check that went red
for it would be a standing red, which makes every other failure in the same list
unreadable (L538). What the plan actually claims is the CONTENT, so the content
being there is the pass and the line having moved is information. `--strict`
refuses on it, for whoever is bringing the plan back into step.

WHY UNANCHORED IS REPORTED AND NOT REFUSED EITHER, and this was measured rather
than reasoned: the plan quotes what is NOT there as often as what is. Row 41
quotes `dirtyFiles` and `signingIdentity` precisely to say Overture's installer
writes neither. So "none of the plan's literals is in the file" is the CORRECT
answer for such a row, and calling it a failure would refuse the plan for being
accurate. It is counted instead, so a row nothing can check is visible rather
than passing as health (L98).

Exit codes:

    0  every citation was checked and none is absent, short or ambiguous
    1  at least one is absent, short or ambiguous, or --strict and something moved
    2  nothing could be compared, which is not a pass
    3  a sibling repository is not on this machine, so most of the plan's
       claims could not be looked at either way

IT NEVER PRINTS A SOURCE LINE. It prints paths, line numbers and the plan's own
quoted literals, which are already in a committed document here. The sibling
files carry comments, and a comment beside a booking is exactly where a client
name would sit (L222, docs/PRIVACY-FLOOR.md).

AND THREE MORE KINDS OF CLAIM, each checked where it can be and DELEGATED where
another script already answers it, rather than implemented twice (L370).

    COMMITS       every sibling commit the plan names, asserted to still be an
                  ancestor of that sibling's main. A hex string no checkout
                  knows is reported and not refused: the plan names one such
                  commit on purpose, a branch HEAD it records as a moment in
                  time and says explicitly is "not knowable in advance".

    INSTALLS      what is installed on this machine, by running
                  `scripts/check-sibling-installs.sh` and carrying its verdict.
                  Those two claims were the expensive ones: acting on them when
                  they had drifted would have meant reinstalling two working
                  apps.

    THE EXPORT    the version and the booking count the plan asserts about
                  snapshot 2, read out of the plan's own sentence and compared
                  with the custody file through `measure-booking-export.py`.

WHAT IT DELIBERATELY DOES NOT DO, said rather than left to be assumed from its
name (L400). It does not map the plan's numbered sub-steps to filed issues.
That is the fifth thing ovation#16 asks for and it is a different job: the
plan's numbering and the tracker are two vocabularies, Phase 0's scope is
frozen, and a coverage report full of legitimately unissued sub-steps is one
nobody reads. It is tracked separately.

Seams: OVATION_PLAN, OVATION_SIBLING_ROOT, OVATION_SIBLING_INSTALL_CHECK,
OVATION_BOOKING_EXPORT.
"""
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAN = os.environ.get("OVATION_PLAN") or os.path.join(REPO, "docs", "IMPLEMENTATION-PLAN.md")
# Where the sibling checkouts live. One variable moves the whole estate for a
# test, so no case here has to reach the real ones (L2).
SIBLING_ROOT = os.environ.get("OVATION_SIBLING_ROOT") or os.path.dirname(REPO)

CITATION = re.compile(r'`([A-Za-z0-9_./-]+\.(?:swift|sh|py|json|yml|md)):([0-9]+)(?:-([0-9]+))?')
QUOTED = re.compile(r'`([^`\n]{2,90})`')
# A literal worth anchoring on. The plan's rows also quote shell commands and
# prose in backticks, and neither is a thing to look for inside a file, so what
# is taken is anything that is not itself a citation and not a command line.
NOT_A_LITERAL = re.compile(r"^(?:grep|ls|find|git|rg|cat|sed|awk|xcodebuild|bash|python3?)\b")

SKIP_DIRS = {".git", "build", ".build", "DerivedData", "node_modules", ".swiftpm"}

# A commit the plan names. Eight hex characters is how this estate writes them.
COMMIT = re.compile(r"`([0-9a-f]{8}(?:[0-9a-f]{32})?)`")
# The plan's assertion about SNAPSHOT 2, in its own words. It is scoped to the
# sentence that names that snapshot, because the plan states a version and a
# booking count for snapshot 1 as well and taking the first match compared the
# v3 custody file against snapshot 1's "version 2, 20 bookings" and reported a
# healthy export as drift.
EXPORT_CLAIM = re.compile(r"version (\d+), (\d+) bookings")
EXPORT_SUBJECT = "snapshot 2"


def repositories():
    """The checkouts this plan talks about, by name."""
    found = {}
    for name in ("Ovation", "Downbeat", "Overture"):
        at = os.path.join(SIBLING_ROOT, name)
        if os.path.isdir(at):
            found[name] = at
    return found


def index(root):
    """Every file under a checkout, by basename, ignoring build output."""
    by_name = {}
    for here, directories, files in os.walk(root):
        directories[:] = [d for d in directories if d not in SKIP_DIRS]
        for name in files:
            by_name.setdefault(name, []).append(os.path.join(here, name))
    return by_name


def resolve(path, repos, indexes):
    """(repo, absolute path) for a cited path, or a refusal.

    THE PLAN'S PATHS ARE SHORT FORMS, and that is measured rather than assumed:
    it writes `Downbeat/DownbeatApp.swift` where the file is at
    `Downbeat/Downbeat/DownbeatApp.swift`, because Downbeat's app sources sit two
    levels down. So the tail of the cited path is matched against the real tree
    rather than joined to a root.
    """
    wanted = path.split("/")
    # A PATH THAT NAMES ITS REPOSITORY IS RESOLVED THERE AND NOWHERE ELSE. The
    # plan writes `Downbeat/CLAUDE.md` for a file at that checkout's root and
    # `mac/...` for one inside Overture's, so the first segment is often the
    # answer to which repository this is. Without this, `Downbeat/CLAUDE.md`
    # matched Overture's CLAUDE.md too, by basename, and was reported ambiguous
    # while the plan had already said which.
    inside = dict(repos)
    if len(wanted) > 1:
        for name in repos:
            if wanted[0].lower() == name.lower():
                inside = {name: repos[name]}
                wanted = wanted[1:]
                break
    hits = []
    for name, root in inside.items():
        for candidate in indexes[name].get(wanted[-1], []):
            relative = os.path.relpath(candidate, root).split("/")
            if relative[-len(wanted):] == wanted or wanted[-1] == relative[-1]:
                hits.append((name, candidate, relative[-len(wanted):] == wanted))
    exact = [h for h in hits if h[2]]
    if exact:
        hits = exact
    seen = {(name, at) for name, at, _ in hits}
    if not seen:
        return None, "ABSENT"
    if len({name for name, _ in seen}) > 1:
        return sorted({name for name, _ in seen}), "AMBIGUOUS"
    if len(seen) > 1:
        return sorted(at for _, at in seen), "AMBIGUOUS"
    name, at = next(iter(seen))
    return (name, at), None


def literals(row):
    out = []
    for found in QUOTED.finditer(row):
        said = found.group(1)
        if CITATION.match("`" + said):
            continue
        if NOT_A_LITERAL.match(said.strip()):
            continue
        out.append(said)
    return out


def main(argv=()):
    strict = "--strict" in argv
    if not os.path.isfile(PLAN):
        print("CANNOT MEASURE: no plan at %s, so no claim was checked." % PLAN)
        return 2
    repos = repositories()
    if "Downbeat" not in repos or "Overture" not in repos:
        missing = [n for n in ("Downbeat", "Overture") if n not in repos]
        print("CANNOT MEASURE: %s is not under %s, so almost every claim this "
              "plan makes could not be looked at either way. That is not a pass: "
              "a checker reporting green because it found nothing to check is "
              "worse than no checker, because the green is read as confirmation."
              % (" and ".join(missing), SIBLING_ROOT))
        return 3
    indexes = {name: index(root) for name, root in repos.items()}

    rows = open(PLAN, encoding="utf-8").read().split("\n")
    claims = []
    for number, row in enumerate(rows, 1):
        found = list(CITATION.finditer(row))
        if not found:
            continue
        anchors = literals(row)
        for match in found:
            # A RANGE IS A RANGE. The plan cites `:92-99` far more often than a
            # single line, and reading only the first number reported a claim as
            # having moved seven lines when the thing it quotes sits INSIDE the
            # range it gives.
            claims.append((number, match.group(1), int(match.group(2)),
                           int(match.group(3) or match.group(2)), anchors))
    # A PLAN THAT CITES NO FILE IS NOT NECESSARILY A PLAN THAT CLAIMS NOTHING.
    # It can still name commits and still assert what the export holds, and an
    # early refusal here skipped both: the suite caught it by staging a plan
    # whose only claim was about the export and getting "cannot measure" (L530).
    # The refusal is made at the END instead, over everything that was asked.

    verdicts = {}
    for plan_line, path, cited, cited_to, anchors in claims:
        where, refusal = resolve(path, repos, indexes)
        if refusal == "ABSENT":
            verdicts.setdefault("ABSENT", []).append(
                (plan_line, path, cited, "no file of that name in any checkout"))
            continue
        if refusal == "AMBIGUOUS":
            verdicts.setdefault("AMBIGUOUS", []).append(
                (plan_line, path, cited,
                 "resolves in %s, so the plan must write a path that names one"
                 % ", ".join(str(w) for w in where)))
            continue
        name, at = where
        lines = open(at, encoding="utf-8", errors="replace").read().split("\n")
        if cited > len(lines):
            verdicts.setdefault("SHORT", []).append(
                (plan_line, path, cited,
                 "%s has %d line(s)" % (name, len(lines))))
            continue
        # THE NEAREST OCCURRENCE, NOT THE FIRST. A symbol usually appears in the
        # comment above its declaration as well as in the declaration, and
        # taking the first match reported `CommitOrchestrator.swift:14` as
        # having moved to line 8 when the declaration is still at 14 and line 8
        # is the comment that introduces it (L237).
        present = {}
        for anchor in anchors:
            where = [n for n, line in enumerate(lines, 1) if anchor in line]
            if not where:
                # A SWIFT SIGNATURE IS QUOTED IN SHORTHAND. The plan writes
                # `labelIds(of:)` where the source says `labelIds(of message:`,
                # which is how Swift is talked about and is not a literal
                # anywhere. So a literal that is not found whole is retried as
                # the CALL it names: the identifier before its first bracket,
                # followed by that bracket. It reported `ReplyDetection.swift:114`
                # as having moved 19 lines when the function is exactly where the
                # plan says.
                #
                # ONLY WHERE THE LITERAL IS A CALL, and this is the second time
                # that mattered. A looser fallback on the first word matched
                # `Overture` in a comment for the quoted `Overture.store`, which
                # is a claim about a DIFFERENT file entirely, and reported a
                # correct citation as moved (L237).
                call = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(", anchor)
                if call and len(call.group(1)) >= 4:
                    needle = call.group(1) + "("
                    where = [n for n, line in enumerate(lines, 1)
                             if needle in line.replace(" (", "(")]
            if where:
                present[anchor] = min(where, key=lambda n: abs(n - cited))
        if not anchors:
            verdicts.setdefault("UNANCHORED", []).append(
                (plan_line, path, cited,
                 "the plan's row quotes nothing to look for, so the line number "
                 "is the only claim and a line number alone cannot be checked"))
            continue
        if not present:
            verdicts.setdefault("UNANCHORED", []).append(
                (plan_line, path, cited,
                 "%s is there and none of the %d literal(s) this row quotes is "
                 "in it, which is the right answer for a row that quotes what is "
                 "ABSENT. Nothing about this citation was checked either way"
                 % (name, len(anchors))))
            continue
        def distance(n):
            if cited <= n <= cited_to:
                return 0
            return min(abs(n - cited), abs(n - cited_to))

        nearest = min(present.values(), key=distance)
        if distance(nearest) <= 3:
            verdicts.setdefault("HELD", []).append((plan_line, path, cited, name))
        else:
            verdicts.setdefault("MOVED", []).append(
                (plan_line, path, cited,
                 "now at line %d in %s, %+d" % (nearest, name, nearest - cited)))

    # ----------------------------------------------------------------- commits
    named = {}
    for number, row in enumerate(rows, 1):
        for found in COMMIT.finditer(row):
            named.setdefault(found.group(1), number)
    commits_bad = 0
    for sha, plan_line in sorted(named.items(), key=lambda kv: kv[1]):
        homes = []
        for name, root in repos.items():
            if subprocess.run(["git", "-C", root, "cat-file", "-e", sha + "^{commit}"],
                              capture_output=True).returncode == 0:
                homes.append((name, root))
        if not homes:
            print("  UNPLACED   plan:%d  commit %s is in no checkout here, so its "
                  "ancestry could not be looked at either way" % (plan_line, sha))
            continue
        for name, root in homes:
            ancestor = subprocess.run(
                ["git", "-C", root, "merge-base", "--is-ancestor", sha, "main"],
                capture_output=True).returncode == 0
            if ancestor:
                print("  ANCESTOR   plan:%d  commit %s is on %s's main"
                      % (plan_line, sha, name))
            else:
                commits_bad += 1
                print("  UNMERGED   plan:%d  commit %s is in %s and is NOT an "
                      "ancestor of its main" % (plan_line, sha, name))

    # ---------------------------------------------------------------- installs
    installs = os.environ.get("OVATION_SIBLING_INSTALL_CHECK") or os.path.join(
        REPO, "scripts", "check-sibling-installs.sh")
    installs_bad = 0
    if os.path.isfile(installs):
        done = subprocess.run(["bash", installs], capture_output=True, text=True)
        said = [l.strip() for l in (done.stdout + done.stderr).strip().splitlines()]
        # ITS VERDICT LINE, not its last line. The last line is the second half
        # of a wrapped sentence, and a report that prints "and the Downbeat
        # export is version 3" without the PASS in front of it has dropped the
        # answer and kept the detail (L351).
        verdict = next((l for l in said
                        if l.split(":")[0] in ("PASS", "BLOCKED", "CANNOT MEASURE",
                                               "REFUSED", "FAIL")), None)
        print("  INSTALLS   %s" % (verdict or (said[-1] if said else "said nothing")))
        if done.returncode not in (0,):
            installs_bad = 1
    else:
        print("  INSTALLS   CANNOT MEASURE: %s is not there, so what is actually "
              "installed was not looked at" % installs)
        installs_bad = 1

    # ------------------------------------------------------------------ export
    export_bad = 0
    export = os.environ.get("OVATION_BOOKING_EXPORT") or os.path.expanduser(
        "~/Library/Application Support/Ovation/custody/"
        "downbeat-export-v3-2026-09-05.json")
    stated = None
    for number, row in enumerate(rows, 1):
        if EXPORT_SUBJECT not in row.lower():
            continue
        found = EXPORT_CLAIM.search(row)
        if found:
            stated = (number, int(found.group(1)), int(found.group(2)))
            break
    if stated is None:
        print("  EXPORT     CANNOT MEASURE: the plan states no version and booking "
              "count for the export, so there was nothing to compare")
    elif not os.path.isfile(export):
        print("  EXPORT     CANNOT MEASURE: no custody export at that path, so the "
              "plan's stated version %d and %d booking(s) were not checked"
              % (stated[1], stated[2]))
    else:
        # AN UNREADABLE EXPORT IS ITS OWN OUTCOME. Handed a truncated or
        # half written file this raised a traceback and exited 1, which is the
        # code for "the plan has drifted": the one thing this script exists to
        # tell apart, reported as the other (L11). Found by a fixture that
        # happened to write invalid JSON.
        try:
            measured = json.load(open(export, encoding="utf-8"))
        except (ValueError, OSError) as err:
            print("  EXPORT     CANNOT MEASURE: the custody export could not be "
                  "read (%s), so the plan's stated version %d and %d booking(s) "
                  "were not checked against anything"
                  % (type(err).__name__, stated[1], stated[2]))
            measured = None
        if measured is None:
            version, bookings = None, None
        else:
            version = measured.get("version")
            bookings = len(measured.get("bookings") or [])
        if measured is None:
            pass
        elif (version, bookings) == (stated[1], stated[2]):
            print("  EXPORT     plan:%d  version %s and %d booking(s), as stated"
                  % (stated[0], version, bookings))
        else:
            export_bad = 1
            print("  EXPORT     plan:%d  the plan states version %d and %d "
                  "booking(s); the export is version %s with %d"
                  % (stated[0], stated[1], stated[2], version, bookings))

    order = ["ABSENT", "AMBIGUOUS", "SHORT", "MOVED", "UNANCHORED", "HELD"]
    for kind in order:
        for plan_line, path, cited, detail in verdicts.get(kind, []):
            if kind == "HELD":
                print("  HELD       plan:%d  %s:%d in %s" % (plan_line, path, cited, detail))
            else:
                print("  %-10s plan:%d  %s:%d  %s" % (kind, plan_line, path, cited, detail))

    broken = sum(len(verdicts.get(k, [])) for k in ("ABSENT", "AMBIGUOUS", "SHORT"))
    broken += commits_bad + installs_bad + export_bad
    if not claims and not named and stated is None:
        print("CANNOT MEASURE: the plan cites no file, names no commit and states "
              "nothing about the export, so this compared nothing. A plan that "
              "stopped citing its sources and one whose sources all still agree "
              "must not report the same thing.")
        return 2
    moved = len(verdicts.get("MOVED", []))
    unanchored = len(verdicts.get("UNANCHORED", []))
    held = len(verdicts.get("HELD", []))
    refused = broken or (strict and moved)
    print("%s: %d citation(s) checked. %d held where the plan says, %d moved, "
          "%d unanchored, %d absent, ambiguous or past the end of the file."
          % ("DRIFTED" if refused else "OK",
             len(claims), held, moved, unanchored, broken))
    if broken:
        print("The plan is corrected by a PERSON, not by this check: a claim that "
              "has drifted may mean the plan is wrong or the sibling has "
              "regressed, and only a reader can tell which.")
    if moved and not strict:
        print("A moved line is information rather than a fault: these are other "
              "repositories and they change daily. Run with --strict to refuse "
              "on it, which is what bringing the plan back into step wants.")
    if unanchored:
        print("An unanchored row quotes nothing that is IN the file it cites, "
              "which is correct for a row saying what is absent. Nothing about "
              "those citations was checked either way.")
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
