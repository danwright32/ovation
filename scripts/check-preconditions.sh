#!/bin/bash
# Run the situational checks: the ones that answer questions about the world
# OUTSIDE this repository.
#
# ovation#27. Three checks run on every push, from scripts/git-hooks/pre-push.
# These two ran nowhere at all, and that is worse than an ordinary wiring gap:
# check-sibling-installs.sh exists BECAUSE a fact about another application went
# stale invisibly for a week, and a re-read that only happens when somebody
# remembers to type it has the same defect the thing it replaced had (L3, L175).
#
# WHY THESE ARE NOT IN THE PUSH GATE. Neither belongs there. One reads two files
# outside the repository and runs git in a sibling checkout; the other reads live
# data that is legitimately empty most of the time. A push gate that goes red
# because Downbeat has not been launched lately is a gate people learn to skip
# (L378), and CANNOT MEASURE blocks a push.
#
# RUN THIS at the start of any Phase 6 or booking queue work, before believing
# anything written down about the siblings.
#
# EVERY CHECK REPORTS SEPARATELY. Two independent checks must never share one
# status field (L53), and BLOCKED and CANNOT MEASURE are different facts needing
# different actions (L11, L260). The aggregate exit code exists for a caller, and
# the per check lines exist for a person; neither replaces the other.
#
#   0  every check passed
#   1  at least one BLOCKED, a fact measured and wrong
#   2  none blocked, but at least one CANNOT MEASURE, or nothing was run
#
# BLOCKED OUTRANKS CANNOT MEASURE because it is the one carrying a real finding.
#
# NOTHING IS RECORDED. Dan's decision, 2026-09-06: a stored pass with a date is
# exactly the stale recorded fact these checks exist to replace, and it invites
# the next reader to consult the record instead of re-running (L244, L336). The
# TIME is printed instead, so a transcript still says when it ran, and the only
# way to know the answer now is to ask now.
#
# EVERY CHECK RUNS EVEN AFTER ONE FAILS. Stopping at the first hides the rest,
# and somebody running this wants the whole picture in one go rather than one
# problem per invocation (L73).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The situational checks, and the list the partition test in
# scripts/test-preconditions.sh holds to what is actually on disk, so a new
# check script cannot end up run by nothing (L96).
DEFAULT_CHECKS="${REPO_ROOT}/scripts/check-custody-files.sh ${REPO_ROOT}/scripts/check-sibling-installs.sh ${REPO_ROOT}/scripts/check-booking-queue.sh ${REPO_ROOT}/scripts/check-backup-grant.sh"
CHECKS="${OVATION_PRECONDITION_CHECKS-$DEFAULT_CHECKS}"

echo "Preconditions, run at $(date '+%Y-%m-%d %H:%M:%S %Z'). Nothing is recorded; re-run to ask again."

# A run that checked nothing must never read as a run where everything passed
# (L98). This is the state a mistyped list or an empty override produces.
if [ -z "${CHECKS// /}" ]; then
    echo "CANNOT MEASURE: nothing was run, so nothing was checked."
    echo "    The check list is empty. This is not a pass."
    exit 2
fi

RAN=0
BLOCKED=0
UNMEASURABLE=0

for c in $CHECKS; do
    name="$(basename "$c")"
    if [ ! -x "$c" ]; then
        # Named, never skipped. A check that is not there is a different fact
        # from one that ran and passed, and only one of them means anything.
        echo "  CANNOT MEASURE  ${name}"
        echo "                  it is not there, or is not executable, at ${c}"
        UNMEASURABLE=$((UNMEASURABLE+1))
        RAN=$((RAN+1))
        continue
    fi

    out="$("$c" 2>&1)"
    status=$?
    RAN=$((RAN+1))

    case "$status" in
        0) label="PASS          " ;;
        1) label="BLOCKED       "; BLOCKED=$((BLOCKED+1)) ;;
        *) label="CANNOT MEASURE"; UNMEASURABLE=$((UNMEASURABLE+1)) ;;
    esac
    echo "  ${label}  ${name}"
    # The check's own words, indented under it. They already obey the privacy
    # floor: counts, versions, ids and field names only (docs/PRIVACY-FLOOR.md).
    printf '%s\n' "$out" | sed 's/^/                  /'
done

echo
echo "Ran ${RAN} check(s): $((RAN - BLOCKED - UNMEASURABLE)) passed, ${BLOCKED} blocked, ${UNMEASURABLE} not measurable."

[ "$BLOCKED" -gt 0 ] && exit 1
[ "$UNMEASURABLE" -gt 0 ] && exit 2
exit 0
