#!/bin/bash
# The suite for scripts/check-design-rules-inline.sh.
#
# ovation#111. `docs/design/rules/` holds the invoice screen's rules as
# executable functions with their cases, and `docs/design/README.md` says they
# exist "so whoever ports this to Swift has something to port AGAINST". They are
# run by scripts/test-design-rules.sh and they pass.
#
# THEY ARE NOT THE CODE THE DESIGN FILE RUNS. A design file must be one self
# contained document (ovation#114), so it cannot load rules/ at render time: it
# carries its own copy. That is two copies of one rule with nothing comparing
# them, which is L370, and it had already gone wrong before this guard existed.
# Commit a12b32a fixed a real NaN defect in typeDigit in rules/time-field.js and
# left the identical copy inside docs/design/invoice-being-priced.html untouched.
# The suite stayed green, because the suite reads rules/. The screen the design
# record IS still held the defect.
#
# So the guard asserts that every rule file appears inside a design file
# VERBATIM, as a contiguous run of lines rather than as lines that merely all
# occur somewhere (L178: a check written as several conditions over one body of
# text is satisfied by several unrelated places in it). The scattered fixture
# below is the case that proves it.
#
# A rule that NO design file renders is its own outcome, not a silent pass, and
# it is cleared by the rule file saying so in its own words rather than by a list
# of exempt filenames here (L362).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design rule inlining tests" 35

TARGET="scripts/check-design-rules-inline.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_on() { OVATION_DESIGN_ROOT="$1" "./$TARGET" 2>&1; }
status_on() {
    OVATION_DESIGN_ROOT="$1" "./$TARGET"
}

# The rule, as it would sit in rules/. Deliberately carries a comment and blank
# lines, because the design file indents its copy inside a <script> and the
# comparison has to survive that or it can only ever match by luck.
RULE='/* Half away from zero, stated for negatives because a credit is one. */

function roundToQuarter(hours) {
  return Math.round(hours / 0.25) * 0.25;
}
'

# The same rule as the design file carries it: indented, and with the comment
# rewrapped, which is what actually happens when it is pasted into a script.
INLINED='  /* Half away from zero, stated for negatives
     because a credit is one. */
  function roundToQuarter(hours) {
    return Math.round(hours / 0.25) * 0.25;
  }
'

record() {
    # $1 destination root, $2 what goes inside the design file's script
    mkdir -p "$1/rules"
    printf '%s' "$RULE" > "$1/rules/duration.js"
    { printf '<meta charset="utf-8">\n<script>\n'
      printf '%s' "$2"
      printf '</script>\n'
    } > "$1/invoice.html"
}

# ---------------------------------------------------------------------------
# The healthy record: the rule is carried verbatim.
# ---------------------------------------------------------------------------
GOOD="$WORK/good"
record "$GOOD" "$INLINED"
check_exit "a rule carried verbatim by a design file passes" 0 status_on "$GOOD"
check "and it says how many rules it actually compared" \
    "$(run_on "$GOOD" | grep -c '1 rule')" "1"
check "and it names the design file it found the rule in" \
    "$(run_on "$GOOD" | grep -c 'invoice.html')" "1"

# ---------------------------------------------------------------------------
# THE CASE THE GUARD EXISTS FOR, and the one that really happened: the rule was
# corrected and the design file's copy was not.
# ---------------------------------------------------------------------------
DRIFT="$WORK/drift"
record "$DRIFT" '  function roundToQuarter(hours) {
    return Math.round(hours / 0.5) * 0.5;
  }
'
check_exit "a design file whose copy has drifted is refused" 1 status_on "$DRIFT"
check "and the refusal says DRIFTED rather than something generic" \
    "$(run_on "$DRIFT" | grep -c 'DRIFTED')" "1"
check "and it names the rule that drifted" \
    "$(run_on "$DRIFT" | grep -c 'duration.js')" "1"
check "and it says which line of the rule it stopped matching at" \
    "$(run_on "$DRIFT" | grep -cE 'line [0-9]+')" "1"

# A drift of ONE line inside an otherwise identical rule, which is the shape of
# the real defect: a guard added to one copy and not the other.
ONELINE="$WORK/oneline"
record "$ONELINE" '  function roundToQuarter(hours) {
    if (!isFinite(hours)) return 0;
    return Math.round(hours / 0.25) * 0.25;
  }
'
check_exit "one extra line inside the rule is still a drift" 1 status_on "$ONELINE"

# ---------------------------------------------------------------------------
# THE CASE THAT PROVES THE MATCH IS CONTIGUOUS. Every line of the rule is present
# in this file, and none of them is in the right place. A containment check would
# call this correct (L178).
# ---------------------------------------------------------------------------
SCATTERED="$WORK/scattered"
record "$SCATTERED" '  function roundToQuarter(hours) {
  var somethingElse = 1;
    return Math.round(hours / 0.25) * 0.25;
  var andAnother = 2;
  }
'
check_exit "a rule whose lines are all present but scattered is refused" \
    1 status_on "$SCATTERED"

# ---------------------------------------------------------------------------
# A rule no design file renders. Not a pass, and not cleared by naming the file
# here: cleared by the rule saying so, in its own words.
# ---------------------------------------------------------------------------
ABSENT="$WORK/absent"
record "$ABSENT" '  var unrelated = 1;
'
check_exit "a rule no design file carries is refused" 1 status_on "$ABSENT"
check "and it says NOT INLINE, which is a different fault from a drift" \
    "$(run_on "$ABSENT" | grep -c 'NOT INLINE')" "1"
check "and it does not also claim the rule drifted" \
    "$(run_on "$ABSENT" | grep -c 'DRIFTED')" "0"

DECLARED="$WORK/declared"
record "$DECLARED" '  var unrelated = 1;
'
printf '/* NOT RENDERED: no screen prices a discount yet, ovation#111. */\n%s' \
    "$RULE" > "$DECLARED/rules/duration.js"
check_exit "a rule that says why no screen renders it passes" 0 status_on "$DECLARED"
check "and the pass still reports it, rather than counting it as inlined" \
    "$(run_on "$DECLARED" | grep -c 'NOT RENDERED')" "1"

# ---------------------------------------------------------------------------
# Nothing to compare is not a pass, and the two ways of having nothing are
# different failures with different remedies (L11).
# ---------------------------------------------------------------------------
check_exit "a missing design root cannot measure" 2 status_on "$WORK/nowhere"

NORULES="$WORK/norules"
mkdir -p "$NORULES"
printf '<meta charset="utf-8">\n' > "$NORULES/invoice.html"
check_exit "a record with no rules at all cannot measure" 2 status_on "$NORULES"
check "and says the rules are missing, not that the design agrees with them" \
    "$(run_on "$NORULES" | grep -c 'CANNOT SCAN')" "1"

NOHTML="$WORK/nohtml"
mkdir -p "$NOHTML/rules"
printf '%s' "$RULE" > "$NOHTML/rules/duration.js"
check_exit "a record with rules but no design files cannot measure" 2 status_on "$NOHTML"
check "and names that as its own cause" \
    "$(run_on "$NOHTML" | grep -c 'no design file')" "1"

# ---------------------------------------------------------------------------
# THE REASONING, WHICH THIS GUARD USED TO LET DRIFT (ovation#144). A rule file's
# comment is where the decision, its measurement and the person who made it are
# recorded, and until 2026-09-09 the guard compared the CODE and reported OK
# while the two copies gave different reasons for the same rule. It is not
# hypothetical: the 12 hour cap's provenance was added to `rules/duration.js` on
# 2026-09-08 and copied into the design file BY HAND, with the guard green
# before and after.
# ---------------------------------------------------------------------------
REWORDED="$WORK/reworded"
record "$REWORDED" '  /* Half away from zero, stated for POSITIVES because a
     debit is one. */
  function roundToQuarter(hours) {
    return Math.round(hours / 0.25) * 0.25;
  }
'
check_exit "a copy that runs the same code and says something else is refused" \
    1 status_on "$REWORDED"
check "and the finding names the reasoning rather than the code" \
    "$(run_on "$REWORDED" | grep -c 'REASONING DRIFTED')" "1"
check "and it is NOT reported as a rule no design file carries" \
    "$(run_on "$REWORDED" | grep -c 'NOT INLINE')" "0"
check "which is what comparing the comments alone would have said" \
    "$(run_on "$REWORDED" | grep -c 'saying something different about the same code')" "1"

# REWRAPPING THE SAME SENTENCE IS STILL FINE, which is the whole reason comments
# were stripped in the first place. The healthy fixture above already rewraps
# its comment across different line breaks and is asserted clean; this makes the
# tolerance explicit rather than incidental, by rewrapping it differently again.
REWRAPPED="$WORK/rewrapped"
record "$REWRAPPED" '  /* Half away from zero, stated
     for negatives
     because a credit is one. */
  function roundToQuarter(hours) {
    return Math.round(hours / 0.25) * 0.25;
  }
'
check_exit "the same sentence wrapped differently is not drift" 0 status_on "$REWRAPPED"

# A COMMENT REMOVED ENTIRELY is the same fault as one reworded: the design file
# then records no reason at all for a rule whose reason is the decision.
STRIPPED="$WORK/stripped"
record "$STRIPPED" '  function roundToQuarter(hours) {
    return Math.round(hours / 0.25) * 0.25;
  }
'
check_exit "a copy that drops the reasoning altogether is refused" 1 status_on "$STRIPPED"
check "and named the same way, because it is the same loss" \
    "$(run_on "$STRIPPED" | grep -c 'REASONING DRIFTED')" "1"

# ---------------------------------------------------------------------------
# A RULE TWO SCREENS RUN (ovation#413). The invoice screen and the invoice PDF
# write one duration with one rule, and the agreement between the two is the
# whole of the decision. "Carried verbatim by at least one design file" cannot
# hold that: the PDF's copy would answer for the screen's, and the screen could
# drift with the guard green. So a rule NAMES the files that run it, and each
# named file is held to it on its own.
# ---------------------------------------------------------------------------
SHARED_RULE='/* CARRIED BY: invoice.html, invoice-pdf.html */

function roundToQuarter(hours) {
  return Math.round(hours / 0.25) * 0.25;
}
'
SHARED_INLINED='  /* CARRIED BY: invoice.html, invoice-pdf.html */
  function roundToQuarter(hours) {
    return Math.round(hours / 0.25) * 0.25;
  }
'
shared_record() {
    # $1 root, $2 invoice.html's script, $3 invoice-pdf.html's script
    mkdir -p "$1/rules"
    printf '%s' "$SHARED_RULE" > "$1/rules/duration.js"
    { printf '<meta charset="utf-8">\n<script>\n%s</script>\n' "$2"; } > "$1/invoice.html"
    { printf '<meta charset="utf-8">\n<script>\n%s</script>\n' "$3"; } > "$1/invoice-pdf.html"
}

BOTH="$WORK/both"
shared_record "$BOTH" "$SHARED_INLINED" "$SHARED_INLINED"
check "a rule carried verbatim by every file it names passes" "$(status_on "$BOTH")" "0"

# invoice-pdf.html sorts first and carries the rule exactly, so a guard that
# stops at the first verbatim copy never reads invoice.html at all.
SCREENDRIFT="$WORK/screendrift"
shared_record "$SCREENDRIFT" '  /* CARRIED BY: invoice.html, invoice-pdf.html */
  function roundToQuarter(hours) {
    return Math.round(hours / 0.5) * 0.5;
  }
' "$SHARED_INLINED"
check "one named file drifting is refused although another carries it exactly" \
    "$(status_on "$SCREENDRIFT")" "1"
check "and the refusal names the file that drifted" \
    "$(run_on "$SCREENDRIFT" | grep 'DRIFTED' | grep -c 'invoice.html')" "1"
check "and does not blame the file that is right" \
    "$(run_on "$SCREENDRIFT" | grep 'DRIFTED' | grep -c 'invoice-pdf.html')" "0"

SCREENMISSING="$WORK/screenmissing"
shared_record "$SCREENMISSING" '  var unrelated = 1;
' "$SHARED_INLINED"
check "a named file carrying none of the rule is refused" \
    "$(status_on "$SCREENMISSING")" "1"
check "and says the named file does not carry it" \
    "$(run_on "$SCREENMISSING" | grep 'NOT INLINE' | grep -c 'invoice.html')" "1"

# A DECLARATION NAMING A FILE THAT IS NOT THERE holds nothing, and reading as a
# declaration it would be believed (L1004).
NOSUCH="$WORK/nosuch"
shared_record "$NOSUCH" "$SHARED_INLINED" "$SHARED_INLINED"
rm "$NOSUCH/invoice-pdf.html"
check "a rule naming a design file that does not exist is refused" \
    "$(status_on "$NOSUCH")" "1"
check "and says that file is not in the record" \
    "$(run_on "$NOSUCH" | grep -c 'invoice-pdf.html is not in the design record')" "1"

# ---------------------------------------------------------------------------
# The real record, so the seam is not the only thing ever exercised.
# ---------------------------------------------------------------------------
check_exit "the real design record carries its rules verbatim" \
    0 env OVATION_DESIGN_ROOT= "./$TARGET"

harness_end
