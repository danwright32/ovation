#!/bin/bash
# The suite for scripts/check-design-shell-inline.sh.
#
# ovation#120. `docs/design/invoice-list.html`, `docs/design/clients.html` and
# `docs/design/invoice.html` all carry the same shell: the embedded typefaces,
# the record page they are written on, and the macOS window with its menu bar,
# espresso sidebar, title bar and palette. Each file got that shell by copying
# the last one, and nothing said what the shell WAS, so every copy was judged by
# whether the result looked right.
#
# IT HAD ALREADY GONE WRONG TWICE, in one session, and neither fault was visible
# by looking. The whole screen rendered in the system typeface, because the
# settled type lives on a `body` rule and the shell was lifted without its page
# chrome. And `.nrow`, already the Clients names column, was reused by the
# narrowed invoice list, so a bare rule in the settled sheet reached rows it was
# never written for. Both still LOOKED finished.
#
# So the shell is now one source under `docs/design/shell/`, and because
# ovation#114 forbids a design file reaching outside itself, each file carries a
# VERBATIM copy rather than a `<link>`. That is the same shape as the rules in
# ovation#111, and this guard is the same guard: it compares each part against
# each file as a CONTIGUOUS run of lines, never as lines that merely all occur
# somewhere (L178), because a shell whose lines are present but interleaved is a
# shell the file does not actually run.
#
# A file that legitimately does not carry a part says so IN ITS OWN WORDS, with
# the reason, rather than being named in a list of exemptions kept here (L362).
# `invoice-pdf.html` is the case: it is paper, and it has no app window at all.
# A declaration that is CONTRADICTED by the file carrying the part anyway is its
# own refusal, because an exemption that outlives its reason reads as a decision
# and is never revisited.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design shell inlining tests" 22

TARGET="scripts/check-design-shell-inline.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_on() { OVATION_DESIGN_ROOT="$1" "./$TARGET" 2>&1; }
status_on() {
    OVATION_DESIGN_ROOT="$1" "./$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

# The shell part, as it sits under shell/. It carries a comment and a blank line
# on purpose: a design file pastes this inside a <style> at its own indent and
# rewraps the prose, so a comparison that broke on either could only ever match
# by luck.
PART='/* The window, which is the same in every file that draws one. */

.win {
  width: 1064px;
  border-radius: 10px;
}
'

# The same part as a design file carries it: indented, comment rewrapped.
INLINED='  /* The window, which is the same
     in every file that draws one. */
  .win {
    width: 1064px;
    border-radius: 10px;
  }
'

record() {
    # $1 destination root, $2 what goes inside the design file's <style>
    mkdir -p "$1/shell"
    printf '%s' "$PART" > "$1/shell/window.css"
    { printf '<meta charset="utf-8">\n<style>\n'
      printf '%s' "$2"
      printf '</style>\n'
    } > "$1/invoice.html"
}

# ---------------------------------------------------------------------------
# The healthy record: the part is carried verbatim.
# ---------------------------------------------------------------------------
GOOD="$WORK/good"
record "$GOOD" "$INLINED"
check "a shell part carried verbatim by a design file passes" "$(status_on "$GOOD")" "0"
check "and it says how many parts it actually compared" \
    "$(run_on "$GOOD" | grep -c '1 shell part')" "1"
check "and it names the design file it checked" \
    "$(run_on "$GOOD" | grep -c 'invoice.html')" "1"

# ---------------------------------------------------------------------------
# THE CASE THE GUARD EXISTS FOR: the shell was corrected and one file's copy of
# it was not, which is how four copies drift while every file still renders.
# ---------------------------------------------------------------------------
DRIFT="$WORK/drift"
record "$DRIFT" '  .win {
    width: 1120px;
    border-radius: 10px;
  }
'
check "a design file whose copy of the shell has drifted is refused" \
    "$(status_on "$DRIFT")" "1"
check "and the refusal says DRIFTED rather than something generic" \
    "$(run_on "$DRIFT" | grep -c 'DRIFTED')" "1"
check "and it names the shell part that drifted" \
    "$(run_on "$DRIFT" | grep -c 'window.css')" "1"
check "and it says which line of the part the copy stopped matching at" \
    "$(run_on "$DRIFT" | grep -cE 'line [0-9]+')" "1"

ONELINE="$WORK/oneline"
record "$ONELINE" '  .win {
    width: 1064px;
    overflow: hidden;
    border-radius: 10px;
  }
'
check "one extra declaration inside the part is still a drift" \
    "$(status_on "$ONELINE")" "1"

# ---------------------------------------------------------------------------
# THE CASE THAT PROVES THE MATCH IS CONTIGUOUS. Every line of the part is in this
# file and none of them is in the right place, so a containment check would call
# it correct (L178).
# ---------------------------------------------------------------------------
SCATTERED="$WORK/scattered"
record "$SCATTERED" '  .win {
  .somethingElse { color: red; }
    width: 1064px;
  .andAnother { color: blue; }
    border-radius: 10px;
  }
'
check "a part whose lines are all present but scattered is refused" \
    "$(status_on "$SCATTERED")" "1"

# ---------------------------------------------------------------------------
# A file carrying none of the part. A different fault from a drift, with a
# different remedy, so it gets its own word (L11).
# ---------------------------------------------------------------------------
ABSENT="$WORK/absent"
record "$ABSENT" '  .unrelated { color: red; }
'
check "a design file carrying none of a shell part is refused" \
    "$(status_on "$ABSENT")" "1"
check "and it says MISSING, which is not the same fault as a drift" \
    "$(run_on "$ABSENT" | grep -c 'MISSING')" "1"
check "and it does not also claim the copy drifted" \
    "$(run_on "$ABSENT" | grep -c 'DRIFTED')" "0"

# ---------------------------------------------------------------------------
# The file that legitimately has no app window says so itself, with its reason.
# invoice-pdf.html is paper. The escape is a sentence in the file, never a list
# of exempt filenames in this guard (L362).
# ---------------------------------------------------------------------------
DECLARED="$WORK/declared"
record "$DECLARED" '  .unrelated { color: red; }
'
printf '<style>\n/* NOT SHELLED: window.css, this is paper and draws no app window. */\n.unrelated { color: red; }\n</style>\n' \
    > "$DECLARED/invoice.html"
check "a design file saying why it carries no app window passes" \
    "$(status_on "$DECLARED")" "0"
check "and the pass still reports it rather than counting it as carried" \
    "$(run_on "$DECLARED" | grep -c 'NOT SHELLED')" "1"

# A declaration the file then contradicts by carrying the part anyway. The
# exemption has outlived its reason, and left alone it reads as a decision
# nobody revisits.
STALE="$WORK/stale"
record "$STALE" "$INLINED"
{ printf '<meta charset="utf-8">\n<style>\n'
  printf '/* NOT SHELLED: window.css, this is paper and draws no app window. */\n'
  printf '%s' "$INLINED"
  printf '</style>\n'
} > "$STALE/invoice.html"
check "a file that declares it has no shell and then carries it is refused" \
    "$(status_on "$STALE")" "1"
check "and the refusal says the declaration is the stale part" \
    "$(run_on "$STALE" | grep -c 'STALE')" "1"

# ---------------------------------------------------------------------------
# Nothing to compare is not a pass, and the three ways of having nothing are
# three different failures with three different remedies (L11, L98).
# ---------------------------------------------------------------------------
check "a missing design root cannot measure" "$(status_on "$WORK/nowhere")" "2"

NOSHELL="$WORK/noshell"
mkdir -p "$NOSHELL"
printf '<meta charset="utf-8">\n' > "$NOSHELL/invoice.html"
check "a record with no shell at all cannot measure" "$(status_on "$NOSHELL")" "2"
check "and says the shell is missing, not that the files agree with it" \
    "$(run_on "$NOSHELL" | grep -c 'CANNOT SCAN')" "1"

NOHTML="$WORK/nohtml"
mkdir -p "$NOHTML/shell"
printf '%s' "$PART" > "$NOHTML/shell/window.css"
check "a record with a shell but no design files cannot measure" \
    "$(status_on "$NOHTML")" "2"
check "and names that as its own cause" \
    "$(run_on "$NOHTML" | grep -c 'no design file')" "1"

# ---------------------------------------------------------------------------
# The real record, so the seam is not the only thing ever exercised.
# ---------------------------------------------------------------------------
check "the real design record carries its shell verbatim" \
    "$(OVATION_DESIGN_ROOT= "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "0"

harness_end
