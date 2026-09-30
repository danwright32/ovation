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
harness_begin "design record status tests" 61

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

# AND THE LABELLED LIST FROM A FILE THE SAME WAY (ovation#195): which open issues
# carry the design-decision label, one number per line, so a case says which
# decisions are waiting on Dan rather than the tracker deciding it.
DECISIONS="$WORK/decisions"
printf '95\n' > "$DECISIONS"

run_on() {
    OVATION_DESIGN_ROOT="$1" STATES="$STATES" \
        OVATION_ISSUE_STATE_COMMAND="bash $WORK/reader.sh {n}" \
        OVATION_DECISION_LIST_COMMAND="cat $DECISIONS" \
        python3 "$TARGET" 2>&1
}
status_on() {
    run_on "$1"
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
check_exit "a record naming only open issues passes" 0 status_on "$OPEN"
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
check_exit "a record calling a closed issue still open is refused" 1 status_on "$STALE"
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
check_exit "an issue that could not be looked up is not a pass" 2 status_on "$STALE"
check "and it is named as unknown rather than as open" \
    "$(run_on "$STALE" | grep -c 'UNKNOWN ovation#111')" "1"
check "and the message says a failed lookup and an open issue are not the same" \
    "$(run_on "$STALE" | grep -c 'must not read the same')" "1"

printf '95 OPEN\n111 SOMETHING ELSE\n' > "$STATES"
check "an answer that is neither OPEN nor CLOSED is unknown, never open" \
    "$(run_on "$STALE" | grep -c 'UNKNOWN ovation#111')" "1"

printf '95 OPEN\n111 CLOSED\n' > "$STATES"
check_exit "a closed issue still refuses even when another cannot be read" \
    1 status_on "$STALE"

# ---------------------------------------------------------------------------
# NOTHING TO MEASURE IS NOT A PASS, and each way of having nothing is its own
# outcome (L98, L11).
# ---------------------------------------------------------------------------
check_exit "no README at all cannot measure" 2 status_on "$WORK/nowhere"
check "and says which cause it hit" \
    "$(run_on "$WORK/nowhere" | grep -c 'no .*README.md, so nothing was read')" "1"

RENAMED="$(mkdir -p "$WORK/renamed" && printf '%s' "$WORK/renamed")"
printf '# The design record\n\n## Outstanding\n\n`ovation#95`\n' > "$RENAMED/README.md"
check_exit "a renamed heading cannot measure" 2 status_on "$RENAMED"
check "and is told apart from a section with nothing in it" \
    "$(run_on "$RENAMED" | grep -c 'has no .* heading')" "1"

EMPTYSEC="$(mkdir -p "$WORK/emptysec" && printf '%s' "$WORK/emptysec")"
record "$EMPTYSEC" 'Nothing is outstanding today.'
check_exit "a section naming no issue cannot measure" 2 status_on "$EMPTYSEC"
check "and says so in its own words" \
    "$(run_on "$EMPTYSEC" | grep -c 'names no issue')" "1"

# ---------------------------------------------------------------------------
# The committed record, which is the run CI makes. It reaches the real tracker,
# so it is only asserted to be one of the answers this check can give rather
# than a particular one: an issue closed while this suite runs is a finding
# about the record, not about the suite.
# ---------------------------------------------------------------------------
REAL_SAID="$(python3 "$TARGET" 2>&1)"; REAL=$?
KNOWN="no, it exited $REAL and said: $(head -n 20 <<< "$REAL_SAID")"
if [ "$REAL" = "0" ] || [ "$REAL" = "1" ] || [ "$REAL" = "2" ]; then KNOWN="yes"; fi
check "the committed record answers with one of this check's own outcomes" "$KNOWN" "yes"

# AND THE COMMITTED FILES' SHAPE IS JUDGED ON EVERY PUSH (ovation#331).
#
# The shape rules of ovation#204 read the files and nothing else, so unlike the
# tracker half they can refuse here, where a badly shaped entry is cheapest to
# fix. Until this, they ran only in the Design record workflow: an entry citing
# nothing could sit on main for up to a day, and the case above cannot see it
# because a real lookup makes the exit code 0, 1 or 2 for reasons of its own.
#
# THE TRACKER IS ANSWERED FROM A STUB, so this needs no network and no
# credentials: a gate that refuses on every machine without them is one people
# learn to skip (L376, L571). That is the arrangement scripts/lib/script-roles.tsv
# records for the rendering checks, which the gate does not call because every
# push already runs them against the COMMITTED files through their sibling suite,
# and a second call in the gate would be a second copy of one policy (L613).
COMMITTED="$(OVATION_ISSUE_STATE_COMMAND='echo OPEN' OVATION_DECISION_LIST_COMMAND='echo 100' \
    python3 "$TARGET" 2>&1)"
check "every committed design file's open list is correctly shaped" \
    "$(printf '%s' "$COMMITTED" | grep -cE '^  (UNCITED|NOT AN ENTRY|EMPTY)')" "0"
# AND THE RUN THAT SAID SO ACTUALLY READ THEM. A check on the absence of a word
# is answered just as well by a run that refused before reaching the files (L159).
check "and that run really did read the files' own lists" \
    "$(printf '%s' "$COMMITTED" | grep -c 'carries its own .What is deliberately still open. list')" "4"

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

printf '100\n' > "$DECISIONS"
FILEOPEN="$WORK/fileopen"
record "$FILEOPEN" 'The record itself names `ovation#100`.'
design_file "$FILEOPEN" "invoice-list.html" '<ol><li>Where the times live, ovation#95.</li></ol>'
printf '95 OPEN\n100 OPEN\n998 CLOSED\n' > "$STATES"
check_exit "a design file whose own open list names an open issue passes" \
    0 status_on "$FILEOPEN"
# The ISSUE line, not merely the file name: the file is also named on its own
# "carries a list" line, which says nothing about whether the list was read.
check "and the file's list is actually read, not just the record's" \
    "$(run_on "$FILEOPEN" | grep -cE 'OPEN +ovation#95, named on line [0-9]+ of invoice-list.html')" "1"

# THE FAULT: a file's own list naming an issue that has since closed.
FILECLOSED="$WORK/fileclosed"
record "$FILECLOSED" 'The record itself names `ovation#100`.'
design_file "$FILECLOSED" "clients.html" '<ol><li>The pane scrolls sideways, ovation#110.</li></ol>'
printf '100 OPEN\n110 CLOSED\n998 CLOSED\n' > "$STATES"
check_exit "a design file calling a closed issue still open is refused" \
    1 status_on "$FILECLOSED"
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
<ol><li>Where the times live, ovation#95.</li></ol>
<script>
/* Settled in ovation#997, which is closed and must never be looked up. */
var x = 1;
</script>
HTML
printf '95 OPEN\n100 OPEN\n997 CLOSED\n' > "$STATES"
check_exit "a settled issue named in a script comment is not read as still open" \
    0 status_on "$SCRIPTED"
check "and that issue is never asked about at all" \
    "$(run_on "$SCRIPTED" | grep -c 'ovation#997')" "0"

# A FILE WITH NO LIST AT ALL IS COUNTED AND NAMED.
NOLIST="$WORK/nolist"
record "$NOLIST" 'The record itself names `ovation#100`.'
mkdir -p "$NOLIST"
printf '<meta charset="utf-8">\n<h1>The invoice screen</h1>\n' > "$NOLIST/invoice.html"
printf '100 OPEN\n' > "$STATES"
check_exit "a design file carrying no open list does not refuse" 0 status_on "$NOLIST"
check "and it is named, so a list that disappeared is visible" \
    "$(run_on "$NOLIST" | grep -c 'invoice.html carries no')" "1"


# ---------------------------------------------------------------------------
# EVERY ENTRY NAMES WHAT IT HANGS ON (ovation#204).
#
# An entry that cites nothing is checked by nothing, and that is the entry that
# caused ovation#200: invoice-list.html said held money had no surface there,
# citing nothing, while two requirements had made it untrue the same day.
# Splitting prose into entries was a guess about markup, so the entries now have a
# DECLARED shape, one list item each, and every one must name an ovation#N or a
# PRD number. Two refusals, told apart, because the remedies differ (L11): an item
# citing nothing needs a citation or deleting, and prose outside any item needs
# writing as an item.
# ---------------------------------------------------------------------------
CITED="$WORK/cited"
record "$CITED" 'The record itself names `ovation#100`.'
design_file "$CITED" "clients.html" '<ol>
<li>The pane scrolls sideways, ovation#110.</li>
<li><b>A decision, not a gap</b> (Dan, 2026-09-10,
PRD 5a). The citation is on the second line of the item.</li>
</ol>'
printf '100 OPEN\n110 OPEN\n' > "$STATES"
check_exit "a list whose every item cites an issue or a requirement passes" 0 status_on "$CITED"
check "and a PRD citation on an item's second line counts" \
    "$(run_on "$CITED" | grep -c 'UNCITED')" "0"

UNCITED="$WORK/uncited"
record "$UNCITED" 'The record itself names `ovation#100`.'
design_file "$UNCITED" "clients.html" '<ol>
<li>The pane scrolls sideways, ovation#110.</li>
<li><b>Nothing here refuses a term the invoice would not offer.</b> Two copies,
and nothing yet compares them.</li>
</ol>'
check_exit "an item that cites nothing is refused" 1 status_on "$UNCITED"
check "and the refusal names the file and the line the item starts on" \
    "$(run_on "$UNCITED" | grep -cE 'UNCITED +line 7 of clients.html')" "1"
check "and the cited item beside it is not accused" \
    "$(run_on "$UNCITED" | grep -cE 'UNCITED +line 6 of clients.html')" "0"

LOOSE="$WORK/loose"
record "$LOOSE" 'The record itself names `ovation#100`.'
design_file "$LOOSE" "review-send.html" '<p>Every outbound sentence owes its cold read (PRD 41a).</p>'
check_exit "prose outside any list item is refused, even when it cites something" \
    1 status_on "$LOOSE"
check "and it is told apart from an uncited item, naming the line" \
    "$(run_on "$LOOSE" | grep -cE 'NOT AN ENTRY +line 5 of review-send.html')" "1"

EMPTYITEMS="$WORK/emptyitems"
record "$EMPTYITEMS" 'The record itself names `ovation#100`.'
design_file "$EMPTYITEMS" "clients.html" '<ol>
</ol>'
check_exit "a list heading with no items in it is refused rather than read as nothing open" \
    1 status_on "$EMPTYITEMS"
check "and says the list is empty" \
    "$(run_on "$EMPTYITEMS" | grep -cE 'EMPTY +clients.html')" "1"


# THE TAGS THAT CLOSE THE SECTION ARE NOT ENTRIES. The list runs to the next
# heading or the script, so it carries the markup wrapping it, and a rule reading
# raw characters accused `</section>` on two real files the first time it ran.
WRAPPED="$WORK/wrapped"
record "$WRAPPED" 'The record itself names `ovation#100`.'
mkdir -p "$WRAPPED"
cat > "$WRAPPED/clients.html" <<'HTML'
<meta charset="utf-8">
<div class="record"><section>
<h2>What is deliberately still open</h2>
<ol>
<li>The pane scrolls sideways, ovation#110.</li>
</ol>
</section>
</div>
<script>var x = 1;</script>
HTML
printf '100 OPEN\n110 OPEN\n' > "$STATES"
check_exit "the markup that closes the section is not read as an entry" 0 status_on "$WRAPPED"
check "and nothing in it is reported" \
    "$(run_on "$WRAPPED" | grep -cE 'NOT AN ENTRY|UNCITED')" "0"

# ---------------------------------------------------------------------------
# THE OTHER DIRECTION (ovation#195). Everything above asks whether an issue the
# section NAMES is still open. Nothing asked whether an issue that is open and
# waiting on Dan is NAMED: the section once listed three while seven design
# decisions of the same kind were open, and this check was green throughout
# because it answered the only question it asked. Dan decided on 2026-09-29 that
# the handle is a dedicated `design-decision` label, applied deliberately, and
# that an open issue carrying it and missing from the section is refused.
# ---------------------------------------------------------------------------
LISTED="$WORK/listed"
record "$LISTED" 'The receipts queue, `ovation#100`, and the combined header, `ovation#147`.'
printf '100 OPEN\n147 OPEN\n' > "$STATES"
printf '100\n147\n' > "$DECISIONS"
check_exit "every labelled decision named in the section passes" 0 status_on "$LISTED"
check "and the verdict says the labelled decisions were compared" \
    "$(run_on "$LISTED" | grep -c 'all 2 open issue(s) carrying the design-decision label')" "1"

printf '100\n147\n489\n' > "$DECISIONS"
check_exit "a labelled decision the section does not name is refused" 1 status_on "$LISTED"
check "and the missing one is named, with what to do" \
    "$(run_on "$LISTED" | grep -c 'MISSING ovation#489 carries the design-decision label')" "1"
check "and the ones that are named are not accused" \
    "$(run_on "$LISTED" | grep -cE 'MISSING ovation#(100|147)')" "0"
check "and the verdict counts it" \
    "$(run_on "$LISTED" | grep -c 'REFUSED: 1 open issue(s) carrying the design-decision label')" "1"

# NAMED IN A DESIGN FILE'S OWN LIST IS NOT NAMED IN THE RECORD. Dan's decision
# names the README's section, which is the list people read as the list.
design_file "$LISTED" "invoice.html" '<ol><li>The chosen type, ovation#489.</li></ol>'
printf '100 OPEN\n147 OPEN\n489 OPEN\n' > "$STATES"
check_exit "a labelled decision named only inside a design file is still refused" \
    1 status_on "$LISTED"
rm -f "$LISTED/invoice.html"

# A LIST THAT COULD NOT BE READ IS NOT A LIST WITH NOTHING ON IT (L98, L11).
printf '100 OPEN\n147 OPEN\n' > "$STATES"
failing_list() {
    OVATION_DESIGN_ROOT="$1" STATES="$STATES" \
        OVATION_ISSUE_STATE_COMMAND="bash $WORK/reader.sh {n}" \
        OVATION_DECISION_LIST_COMMAND="$2" \
        python3 "$TARGET" 2>&1
}
check_exit "a label list that could not be read cannot measure" \
    2 failing_list "$LISTED" "exit 4"
check "and says the list could not be read, in its own words" \
    "$(failing_list "$LISTED" "exit 4" | grep -c 'CANNOT MEASURE: the open issues carrying the design-decision label could not be listed')" "1"
check_exit "a label list answering something that is not issue numbers cannot measure" \
    2 failing_list "$LISTED" "echo 'HTTP 504: try again'"
check "and it is not read as a list of numbers" \
    "$(failing_list "$LISTED" "echo 'HTTP 504: try again'" | grep -c 'could not be listed')" "1"

# NO LABELLED ISSUE AT ALL IS A LEGITIMATE STATE. On 2026-09-29 Dan settled
# every open design question and the label came off all seven issues, so a list
# with nothing on it is the tracker saying nothing is waiting, and it passes.
# The issues the section still names are still asked about, in the first
# direction, exactly as before.
check_exit "no open issue carrying the label passes" 0 failing_list "$LISTED" "true"
check "and it says so rather than passing silently" \
    "$(failing_list "$LISTED" "true" | grep -c 'No open issue carries the design-decision label')" "1"

# AND A SECTION WITH NOTHING IN IT SAYS SO. A section naming no issue used to be
# CANNOT MEASURE and still is, unless it states the healthy day in the one
# declared sentence, so an emptied section and a record with nothing waiting
# are told apart by what the record says rather than by a guess (L98, L610).
SETTLED="$WORK/settled"
record "$SETTLED" 'Nothing is waiting on Dan. Every design decision has been made.'
check_exit "a section saying nothing is waiting, with no labelled issue, passes" \
    0 failing_list "$SETTLED" "true"
check "and the verdict says nothing is waiting" \
    "$(failing_list "$SETTLED" "true" | grep -c 'OK: the design record says nothing is waiting on Dan, and no open issue carries the design-decision label')" "1"
check_exit "a section saying nothing is waiting while a labelled issue is open is refused" \
    1 failing_list "$SETTLED" "echo 489"
check "and the labelled issue is named as missing" \
    "$(failing_list "$SETTLED" "echo 489" | grep -c 'MISSING ovation#489')" "1"
check_exit "a section saying nothing is waiting still cannot measure when the list fails" \
    2 failing_list "$SETTLED" "exit 4"

# A CLOSED ISSUE STILL OUTRANKS A LIST THAT FAILED, as a shape fault does: it
# was measured and is true whatever the list says.
printf '100 OPEN\n147 CLOSED\n' > "$STATES"
check_exit "a closed issue is still refused when the label list cannot be read" \
    1 failing_list "$LISTED" "exit 4"

harness_end
