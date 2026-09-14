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
harness_begin "plan claim tests" 49

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
    # $1 estate, then arguments. EVERY SEAM IS SET, the record and the live
    # export included, so no case can fall through to the repository's own PRD
    # or to the export on this Mac (L284, L2).
    OVATION_SIBLING_ROOT="$1" OVATION_PLAN="$1/plan.md" \
        OVATION_SIBLING_INSTALL_CHECK="$1/installs.sh" \
        OVATION_BOOKING_EXPORT="$1/export.json" \
        OVATION_EXPORT_RECORDS="$1/record.md" \
        OVATION_LIVE_EXPORT="$1/live.json" \
        python3 "$TARGET" "${@:2}" 2>&1
}
status_on() { run_on "$@" >/dev/null 2>&1; printf '%s' "$?"; }

# Every estate gets an install check, an export and a record that agree, so a
# case is about the one thing it changes.
furnish() {
    printf '#!/bin/bash\necho "PASS: both siblings are as the plan says"\n' > "$1/installs.sh"
    printf '{"version": 3, "bookings": [1,2,3]}\n' > "$1/export.json"
    printf '{"version": 3, "bookings": [], "clients": []}\n' > "$1/live.json"
    printf 'A record that says nothing about what any export holds.\n' > "$1/record.md"
}

# Downbeat's contract, in the place the real one sits, declaring the fields
# given. Line 3 is the client shape, so a field's line is known by construction.
contract() {
    # $1 estate, $2 the backticked fields the client shape declares
    mkdir -p "$1/Downbeat/Downbeat/Integration/OvertureExport"
    printf '# A contract\n\nOvertureClient: %s.\n' "$2" \
        > "$1/Downbeat/Downbeat/Integration/OvertureExport/CONTRACT.md"
}
record() { printf '%s\n' "$2" > "$1/record.md"; }

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
# THE FIELDS THE RECORD SAYS THE EXPORT CARRIES, AND LACKS (ovation#215). The
# PRD said the Downbeat export has no field for a client's tax status, while
# Downbeat's own contract declared `isTaxExempt` and the export carried it on 6
# of 31 clients. A claim that something is ABSENT never fails on its own, so
# nothing revisited it (L460, L182). These fixtures invent every field and name.
# ---------------------------------------------------------------------------
FIELDS="$(estate fields)"; furnish "$FIELDS"
plan "$FIELDS" 'A plan that states nothing checkable of its own.
It names `deadbeef` so the run has something to compare besides the record.' >/dev/null
contract "$FIELDS" '`id`, `displayName`, `isTaxExempt` (bool), `notes`'

# THE CASE THIS EXISTS FOR: the record says a field is absent, the contract
# declares it.
record "$FIELDS" 'Nobody can re-derive it, because the Downbeat export has no field for a tax status.'
check "a record saying the export lacks what the contract declares is refused" \
    "$(status_on "$FIELDS")" "1"
check "and it is named DERIVABLE rather than as any other drift" \
    "$(run_on "$FIELDS" | grep -c '^  DERIVABLE')" "1"
check "and the refusal names the field, and the contract line declaring it" \
    "$(run_on "$FIELDS" | grep -c 'DERIVABLE  record.md:1 .*`isTaxExempt`.*CONTRACT.md:3')" "1"

# A SENTENCE WRAPPED OVER LINES IS STILL ONE SENTENCE, which is how the design
# record is written, and the line named is the one the claim starts on.
record "$FIELDS" 'The round could not be judged.
The export cannot say which is true, because it has no field for a
tax status at all.'
check "a claim hard wrapped across lines is read as one sentence" \
    "$(run_on "$FIELDS" | grep -c 'DERIVABLE  record.md:2 ')" "1"

# THE EXPORT IS A SOURCE OF ITS OWN, not only the contract: an optional field
# the contract has not caught up with is still carried.
contract "$FIELDS" '`id`, `displayName`, `notes`'
printf '{"version": 3, "clients": [{"id": "c1", "isTaxExempt": true}]}\n' > "$FIELDS/live.json"
record "$FIELDS" 'The Downbeat export has no field for a tax status.'
check "a field only the live export carries still makes the claim derivable" \
    "$(run_on "$FIELDS" | grep -c 'DERIVABLE .*`isTaxExempt`.*the live export')" "1"
printf '{"version": 3, "bookings": [], "clients": []}\n' > "$FIELDS/live.json"
printf '{"version": 3, "clients": [{"id": "c1", "isTaxExempt": false}]}\n' > "$FIELDS/export.json"
check "and so does one only the custody snapshot carries" \
    "$(run_on "$FIELDS" | grep -c 'DERIVABLE .*`isTaxExempt`.*the custody snapshot')" "1"
printf '{"version": 3, "bookings": [1,2,3]}\n' > "$FIELDS/export.json"

# A CLAIM THAT HOLDS, said positively rather than by silence (L98).
record "$FIELDS" 'The Downbeat export carries nothing about payments, and nothing else holds them.'
check "an absence no source contradicts holds" "$(status_on "$FIELDS")" "0"
check "and is reported as holding rather than passing silently" \
    "$(run_on "$FIELDS" | grep -c '^  FIELDS     record.md:1 ')" "1"

# WHAT IT MUST PRESERVE (L104). Another export's sentence is not a claim about
# Downbeat's, and a word matches whole words of a key, never letters inside one.
contract "$FIELDS" '`id`, `syntaxNote`, `isTaxExempt` (bool)'
record "$FIELDS" 'The FreshBooks export carries no tax amounts at all.'
check "a sentence about the FreshBooks export is not read as one about Downbeat's" \
    "$(status_on "$FIELDS")" "0"
contract "$FIELDS" '`id`, `syntaxNote`'
record "$FIELDS" 'The Downbeat export carries nothing about tax.'
check "and a word never matches letters inside a longer word of a key" \
    "$(status_on "$FIELDS")" "0"
# A COUNT OF CLIENTS IS NOT A CLAIM ABOUT THE FILE. This sentence is PRD 5b's,
# word for word, and it names an export while its subject is the clients.
contract "$FIELDS" '`id`, `isTaxExempt` (bool)'
record "$FIELDS" 'Measured against the live export, 25 of 31 clients carry no tax status, so the other reading would tell most clients.'
check "and a count of clients carrying nothing is not read as the export lacking a field" \
    "$(status_on "$FIELDS")" "0"

# THE RECORD SAYING A FIELD IS THERE, which fails the other way.
contract "$FIELDS" '`id`, `isTaxExempt` (bool)'
record "$FIELDS" 'The Downbeat export carries `isTaxExempt` on the clients that have one.'
check "a field the record says is carried, and the contract declares, holds" \
    "$(status_on "$FIELDS")" "0"
contract "$FIELDS" '`id`, `notes`'
check "and one no source declares or carries is refused" "$(status_on "$FIELDS")" "1"
check "and named UNCARRIED" "$(run_on "$FIELDS" | grep -c '^  UNCARRIED')" "1"

# A SUBJECT THAT NAMES NO FIELD, which is how the original false sentence was
# written ("no field for either"). Reported so it is visible, never refused.
record "$FIELDS" 'The Downbeat export has no field for either.'
check "a claim whose subject names no field is not refused" "$(status_on "$FIELDS")" "0"
check "and is reported UNPARSED rather than passing as checked" \
    "$(run_on "$FIELDS" | grep -c '^  UNPARSED')" "1"

# NO SOURCE AT ALL IS NOT A HOLD. With the contract gone and both exports
# unreadable, "nothing carries it" was measured against nothing (L98, L530).
rm -f "$FIELDS/Downbeat/Downbeat/Integration/OvertureExport/CONTRACT.md"
printf 'not json\n' > "$FIELDS/live.json"
printf 'not json\n' > "$FIELDS/export.json"
record "$FIELDS" 'The Downbeat export has no field for a tax status.'
check "a field claim with no readable source is CANNOT MEASURE" \
    "$(run_on "$FIELDS" | grep -c '^  FIELDS     CANNOT MEASURE')" "1"
check "and never reported as holding" \
    "$(run_on "$FIELDS" | grep -c '^  FIELDS     record.md')" "0"

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
