#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a plan sub-step with no issue, and an issue that maps to no sub-step.

    check-plan-issues.sh

ovation#180, the fifth thing ovation#16 asked for and the one part
`scripts/check-plan-claims.sh` deliberately does not do. A sweep of Phase 0 on the
day its issues were filed found that plan 0.2 step 5 had no home at all, because
the issues were derived by reading the plan once. The plan's numbering and the
tracker are two vocabularies, and nothing held them to each other.

THE RULE IS DAN'S, 2026-09-29: every numbered sub-step of a phase whose milestone
is OPEN owes a filed issue, and every OPEN issue in that milestone maps back to a
sub-step. The second half was narrowed by Dan on 2026-09-30, answering the first
real run on pull request 628: closed issues are history and are not counted.
That run had found 92 closed issues citing no sub-step, which nobody would edit. A phase with no open milestone is not checked until it is opened, which
is what keeps this from being a coverage report full of legitimately unissued
steps that nobody reads (L400).

WHAT A SUB-STEP IS, read from the plan's own numbering rather than a list kept
beside it (L41). A sub-step is a number like `4.2` or `5.0a` that opens a `###`
heading or a bold lead inside a `## Phase` section. The numbered list items inside
one are its STEPS, which the plan itself cites as "0.2 step 4", and they are
covered by the sub-step's issue: some of those lists are steps and some are not
(4.0's is the four reader states), and a check that guessed which would refuse the
plan for being a list.

WHICH MILESTONE A SUB-STEP IS ON. The phase's `Milestone:` line, unless a table
row in the plan gives that sub-step one of its own, which is how Phase 1 tracks
each foundation issue on the feature milestone that cannot ship without it.

WHICH ISSUES MUST MAP BACK: every OPEN issue in a milestone a phase's
`Milestone:` line names, when that milestone is open. A closed one is history
(Dan, 2026-09-30) and is not read in this direction at all, whatever it cites.
In the other direction a closed issue still counts: a sub-step whose issue was
closed has an issue, which is what finished work looks like. A milestone
reached only through Phase 1's table (`Ungrouped` is one) is no phase's milestone,
so its other issues owe nothing to the plan.

WHAT MAPS AN ISSUE BACK is its title or body citing a sub-step the way this
tracker already does: "Plan 1.10", "plan 4.2 step 5", "Phase 0.3". A number is
matched whole, so plan 4.10 does not cover 4.1. An issue that cites only numbers
the plan does not have is STRAY rather than UNMAPPED, because the remedy differs:
the plan may have been renumbered under it.

IT REPORTS, IT DOES NOT FILE. A sub-step with no issue may be one the plan should
drop, and an issue that maps to nothing may be one the plan should gain; only a
reader can tell which.

IT PRINTS NUMBERS, NEVER AN ISSUE'S WORDS. This repository is public, so a
workflow log is a published document (docs/PRIVACY-FLOOR.md).

NOT A PUSH GATE, for check-design-record-open.sh's reason: it asks GitHub, and a
gate refusing every push from a machine without a network is one people learn to
skip (L376, L571). It runs in .github/workflows/plan-issues.yml, and by hand.

Outcomes, each said differently because each needs different work (L11):

    ISSUED             a sub-step owed an issue, and an issue cites it
    UNISSUED           a sub-step owed an issue, and no issue cites it
    UNMAPPED           an open issue in an open phase milestone cites no sub-step
    STRAY              one cites only sub-steps the plan does not number
    NO SUCH MILESTONE  the plan names a milestone the tracker does not have
    NOT OWED           a sub-step or phase with no milestone, or a closed one

Exit codes:

    0  every sub-step owed an issue has one, and every issue maps back
    1  something is UNISSUED, UNMAPPED, STRAY or names NO SUCH MILESTONE
    2  the plan, the issues or the milestones could not be read, or nothing is
       owed at all: not a pass
    3  used wrongly

Seams:

    OVATION_PLAN                     the plan to read
    OVATION_PLAN_ISSUES_COMMAND      prints every issue as a JSON array of
                                     number, state, title, body and milestone
    OVATION_PLAN_MILESTONES_COMMAND  prints one milestone per line, its state and
                                     its title separated by a tab
    OVATION_PLAN_ISSUE_LIMIT         the most issues the list is asked for, which
                                     a list reaching is refused as possibly short
"""
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAN = os.environ.get("OVATION_PLAN") or os.path.join(REPO, "docs", "IMPLEMENTATION-PLAN.md")
ISSUE_LIMIT = int(os.environ.get("OVATION_PLAN_ISSUE_LIMIT") or 3000)
ISSUES_COMMAND = os.environ.get("OVATION_PLAN_ISSUES_COMMAND") or (
    "gh issue list --state all --limit %d --json number,state,title,body,milestone" % ISSUE_LIMIT)
MILESTONES_COMMAND = os.environ.get("OVATION_PLAN_MILESTONES_COMMAND") or (
    "gh api 'repos/{owner}/{repo}/milestones?state=all&per_page=100' --paginate "
    "--jq '.[] | [.state, .title] | @tsv'")

NUMBER = r"\d+\.\d+(?:\.\d+)?[a-z]?"
PHASE = re.compile(r"^## (Phase [^,\s]+)")
SUB_STEP = re.compile(r"^(?:### |\*\*)(" + NUMBER + r")(?![\w.])")
PHASE_MILESTONE = re.compile(r"^Milestone: `([^`]+)`")
TABLE_ROW = re.compile(r"^\|\s*(" + NUMBER + r")(?![\w.])[^|]*\|\s*`([^`]+)`")
# A CITATION IS A WHOLE NUMBER: the pattern takes every digit and the letter
# after them, so plan 4.10 and plan 4.1a do not cite 4.1.
CITES = re.compile(r"(?i)\b(?:plan|phase)\s+(" + NUMBER + r")")


def read_plan(text):
    """(sub-steps, phase milestones, where each milestone is named).

    sub-steps: number -> dict(line, phase, milestone). phase milestones: phase ->
    (milestone, line). A number seen outside any `## Phase` section is not a
    sub-step, which keeps the cross-cutting section and the preamble out.
    """
    subs, phases, table = {}, {}, {}
    phase = None
    for n, line in enumerate(text.split("\n"), 1):
        found = PHASE.match(line)
        if found:
            phase = found.group(1)
            phases.setdefault(phase, (None, None))
            continue
        if line.startswith("## "):
            phase = None
            continue
        if phase is None:
            continue
        found = PHASE_MILESTONE.match(line)
        if found and phases[phase][0] is None:
            phases[phase] = (found.group(1), n)
            continue
        found = TABLE_ROW.match(line)
        if found:
            table.setdefault(found.group(1), (found.group(2), n))
            continue
        found = SUB_STEP.match(line)
        if found and found.group(1) not in subs:
            subs[found.group(1)] = {"line": n, "phase": phase}
    for number, sub in subs.items():
        if number in table:
            sub["milestone"], sub["named_on"] = table[number]
        else:
            sub["milestone"], sub["named_on"] = phases[sub["phase"]]
    return subs, phases


def run(command):
    try:
        done = subprocess.run(command, shell=True, capture_output=True, text=True,
                              timeout=120)
    except (subprocess.SubprocessError, OSError):
        return None
    if done.returncode != 0:
        return None
    return done.stdout


def read_issues():
    """A list of issues, or a sentence saying why there is none."""
    said = run(ISSUES_COMMAND)
    if said is None:
        return None, "the issues could not be listed"
    try:
        issues = json.loads(said)
    except ValueError:
        return None, "the issues could not be listed: the answer was not JSON"
    if not isinstance(issues, list) or not all(isinstance(i, dict) and "number" in i
                                               for i in issues):
        return None, "the issues could not be listed: the answer was not a list of issues"
    if not issues:
        # A TRACKER WITH NO ISSUES AT ALL is a lookup that went wrong, not a
        # finding that every sub-step is unissued (L215).
        return None, "the issue list came back empty, which is a lookup that failed"
    if len(issues) >= ISSUE_LIMIT:
        return None, ("the issue list reached its limit of %d and may have been cut "
                      "short, so an issue missing from it proves nothing" % ISSUE_LIMIT)
    return issues, None


def read_milestones():
    """title -> 'open' or 'closed', or a sentence saying why there is none."""
    said = run(MILESTONES_COMMAND)
    if said is None:
        return None, "the milestones could not be listed"
    out = {}
    for line in said.splitlines():
        if not line.strip():
            continue
        state, _, title = line.partition("\t")
        if state not in ("open", "closed") or not title:
            return None, "the milestones could not be listed: a line was not a state and a title"
        out[title] = state
    if not out:
        return None, "the milestone list came back empty, which is a lookup that failed"
    return out, None


def main(argv):
    if argv:
        print(__doc__.strip().split("\n")[2])
        return 3
    if not os.path.isfile(PLAN):
        print("CANNOT MEASURE: no plan at %s, so no sub-step was read. That is not a pass."
              % PLAN)
        return 2
    subs, phases = read_plan(open(PLAN, encoding="utf-8").read())
    issues, why = read_issues()
    if issues is None:
        print("CANNOT MEASURE: %s, so nothing was compared. That is not a pass." % why)
        return 2
    milestones, why = read_milestones()
    if milestones is None:
        print("CANNOT MEASURE: %s, so which phases are open is unknown. That is not a pass."
              % why)
        return 2

    cited_by = {}
    cites = {}
    for issue in issues:
        text = "%s\n%s" % (issue.get("title") or "", issue.get("body") or "")
        numbers = set(CITES.findall(text))
        cites[issue["number"]] = numbers
        for number in numbers:
            cited_by.setdefault(number, []).append(issue["number"])

    refused = {"UNISSUED": 0, "UNMAPPED": 0, "STRAY": 0, "NO SUCH MILESTONE": 0}

    # --------------------------------------------------- milestones the plan names
    named = {}
    for phase, (milestone, line) in phases.items():
        if milestone:
            named.setdefault(milestone, ("for %s" % phase, line))
    for number, sub in subs.items():
        if sub["milestone"]:
            named.setdefault(sub["milestone"], ("for plan %s" % number, sub["named_on"]))
    for milestone, (what, line) in sorted(named.items(), key=lambda kv: kv[1][1]):
        if milestone not in milestones:
            refused["NO SUCH MILESTONE"] += 1
            print("  NO SUCH MILESTONE `%s`, named %s on plan line %d: the tracker has no "
                  "milestone of that name, so nothing on it could be judged. The plan "
                  "names it or the milestone was renamed" % (milestone, what, line))

    # ----------------------------------------------- every owed sub-step is issued
    owed = 0
    for number, sub in sorted(subs.items(), key=lambda kv: kv[1]["line"]):
        milestone = sub["milestone"]
        if not milestone:
            print("  NOT OWED   plan %s: no milestone, so it owes no issue until one is "
                  "opened for %s" % (number, sub["phase"]))
            continue
        if milestones.get(milestone) != "open":
            continue
        owed += 1
        if number in cited_by:
            print("  ISSUED     plan %s by %s" % (number, ", ".join(
                "ovation#%d" % n for n in sorted(cited_by[number]))))
        else:
            refused["UNISSUED"] += 1
            print("  UNISSUED   plan %s (line %d, milestone `%s`): no issue cites it. File "
                  "one that says `Plan %s`, or take the step out of the plan"
                  % (number, sub["line"], milestone, number))

    # ------------------------------------------- every issue in them maps back
    open_phase_milestones = {}
    for phase, (milestone, line) in phases.items():
        if not milestone or milestone not in milestones:
            continue
        if milestones[milestone] != "open":
            print("  NOT OWED   %s: its milestone `%s` is closed, so its sub-steps and its "
                  "issues are not checked until it is opened" % (phase, milestone))
            continue
        open_phase_milestones[milestone] = phase
    mapped = 0
    for issue in sorted(issues, key=lambda i: i["number"]):
        milestone = (issue.get("milestone") or {}).get("title")
        if milestone not in open_phase_milestones:
            continue
        # ONLY OPEN ISSUES MAP BACK (Dan, 2026-09-30). Asked as "is it open"
        # rather than "is it closed", so an issue whose state is missing or
        # unexpected is still judged rather than waved through (L42).
        if (issue.get("state") or "").upper() == "CLOSED":
            continue
        numbers = cites[issue["number"]]
        if numbers & set(subs):
            mapped += 1
        elif numbers:
            refused["STRAY"] += 1
            print("  STRAY      ovation#%d in `%s` cites plan %s, which the plan does "
                  "not number" % (issue["number"], milestone, ", ".join(sorted(numbers))))
        else:
            refused["UNMAPPED"] += 1
            print("  UNMAPPED   ovation#%d in `%s` cites no plan sub-step"
                  % (issue["number"], milestone))

    if not owed and not open_phase_milestones:
        print("CANNOT MEASURE: no sub-step is owed an issue and no phase milestone is "
              "open, so this compared nothing. A plan whose milestones are all closed "
              "and one this could not read must not report the same thing.")
        return 2
    if any(refused.values()):
        if refused["UNISSUED"]:
            print("REFUSED: %d sub-step(s) of an open milestone have no issue."
                  % refused["UNISSUED"])
        if refused["UNMAPPED"] or refused["STRAY"]:
            print("REFUSED: %d open issue(s) in an open phase milestone map to no sub-step "
                  "(%d cite nothing, %d cite a number the plan does not have)."
                  % (refused["UNMAPPED"] + refused["STRAY"], refused["UNMAPPED"],
                     refused["STRAY"]))
        if refused["NO SUCH MILESTONE"]:
            print("REFUSED: the plan names %d milestone(s) the tracker does not have."
                  % refused["NO SUCH MILESTONE"])
        print("The plan and the tracker are brought back into step by a PERSON: a "
              "sub-step with no issue may belong out of the plan, and an issue that "
              "maps to nothing may belong in it.")
        return 1
    print("OK: %d sub-step(s) owed an issue and every one has one, and all %d open issue(s) "
          "in %d open phase milestone(s) map back to a sub-step."
          % (owed, mapped, len(open_phase_milestones)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
