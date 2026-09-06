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
harness_begin "preconditions tests" 17

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
# 4. THE PARTITION. Every check-*.sh is run by exactly one of the two entry
#    points. This is the assertion that stops the next orphan.
# ---------------------------------------------------------------------------
gate_runs() { grep -oE 'check-[a-z-]+\.sh' scripts/git-hooks/pre-push | sort -u; }
pre_runs() { grep -oE 'check-[a-z-]+\.sh' "$TARGET" | grep -v 'check-preconditions' | sort -u; }
on_disk() { (cd scripts && ls -1 check-*.sh | grep -v 'check-preconditions' | sort); }

check "no check script is run by nothing" \
    "$(comm -13 <(cat <(gate_runs) <(pre_runs) | sort -u) <(on_disk) | tr '\n' ' ' | sed 's/ $//')" ""
check "and none is run by both, which would make its outcome ambiguous" \
    "$(comm -12 <(gate_runs) <(pre_runs) | tr '\n' ' ' | sed 's/ $//')" ""
check "and neither entry point names a check that does not exist" \
    "$(comm -23 <(cat <(gate_runs) <(pre_runs) | sort -u) <(on_disk) | tr '\n' ' ' | sed 's/ $//')" ""

harness_end
