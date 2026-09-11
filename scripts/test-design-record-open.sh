#!/bin/bash
# The suite for scripts/check-design-record-open.sh.
#
# ovation#172. A guard is only real once it has been seen to fail (L1), and this
# one asks an external system, so the case that decides whether it is worth
# anything is the LOOKUP THAT FAILED: no network, no credentials and a deleted
# issue all land there, and every one of them would otherwise read as the
# sentence being true.
#
# THE STATE READER IS A SEAM, so nothing here reaches the real tracker. A test
# that did would be asserting about the backlog rather than about this check,
# and would go red the day somebody closes an issue (L2, L291).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design record status tests" 29

TARGET="scripts/check-design-record-open.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A reader that answers from a table written into the fixture, so a case names
# the states it is about rather than the check finding them somewhere.
STATES="$WORK/states"
cat > "$WORK/reader.sh" <<'SH'
#!/bin/bash
  line="$(grep "^$1 " "$STATES" 2>/dev/null)" || exit 1
  [ -n "$line" ] || exit 1
  printf '%s' "${line#* }"
SH
chmod +x "$WORK/reader.sh"

run_on() {
    OVATION_DESIGN_ROOT="$1" STATES="$STATES" \
        OVATION_ISSUE_STATE_COMMAND="bash $WORK/reader.sh {n}" \
        python3 "$TARGET" 2>&1
}
status_on() {
    run_on "$1" >/dev/null 2>&1
    printf '%s' "$?"
}

record() {
    # $1 destination directory, $2 the body of the status section
    mkdir -p "$1"
    cat > "$1/README.md" <<MD
# The design record

Decisions live up here and nothing reads them.

## What is still open

$2

## The invoice PDF

Also not read, because it is a different heading at the same level.
Mentions ovation#999 which must never be looked up.
MD
}

# ---------------------------------------------------------------------------
# The healthy record.
# ---------------------------------------------------------------------------
OPEN="$(mkdir -p "$WORK/open" && printf '%s' "$WORK/open")"
record "$OPEN" 'The receptor queue is `ovation#100`, and `ovation#95` is where the times live.'
printf '95 OPEN\n100 OPEN\n999 CLOSED\n' > "$STATES"
check "a record naming only open issues passes" "$(status_on "$OPEN")" "0"
check "and it says how many it asked about" \
    "$(run_on "$OPEN" | grep -c 'every one of the 2 issue')" "1"
check "and an issue outside the section is never looked up" \
    "$(run_on "$OPEN" | grep -c 'ovation#999')" "0"

# ---------------------------------------------------------------------------
# THE CASE THIS EXISTS FOR.
# ---------------------------------------------------------------------------
STALE="$(mkdir -p "$WORK/stale" && printf '%s' "$WORK/stale")"
record "$STALE" 'The invoice screen (`ovation#111`) is not designed yet. `ovation#95` is open.'
printf '95 OPEN\n111 CLOSED\n' > "$STATES"
check "a record calling a closed issue still open is refused" "$(status_on "$STALE")" "1"
check "and the closed one is named" \
    "$(run_on "$STALE" | grep -c 'CLOSED  ovation#111')" "1"
check "with the line it is on" \
    "$(run_on "$STALE" | sed -n 's/.*CLOSED  ovation#111, named on line \([0-9]*\).*/\1/p')" "7"
check "and the open one is not accused" \
    "$(run_on "$STALE" | grep -c 'CLOSED  ovation#95')" "0"
check "and the verdict counts both" \
    "$(run_on "$STALE" | grep -c 'REFUSED: 1 of 2 issue')" "1"

# ---------------------------------------------------------------------------
# A FAILED LOOKUP IS NEVER READ AS OPEN. This is the case that decides whether
# the check is worth having at all.
# ---------------------------------------------------------------------------
printf '95 OPEN\n' > "$STATES"
record "$STALE" '`ovation#95` is open and `ovation#111` cannot be looked up.'
check "an issue that could not be looked up is not a pass" "$(status_on "$STALE")" "2"
check "and it is named as unknown rather than as open" \
    "$(run_on "$STALE" | grep -c 'UNKNOWN ovation#111')" "1"
check "and the message says a failed lookup and an open issue are not the same" \
    "$(run_on "$STALE" | grep -c 'must not read the same')" "1"

printf '95 OPEN\n111 SOMETHING ELSE\n' > "$STATES"
check "an answer that is neither OPEN nor CLOSED is unknown, never open" \
    "$(run_on "$STALE" | grep -c 'UNKNOWN ovation#111')" "1"

printf '95 OPEN\n111 CLOSED\n' > "$STATES"
check "a closed issue still refuses even when another cannot be read" \
    "$(status_on "$STALE")" "1"

# ---------------------------------------------------------------------------
# NOTHING TO MEASURE IS NOT A PASS, and each way of having nothing is its own
# outcome (L98, L11).
# ---------------------------------------------------------------------------
check "no README at all cannot measure" "$(status_on "$WORK/nowhere")" "2"
check "and says which cause it hit" \
    "$(run_on "$WORK/nowhere" | grep -c 'no .*README.md, so nothing was read')" "1"

RENAMED="$(mkdir -p "$WORK/renamed" && printf '%s' "$WORK/renamed")"
printf '# The design record\n\n## Outstanding\n\n`ovation#95`\n' > "$RENAMED/README.md"
check "a renamed heading cannot measure" "$(status_on "$RENAMED")" "2"
check "and is told apart from a section with nothing in it" \
    "$(run_on "$RENAMED" | grep -c 'has no .* heading')" "1"

EMPTYSEC="$(mkdir -p "$WORK/emptysec" && printf '%s' "$WORK/emptysec")"
record "$EMPTYSEC" 'Nothing is outstanding today.'
check "a section naming no issue cannot measure" "$(status_on "$EMPTYSEC")" "2"
check "and says so in its own words" \
    "$(run_on "$EMPTYSEC" | grep -c 'names no issue')" "1"

# ---------------------------------------------------------------------------
# The committed record, which is the run CI makes. It reaches the real tracker,
# so it is only asserted to be one of the answers this check can give rather
# than a particular one: an issue closed while this suite runs is a finding
# about the record, not about the suite.
# ---------------------------------------------------------------------------
python3 "$TARGET" >/dev/null 2>&1
REAL=$?
KNOWN="no, it exited $REAL"
if [ "$REAL" = "0" ] || [ "$REAL" = "1" ] || [ "$REAL" = "2" ]; then KNOWN="yes"; fi
check "the committed record answers with one of this check's own outcomes" "$KNOWN" "yes"

# ---------------------------------------------------------------------------
# EACH DESIGN FILE'S OWN LIST OF WHAT IT DOES NOT ANSWER (ovation#200). The
# record's section above was checked from ovation#172 onwards; the same kind of
# list inside each design file was checked by nothing, and one of them was false
# on the day this was filed. They carried three different headings, so nothing
# could even find them all; they now carry one (L118).
#
# A DESIGN FILE THAT CARRIES NO SUCH LIST IS NAMED, NOT PASSED OVER. invoice.html
# keeps its record in the README rather than in itself, so having none is
# correct there, and a file that LOST its list would otherwise look the same.
# ---------------------------------------------------------------------------
design_file() {
    # $1 destination directory, $2 file name, $3 the body of the open list
    mkdir -p "$1"
    cat > "$1/$2" <<HTML
<meta charset="utf-8">
<h2>The decisions</h2>
<p>Settled, and naming ovation#998 which must never be looked up.</p>
<h2>What is deliberately still open</h2>
$3
HTML
}

FILEOPEN="$WORK/fileopen"
record "$FILEOPEN" 'The record itself names `ovation#100`.'
design_file "$FILEOPEN" "invoice-list.html" '<p>Where the times live, ovation#95.</p>'
printf '95 OPEN\n100 OPEN\n998 CLOSED\n' > "$STATES"
check "a design file whose own open list names an open issue passes" \
    "$(status_on "$FILEOPEN")" "0"
# The ISSUE line, not merely the file name: the file is also named on its own
# "carries a list" line, which says nothing about whether the list was read.
check "and the file's list is actually read, not just the record's" \
    "$(run_on "$FILEOPEN" | grep -cE 'OPEN +ovation#95, named on line [0-9]+ of invoice-list.html')" "1"

# THE FAULT: a file's own list naming an issue that has since closed.
FILECLOSED="$WORK/fileclosed"
record "$FILECLOSED" 'The record itself names `ovation#100`.'
design_file "$FILECLOSED" "clients.html" '<p>The pane scrolls sideways, ovation#110.</p>'
printf '100 OPEN\n110 CLOSED\n998 CLOSED\n' > "$STATES"
check "a design file calling a closed issue still open is refused" \
    "$(status_on "$FILECLOSED")" "1"
check "and the refusal names the file it is in" \
    "$(run_on "$FILECLOSED" | grep -cE 'CLOSED +ovation#110, named on line [0-9]+ of clients.html')" "1"

# AND NOTHING OUTSIDE THE LIST IS LOOKED UP, or the check would report on every
# issue the file happens to mention, most of which are settled by design.
check "an issue named outside the list is never asked about" \
    "$(run_on "$FILECLOSED" | grep -c 'ovation#998')" "0"

# THE LIST ENDS AT THE SCRIPT, and this case is why. These files put the open
# list LAST in their prose with no heading after it, so a section ending only at
# the next heading runs to the end of the file and swallows every issue named in
# a script comment. The first run of this check accused nine citations and every
# one of them was a comment correctly recording a settled decision (L11, L375).
SCRIPTED="$WORK/scripted"
record "$SCRIPTED" 'The record itself names `ovation#100`.'
mkdir -p "$SCRIPTED"
cat > "$SCRIPTED/invoice-list.html" <<'HTML'
<meta charset="utf-8">
<h2>What is deliberately still open</h2>
<p>Where the times live, ovation#95.</p>
<script>
/* Settled in ovation#997, which is closed and must never be looked up. */
var x = 1;
</script>
HTML
printf '95 OPEN\n100 OPEN\n997 CLOSED\n' > "$STATES"
check "a settled issue named in a script comment is not read as still open" \
    "$(status_on "$SCRIPTED")" "0"
check "and that issue is never asked about at all" \
    "$(run_on "$SCRIPTED" | grep -c 'ovation#997')" "0"

# A FILE WITH NO LIST AT ALL IS COUNTED AND NAMED.
NOLIST="$WORK/nolist"
record "$NOLIST" 'The record itself names `ovation#100`.'
mkdir -p "$NOLIST"
printf '<meta charset="utf-8">\n<h1>The invoice screen</h1>\n' > "$NOLIST/invoice.html"
printf '100 OPEN\n' > "$STATES"
check "a design file carrying no open list does not refuse" "$(status_on "$NOLIST")" "0"
check "and it is named, so a list that disappeared is visible" \
    "$(run_on "$NOLIST" | grep -c 'invoice.html carries no')" "1"

harness_end
