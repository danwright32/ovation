#!/bin/bash
# Whether a pull request description that closes an issue as ovation#N is refused.
#
# ovation#261. Everything in this repository names issues as `ovation#N`, so pull
# request descriptions wrote `Closes ovation#N`. GitHub reads a closing keyword
# only before `#N` or `owner/repo#N`, so the issue stayed open after the merge and
# nothing said so: #245 left ovation#232 open with its code shipped, #251 left
# ovation#247 and ovation#231, #256 left ovation#252 and ovation#254, and
# ovation#232 was then offered as the next issue to work on (L468, L346).
#
# The push gate cannot see a description, so the check reads one handed to it,
# and every case here hands it a file rather than asking GitHub (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "pull request closing keyword tests" 27

TARGET="scripts/check-pr-closing-keywords.sh"
require_target "$TARGET"
harness_temp_dir WORK

# body <text>: a description file holding exactly the text given.
n=0
body() { n=$((n+1)); printf '%s\n' "$1" > "$WORK/body-$n.md"; printf '%s' "$WORK/body-$n.md"; }
run_on() { OVATION_PR_BODY_FILE="$1" "./$TARGET" 2>&1; }
status_on() { run_on "$1" >/dev/null 2>&1; printf '%s' "$?"; }
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE SPELLING GITHUB READS PASSES, and it is produced first, or every refusal
#    below is satisfied by a check that refuses everything (L159).
# ---------------------------------------------------------------------------
GOOD="$(body 'Closes #1.')"
check "Closes #1 passes" "$(status_on "$GOOD")" "0"
check "and it says how many closing references it read" \
    "$(says "$(run_on "$GOOD")" "1 closing reference")" "yes"

BOTH_GOOD="$(body 'Closes #236. Closes #281.')"
check "two closing references in the spelling GitHub reads pass" "$(status_on "$BOTH_GOOD")" "0"

FULL="$(body 'Fixes danwright32/ovation#12.')"
check "the owner/repo#N spelling passes, because GitHub reads it too" "$(status_on "$FULL")" "0"

# ---------------------------------------------------------------------------
# 2. THE SPELLING THAT LEFT FIVE ISSUES OPEN.
# ---------------------------------------------------------------------------
BAD="$(body 'Closes ovation#1')"
OUT_BAD="$(run_on "$BAD")"
check "Closes ovation#1 is refused" "$(status_on "$BAD")" "1"
check "and it names the reference it refused" "$(says "$OUT_BAD" "Closes ovation#1")" "yes"
check "and it gives the spelling GitHub reads, rather than describing it (L399)" \
    "$(says "$OUT_BAD" "Closes #1")" "yes"

# EVERY KEYWORD GitHub documents, in every tense, and in any case.
for keyword in close closes closed fix fixes fixed resolve resolves resolved; do
    f="$(body "This $keyword ovation#7 today.")"
    [ "$(status_on "$f")" = "1" ] || MISSED="${MISSED:-}${keyword} "
done
check "every closing keyword before ovation#N is refused" "${MISSED:-}" ""
check "and case does not hide one" "$(status_on "$(body 'FIXES ovation#7')")" "1"
# GitHub reads `Closes: #N` as well, so the colon form of the mistake is the same
# mistake.
check "and neither does a colon after the keyword" "$(status_on "$(body 'Resolves: ovation#7')")" "1"

# EVERY ONE, NOT THE FIRST. A refusal naming one of three teaches whoever fixes it
# that there was one (L30).
MANY="$(body 'Closes ovation#247. Closes ovation#231.
Also fixes ovation#9.')"
check "every refused reference is named, not only the first" \
    "$(run_on "$MANY" | grep -c 'write Closes #247\|write Closes #231\|write fixes #9')" "3"

# A mixed description is refused for the half that is wrong.
check "one right and one wrong reference is still refused" \
    "$(status_on "$(body 'Closes #252. Closes ovation#254.')")" "1"

# ---------------------------------------------------------------------------
# 3. WHAT IT MUST NOT REFUSE. A description names issues as ovation#N all the
#    time without closing them, and a check that refused prose would be one
#    people learn to route around (L104, L36).
# ---------------------------------------------------------------------------
check "an ovation#N reference with no closing keyword passes" \
    "$(status_on "$(body 'This follows ovation#155 and ovation#214.')")" "0"
check "a keyword that is only part of a longer word does not count" \
    "$(status_on "$(body 'The prefixes ovation#3 and the enclosed ovation#4 are prose.')")" "0"
check "a keyword far from the reference does not count" \
    "$(status_on "$(body 'This fixes the gate that ovation#5 described.')")" "0"
# ovation#486. A SENTENCE SAYING AN ISSUE STAYS OPEN IS NOT AN ATTEMPT TO CLOSE IT.
# PR ovation#484 was refused for "It does not close ovation#457, which still owes
# ...": a guard matching the phrase anywhere fires on prose that talks about it
# (L673), and the prose it fired on is the good habit of naming the issue a slice
# leaves open.
check "a keyword a negation stands in front of does not count" \
    "$(status_on "$(body 'It does not close ovation#457, which still owes the line item control.')")" "0"
check "and neither does never, or a contraction" \
    "$(status_on "$(body "This never fixes ovation#3, and it won't resolve ovation#4 either.")")" "0"
check "and it is not counted as a closing reference it read" \
    "$(says "$(run_on "$(body 'It does not close ovation#457.')")" "0 closing reference")" "yes"
# THE STAND DOWN IS NO BROADER THAN ITS REASON (L324). GitHub reads a keyword
# anywhere in the description, mid sentence included, so an affirmative one there
# is still refused: narrowing to the start of a line would pass exactly this.
check "an affirmative keyword mid sentence is still refused" \
    "$(status_on "$(body 'This change closes ovation#12 once it lands.')")" "1"
check "and a negation elsewhere in the description does not excuse another reference" \
    "$(status_on "$(body "It does not close ovation#457. Closes ovation#458.")")" "1"
check "a description with no closing reference at all passes, and says it read none" \
    "$(says "$(run_on "$(body 'A change with nothing to close.')")" "0 closing reference")" "yes"

# ---------------------------------------------------------------------------
# 4. CANNOT MEASURE. No description to read proves nothing about one (L98).
# ---------------------------------------------------------------------------
check "no description file given cannot be measured" \
    "$(OVATION_PR_BODY_FILE="" "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "a description file that is not there cannot be measured" \
    "$(status_on "$WORK/no-such-body.md")" "2"
check "and it says so rather than passing" \
    "$(says "$(run_on "$WORK/no-such-body.md")" "CANNOT MEASURE")" "yes"
# AN EMPTY DESCRIPTION IS A REAL DESCRIPTION. GitHub sends an empty body for a
# pull request with none, and it closes nothing, so it passes.
check "an empty description passes, because it closes nothing" \
    "$(status_on "$(body '')")" "0"

# ---------------------------------------------------------------------------
# 5. THE WORKFLOW RUNS IT, ON THE EVENTS THAT CHANGE A DESCRIPTION. A check on
#    `opened` alone would never see the description once somebody corrected it.
# ---------------------------------------------------------------------------
WF=".github/workflows/pr-description.yml"
check "a workflow runs the check" "$(grep -c 'scripts/check-pr-closing-keywords.sh' "$WF" 2>/dev/null)" "1"
check "and it runs again when the description is edited" \
    "$(grep -cE 'types:.*edited' "$WF" 2>/dev/null)" "1"

harness_end
