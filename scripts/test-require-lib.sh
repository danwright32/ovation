#!/bin/bash
# A script whose library is missing refuses, and none loads a library another way.
#
# ovation#399. Bash's `.` on a missing file carries on, so check-ci-workflow.sh
# with its libraries absent printed a true summary of nothing and exited 0.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "require lib tests" 7

LIB="scripts/lib/require.sh"
require_target "$LIB"
harness_temp_dir WORK
ROOT="$PWD"

# 1 and 2. The helper itself: a missing library refuses with 2 and names it.
OUT="$( bash -c ". '$ROOT/$LIB'; require_lib '$WORK/nope.sh'; echo CARRIED-ON" 2>&1 )"; ST=$?
check "a missing library refuses with exit 2" "$ST" "2"
check "and nothing after it runs" "$(printf '%s' "$OUT" | grep -c CARRIED-ON)" "0"
check "and it names the missing file" "$(printf '%s' "$OUT" | grep -c "nope.sh is missing")" "1"

# 3. The CONTROL: a present library is loaded and the script carries on.
printf 'lib_says() { echo LOADED; }\n' > "$WORK/present.sh"
OUT="$( bash -c ". '$ROOT/$LIB'; require_lib '$WORK/present.sh'; lib_says" 2>&1 )"; ST=$?
check "a present library loads and the script carries on" "$ST:$OUT" "0:LOADED"

# 4. THE MEASURED CASE, on a copy of this tree with one library removed: the CI
#    workflow check refuses rather than summarising nothing and passing.
COPY="$WORK/tree"; mkdir -p "$COPY"
cp -R scripts .github "$COPY"/
( cd "$COPY" && git init -q -b main ) >/dev/null 2>&1
rm "$COPY/scripts/lib/workflow-text.sh"
( cd "$COPY" && bash scripts/check-ci-workflow.sh ) >/dev/null 2>&1; ST=$?
check "the CI workflow check with a library missing refuses with 2, never 0" "$ST" "2"

# 5. And with require.sh ITSELF missing, the bootstrap line refuses too.
rm "$COPY/scripts/lib/require.sh"
( cd "$COPY" && bash scripts/check-ci-workflow.sh ) >/dev/null 2>&1; ST=$?
check "with the helper itself missing, it still refuses with 2" "$ST" "2"

# 6. THE CLASS, not the instance (L30): no script that is not a test loads a file
#    any way but the bootstrap line or require_lib. Enumerated from the tree, so a
#    script added tomorrow is covered without anybody listing it (L41, L96).
BARE=0
while IFS= read -r f; do
    while IFS= read -r line; do
        case "$line" in
            *'lib/require.sh" 2>/dev/null ||'*) ;;
            *) BARE=$((BARE + 1)); echo "    bare source in ${f#"$ROOT"/}: $line" >&2 ;;
        esac
    done < <(grep -E '^[[:space:]]*(\.|source)[[:space:]]+"' "$f")
done < <(find "$ROOT/scripts" -name '*.sh' ! -name 'test-*' ! -name 'require.sh' -type f; echo "$ROOT/scripts/git-hooks/pre-push")
check "no script that is not a test loads a library except through require_lib" "$BARE" "0"

harness_end
