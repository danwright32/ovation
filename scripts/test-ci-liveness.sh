#!/bin/bash
# Whether the CI liveness judgement can tell a stopped workflow from a quiet week.
#
# ovation#155. The judgement lives in its own script precisely so it can be
# driven with dates instead of by pushing and waiting (L2, L196), and these cases
# are the ones that decide whether it is worth having: a rule that fires on every
# quiet fortnight is one Dan learns to ignore (L36), and one that never fires is
# a monitor that has never passed anything (L557).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "ci liveness tests" 38

TARGET="scripts/check-ci-liveness.sh"
require_target "$TARGET"

NOW="2026-09-09T12:00:00Z"

# judge <last-success> <last-commit> [grace] [newest run]
#
# THE NEWEST RUN IS A POSITIONAL ARGUMENT, NEVER AN EXPORTED DEFAULT (ovation#212).
# A value one case exports is inherited by every later case's runner, which then
# answers a question it was never asked (L439). Every case below that is not
# about the newest run says `success`, the state in which the dates alone decide,
# which is what each of those cases was written to measure.
judge() {
    OVATION_CI_NOW="$NOW" \
    OVATION_CI_LAST_SUCCESS="$1" \
    OVATION_CI_LAST_COMMIT="$2" \
    OVATION_CI_GRACE_HOURS="${3:-24}" \
    OVATION_CI_NEWEST_RUN="${4:-success}" \
        "./$TARGET" 2>&1
}
status_of() { judge "$@" >/dev/null 2>&1; printf '%s' "$?"; }
says() { if grep -qiF "$2" <<< "$1"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE HEALTHY CASE. Everything that landed has been judged.
# ---------------------------------------------------------------------------
check "a commit followed by a successful run passes" \
    "$(status_of "2026-09-09T11:00:00Z" "2026-09-09T10:00:00Z")" "0"

# AND A QUIET FORTNIGHT IS STILL HEALTHY. This is the case that makes the whole
# check worth having rather than noise: nobody has pushed for two weeks, so there
# is nothing for CI to have run, and a rule keyed on "no run for N days" would be
# raising an alarm about a person taking a holiday.
check "two quiet weeks after a judged commit is not a problem" \
    "$(status_of "2026-08-26T11:00:00Z" "2026-08-26T10:00:00Z")" "0"

# ---------------------------------------------------------------------------
# 2. THE CASE IT EXISTS FOR. Work has landed and nothing has judged it.
# ---------------------------------------------------------------------------
OUT3="$(judge "2026-09-01T10:00:00Z" "2026-09-05T10:00:00Z")"
check "a commit no successful run has followed is BLOCKED" \
    "$(status_of "2026-09-01T10:00:00Z" "2026-09-05T10:00:00Z")" "1"
check "and it says how old the unjudged commit is" "$(says "$OUT3" "hour(s) old")" "yes"
check "and it names both possibilities rather than asserting one" \
    "$(says "$OUT3" "may have stopped triggering")" "yes"

# ---------------------------------------------------------------------------
# 3. THE GRACE PERIOD, both sides of it. Without one this fires on every push in
#    the minutes between landing and going green, which is an alarm on the normal
#    case (L36, L144).
# ---------------------------------------------------------------------------
check "a commit inside the grace period passes, because a run may be in flight" \
    "$(status_of "2026-09-08T10:00:00Z" "2026-09-09T06:00:00Z")" "0"
check "and the same commit past the grace period is blocked" \
    "$(status_of "2026-09-08T10:00:00Z" "2026-09-09T06:00:00Z" 4)" "1"

# ---------------------------------------------------------------------------
# 4. NO SUCCESSFUL RUN AT ALL is the strongest form of the same fact, and it is
#    also what a brand new workflow looks like, so the grace period applies to it
#    too rather than firing the moment CI is added.
# ---------------------------------------------------------------------------
OUT5="$(judge "" "2026-09-01T10:00:00Z" 24 none)"
check "commits with no successful run ever is BLOCKED" \
    "$(status_of "" "2026-09-01T10:00:00Z" 24 none)" "1"
check "and it says that none exists rather than naming a stale one" \
    "$(says "$OUT5" "no successful CI run exists at all")" "yes"
check "a brand new commit with no run yet is inside the grace period" \
    "$(status_of "" "2026-09-09T11:30:00Z" 24 none)" "0"

# ---------------------------------------------------------------------------
# 5. CANNOT MEASURE IS NOT A PASS, and each cause has its own sentence, because
#    a missing input and a stopped CI need opposite work (L11, L98).
# ---------------------------------------------------------------------------
OUT6="$(OVATION_CI_NOW="" OVATION_CI_LAST_SUCCESS="x" OVATION_CI_LAST_COMMIT="y" "./$TARGET" 2>&1)"
check "no current time cannot be measured" \
    "$(OVATION_CI_NOW="" OVATION_CI_LAST_COMMIT="y" "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "and it says so rather than passing" "$(says "$OUT6" "CANNOT MEASURE")" "yes"

check "no commit date cannot be measured either" \
    "$(OVATION_CI_NOW="$NOW" OVATION_CI_LAST_COMMIT="" "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "2"

OUT7="$(judge "2026-09-01T10:00:00Z" "not a date")"
check "a commit date that will not parse cannot be measured" \
    "$(status_of "2026-09-01T10:00:00Z" "not a date")" "2"
check "and it quotes the value it could not read" "$(says "$OUT7" "not a date")" "yes"
check "a successful run date that will not parse cannot be measured" \
    "$(status_of "gibberish" "2026-09-05T10:00:00Z")" "2"

# A date that will not parse must never be treated as very old, which is the
# shape that turns an unreadable value into a confident alarm (L50).
check "an unparseable run date does not become a BLOCKED verdict" \
    "$([ "$(status_of "gibberish" "2026-09-05T10:00:00Z")" = "1" ] && echo blocked || echo not-blocked)" \
    "not-blocked"

# ---------------------------------------------------------------------------
# 6. THE OFFSETS ARE READ, not assumed to be Z. A workflow reading a local time
#    from git would otherwise be judged as if it were UTC and land hours out.
# ---------------------------------------------------------------------------
check "an offset date is understood rather than refused" \
    "$(status_of "2026-09-09T07:00:00-04:00" "2026-09-09T06:00:00-04:00")" "0"

# ---------------------------------------------------------------------------
# 7. A RED BUILD IS NOT A LATE BUILD (ovation#212). Measured 2026-09-11: this
#    reported PASS on two commits while CI was failing on both, because inside
#    the grace period "no successful run yet" is all it could see, and that is
#    equally true of a run still in flight. A run in flight needs nothing; a run
#    that has FAILED has already answered, so the grace protects nothing (L11).
#
#    Every case here stages the same unjudged commit two hours old, well inside
#    the grace, so the only thing that differs between them is the newest run.
# ---------------------------------------------------------------------------
LAST_OK="2026-09-08T10:00:00Z"
YOUNG="2026-09-09T10:00:00Z"

# THE POSITIVE FIRST, in the same fixture the refusals use, or a case asserting
# the grace still applies is satisfied by a fixture where FAILING could not fire
# (L159).
OUT_RED="$(judge "$LAST_OK" "$YOUNG" 24 failure)"
check "a newest run that FAILED is reported at once, inside the grace period" \
    "$(status_of "$LAST_OK" "$YOUNG" 24 failure)" "3"
check "and it says FAILING, a fourth outcome, not BLOCKED" \
    "$(says "$OUT_RED" "FAILING")" "yes"
check "and it does not borrow BLOCKED's sentence about CI having stopped" \
    "$(says "$OUT_RED" "may have stopped triggering")" "no"
check "and it names the conclusion it read, so the log says what was measured" \
    "$(says "$OUT_RED" "failure")" "yes"

# A run can end red without the word failure. A timeout and a run that could not
# start have answered as surely as a failed test.
check "a newest run that timed out is FAILING too" \
    "$(status_of "$LAST_OK" "$YOUNG" 24 timed_out)" "3"
check "and so is one that could not start" \
    "$(status_of "$LAST_OK" "$YOUNG" 24 startup_failure)" "3"

# THE GRACE IS KEPT FOR WHAT IT WAS BUILT FOR: a run that has not answered yet.
check "a newest run still in progress keeps the grace period" \
    "$(status_of "$LAST_OK" "$YOUNG" 24 in_progress)" "0"
check "and so does one still queued" \
    "$(status_of "$LAST_OK" "$YOUNG" 24 queued)" "0"
# A CANCELLED RUN ANSWERED NOTHING. On main it is almost always a run a newer
# push superseded, and calling it red would raise an alarm about ordinary use
# (L36).
check "a newest run that was cancelled is not a failure" \
    "$(status_of "$LAST_OK" "$YOUNG" 24 cancelled)" "0"

# AND A FAILURE STILL OUTRANKS AGE. Past the grace a failing run is FAILING, not
# BLOCKED, because the second would send somebody looking for a workflow that has
# stopped triggering when it is triggering fine and going red.
check "a failing newest run past the grace period is still FAILING, not BLOCKED" \
    "$(status_of "2026-09-01T10:00:00Z" "2026-09-05T10:00:00Z" 24 failure)" "3"

# THE INPUT IS REQUIRED, NOT DEFAULTED. An unset newest run silently switching
# the new outcome off would put this back exactly where ovation#212 found it,
# with a green verdict over a red build (L168, L98).
OUT_NONE="$(OVATION_CI_NOW="$NOW" OVATION_CI_LAST_SUCCESS="$LAST_OK" \
    OVATION_CI_LAST_COMMIT="$YOUNG" "./$TARGET" 2>&1)"
check "no newest run given cannot be measured" \
    "$(OVATION_CI_NOW="$NOW" OVATION_CI_LAST_SUCCESS="$LAST_OK" \
        OVATION_CI_LAST_COMMIT="$YOUNG" "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "and it names the newest run as the missing input" \
    "$(says "$OUT_NONE" "newest CI run")" "yes"

# A STATE NOBODY LISTED IS NOT A PASS. Validity by a list of failures would admit
# every value GitHub adds tomorrow as healthy (L257).
OUT_ODD="$(judge "$LAST_OK" "$YOUNG" 24 something_new)"
check "a newest run state this does not know cannot be measured" \
    "$(status_of "$LAST_OK" "$YOUNG" 24 something_new)" "2"
check "and it quotes the state it did not know" \
    "$(says "$OUT_ODD" "something_new")" "yes"

# ---------------------------------------------------------------------------
# 8. THE WORKFLOW FEEDS AND ACTS ON IT. A judgement nothing gives the input to,
#    or whose fourth verdict nothing reads, is the ovation#212 state with more
#    code in it (L3).
# ---------------------------------------------------------------------------
LIVENESS_WF=".github/workflows/ci-liveness.yml"
check "the workflow hands the judge the newest run" \
    "$(grep -c 'OVATION_CI_NEWEST_RUN=' "$LIVENESS_WF")" "1"
check "and acts on a FAILING verdict" \
    "$(grep -c "steps.judge.outputs.status == '3'" "$LIVENESS_WF")" "1"
# IMMEDIATELY MEANS WHEN CI FINISHES. Run only on a schedule and on the push that
# starts CI, the newest run is always still in flight when this looks, and a red
# build would wait for the next day's run to be seen at all.
check "and it runs when a CI run on main completes, not only on a schedule" \
    "$(grep -cE '^  workflow_run:' "$LIVENESS_WF")" "1"


# ---------------------------------------------------------------------------
# 7. THE WATCHDOG MUST NOT READ ITS OWN RUNS (L71). This workflow is called
#    "CI liveness" and the one it watches is called "CI", so a lookup by DISPLAY
#    name is one rename away from watching itself, and a watchdog judged by the
#    instrument it applies to the work marks itself unhealthy with its own
#    correct alarm and can never clear it. The file name cannot become ambiguous.
#
#    Asserted on the workflow file because that is where the query lives, and the
#    query is the whole of the coupling.
WORKFLOW=".github/workflows/ci-liveness.yml"
check "the liveness workflow exists to be read" \
    "$([ -f "$WORKFLOW" ] && echo yes || echo no)" "yes"
# EVERY RUN LOOKUP, not a count of one. ovation#212 added a second query, for the
# newest run's state, and a count pinned at one would have refused the change
# that made the watched workflow's name matter twice (L63). What is protected is
# that no lookup of runs names the workflow any other way.
check "and every lookup of its runs asks for the watched workflow by FILE name" \
    "$([ "$(grep -c -- 'gh run list' "$WORKFLOW")" -ge 1 ] \
        && [ "$(grep -c -- 'gh run list' "$WORKFLOW")" = "$(grep -c -- 'gh run list --workflow ci.yml' "$WORKFLOW")" ] \
        && echo by-file || echo not-by-file)" "by-file"
check "and never by display name, which two workflows can share a prefix of" \
    "$(grep -c -- '--workflow CI' "$WORKFLOW")" "0"

harness_end
