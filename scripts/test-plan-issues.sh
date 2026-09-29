#!/bin/bash
# The suite for scripts/check-plan-issues.sh.
#
# ovation#180. The fifth thing ovation#16 asked for: every numbered sub-step of
# docs/IMPLEMENTATION-PLAN.md mapped to a filed issue, and every filed issue
# mapped back. Dan decided the rule on 2026-09-29: a sub-step of a phase whose
# milestone is OPEN owes an issue, every issue in that milestone maps back to a
# sub-step, and a phase with no open milestone is not checked until it opens.
#
# EVERY CASE IS A FIXTURE. The plan, the issues and the milestones all come from
# files written here, through the check's seams, so nothing reaches the real
# tracker: a case that did would be asserting about the backlog, and would go red
# the day somebody files an issue (L2, L291). Each refusal the check can give is
# produced here by a case of its own (L151).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "plan issue mapping tests" 44

TARGET="scripts/check-plan-issues.sh"
require_target "$TARGET"
harness_temp_dir WORK

PLAN="$WORK/plan.md"
ISSUES="$WORK/issues.json"
MILESTONES="$WORK/milestones.tsv"

run_it() {
    OVATION_PLAN="$PLAN" \
        OVATION_PLAN_ISSUES_COMMAND="cat $ISSUES" \
        OVATION_PLAN_MILESTONES_COMMAND="cat $MILESTONES" \
        python3 "$TARGET" "$@" 2>&1
}
said() { run_it | grep -c -- "$1"; }

# A plan shaped like the real one: a phase whose sub-steps are headings, a phase
# whose sub-steps are bold leads assigned to milestones by a table, and a phase
# with no numbered sub-steps at all.
cat > "$PLAN" <<'MD'
# A plan

## What decides this plan

Nothing numbered here is a sub-step: 9.9 is a requirement.

## Phase 0, day zero

### 0.1 Make the repo private

## Phase 1, the foundation work

| Foundation issue | Milestone |
| --- | --- |
| 1.1 Store location | `Year end` |
| 1.2 Invoice numbers | `Invoicing` |

**1.1 Store location.** Port it.

**1.2 Invoice numbers.** Allocate them.

## Phase 4, expenses

Milestone: `Expenses`.

### 4.0 First: the measurement

1. `corroborated`, a reader state and not a step.

### 4.1 Thinnest slice

## Phase 6, the queue consumer

Milestone: `Queue`.

### The one-time backfill

## Cross-cutting, throughout

**7.1 Not in a phase.** Never owed.
MD

printf 'open\tYear end\nopen\tInvoicing\nopen\tExpenses\nclosed\tQueue\nopen\tUngrouped\n' > "$MILESTONES"

issue() {
    # number, state, milestone (or empty), body
    python3 -c 'import json,sys
n,state,ms,body=sys.argv[1:5]
print(json.dumps({"number":int(n),"state":state,"title":"An issue",
  "body":body,"milestone":({"title":ms} if ms else None)}))' "$@"
}
issues() {
    { printf '['; local first=1 line
      while IFS= read -r line; do
        [ "$first" = 1 ] || printf ','
        first=0; printf '%s' "$line"
      done; printf ']'; } > "$ISSUES"
}

healthy() {
    {
        issue 51 CLOSED "Year end" "Plan 1.1 says where the store lives."
        issue 37 OPEN "Invoicing" "Plan 1.2, the allocator."
        issue 60 OPEN "Expenses" "The measurement first, plan 4.0, and then the slice."
        issue 61 CLOSED "Expenses" "Phase 4.1 is the thinnest slice."
        issue 90 OPEN "Ungrouped" "Cites nothing, and Ungrouped is no phase's milestone."
        issue 91 OPEN "Queue" "Cites nothing, in a closed phase milestone."
    } | issues
}

# ---------------------------------------------------------------------------
# The healthy tracker.
# ---------------------------------------------------------------------------
healthy
check_exit "every owed sub-step issued and every issue mapped passes" 0 run_it
check "and it says how many sub-steps it judged" \
    "$(said 'OK: 4 sub-step(s) owed an issue and every one has one')" "1"
check "a sub-step whose issue is closed is still issued" \
    "$(said 'ISSUED     plan 4.1 by ovation#61')" "1"
check "a bold lead assigned by the table is a sub-step" \
    "$(said 'ISSUED     plan 1.2 by ovation#37')" "1"
check "a phase whose milestone is closed is named as not checked" \
    "$(said 'NOT OWED   Phase 6: its milestone `Queue` is closed')" "1"
check "a phase with no milestone is named as not checked" \
    "$(said 'NOT OWED   plan 0.1: no milestone')" "1"
check "a numbered list item is not a sub-step" \
    "$(run_it | grep -cE 'plan 4\.0\.1|plan 1\.? ')" "0"
check "a number outside every phase is not a sub-step" \
    "$(said 'plan 7.1')" "0"
check "an issue in a table-only milestone is not asked to map back" \
    "$(said 'ovation#90')" "0"
check "an issue in a closed phase milestone is not asked to map back" \
    "$(said 'ovation#91')" "0"

# ---------------------------------------------------------------------------
# UNISSUED: a sub-step of an open phase milestone that no issue cites.
# ---------------------------------------------------------------------------
{
    issue 51 CLOSED "Year end" "Plan 1.1 says where the store lives."
    issue 37 OPEN "Invoicing" "Plan 1.2, the allocator."
    issue 60 OPEN "Expenses" "The measurement first, plan 4.0."
} | issues
check_exit "a sub-step no issue cites is refused" 1 run_it
check "and it is named with its line in the plan" \
    "$(run_it | grep -cE 'UNISSUED   plan 4\.1 \(line [0-9]+, milestone `Expenses`\)')" "1"
check "and the verdict counts it" \
    "$(said 'REFUSED: 1 sub-step(s) of an open milestone have no issue')" "1"

# A CITATION IS A WHOLE NUMBER. Plan 4.10 is not plan 4.1, and plan 4.1a is not
# either, or one issue would silently cover a sub-step it never mentions.
{
    issue 51 CLOSED "Year end" "Plan 1.1."
    issue 37 OPEN "Invoicing" "Plan 1.2."
    issue 60 OPEN "Expenses" "Plan 4.0, and see plan 4.10 and plan 4.1a."
} | issues
check "a longer number does not cover a shorter one" \
    "$(said 'UNISSUED   plan 4.1 ')" "1"

# A SUB-STEP IN A TABLE MILESTONE IS OWED WHEN THAT MILESTONE IS OPEN.
{
    issue 37 OPEN "Invoicing" "Plan 1.2."
    issue 60 OPEN "Expenses" "Plan 4.0."
    issue 61 OPEN "Expenses" "Plan 4.1."
} | issues
check_exit "a foundation sub-step on an open milestone with no issue is refused" 1 run_it
check "and named with the milestone its table row gives it" \
    "$(said 'UNISSUED   plan 1.1 (line 18, milestone `Year end`)')" "1"

# ---------------------------------------------------------------------------
# UNMAPPED: an OPEN issue in an open phase milestone that cites no sub-step.
# Dan decided on 2026-09-29 that closed issues are history and do not have to
# map back, so each direction has its own case: a closed unmapped issue passes,
# an open one refuses.
# ---------------------------------------------------------------------------
healthy
{ cat "$ISSUES" | python3 -c 'import json,sys
d=json.load(sys.stdin)
d.append({"number":70,"state":"CLOSED","title":"t","body":"Nothing cited.","milestone":{"title":"Expenses"}})
print(json.dumps(d))'; } > "$ISSUES.new" && mv "$ISSUES.new" "$ISSUES"
check_exit "a CLOSED issue citing no sub-step passes, because closed issues are history" 0 run_it
check "and it is not accused" "$(said 'ovation#70')" "0"
check "and the verdict counts only the open issues it asked about" \
    "$(said 'all 1 open issue(s) in 1 open phase milestone(s) map back')" "1"

{ cat "$ISSUES" | python3 -c 'import json,sys
d=json.load(sys.stdin)
d.append({"number":71,"state":"OPEN","title":"t","body":"Phase four, in words only.","milestone":{"title":"Expenses"}})
print(json.dumps(d))'; } > "$ISSUES.new" && mv "$ISSUES.new" "$ISSUES"
check_exit "an OPEN issue in an open phase milestone citing no sub-step is refused" 1 run_it
check "and it is named" \
    "$(said 'UNMAPPED   ovation#71 in `Expenses` cites no plan sub-step')" "1"
check "and the closed one beside it is still not accused" "$(said 'ovation#70')" "0"
check "and the verdict counts only the open one" \
    "$(said 'REFUSED: 1 open issue(s) in an open phase milestone map to no sub-step')" "1"
check "and the mapped ones are not accused" \
    "$(said 'ovation#60 ')" "0"

# A CLOSED STRAY IS HISTORY TOO: only open issues are asked to map back.
healthy
{ cat "$ISSUES" | python3 -c 'import json,sys
d=json.load(sys.stdin)
d.append({"number":74,"state":"CLOSED","title":"t","body":"Plan 4.9 once.","milestone":{"title":"Expenses"}})
print(json.dumps(d))'; } > "$ISSUES.new" && mv "$ISSUES.new" "$ISSUES"
check_exit "a closed issue citing a number the plan lacks passes" 0 run_it

# A CITATION IN THE TITLE COUNTS as much as one in the body.
healthy
{ cat "$ISSUES" | python3 -c 'import json,sys
d=json.load(sys.stdin)
d.append({"number":72,"state":"OPEN","title":"Plan 4.1, the slice again","body":"","milestone":{"title":"Expenses"}})
print(json.dumps(d))'; } > "$ISSUES.new" && mv "$ISSUES.new" "$ISSUES"
check_exit "a citation in the title maps an issue back" 0 run_it

# STRAY: an issue citing only numbers the plan does not have is told apart from
# one citing nothing, because the remedy differs (L11): the plan may have been
# renumbered under it.
healthy
{ cat "$ISSUES" | python3 -c 'import json,sys
d=json.load(sys.stdin)
d.append({"number":73,"state":"OPEN","title":"t","body":"Plan 4.9 says so.","milestone":{"title":"Expenses"}})
print(json.dumps(d))'; } > "$ISSUES.new" && mv "$ISSUES.new" "$ISSUES"
check_exit "an issue citing only a sub-step the plan does not number is refused" 1 run_it
check "and it is told apart from one citing nothing" \
    "$(said 'STRAY      ovation#73 in `Expenses` cites plan 4.9, which the plan does not number')" "1"

# ---------------------------------------------------------------------------
# NO SUCH MILESTONE: the plan names a milestone the tracker does not have, so
# nothing about that phase could be judged. A refusal, because it is a fact about
# the plan: the milestone was renamed under it.
# ---------------------------------------------------------------------------
healthy
printf 'open\tYear end\nopen\tInvoicing\nclosed\tQueue\n' > "$MILESTONES"
check_exit "a plan naming a milestone the tracker lacks is refused" 1 run_it
check "and the milestone is named with where the plan names it" \
    "$(run_it | grep -cE 'NO SUCH MILESTONE `Expenses`, named for Phase 4 on plan line [0-9]+')" "1"
printf 'open\tYear end\nopen\tInvoicing\nopen\tExpenses\nclosed\tQueue\nopen\tUngrouped\n' > "$MILESTONES"

# ---------------------------------------------------------------------------
# NOTHING TO MEASURE IS NOT A PASS, and each way of having nothing is its own
# sentence (L98, L11).
# ---------------------------------------------------------------------------
healthy
no_plan() { OVATION_PLAN="$WORK/nowhere.md" OVATION_PLAN_ISSUES_COMMAND="cat $ISSUES" \
    OVATION_PLAN_MILESTONES_COMMAND="cat $MILESTONES" python3 "$TARGET" 2>&1; }
check_exit "no plan cannot measure" 2 no_plan
check "and says which cause it hit" "$(no_plan | grep -c 'no plan at')" "1"

with_issues() { OVATION_PLAN="$PLAN" OVATION_PLAN_ISSUES_COMMAND="$1" \
    OVATION_PLAN_MILESTONES_COMMAND="cat $MILESTONES" python3 "$TARGET" 2>&1; }
check_exit "an issue list that could not be read cannot measure" 2 with_issues "exit 4"
check "and says so" "$(with_issues "exit 4" | grep -c 'the issues could not be listed')" "1"
check_exit "an issue list that is not JSON cannot measure" 2 with_issues "echo 'HTTP 504'"
check_exit "an empty issue list cannot measure rather than refusing every sub-step" \
    2 with_issues "echo '[]'"

with_milestones() { OVATION_PLAN="$PLAN" OVATION_PLAN_ISSUES_COMMAND="cat $ISSUES" \
    OVATION_PLAN_MILESTONES_COMMAND="$1" python3 "$TARGET" 2>&1; }
check_exit "a milestone list that could not be read cannot measure" 2 with_milestones "exit 4"
check "and says so" "$(with_milestones "exit 4" | grep -c 'the milestones could not be listed')" "1"
check_exit "a milestone list in a shape it cannot read cannot measure" \
    2 with_milestones "echo 'HTTP 504: gateway'"

# A LIST THAT REACHED ITS LIMIT is refused rather than read as complete, because
# the issues past the limit are exactly the ones a coverage check needs (L211).
limited() { OVATION_PLAN="$PLAN" OVATION_PLAN_ISSUES_COMMAND="cat $ISSUES" \
    OVATION_PLAN_MILESTONES_COMMAND="cat $MILESTONES" OVATION_PLAN_ISSUE_LIMIT=3 \
    python3 "$TARGET" 2>&1; }
check_exit "an issue list as long as its limit cannot measure" 2 limited
check "and says the list may be cut short" "$(limited | grep -c 'may have been cut short')" "1"

# A PLAN WHOSE PHASES ALL HAVE CLOSED OR NO MILESTONES compared nothing.
printf 'closed\tYear end\nclosed\tInvoicing\nclosed\tExpenses\nclosed\tQueue\n' > "$MILESTONES"
check_exit "a plan with no open milestone anywhere cannot measure" 2 run_it
check "and says it compared nothing" "$(said 'no sub-step is owed an issue')" "1"

check_exit "an argument it does not take is refused as used wrongly" 3 run_it --strict

harness_end
