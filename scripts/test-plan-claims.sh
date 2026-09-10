#!/bin/bash
# The suite for scripts/check-plan-claims.sh.
#
# ovation#16. The plan is 780 lines built almost entirely on measured facts about
# two other repositories that change daily, and nothing re-checked any of it.
# What has to be right about this checker is its REFUSALS, because a checker
# that reports green having found nothing to check is worse than no checker: the
# green is read as confirmation (L98).
#
# EVERY CASE IS A FIXTURE ESTATE. Nothing here reads the real Downbeat or
# Overture: a test that did would be asserting about their current contents and
# would go red the next time somebody edits either one (L2, L48). The seams that
# make that possible were written with the script rather than retrofitted.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "plan claim tests" 31

TARGET="scripts/check-plan-claims.sh"
require_target "$TARGET"
harness_temp_dir WORK

# An estate: three checkouts, with the files a plan can cite.
estate() {
    local at="$WORK/$1"
    rm -rf "$at"
    mkdir -p "$at/Ovation" "$at/Downbeat/scripts" "$at/Downbeat/Downbeat/App" \
             "$at/Overture/mac/Overture/Domain"
    printf 'one\ntwo\nLOCK_DIR="/tmp/one.lock"\nfour\nfive\n' \
        > "$at/Downbeat/scripts/run-tests.sh"
    printf 'a\nb\nc\nd\ne\nf\nstatic func labelIds(of message: [String: Any]) -> [String]? {\nh\n' \
        > "$at/Overture/mac/Overture/Domain/ReplyDetection.swift"
    printf 'x\ny\nvar contractEmail: String\n' \
        > "$at/Downbeat/Downbeat/App/AppStoreConfiguration.swift"
    printf 'nothing to cite here\n' > "$at/Ovation/README.md"
    printf '%s' "$at"
}

plan() {
    # $1 estate, $2 the plan's body
    printf '%s\n' "$2" > "$1/plan.md"
    printf '%s' "$1/plan.md"
}

run_on() {
    # $1 estate, then arguments
    OVATION_SIBLING_ROOT="$1" OVATION_PLAN="$1/plan.md" \
        OVATION_SIBLING_INSTALL_CHECK="$1/installs.sh" \
        OVATION_BOOKING_EXPORT="$1/export.json" \
        python3 "$TARGET" "${@:2}" 2>&1
}
status_on() { run_on "$@" >/dev/null 2>&1; printf '%s' "$?"; }

# Every estate gets an install check and an export that agree, so a case is
# about the one thing it changes.
furnish() {
    printf '#!/bin/bash\necho "PASS: both siblings are as the plan says"\n' > "$1/installs.sh"
    printf '{"version": 3, "bookings": [1,2,3]}\n' > "$1/export.json"
}

# ---------------------------------------------------------------------------
# A claim that holds.
# ---------------------------------------------------------------------------
GOOD="$(estate good)"; furnish "$GOOD"
plan "$GOOD" '| a claim | `Downbeat/scripts/run-tests.sh:3` | `LOCK_DIR="/tmp/one.lock"` |' >/dev/null
check "a citation whose literal is where the plan says holds" "$(status_on "$GOOD")" "0"
check "and it is reported as held" "$(run_on "$GOOD" | grep -c '^  HELD')" "1"

# ---------------------------------------------------------------------------
# THE CASE THIS EXISTS FOR: the sibling moved and the plan did not.
# ---------------------------------------------------------------------------
plan "$GOOD" '| a claim | `Downbeat/scripts/run-tests.sh:40` | `LOCK_DIR="/tmp/one.lock"` |' >/dev/null
check "a line past the end of the file is refused" "$(status_on "$GOOD")" "1"
check "and named as SHORT rather than as anything else" \
    "$(run_on "$GOOD" | grep -c '^  SHORT')" "1"

plan "$GOOD" '| a claim | `Overture/mac/Overture/Domain/ReplyDetection.swift:2` | `labelIds(of:)` |' >/dev/null
check "a literal that has moved is reported" "$(run_on "$GOOD" | grep -c '^  MOVED')" "1"
check "and it does NOT refuse, because these repositories change daily" \
    "$(status_on "$GOOD")" "0"
check "and the report says where it is now" \
    "$(run_on "$GOOD" | grep -c 'now at line 7')" "1"
check "while --strict refuses on it, for bringing the plan back into step" \
    "$(status_on "$GOOD" --strict)" "1"

# A SWIFT SIGNATURE IS QUOTED IN SHORTHAND, so a literal that is not in the file
# whole is retried as the CALL it names. Without this the function above reported
# as moved while sitting exactly where the plan says.
plan "$GOOD" '| a claim | `Overture/mac/Overture/Domain/ReplyDetection.swift:7` | `labelIds(of:)` |' >/dev/null
check "a signature quoted in shorthand still anchors its own line" \
    "$(run_on "$GOOD" | grep -c '^  HELD')" "1"

# ---------------------------------------------------------------------------
# AN AMBIGUOUS PATH IS REFUSED, never guessed. A checker that picked one would
# report confidently about a file the plan was not talking about (L237, L320).
# ---------------------------------------------------------------------------
AMBIG="$(estate ambig)"; furnish "$AMBIG"
printf 'one\ntwo\nLOCK_DIR="/tmp/other.lock"\n' > "$AMBIG/Ovation/run-tests.sh"
plan "$AMBIG" '| a claim | `run-tests.sh:3` | `LOCK_DIR="/tmp/one.lock"` |' >/dev/null
check "a path that exists in two checkouts is refused" "$(status_on "$AMBIG")" "1"
check "and the refusal names them and says what the plan must do" \
    "$(run_on "$AMBIG" | grep -c 'must write a path that names one')" "1"
plan "$AMBIG" '| a claim | `Downbeat/scripts/run-tests.sh:3` | `LOCK_DIR="/tmp/one.lock"` |' >/dev/null
check "and a path that names its checkout resolves there and nowhere else" \
    "$(status_on "$AMBIG")" "0"

# ---------------------------------------------------------------------------
# A FILE THAT IS GONE.
# ---------------------------------------------------------------------------
plan "$GOOD" '| a claim | `Downbeat/scripts/vanished.sh:3` | `something` |' >/dev/null
check "a file no checkout has is refused" "$(status_on "$GOOD")" "1"
check "and named ABSENT" "$(run_on "$GOOD" | grep -c '^  ABSENT')" "1"

# ---------------------------------------------------------------------------
# A ROW THAT QUOTES WHAT IS ABSENT is the plan being ACCURATE, and calling it a
# failure would refuse the plan for being right. Counted, never refused.
# ---------------------------------------------------------------------------
plan "$GOOD" '| a claim | `Downbeat/scripts/run-tests.sh:3` | writes no `dirtyFiles` and no `signingIdentity` |' >/dev/null
check "a row quoting only what is NOT in the file does not refuse" "$(status_on "$GOOD")" "0"
check "and is counted as unanchored rather than passing silently" \
    "$(run_on "$GOOD" | grep -c '^  UNANCHORED')" "1"

# ---------------------------------------------------------------------------
# THE COMMITS THE PLAN NAMES.
# ---------------------------------------------------------------------------
COMMITS="$(estate commits)"; furnish "$COMMITS"
( cd "$COMMITS/Downbeat" && git init -q -b main . \
    && git -c user.email=t@e -c user.name=t commit -q --allow-empty -m one \
    && git -c user.email=t@e -c user.name=t commit -q --allow-empty -m two ) >/dev/null 2>&1
ONMAIN="$(git -C "$COMMITS/Downbeat" rev-parse --short=8 HEAD)"
( cd "$COMMITS/Downbeat" && git checkout -q -b side \
    && git -c user.email=t@e -c user.name=t commit -q --allow-empty -m three \
    && git checkout -q main ) >/dev/null 2>&1
OFFMAIN="$(git -C "$COMMITS/Downbeat" rev-parse --short=8 side)"
plan "$COMMITS" "The plan names \`$ONMAIN\` as landed." >/dev/null
check "a commit on the sibling's main holds" "$(status_on "$COMMITS")" "0"
check "and is reported as an ancestor" "$(run_on "$COMMITS" | grep -c '^  ANCESTOR')" "1"
plan "$COMMITS" "The plan names \`$OFFMAIN\` as landed." >/dev/null
check "a commit that is NOT on main is refused" "$(status_on "$COMMITS")" "1"
check "and named UNMERGED" "$(run_on "$COMMITS" | grep -c '^  UNMERGED')" "1"
plan "$COMMITS" 'The plan names `deadbeef` as a branch head at a moment in time.' >/dev/null
check "a commit no checkout knows is reported, not refused" "$(status_on "$COMMITS")" "0"
check "and named UNPLACED, because the plan records one such on purpose" \
    "$(run_on "$COMMITS" | grep -c '^  UNPLACED')" "1"

# ---------------------------------------------------------------------------
# WHAT IS INSTALLED, AND THE EXPORT. Both were the expensive claims: acting on
# them when they had drifted would have meant reinstalling two working apps.
# ---------------------------------------------------------------------------
INST="$(estate inst)"; furnish "$INST"
plan "$INST" 'The assertion is: version 3, 19 bookings, on snapshot 2.' >/dev/null
printf '{"version": 3, "bookings": [%s]}\n' "$(seq 1 19 | paste -sd, -)" > "$INST/export.json"
check "an export that is what the plan asserts holds" "$(status_on "$INST")" "0"
printf '{"version": 2, "bookings": [1,2]}\n' > "$INST/export.json"
check "an export that is not is refused" "$(status_on "$INST")" "1"
check "and the report gives both figures rather than only saying they differ" \
    "$(run_on "$INST" | grep -c 'the plan states version 3 and 19 booking(s); the export is version 2 with 2')" "1"

printf 'not json at all\n' > "$INST/export.json"
check "an export that cannot be read is CANNOT MEASURE, never drift" \
    "$(run_on "$INST" | grep -c 'EXPORT     CANNOT MEASURE: the custody export could not be read')" "1"
printf '{"version": 3, "bookings": [%s]}\n' "$(seq 1 19 | paste -sd, -)" > "$INST/export.json"

printf '#!/bin/bash\necho "BLOCKED: the installed Overture lacks the gate fix"\nexit 1\n' > "$INST/installs.sh"
printf '{"version": 3, "bookings": [%s]}\n' "$(seq 1 19 | paste -sd, -)" > "$INST/export.json"
check "an install check that refuses is carried through rather than swallowed" \
    "$(status_on "$INST")" "1"
check "and its own verdict line is what gets printed, not its last line" \
    "$(run_on "$INST" | grep -c 'INSTALLS   BLOCKED:')" "1"

# ---------------------------------------------------------------------------
# NOTHING TO MEASURE IS NOT A PASS, and each way of having nothing is its own
# outcome (L98, L11).
# ---------------------------------------------------------------------------
BARE="$WORK/bare"; mkdir -p "$BARE"
check "an estate with no siblings cannot measure" \
    "$(OVATION_SIBLING_ROOT="$BARE" OVATION_PLAN="$GOOD/plan.md" python3 "$TARGET" \
        >/dev/null 2>&1; printf '%s' "$?")" "3"
NOCITE="$(estate nocite)"; furnish "$NOCITE"
plan "$NOCITE" 'A plan that cites nothing at all.' >/dev/null
check "a plan citing no file cannot measure" "$(status_on "$NOCITE")" "2"
check "and says that is different from every claim agreeing" \
    "$(run_on "$NOCITE" | grep -c 'must not report the same thing')" "1"

harness_end
