#!/bin/bash
# A pull request that conflicts with main is said to, rather than waiting on checks.
#
# ovation#350. GitHub schedules no pull_request run for a pull request whose merge
# commit it cannot compute, so a CONFLICTING one shows "no checks reported", which
# reads exactly like CI never starting. About forty minutes went into Actions
# incidents and credentials before `mergeable` was read (L476).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "pull request mergeable tests" 12

TARGET="scripts/check-pr-mergeable.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A STAND IN FOR gh, answering from files, so no case reaches GitHub (L2). Each
# answer file holds one answer per line, consumed in order, so "UNKNOWN then
# CONFLICTING" is how GitHub really behaves while it computes the merge.
FAKE="$WORK/gh"; LOG="$WORK/gh-calls"
cat > "$FAKE" <<'SH'
#!/bin/bash
echo "$*" >> "$FAKE_LOG"
case "$1 $2" in
  "pr view")
    n="$3"; f="$FAKE_DIR/mergeable-$n"
    [ -s "$f" ] || { echo "no such pull request" >&2; exit 1; }
    head -1 "$f"; sed -i.bak 1d "$f" 2>/dev/null; [ -s "$f" ] || head -1 "$f.bak" > "$f"
    ;;
  "pr list") cat "$FAKE_DIR/open" ;;
  "pr comment") echo commented ;;
  "api repos/"*) cat "$FAKE_DIR/comments-$(printf '%s' "$2" | sed -E 's|.*/issues/([0-9]+)/comments.*|\1|')" 2>/dev/null ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$FAKE"
run_check() { FAKE_DIR="$WORK" FAKE_LOG="$LOG" OVATION_GH="$FAKE" OVATION_SLEEP=true \
    OVATION_REPO=danwright32/ovation bash "$TARGET" "$@" 2>&1; }
answers() { printf '%s\n' "${@:2}" > "$WORK/mergeable-$1"; : > "$WORK/comments-$1"; }
says() { if grep -qiF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }
comments_posted() { grep -c '^pr comment' "$LOG" 2>/dev/null || true; }

# 1. A MERGEABLE pull request passes, and nothing is posted.
: > "$LOG"; answers 10 MERGEABLE
OUT="$(run_check --comment 10)"; ST=$?
check "a mergeable pull request passes" "$ST" "0"
check "and nothing is posted on it" "$(comments_posted)" "0"

# 2. CONFLICTING: refused, and ONE comment naming the remedy.
: > "$LOG"; answers 11 CONFLICTING
OUT="$(run_check --comment 11)"; ST=$?
check "a conflicting pull request is reported" "$ST" "1"
check "and it says no checks will run until main is merged in" "$(says "$OUT" "merge main")" "yes"
check "and one comment is posted" "$(comments_posted)" "1"

# 3. ALREADY SAID: a second run does not comment again (L393).
: > "$LOG"; answers 11 CONFLICTING
printf '%s\n' "<!-- ovation-pr-mergeable -->" > "$WORK/comments-11"
OUT="$(run_check --comment 11)"; ST=$?
check "a conflict already reported is not commented on again" "$(comments_posted)" "0"
check "and is still reported" "$ST" "1"

# 4. GitHub COMPUTING: UNKNOWN is polled until it answers, not taken as mergeable.
: > "$LOG"; answers 12 UNKNOWN UNKNOWN CONFLICTING
OUT="$(run_check 12)"; ST=$?
check "an answer that arrives after UNKNOWN is waited for" "$ST" "1"

# 5. UNKNOWN THROUGHOUT is its own outcome, never a pass (L98).
: > "$LOG"; answers 13 UNKNOWN
OUT="$(run_check 13)"; ST=$?
check "a pull request GitHub never decides about cannot be measured" "$ST" "2"
check "and it says so rather than calling it mergeable" "$(says "$OUT" "could not tell")" "yes"

# 6. WITH NO NUMBER, every open pull request is asked about, which is the run
#    on a push to main: main moving is what makes an open one conflict.
: > "$LOG"; answers 20 MERGEABLE; answers 21 CONFLICTING; printf '20\n21\n' > "$WORK/open"
OUT="$(run_check)"; ST=$?
check "with no number every open pull request is checked, and a conflict among them is reported" "$ST" "1"

# 7. gh ITSELF FAILING is could not measure, not a conflict and not a pass.
: > "$LOG"; rm -f "$WORK/mergeable-30"
OUT="$(run_check 30)"; ST=$?
check "a pull request that cannot be read cannot be measured" "$ST" "2"

harness_end
