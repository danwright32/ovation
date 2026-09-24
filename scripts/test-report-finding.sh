#!/bin/bash
# Whether a finding reaches Dan once, and whether it stops being reported when
# it is over.
#
# ovation#339. Two workflows carried this logic inside a YAML step, so it only
# ever ran on a runner and nothing could judge it before it shipped. It is the
# half that decides whether a finding is seen at all, and every way it breaks is
# silent in the direction that loses the report: a lookup that matches nothing
# files a SECOND issue beside the first (L393), a title that stops matching
# duplicates the finding for ever, and a close that never fires leaves a finished
# finding reading as outstanding (L269).
#
# `gh` IS A SEAM, so every path below is driven against a stub that records what
# it was asked and answers from a file. Nothing here reaches the real tracker,
# and a suite that could only pass by reaching it would be asserting about the
# backlog rather than about this script (L2, L291).
#
# THE STUB ANSWERS AND RECORDS, which is both halves: a case asserting a write
# did NOT happen is satisfied by a stub that cannot write at all, so each case
# also reads the call log and says which calls were made (L159).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "report finding tests" 64

TARGET="scripts/report-finding.sh"
require_target "$TARGET"
harness_temp_dir WORK

# ---------------------------------------------------------------------------
# The stub. One file, answering from whichever directory STUB_DIR names, so a
# case stages an answer rather than rewriting the stub. It logs `issue create`,
# `issue comment`, `issue close` and `issue list` one per line, and every
# argument it was given one per line, so a case can assert on the text a write
# carried as well as on the fact that it happened.
# ---------------------------------------------------------------------------
BIN="$WORK/bin"; mkdir -p "$BIN"
#
# ITS BODY IS INDENTED, and that is not decoration. scripts/test-run-tests.sh
# refuses a suite that reads `$1` on a line of its own, because a suite taking a
# parameter is only ever run one way by the glob that finds it, and a heredoc's
# lines are read by that rule exactly like the suite's own (L135, ovation#71).
# Leading spaces mean nothing to the stub and keep the rule able to see what it
# is looking for.
cat > "$BIN/gh" <<'STUB'
#!/bin/bash
    D="${STUB_DIR:?the gh stub was run with no directory to answer from}"
    printf '%s %s\n' "${1:-}" "${2:-}" >> "$D/calls.log"
    for a in "$@"; do printf '%s\n' "$a" >> "$D/args.log"; done
    if [ "${1:-} ${2:-}" = "issue list" ]; then
        [ -f "$D/list.json" ] && cat "$D/list.json"
        exit "$(cat "$D/list.status" 2>/dev/null || echo 0)"
    fi
    exit "$(cat "$D/write.status" 2>/dev/null || echo 0)"
STUB
chmod +x "$BIN/gh"

# stage <name> <what the lookup prints> [lookup exit] [write exit]
stage() {
    STUB_DIR="$WORK/stub-$1"
    mkdir -p "$STUB_DIR"
    : > "$STUB_DIR/calls.log"
    : > "$STUB_DIR/args.log"
    printf '%s' "$2" > "$STUB_DIR/list.json"
    printf '%s' "${3:-0}" > "$STUB_DIR/list.status"
    printf '%s' "${4:-0}" > "$STUB_DIR/write.status"
    export STUB_DIR
}

# ONE RUN PER CASE, its output and its exit code both kept. Running the script
# twice to read one and then the other would double every entry in the call log
# and quietly make each write assertion about two invocations.
OUT=""
STATUS=""
run_report() {
    OUT="$(OVATION_GH="$BIN/gh" "./$TARGET" "$@" 2>&1)"
    STATUS=$?
}
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }
calls() { grep -cx -- "$1" "$STUB_DIR/calls.log"; }
call_count() { grep -c . "$STUB_DIR/calls.log"; }
carried() { if grep -qxF -- "$1" "$STUB_DIR/args.log"; then echo yes; else echo no; fi; }

TITLE="A staged finding that nothing real carries"
NEW="$WORK/new.md";     printf 'The body of a newly filed finding.\n' > "$NEW"
AGAIN="$WORK/again.md"; printf 'Still true today.\n' > "$AGAIN"
CLOSE="$WORK/close.md"; printf 'It is over, so this is closed.\n' > "$CLOSE"

# A tracker holding one open issue with exactly this title, and one whose title
# merely resembles it. `gh issue list --search "in:title ..."` is a FUZZY search
# and returns both, which is why the exact filter exists at all.
EXACT='[{"number":44,"title":"A staged finding that nothing real carries"}]'
RESEMBLES='[{"number":12,"title":"A staged finding that nothing real carries any more"}]'
BOTH='[{"number":12,"title":"A staged finding that nothing real carries any more"},
       {"number":44,"title":"A staged finding that nothing real carries"}]'
TWICE='[{"number":44,"title":"A staged finding that nothing real carries"},
        {"number":91,"title":"A staged finding that nothing real carries"}]'

# ---------------------------------------------------------------------------
# 1. NOTHING OPEN, so the finding is filed. This is the path that must not run
#    when an issue already stands, and the one every other case is measured
#    against.
# ---------------------------------------------------------------------------
stage opened '[]'
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN" \
    --milestone Ungrouped --label priority-p1 --label ci-hygiene
check "a finding with no open issue is filed" "$STATUS" "0"
check "and it says so in its own word" "$(says "$OUT" "OPENED")" "yes"
check "and gh was asked to create exactly one issue" "$(calls 'issue create')" "1"
check "and it was never asked to comment" "$(calls 'issue comment')" "0"
check "and the body came from the file, never an inline string" "$(carried "$NEW")" "yes"
check "and the milestone the caller named went with it" "$(carried "Ungrouped")" "yes"
check "and both labels the caller named went with it" \
    "$(grep -cx -- '--label' "$STUB_DIR/args.log")" "2"

# ---------------------------------------------------------------------------
# 2. ONE ALREADY OPEN, so it is commented on rather than duplicated (L393).
# ---------------------------------------------------------------------------
stage commented "$EXACT"
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN" \
    --milestone Ungrouped --label priority-p1
check "a finding whose issue is already open is commented on" "$STATUS" "1"
check "and it says so in its own word" "$(says "$OUT" "COMMENTED")" "yes"
check "and it names the issue it commented on" "$(says "$OUT" "44")" "yes"
check "and gh was asked to comment exactly once" "$(calls 'issue comment')" "1"
check "and it was never asked to create a second issue" "$(calls 'issue create')" "0"
check "and the comment came from the file the caller gave" "$(carried "$AGAIN")" "yes"

# ---------------------------------------------------------------------------
# 3. THE LOOKUP IS FUZZY AND THE MATCH IS NOT. `in:title` is a search, not an
#    equality, so it returns titles that merely resemble the marker. Acting on
#    one of those would comment on somebody else's issue and leave this finding
#    unreported for ever.
# ---------------------------------------------------------------------------
stage resembles "$RESEMBLES"
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN"
check "an issue whose title only resembles the marker is not this finding" "$STATUS" "0"
check "so the finding is filed rather than left on somebody else's issue" \
    "$(calls 'issue create')" "1"

stage both "$BOTH"
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN"
check "the exact match is taken even when a resembling one comes back first" "$STATUS" "1"
check "and it is the exact one's number, not the first the search returned" \
    "$(says "$OUT" "44")" "yes"

# ---------------------------------------------------------------------------
# 4. THE CONDITION CLEARS, so the issue is closed. A finding left open after it
#    stops being true reads as outstanding and teaches everyone to skim the next
#    one (L269).
# ---------------------------------------------------------------------------
stage closed "$EXACT"
run_report cleared --title "$TITLE" --comment-file "$CLOSE"
check "a finding that is over closes its issue" "$STATUS" "2"
check "and it says so in its own word" "$(says "$OUT" "CLOSED")" "yes"
check "and gh was asked to close exactly once" "$(calls 'issue close')" "1"
check "and it named the issue it closed" "$(carried "44")" "yes"
check "and the closing comment came from the file" \
    "$(carried "It is over, so this is closed.")" "yes"

# ---------------------------------------------------------------------------
# 5. NOTHING TO CLOSE. This is what a condition that never fired looks like, and
#    it is not a fault: saying nothing at all here would make it indistinguishable
#    from a close that failed (L11, L98).
# ---------------------------------------------------------------------------
stage nothing '[]'
run_report cleared --title "$TITLE" --comment-file "$CLOSE"
check "a condition that never fired has nothing to close" "$STATUS" "3"
check "and it says that rather than reporting a close" \
    "$(says "$OUT" "NOTHING TO CLOSE")" "yes"
check "and nothing beyond the lookup was asked of gh" "$(call_count)" "1"

# ---------------------------------------------------------------------------
# 6. TWO ISSUES CARRY THE MARKER. That means an earlier run already duplicated
#    the finding, so picking one of them hides the very fault this script exists
#    to prevent. Many matches is its own refusal (L521).
# ---------------------------------------------------------------------------
stage many "$TWICE"
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN"
check "two issues carrying one marker title is refused" "$STATUS" "4"
check "and it says so rather than acting on one of them" "$(says "$OUT" "MANY")" "yes"
check "and it names the first of them so a person can merge them" "$(says "$OUT" "44")" "yes"
check "and the second as well, not just the one it would have used" \
    "$(says "$OUT" "91")" "yes"
check "and nothing was written while the tracker is in that state" "$(call_count)" "1"

stage many-cleared "$TWICE"
run_report cleared --title "$TITLE" --comment-file "$CLOSE"
check "and closing refuses on the same state rather than closing whichever it saw" \
    "$STATUS" "4"
check "and closes nothing" "$(calls 'issue close')" "0"

# ---------------------------------------------------------------------------
# 7. THE LOOKUP ITSELF FAILS. No token, no network, a rate limit. Reading that
#    as "no such issue" files a duplicate beside the one already open, which is
#    the loudest way this can go wrong (L393, L214).
# ---------------------------------------------------------------------------
stage cannot-ask '' 1
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN"
check "a lookup that failed is not read as no such issue" "$STATUS" "5"
check "and it says the lookup could not be made" "$(says "$OUT" "CANNOT ASK")" "yes"
check "and it files nothing on the strength of an answer it did not get" \
    "$(call_count)" "1"

stage garbled 'not json at all'
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN"
check "an answer that cannot be read is refused the same way" "$STATUS" "5"

stage untitled '[{"title":"A staged finding that nothing real carries"}]'
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN"
check "a matching row carrying no number is refused rather than dropped" "$STATUS" "5"

# ---------------------------------------------------------------------------
# 8. THE LOOKUP ANSWERS AND THE WRITE FAILS. The finding was measured and nobody
#    was told, which is a different fact from not being able to ask (L11).
# ---------------------------------------------------------------------------
stage create-fails '[]' 0 1
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN"
check "a creation that failed is not reported as a finding filed" "$STATUS" "6"
check "and it says nobody was told" "$(says "$OUT" "COULD NOT SAY IT")" "yes"

stage comment-fails "$EXACT" 0 1
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN"
check "a comment that failed is reported the same way" "$STATUS" "6"

stage close-fails "$EXACT" 0 1
run_report cleared --title "$TITLE" --comment-file "$CLOSE"
check "and a close that failed too" "$STATUS" "6"

# ---------------------------------------------------------------------------
# 9. USED WRONGLY. A missing argument must never fall back to a default: a
#    finding reported under the wrong title is a finding nobody will ever match
#    again (L168, L320).
# ---------------------------------------------------------------------------
stage wrong '[]'
run_report
check "no command at all is refused" "$STATUS" "7"
check "and it says the script was used wrongly" "$(says "$OUT" "USED WRONGLY")" "yes"
run_report shout --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN"
check "a command this script does not have is refused" "$STATUS" "7"
run_report stands --body-file "$NEW" --comment-file "$AGAIN"
check "a finding with no title is refused rather than given one" "$STATUS" "7"
run_report stands --title "$TITLE" --comment-file "$AGAIN"
check "a finding with no body file is refused" "$STATUS" "7"
run_report stands --title "$TITLE" --body-file "$WORK/no-such-body.md" --comment-file "$AGAIN"
check "a body file that is not there is refused before anything is written" "$STATUS" "7"
run_report cleared --title "$TITLE" --comment-file "$CLOSE" --label priority-p1
check "an option the close path has no use for is refused, not ignored" "$STATUS" "7"

# ---------------------------------------------------------------------------
# 10. THE DEFAULT IS THE REAL gh, and that is asserted without reaching it: the
#     stub is put on PATH under the name `gh` and the seam is left unset, so what
#     is proved is which NAME the script reaches for (L2).
# ---------------------------------------------------------------------------
stage default '[]'
OUT="$(PATH="$BIN:$PATH" env -u OVATION_GH "./$TARGET" stands --title "$TITLE" \
    --body-file "$NEW" --comment-file "$AGAIN" 2>&1)"
STATUS=$?
check "with no seam set it reaches for the command named gh" "$STATUS" "0"
check "and that is the command it actually ran" "$(calls 'issue create')" "1"

# ---------------------------------------------------------------------------
# 11. IT PRINTS NUMBERS, NOT THE WORDS THE CALLER COMPOSED. This repository is
#     public on purpose, so a workflow log is a published document, and the title
#     and body are text a caller could put anything into (docs/PRIVACY-FLOOR.md).
#     The issue number names the finding exactly and carries nothing.
# ---------------------------------------------------------------------------
stage quiet '[]'
run_report stands --title "$TITLE" --body-file "$NEW" --comment-file "$AGAIN"
check "it does not print the title back" "$(says "$OUT" "$TITLE")" "no"
check "and it does not print the body it was given" \
    "$(says "$OUT" "The body of a newly filed finding.")" "no"

# ---------------------------------------------------------------------------
# 12. A CALLER THAT MAY NOT OPEN AN ISSUE AT ALL (ovation#332).
#
#     `stands` files one when none is open, which is right for a condition a
#     workflow measures and nobody has asked about. A RECURRENCE COUNT is the
#     other shape: Dan opens the issue that carries it, deliberately, and the
#     workflow adds one comment each time it happens. An automated write that
#     opens an issue on a public tracker is his decision to make, not this
#     script's, and he made it on 2026-09-15.
#
#     NOTHING OPEN IS ITS OWN OUTCOME, never a quiet success. A recurrence that
#     was measured and reported to nobody is exactly the silent loss this script
#     exists to prevent, so it refuses and says which title it looked for is not
#     open (L98, L11).
# ---------------------------------------------------------------------------
stage recurred "$EXACT"
run_report recurred --title "$TITLE" --comment-file "$AGAIN"
check "a recurrence on an open issue is commented on" "$STATUS" "1"
check "and it says so in its own word" "$(says "$OUT" "COMMENTED")" "yes"
check "and gh was asked to comment exactly once" "$(calls 'issue comment')" "1"
check "and it was never asked to create anything" "$(calls 'issue create')" "0"

stage recurred-none '[]'
run_report recurred --title "$TITLE" --comment-file "$AGAIN"
check "a recurrence with no issue open refuses rather than filing one" "$STATUS" "8"
check "and it says there is nothing open carrying it" \
    "$(says "$OUT" "NOTHING OPEN")" "yes"
check "and nothing at all was written" \
    "$(($(calls 'issue create') + $(calls 'issue comment') + $(calls 'issue close')))" "0"

# AND THE REFUSALS IT SHARES WITH THE OTHER COMMANDS STILL ANSWER (L151).
stage recurred-many "$TWICE"
run_report recurred --title "$TITLE" --comment-file "$AGAIN"
check "a recurrence with two issues carrying the title refuses as MANY" "$STATUS" "4"
stage recurred-cannot '[]' 1
run_report recurred --title "$TITLE" --comment-file "$AGAIN"
check "a recurrence whose lookup failed refuses as CANNOT ASK" "$STATUS" "5"
stage recurred-mute "$EXACT" 0 1
run_report recurred --title "$TITLE" --comment-file "$AGAIN"
check "a recurrence whose comment failed says nobody was told" "$STATUS" "6"

# A BODY IS AN OPTION THIS COMMAND HAS NO USE FOR, and an option that is ignored
# rather than refused is how a caller believes it can open one after all (L320).
stage recurred-body "$EXACT"
run_report recurred --title "$TITLE" --comment-file "$AGAIN" --body-file "$NEW"
check "a recurrence given a body to file with is refused, not quietly obeyed" "$STATUS" "7"
check "and it names the option this command has no use for" \
    "$(says "$OUT" "--body-file")" "yes"

harness_end
