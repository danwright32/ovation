#!/bin/bash
# Custody data must never enter git history, and the check that says so must be
# able to fail.
#
# ovation#4. The repository is PUBLIC for the whole build (Dan's decision,
# 2026-09-05, on Actions minutes), so this is the only thing between a real
# receipt or a real QuickBooks export and a public URL.
#
# This is a DIFFERENT QUESTION from the identity guard in ovation#5. That one
# searches file CONTENTS for names. This one asks whether a custody file ever
# entered history at all, which .gitignore alone cannot answer: an entry added
# after a file was committed hides it from `git status` while leaving it in every
# clone for ever.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "custody staging tests" 14

TARGET="scripts/check-custody-not-staged.sh"
require_target "$TARGET"
harness_temp_dir WORK

# Throwaway repos, so no case can touch Ovation's real history.
new_repo() {
    local r="$WORK/$1"; rm -rf "$r"; mkdir -p "$r"
    ( cd "$r" && git init -q -b main && git config user.email t@t && git config user.name t \
      && echo x > README.md && git add README.md && git commit -qm init ) >/dev/null 2>&1
    printf '%s\n' "$r"
}
run_check() { ( cd "$1" && OVATION_CUSTODY_PATHS="${2-.receipt-samples .quickbooks-samples}" \
    bash "$PWD_ROOT/$TARGET" 2>&1 ); }
# A path or a word appears on several lines of a refusal, so assert PRESENCE.
says() { if printf '%s' "$1" | grep -qi "$2"; then echo yes; else echo no; fi; }
PWD_ROOT="$PWD"

# 1. A clean repository with no custody data at all: passes.
R1="$(new_repo clean)"
OUT1="$(run_check "$R1")"; ST1=$?
check "a repository that never held custody data passes" "$ST1" "0"

# 2. Custody files present on disk but UNTRACKED and ignored: still passes. This
#    is the normal working state, and a check that fired here would fire every
#    day and be turned off (L324, L36).
R2="$(new_repo working)"
mkdir -p "$R2/.receipt-samples"
printf 'a real receipt\n' > "$R2/.receipt-samples/receipt.pdf"
printf '.receipt-samples\n' > "$R2/.gitignore"
( cd "$R2" && git add .gitignore && git commit -qm ignore ) >/dev/null 2>&1
OUT2="$(run_check "$R2")"; ST2=$?
check "custody data present but ignored is the normal state, and passes" "$ST2" "0"
check "and it says what it actually examined" \
    "$(says "$OUT2" "receipt-samples")" "yes"

# 3. STAGED BUT NOT COMMITTED: caught. This is the moment it is still fixable.
R3="$(new_repo staged)"
mkdir -p "$R3/.quickbooks-samples"
printf 'client,amount\n' > "$R3/.quickbooks-samples/export.csv"
( cd "$R3" && git add -f .quickbooks-samples/export.csv ) >/dev/null 2>&1
OUT3="$(run_check "$R3")"; ST3=$?
check "a custody file staged in the index is caught" \
    "$([ "$ST3" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names the path, so it can be unstaged" \
    "$(says "$OUT3" "export.csv")" "yes"
check "and it says the file is staged rather than in history" \
    "$(says "$OUT3" "staged")" "yes"

# 4. COMMITTED IN HISTORY: caught even after the file is deleted and gitignored.
#    This is the case .gitignore cannot see and the one that actually matters,
#    because deleting the file later does not remove it from any clone.
R4="$(new_repo history)"
mkdir -p "$R4/.receipt-samples"
printf 'a real receipt\n' > "$R4/.receipt-samples/old.pdf"
( cd "$R4" && git add -f .receipt-samples/old.pdf && git commit -qm oops \
  && git rm -q .receipt-samples/old.pdf && printf '.receipt-samples\n' > .gitignore \
  && git add .gitignore && git commit -qm "hide it" ) >/dev/null 2>&1
OUT4="$(run_check "$R4")"; ST4=$?
check "a custody file that was committed and then deleted is STILL caught" \
    "$([ "$ST4" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names the path" "$(says "$OUT4" "old.pdf")" "yes"
check "and it says the file is in history, not merely staged" \
    "$(says "$OUT4" "IN HISTORY")" "yes"
check "and git status alone would have said nothing" \
    "$( cd "$R4" && git status --porcelain | wc -l | tr -d ' ' )" "0"

# 5. A file on a branch that was never merged is still in history and still
#    reachable by anyone who clones. --all, not HEAD.
R5="$(new_repo branch)"
( cd "$R5" && git checkout -qb side && mkdir -p .receipt-samples \
  && printf 'r\n' > .receipt-samples/side.pdf \
  && git add -f .receipt-samples/side.pdf && git commit -qm side \
  && git checkout -q main ) >/dev/null 2>&1
OUT5="$(run_check "$R5")"; ST5=$?
check "a custody file on an unmerged branch is caught too" \
    "$([ "$ST5" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# 6. NOTHING TO CHECK IS NOT A PASS. Given a path list that is empty, it must
#    refuse naming the emptiness rather than reporting clean (L98). This is the
#    same trap as the identity guard's empty needle set.
OUT6="$(run_check "$R1" "")"; ST6=$?
check "an empty path list is refused, not reported clean" \
    "$([ "$ST6" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names the emptiness" \
    "$(says "$OUT6" "no custody paths")" "yes"

# 7. Not a git repository at all: CANNOT MEASURE, never a pass.
NOTREPO="$WORK/notarepo"; mkdir -p "$NOTREPO"
OUT7="$(run_check "$NOTREPO")"; ST7=$?
check "a directory that is not a git repository does not pass" \
    "$([ "$ST7" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

harness_end
