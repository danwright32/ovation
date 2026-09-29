#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Count the jobs that went red and then green on a re-run of the same commit.

    check-flaky-jobs.sh

ovation#493. Nothing in this repository recorded that a job failed and then
passed when the same commit was run again. ovation#433 and ovation#279 were both
found by a person who happened to be watching, and anything nobody was watching
for is still unrecorded. A flake is a speed cost priced at a full re-run and the
re-run hides the price (L293); without a count, a suite with one flaky case and a
suite with ten look the same, and a red that is unrelated to the change is one
people learn to re-run rather than read (L538).

WHAT IS COUNTED: over the last 30 days, every job that concluded `failure` on one
attempt of a workflow run and `success` on a later attempt of the SAME run. A
re-run is the same run on the same commit with nothing new arriving, which is
what "red then green with no push between" means.

WHY ATTEMPTS OF ONE RUN AND NOT EVERY RUN ON ONE COMMIT. A second run on a commit
exists only because a second EVENT arrived: a schedule, a finished workflow, an
edited pull request. That event is an input besides the commit, so a job going
green on it may be the world changing rather than the job being flaky: the pull
request description check goes green when the description is fixed, and the
design record check when an issue is reopened. Counting those would accuse
monitors of flaking for doing their job (L144). Measured on 2026-09-29: of 1000
runs in the month the only failure then success across separate runs on one
commit was exactly that description check, while the re-runs held the real one.

NOTHING IS DERIVED FROM A NAME A RENAME WOULD BREAK. No job or workflow name is
written here. A workflow is keyed on its id, and a job's name is compared only
with the same job in another attempt of the same run, which reads one workflow
file at one commit, so the name cannot differ between them. The name shown is
the newest run's, and a job renamed inside the window shows as two lines, which
is visible rather than silent.

IT ASKS ONE DAY AT A TIME, because GitHub's run listing stops at 1000 results and
a month of this repository's runs reached it on the day this was written. A day
that reaches the limit, like an attempt holding more jobs than were returned, is
refused rather than read as complete (L211).

ITS VERDICT CARRIES NO DATE AND NO WINDOW TOTAL, so what a finding prints on
stdout changes only when the flaky jobs or their counts do, and the
finding reporter (ovation#339) can say it once per verdict rather than once per
run.

IT RUNS IN .github/workflows/flaky-jobs.yml, which reports through the finding
reporter: one finding issue while any flake stands in the
window, commented on only when the count changes, closed when the window holds
none. A count on a page nobody reads would be L357.

Outcomes:

    FLAKY   a job went red then green on a re-run, with its count and its runs
    CLEAR   nothing did

Exit codes:

    0  no job went red then green on a re-run in the window
    1  at least one did
    2  a day or an attempt could not be read, or the window held no run at all:
       not a pass
    3  used wrongly

Seams:

    OVATION_GH               the command that talks to GitHub, default `gh`
    OVATION_REPO             owner/name, default the workflow's own repository
    OVATION_FLAKY_TODAY      the last day of the window, YYYY-MM-DD, default today
                             in UTC
    OVATION_FLAKY_DAY_LIMIT  the most runs one day's listing is asked for
"""
import datetime
import json
import os
import shlex
import subprocess
import sys

WINDOW_DAYS = 30
GH = shlex.split(os.environ.get("OVATION_GH") or "gh")
REPO = os.environ.get("OVATION_REPO") or os.environ.get("GITHUB_REPOSITORY") or "danwright32/ovation"
DAY_LIMIT = int(os.environ.get("OVATION_FLAKY_DAY_LIMIT") or 1000)


class CannotMeasure(Exception):
    pass


def ask(args, what):
    try:
        done = subprocess.run(GH + args, capture_output=True, text=True, timeout=120)
    except (subprocess.SubprocessError, OSError):
        raise CannotMeasure(what)
    if done.returncode != 0:
        raise CannotMeasure(what)
    try:
        return json.loads(done.stdout)
    except ValueError:
        raise CannotMeasure(what + ": the answer was not JSON")


def runs_on(day):
    what = "the runs created on %s could not be listed" % day
    rows = ask(["run", "list", "--repo", REPO, "--created", day, "--limit", str(DAY_LIMIT),
                "--json", "databaseId,attempt,workflowDatabaseId,workflowName,headSha"], what)
    if not isinstance(rows, list):
        raise CannotMeasure(what + ": the answer was not a list")
    if len(rows) >= DAY_LIMIT:
        raise CannotMeasure("the runs created on %s reached the limit of %d and may have "
                            "been cut short" % (day, DAY_LIMIT))
    return rows


def jobs_of(run_id, attempt):
    what = "the jobs of run %d attempt %d could not be read" % (run_id, attempt)
    answer = ask(["api", "repos/%s/actions/runs/%d/attempts/%d/jobs?per_page=100"
                  % (REPO, run_id, attempt)], what)
    if not isinstance(answer, dict) or not isinstance(answer.get("jobs"), list):
        raise CannotMeasure(what + ": the answer held no job list")
    jobs = answer["jobs"]
    if answer.get("total_count", len(jobs)) > len(jobs):
        raise CannotMeasure("run %d attempt %d holds %d job(s) and %d were returned, so "
                            "a job not returned could be the flaky one"
                            % (run_id, attempt, answer["total_count"], len(jobs)))
    return {job.get("name"): job.get("conclusion") for job in jobs}


def main(argv):
    if argv:
        print(__doc__.strip().split("\n")[2])
        return 3
    today = os.environ.get("OVATION_FLAKY_TODAY") or datetime.datetime.now(
        datetime.timezone.utc).strftime("%Y-%m-%d")
    try:
        last = datetime.date.fromisoformat(today)
    except ValueError:
        print("USED WRONGLY: %r is not a day written YYYY-MM-DD." % today)
        return 3
    days = [(last - datetime.timedelta(days=n)).isoformat() for n in range(WINDOW_DAYS)]

    try:
        runs = []
        for day in sorted(days):
            runs.extend((day, row) for row in runs_on(day))
        if not runs:
            print("CANNOT MEASURE: no run at all in the last %d days. This repository "
                  "runs something every day, so an empty month is a lookup that went "
                  "wrong, and it must not read like a month with no flake." % WINDOW_DAYS)
            return 2
        rerun = [(day, row) for day, row in runs if int(row.get("attempt") or 1) > 1]
        flaky = {}
        names = {}
        for day, row in rerun:
            run_id, attempts = int(row["databaseId"]), int(row["attempt"])
            seen = [jobs_of(run_id, n) for n in range(1, attempts + 1)]
            workflow = row.get("workflowDatabaseId")
            for name in sorted({name for attempt in seen for name in attempt}):
                outcomes = [attempt.get(name) for attempt in seen]
                if "failure" not in outcomes:
                    continue
                if "success" not in outcomes[outcomes.index("failure") + 1:]:
                    continue
                flaky.setdefault((workflow, name), []).append(
                    (run_id, (row.get("headSha") or "")[:8]))
            names[workflow] = row.get("workflowName") or "workflow %s" % workflow
    except CannotMeasure as fault:
        print("CANNOT MEASURE: %s, so nothing about the window is known. That is not "
              "a pass." % fault)
        return 2

    if not flaky:
        print("CLEAR: %d run(s) over the last %d days, %d re-run, and no job went red "
              "then green on a re-run of the same commit."
              % (len(runs), WINDOW_DAYS, len(rerun)))
        return 0
    total = 0
    for (workflow, name), where in sorted(flaky.items(),
                                          key=lambda kv: (-len(kv[1]), names[kv[0][0]], kv[0][1])):
        total += len(where)
        print("  FLAKY  %s: %s, %d time(s): %s" % (
            names[workflow], name, len(where),
            ", ".join("run %d on %s" % pair for pair in where)))
    print("FOUND: %d job(s) went red then green on a re-run of the same commit, %d "
          "time(s) in all, over the last %d days." % (len(flaky), total, WINDOW_DAYS))
    # THE TOTALS GO TO STDERR, which reaches the log and not the verdict. The
    # window slides every day, so how many runs it holds moves while the flaky
    # set stays put, and stdout is what the workflow hands report-finding.sh as
    # its verdict: a total there commented on the finding every day (ovation#512).
    print("Read %d run(s) over the last %d days, %d re-run."
          % (len(runs), WINDOW_DAYS, len(rerun)), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
