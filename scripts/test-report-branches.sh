#!/bin/bash
# Every branch beside the state of its pull request, and nothing deleted.
#
# ovation#359 and ovation#396. This repository squash merges, so no merged branch
# is ever an ancestor of main and every local test of "did it ship" answers no
# (L642); the only truthful answer is the pull request. A listing that says which
# branches are MERGED makes clearing them a decision rather than a guess, and it
# stays one: this deletes nothing.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "branch report tests" 9

TARGET="scripts/report-branches.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A throwaway repository and a bare remote, with three pushed branches.
[ -n "$WORK" ] || exit 1
git init -q --bare "$WORK/remote.git" >/dev/null 2>&1
REPO="$WORK/repo"; mkdir -p "$REPO"
( cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t \
  && git remote add origin "$WORK/remote.git" && echo x > f && git add f && git commit -qm x \
  && git push -q origin main \
  && for b in shipped-one still-open never-had-one; do git branch "$b"; git push -q origin "$b"; done ) >/dev/null 2>&1

# gh answers by branch name from a file per branch, and the absence of one is
# "no pull request" (L2).
cat > "$WORK/gh" <<'SH'
#!/bin/bash
for a in "$@"; do prev="$last"; last="$a"; [ "$prev" = "--head" ] && head="$a"; done
cat "$FAKE/pr-$head" 2>/dev/null
SH
chmod +x "$WORK/gh"
echo MERGED > "$WORK/pr-shipped-one"
echo OPEN > "$WORK/pr-still-open"
run_report() { ( cd "$REPO" && FAKE="$WORK" OVATION_GH="$WORK/gh" bash "$OLDPWD/$TARGET" 2>&1 ); }
line_for() { grep -E "^ *$1 " <<< "$2" | head -1; }

OUT="$(run_report)"; ST=$?
check "the report runs and says what it examined" "$ST" "0"
check "a branch whose pull request merged is listed as MERGED" \
    "$(line_for shipped-one "$OUT" | grep -c MERGED)" "1"
check "an open one as OPEN" "$(line_for still-open "$OUT" | grep -c OPEN)" "1"
check "and one that never had a pull request as none" \
    "$(line_for never-had-one "$OUT" | grep -c 'no pull request')" "1"
check "main is not listed as a leftover" "$(line_for main "$OUT" | grep -c .)" "0"
check "and it says how to clear the merged ones rather than doing it" \
    "$(grep -c 'nothing was deleted' <<< "$OUT")" "1"
check "and it deleted nothing" \
    "$(git --git-dir="$WORK/remote.git" branch --list shipped-one | grep -c shipped-one)" "1"

# ASKED, NOT REMEMBERED: a branch deleted on origin after this checkout fetched
# is shown as gone from origin, because the report asks origin rather than the
# tracking ref the checkout still holds for it.
( cd "$REPO" && git fetch -q origin ) >/dev/null 2>&1
git --git-dir="$WORK/remote.git" branch -D shipped-one >/dev/null 2>&1
OUT="$(run_report)"
check "a branch deleted on origin since the last fetch is shown as not on origin" \
    "$(line_for shipped-one "$OUT" | awk '{print $3}')" "no"
check "and it says the origin column was asked just now" \
    "$(grep -c 'asked just now' <<< "$OUT")" "1"

harness_end
