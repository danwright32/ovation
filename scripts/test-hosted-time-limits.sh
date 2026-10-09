#!/bin/bash
# Whether the hosted time limit check can tell a suite with a limit from one without.
#
# ovation#652. Every case drives the check over a STAGED tree rather than this
# repository, because a guard verified only against the current tree passes for
# as long as that tree happens to be clean and says nothing about what it would
# catch (L1, L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "hosted time limit tests" 33

TARGET="scripts/check-hosted-time-limits.sh"
require_target "$TARGET"
harness_temp_dir WORK

LIMITED='import Testing
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LimitedTests {
    @Test("a row answers a click") func answers() async throws {
        if true { #expect(1 == 1) }
    }
}'

# A STAGED TREE SHAPED LIKE THE REAL ONE: the hosted target's folder holding one
# suite that carries a limit, plus whatever a case adds.
stage() {
    local root="$WORK/$1"
    rm -rf "$root"
    mkdir -p "$root/OvationHostedTests"
    printf '%s\n' "$LIMITED" > "$root/OvationHostedTests/LimitedTests.swift"
    printf '%s' "$root"
}

run_check() { OVATION_REPO_ROOT="$1" "./$TARGET" 2>&1; }
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }
add() { printf '%s\n' "$3" > "$1/OvationHostedTests/$2"; }

# ---------------------------------------------------------------------------
# 1. THE TREE AS IT SHOULD BE: every suite carries a limit, in each spelling a
#    suite trait can be written.
ROOT="$(stage clean)"
add "$ROOT" "SpelledTests.swift" 'import Testing
@Suite(.timeLimit(.minutes(1))) @MainActor struct OneLineTests {
    @Test func one() {}
}
@Suite(
    .serialized,
    .timeLimit(.minutes(1))
)
final class WrappedTests {
    @Test("braces { in a name } do not end the suite") func two() {}
    @Test func three() {}
}
enum Helper { static func help() {} }'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a tree whose every suite carries a limit passes" "$STATUS" "0"
check "and it says how many suites it judged, so none cannot read as all" "$(says "$OUT" "3 hosted suites")" "yes"
check "and how many tests they hold" "$(says "$OUT" "4 tests")" "yes"

# ---------------------------------------------------------------------------
# 2. A SUITE WITH NO LIMIT, which is the whole point: a hang there holds the job
#    silent until its cutoff.
ROOT="$(stage bare)"
add "$ROOT" "BareTests.swift" 'import Testing
@MainActor
struct BareTests {
    @Test func hangs() async {}
}'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a suite with no limit is refused" "$STATUS" "1"
check "and the refusal names the file and the line the suite is declared on" "$(says "$OUT" "OvationHostedTests/BareTests.swift:3 BareTests")" "yes"
check "and what to add" "$(says "$OUT" "@Suite(.timeLimit(.minutes(1)))")" "yes"
check "and the suite that has one is not named" "$(says "$OUT" "LimitedTests")" "no"

# 3. TWO SUITES IN ONE FILE: the first one's limit is not the second's.
ROOT="$(stage second)"
add "$ROOT" "PairTests.swift" 'import Testing
@Suite(.timeLimit(.minutes(1)))
struct FirstTests { @Test func a() {} }

struct SecondTests { @Test func b() {} }'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a suite below a limited one is refused on its own" "$STATUS" "1"
check "and it is the second that is named" "$(says "$OUT" "PairTests.swift:5 SecondTests")" "yes"
check "and not the first" "$(says "$OUT" "FirstTests")" "no"

# 4. A LIMIT IN A COMMENT OR A STRING IS PROSE, not a trait, and a test in a
#    comment is not a test.
ROOT="$(stage prose)"
add "$ROOT" "ProseTests.swift" 'import Testing
// @Suite(.timeLimit(.minutes(1)))
struct ProseTests {
    let note = "@Suite(.timeLimit(.minutes(1)))"
    @Test func c() {}
}
/* @Test func ghost() {} */
struct Quiet { let words = "@Test" }'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a limit written in a comment does not count" "$STATUS" "1"
check "and the suite is named" "$(says "$OUT" "ProseTests.swift:3 ProseTests")" "yes"
check "and a type naming @Test only in a comment or string is not a suite" "$(says "$OUT" "Quiet")" "no"

# ---------------------------------------------------------------------------
# 5. A LIMIT ON EVERY TEST is the same protection, and one test without it is not.
ROOT="$(stage pertest)"
add "$ROOT" "EachTests.swift" 'import Testing
struct EachTests {
    @Test("first", .timeLimit(.minutes(1))) func one() {}
    @Test(.timeLimit(.minutes(1))) func two() {}
}'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a suite whose every test carries a limit passes" "$STATUS" "0"

add "$ROOT" "EachTests.swift" 'import Testing
struct EachTests {
    @Test("first", .timeLimit(.minutes(1))) func one() {}
    @Test("second")
    func two() {}
}'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "one test without a limit, in a suite without one, is refused" "$STATUS" "1"
check "and the suite is named with the line of the one test it leaves bare" "$(says "$OUT" "EachTests.swift:2 EachTests: no limit, on the test at line 4")" "yes"

# ---------------------------------------------------------------------------
# 6. NESTED SUITES inherit their parent's traits, so a limit on the outer one
#    covers the inner one, and a limit on neither covers nothing.
ROOT="$(stage nested)"
add "$ROOT" "OuterTests.swift" 'import Testing
@Suite(.timeLimit(.minutes(1)))
struct OuterTests {
    struct InnerTests { @Test func d() {} }
}'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a nested suite inside a limited one passes" "$STATUS" "0"

add "$ROOT" "OuterTests.swift" 'import Testing
struct OuterTests {
    final class Box { var it = 0 }
    struct InnerTests { @Test func d() {} }
}'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a nested suite with no limit above it is refused" "$STATUS" "1"
check "and the innermost suite is the one named" "$(says "$OUT" "OuterTests.swift:4 InnerTests")" "yes"

# 7. AN EXTENSION'S TESTS belong to the type it extends, so they carry that
#    type's limit or none.
ROOT="$(stage extension)"
add "$ROOT" "MoreTests.swift" 'import Testing
extension LimitedTests {
    @Test func more() {}
}'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "an extension of a limited suite passes" "$STATUS" "0"

add "$ROOT" "MoreTests.swift" 'import Testing
struct PlainTests {}
extension PlainTests {
    @Test func more() {}
}'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "an extension of a suite with no limit is refused" "$STATUS" "1"
check "and it is named at the extension" "$(says "$OUT" "MoreTests.swift:3 PlainTests")" "yes"

# 8. A TEST AT FILE SCOPE has no suite to inherit from.
ROOT="$(stage free)"
add "$ROOT" "FreeTests.swift" 'import Testing

@Test func loose() async {}'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a free test function with no limit is refused" "$STATUS" "1"
check "and it is named at its line" "$(says "$OUT" "FreeTests.swift:3")" "yes"

# ---------------------------------------------------------------------------
# 9. A LIMIT TOO LONG TO FIRE BEFORE ANYONE GIVES UP is not a limit, and one the
#    check cannot read cannot be judged.
ROOT="$(stage long)"
add "$ROOT" "LongTests.swift" 'import Testing
@Suite(.timeLimit(.minutes(30)))
struct LongTests { @Test func e() {} }'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a limit above the ceiling is refused" "$STATUS" "1"
check "and the refusal names the suite and the limit it carries" "$(says "$OUT" "LongTests.swift:3 LongTests: 30 minutes")" "yes"

ROOT="$(stage unread)"
add "$ROOT" "VarTests.swift" 'import Testing
let budget = TimeLimitTrait.Duration.minutes(1)
@Suite(.timeLimit(budget))
struct VarTests { @Test func f() {} }'
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a limit the check cannot read is refused" "$STATUS" "1"
check "and it says the limit could not be read" "$(says "$OUT" "VarTests.swift:4 VarTests: a limit this check cannot read")" "yes"

# ---------------------------------------------------------------------------
# 10. A RUN THAT JUDGED NOTHING IS REFUSED, never reported as every suite having
#     a limit (L98).
ROOT="$WORK/empty"
rm -rf "$ROOT"; mkdir -p "$ROOT/OvationHostedTests"
printf 'enum Helper {}\n' > "$ROOT/OvationHostedTests/Helper.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a hosted folder holding no tests is refused" "$STATUS" "1"
check "and it says it is checking nothing" "$(says "$OUT" "checking nothing")" "yes"

ROOT="$WORK/missing"
rm -rf "$ROOT"; mkdir -p "$ROOT"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a tree with no hosted folder is refused" "$STATUS" "1"
check "and it names the folder it looked for" "$(says "$OUT" "OvationHostedTests")" "yes"

# ---------------------------------------------------------------------------
# 11. AND THE REAL TREE, so the limit added to every suite is the state this
#     check passes, not only a staged one.
OUT="$(./$TARGET 2>&1)"
STATUS=$?
check "this repository's hosted suites all carry a limit" "$STATUS" "0"

harness_end
