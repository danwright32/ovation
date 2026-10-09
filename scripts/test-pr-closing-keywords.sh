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
harness_begin "pull request closing keyword tests" 54

TARGET="scripts/check-pr-closing-keywords.sh"
require_target "$TARGET"
harness_temp_dir WORK

# body <text>: a description file holding exactly the text given.
n=0
body() { n=$((n+1)); printf '%s\n' "$1" > "$WORK/body-$n.md"; printf '%s' "$WORK/body-$n.md"; }
run_on() { OVATION_PR_BODY_FILE="$1" "./$TARGET" 2>&1; }
status_on() { run_on "$1"; }
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE SPELLING GITHUB READS PASSES, and it is produced first, or every refusal
#    below is satisfied by a check that refuses everything (L159).
# ---------------------------------------------------------------------------
GOOD="$(body 'Closes #1.')"
check_exit "Closes #1 passes" 0 status_on "$GOOD"
check "and it says how many closing references it read" \
    "$(says "$(run_on "$GOOD")" "1 closing reference")" "yes"

BOTH_GOOD="$(body 'Closes #236. Closes #281.')"
check_exit "two closing references in the spelling GitHub reads pass" 0 status_on "$BOTH_GOOD"

FULL="$(body 'Fixes danwright32/ovation#12.')"
check_exit "the owner/repo#N spelling passes, because GitHub reads it too" 0 status_on "$FULL"

# ---------------------------------------------------------------------------
# 2. THE SPELLING THAT LEFT FIVE ISSUES OPEN.
# ---------------------------------------------------------------------------
BAD="$(body 'Closes ovation#1')"
OUT_BAD="$(run_on "$BAD")"
check_exit "Closes ovation#1 is refused" 1 status_on "$BAD"
check "and it names the reference it refused" "$(says "$OUT_BAD" "Closes ovation#1")" "yes"
check "and it gives the spelling GitHub reads, rather than describing it (L399)" \
    "$(says "$OUT_BAD" "Closes #1")" "yes"

# EVERY KEYWORD GitHub documents, in every tense, and in any case.
for keyword in close closes closed fix fixes fixed resolve resolves resolved; do
    f="$(body "This $keyword ovation#7 today.")"
    said="$(status_on "$f" 2>&1)"; [ "$?" = "1" ] || MISSED="${MISSED:-}${keyword} "
done
check "every closing keyword before ovation#N is refused" "${MISSED:-}" ""
check_exit "and case does not hide one" 1 status_on "$(body 'FIXES ovation#7')"
# GitHub reads `Closes: #N` as well, so the colon form of the mistake is the same
# mistake.
check_exit "and neither does a colon after the keyword" 1 status_on "$(body 'Resolves: ovation#7')"

# EVERY ONE, NOT THE FIRST. A refusal naming one of three teaches whoever fixes it
# that there was one (L30).
MANY="$(body 'Closes ovation#247. Closes ovation#231.
Also fixes ovation#9.')"
check "every refused reference is named, not only the first" \
    "$(run_on "$MANY" | grep -c 'write Closes #247\|write Closes #231\|write fixes #9')" "3"

# A mixed description is refused for the half that is wrong.
check_exit "one right and one wrong reference is still refused" \
    1 status_on "$(body 'Closes #252. Closes ovation#254.')"

# ---------------------------------------------------------------------------
# 3. WHAT IT MUST NOT REFUSE. A description names issues as ovation#N all the
#    time without closing them, and a check that refused prose would be one
#    people learn to route around (L104, L36).
# ---------------------------------------------------------------------------
check_exit "an ovation#N reference with no closing keyword passes" \
    0 status_on "$(body 'This follows ovation#155 and ovation#214.')"
check_exit "a keyword that is only part of a longer word does not count" \
    0 status_on "$(body 'The prefixes ovation#3 and the enclosed ovation#4 are prose.')"
check_exit "a keyword far from the reference does not count" \
    0 status_on "$(body 'This fixes the gate that ovation#5 described.')"
# ovation#486. A SENTENCE SAYING AN ISSUE STAYS OPEN IS NOT AN ATTEMPT TO CLOSE IT.
# PR ovation#484 was refused for "It does not close ovation#457, which still owes
# ...": a guard matching the phrase anywhere fires on prose that talks about it
# (L673), and the prose it fired on is the good habit of naming the issue a slice
# leaves open.
check_exit "a keyword a negation stands in front of does not count" \
    0 status_on "$(body 'It does not close ovation#457, which still owes the line item control.')"
check_exit "and neither does never, or a contraction" \
    0 status_on "$(body "This never fixes ovation#3, and it won't resolve ovation#4 either.")"
check "and it is not counted as a closing reference it read" \
    "$(says "$(run_on "$(body 'It does not close ovation#457.')")" "0 closing reference")" "yes"
# THE STAND DOWN IS NO BROADER THAN ITS REASON (L324). GitHub reads a keyword
# anywhere in the description, mid sentence included, so an affirmative one there
# is still refused: narrowing to the start of a line would pass exactly this.
check_exit "an affirmative keyword mid sentence is still refused" \
    1 status_on "$(body 'This change closes ovation#12 once it lands.')"
check_exit "and a negation elsewhere in the description does not excuse another reference" \
    1 status_on "$(body "It does not close ovation#457. Closes ovation#458.")"
# AND A NEGATION BESIDE A REFERENCE GITHUB DOES READ IS REFUSED, the other way
# round. GitHub's parser does no negation handling at all, so "does not close #12"
# CLOSES #12 on merge: it closed Overture #897 on a pull request that said it did
# not. The ovation#N spelling above is harmless precisely because GitHub reads
# none of it; #N and owner/repo#N are read, "not" and all.
check_exit "a negated keyword before #N is refused, because GitHub closes it anyway" \
    1 status_on "$(body 'It does not close #457, which still owes the line item control.')"
check_exit "and so is one before owner/repo#N" \
    1 status_on "$(body 'This never fixes danwright32/ovation#3.')"
check "and the refusal says how to leave it open instead (L1018)" \
    "$(says "$(run_on "$(body 'It does not close #457.')")" "Part of #457")" "yes"
check "a description with no closing reference at all passes, and says it read none" \
    "$(says "$(run_on "$(body 'A change with nothing to close.')")" "0 closing reference")" "yes"

# ---------------------------------------------------------------------------
# 3a. A CLOSING KEYWORD GITHUB READS CLOSES WHATEVER ITS SENTENCE SAYS (ovation#683,
#     L1018). GitHub closes the issue for any keyword directly before #N or
#     owner/repo#N, so a negation further back in the sentence closes it just as
#     surely as one right before the keyword. Recognising negation cannot keep up
#     with English, so the rule is the shape GitHub's own reading gives: a
#     reference it reads stands in a sentence that holds nothing else.
# ---------------------------------------------------------------------------
for phrase in \
    'This does not yet close #12.' \
    "It doesn't fully fix #12." \
    'This is not meant to close #12.' \
    'Nothing here can fix #12, which needs the export.' \
    'A later pull request will resolve #12.' \
    'The work that will not by itself resolve danwright32/ovation#12 is here.'; do
    f="$(body "$phrase")"
    run_on "$f" > /dev/null; [ "$?" = "1" ] || WIDE_MISSED="${WIDE_MISSED:-}[$phrase] "
done
check "a closing keyword before #N inside a sentence saying something else is refused" \
    "${WIDE_MISSED:-}" ""
# A SENTENCE WRAPPED ACROSS LINES IS ONE SENTENCE. Commit messages are wrapped,
# and the line after the wrap looks exactly like a closing line on its own.
check_exit "a negation on the line before a wrapped keyword is still read with it" \
    1 status_on "$(body 'This change does not
close #12.')"
check_exit "and so is a keyword at the end of a line with its number on the next" \
    1 status_on "$(body 'This change does not close
#12 yet.')"
OUT_WIDE="$(run_on "$(body 'This does not yet close #12.')")"
check "the refusal names the reference" "$(says "$OUT_WIDE" "close #12")" "yes"
check "and gives both ways to write it: a closing line, or Part of" \
    "$(says "$OUT_WIDE" "Closes #12")$(says "$OUT_WIDE" "Part of #12")" "yesyes"

# THE FORMS THAT CLOSE ON PURPOSE, each produced, so the refusals above are not a
# check that refuses every keyword (L159). Each is a shape taken from this
# repository's own descriptions and commit messages.
check_exit "a closing sentence followed by prose on the same line passes" \
    0 status_on "$(body 'Closes #424. Also closes out the measurement #420 asked for.')"
check_exit "a negation in the next sentence does not touch the closing one" \
    0 status_on "$(body 'Fixes #12. This does not change the export.')"
check_exit "Part of #N passes, because it closes nothing" \
    0 status_on "$(body 'Part of #12, which still owes the line item control.')"
check_exit "closing lines in a list pass" \
    0 status_on "$(body '- Closes #1
- Fixes #2')"
check_exit "closing lines straight above unpunctuated prose pass" \
    0 status_on "$(body 'Closes #1
Closes #2
Adds the export')"
check_exit "a colon after the keyword on a closing line passes" \
    0 status_on "$(body 'Resolves: #7')"

# ---------------------------------------------------------------------------
# 4. CANNOT MEASURE. No description to read proves nothing about one (L98).
# ---------------------------------------------------------------------------
check_exit "no description file given cannot be measured" \
    2 env OVATION_PR_BODY_FILE="" "./$TARGET"
check_exit "a description file that is not there cannot be measured" \
    2 status_on "$WORK/no-such-body.md"
check "and it says so rather than passing" \
    "$(says "$(run_on "$WORK/no-such-body.md")" "CANNOT MEASURE")" "yes"
# AN EMPTY DESCRIPTION IS A REAL DESCRIPTION. GitHub sends an empty body for a
# pull request with none, and it closes nothing, so it passes.
check_exit "an empty description passes, because it closes nothing" \
    0 status_on "$(body '')"

# ---------------------------------------------------------------------------
# 5. THE WORKFLOW RUNS IT, ON THE EVENTS THAT CHANGE A DESCRIPTION. A check on
#    `opened` alone would never see the description once somebody corrected it.
# ---------------------------------------------------------------------------
WF=".github/workflows/pr-description.yml"
check "a workflow runs the check" "$(grep -c 'scripts/check-pr-closing-keywords.sh' "$WF" 2>/dev/null)" "1"
check "and it runs again when the description is edited" \
    "$(grep -cE 'types:.*edited' "$WF" 2>/dev/null)" "1"
check "and it hands the check the pull request number, so the commit messages are read" \
    "$(grep -c 'OVATION_PR_NUMBER="${PR_NUMBER}"' "$WF" 2>/dev/null)" "1"
check "with a token that may read the pull request" \
    "$(grep -c 'GH_TOKEN: ${{ github.token }}' "$WF" 2>/dev/null)$(grep -cE '^ *pull-requests: read' "$WF" 2>/dev/null)" "11"

# ---------------------------------------------------------------------------
# 6. THE COMMIT MESSAGES (ovation#683). This repository squash merges with the
#    commit messages as the squash body, so every branch commit message lands on
#    main, where GitHub reads its closing keywords too: commit b3d9f8d put "does
#    not close #12" on main. They are asked of GitHub through a stand in here, so
#    no case reaches it (L2).
# ---------------------------------------------------------------------------
FAKE="$WORK/gh"
cat > "$FAKE" <<'SH'
#!/bin/bash
echo "$*" >> "$FAKE_DIR/calls"
[ -f "$FAKE_DIR/fail" ] && { echo "HTTP 502" >&2; exit 1; }
case "$*" in
  *"/commits"*) cat "$FAKE_DIR/commits" ;;
  *"repos/danwright32/ovation/pulls/"*) cat "$FAKE_DIR/count" ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$FAKE"
# commits <message>...: the fake pull request carries exactly these commits.
commits() {
    : > "$WORK/commits"; rm -f "$WORK/fail"
    local i=0 m
    for m in "$@"; do
        i=$((i+1))
        printf 'abc%04d %s\n' "$i" "$(printf '%s' "$m" | perl -MMIME::Base64 -0777 -ne 'print encode_base64($_, "")')" >> "$WORK/commits"
    done
    printf '%s\n' "$i" > "$WORK/count"
}
run_pr() { FAKE_DIR="$WORK" OVATION_GH="$FAKE" OVATION_REPO=danwright32/ovation \
    OVATION_PR_NUMBER=7 OVATION_PR_BODY_FILE="$1" "./$TARGET" 2>&1; }
CLEAN_BODY="$(body 'Closes #683.')"

commits 'Add the export' 'Round the totals

Closes #683'
check_exit "clean commit messages pass" 0 run_pr "$CLEAN_BODY"
check "and it says how many commit messages it read" \
    "$(says "$(run_pr "$CLEAN_BODY")" "2 commit message")" "yes"

commits 'Add the export' 'Quote the lesson

GitHub reads "does not close #12" as closing it.'
OUT_COMMIT="$(run_pr "$CLEAN_BODY")"
check_exit "a commit message whose sentence holds a closing keyword is refused" 1 run_pr "$CLEAN_BODY"
check "and the refusal names the commit and the reference" \
    "$(says "$OUT_COMMIT" "abc0002")$(says "$OUT_COMMIT" "close #12")" "yesyes"
check "and says the squash merge carries it onto main and to reword it" \
    "$(says "$OUT_COMMIT" "reword")" "yes"
commits 'The booking for Hartwell at the Lyceum does not fix #12.'
check_exit "a refused commit naming a client is refused" 1 run_pr "$CLEAN_BODY"
check "and never prints the sentence around it (L222)" \
    "$(run_pr "$CLEAN_BODY" | grep -ciE 'Hartwell|Lyceum')" "0"

# FEWER MESSAGES THAN COMMITS is a partial read, not a pass (L288).
commits 'Add the export'; printf '3\n' > "$WORK/count"
check_exit "fewer messages read than the pull request has commits cannot be measured" \
    2 run_pr "$CLEAN_BODY"
commits 'Add the export'; : > "$WORK/fail"
OUT_FAIL="$(run_pr "$CLEAN_BODY")"
check_exit "GitHub failing to answer cannot be measured, rather than passing" 2 run_pr "$CLEAN_BODY"
check "and it says so" "$(says "$OUT_FAIL" "CANNOT MEASURE")" "yes"
# WITHOUT A NUMBER the commit messages are not read, and the verdict says so
# rather than claiming them (L440).
check "a run given no number says it did not read the commit messages" \
    "$(says "$(run_on "$CLEAN_BODY")" "commit messages not read")" "yes"

harness_end
