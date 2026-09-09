#!/usr/bin/env bash
# Is CI still running, or has it quietly stopped? ovation#155.
#
# CI THAT HAS STOPPED IS THE SLOWEST TEST SUITE THERE IS, AND IT STOPS QUIETLY.
# A workflow that stops triggering looks exactly like a repository nobody is
# pushing to: no red build, no notification, just an absence (L314, L98). Every
# way it can happen here is silent: an edit that makes it never trigger, a change
# in how branches are pushed, the repository going private under ovation#15 and
# meeting a minute cap, or GitHub disabling the workflow.
#
# IT COMPARES TWO DATES RATHER THAN ONE. "No successful run for N days" cries
# wolf on every quiet fortnight, and an alert that cries wolf gets ignored (L36).
# What is actually alarming is a COMMIT that no successful run has followed: work
# is landing and nothing is judging it. So this asks whether the newest commit is
# newer than the newest successful run, by more than a grace period that lets a
# run in flight finish.
#
# THREE OUTCOMES, because they need three different actions:
#
#   0  PASS            the newest commit has been judged, or is inside the grace
#   1  BLOCKED         work has landed that no successful run has followed
#   2  CANNOT MEASURE  a date could not be got, for a named reason
#
# THE DATES ARE INPUTS. Whoever calls this knows how to ask GitHub; this decides
# what the answer means, and it is a separate file for exactly that reason: a
# judgement inside a workflow step can only be tested by pushing (L2, L196).
set -uo pipefail

NOW="${OVATION_CI_NOW:-}"
LAST_SUCCESS="${OVATION_CI_LAST_SUCCESS:-}"
LAST_COMMIT="${OVATION_CI_LAST_COMMIT:-}"
GRACE_HOURS="${OVATION_CI_GRACE_HOURS:-24}"

cannot_measure() {
    echo "CANNOT MEASURE: $1"
    [ "${2:-}" = "" ] || echo "    $2"
    echo "    Nothing was judged. This is not a pass."
    exit 2
}

[ -n "$NOW" ] || cannot_measure "no current time was given" \
    "set OVATION_CI_NOW to an ISO 8601 instant"
[ -n "$LAST_COMMIT" ] || cannot_measure "the date of the newest commit was not given" \
    "without it, an absent run cannot be told from a repository nobody is pushing to"

# Every date is parsed by one helper, and a date that will not parse is CANNOT
# MEASURE rather than a comparison against a value that lost (L50). `date` itself
# is not used: its BSD and GNU forms take different flags and neither errors on
# the other's, so a pattern that silently stopped parsing would read as an
# absence (L434).
delta_hours() {
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import datetime, sys
def parse(text):
    return datetime.datetime.fromisoformat(text.strip().replace("Z", "+00:00"))
try:
    later, earlier = parse(sys.argv[1]), parse(sys.argv[2])
except Exception:
    raise SystemExit(1)
print("%.4f" % ((later - earlier).total_seconds() / 3600.0))
PY
}

COMMIT_AGE="$(delta_hours "$NOW" "$LAST_COMMIT")" \
    || cannot_measure "the newest commit's date could not be read" \
        "it was: ${LAST_COMMIT}"

if [ -z "$LAST_SUCCESS" ]; then
    # NEVER a pass. A repository with commits and no successful run is the
    # strongest form of the thing this exists to find, and it is also what a
    # brand new workflow looks like, so it says which it is by naming the commit.
    if awk "BEGIN{exit !($COMMIT_AGE > $GRACE_HOURS)}"; then
        echo "BLOCKED: no successful CI run exists at all, and the newest commit is"
        echo "    ${COMMIT_AGE%.*} hour(s) old."
        echo "    Work has landed that nothing has judged."
        exit 1
    fi
    echo "PASS: no successful run yet, and the newest commit is inside the"
    echo "    ${GRACE_HOURS} hour grace period, so a run may still be in flight."
    exit 0
fi

BEHIND="$(delta_hours "$LAST_COMMIT" "$LAST_SUCCESS")" \
    || cannot_measure "the last successful run's date could not be read" \
        "it was: ${LAST_SUCCESS}"

# A commit OLDER than the last successful run is the healthy case: everything
# that has landed has been judged.
if awk "BEGIN{exit !($BEHIND <= 0)}"; then
    echo "PASS: the newest commit has been followed by a successful CI run."
    exit 0
fi

# It is newer. That is only alarming once a run has had time to finish, which is
# what the grace period is: without it this would fire on every push, in the
# minutes between landing and going green, and an alarm that fires on the normal
# case is one nobody reads (L36, L144).
if awk "BEGIN{exit !($COMMIT_AGE <= $GRACE_HOURS)}"; then
    echo "PASS: the newest commit is newer than the last successful run and is only"
    echo "    ${COMMIT_AGE%.*} hour(s) old, so a run is still allowed to be in flight."
    exit 0
fi

echo "BLOCKED: the newest commit is ${COMMIT_AGE%.*} hour(s) old and no successful"
echo "    CI run has followed it. The last successful run was ${BEHIND%.*} hour(s)"
echo "    before that commit."
echo "    Work has landed that nothing has judged. CI may have stopped triggering,"
echo "    or it may be failing on every run."
exit 1
