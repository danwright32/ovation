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
# the description is handed to it as a file. The commit messages are asked of
# GitHub through OVATION_GH, so its suite drives every outcome with a file and a
# stand in for gh rather than a real pull request (L2).
#
# A CLOSING KEYWORD GITHUB READS CLOSES THE ISSUE WHATEVER ITS SENTENCE SAYS
# (ovation#683, L1018). GitHub's parser does no negation handling: "does not
# close #12", "does not yet close #12" and "a later pull request will resolve
# #12" all close #12 on merge (it closed Overture #897 on a pull request saying
# it did not). The first version of this refused only a negation DIRECTLY before
# the keyword, which passed "does not yet close", "doesn't fully fix", "not
# meant to close" and "cannot fix", because recognising negation is recognising
# English and never ends. So the rule is the shape of what GitHub does instead: a
# reference GitHub reads (#N or owner/repo#N after a keyword) must stand in a
# sentence holding nothing but closing references, which is the one spelling
# whose meaning and GitHub's reading cannot differ. A sentence runs across a
# wrapped line, because commit messages are wrapped and the line after the wrap
# ("close #12.") looks exactly like a closing line on its own. Measured before it
# shipped against all 203 pull request descriptions here and every commit message
# on main: no description is refused by it, "Closes #424. Also ..." included, and
# the one commit it refuses is b3d9f8d, whose three references (#95, #12 twice)
# are all prose GitHub read as closing.
#
# THE COMMIT MESSAGES TOO, because this repository squash merges with the commit
# messages as the squash body (squash_merge_commit_message COMMIT_MESSAGES), so
# every branch commit message lands on main, where GitHub reads its keywords as
# well: b3d9f8d put "does not close #12" on main. Only the sentence rule applies
# to them. The ovation#N rule below is about a description meant to close an
# issue and failing to, and a commit message is not where closing is decided.
# The number of messages read is compared with the number of commits GitHub says
# the pull request has, so a partial read is refused rather than passed (L288);
# GitHub lists at most 250, which a pull request here has never come near.
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
#   0  every closing reference is one GitHub reads, standing in a sentence of its
#      own, or there are none
#   1  at least one closes as ovation#N, which GitHub does not read, or one GitHub
#      reads sits in a sentence saying something else
#   2  CANNOT MEASURE: no description was handed to it, or the commit messages
#      could not be read in full
#
# OVATION_PR_NUMBER names the pull request whose commit messages are read. With
# none, only the description is read, and the verdict says so rather than
# claiming the commits (L440); the workflow always passes it, and its suite
# asserts that.
set -uo pipefail

BODY_FILE="${OVATION_PR_BODY_FILE:-}"
PR_NUMBER="${OVATION_PR_NUMBER:-}"
GH="${OVATION_GH:-gh}"
REPO="${OVATION_REPO:-${GITHUB_REPOSITORY:-danwright32/ovation}}"

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
# THE SENTENCE RULE, ONE IMPLEMENTATION FOR THE DESCRIPTION AND EVERY COMMIT
# MESSAGE (L16). It reads the text on stdin and prints one line per reference
# GitHub reads: `ok<TAB>keyword ref` when its sentence holds nothing else, and
# `refused<TAB>keyword ref` when it does. A paragraph is split into sentences at
# a terminator, a list item or heading, or a line that is itself only closing
# references; any other line break continues the sentence, which is how a
# wrapped "does not\nclose #12." is read as the one sentence it is.
SENTENCE_RULE='
my $t = do { local $/; <STDIN> }; $t = "" unless defined $t;
$t =~ s/\r\n?/\n/g;
my $K = qr/(?:close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)/i;
my $R = qr/(?:[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)?#[0-9]+/;
my $C = qr/(?<![A-Za-z0-9_])($K):?\s+($R)(?![A-Za-z0-9_])/;
sub plain {
    my $s = shift;
    return 0 unless $s =~ $C;
    $s =~ s/^\s*(?:[-*+]|\d+[.)])\s+//;
    $s =~ s/$C//g;
    $s =~ s/\band\b//gi;
    return $s !~ /[A-Za-z0-9]/;
}
for my $para (split /\n[ \t]*\n/, $t) {
    my @units; my $cur; my $split_next = 1;
    for my $line (split /\n/, $para) {
        my $block = $line =~ /^\s*(?:[-*+]\s|\d+[.)]\s|#{1,6}\s|>)/;
        if (!defined $cur || $split_next || $block) {
            push @units, $cur if defined $cur;
            $cur = $line;
        } else {
            $cur .= " $line";
        }
        $split_next = ($line =~ /[.!?;][)"*_`\x27]*\s*$/ || plain($line)) ? 1 : 0;
    }
    push @units, $cur if defined $cur;
    for my $u (@units) {
        for my $sentence (split /(?<=[.!?;])\s+/, $u) {
            next unless $sentence =~ $C;
            my $verdict = plain($sentence) ? "ok" : "refused";
            while ($sentence =~ /$C/g) { print "$verdict\t$1 $2\n"; }
        }
    }
}
'

# sentence_refusals <where> <verdicts>: print a refusal for every refused line,
# naming the reference and where it is, never the sentence around it (L222).
sentence_refusals() {
    local where="$1" verdicts="$2" verdict ref number
    while IFS=$'\t' read -r verdict ref; do
        [ "$verdict" = "refused" ] || continue
        number="${ref##* }"
        echo "  REFUSED  ${ref} in ${where}: GitHub closes that issue on merge whatever the rest of the sentence says, a \"not\" included (L1018). To close it, give it a sentence of its own: Closes ${number}. To leave it open, write: Part of ${number}"
    done <<< "$verdicts"
}

if ! BODY_VERDICTS="$(perl -e "$SENTENCE_RULE" < "$BODY_FILE")"; then
    echo "CANNOT MEASURE: perl could not read $BODY_FILE, so nothing was checked."
    exit 2
fi
BODY_READ_COUNT="$(printf '%s' "$BODY_VERDICTS" | grep -c . || true)"
sentence_refused="$(printf '%s' "$BODY_VERDICTS" | grep -c '^refused' || true)"
sentence_refusals "the description" "$BODY_VERDICTS"

# THE COMMIT MESSAGES, read only when the pull request is named.
COMMITS_READ=""
COMMIT_REF_COUNT=0
commit_refused=0
if [ -n "$PR_NUMBER" ]; then
    if ! EXPECTED="$("$GH" api "repos/${REPO}/pulls/${PR_NUMBER}" --jq .commits 2>&1)" \
        || ! grep -qE '^[0-9]+$' <<< "$EXPECTED"; then
        echo "CANNOT MEASURE: GitHub did not say how many commits pull request ${PR_NUMBER} has:"
        echo "    $(printf '%s' "$EXPECTED" | head -1)"
        echo "    Its commit messages were not read, and that is not a pass (L98)."
        exit 2
    fi
    if ! COMMITS="$("$GH" api --paginate "repos/${REPO}/pulls/${PR_NUMBER}/commits?per_page=100" \
        --jq '.[] | .sha[0:7] + " " + (.commit.message | @base64)' 2>&1)"; then
        echo "CANNOT MEASURE: GitHub did not list the commits of pull request ${PR_NUMBER}:"
        echo "    $(printf '%s' "$COMMITS" | head -1)"
        echo "    Its commit messages were not read, and that is not a pass (L98)."
        exit 2
    fi
    COMMITS_READ="$(printf '%s' "$COMMITS" | grep -c . || true)"
    if [ "$COMMITS_READ" != "$EXPECTED" ] || [ "$COMMITS_READ" -eq 0 ]; then
        echo "CANNOT MEASURE: read ${COMMITS_READ} commit message(s), but pull request ${PR_NUMBER}"
        echo "    has ${EXPECTED} commit(s). A partial read is not a pass (L288). GitHub lists"
        echo "    at most 250 commits of a pull request."
        exit 2
    fi
    while read -r sha encoded; do
        [ -n "$sha" ] || continue
        if ! verdicts="$(printf '%s' "$encoded" \
            | perl -MMIME::Base64 -e 'local $/; print decode_base64(<STDIN>)' \
            | perl -e "$SENTENCE_RULE")"; then
            echo "CANNOT MEASURE: commit ${sha}'s message could not be decoded and read."
            exit 2
        fi
        [ -n "$verdicts" ] || continue
        COMMIT_REF_COUNT=$((COMMIT_REF_COUNT + $(printf '%s\n' "$verdicts" | grep -c .)))
        commit_refused=$((commit_refused + $(printf '%s\n' "$verdicts" | grep -c '^refused' || true)))
        sentence_refusals "commit ${sha}" "$verdicts"
    done <<< "$COMMITS"
fi

REFS="$(printf '%s\n' "$READABLE" | grep -oiE "(^|[^A-Za-z0-9_])${KEYWORD}:?[[:space:]]+${REFERENCE}" \
    | sed -E 's/^[^A-Za-z]+//')"
# The count is every reference GitHub reads, from the sentence rule, plus every
# bare short name a keyword precedes, which GitHub reads none of but this check
# does. A negated short name is neither, which is what ovation#486 asked for.
SHORT_COUNT="$(printf '%s\n' "$REFS" | sed -E 's/^[A-Za-z]+:?[[:space:]]+//' | grep -cE '^[A-Za-z0-9_.-]+#[0-9]+$' || true)"
REF_COUNT=$((BODY_READ_COUNT + SHORT_COUNT))

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
if [ -n "$COMMITS_READ" ]; then
    echo "read ${COMMIT_REF_COUNT} closing reference(s) GitHub reads across ${COMMITS_READ} commit message(s)"
else
    echo "commit messages not read: no pull request number was given, so only the description was checked"
fi
status=0
if [ "$sentence_refused" -gt 0 ]; then
    echo "REFUSED: ${sentence_refused} closing reference(s) in the description sit in a sentence"
    echo "    saying something else, and GitHub closes them on merge whatever it says."
    echo "    Edit the description; this check runs again when it is edited."
    status=1
fi
if [ "$commit_refused" -gt 0 ]; then
    echo "REFUSED: ${commit_refused} closing reference(s) in commit messages sit in a sentence saying"
    echo "    something else. The squash merge copies every commit message onto main, where"
    echo "    GitHub closes them, so reword those commits (git commit --amend for the newest,"
    echo "    git rebase -i for an older one) and push again."
    status=1
fi
if [ "$refused" -gt 0 ]; then
    echo "REFUSED: ${refused} closing reference(s) name the issue as ovation#N, which"
    echo "    GitHub does not read, so the issue would stay open after the merge with"
    echo "    nothing saying so (ovation#261). Edit the description; this check runs"
    echo "    again when it is edited."
    status=1
fi
[ "$status" -eq 0 ] || exit 1
if [ -n "$COMMITS_READ" ]; then
    echo "OK: every closing reference in the description and the commit messages is one GitHub reads, in a sentence of its own."
else
    echo "OK: every closing reference in the description is one GitHub reads, in a sentence of its own."
fi
exit 0
