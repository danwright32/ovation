#!/bin/bash
# The suite for scripts/check-prd-citations.sh.
#
# ovation#199. The repository cites PRD requirements several hundred times, in
# two forms: `PRD 5.14a`, section qualified, and `PRD 14a`, which resolves to
# section 5 because the numbered requirements sit under `## 5. What Ovation must
# do`. Nothing verified that any of them named a requirement that is there.
#
# A WRONG CITATION IS WORSE THAN A DANGLING LINK. A reader follows it, finds a
# number, and reads whatever is at it, coming away believing the requirement says
# something. So existence is what this checks, and the limit is stated on the
# check itself: a citation resolving to a REAL requirement that says something
# else passes, which is the fault that happened on 2026-09-10 and no checker of
# this kind can catch.
#
# THE FIXTURES ARE THROWAWAY GIT REPOSITORIES because the check enumerates with
# `git ls-files` and that is its ONE enumeration path. A suite driving a second,
# walk-the-directory path would leave the path that actually ships exercised only
# by the committed tree (L101).
#
# EACH REFUSAL IS ASSERTED BY NAME. A defect big enough to break parsing makes
# every case refuse at once and is indistinguishable from the one that should
# have (L154), so no case here asserts merely that it refused.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "every PRD citation names a requirement that exists" 23

TARGET="scripts/check-prd-citations.sh"
require_target "$TARGET"
require_target "PRD.md"
# THIS SUITE MAY NOT SPELL A BROKEN CITATION. It plants deliberately wrong ones,
# and the check scans every file git tracks, this one included, so a literal here
# is refused by the very check it drives. It is the same shape as a style gate
# that cannot tell the line banning a character from the line using it, and the
# check's own docstring records why an exemption list is the wrong answer. So the
# word and the number are composed rather than written adjacent.
C="PRD"
CHECK="$PWD/$TARGET"
REAL_PRD="$PWD/PRD.md"
harness_temp_dir WORK

# A throwaway repository holding the real PRD.md and one cited file, so every
# case differs from the committed tree only in the citation it plants.
fixture() {
    local name="$1" body="$2" prd="${3:-$REAL_PRD}"
    local dir="$WORK/$name"
    mkdir -p "$dir"
    [ "$prd" = "none" ] || cp "$prd" "$dir/PRD.md"
    printf '%s\n' "$body" > "$dir/notes.md"
    ( cd "$dir" && git init -q -b main . && git add -A ) >/dev/null 2>&1
    printf '%s' "$dir"
}

run_on() { ( "$CHECK" "$1" 2>&1 ); }

# 1. THE COMMITTED TREE PASSES. A suite that only ever runs against planted
#    defects never proves the check passes anything real.
OUT="$("$CHECK" 2>&1)"; RC=$?
check "the committed tree's citations all resolve" "$RC" "0"
case "$OUT" in
    *citation*) check "it says how many citations it checked" "yes" "yes" ;;
    *) check "it says how many citations it checked" "$OUT" "should count the citations" ;;
esac

# 2. A BARE TOKEN NAMING NOTHING. Section 5 stops at 52g.
D="$(fixture dangling "The rule is stated at $C 999.")"
OUT="$(run_on "$D")"; RC=$?
check "a bare citation naming no requirement is refused" "$RC" "1"
case "$OUT" in
    *notes.md*) check "it names the file the bad citation is in" "yes" "yes" ;;
    *) check "it names the file the bad citation is in" "$OUT" "should say notes.md" ;;
esac
case "$OUT" in
    *:1*) check "it names the line the bad citation is on" "yes" "yes" ;;
    *) check "it names the line the bad citation is on" "$OUT" "should give a line number" ;;
esac
case "$OUT" in
    *999*) check "it names the citation that resolved to nothing" "yes" "yes" ;;
    *) check "it names the citation that resolved to nothing" "$OUT" "should say 999" ;;
esac

# 3. A SECTION QUALIFIED TOKEN NAMING NOTHING. Section 9 stops at 16.
D="$(fixture qualified "See $C 9.99 for the answer.")"
OUT="$(run_on "$D")"; RC=$?
check "a qualified citation naming no requirement is refused" "$RC" "1"
case "$OUT" in
    *9.99*) check "it names the qualified citation" "yes" "yes" ;;
    *) check "it names the qualified citation" "$OUT" "should say 9.99" ;;
esac

# 4. AN UNQUALIFIED TOKEN RESOLVES TO SECTION 5, and the proof is a requirement
#    that exists ONLY there.
D="$(fixture unqualified 'See PRD 52g for the vocabulary.')"
run_on "$D" >/dev/null; check "a bare token resolves against section 5" "$?" "0"

# 5. AND THE QUALIFIER IS HONOURED rather than being read as "any section". The
#    same requirement, asked for in a section that does not hold it, is refused.
D="$(fixture wrongsection "See $C 9.52g for the vocabulary.")"
OUT="$(run_on "$D")"; RC=$?
check "the same requirement in the wrong section is refused" "$RC" "1"
case "$OUT" in
    *9.52g*) check "it names the wrongly qualified citation" "yes" "yes" ;;
    *) check "it names the wrongly qualified citation" "$OUT" "should say 9.52g" ;;
esac

# 6. A REQUIREMENT WHOSE LABEL CARRIES A DIGIT AFTER ITS LETTER. `5a0` is real,
#    and a parser reading a number then letters stops before the 0, resolves the
#    citation to `5a`, and reports a real requirement as missing. That is not a
#    hypothetical: the throwaway parser written while measuring this issue did
#    exactly that and named 5a0 as the first dangling citation in the repo.
D="$(fixture digitsuffix 'See PRD 5a0 for what cannot be re-derived.')"
run_on "$D" >/dev/null; check "a requirement labelled 5a0 resolves" "$?" "0"

# 7. A CONTINUATION IN A LIST IS A CITATION. The one real defect in the tree was
#    written as a section qualifier, `and`, and a second number, and a check
#    reading only the token after the word PRD would have had the first half
#    fixed and left the second dangling with nothing able to say so.
D="$(fixture continuation "Recorded at $C 5.3 and 5.999 as agreed.")"
OUT="$(run_on "$D")"; RC=$?
check "a dangling continuation citation is refused" "$RC" "1"
case "$OUT" in
    *5.999*) check "it names the continuation that resolved to nothing" "yes" "yes" ;;
    *) check "it names the continuation that resolved to nothing" "$OUT" "should say 5.999" ;;
esac

# 8. AND A LEGITIMATE CONTINUATION IS NOT REFUSED, or the rule above would be
#    bought by refusing most of the real citations in the tree.
D="$(fixture goodlist 'Recorded at PRD 5.3, 5.3a and 14h as agreed.')"
run_on "$D" >/dev/null; check "a continuation naming real requirements passes" "$?" "0"

# 9. NO PRD TO READ IS NOT A PASS.
D="$(fixture noprd 'See PRD 3.' none)"
OUT="$(run_on "$D")"; RC=$?
check "a tree with no PRD.md cannot be measured" "$RC" "2"
case "$OUT" in
    *"CANNOT MEASURE"*) check "it says it could not measure, rather than passing" "yes" "yes" ;;
    *) check "it says it could not measure, rather than passing" "$OUT" "should say CANNOT MEASURE" ;;
esac

# 10. A PRD DECLARING NO REQUIREMENTS IS NOT A PASS EITHER. A parser that quietly
#     matches nothing resolves every citation against an empty set and would
#     refuse the whole tree, or, worse, pass it (L215).
printf '# A PRD with no numbered requirements\n\nProse only.\n' > "$WORK/empty-prd.md"
D="$(fixture noreqs 'See PRD 3.' "$WORK/empty-prd.md")"
OUT="$(run_on "$D")"; RC=$?
check "a PRD declaring no requirements cannot be measured" "$RC" "2"
case "$OUT" in
    *requirement*) check "it says the PRD declared no requirements" "yes" "yes" ;;
    *) check "it says the PRD declared no requirements" "$OUT" "should name the empty requirement list" ;;
esac

# 11b. A TRACKED FILE THAT CANNOT BE OPENED IS NOT A BINARY. Both used to be
#      counted together and neither was mentioned unless the run passed, so a
#      file whose citations went unchecked was indistinguishable from a PNG
#      (L11). It is reported on EVERY path and it refuses, because a verdict on
#      the whole tree made from part of it is a claim nothing measured.
D="$(fixture unopenable "Recorded at $C 5.3 as agreed.")"
printf 'Recorded at %s 5.3 as agreed.\n' "$C" > "$D/locked.md"
( cd "$D" && git add -A ) >/dev/null 2>&1
chmod 000 "$D/locked.md"
OUT="$(run_on "$D")"; RC=$?
chmod 644 "$D/locked.md"
check "a tracked file that cannot be opened cannot be measured" "$RC" "2"
case "$OUT" in
    *locked.md*) check "and it names the file it could not open" "yes" "yes" ;;
    *) check "and it names the file it could not open" "$OUT" "should say locked.md" ;;
esac

# 11. FINDING NO CITATIONS AT ALL IS ITS OWN OUTCOME. A tree citing nothing and a
#     scan that has stopped matching produce the same silence (L98, L100).
D="$(fixture nocitations 'This file cites nothing at all.')"
OUT="$(run_on "$D")"; RC=$?
check "a tree holding no citations cannot be measured" "$RC" "2"
case "$OUT" in
    *citation*) check "it says no citations were found" "yes" "yes" ;;
    *) check "it says no citations were found" "$OUT" "should name the empty scan" ;;
esac

harness_end
