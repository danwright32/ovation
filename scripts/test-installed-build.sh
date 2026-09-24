#!/bin/bash
# Whether the installed Ovation is behind main, read from the record the installer writes.
#
# ovation#389. build-install.sh writes installed-build.json and nothing read it, so
# on 2026-09-17 the installed app was four commits and four days behind main and
# nothing said so; it surfaced only because a Settings tab Dan wanted was not
# there. Stored data needs a reader (L46, L3). The reader is the post-merge step
# in this repository's CLAUDE.md, which runs this after every merge.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "installed build tests" 11

TARGET="scripts/check-installed-build.sh"
require_target "$TARGET"
harness_temp_dir WORK
ROOT="$PWD"

# A throwaway repository with three commits on main, so "behind" has a count.
REPO="$WORK/repo"
mkdir -p "$REPO"
( cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t \
  && for n in one two three; do echo "$n" > f; git add f; git commit -qm "$n"; done ) >/dev/null 2>&1
FIRST="$(git -C "$REPO" rev-list --max-parents=0 HEAD)"
HEAD_NOW="$(git -C "$REPO" rev-parse HEAD)"
record() { printf '{"version":1,"commit":"%s","commitDate":"2026-09-20T21:50:50-04:00","installedAt":"2026-09-21T02:04:22Z"}\n' "$1" > "$WORK/installed-build.json"; }
run_check() { ( cd "$REPO" && OVATION_INSTALLED_RECORD="$WORK/installed-build.json" bash "$ROOT/$TARGET" 2>&1 ); }
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# 1. CURRENT: the installed commit IS main. The healthy state is not reported as a
#    problem, and it still says what it measured (L98).
record "$HEAD_NOW"
OUT="$(run_check)"; ST=$?
check "an install built from main's tip is current" "$ST" "0"
check "and it says so, naming the commit" "$(says "$OUT" "${HEAD_NOW:0:8}")" "yes"

# 2. BEHIND: the measured case, with the count and the remedy.
record "$FIRST"
OUT="$(run_check)"; ST=$?
check "an install two commits behind main is reported" "$ST" "1"
check "and it says how far behind" "$(says "$OUT" "2 commit(s) behind")" "yes"
check "and it names the command that fixes it" "$(says "$OUT" "bash scripts/build-install.sh")" "yes"

# 3. NO RECORD is its own outcome: never installed, or installed by hand.
rm -f "$WORK/installed-build.json"
OUT="$(run_check)"; ST=$?
check "no record at all cannot be measured" "$ST" "2"
check "and it says there is no record, rather than calling the install current" \
    "$(says "$OUT" "no install record")" "yes"

# 4. A COMMIT MAIN DOES NOT CONTAIN: built from a branch that never merged, or a
#    history that moved. Not "current", and not a count of nothing.
( cd "$REPO" && git checkout -qb side && echo side > g && git add g && git commit -qm side \
  && git checkout -q main ) >/dev/null 2>&1
record "$(git -C "$REPO" rev-parse side)"
OUT="$(run_check)"; ST=$?
check "an install from a commit main does not contain is reported" "$ST" "1"
check "and it says the install is not on main" "$(says "$OUT" "is not on main")" "yes"

# 5. A RECORD THAT CANNOT BE READ is not a current install either.
printf 'not json\n' > "$WORK/installed-build.json"
OUT="$(run_check)"; ST=$?
check "a record with no readable commit cannot be measured" "$ST" "2"
check "and it says the record could not be read" "$(says "$OUT" "could not be read")" "yes"

harness_end
