#!/bin/bash
# The situational checks must have somewhere to be run FROM, and no check script
# may be run by nothing.
#
# ovation#27. scripts/git-hooks/pre-push runs three checks on every push. Two
# more existed and nothing ran them at all, which is worse here than an ordinary
# wiring gap: check-sibling-installs.sh exists BECAUSE a fact about another
# application went stale invisibly, and a re-read that only happens when somebody
# remembers to type it has the same defect the thing it replaced had (L3, L175).
#
# WHY THEY DO NOT SIMPLY JOIN THE PUSH GATE. Neither belongs there.
# check-sibling-installs.sh reads two files outside the repository and runs git
# in a sibling checkout; check-booking-queue.sh reads live data that is
# legitimately empty most of the time. A push gate that goes red because Downbeat
# has not been launched lately is a gate people learn to skip (L378).
#
# THE PARTITION IS THE POINT. The last assertion here is the one that fixes the
# class rather than the instance (L30): every check-*.sh on disk must be run by
# EXACTLY ONE of the push gate or the preconditions entry point. Two hand kept
# lists with nothing watching them is how the first two orphans happened, and
# the next orphan now fails a test instead of sitting unnoticed for a week (L96).
#
# EVERY OUTCOME IS DRIVEN, not merely the one this machine happens to be in. The
# sub-checks are injected, so pass, blocked and cannot-measure are all staged
# rather than waited for (L1, L151). Nothing here runs a real check against real
# data (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "preconditions tests" 29

TARGET="scripts/check-preconditions.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A stand-in check that exits with whatever code it is named for, so every
# combination can be staged without touching a real one.
stub() {
    local path="$1" code="$2" word="$3"
    printf '#!/bin/bash\necho "%s: staged"\nexit %s\n' "$word" "$code" > "$path"
    chmod +x "$path"
}

BIN="$WORK/bin"; mkdir -p "$BIN"
stub "$BIN/pass1" 0 PASS
stub "$BIN/pass2" 0 PASS
stub "$BIN/blocked" 1 BLOCKED
stub "$BIN/unmeasurable" 2 "CANNOT MEASURE"

run_pre() { OVATION_PRECONDITION_CHECKS="$1" "./$TARGET" 2>&1; }
status_of() { run_pre "$1" >/dev/null 2>&1; printf '%s' "$?"; }
says() { if printf '%s' "$1" | grep -qF "$2"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. All clear.
# ---------------------------------------------------------------------------
OUT_OK="$(run_pre "$BIN/pass1 $BIN/pass2")"
check "every check passing is a pass" "$(status_of "$BIN/pass1 $BIN/pass2")" "0"
check "and it names how many it ran, so a run of none cannot read as a run of all" \
    "$(says "$OUT_OK" "2 check")" "yes"
# Dan's decision 2026-09-06: nothing is stored. A recorded pass is the stale fact
# these checks exist to replace, and it invites reading the record instead of
# re-running. The TIME is printed so a transcript still says when it ran.
check "it prints when it ran" \
    "$(printf '%s' "$OUT_OK" | grep -cE '[0-9]{4}-[0-9]{2}-[0-9]{2}')" "1"
check "and it writes no record anywhere" \
    "$(ls -1 "$WORK" | grep -c 'preconditions')" "0"

# ---------------------------------------------------------------------------
# 2. THE OUTCOMES ARE NOT FOLDED TOGETHER. Two independent checks must never
#    share one status field (L53), and BLOCKED and CANNOT MEASURE are different
#    facts needing different actions (L11, L260).
# ---------------------------------------------------------------------------
OUT_MIX="$(run_pre "$BIN/pass1 $BIN/blocked $BIN/unmeasurable")"
check "a run holding all three outcomes reports each one separately" \
    "$(printf '%s' "$OUT_MIX" | grep -cE '^  (PASS|BLOCKED|CANNOT MEASURE)')" "3"
check "and it names the check each outcome belongs to" \
    "$(says "$OUT_MIX" "unmeasurable")" "yes"

check "one blocked check blocks the run" "$(status_of "$BIN/pass1 $BIN/blocked")" "1"
check "one unmeasurable check is NOT reported as blocked" \
    "$(status_of "$BIN/pass1 $BIN/unmeasurable")" "2"
check "and blocked outranks unmeasurable, because it is the one with a real finding" \
    "$(status_of "$BIN/blocked $BIN/unmeasurable")" "1"

# EVERY check runs even after one fails. Stopping at the first would hide the
# rest, and a person running this wants the whole picture in one go, not one
# problem per invocation (L73).
check "a failing check does not stop the ones after it" \
    "$(printf '%s' "$OUT_MIX" | grep -c 'staged')" "3"

# ---------------------------------------------------------------------------
# 3. REFUSALS. A run that checked nothing must never read as a run that passed
#    (L98), and a named check that is not there is its own outcome.
# ---------------------------------------------------------------------------
check "an empty check list is refused, not reported as all clear" \
    "$(status_of "")" "2"
check "and it says so rather than claiming success" \
    "$(says "$(run_pre "")" "nothing")" "yes"
check "a check that is not on disk is refused by name" \
    "$(status_of "$BIN/pass1 $WORK/no-such-check")" "2"
check "and the missing one is named" \
    "$(says "$(run_pre "$BIN/pass1 $WORK/no-such-check")" "no-such-check")" "yes"

# ---------------------------------------------------------------------------
# 4. THE PARTITION, and the INVENTORY it is now derived from (ovation#86).
#
# This assertion used to look only at `check-*.sh`, and four scripts sat outside
# it, each for a real reason that was written nowhere a rule could read. It also
# could not see `check-design-collisions.py`, which is named like a check, is run
# by nothing at all, and is Python. A guard driven by a pattern checks only what
# the pattern happens to match (L96, L247).
#
# So every script under scripts/ now declares its role in
# `lib/script-roles.tsv`, and BOTH completeness rules read that file through
# `lib/script-roles.sh` rather than each parsing it (L370).
# ---------------------------------------------------------------------------
. scripts/lib/script-roles.sh

check "every script on disk is declared, and every declaration names a real script" \
    "$(diff <(scripts_on_disk) <(roles_paths) >/dev/null 2>&1 && echo agree || echo differ)" \
    "agree"

# An entry with no reason is evidence nobody reasoned about it (L233). `suite` is
# the one role that needs none, because a suite is run purely because of what it
# is called, so the role states the whole fact.
check "every entry that needs a reason carries one" \
    "$(roles_entries | awk -F'\t' '$2 != "suite" && ($3 == "" || $3 ~ /^[[:space:]]*$/) { print $1 }' \
        | tr '\n' ' ' | sed 's/ $//')" ""

# THE VOCABULARY IS READ FROM THE FILE THAT DEFINES IT, not repeated here. It was
# a second copy of the list, and a list that must mirror another source is derived
# from it or the two drift, with the copy that fell behind refusing a role the
# header plainly documents (L41). Adding `workflow` for ovation#155 is what made
# that concrete: the header gained it and this line refused it.
roles_defined() {
    sed -n 's/^#   \([a-z][a-z-]\{2,\}\)  *[A-Z].*/\1/p' scripts/lib/script-roles.tsv | sort -u
}
# A DERIVATION THAT MATCHED NOTHING WOULD PASS EVERYTHING, since every role would
# then be undefined and the grep below would have nothing to exclude... in fact it
# would refuse everything, which is the loud direction. This asserts the reading
# worked anyway, because a check whose input is silently empty is a check nobody
# can trust in either direction (L100, L98).
check "the role vocabulary was actually read out of the inventory" \
    "$([ "$(roles_defined | grep -c .)" -ge 6 ] && echo read || echo empty)" "read"
check "every role used is one that file defines" \
    "$(roles_entries | awk -F'\t' '{ print $2 }' | sort -u \
        | grep -vxF -f <(roles_defined) \
        | tr '\n' ' ' | sed 's/ $//')" ""

# THE PARTITION ITSELF, now over the roles rather than over a filename pattern.
# READ FROM THE gate_check CALLS, which are now the one form a check is run in
# (ovation#135). It used to grep the whole file for anything shaped like a check
# script name, which also matched a check merely MENTIONED in a comment: a note
# explaining why something is NOT run by the gate would have counted as it being
# run (L103, L135). The call is the thing that runs it, so the call is what is
# read.
gate_runs() { grep -oE '^gate_check +check-[a-z-]+\.(sh|py)' scripts/git-hooks/pre-push | awk '{print $2}' | sort -u; }
pre_runs() { grep -oE 'check-[a-z-]+\.(sh|py)' "$TARGET" | grep -v 'check-preconditions' | sort -u; }
# One gated script is a BRACKET rather than a question: check-live-data-untouched.sh
# snapshots before a test run and compares after, so scripts/run-tests.sh holds
# both ends and neither entry point above can run it alone. Its reason is in the
# inventory beside every other one rather than in a list here.
bracketed() { printf 'check-live-data-untouched.sh\n'; }
must_be_run() { roles_with gated | grep -v 'check-preconditions' | grep -vxF -f <(bracketed); }

check "no gated script is run by nothing" \
    "$(comm -13 <(cat <(gate_runs) <(pre_runs) | sort -u) <(must_be_run) | tr '\n' ' ' | sed 's/ $//')" ""
check "and none is run by both, which would make its outcome ambiguous" \
    "$(comm -12 <(gate_runs) <(pre_runs) | tr '\n' ' ' | sed 's/ $//')" ""
check "the bracketed one is really run by the test runner" \
    "$(grep -c 'check-live-data-untouched.sh' scripts/run-tests.sh)" "1"
check "and neither entry point names a check that does not exist" \
    "$(comm -23 <(cat <(gate_runs) <(pre_runs) | sort -u) <(must_be_run) \
        | grep -vxF -f <(bracketed) | tr '\n' ' ' | sed 's/ $//')" ""

# WHAT EACH ROLE OBLIGES. Without these the inventory is a list of labels and a
# script could be given whichever role has the fewest consequences.
check "every suite is named so run-tests.sh's glob actually reaches it" \
    "$(roles_with suite | grep -vE '^test-[a-z0-9-]+\.sh$' | tr '\n' ' ' | sed 's/ $//')" ""
# COVERAGE IS ASSERTED AS A SUITE THAT ACTUALLY RUNS THE TOOL, never as a
# filename convention. The first version of this looked for `test-<name>.sh` and
# reported install-git-hooks.sh as uncovered when it is covered in full by
# test-git-hooks.sh: a rule keyed on spelling reports a name it did not like,
# which is not the question anybody wanted answered (L63).
covering_suite() {
    grep -rlF "$(basename "$1")" scripts --include='test-*.sh' 2>/dev/null | head -1
}
check "every tool is actually run by some suite" \
    "$(for t in $(roles_with tool); do
         [ -n "$(covering_suite "$t")" ] || printf '%s ' "$t"
       done | sed 's/ $//')" ""
check "every untested tool NAMES the issue that will give it a sibling" \
    "$(for t in $(roles_with tool-untested); do
         reason_of "$t" | grep -q 'ovation#[0-9]' || printf '%s ' "$t"
       done | sed 's/ $//')" ""
check "every real data tool is run by some suite too" \
    "$(for t in $(roles_with reads-real-data); do
         [ -n "$(covering_suite "$t")" ] || printf '%s ' "$t"
       done | sed 's/ $//')" ""
# A WORKFLOW SCRIPT IS RUN BY NOTHING ON THIS MACHINE, which is what makes both
# halves necessary: the workflow is the only thing that runs it, and a suite is
# the only thing that can judge it before it is pushed (ovation#155).
check "every workflow script is actually named by a workflow file" \
    "$(for w in $(roles_with workflow); do
         grep -rlq "$(basename "$w")" .github/workflows 2>/dev/null || printf '%s ' "$w"
       done | sed 's/ $//')" ""
check "and every workflow script is covered by a suite" \
    "$(for w in $(roles_with workflow); do
         [ -n "$(covering_suite "$w")" ] || printf '%s ' "$w"
       done | sed 's/ $//')" ""

# THE MODULE NAME, NOT THE FILE NAME, for a Python library. A shell library is
# reached by `. lib/thing.sh`, which carries its extension, and a Python one by
# `from thing import x`, which does not. Matching only the file name reported
# lib/design_render.py as sourced by nothing while both of its importers named it
# on their import line, which is a rule blind to the very thing it checks. The
# `.py` is stripped, and nothing under lib/ can match itself here because this
# only ever reads *.sh.
check "and every library really is sourced by something rather than run" \
    "$(for l in $(roles_with library); do
         grep -rlq "$(basename "$l" .py)" scripts --include='*.sh' || printf '%s ' "$l"
       done | sed 's/ $//')" ""

harness_end
