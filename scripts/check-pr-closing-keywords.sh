#!/bin/bash
# Refuse a pull request description that closes an issue as ovation#N.
#
# ovation#261. Everything in this repository names issues as `ovation#N`, so pull
# request descriptions wrote `Closes ovation#N`. GitHub reads a closing keyword
# only before `#N` or `owner/repo#N`, so the issue stayed open after the merge and
# nothing said so: #245 left ovation#232 open with its code shipped, #251 left
# ovation#247 and ovation#231, and #256 left ovation#252 and ovation#254.
# ovation#232 was then offered as the next issue to work on, which is what an
# issue left open after its work shipped does: it reads as work outstanding, and
# gets picked up, re-planned or duplicated (L346, L468).
#
# THE PUSH GATE CANNOT SEE A DESCRIPTION, so this is run by
# .github/workflows/pr-description.yml on every event that can change one, and
# the description is handed to it as a file. It never asks GitHub itself, so its
# suite drives every outcome with a file rather than a real pull request (L2).
#
# WHAT IT REFUSES is a closing keyword GitHub documents (close, closes, closed,
# fix, fixes, fixed, resolve, resolves, resolved, in any case, with or without a
# colon) followed directly by `ovation#N`. Prose that NAMES an issue as
# ovation#N without a keyword is how this repository writes, and a check that
# refused it would be one people learn to route around (L36). A keyword inside a
# longer word ("prefixes", "enclosed") is not a keyword.
#
# IT PRINTS THE REFERENCE AND ITS CORRECTED SPELLING, NEVER THE LINE AROUND IT.
# A description is prose about real work, which is exactly where a sentence
# naming a client sits, and this prints into the log of a repository that is
# public on purpose (L222).
#
# Outcomes:
#
#   0  every closing reference is one GitHub reads, or there are none
#   1  at least one closes as ovation#N, which GitHub does not read
#   2  CANNOT MEASURE: no description was handed to it
set -uo pipefail

BODY_FILE="${OVATION_PR_BODY_FILE:-}"

if [ -z "$BODY_FILE" ]; then
    echo "CANNOT MEASURE: no pull request description was given."
    echo "    Set OVATION_PR_BODY_FILE to a file holding it. Nothing was read, and"
    echo "    that is not a pass."
    exit 2
fi
if [ ! -f "$BODY_FILE" ]; then
    echo "CANNOT MEASURE: the description file $BODY_FILE is not there."
    echo "    Nothing was read, and that is not a pass (L98)."
    exit 2
fi

# ONE PATTERN FOR A CLOSING REFERENCE OF ANY SPELLING, so the count of what was
# read and the refusals come from the same reading (L16). The leading class stops
# a keyword matching inside a longer word; it is stripped off again below.
KEYWORD='(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)'
REFERENCE='([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+|[A-Za-z0-9_.-]+)?#[0-9]+'
# A NEGATED KEYWORD IS NOT A CLOSING ONE (ovation#486). "It does not close
# ovation#457" says the issue stays OPEN, and was refused as though it closed it:
# a guard matching a phrase anywhere fires on prose that talks about it (L673). A
# keyword directly after `not`, `never`, `nor` or a `n't` contraction is taken out
# before reading. Narrowing to the start of a line instead would be wrong, because
# GitHub reads a keyword anywhere, so an affirmative one mid sentence is still a
# closing reference and still refused (L324). Perl, because BSD sed has no case
# insensitive substitution; the apostrophe may be straight or curly.
READABLE="$(perl -pe 's/(\bnot|\bnever|\bnor|n(?:\x27|\xE2\x80\x99)t)(\s+)(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)\b/$1$2NEGATED/gi' "$BODY_FILE")" || {
    echo "CANNOT MEASURE: perl could not read $BODY_FILE, so nothing was checked."
    exit 2
}
REFS="$(printf '%s\n' "$READABLE" | grep -oiE "(^|[^A-Za-z0-9_])${KEYWORD}:?[[:space:]]+${REFERENCE}" \
    | sed -E 's/^[^A-Za-z]+//')"
REF_COUNT="$(printf '%s' "$REFS" | grep -c . || true)"

refused=0
while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    keyword="$(printf '%s' "$ref" | sed -E 's/^([A-Za-z]+).*/\1/')"
    target="$(printf '%s' "$ref" | sed -E 's/^[A-Za-z]+:?[[:space:]]+//')"
    # ONLY THE BARE SHORT NAME IS REFUSED. `danwright32/ovation#N` is the
    # owner/repo form GitHub reads, and it never reaches here as `ovation#N`
    # because the whitespace before the reference is required.
    if grep -qiE '^ovation#[0-9]+$' <<< "$target"; then
        number="${target##*#}"
        echo "  REFUSED  ${keyword} ovation#${number}: GitHub reads a closing keyword only before #N or owner/repo#N, so this leaves the issue open; write ${keyword} #${number}"
        refused=$((refused+1))
    fi
done <<< "$REFS"

echo "read ${REF_COUNT} closing reference(s) in the description"
if [ "$refused" -gt 0 ]; then
    echo "REFUSED: ${refused} closing reference(s) name the issue as ovation#N, which"
    echo "    GitHub does not read, so the issue would stay open after the merge with"
    echo "    nothing saying so (ovation#261). Edit the description; this check runs"
    echo "    again when it is edited."
    exit 1
fi
echo "OK: every closing reference is one GitHub reads."
exit 0
