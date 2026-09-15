#!/bin/bash
# The suite for scripts/check-design-measurements-marked.sh.
#
# ovation#201. The check REPORTS the unmarked count and REFUSES only a marking
# that is wrong, so the two halves need testing in opposite directions and the
# easy mistake is to test only one. A suite that proved the refusals and never
# proved the reporting would leave a check free to refuse an unmarked number
# tomorrow, which is the change that makes it unlandable; a suite that proved the
# reporting and never proved a refusal would leave a guard that has never been
# seen to fail (L1).
#
# EVERYTHING IS A FIXTURE. The real record is not read here: a suite asserting
# about docs/design/README.md would be asserting about the backlog of unmarked
# numbers rather than about this check, and would go red the day somebody marks
# one (L2, L291). Both the record and the scripts directory the markings point
# into are injected.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design measurement marking tests" 36

TARGET="scripts/check-design-measurements-marked.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A scripts directory of its own, so a case names the scripts it is about rather
# than depending on what happens to be committed beside this suite.
SCRIPTS="$WORK/scripts"
mkdir -p "$SCRIPTS/lib"
printf '#!/bin/sh\nexit 0\n' > "$SCRIPTS/check-real.sh"
printf '#!/bin/sh\nexit 0\n' > "$SCRIPTS/check-unlisted.sh"
chmod +x "$SCRIPTS/check-real.sh" "$SCRIPTS/check-unlisted.sh"
printf '# A fixture inventory.\ncheck-real.sh\tgated\tA repo wide guard.\n' \
    > "$SCRIPTS/lib/script-roles.tsv"

run_on() {
    OVATION_DESIGN_ROOT="$1" OVATION_SCRIPTS_ROOT="$SCRIPTS" \
        python3 "$TARGET" 2>&1
}
status_on() {
    run_on "$1" >/dev/null 2>&1
    printf '%s' "$?"
}

record() {
    # $1 destination directory, $2 the body under the heading
    mkdir -p "$1"
    cat > "$1/README.md" <<MD
# The design record

$2
MD
}

# ---------------------------------------------------------------------------
# A WELL FORMED RECORD. Both markings, each pointing at something real.
# ---------------------------------------------------------------------------
GOOD="$WORK/good"
record "$GOOD" 'The five figures keep the edge at 1246px, `asserted by check-real.sh`.

A third statebar cost 40px above the window, `measured 2026-09-10`.'
check "a record whose markings are all well formed passes" "$(status_on "$GOOD")" "0"
check "and it says how many markings it read" \
    "$(run_on "$GOOD" | grep -c 'read 2 marking')" "1"
check "and it names the check the owned number hangs on" \
    "$(run_on "$GOOD" | grep -c 'OWNED   .*check-real.sh')" "1"
check "and it names the day the unowned one was measured" \
    "$(run_on "$GOOD" | grep -c 'MEASURED.*2026-09-10')" "1"
check "and a marked paragraph's numbers are not counted as unmarked" \
    "$(run_on "$GOOD" | grep -c 'UNMARKED: 0 number')" "1"

# ---------------------------------------------------------------------------
# A MARKING NAMING A SCRIPT THAT IS NOT THERE. The first of the three wrong
# markings, and the one a rename produces.
# ---------------------------------------------------------------------------
GONE="$WORK/gone"
record "$GONE" 'The row stays 318px, `asserted by check-vanished.sh`.

And 40px above the window, `measured 2026-09-10`.'
check "a marking naming a script that is not there is refused" "$(status_on "$GONE")" "1"
check "and the missing script is named" \
    "$(run_on "$GONE" | grep -c 'NO SUCH SCRIPT.*check-vanished.sh')" "1"
check "with the line it is on" \
    "$(run_on "$GONE" | sed -n 's/.*NO SUCH SCRIPT *line \([0-9]*\).*/\1/p')" "3"
check "and the well formed marking beside it is not accused" \
    "$(run_on "$GONE" | grep -c 'MEASURED.*2026-09-10')" "1"

# ---------------------------------------------------------------------------
# A MARKING NAMING A SCRIPT NOTHING WATCHES. It is on disk, so the case above
# cannot see it, and a check no inventory lists is one nothing runs (ovation#86).
# ---------------------------------------------------------------------------
UNLISTED="$WORK/unlisted"
record "$UNLISTED" 'The rail keeps its edge at 1246px, `asserted by check-unlisted.sh`.'
check "a marking naming an unregistered script is refused" "$(status_on "$UNLISTED")" "1"
check "and it is named as unregistered rather than as missing" \
    "$(run_on "$UNLISTED" | grep -c 'NOT REGISTERED.*check-unlisted.sh')" "1"
check "and it is not reported as missing from the tree as well" \
    "$(run_on "$UNLISTED" | grep -c 'NO SUCH SCRIPT')" "0"

# ---------------------------------------------------------------------------
# A DATE THAT DOES NOT PARSE. A marking saying a number was measured once says
# nothing at all when nobody can tell which day it means.
# ---------------------------------------------------------------------------
BADDAY="$WORK/badday"
record "$BADDAY" 'Contrast cleared 4.5 to 1 on 72 pairs, `measured 2026-13-45`.'
check "a date that is not a day is refused" "$(status_on "$BADDAY")" "1"
check "and it is named as a date nothing can read" \
    "$(run_on "$BADDAY" | grep -c 'UNREADABLE DATE.*2026-13-45')" "1"

SHORTDAY="$WORK/shortday"
record "$SHORTDAY" 'The window starts 437px down, `measured 2026-9-1`.'
check "a date that is not written out in full is refused too" "$(status_on "$SHORTDAY")" "1"
check "and it is the date outcome rather than a marking nobody recognised" \
    "$(run_on "$SHORTDAY" | grep -c 'UNREADABLE DATE')" "1"

WORDDAY="$WORK/wordday"
record "$WORDDAY" 'It was 318px wide, `measured last Tuesday`.'
check "a marking whose day is not a date at all is refused" "$(status_on "$WORDDAY")" "1"
check "and it says so rather than passing over a marking it could not read" \
    "$(run_on "$WORDDAY" | grep -c 'UNREADABLE DATE')" "1"

# NOTHING OUT OF THE RECORD'S PROSE IS SAID BACK unless it wears the shape of a
# day or of a script name. A marking's inside is prose, and the design record's
# prose is where a client's name would sit (docs/PRIVACY-FLOOR.md, L222).
check "a day that is not digits and hyphens is counted rather than quoted" \
    "$(run_on "$WORDDAY" | grep -c 'measured on 12 character(s) that are not digits')" "1"

NOTANAME="$WORK/notaname"
record "$NOTANAME" 'The edge is at 1246px, `asserted by whatever Dan said on the day`.'
check "a marking naming something that is not a script name is refused without being quoted" \
    "$(run_on "$NOTANAME" | grep -c 'by 28 character(s) that are not a script name')" "1"

# ---------------------------------------------------------------------------
# THE HALF THAT MUST NOT REFUSE. An unmarked number is REPORTED and counted.
#
# This is the case the whole design turns on. A sweep that refused until every
# number in the record carried a marking would be unlandable, and the way it
# would actually be answered is by marking numbers to silence it.
# ---------------------------------------------------------------------------
PLAIN="$WORK/plain"
record "$PLAIN" 'The row stays 318px and the five figures keep the edge at 1246px.

A screen identical at 1440, 1280, 1180 and 1024, and one marking so this is read.

The rail, `asserted by check-real.sh`.'
check "a record full of unmarked numbers still passes" "$(status_on "$PLAIN")" "0"
check "and the unmarked ones are counted rather than refused" \
    "$(run_on "$PLAIN" | grep -c 'UNMARKED: 6 number')" "1"
check "and the paragraphs holding them are named so the gap can be found" \
    "$(run_on "$PLAIN" | grep -c 'unmarked  line 3')" "1"
check "and nothing in it is reported as a wrong marking" \
    "$(run_on "$PLAIN" | grep -cE 'NO SUCH SCRIPT|NOT REGISTERED|UNREADABLE DATE')" "0"

# WHAT IS NOT A MEASUREMENT. A citation, a date and a lesson are numbers a reader
# never re-measures, and counting them would bury the real gap in noise.
QUIET="$WORK/quiet"
record "$QUIET" 'Settled 2026-09-10 (ovation#191, PRD 46b), which is L210 again.

The rail, `asserted by check-real.sh`.'
check "citations, dates and lesson numbers are not counted as measurements" \
    "$(run_on "$QUIET" | grep -c 'UNMARKED: 0 number')" "1"
check "and a number inside a code span is not one either" \
    "$(run_on "$QUIET" | grep -c 'NO SUCH SCRIPT')" "0"

# ---------------------------------------------------------------------------
# NOTHING TO MEASURE IS NOT A PASS, and each way of having nothing is its own
# outcome (L98, L11).
# ---------------------------------------------------------------------------
BARE="$WORK/bare"
record "$BARE" 'The row stays 318px and the edge is at 1246px, and nothing says which.'
check "a record carrying no marking at all cannot measure" "$(status_on "$BARE")" "2"
check "and it says the convention reached nothing rather than reporting a pass" \
    "$(run_on "$BARE" | grep -c 'carries no marking')" "1"

check "no README at all cannot measure" "$(status_on "$WORK/nowhere")" "2"
check "and says which cause it hit" \
    "$(run_on "$WORK/nowhere" | grep -c 'so nothing was read')" "1"

MISSINGROLES="$WORK/missing-roles"
record "$MISSINGROLES" 'The rail, `asserted by check-real.sh`.'
check "no inventory to check a named script against cannot measure" \
    "$(OVATION_DESIGN_ROOT="$MISSINGROLES" OVATION_SCRIPTS_ROOT="$WORK/nowhere" \
        python3 "$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "and it says the inventory is what it could not read" \
    "$(OVATION_DESIGN_ROOT="$MISSINGROLES" OVATION_SCRIPTS_ROOT="$WORK/nowhere" \
        python3 "$TARGET" 2>&1 | grep -c 'script-roles.tsv')" "1"

check "used with an argument it does not take, it says so" \
    "$(OVATION_DESIGN_ROOT="$GOOD" OVATION_SCRIPTS_ROOT="$SCRIPTS" \
        python3 "$TARGET" something >/dev/null 2>&1; printf '%s' "$?")" "3"

# ---------------------------------------------------------------------------
# A WRONG MARKING OUTRANKS THE REPORT. The count is still printed, because a
# refusal that swallowed it would hide the gap on exactly the runs somebody is
# already editing the record (L98).
# ---------------------------------------------------------------------------
BOTH="$WORK/both"
record "$BOTH" 'The row stays 318px, `asserted by check-vanished.sh`.

An unmarked 1246px sits here with nothing behind it.'
check "a record with a wrong marking and an unmarked number is refused" \
    "$(status_on "$BOTH")" "1"
check "and the unmarked count is still reported" \
    "$(run_on "$BOTH" | grep -c 'UNMARKED: 1 number')" "1"
check "and the refusal names the wrong marking as the reason" \
    "$(run_on "$BOTH" | grep -c 'REFUSED: 1 marking')" "1"

harness_end
