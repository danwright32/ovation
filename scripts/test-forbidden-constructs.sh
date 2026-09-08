#!/bin/bash
# The suite for scripts/check-forbidden-constructs.sh.
#
# ovation#53, plan 1.4. Money is Int64 minor units and the type carries no
# floating point constructor, which makes the mistake impossible to write INSIDE
# the money type. It does nothing about a `Double` declared anywhere else in the
# app, and a rule that lives only in a header is enforced by nothing (L27, L407).
#
# Every case runs against a THROWAWAY scan root through the script's own seam.
# The real default root is exercised once, deliberately, because a seam that
# hides the real path from every test leaves the real path untested (L246).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"

TARGET="scripts/check-forbidden-constructs.sh"

# The per type cases are DERIVED from the script's own list, so a type added
# there arrives with a case rather than being forbidden by a check nothing
# exercises (L41, L217). The declared total is derived from the same count, so
# the two numbers cannot drift (L70).
FORBIDDEN="$([ -x "./$TARGET" ] && "./$TARGET" --list 2>/dev/null)"
FORBIDDEN_COUNT="$(printf '%s\n' "$FORBIDDEN" | grep -c .)"

harness_begin "forbidden construct tests" $((22 + FORBIDDEN_COUNT))
require_target "$TARGET"
harness_temp_dir WORK

run_on() {
    OVATION_CONSTRUCT_SCAN_ROOT="$1" OVATION_CONSTRUCT_ALLOWLIST="${2-}" "./$TARGET" 2>&1
}
status_on() {
    OVATION_CONSTRUCT_SCAN_ROOT="$1" OVATION_CONSTRUCT_ALLOWLIST="${2-}" "./$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

# ---------------------------------------------------------------------------
# A clean tree.
# ---------------------------------------------------------------------------
CLEAN="$WORK/clean"
mkdir -p "$CLEAN/Domain"
cat > "$CLEAN/Domain/Money.swift" <<'SWIFT'
struct Money {
    let cents: Int64
}
SWIFT
cat > "$CLEAN/Domain/Hours.swift" <<'SWIFT'
struct Hours {
    let tenths: Int64
}
SWIFT

# THE RULES THEMSELVES ARE ASSERTED, not only the cases derived from them.
# Deriving both the loop and the declared total from the script's own list means
# DELETING a rule shrinks the coverage and the expectation together, and the run
# stays green while the rule is gone (L70). These two are the floor.
check "the money rule is still declared" \
    "$(printf '%s\n' "$FORBIDDEN" | grep -c '^Double$')" "1"
check "the calendar rule is still declared" \
    "$(printf '%s\n' "$FORBIDDEN" | grep -c '^Calendar\.current$')" "1"
check "the cooperative pool rule is still declared" \
    "$(printf '%s\n' "$FORBIDDEN" | grep -c '^Task\.detached$')" "1"

check "a tree with no floating point types passes" "$(status_on "$CLEAN")" "0"
check "and it says how many files it actually looked at" \
    "$(run_on "$CLEAN" | grep -c 'scanned 2')" "1"

# ---------------------------------------------------------------------------
# Each forbidden type, one case each, because a check written for one of them
# is satisfied by finding any of them.
# ---------------------------------------------------------------------------
for TYPE in $FORBIDDEN; do
    BAD="$WORK/bad-$TYPE"
    mkdir -p "$BAD"
    printf 'struct Charge {\n    let amount: %s\n}\n' "$TYPE" > "$BAD/Charge.swift"
    check "a $TYPE in the sources is refused" "$(status_on "$BAD")" "1"
done

BAD="$WORK/bad-Double"
check "the refusal names the file and the line" \
    "$(run_on "$BAD" | grep -c 'Charge.swift:2')" "1"
check "the refusal names the type it found" \
    "$(run_on "$BAD" | grep -c 'Double')" "1"
check "the refusal names WHICH rule fired, because the two forbid different things" \
    "$(run_on "$BAD" | grep -c '^floating point money: ')" "1"
check "and says nothing about the rule that did not fire" \
    "$(run_on "$BAD" | grep -c '^ambient calendar: ')" "0"
check "the refusal does NOT print the source line, which is how a comment would leak" \
    "$(run_on "$BAD" | grep -c 'struct Charge')" "0"

# ---------------------------------------------------------------------------
# Comments. The scanner has to NAME the types it forbids in order to forbid
# them, and so does every file explaining the rule, so prose is not code (L245).
# It is stripped from INSIDE the line rather than the whole line being judged by
# how it starts, because one line routinely mixes the two (L361).
# ---------------------------------------------------------------------------
COMMENTS="$WORK/comments"
mkdir -p "$COMMENTS"
cat > "$COMMENTS/Notes.swift" <<'SWIFT'
// There is deliberately no Double constructor on Money.
/* Nor any Decimal, for the same reason.
   Nor Float. */
struct Money {
    let cents: Int64 // never a Double
}
SWIFT
check "a mention in a line comment is not a finding" "$(status_on "$COMMENTS")" "0"

TRAILING="$WORK/trailing"
mkdir -p "$TRAILING"
printf 'let amount: Double = 1 // a comment\n' > "$TRAILING/Bad.swift"
check "code before a comment on the same line is still scanned" \
    "$(status_on "$TRAILING")" "1"

IDENT="$WORK/identifiers"
mkdir -p "$IDENT"
printf 'struct DoubleEntryLedger {\n    let myDoubleCheck: Int64\n    let floatingDock: Int64\n}\n' \
    > "$IDENT/Ledger.swift"
check "a longer identifier that merely contains the word is not a finding" \
    "$(status_on "$IDENT")" "0"

# ---------------------------------------------------------------------------
# NOTHING SCANNED IS NOT A PASS (L98).
# ---------------------------------------------------------------------------
EMPTY="$WORK/empty"
mkdir -p "$EMPTY"
check "a root holding no Swift files refuses rather than passing" "$(status_on "$EMPTY")" "2"
check "and says that it scanned nothing" \
    "$(run_on "$EMPTY" | grep -c 'no Swift files')" "1"
check "a root that is not there refuses with its own exit code" \
    "$(status_on "$WORK/not-here")" "2"

# ---------------------------------------------------------------------------
# The allowlist. An entry carrying no written reason is evidence nobody reasoned
# about it (L233), and one naming a file that is gone outlives its reason.
# ---------------------------------------------------------------------------
ALLOWED="$WORK/allowed"
mkdir -p "$ALLOWED"
printf 'let progress: Double = 0\n' > "$ALLOWED/Animation.swift"
printf 'struct Money { let cents: Int64 }\n' > "$ALLOWED/Money.swift"
check "an allowlisted file with a written reason is not reported" \
    "$(status_on "$ALLOWED" "Animation.swift # a SwiftUI animation fraction, never money")" "0"
check "an allowlist entry with no reason is refused" \
    "$(status_on "$ALLOWED" "Animation.swift")" "3"
check "an allowlist entry naming a file that is not there is refused" \
    "$(status_on "$ALLOWED" "Gone.swift # a reason for a file that no longer exists")" "3"
# An allowlist that has grown to cover EVERYTHING has scanned nothing, and that
# is the state in which a scanner reports exactly what a clean tree does (L98).
EVERYTHING="$WORK/everything-allowed"
mkdir -p "$EVERYTHING"
printf 'let progress: Double = 0\n' > "$EVERYTHING/Animation.swift"
check "an allowlist covering every file in the root refuses rather than passing" \
    "$(status_on "$EVERYTHING" "Animation.swift # the only file, and it is exempt")" "2"

check "a refused allowlist says which entry it refused" \
    "$(OVATION_CONSTRUCT_SCAN_ROOT="$ALLOWED" OVATION_CONSTRUCT_ALLOWLIST="Gone.swift # a reason" \
        "./$TARGET" 2>&1 | grep -c 'Gone.swift')" "1"

# ---------------------------------------------------------------------------
# The real root, once, so the seam is not the only thing ever measured (L246).
# ---------------------------------------------------------------------------
check "Ovation's own sources pass, scanned at the real default root" \
    "$("./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "0"

harness_end
