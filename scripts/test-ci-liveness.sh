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
harness_begin "ci liveness tests" 21

TARGET="scripts/check-ci-liveness.sh"
require_target "$TARGET"

NOW="2026-09-09T12:00:00Z"

# judge <last-success> <last-commit> [grace]
judge() {
    OVATION_CI_NOW="$NOW" \
    OVATION_CI_LAST_SUCCESS="$1" \
    OVATION_CI_LAST_COMMIT="$2" \
    OVATION_CI_GRACE_HOURS="${3:-24}" \
        "./$TARGET" 2>&1
}
status_of() { judge "$@" >/dev/null 2>&1; printf '%s' "$?"; }
says() { if printf '%s' "$1" | grep -qiF "$2"; then echo yes; else echo no; fi; }

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
OUT5="$(judge "" "2026-09-01T10:00:00Z")"
check "commits with no successful run ever is BLOCKED" \
    "$(status_of "" "2026-09-01T10:00:00Z")" "1"
check "and it says that none exists rather than naming a stale one" \
    "$(says "$OUT5" "no successful CI run exists at all")" "yes"
check "a brand new commit with no run yet is inside the grace period" \
    "$(status_of "" "2026-09-09T11:30:00Z")" "0"

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
check "and it asks for the watched workflow by FILE name" \
    "$(grep -c -- '--workflow ci.yml' "$WORKFLOW")" "1"
check "and never by display name, which two workflows can share a prefix of" \
    "$(grep -c -- '--workflow CI' "$WORKFLOW")" "0"

harness_end
